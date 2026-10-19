// Supabase Edge Function: app-store-sync
//
// Called by the iOS app (StoreManager) after a purchase, restore, launch refresh,
// or Transaction.updates event:
//   supabase.functions.invoke("app-store-sync", { body: { originalTransactionId } })
//
// Asks Apple for the subscription's real status and records it for the signed-in
// user in `user_entitlements` (source = 'app_store'), which the web app reads to
// unlock play. See _shared/appstore.ts for the trust model.
//
// Binding rules:
//   • If the transaction carries an appAccountToken (iOS sets it to the user's
//     Supabase id at purchase), only that user may claim it.
//   • Otherwise the most recent signed-in claimant wins, and any other account's
//     row for the same subscription is released — one Apple subscription unlocks
//     one Mahjong Garden Party account at a time.
//
// Secrets: APPLE_IAP_ISSUER_ID, APPLE_IAP_KEY_ID, APPLE_IAP_PRIVATE_KEY, APPLE_BUNDLE_ID
// deno-lint-ignore-file no-explicit-any
import { admin, callerId, corsHeaders, json } from "../_shared/common.ts";
import { appleConfigured, fetchSubscriptionState } from "../_shared/appstore.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) });
  if (req.method !== "POST") return json(req, { error: "Method not allowed" }, 405);

  const uid = await callerId(req);
  if (!uid) return json(req, { error: "Not authenticated" }, 401);
  if (!appleConfigured()) return json(req, { error: "App Store sync is not configured" }, 503);

  let body: any;
  try { body = await req.json(); } catch { return json(req, { error: "Invalid JSON" }, 400); }
  const txId = String(body?.originalTransactionId ?? body?.transactionId ?? "");
  if (!/^\d{1,32}$/.test(txId)) return json(req, { error: "originalTransactionId required" }, 400);

  let state;
  try {
    state = await fetchSubscriptionState(txId);
  } catch (e) {
    console.error("app-store-sync: Apple API error", e);
    return json(req, { error: "Could not reach the App Store" }, 502);
  }
  if (!state) return json(req, { error: "Unknown transaction" }, 404);

  if (state.appAccountToken && state.appAccountToken.toLowerCase() !== uid.toLowerCase()) {
    return json(req, { error: "This subscription belongs to a different account" }, 403);
  }

  const db = admin();
  // Release this subscription from any other account that previously claimed it.
  await db.from("user_entitlements").delete()
    .eq("original_transaction_id", state.originalTransactionId).neq("user_id", uid);

  const { error } = await db.from("user_entitlements").upsert({
    user_id: uid,
    source: "app_store",
    product_id: state.productId,
    status: state.status,
    expires_at: state.expiresAt,
    will_renew: state.willRenew,
    original_transaction_id: state.originalTransactionId,
    environment: state.environment,
    had_trial: true,
    updated_at: new Date().toISOString(),
  }, { onConflict: "user_id,source" });
  if (error) {
    console.error("app-store-sync: upsert failed", error);
    return json(req, { error: "Could not save entitlement" }, 500);
  }

  return json(req, { ok: true, status: state.status, expiresAt: state.expiresAt, productId: state.productId });
});
