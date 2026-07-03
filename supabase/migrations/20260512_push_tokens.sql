-- push_tokens: stores APNs/FCM device tokens for delivering push notifications.
-- Used by the `send-game-invite-push` edge function to look up a user's devices.

create table if not exists public.push_tokens (
    user_id    uuid        not null references auth.users(id) on delete cascade,
    token      text        not null,
    platform   text        not null default 'ios' check (platform in ('ios', 'android')),
    updated_at timestamptz not null default now(),
    primary key (user_id, token)
);

create index if not exists push_tokens_user_id_idx on public.push_tokens (user_id);
create index if not exists push_tokens_token_idx   on public.push_tokens (token);

-- Auto-bump updated_at on upsert.
create or replace function public.push_tokens_set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists push_tokens_set_updated_at on public.push_tokens;
create trigger push_tokens_set_updated_at
    before insert or update on public.push_tokens
    for each row execute function public.push_tokens_set_updated_at();

-- Row Level Security: users manage only their own tokens.
-- The edge function uses the service-role key, which bypasses RLS.
alter table public.push_tokens enable row level security;

drop policy if exists "push_tokens_select_own" on public.push_tokens;
create policy "push_tokens_select_own"
    on public.push_tokens
    for select
    using (auth.uid() = user_id);

drop policy if exists "push_tokens_insert_own" on public.push_tokens;
create policy "push_tokens_insert_own"
    on public.push_tokens
    for insert
    with check (auth.uid() = user_id);

drop policy if exists "push_tokens_update_own" on public.push_tokens;
create policy "push_tokens_update_own"
    on public.push_tokens
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

drop policy if exists "push_tokens_delete_own" on public.push_tokens;
create policy "push_tokens_delete_own"
    on public.push_tokens
    for delete
    using (auth.uid() = user_id);
