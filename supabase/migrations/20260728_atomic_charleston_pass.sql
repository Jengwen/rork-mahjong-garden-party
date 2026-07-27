-- Atomic, phase-guarded Charleston pass merge.
--
-- Replaces the edge function's read-modify-write (which could revert the whole
-- game_data row when it raced the host's phase advance) with a single UPDATE
-- executed under the row lock. The phase check lives in the WHERE clause of the
-- same statement, so a submission for a phase the row has already left simply
-- matches zero rows and no-ops — it can never write back a stale snapshot.
--
-- SECURITY DEFINER so the edge function can call it with the caller's JWT while
-- the update itself bypasses RLS (participant verification stays in the edge
-- function, which already checks the caller owns the seat).

create or replace function public.submit_charleston_pass_atomic(
  p_game_id uuid,
  p_seat int,
  p_phase int,
  p_tiles jsonb,
  p_hand_after jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int;
  v_row record;
begin
  if p_seat < 0 or p_seat > 3 then
    return jsonb_build_object('ok', false, 'error', 'invalid_seat');
  end if;

  -- Single guarded UPDATE: only touches pending[seat] and players[seat].hand,
  -- and only while the row is still in the caller's phase. Never rewrites the
  -- rest of game_data, so a slow submission can't drag the row backwards.
  update online_games
  set
    game_data = jsonb_set(
      jsonb_set(
        game_data,
        array['charlestonPendingPasses', p_seat::text],
        p_tiles,
        true
      ),
      array['players', p_seat::text, 'hand'],
      p_hand_after,
      false  -- only mirror the hand if the player entry exists
    ),
    updated_at = now()
  where id = p_game_id
    and status = 'charleston'
    and (game_data->>'charlestonPhase')::int = p_phase;

  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    -- Distinguish "phase moved on" from "game not found" for the client log.
    select status, (game_data->>'charlestonPhase')::int as row_phase
      into v_row
      from online_games where id = p_game_id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'game_not_found');
    end if;
    return jsonb_build_object(
      'ok', true,
      'skipped', case when v_row.status <> 'charleston' then 'not_charleston' else 'phase_mismatch' end,
      'rowPhase', v_row.row_phase,
      'phase', p_phase
    );
  end if;

  select array(
    select k from jsonb_object_keys(
      (select game_data->'charlestonPendingPasses' from online_games where id = p_game_id)
    ) as k order by k
  ) into v_row;

  return jsonb_build_object('ok', true, 'seat', p_seat, 'phase', p_phase);
end;
$$;

-- Only service role / authenticated backend paths should call this.
revoke all on function public.submit_charleston_pass_atomic(uuid, int, int, jsonb, jsonb) from public;
grant execute on function public.submit_charleston_pass_atomic(uuid, int, int, jsonb, jsonb) to service_role;
