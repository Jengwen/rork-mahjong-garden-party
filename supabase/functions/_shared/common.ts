// Shared helpers for the subscription edge functions.
// deno-lint-ignore-file no-explicit-any
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

/** Comma-separated origins allowed to call browser-facing functions, e.g. "https://play.mahjonggardenparty.com". */
// Entries are normalized to a bare origin, so "https://play.example.com/" or a pasted
// page URL ("https://play.example.com/index.html") still match the browser's Origin.
function toOrigin(s: string): string {
  try { return new URL(s.trim()).origin.toLowerCase(); } catch { return s.trim().replace(/\/+$/, "").toLowerCase(); }
}
const ALLOWED_ORIGINS = (Deno.env.get("WEB_APP_ORIGINS") ?? "")
  .split(",").map(toOrigin).filter(Boolean);

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const ok = ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin.toLowerCase());
  if (!ok && origin) console.warn(`CORS: origin ${origin} is not in WEB_APP_ORIGINS (${ALLOWED_ORIGINS.join(", ")})`);
  const allow = ok ? (origin || "*") : ALLOWED_ORIGINS[0];
  return {
    "access-control-allow-origin": allow,
    // Kept in sync with @supabase/supabase-js/cors (headers the SDK may send).
    "access-control-allow-headers": "authorization, x-client-info, apikey, content-type, x-retry-count, x-region, traceparent, tracestate, baggage",
    "access-control-allow-methods": "POST, OPTIONS",
    "vary": "origin",
  };
}

export function json(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", ...corsHeaders(req) } });
}

export function isAllowedReturnUrl(url: unknown): url is string {
  if (typeof url !== "string") return false;
  try {
    const u = new URL(url);
    if (ALLOWED_ORIGINS.length === 0) return u.protocol === "https:" || u.hostname === "localhost";
    const ok = ALLOWED_ORIGINS.includes(u.origin.toLowerCase());
    if (!ok) console.warn(`Return URL ${u.origin} is not in WEB_APP_ORIGINS (${ALLOWED_ORIGINS.join(", ")})`);
    return ok;
  } catch {
    return false;
  }
}

export function admin(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } });
}

/** Resolve the calling user from the Authorization header; null if missing/invalid. */
export async function callerId(req: Request): Promise<string | null> {
  const auth = req.headers.get("authorization") ?? "";
  if (!auth.toLowerCase().startsWith("bearer ")) return null;
  const client = createClient(SUPABASE_URL, ANON || SERVICE_ROLE, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data, error } = await client.auth.getUser(auth.slice(7));
  if (error || !data.user) return null;
  return data.user.id;
}

export function b64urlDecode(s: string): Uint8Array {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

export function b64urlEncode(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let bin = "";
  for (const b of data) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Decode a JWS payload WITHOUT verifying. Only use on data whose trust comes from elsewhere. */
export function decodeJwsPayload<T = any>(jws: string): T {
  const part = jws.split(".")[1];
  return JSON.parse(new TextDecoder().decode(b64urlDecode(part)));
}
