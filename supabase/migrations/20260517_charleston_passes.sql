-- charleston_passes: per-seat per-phase Charleston pass submissions.
--
-- Why this table exists:
--   Previously, each client merged its pass into `online_games.game_data` JSON
--   via fetch → modify → write, OR via the `submit-charleston-pass` edge
--   function. Both paths cost extra DB calls, races, and were vulnerable to
--   RLS issues / clobbering. This table replaces those paths with a single
--   INSERT (UPSERT) per seat per phase. The host subscribes to realtime
--   inserts and finalizes the round with one UPDATE on `online_games`.
--
-- Cost per Charleston round:
--   - 4 INSERTs (one per seat)
--   - 1 UPDATE (host advances `online_games` after finalize)
--   = 5 DB calls minimum (vs. 16+ in the read-modify-write path).

create table if not exists public.charleston_passes (
    game_id    uuid        not null references public.online_games(id) on delete cascade,
    seat_index int         not null check (seat_index between 0 and 3),
    phase      int         not null,
    user_id    uuid        not null references auth.users(id) on delete cascade,
    tiles      jsonb       not null,
    hand_after jsonb       not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    primary key (game_id, seat_index, phase)
);

create index if not exists charleston_passes_game_idx
    on public.charleston_passes (game_id);
create index if not exists charleston_passes_game_phase_idx
    on public.charleston_passes (game_id, phase);

-- Auto-bump updated_at on UPSERT.
create or replace function public.charleston_passes_set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists charleston_passes_set_updated_at on public.charleston_passes;
create trigger charleston_passes_set_updated_at
    before insert or update on public.charleston_passes
    for each row execute function public.charleston_passes_set_updated_at();

alter table public.charleston_passes enable row level security;

-- Anyone seated in the game can read every seat's submissions for that game.
drop policy if exists "charleston_passes_select_participant" on public.charleston_passes;
create policy "charleston_passes_select_participant"
    on public.charleston_passes
    for select
    using (
        exists (
            select 1
            from public.game_participants gp
            where gp.game_id::text = charleston_passes.game_id::text
              and gp.user_id::text = auth.uid()::text
        )
    );

-- A user may only insert their own seat's pass — and only if they are
-- actually seated at that seat.
drop policy if exists "charleston_passes_insert_own_seat" on public.charleston_passes;
create policy "charleston_passes_insert_own_seat"
    on public.charleston_passes
    for insert
    with check (
        auth.uid() = user_id
        and exists (
            select 1
            from public.game_participants gp
            where gp.game_id::text = charleston_passes.game_id::text
              and gp.user_id::text = auth.uid()::text
              and gp.seat_index = charleston_passes.seat_index
        )
    );

-- Idempotent retries: a client may UPSERT the same row to overwrite their
-- own submission (e.g. heartbeat re-pushes after a transient failure).
drop policy if exists "charleston_passes_update_own_seat" on public.charleston_passes;
create policy "charleston_passes_update_own_seat"
    on public.charleston_passes
    for update
    using (auth.uid() = user_id)
    with check (auth.uid() = user_id);

-- Host (or any participant) may delete pass rows for cleanup at end of round.
drop policy if exists "charleston_passes_delete_participant" on public.charleston_passes;
create policy "charleston_passes_delete_participant"
    on public.charleston_passes
    for delete
    using (
        exists (
            select 1
            from public.game_participants gp
            where gp.game_id::text = charleston_passes.game_id::text
              and gp.user_id::text = auth.uid()::text
        )
    );

-- Enable realtime broadcasts for INSERT/UPDATE/DELETE on this table.
do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'charleston_passes'
    ) then
        execute 'alter publication supabase_realtime add table public.charleston_passes';
    end if;
end$$;
