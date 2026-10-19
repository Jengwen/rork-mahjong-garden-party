// Supabase Edge Function: app-store-notifications
//
// App Store Server Notifications V2 endpoint. Configure in App Store Connect →
// App Information → App Store Server Notifications (Production AND Sandbox URL):
//   https://<project>.supabase.co/functions/v1/app-store-notifications
// Deploy with JWT verification OFF (Apple doesn't send a Supabase token).
//
// Keeps web access in sync when a subscription renews, lapses, is refunded or
// revoked — without the user opening the iPhone app.
//
// Trust: the notification body is only used to learn WHICH subscription changed.
// Its current status is then fetched from Apple's API directly (see
// _shared/appstore.ts), so a forged notification can't grant access — at most it
// triggers a harmless re-check.
// deno-lint-ignore-file no-explicit-any
import { admin, decodeJwsPayload } from "../_shared/common.ts";
import { appleConfigured, BUNDLE_ID, fetchSubscriptionState } from "../_shared/appstore.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (!appleConfigured()) return new Response("Not configured", { status: 503 });

  let originalTransactionId: string | null = null;
  try {
    const { signedPayload } = await req.json();
    const payload = decodeJwsPayload(signedPayload);
    if (payload?.data?.bundleId && payload.data.bundleId !== BUNDLE_ID) return new Response("ignored", { status: 200 });
    if (payload?.notificationType === "TEST") return new Response("ok", { status: 200 });
    const tx = payload?.data?.signedTransactionInfo ? decodeJwsPayload(payload.data.signedTransactionInfo) : null;
    originalTransactionId = tx?.originalTransactionId ? String(tx.originalTransactionId) : null;
  } catch {
    return new Response("Bad payload", { status: 400 });
  }
  if (!originalTransactionId) return new Response("ok", { status: 200 });

  const db = admin();
  const { data: rows } = await db.from("user_entitlements").select("user_id")
    .eq("original_transaction_id", originalTransactionId).limit(1);
  // Not linked to any account yet: the app will link it on next launch via app-store-sync.
  if (!rows?.length) return new Response("ok", { status: 200 });

  let state;
  try {
    state = await fetchSubscriptionState(originalTransactionId);
  } catch (e) {
    console.error("app-store-notifications: Apple API error", e);
    return new Response("Retry later", { status: 500 }); // Apple retries on non-2xx
  }

  const update = state
    ? { product_id: state.productId, status: state.status, expires_at: state.expiresAt, will_renew: state.willRenew, environment: state.environment }
    : { status: "expired", will_renew: false };
  const { error } = await db.from("user_entitlements")
    .update({ ...update, updated_at: new Date().toISOString() })
    .eq("original_transaction_id", originalTransactionId);
  if (error) {
    console.error("app-store-notifications: update failed", error);
    return new Response("Retry later", { status: 500 });
  }
  return new Response("ok", { status: 200 });
});
