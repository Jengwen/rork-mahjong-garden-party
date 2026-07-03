// Supabase Edge Function: send-game-invite-push
//
// Sends an APNs push notification to the invitee when a game invite is created.
// Invoked from the iOS app via `supabase.functions.invoke("send-game-invite-push", { body: { receiverId, gameId, senderName } })`.
//
// Required Supabase secrets (set with `supabase secrets set ...`):
//   - APNS_TEAM_ID            Apple Developer Team ID (10 chars)
//   - APNS_KEY_ID             APNs Auth Key ID (10 chars)
//   - APNS_PRIVATE_KEY        Contents of the .p8 file (PEM, with -----BEGIN PRIVATE KEY----- header)
//   - APNS_BUNDLE_ID          App bundle identifier, e.g. com.example.MahjongGardenParty
//   - APNS_USE_SANDBOX        "true" for development builds, "false" or unset for production
//
// Database expectations:
//   A table `push_tokens` with columns:
//     user_id  uuid     (matches auth.users.id)
//     token    text     (hex-encoded APNs device token)
//     platform text     ('ios')
//     updated_at timestamptz

// deno-lint-ignore-file no-explicit-any
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

interface InvitePayload {
  receiverId: string;
  gameId: string;
  senderName: string;
}

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_PRIVATE_KEY = Deno.env.get("APNS_PRIVATE_KEY") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const APNS_USE_SANDBOX = (Deno.env.get("APNS_USE_SANDBOX") ?? "false").toLowerCase() === "true";

const APNS_HOST = APNS_USE_SANDBOX
  ? "https://api.sandbox.push.apple.com"
  : "https://api.push.apple.com";

// APNs reason strings that mean the device token is permanently invalid
// (Apple Push Notification Service docs, table of "reason" values).
const TOKEN_INVALID_REASONS = new Set([
  "BadDeviceToken",
  "Unregistered",
  "DeviceTokenNotForTopic",
  "TopicDisallowed",
]);

// Reason strings that indicate the provider token (our JWT) is the problem.
const PROVIDER_TOKEN_REASONS = new Set([
  "ExpiredProviderToken",
  "InvalidProviderToken",
  "MissingProviderToken",
]);

// Reason strings that are worth retrying after a short delay.
const TRANSIENT_REASONS = new Set([
  "TooManyRequests",
  "TooManyProviderTokenUpdates",
  "InternalServerError",
  "ServiceUnavailable",
  "Shutdown",
  "IdleTimeout",
]);

// ---- JWT helpers ---------------------------------------------------------

function base64UrlEncode(data: ArrayBuffer | Uint8Array | string): string {
  const bytes =
    typeof data === "string"
      ? new TextEncoder().encode(data)
      : data instanceof Uint8Array
      ? data
      : new Uint8Array(data);
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/=+$/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToPkcs8(pem: string): Uint8Array {
  const clean = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(clean);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

let cachedToken: { jwt: string; expiresAt: number } | null = null;

async function getApnsJWT(forceRefresh = false): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (!forceRefresh && cachedToken && cachedToken.expiresAt > now + 60) {
    return cachedToken.jwt;
  }

  const header = { alg: "ES256", kid: APNS_KEY_ID, typ: "JWT" };
  const claims = { iss: APNS_TEAM_ID, iat: now };
  const headerB64 = base64UrlEncode(JSON.stringify(header));
  const claimsB64 = base64UrlEncode(JSON.stringify(claims));
  const signingInput = `${headerB64}.${claimsB64}`;

  const keyBytes = pemToPkcs8(APNS_PRIVATE_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64UrlEncode(signature)}`;
  // APNs tokens are valid up to 60 minutes; refresh every ~50 minutes.
  cachedToken = { jwt, expiresAt: now + 50 * 60 };
  return jwt;
}

// ---- APNs send -----------------------------------------------------------

interface ApnsResult {
  status: number;
  ok: boolean;
  reason: string | null;
  apnsId: string | null;
  body: string;
  error: string | null;
}

function parseReason(body: string): string | null {
  if (!body) return null;
  try {
    const parsed = JSON.parse(body);
    return typeof parsed?.reason === "string" ? parsed.reason : null;
  } catch {
    return null;
  }
}

async function sendApnsOnce(
  deviceToken: string,
  payload: Record<string, unknown>,
  jwt: string,
): Promise<ApnsResult> {
  // Per-request 10s timeout so a slow APNs host can never hang the function.
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 10_000);
  try {
    const res = await fetch(`${APNS_HOST}/3/device/${deviceToken}`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 60 * 60 * 24),
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    const body = await res.text();
    return {
      status: res.status,
      ok: res.ok,
      reason: parseReason(body),
      apnsId: res.headers.get("apns-id"),
      body,
      error: null,
    };
  } catch (err) {
    return {
      status: 0,
      ok: false,
      reason: null,
      apnsId: null,
      body: "",
      error: err instanceof Error ? err.message : String(err),
    };
  } finally {
    clearTimeout(timer);
  }
}

async function sendApns(
  deviceToken: string,
  payload: Record<string, unknown>,
): Promise<ApnsResult> {
  let jwt = await getApnsJWT();
  let result = await sendApnsOnce(deviceToken, payload, jwt);

  // Refresh JWT and retry once on provider-token failure (403).
  if (!result.ok && result.reason && PROVIDER_TOKEN_REASONS.has(result.reason)) {
    cachedToken = null;
    jwt = await getApnsJWT(true);
    result = await sendApnsOnce(deviceToken, payload, jwt);
  }

  // One retry with short backoff on transient 5xx / 429 / network errors.
  const isTransientNetwork = result.status === 0 && result.error !== null;
  const isTransientReason = result.reason !== null && TRANSIENT_REASONS.has(result.reason);
  const isTransientStatus = result.status === 429 || result.status === 503 || result.status === 500;
  if (!result.ok && (isTransientNetwork || isTransientReason || isTransientStatus)) {
    await new Promise((r) => setTimeout(r, 400));
    result = await sendApnsOnce(deviceToken, payload, jwt);
  }

  return result;
}

// ---- Request handler -----------------------------------------------------

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "content-type": "application/json" },
    });
  }

  let body: InvitePayload;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  const { receiverId, gameId, senderName } = body ?? ({} as InvitePayload);
  if (!receiverId || !gameId || !senderName) {
    return new Response(
      JSON.stringify({ error: "receiverId, gameId, senderName required" }),
      { status: 400, headers: { "content-type": "application/json" } },
    );
  }

  if (!APNS_TEAM_ID || !APNS_KEY_ID || !APNS_PRIVATE_KEY || !APNS_BUNDLE_ID) {
    return new Response(
      JSON.stringify({ error: "APNs credentials not configured" }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data: tokens, error: tokensErr } = await supabase
    .from("push_tokens")
    .select("token, platform")
    .eq("user_id", receiverId)
    .eq("platform", "ios");

  if (tokensErr) {
    return new Response(
      JSON.stringify({ error: "Failed to load device tokens", details: tokensErr.message }),
      { status: 500, headers: { "content-type": "application/json" } },
    );
  }

  if (!tokens || tokens.length === 0) {
    return new Response(
      JSON.stringify({ ok: true, delivered: 0, reason: "no device tokens" }),
      { status: 200, headers: { "content-type": "application/json" } },
    );
  }

  const payload = {
    aps: {
      alert: {
        title: "Game Invite",
        body: `${senderName} invited you to play Mahjong`,
      },
      sound: "default",
      "thread-id": `invite-${gameId}`,
    },
    type: "invite",
    gameId,
    senderName,
  };

  const results = await Promise.all(
    tokens.map(async (row: any) => {
      const r = await sendApns(row.token, payload);

      // Permanently invalid token → clean it up so we never try it again.
      const shouldDelete =
        r.status === 410 ||
        (r.reason !== null && TOKEN_INVALID_REASONS.has(r.reason));

      if (shouldDelete) {
        const { error: delErr } = await supabase
          .from("push_tokens")
          .delete()
          .eq("token", row.token);
        if (delErr) {
          console.error("Failed to delete stale token", row.token.slice(0, 8), delErr.message);
        }
      } else if (!r.ok) {
        // Log non-fatal failures so they show up in Supabase function logs.
        console.error("APNs send failed", {
          tokenPrefix: row.token.slice(0, 8),
          status: r.status,
          reason: r.reason,
          apnsId: r.apnsId,
          error: r.error,
        });
      }

      return {
        token: row.token.slice(0, 8) + "…",
        status: r.status,
        ok: r.ok,
        reason: r.reason,
        cleanedUp: shouldDelete,
      };
    }),
  );

  return new Response(
    JSON.stringify({
      ok: true,
      delivered: results.filter((r) => r.ok).length,
      attempted: results.length,
      results,
    }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
});
