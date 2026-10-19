import { useState } from 'react';
import type { FormEvent } from 'react';
import { WEB_RESET_REDIRECT, supabase } from '../lib/supabase';
import { ensureProfile } from '../lib/profile';
import { PRIVACY_POLICY_URL } from '../lib/links';

type Mode = 'signin' | 'signup' | 'forgot';

export function AuthScreen() {
  const [mode, setMode] = useState<Mode>('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(() => {
    const params = new URLSearchParams(window.location.search);
    if (!params.has('deleted')) return null;
    window.history.replaceState(null, '', window.location.pathname);
    return 'Your account has been deleted.';
  });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true); setError(null); setNotice(null);
    try {
      if (mode === 'signin') {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
        if (error) throw error;
      } else if (mode === 'signup') {
        if (password.length < 6) throw new Error('Password must be at least 6 characters.');
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(), password, options: { data: { display_name: name.trim() } },
        });
        if (error) throw error;
        if (data.session && data.user) await ensureProfile(data.user.id, email.trim(), name);
        else setNotice('Check your email to confirm your account, then sign in.');
      } else {
        const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: WEB_RESET_REDIRECT });
        if (error) throw error;
        setNotice('If that email has an account, a reset link is on its way.');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="page garden-bg">
      <div className="auth-wrap">
        <div className="auth-art">
          <img className="logo" src="/img/logo.webp" alt="Mahjong Garden Party" />
          <p className="tagline">American Mahjong on the NMJL card — now on your computer, too.</p>
        </div>
        <div className="auth-form-side">
          <form className="auth-card" onSubmit={submit}>
            <h1>{mode === 'signup' ? 'Join the party' : mode === 'forgot' ? 'Reset password' : 'Welcome back'}</h1>
            {mode !== 'forgot' && (
              <div className="tabs" role="tablist">
                <button type="button" className={mode === 'signin' ? 'on' : ''} onClick={() => { setMode('signin'); setError(null); }}>Sign in</button>
                <button type="button" className={mode === 'signup' ? 'on' : ''} onClick={() => { setMode('signup'); setError(null); }}>Create account</button>
              </div>
            )}
            {mode === 'signup' && (
              <div className="field">
                <label htmlFor="name">Display name</label>
                <input id="name" className="input" value={name} onChange={(e) => setName(e.target.value)} placeholder="What should we call you?" autoComplete="nickname" />
              </div>
            )}
            <div className="field">
              <label htmlFor="email">Email</label>
              <input id="email" className="input" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" />
            </div>
            {mode !== 'forgot' && (
              <div className="field">
                <label htmlFor="pw">Password</label>
                <input id="pw" className="input" type="password" required value={password} onChange={(e) => setPassword(e.target.value)} autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} />
              </div>
            )}
            {error && <div className="error" role="alert">{error}</div>}
            {notice && <div className="notice" role="status">{notice}</div>}
            <button className="btn btn-primary btn-lg" disabled={busy}>
              {busy ? 'One moment…' : mode === 'signup' ? 'Create account' : mode === 'forgot' ? 'Send reset link' : 'Sign in'}
            </button>
            {mode === 'signin' && <button type="button" className="btn btn-quiet" onClick={() => { setMode('forgot'); setError(null); }}>Forgot password?</button>}
            {mode === 'forgot' && <button type="button" className="btn btn-quiet" onClick={() => setMode('signin')}>Back to sign in</button>}
            <div className="sync-note">
              <span aria-hidden>📱</span>
              <span>Already play on iPhone? Sign in with the <b>same email</b> — your level, stats and subscription come with you.</span>
            </div>
            <p className="legal">
              {mode === 'signup' ? 'By creating an account you agree to our ' : 'See our '}
              <a href={PRIVACY_POLICY_URL} target="_blank" rel="noopener noreferrer">Privacy Policy</a>.
            </p>
          </form>
        </div>
      </div>
    </div>
  );
}

export function ResetPasswordScreen({ onDone }: { onDone: () => void }) {
  const [pw, setPw] = useState('');
  const [pw2, setPw2] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (pw.length < 6) { setError('Password must be at least 6 characters.'); return; }
    if (pw !== pw2) { setError('Passwords don’t match.'); return; }
    setBusy(true); setError(null);
    const { error } = await supabase.auth.updateUser({ password: pw });
    setBusy(false);
    if (error) setError(error.message); else onDone();
  }

  return (
    <div className="page garden-bg center" style={{ minHeight: '100vh', padding: 16 }}>
      <form className="card auth-card" style={{ padding: 28 }} onSubmit={submit}>
        <h1>Choose a new password</h1>
        <div className="field"><label htmlFor="np">New password</label><input id="np" className="input" type="password" value={pw} onChange={(e) => setPw(e.target.value)} autoComplete="new-password" /></div>
        <div className="field"><label htmlFor="np2">Confirm password</label><input id="np2" className="input" type="password" value={pw2} onChange={(e) => setPw2(e.target.value)} autoComplete="new-password" /></div>
        {error && <div className="error" role="alert">{error}</div>}
        <button className="btn btn-primary btn-lg" disabled={busy}>{busy ? 'Saving…' : 'Save password'}</button>
      </form>
    </div>
  );
}
