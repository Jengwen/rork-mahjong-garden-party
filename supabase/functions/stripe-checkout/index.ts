// Supabase Edge Function: stripe-checkout
//
// Web app → { plan: "monthly" | "annual", success_url, cancel_url } → { url }
// Creates (or reuses) the user's Stripe customer and a subscription Checkout
// Session. A 7-day trial is offered only to accounts that have never had a
// subscription from either store (same introductory offer as the App Store).
//
// Refuses to start a second subscription when the account already has active
// access from either iOS or the web.
//
// Secrets: STRIPE_SECRET_KEY, STRIPE_PRICE_MONTHLY, STRIPE_PRICE_ANNUAL, WEB_APP_ORIGINS
// deno-lint-ignore-file no-explicit-any
import { admin, callerId, corsHeaders, isAllowedReturnUrl, json } from "../_shared/common.ts";
import { PRICES, stripe, stripeConfigured } from "../_shared/stripe.ts";

const ACTIVE = new Set(["active", "trialing", "grace_period", "canceled_pending"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  const uid = await callerId(req);
  if (!uid) return json(req, { error: "Not authenticated" }, 401);
  if (!stripeConfigured()) return json(req, { error: "Web subscriptions are not available yet." }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json(req, { error: "Invalid JSON" }, 400); }
  const plan = body?.plan === "monthly" ? "monthly" : body?.plan === "annual" ? "annual" : null;
  if (!plan) return json(req, { error: "Unknown plan" }, 400);
  if (!isAllowedReturnUrl(body.success_url) || !isAllowedReturnUrl(body.cancel_url)) {
    return json(req, { error: "Invalid return URL" }, 400);
  }

  const db = admin();
  const { data: rows } = await db.from("user_entitlements").select("*").eq("user_id", uid);
  const now = Date.now();
  const activeRow = (rows ?? []).find((r: any) => ACTIVE.has(r.status) && (!r.expires_at || new Date(r.expires_at).getTime() > now));
  if (activeRow) {
    return json(req, { error: activeRow.source === "app_store" ? "You already have an active iPhone subscription on this account." : "You already have an active subscription." }, 409);
  }
  const hadTrial = (rows ?? []).some((r: any) => r.had_trial || r.source === "app_store");
  let customerId: string | undefined = (rows ?? []).find((r: any) => r.source === "stripe")?.stripe_customer_id ?? undefined;

  try {
    if (!customerId) {
      const { data: userData } = await db.auth.admin.getUserById(uid);
      const customer = await stripe("POST", "customers", {
        email: userData?.user?.email ?? undefined,
        metadata: { supabase_user_id: uid },
      });
      customerId = customer.id;
      await db.from("user_entitlements").upsert({
        user_id: uid, source: "stripe", status: "inactive", stripe_customer_id: customerId, updated_at: new Date().toISOString(),
      }, { onConflict: "user_id,source" });
    }

    const session = await stripe("POST", "checkout/sessions", {
      mode: "subscription",
      customer: customerId,
      client_reference_id: uid,
      line_items: [{ price: PRICES[plan], quantity: 1 }],
      success_url: body.success_url,
      cancel_url: body.cancel_url,
      allow_promotion_codes: "true",
      subscription_data: {
        metadata: { supabase_user_id: uid },
        ...(hadTrial ? {} : { trial_period_days: 7 }),
      },
    });
    return json(req, { url: session.url });
  } catch (e) {
    console.error("stripe-checkout", e);
    return json(req, { error: "Could not start checkout. Please try again." }, 502);
  }
});
