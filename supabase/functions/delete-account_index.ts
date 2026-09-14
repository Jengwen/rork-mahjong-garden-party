// Supabase Edge Function: delete-account
//
// Permanently deletes the CALLING user's account and every row of app data
// tied to them. This must run with the service-role key because deleting an
// auth.users row (client SDKs never expose this — only the Admin API does,
// and that key must never ship in the app bundle).
//
// Schema note (checked against the live DB before writing this):
//   player_profiles, game_results, device_tokens, push_tokens,
//   charleston_passes, and game_actions all have `user_id uuid references
//   auth.users(id) on delete cascade` — deleting the auth user cleans these
//   up automatically.
//
//   friendships, messages, online_games, game_participants, and
//   game_invites predate that convention and key their user columns as
//   plain `text` with NO foreign key to auth.users at all. Nothing cascades
//   there, so this function deletes those rows explicitly BEFORE removing
//   the auth user — otherwise a deleted user's id would keep showing up in
//   other people's friend lists, inboxes, and game rosters forever.
//
// Multiplayer rows (game_participants / game_invites) are scoped to only
// the caller's own rows. If removing the caller leaves an online_games row
// with zero remaining participants, that orphaned game row is deleted too
// (its own game_id-scoped FKs to charleston_passes/game_actions/
// game_invites are ON DELETE CASCADE, so that cleans up in one shot). Games
// that still have other seated players are left alone.
//
// Required Supabase secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// (both auto-injected by Supabase).

// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

  // ---- auth: caller can only ever delete THEMSELVES ----
  // Deliberately never accept a target user id in the request body — the
  // only identity this function trusts is the one attached to the bearer
  // token, so there is no way to make it delete someone else's account.
  const authHeader = req.headers.get("authorization") ?? "";
  const jwt = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!jwt) return jsonResponse({ error: "Missing bearer token" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData?.user) {
    return jsonResponse({ error: "Invalid token" }, 401);
  }
  const callerId = userData.user.id;
  const callerIdText = callerId; // uuid string form, used against text columns below

  const errors: Record<string, string> = {};

  // ---- 1) social graph: friendships, messages, invites (text columns, no FK) ----
  const { error: friendErr } = await admin
    .from("friendships")
    .delete()
    .or(`user_id.eq.${callerIdText},friend_id.eq.${callerIdText}`);
  if (friendErr) errors.friendships = friendErr.message;

  const { error: msgErr } = await admin
    .from("messages")
    .delete()
    .or(`sender_id.eq.${callerIdText},receiver_id.eq.${callerIdText}`);
  if (msgErr) errors.messages = msgErr.message;

  const { error: inviteErr } = await admin
    .from("game_invites")
    .delete()
    .or(`sender_id.eq.${callerIdText},receiver_id.eq.${callerIdText}`);
  if (inviteErr) errors.game_invites = inviteErr.message;

  // ---- 2) multiplayer seats: remove caller's own participant rows, then ----
  //         sweep any game that's now empty.
  const { data: ownSeats, error: seatsErr } = await admin
    .from("game_participants")
    .select("game_id")
    .eq("user_id", callerIdText);
  if (seatsErr) errors.game_participants_read = seatsErr.message;

  const affectedGameIds = Array.from(
    new Set((ownSeats ?? []).map((r: any) => r.game_id as string)),
  );

  const { error: seatDeleteErr } = await admin
    .from("game_participants")
    .delete()
    .eq("user_id", callerIdText);
  if (seatDeleteErr) errors.game_participants = seatDeleteErr.message;

  for (const gameId of affectedGameIds) {
    const { count, error: remainingErr } = await admin
      .from("game_participants")
      .select("id", { count: "exact", head: true })
      .eq("game_id", gameId);
    if (remainingErr) {
      errors[`game_check_${gameId}`] = remainingErr.message;
      continue;
    }
    if ((count ?? 0) === 0) {
      // No one left seated — delete the game shell. game_id-scoped FKs
      // (charleston_passes, game_actions, game_invites) cascade from here.
      const { error: gameDeleteErr } = await admin
        .from("online_games")
        .delete()
        .eq("id", gameId);
      if (gameDeleteErr) errors[`game_delete_${gameId}`] = gameDeleteErr.message;
    }
  }

  // ---- 3) delete the auth user last ----
  // Cascades player_profiles, game_results, device_tokens, push_tokens, and
  // any remaining charleston_passes/game_actions rows tied to this user_id
  // directly (e.g. in games that stayed alive because other seats remain).
  const { error: deleteUserErr } = await admin.auth.admin.deleteUser(callerId);
  if (deleteUserErr) {
    return jsonResponse(
      {
        error: "Account data was cleaned up but the auth user could not be deleted",
        details: deleteUserErr.message,
        partialErrors: errors,
      },
      500,
    );
  }

  return jsonResponse({
    ok: true,
    deletedUserId: callerId,
    partialErrors: Object.keys(errors).length > 0 ? errors : undefined,
  });
});
