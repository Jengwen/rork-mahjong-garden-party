// App Store Server API client used by app-store-sync and app-store-notifications.
//
// TRUST MODEL: we never trust a transaction the client (or a notification body)
// hands us. Both entry points only extract an originalTransactionId, then ask
// Apple directly — over TLS, authenticated with our own In-App Purchase key —
// for the subscription's current status. The JWS objects in Apple's RESPONSE are
// decoded without re-verifying their signature chain because they came straight
// from Apple's API, not from a third party.
//
// Required secrets:
//   APPLE_IAP_ISSUER_ID   App Store Connect → Users and Access → Integrations → In-App Purchase (Issuer ID)
//   APPLE_IAP_KEY_ID      Key ID of the In-App Purchase key
//   APPLE_IAP_PRIVATE_KEY Contents of the .p8 (PEM, including BEGIN/END lines)
//   APPLE_BUNDLE_ID       com.mahjonggardenparty
// deno-lint-ignore-file no-explicit-any
import { b64urlEncode, decodeJwsPayload } from "./common.ts";

const ISSUER = Deno.env.get("APPLE_IAP_ISSUER_ID") ?? "";
const KEY_ID = Deno.env.get("APPLE_IAP_KEY_ID") ?? "";
const PRIVATE_KEY = Deno.env.get("APPLE_IAP_PRIVATE_KEY") ?? "";
export const BUNDLE_ID = Deno.env.get("APPLE_BUNDLE_ID") ?? "com.mahjonggardenparty";

const HOSTS = {
  Production: "https://api.storekit.itunes.apple.com",
  Sandbox: "https://api.storekit-sandbox.itunes.apple.com",
} as const;

export const SUBSCRIPTION_PRODUCTS = new Set(["mgg_monthly", "mgg_annual"]);

export function appleConfigured(): boolean {
  return Boolean(ISSUER && KEY_ID && PRIVATE_KEY);
}

let cachedToken: { jwt: string; exp: number } | null = null;

export async function apiToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.exp - 60 > now) return cachedToken.jwt;
  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const payload = { iss: ISSUER, iat: now, exp: now + 1800, aud: "appstoreconnect-v1", bid: BUNDLE_ID };
  const input = `${b64urlEncode(JSON.stringify(header))}.${b64urlEncode(JSON.stringify(payload))}`;
  const pem = PRIVATE_KEY.replace(/\\n/g, "\n").replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input)));
  const jwt = `${input}.${b64urlEncode(sig)}`;
  cachedToken = { jwt, exp: now + 1800 };
  return jwt;
}

export interface SubscriptionState {
  originalTransactionId: string;
  productId: string;
  status: "active" | "grace_period" | "expired" | "revoked";
  expiresAt: string | null;
  willRenew: boolean | null;
  appAccountToken: string | null;
  environment: "Production" | "Sandbox";
}

// Apple status codes: 1 active, 2 expired, 3 billing retry, 4 grace period, 5 revoked.
function mapStatus(code: number, expiresMs: number | null): SubscriptionState["status"] {
  if (code === 1) return "active";
  if (code === 4) return "grace_period";
  if (code === 5) return "revoked";
  if (code === 3) return expiresMs && expiresMs > Date.now() ? "grace_period" : "expired";
  return "expired";
}

/**
 * Fetch the current state of the subscription group containing this transaction.
 * Tries Production first, then Sandbox (TestFlight and review purchases are Sandbox).
 * Returns null if Apple doesn't know the transaction in either environment.
 */
export async function fetchSubscriptionState(transactionId: string): Promise<SubscriptionState | null> {
  if (!/^\d{1,32}$/.test(transactionId)) return null;
  const token = await apiToken();
  for (const env of ["Production", "Sandbox"] as const) {
    const res = await fetch(`${HOSTS[env]}/inApps/v1/subscriptions/${transactionId}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (res.status === 404) continue;
    if (!res.ok) throw new Error(`App Store API ${env} ${res.status}: ${await res.text()}`);
    const body = await res.json();
    if (body.bundleId && body.bundleId !== BUNDLE_ID) return null;
    // Pick the latest transaction across our subscription products (they share one group).
    let best: SubscriptionState | null = null;
    let bestExp = -1;
    for (const group of body.data ?? []) {
      for (const last of group.lastTransactions ?? []) {
        const tx = decodeJwsPayload(last.signedTransactionInfo);
        if (!SUBSCRIPTION_PRODUCTS.has(tx.productId)) continue;
        const renewal = last.signedRenewalInfo ? decodeJwsPayload(last.signedRenewalInfo) : null;
        const exp = typeof tx.expiresDate === "number" ? tx.expiresDate : null;
        if ((exp ?? 0) > bestExp) {
          bestExp = exp ?? 0;
          best = {
            originalTransactionId: String(tx.originalTransactionId ?? last.originalTransactionId),
            productId: tx.productId,
            status: tx.revocationDate ? "revoked" : mapStatus(last.status, exp),
            expiresAt: exp ? new Date(exp).toISOString() : null,
            willRenew: renewal ? renewal.autoRenewStatus === 1 : null,
            appAccountToken: tx.appAccountToken ?? null,
            environment: env,
          };
        }
      }
    }
    return best;
  }
  return null;
}
