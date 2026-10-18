import { useEffect, useState } from 'react';
import { Modal } from '../components/Modal';
import { startCheckout } from '../lib/entitlements';
import type { Access, Plan } from '../lib/entitlements';

// Same plans and pricing as the iOS PaywallView / App Store products
// (mgg_monthly $1.99, mgg_annual $19.99, 7-day free trial on both).

export function Paywall({ access, onClose, onRefresh, checkoutReturn }: {
  access: Access; onClose: () => void; onRefresh: () => Promise<void>; checkoutReturn: 'success' | 'cancel' | null;
}) {
  const [plan, setPlan] = useState<Plan>('annual');
  const [busy, setBusy] = useState(false);
  const [checking, setChecking] = useState(checkoutReturn === 'success');
  const [error, setError] = useState<string | null>(null);

  // After returning from Stripe the webhook can take a few seconds — poll briefly.
  useEffect(() => {
    if (checkoutReturn !== 'success' || access.active) { setChecking(false); return; }
    let n = 0;
    const id = setInterval(async () => {
      n++;
      await onRefresh();
      if (n >= 10) { clearInterval(id); setChecking(false); }
    }, 2000);
    return () => clearInterval(id);
  }, [checkoutReturn, access.active, onRefresh]);

  async function buy() {
    setBusy(true); setError(null);
    try { await startCheckout(plan); } catch (e) {
      setError(e instanceof Error ? e.message : 'Checkout is unavailable right now.');
      setBusy(false);
    }
  }

  async function recheck() {
    setBusy(true);
    await onRefresh();
    setBusy(false);
  }

  if (access.active) {
    return (
      <Modal title="You’re all set 🌷" onClose={onClose}>
        <p style={{ margin: 0, lineHeight: 1.5 }}>Your membership is active on this account — on the web and on your iPhone.</p>
        <button className="btn btn-primary" onClick={onClose}>Let’s play</button>
      </Modal>
    );
  }

  return (
    <Modal title="Unlock Solo Practice" onClose={onClose}>
      {checking ? (
        <div className="row" style={{ padding: '10px 0' }}><div className="spinner" /><span>Confirming your subscription…</span></div>
      ) : (
        <>
          <ul className="perks">
            <li>Unlimited games against three AI opponents</li>
            <li>2025 and 2026 NMJL cards with hand suggestions</li>
            <li>One membership for iPhone and the web</li>
          </ul>
          <div className="plans">
            <button className={`plan${plan === 'monthly' ? ' on' : ''}`} onClick={() => setPlan('monthly')}>
              <span className="muted" style={{ fontWeight: 800, fontSize: 13 }}>Monthly</span>
              <b>$1.99</b><span className="muted" style={{ fontSize: 13 }}>per month</span>
            </button>
            <button className={`plan${plan === 'annual' ? ' on' : ''}`} onClick={() => setPlan('annual')}>
              <span className="tag">SAVE 16%</span>
              <span className="muted" style={{ fontWeight: 800, fontSize: 13 }}>Annual</span>
              <b>$19.99</b><span className="muted" style={{ fontSize: 13 }}>per year</span>
            </button>
          </div>
          <button className="btn btn-pink btn-lg" disabled={busy} onClick={buy}>{busy ? 'Opening checkout…' : 'Start 7-day free trial'}</button>
          <p className="muted" style={{ margin: 0, fontSize: 12, textAlign: 'center' }}>Cancel anytime. Secure checkout by Stripe.</p>
          {error && <div className="error">{error}</div>}
        </>
      )}
      <div className="sync-note">
        <span aria-hidden>📱</span>
        <span>Subscribed on iPhone? Open the app once while signed in to this account, then <button className="btn btn-quiet btn-sm" style={{ padding: '0 2px', textDecoration: 'underline' }} disabled={busy} onClick={recheck}>check again</button>.</span>
      </div>
      {access.unavailable && <div className="muted" style={{ fontSize: 12 }}>Subscriptions aren’t connected on the server yet.</div>}
    </Modal>
  );
}
