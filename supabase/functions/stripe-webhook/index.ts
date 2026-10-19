// Supabase Edge Function: stripe-webhook
//
// Stripe → this endpoint (deploy with JWT verification OFF):
//   https://<project>.supabase.co/functions/v1/stripe-webhook
// Subscribe the endpoint to: checkout.session.completed,
//   customer.subscription.created, customer.subscription.updated,
//   customer.subscription.deleted
//
// Every event is signature-verified, then the subscription is re-fetched from
// Stripe so out-of-order deliveries always converge on the current state.
//
// Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PRICE_MONTHLY, STRIPE_PRICE_ANNUAL
// deno-lint-ignore-file no-explicit-any
import { admin } from "../_shared/common.ts";
import { stripe, subscriptionToEntitlement, verifyWebhook } from "../_shared/stripe.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const raw = await req.text();
  if (!(await verifyWebhook(raw, req.headers.get("stripe-signature")))) {
    return new Response("Invalid signature", { status: 400 });
  }
  const event = JSON.parse(raw);
  const obj = event.data?.object ?? {};

  let subscriptionId: string | null = null;
  if (event.type === "checkout.session.completed" && obj.mode === "subscription") subscriptionId = obj.subscription;
  else if (event.type?.startsWith("customer.subscription.")) subscriptionId = obj.id;
  if (!subscriptionId) return new Response("ignored", { status: 200 });

  try {
    const sub = await stripe("GET", `subscriptions/${subscriptionId}`);
    const db = admin();
    let uid: string | undefined = sub.metadata?.supabase_user_id;
    if (!uid) {
      const { data } = await db.from("user_entitlements").select("user_id")
        .eq("stripe_customer_id", typeof sub.customer === "string" ? sub.customer : sub.customer?.id).limit(1);
      uid = data?.[0]?.user_id;
    }
    if (!uid) {
      console.warn("stripe-webhook: no user for subscription", subscriptionId);
      return new Response("no user", { status: 200 });
    }
    const patch = subscriptionToEntitlement(sub);
    const { error } = await db.from("user_entitlements").upsert({
      user_id: uid, source: "stripe", ...patch,
      had_trial: true,
      updated_at: new Date().toISOString(),
    }, { onConflict: "user_id,source" });
    if (error) throw error;
    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("stripe-webhook", e);
    return new Response("Retry later", { status: 500 }); // Stripe retries on non-2xx
  }
});
