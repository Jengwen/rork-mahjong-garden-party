// Shared helpers for the subscription edge functions.
// deno-lint-ignore-file no-explicit-any
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

/** Comma-separated origins allowed to call browser-facing functions, e.g. "https://play.mahjonggardenparty.com". */
const ALLOWED_ORIGINS = (Deno.env.get("WEB_APP_ORIGINS") ?? "")
  .split(",").map((s) => s.trim()).filter(Boolean);

export function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allow = ALLOWED_ORIGINS.length === 0 || ALLOWED_ORIGINS.includes(origin) ? (origin || "*") : ALLOWED_ORIGINS[0];
  return {
    "access-control-allow-origin": allow,
    "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
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
    return ALLOWED_ORIGINS.includes(u.origin);
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
