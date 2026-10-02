-- App Store Guideline 1.2 (Safety — User-Generated Content).
-- The app carries user-generated content (direct messages, display names,
-- avatars), so it must let users report objectionable content and block
-- abusive users. Neither existed before this migration.

-- ---------------------------------------------------------------------------
-- blocked_users — one row per (blocker, blocked) pair.
-- ---------------------------------------------------------------------------
-- User ids are TEXT here to match `friendships` and `messages`, which both
-- store them as text; `player_profiles.user_id` is uuid, so joins against it
-- cast. Keeping the type consistent with the tables we actually filter against
-- avoids a cast on every block lookup in the hot path.
create table if not exists public.blocked_users (
    blocker_id  text        not null,
    blocked_id  text        not null,
    created_at  timestamptz not null default now(),
    primary key (blocker_id, blocked_id),
    constraint blocked_users_no_self_block check (blocker_id <> blocked_id)
);

-- The common queries are "who have I blocked?" (filtering lists on load) and
-- "who has blocked me?" (suppressing outbound contact). The PK already covers
-- blocker_id; index the other direction too.
create index if not exists blocked_users_blocked_id_idx
    on public.blocked_users (blocked_id);

alter table public.blocked_users enable row level security;

-- A block is private to the blocker. Deliberately NOT readable by the blocked
-- user: being told you have been blocked invites retaliation, and Apple only
-- requires that the block take effect, not that it be announced.
drop policy if exists "blocked_users_select_own" on public.blocked_users;
create policy "blocked_users_select_own"
    on public.blocked_users for select
    using (auth.uid()::text = blocker_id);

drop policy if exists "blocked_users_insert_own" on public.blocked_users;
create policy "blocked_users_insert_own"
    on public.blocked_users for insert
    with check (auth.uid()::text = blocker_id);

drop policy if exists "blocked_users_delete_own" on public.blocked_users;
create policy "blocked_users_delete_own"
    on public.blocked_users for delete
    using (auth.uid()::text = blocker_id);

-- ---------------------------------------------------------------------------
-- content_reports — a durable record of what was reported, by whom, and why.
-- ---------------------------------------------------------------------------
create table if not exists public.content_reports (
    id                uuid        primary key default gen_random_uuid(),
    reporter_id       text        not null,
    reported_user_id  text        not null,
    -- 'message' | 'display_name' | 'avatar' | 'other'
    content_type      text        not null,
    -- id of the offending row where one exists (messages.id); null otherwise.
    content_id        text,
    -- VERBATIM COPY of the offending content at report time. This is the whole
    -- point: a reported user can delete their message seconds later, and
    -- without a snapshot the report becomes unreviewable. Apple expects reports
    -- to be actionable, which means the evidence has to survive the content.
    content_snapshot  text,
    reason            text        not null,
    details           text,
    -- 'pending' | 'reviewed' | 'actioned' | 'dismissed'
    status            text        not null default 'pending',
    created_at        timestamptz not null default now(),
    constraint content_reports_no_self_report check (reporter_id <> reported_user_id)
);

-- Triage queue ordering, and "show me everything about this user".
create index if not exists content_reports_status_created_idx
    on public.content_reports (status, created_at desc);
create index if not exists content_reports_reported_user_idx
    on public.content_reports (reported_user_id);

alter table public.content_reports enable row level security;

-- Reporters may file a report and read their own history, so the UI can say
-- "already reported" rather than inviting duplicates.
drop policy if exists "content_reports_insert_own" on public.content_reports;
create policy "content_reports_insert_own"
    on public.content_reports for insert
    with check (auth.uid()::text = reporter_id);

drop policy if exists "content_reports_select_own" on public.content_reports;
create policy "content_reports_select_own"
    on public.content_reports for select
    using (auth.uid()::text = reporter_id);

-- No UPDATE or DELETE policy for users, on purpose: a report is a record, not a
-- document. Triage happens with the service role (Supabase dashboard or an
-- admin tool), which bypasses RLS.

-- ---------------------------------------------------------------------------
-- Message visibility: stop blocked users from reaching each other.
-- ---------------------------------------------------------------------------
-- Client-side filtering alone is not enough — Apple's reviewers test that a
-- blocked user genuinely cannot contact you, and a client filter is bypassed by
-- anything that talks to the API directly. This tightens the INSERT path so the
-- database itself refuses a message in either direction of a block.
--
-- The table predates versioned migrations, so the live policy names are
-- unknown; enumerate and drop the INSERT policies rather than guessing.
do $$
declare
    pol record;
begin
    for pol in
        select policyname
        from pg_policies
        where schemaname = 'public'
          and tablename = 'messages'
          and cmd = 'INSERT'
    loop
        execute format('drop policy %I on public.messages', pol.policyname);
    end loop;
end$$;

create policy "messages_insert_not_blocked"
    on public.messages for insert
    with check (
        auth.uid()::text = sender_id
        and not exists (
            select 1 from public.blocked_users b
            where (b.blocker_id = receiver_id and b.blocked_id = sender_id)
               or (b.blocker_id = sender_id   and b.blocked_id = receiver_id)
        )
    );
