import { useState } from 'react';
import type { FormEvent } from 'react';
import { Avatar } from '../components/Tile';
import { Modal } from '../components/Modal';
import { isActive, openBillingPortal } from '../lib/entitlements';
import type { Access } from '../lib/entitlements';
import { PRIVACY_POLICY_URL } from '../lib/links';
import { updateProfile, xpForNextLevel } from '../lib/profile';
import type { Profile } from '../lib/profile';
import { supabase } from '../lib/supabase';

export const AVATARS = ['daffodil', 'daylily', 'dogwood', 'hydrangea', 'lily', 'pdaisy', 'peony', 'pink_flower', 'pink_rose', 'tulip'];

interface Props {
  profile: Profile;
  access: Access;
  onProfile: (p: Profile) => void;
  onBack: () => void;
  /** Dev preview: skip network calls. */
  preview?: boolean;
}

export function ProfileScreen({ profile, access, onProfile, onBack, preview }: Props) {
  return (
    <div className="page garden-bg">
      <header className="topbar">
        <button className="btn btn-ghost btn-sm" onClick={onBack}>← Home</button>
        <div className="spacer" />
        <div className="brand"><img src="/icon-192.png" alt="" />Mahjong Garden Party</div>
        <div className="spacer" />
        <button className="btn btn-ghost btn-sm" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </header>
      <main className="account">
        <h1 className="account-title">Profile &amp; Account</h1>
        <ProfileCard profile={profile} onProfile={onProfile} preview={preview} />
        <PasswordCard email={profile.email} preview={preview} />
        <MembershipCard access={access} />
        <section className="card panel">
          <h3 className="section-title">Legal</h3>
          <a className="link-row" href={PRIVACY_POLICY_URL} target="_blank" rel="noopener noreferrer">
            <span>Privacy Policy</span><span aria-hidden>↗</span>
          </a>
        </section>
        <DeleteCard profile={profile} access={access} preview={preview} />
      </main>
    </div>
  );
}

function ProfileCard({ profile, onProfile, preview }: { profile: Profile; onProfile: (p: Profile) => void; preview?: boolean }) {
  const [name, setName] = useState(profile.display_name);
  const [avatar, setAvatar] = useState(profile.avatar_image);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const dirty = name.trim() !== profile.display_name || avatar !== profile.avatar_image;

  async function save() {
    const trimmed = name.trim();
    if (!trimmed) { setMsg({ ok: false, text: 'Display name can’t be empty.' }); return; }
    setBusy(true); setMsg(null);
    try {
      onProfile(preview ? { ...profile, display_name: trimmed, avatar_image: avatar }
        : await updateProfile(profile.user_id, { display_name: trimmed, avatar_image: avatar }));
      setMsg({ ok: true, text: 'Saved. Your iPhone will show the change next time it opens.' });
    } catch (e) {
      setMsg({ ok: false, text: e instanceof Error ? e.message : 'Could not save.' });
    } finally { setBusy(false); }
  }

  const pct = Math.min(100, (profile.xp / xpForNextLevel(profile.level)) * 100);
  return (
    <section className="card panel account-section">
      <h3 className="section-title">Profile</h3>
      <div className="row" style={{ gap: 16 }}>
        <Avatar name={avatar} size={72} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <b style={{ fontSize: 18 }}>{profile.display_name}</b>
          <div className="level-row" style={{ marginTop: 4 }}>
            <span>Level {profile.level}</span>
            <div className="xpbar"><i style={{ width: `${pct}%` }} /></div>
          </div>
          <div className="muted" style={{ fontSize: 13, marginTop: 4 }}>{profile.total_games} games · {profile.total_wins} wins</div>
        </div>
      </div>
      <div className="field">
        <label htmlFor="pf-name">Display name</label>
        <input id="pf-name" className="input" value={name} maxLength={24} onChange={(e) => setName(e.target.value)} autoComplete="nickname" />
      </div>
      <div className="field">
        <label id="pf-avatar">Avatar</label>
        <div className="avatar-grid" role="radiogroup" aria-labelledby="pf-avatar">
          {AVATARS.map((a) => (
            <button key={a} role="radio" aria-checked={avatar === a} aria-label={a.replace('_', ' ')} className={`avatar-pick${avatar === a ? ' on' : ''}`} onClick={() => setAvatar(a)}>
              <Avatar name={a} size={52} />
            </button>
          ))}
        </div>
      </div>
      <div className="field">
        <label>Email</label>
        <div className="readonly">{profile.email || '—'}</div>
      </div>
      {msg && <div className={msg.ok ? 'notice' : 'error'} role="status">{msg.text}</div>}
      <button className="btn btn-primary" style={{ alignSelf: 'flex-start' }} disabled={!dirty || busy} onClick={save}>{busy ? 'Saving…' : 'Save changes'}</button>
    </section>
  );
}

function PasswordCard({ email, preview }: { email: string; preview?: boolean }) {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setMsg(null);
    if (next.length < 6) { setMsg({ ok: false, text: 'New password must be at least 6 characters.' }); return; }
    if (next !== confirm) { setMsg({ ok: false, text: 'New passwords don’t match.' }); return; }
    if (next === current) { setMsg({ ok: false, text: 'Choose a password different from your current one.' }); return; }
    setBusy(true);
    try {
      if (!preview) {
        // Re-check the current password first so someone at an unlocked computer can't change it.
        const { error: authErr } = await supabase.auth.signInWithPassword({ email, password: current });
        if (authErr) throw new Error('Your current password is incorrect.');
        const { error } = await supabase.auth.updateUser({ password: next });
        if (error) throw error;
      }
      setCurrent(''); setNext(''); setConfirm('');
      setMsg({ ok: true, text: 'Password updated. Use it next time you sign in on the web or iPhone.' });
    } catch (err) {
      setMsg({ ok: false, text: err instanceof Error ? err.message : 'Could not update password.' });
    } finally { setBusy(false); }
  }

  return (
    <form className="card panel account-section" onSubmit={submit}>
      <h3 className="section-title">Change password</h3>
      <input type="text" name="username" autoComplete="username" value={email} readOnly hidden />
      <div className="field"><label htmlFor="pw-cur">Current password</label><input id="pw-cur" className="input" type="password" required value={current} onChange={(e) => setCurrent(e.target.value)} autoComplete="current-password" /></div>
      <div className="two-col">
        <div className="field"><label htmlFor="pw-new">New password</label><input id="pw-new" className="input" type="password" required value={next} onChange={(e) => setNext(e.target.value)} autoComplete="new-password" /></div>
        <div className="field"><label htmlFor="pw-conf">Confirm new password</label><input id="pw-conf" className="input" type="password" required value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="new-password" /></div>
      </div>
      {msg && <div className={msg.ok ? 'notice' : 'error'} role="status">{msg.text}</div>}
      <button className="btn btn-primary" style={{ alignSelf: 'flex-start' }} disabled={busy || !current || !next || !confirm}>{busy ? 'Updating…' : 'Update password'}</button>
    </form>
  );
}

function MembershipCard({ access }: { access: Access }) {
  const active = access.entitlements.filter((e) => isActive(e));
  const apple = active.find((e) => e.source === 'app_store');
  const web = active.find((e) => e.source === 'stripe');
  const until = (iso: string | null) => (iso ? new Date(iso).toLocaleDateString(undefined, { month: 'long', day: 'numeric', year: 'numeric' }) : null);
  return (
    <section className="card panel account-section">
      <h3 className="section-title">Membership</h3>
      {!access.active && <p className="muted" style={{ margin: 0 }}>No active subscription.</p>}
      {apple && (
        <p style={{ margin: 0, lineHeight: 1.5 }}>
          Active through your <b>iPhone (App Store)</b> subscription{apple.expires_at ? <>, {apple.will_renew ? 'renews' : 'ends'} {until(apple.expires_at)}</> : null}.
          <br /><span className="muted" style={{ fontSize: 13 }}>Manage or cancel it on your iPhone in Settings → your name → Subscriptions.</span>
        </p>
      )}
      {web && (
        <>
          <p style={{ margin: 0, lineHeight: 1.5 }}>
            Active web subscription{web.status === 'trialing' ? ' (free trial)' : ''}{web.expires_at ? <>, {web.will_renew ? 'renews' : 'ends'} {until(web.expires_at)}</> : null}.
          </p>
          <button className="btn btn-ghost" style={{ alignSelf: 'flex-start' }} onClick={() => openBillingPortal().catch((e) => alert(e.message))}>Manage billing</button>
        </>
      )}
    </section>
  );
}

function DeleteCard({ profile, access, preview }: { profile: Profile; access: Access; preview?: boolean }) {
  const [open, setOpen] = useState(false);
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const activeWeb = access.entitlements.find((e) => e.source === 'stripe' && isActive(e) && e.will_renew !== false);
  const activeApple = access.entitlements.find((e) => e.source === 'app_store' && isActive(e) && e.will_renew !== false);

  async function remove() {
    setBusy(true); setError(null);
    try {
      if (preview) { setOpen(false); return; }
      const { error } = await supabase.functions.invoke('delete-account');
      if (error) throw error;
      await supabase.auth.signOut();
      window.location.replace(`${window.location.pathname}?deleted=1`);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not delete your account. Please try again.');
      setBusy(false);
    }
  }

  return (
    <section className="card panel account-section danger-zone">
      <h3 className="section-title" style={{ color: 'var(--danger)' }}>Delete account</h3>
      <p style={{ margin: 0, lineHeight: 1.5 }}>Permanently deletes your account on iPhone and the web: your profile, level, stats, game history, friends and messages. This can’t be undone.</p>
      <button className="btn btn-danger" style={{ alignSelf: 'flex-start' }} onClick={() => { setTyped(''); setError(null); setOpen(true); }}>Delete my account…</button>
      {open && (
        <Modal title="Delete your account?" onClose={() => !busy && setOpen(false)}>
          {activeWeb ? (
            <>
              <p style={{ margin: 0, lineHeight: 1.5 }}>You have an active web subscription. Cancel it first so you aren’t charged again, then come back to delete your account.</p>
              <div className="row"><button className="btn btn-ghost" onClick={() => setOpen(false)}>Close</button><span className="spacer" /><button className="btn btn-primary" onClick={() => openBillingPortal().catch((e) => setError(e.message))}>Manage billing</button></div>
              {error && <div className="error">{error}</div>}
            </>
          ) : (
            <>
              <p style={{ margin: 0, lineHeight: 1.5 }}>This permanently deletes <b>{profile.email || 'your account'}</b> and everything tied to it, on every device.</p>
              {activeApple && <div className="sync-note"><span aria-hidden>📱</span><span>Deleting your account <b>doesn’t cancel</b> your iPhone subscription. Cancel it on your iPhone in Settings → your name → Subscriptions.</span></div>}
              <div className="field">
                <label htmlFor="del-confirm">Type DELETE to confirm</label>
                <input id="del-confirm" className="input" value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" autoCapitalize="characters" />
              </div>
              {error && <div className="error" role="alert">{error}</div>}
              <div className="row"><button className="btn btn-ghost" disabled={busy} onClick={() => setOpen(false)}>Cancel</button><span className="spacer" /><button className="btn btn-danger" disabled={busy || typed.trim().toUpperCase() !== 'DELETE'} onClick={remove}>{busy ? 'Deleting…' : 'Delete forever'}</button></div>
            </>
          )}
        </Modal>
      )}
    </section>
  );
}
