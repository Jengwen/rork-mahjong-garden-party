// Supabase Edge Function: submit-charleston-pass
//
// Atomic server-side relay for a single seat's Charleston pass. The iOS client
// has historically tried to write its pass directly into `online_games.game_data`
// using a fetch-then-merge-then-update sequence. Two problems made that path
// unreliable in production:
//
//   1) RLS sometimes blocks a non-host's UPDATE on `online_games`, so the
//      invitee's pass never lands on the row at all and the host's poll never
//      sees it. Their realtime broadcasts are also occasionally dropped, so the
//      host can sit forever on a phase missing the invitee's submission.
//
//   2) Even when RLS permits the write, two clients can race: invitee fetches,
//      host fetches, invitee writes pending={0,1,2,3}, host writes pending={0,2,3}
//      (host's local view from before invitee's write), clobbering seat 1.
//
// This function fixes both by performing the read-modify-write inside a single
// edge invocation using the service role key. Concurrent calls from different
// clients each merge their own seat's pass into the latest row state, so no
// pass is ever clobbered.
//
// Body shape:
//   {
//     gameId: string,        // online_games.id
//     seat: number,          // 0-3, caller's seat
//     phase: number,         // local charleston phase the caller is on
//     tiles: any[],          // the seat's MahjongTile[] for this pass
//     handAfter: any[]       // the seat's hand AFTER removing the pass tiles
//   }
//
// The function:
//   - Authenticates the caller via their bearer JWT.
//   - Verifies they are a participant of `gameId` AT `seat`.
//   - Reads `online_games.game_data`.
//   - If status == 'charleston' and game_data.charlestonPhase == phase, merges
//     the pass into game_data.charlestonPendingPasses[String(seat)] and
//     mirrors `handAfter` into game_data.players[seat].hand.
//   - Otherwise returns `{ ok: true, skipped: 'phase_mismatch' }` so the
//     client knows it's stale; clients use this to stop their heartbeats.
//
// Required Supabase secrets:
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (auto-injected by Supabase)

// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface SubmitPayload {
  gameId: string;
  seat: number;
  phase: number;
  tiles: unknown[];
  handAfter: unknown[];
}

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers":
    "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...corsHeaders },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // ---- auth ----
  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!jwt) return jsonResponse({ error: "Missing bearer token" }, 401);

  // Service-role client: used for ALL row reads/writes so RLS never blocks.
  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // Identify caller from their JWT.
  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }
  const callerId = userData.user.id;

  // ---- parse body ----
  let body: SubmitPayload;
  try {
    body = (await req.json()) as SubmitPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400);
  }
  const { gameId, seat, phase, tiles, handAfter } = body ?? ({} as SubmitPayload);
  if (
    typeof gameId !== "string" ||
    typeof seat !== "number" ||
    typeof phase !== "number" ||
    !Array.isArray(tiles) ||
    !Array.isArray(handAfter)
  ) {
    return jsonResponse({ error: "Invalid payload" }, 400);
  }
  if (seat < 0 || seat > 3) {
    return jsonResponse({ error: "Invalid seat" }, 400);
  }

  // ---- verify caller is the participant at this seat ----
  const { data: participants, error: partErr } = await admin
    .from("game_participants")
    .select("user_id, seat_index")
    .eq("game_id", gameId);
  if (partErr) {
    return jsonResponse(
      { error: "Failed to load participants", details: partErr.message },
      500,
    );
  }
  const ownSeat = (participants ?? []).find(
    (p: any) => p.user_id === callerId,
  )?.seat_index;
  if (ownSeat !== seat) {
    return jsonResponse(
      { error: "Caller is not seated at the requested seat" },
      403,
    );
  }

  // ---- read current row ----
  const { data: row, error: rowErr } = await admin
    .from("online_games")
    .select("status, game_data")
    .eq("id", gameId)
    .maybeSingle();
  if (rowErr || !row) {
    return jsonResponse(
      { error: "Game not found", details: rowErr?.message ?? null },
      404,
    );
  }

  const status: string = row.status;
  const gameData: any = row.game_data ?? null;
  if (!gameData) {
    return jsonResponse(
      { ok: true, skipped: "no_game_data" },
      200,
    );
  }

  // Only merge while the row is still in the same Charleston phase.
  if (status !== "charleston") {
    return jsonResponse({ ok: true, skipped: "not_charleston", status }, 200);
  }
  const rowPhase: number = typeof gameData.charlestonPhase === "number"
    ? gameData.charlestonPhase
    : -1;
  if (rowPhase !== phase) {
    return jsonResponse(
      { ok: true, skipped: "phase_mismatch", rowPhase, phase },
      200,
    );
  }

  // ---- merge pass ----
  const pending: Record<string, unknown> =
    (gameData.charlestonPendingPasses && typeof gameData.charlestonPendingPasses === "object")
      ? { ...gameData.charlestonPendingPasses }
      : {};
  pending[String(seat)] = tiles;
  gameData.charlestonPendingPasses = pending;

  // Mirror hand-after onto the seat so post-exchange math stays consistent
  // with what the seat actually has client-side.
  if (Array.isArray(gameData.players) && gameData.players[seat]) {
    gameData.players[seat] = { ...gameData.players[seat], hand: handAfter };
  }

  // ---- write back ----
  const nowIso = new Date().toISOString();
  const { error: updErr } = await admin
    .from("online_games")
    .update({ game_data: gameData, updated_at: nowIso })
    .eq("id", gameId);
  if (updErr) {
    return jsonResponse(
      { error: "Failed to write game state", details: updErr.message },
      500,
    );
  }

  return jsonResponse({
    ok: true,
    seat,
    phase,
    pending: Object.keys(pending).map((k) => Number(k)).sort(),
  });
});
