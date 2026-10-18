// Supabase Edge Function: stripe-portal
// Web app → { return_url } → { url } for Stripe's hosted billing portal
// (update card, switch plan, cancel). Only for web (Stripe) subscribers;
// iPhone subscriptions are managed in the iOS Settings app.
// Secrets: STRIPE_SECRET_KEY, WEB_APP_ORIGINS
// deno-lint-ignore-file no-explicit-any
import { admin, callerId, corsHeaders, isAllowedReturnUrl, json } from "../_shared/common.ts";
import { stripe } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);
  const uid = await callerId(req);
  if (!uid) return json(req, { error: "Not authenticated" }, 401);

  let body: any;
  try { body = await req.json(); } catch { body = {}; }
  if (!isAllowedReturnUrl(body?.return_url)) return json(req, { error: "Invalid return URL" }, 400);

  const { data } = await admin().from("user_entitlements").select("stripe_customer_id")
    .eq("user_id", uid).eq("source", "stripe").maybeSingle();
  if (!data?.stripe_customer_id) return json(req, { error: "No web subscription on this account." }, 404);

  try {
    const session = await stripe("POST", "billing_portal/sessions", { customer: data.stripe_customer_id, return_url: body.return_url });
    return json(req, { url: session.url });
  } catch (e) {
    console.error("stripe-portal", e);
    return json(req, { error: "Billing portal unavailable." }, 502);
  }
});
