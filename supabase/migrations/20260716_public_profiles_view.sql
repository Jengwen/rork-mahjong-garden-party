-- Close the player-email exposure: stop letting every signed-in user read
-- every column of every player_profiles row.
--
-- player_profiles carries private columns (email, settings_data, unlocked_*)
-- alongside the public display fields that the leaderboard, player search,
-- and friend cards need. Postgres RLS is row-level, not column-level, so any
-- policy that let users read OTHER players' rows for those features
-- necessarily exposed every column — including email — to any client holding
-- the (public, ships-in-the-binary) anon key and a login.
--
-- Fix, in two parts:
--   1) a view exposing ONLY the public columns, readable by any signed-in
--      user — the leaderboard / search / friend-profile reads move here;
--   2) base-table SELECT tightened to own-row-only.
--
-- DEPLOY ORDER: apply this migration BEFORE shipping the client build that
-- reads `public_player_profiles`. Until users update, old clients querying
-- the base table for the leaderboard will see only their own row (degraded
-- but harmless); the email leak closes the moment this runs.

-- SECURITY DEFINER semantics are deliberate here (and are why this works):
-- the view is owned by the migration role, so reads through it are not
-- subject to the caller's base-table RLS — but the view's column list is
-- exactly the public subset, so that is the entire point. Supabase's
-- advisor flags definer views generically; this one is intentional.
create or replace view public.public_player_profiles
with (security_invoker = false) as
select
    user_id,
    display_name,
    avatar_image,
    level,
    total_wins,
    total_games
from public.player_profiles;

-- Signed-in users only; no anonymous scraping of the public fields either.
revoke all on public.public_player_profiles from anon, authenticated;
grant select on public.public_player_profiles to authenticated;

-- Drop every existing SELECT policy on the base table. The table predates
-- versioned migrations, so the live policy names are unknown — enumerate
-- them from pg_policies instead of guessing.
do $$
declare
    pol record;
begin
    for pol in
        select policyname
        from pg_policies
        where schemaname = 'public'
          and tablename = 'player_profiles'
          and cmd = 'SELECT'
    loop
        execute format('drop policy %I on public.player_profiles', pol.policyname);
    end loop;
end$$;

alter table public.player_profiles enable row level security;

-- Own row only. ::text casts on both sides keep this correct whether
-- user_id is uuid or text (the same pattern the charleston_passes /
-- game_actions policies already use).
drop policy if exists "player_profiles_select_own" on public.player_profiles;
create policy "player_profiles_select_own"
    on public.player_profiles
    for select
    using (auth.uid()::text = user_id::text);
