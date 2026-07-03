-- game_actions: append-only log of play-phase moves used as a durable
-- "wake-up" signal that survives dropped realtime broadcasts and per-client
-- RLS quirks. Mirrors the charleston_passes pattern that proved freeze-free.
--
-- Each row is one move (discard, draw, call, mahjong, generic state-sync).
-- Clients keep a local `lastAppliedSeq` and, when they receive a postgres
-- insert with `seq > lastAppliedSeq` from another seat, they pull the
-- authoritative `online_games.game_data` and apply it. The row itself is
-- intentionally small — the durable signal is what we need; the full state
-- still lives in `online_games`.
--
-- Cost per move: 1 small INSERT (in addition to the existing UPDATE). The
-- write is fire-and-forget; failures are non-fatal because the existing
-- realtime broadcast remains the fast path. This table is the safety net.

create table if not exists public.game_actions (
    game_id    uuid        not null references public.online_games(id) on delete cascade,
    seq        bigint      not null,
    seat       int         not null check (seat between 0 and 3),
    user_id    uuid        not null references auth.users(id) on delete cascade,
    kind       text        not null,
    payload    jsonb       not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    primary key (game_id, seq)
);

create index if not exists game_actions_game_idx
    on public.game_actions (game_id);
create index if not exists game_actions_game_seq_idx
    on public.game_actions (game_id, seq desc);

-- Per-game monotonic sequence. Assigned server-side via trigger so clients
-- can't race on seq allocation. NULL/zero on insert → next seq for this game.
create or replace function public.game_actions_assign_seq()
returns trigger
language plpgsql
as $$
begin
    if new.seq is null or new.seq = 0 then
        select coalesce(max(seq), 0) + 1
          into new.seq
          from public.game_actions
         where game_id = new.game_id;
    end if;
    return new;
end;
$$;

drop trigger if exists game_actions_assign_seq on public.game_actions;
create trigger game_actions_assign_seq
    before insert on public.game_actions
    for each row execute function public.game_actions_assign_seq();

alter table public.game_actions enable row level security;

-- Any seated participant can read every action for that game.
drop policy if exists "game_actions_select_participant" on public.game_actions;
create policy "game_actions_select_participant"
    on public.game_actions
    for select
    using (
        exists (
            select 1
            from public.game_participants gp
            where gp.game_id::text = game_actions.game_id::text
              and gp.user_id::text = auth.uid()::text
        )
    );

-- A user may only insert actions for their own seat, and only if they are
-- actually seated at that seat in this game.
drop policy if exists "game_actions_insert_own_seat" on public.game_actions;
create policy "game_actions_insert_own_seat"
    on public.game_actions
    for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1
            from public.game_participants gp
            where gp.game_id::text = game_actions.game_id::text
              and gp.user_id::text = auth.uid()::text
              and gp.seat_index = game_actions.seat
        )
    );

-- Append-only: no UPDATE policy. Any seated participant may DELETE (used to
-- prune old rows at end of game). Failures are non-fatal.
drop policy if exists "game_actions_delete_participant" on public.game_actions;
create policy "game_actions_delete_participant"
    on public.game_actions
    for delete
    using (
        exists (
            select 1
            from public.game_participants gp
            where gp.game_id::text = game_actions.game_id::text
              and gp.user_id::text = auth.uid()::text
        )
    );

-- Enable realtime postgres_changes on this table.
do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'game_actions'
    ) then
        execute 'alter publication supabase_realtime add table public.game_actions';
    end if;
end$$;
