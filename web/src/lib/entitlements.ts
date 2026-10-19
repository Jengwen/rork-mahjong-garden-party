// Subscription access shared across iOS (App Store) and web (Stripe).
// Rows live in `user_entitlements`, written only by server-side edge functions.
import { supabase } from './supabase';

export interface Entitlement {
  source: 'app_store' | 'stripe';
  product_id: string | null;
  status: string;
  expires_at: string | null;
  will_renew: boolean | null;
}

export interface Access {
  active: boolean;
  entitlements: Entitlement[];
  /** True when the table/function isn't deployed yet — lets the UI explain instead of just locking. */
  unavailable?: boolean;
}

export function isActive(e: Entitlement, now = Date.now()) {
  if (!['active', 'trialing', 'grace_period', 'canceled_pending'].includes(e.status)) return false;
  return !e.expires_at || new Date(e.expires_at).getTime() > now;
}

export async function fetchAccess(userId: string): Promise<Access> {
  const { data, error } = await supabase.from('user_entitlements')
    .select('source,product_id,status,expires_at,will_renew').eq('user_id', userId);
  if (error) {
    if (error.code === '42P01' || error.code === 'PGRST205') return { active: false, entitlements: [], unavailable: true };
    throw error;
  }
  const entitlements = (data ?? []) as Entitlement[];
  return { active: entitlements.some((e) => isActive(e)), entitlements };
}

export type Plan = 'monthly' | 'annual';

export async function startCheckout(plan: Plan): Promise<void> {
  const base = `${window.location.origin}${window.location.pathname}`;
  const { data, error } = await supabase.functions.invoke('stripe-checkout', {
    body: { plan, success_url: `${base}?checkout=success`, cancel_url: `${base}?checkout=cancel` },
  });
  if (error) throw error;
  if (!data?.url) throw new Error(data?.error ?? 'Checkout is not available right now.');
  window.location.assign(data.url);
}

export async function openBillingPortal(): Promise<void> {
  const base = `${window.location.origin}${window.location.pathname}`;
  const { data, error } = await supabase.functions.invoke('stripe-portal', { body: { return_url: base } });
  if (error) throw error;
  if (!data?.url) throw new Error(data?.error ?? 'Billing portal unavailable.');
  window.location.assign(data.url);
}
