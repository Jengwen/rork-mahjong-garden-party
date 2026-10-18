// Minimal Stripe REST client (no SDK) + webhook signature verification.
//
// Secrets:
//   STRIPE_SECRET_KEY       sk_live_… / sk_test_…
//   STRIPE_WEBHOOK_SECRET   whsec_… (from the webhook endpoint)
//   STRIPE_PRICE_MONTHLY    price_… ($1.99 / month)
//   STRIPE_PRICE_ANNUAL     price_… ($19.99 / year)
// deno-lint-ignore-file no-explicit-any

const SECRET = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
export const PRICES: Record<string, string> = {
  monthly: Deno.env.get("STRIPE_PRICE_MONTHLY") ?? "",
  annual: Deno.env.get("STRIPE_PRICE_ANNUAL") ?? "",
};
const API_VERSION = "2024-06-20";

export function stripeConfigured(): boolean {
  return Boolean(SECRET && PRICES.monthly && PRICES.annual);
}

export function form(params: Record<string, unknown>, prefix = ""): string[] {
  const out: string[] = [];
  for (const [k, v] of Object.entries(params)) {
    if (v === undefined || v === null) continue;
    const key = prefix ? `${prefix}[${k}]` : k;
    if (Array.isArray(v)) v.forEach((item, i) => {
      if (typeof item === "object") out.push(...form(item, `${key}[${i}]`));
      else out.push(`${encodeURIComponent(`${key}[${i}]`)}=${encodeURIComponent(String(item))}`);
    });
    else if (typeof v === "object") out.push(...form(v as Record<string, unknown>, key));
    else out.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(v))}`);
  }
  return out;
}

export async function stripe(method: "GET" | "POST", path: string, params?: Record<string, unknown>): Promise<any> {
  const qs = params ? form(params).join("&") : "";
  const url = `https://api.stripe.com/v1/${path}${method === "GET" && qs ? `?${qs}` : ""}`;
  const res = await fetch(url, {
    method,
    headers: {
      authorization: `Bearer ${SECRET}`,
      "stripe-version": API_VERSION,
      ...(method === "POST" ? { "content-type": "application/x-www-form-urlencoded" } : {}),
    },
    body: method === "POST" ? qs : undefined,
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Stripe ${path}: ${body?.error?.message ?? res.status}`);
  return body;
}

/** Verify the Stripe-Signature header (v1 HMAC-SHA256, 5-minute tolerance). */
export async function verifyWebhook(rawBody: string, header: string | null): Promise<boolean> {
  if (!WEBHOOK_SECRET || !header) return false;
  const parts = Object.fromEntries(header.split(",").map((p) => p.split("=") as [string, string]));
  const t = Number(parts.t);
  if (!t || Math.abs(Date.now() / 1000 - t) > 300) return false;
  const signatures = header.split(",").filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(WEBHOOK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${rawBody}`)));
  const expected = Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
  return signatures.some((sig) => timingSafeEqual(sig, expected));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Map a Stripe subscription object to an entitlements row patch. */
export function subscriptionToEntitlement(sub: any) {
  const item = sub.items?.data?.[0];
  // current_period_end moved from the subscription to its items in newer API versions.
  const periodEnd: number | undefined = sub.current_period_end ?? item?.current_period_end;
  const plan = item?.price?.id === PRICES.annual ? "annual" : item?.price?.id === PRICES.monthly ? "monthly" : item?.price?.id;
  let status: string;
  switch (sub.status) {
    case "trialing": status = "trialing"; break;
    case "active": status = sub.cancel_at_period_end ? "canceled_pending" : "active"; break;
    case "past_due": status = "grace_period"; break;
    case "incomplete": status = "incomplete"; break;
    default: status = "expired"; // canceled, unpaid, incomplete_expired, paused
  }
  return {
    product_id: plan ?? null,
    status,
    expires_at: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
    will_renew: !sub.cancel_at_period_end && ["active", "trialing", "past_due"].includes(sub.status),
    stripe_subscription_id: sub.id,
    stripe_customer_id: typeof sub.customer === "string" ? sub.customer : sub.customer?.id,
  };
}
