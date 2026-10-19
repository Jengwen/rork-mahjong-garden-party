-- Web app support: shared subscription entitlements + atomic game-result recording.
--
-- 1. user_entitlements
--    One row per (user, source). Written ONLY by edge functions running with the
--    service role (app-store-sync, app-store-notifications, stripe-webhook,
--    stripe-checkout). Clients may read their own rows; there are deliberately no
--    insert/update/delete policies, so a client can never grant itself access.
--
-- 2. record_game_result(...)
--    Increments totals/streak/XP and logs the game in ONE statement-level
--    transaction. Replaces the client read-modify-write so a game finished on the
--    web and one finished on the phone can't overwrite each other's counts.
--    SECURITY INVOKER: runs as the caller, so existing own-row RLS still applies.

create table if not exists public.user_entitlements (
  user_id                  uuid        not null references auth.users(id) on delete cascade,
  source                   text        not null check (source in ('app_store', 'stripe')),
  product_id               text,
  status                   text        not null default 'inactive'
                           check (status in ('active', 'trialing', 'grace_period', 'canceled_pending', 'expired', 'revoked', 'inactive', 'incomplete')),
  expires_at               timestamptz,
  will_renew               boolean,
  -- App Store
  original_transaction_id  text unique,
  environment              text,
  -- Stripe
  stripe_customer_id       text,
  stripe_subscription_id   text unique,
  had_trial                boolean     not null default false,
  updated_at               timestamptz not null default now(),
  primary key (user_id, source)
);

create index if not exists user_entitlements_customer_idx on public.user_entitlements (stripe_customer_id);

alter table public.user_entitlements enable row level security;

drop policy if exists "Users read own entitlements" on public.user_entitlements;
create policy "Users read own entitlements"
  on public.user_entitlements for select
  using (auth.uid() = user_id);

comment on table public.user_entitlements is
  'Subscription access shared by iOS (App Store) and web (Stripe). Service-role writes only.';

create or replace function public.record_game_result(
  p_result    text,
  p_score     integer,
  p_opponents text[],
  p_mode      text default 'Solo Practice'
) returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_won   boolean := p_result = 'Win';
  v_gain  integer := case when p_result = 'Win' then 100 else 25 end;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if p_result not in ('Win', 'Loss', 'Draw') then
    raise exception 'invalid result %', p_result using errcode = '22023';
  end if;

  -- Same rules as iOS AppViewModel.recordGameResult / addXP:
  -- win: +1 win, +1 streak, +100 XP; otherwise streak resets, +25 XP;
  -- at most one level-up per game, threshold level * 500.
  update public.player_profiles p
     set total_games    = p.total_games + 1,
         total_wins     = p.total_wins + case when v_won then 1 else 0 end,
         current_streak = case when v_won then p.current_streak + 1 else 0 end,
         level          = p.level + case when p.xp + v_gain >= p.level * 500 then 1 else 0 end,
         xp             = case when p.xp + v_gain >= p.level * 500
                               then p.xp + v_gain - p.level * 500
                               else p.xp + v_gain end,
         updated_at     = now()
   where p.user_id = v_uid;

  insert into public.game_results (user_id, result, score, opponent_names, game_mode)
  values (v_uid, p_result, greatest(coalesce(p_score, 0), 0), coalesce(p_opponents, '{}'), coalesce(p_mode, 'Solo Practice'));
end;
$$;

revoke all on function public.record_game_result(text, integer, text[], text) from public, anon;
grant execute on function public.record_game_result(text, integer, text[], text) to authenticated;
