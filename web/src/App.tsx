import { useCallback, useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import type { CardYear } from './engine/types';
import { fetchAccess } from './lib/entitlements';
import type { Access } from './lib/entitlements';
import { DEFAULT_SETTINGS, ensureProfile, fetchProfile, recordGameResult } from './lib/profile';
import type { Profile } from './lib/profile';
import { supabase } from './lib/supabase';
import { AuthScreen, ResetPasswordScreen } from './screens/AuthScreen';
import { GameScreen } from './screens/GameScreen';
import type { FinishedGame } from './screens/GameScreen';
import { HomeScreen } from './screens/HomeScreen';

function readCheckoutParam(): 'success' | 'cancel' | null {
  const v = new URLSearchParams(window.location.search).get('checkout');
  if (v === 'success' || v === 'cancel') {
    window.history.replaceState(null, '', window.location.pathname);
    return v;
  }
  return null;
}

// Dev-only preview (`npm run dev`, then /?preview): renders screens with a sample
// profile and no network. `import.meta.env.DEV` is false in production builds, so
// this branch is removed entirely from the deployed bundle.
function PreviewApp() {
  const [playing, setPlaying] = useState<CardYear | null>(null);
  const [profile, setProfile] = useState<Profile>({
    user_id: 'preview', display_name: 'Jennifer', avatar_image: 'daffodil', email: 'preview@example.com',
    level: 4, xp: 820, total_wins: 23, total_games: 61, current_streak: 2, selected_theme_id: 'garden_party',
    unlocked_themes: ['garden_party'], unlocked_tile_sets: ['classic'],
    settings_data: { ...DEFAULT_SETTINGS },
  });
  const locked = new URLSearchParams(window.location.search).has('locked');
  const access: Access = { active: !locked, entitlements: locked ? [] : [{ source: 'app_store', product_id: 'mgg_annual', status: 'active', expires_at: null, will_renew: true }] };
  if (new URLSearchParams(window.location.search).has('auth')) return <AuthScreen />;
  if (playing) return <GameScreen playerName={profile.display_name} avatar={profile.avatar_image} cardYear={playing} settings={profile.settings_data} onFinished={() => {}} onExit={() => setPlaying(null)} speed={Number(new URLSearchParams(window.location.search).get('speed') ?? 1)} />;
  return <HomeScreen profile={profile} access={access} onProfile={setProfile} onRefreshAccess={async () => {}} onPlay={setPlaying} checkoutReturn={null} />;
}

export default function App() {
  if (import.meta.env.DEV && new URLSearchParams(window.location.search).has('preview')) return <PreviewApp />;
  return <RealApp />;
}

function RealApp() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [recovery, setRecovery] = useState(() => window.location.hash.includes('type=recovery'));
  const [profile, setProfile] = useState<Profile | null>(null);
  const [access, setAccess] = useState<Access>({ active: false, entitlements: [] });
  const [loadError, setLoadError] = useState<string | null>(null);
  const [playing, setPlaying] = useState<CardYear | null>(null);
  const [checkoutReturn] = useState(readCheckoutParam);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((event, sess) => {
      if (event === 'PASSWORD_RECOVERY') setRecovery(true);
      setSession(sess);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const userId = session?.user.id;

  const refreshAccess = useCallback(async () => {
    if (!userId) return;
    try { setAccess(await fetchAccess(userId)); } catch { /* keep last known */ }
  }, [userId]);

  const loadUser = useCallback(async () => {
    if (!session) return;
    setLoadError(null);
    try {
      const meta = session.user.user_metadata as { display_name?: string } | undefined;
      const [p] = await Promise.all([
        ensureProfile(session.user.id, session.user.email ?? '', meta?.display_name),
        refreshAccess(),
      ]);
      setProfile(p);
    } catch (e) {
      setLoadError(e instanceof Error ? e.message : 'Could not load your profile.');
    }
  }, [session, refreshAccess]);

  useEffect(() => {
    if (!userId) { setProfile(null); setPlaying(null); return; }
    loadUser();
  }, [userId, loadUser]);

  // Pick up games finished on the phone when the tab regains focus.
  useEffect(() => {
    if (!userId) return;
    const on = () => {
      if (document.visibilityState !== 'visible' || playing) return;
      fetchProfile(userId).then((p) => p && setProfile(p)).catch(() => {});
      refreshAccess();
    };
    document.addEventListener('visibilitychange', on);
    return () => document.removeEventListener('visibilitychange', on);
  }, [userId, playing, refreshAccess]);

  const onFinished = useCallback((g: FinishedGame) => {
    if (!userId) return;
    recordGameResult(userId, g.result, g.score, g.opponents)
      .then((p) => p && setProfile(p))
      .catch((e) => console.warn('Could not save result', e));
  }, [userId]);

  if (recovery && session) {
    return <ResetPasswordScreen onDone={() => { setRecovery(false); window.history.replaceState(null, '', window.location.pathname); }} />;
  }
  if (session === undefined) return <div className="page center" style={{ minHeight: '100vh' }}><div className="spinner" /></div>;
  if (!session) return <AuthScreen />;
  if (loadError) {
    return (
      <div className="page center garden-bg" style={{ minHeight: '100vh', gap: 12, padding: 16, textAlign: 'center' }}>
        <div className="error">{loadError}</div>
        <div className="row"><button className="btn btn-primary" onClick={loadUser}>Try again</button><button className="btn btn-ghost" onClick={() => supabase.auth.signOut()}>Sign out</button></div>
      </div>
    );
  }
  if (!profile) return <div className="page center" style={{ minHeight: '100vh' }}><div className="spinner" /></div>;

  if (playing && access.active) {
    return (
      <GameScreen
        playerName={profile.display_name}
        avatar={profile.avatar_image}
        cardYear={playing}
        settings={profile.settings_data}
        onFinished={onFinished}
        onExit={() => setPlaying(null)}
      />
    );
  }

  return (
    <HomeScreen
      profile={profile}
      access={access}
      onProfile={setProfile}
      onRefreshAccess={refreshAccess}
      onPlay={setPlaying}
      checkoutReturn={checkoutReturn}
    />
  );
}
