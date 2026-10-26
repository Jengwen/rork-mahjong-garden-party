import { useEffect, useState } from 'react';
import { Avatar } from '../components/Tile';
import { Modal } from '../components/Modal';
import { CardReference } from '../components/CardReference';
import { CARD_YEARS } from '../engine/cards';
import type { CardYear } from '../engine/types';
import type { Access } from '../lib/entitlements';
import { openBillingPortal } from '../lib/entitlements';
import { fetchRecentResults, xpForNextLevel } from '../lib/profile';
import { PRIVACY_POLICY_URL } from '../lib/links';
import type { GameResultRow, Profile } from '../lib/profile';
import { supabase } from '../lib/supabase';
import { Paywall } from './Paywall';

interface Props {
  profile: Profile;
  access: Access;
  onProfile: (p: Profile) => void;
  onRefreshAccess: () => Promise<void>;
  onPlay: (year: CardYear) => void;
  onOpenProfile: () => void;
  onOpenLearn: () => void;
  checkoutReturn: 'success' | 'cancel' | null;
}

function timeAgo(iso: string) {
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

export function HomeScreen({ profile, access, onRefreshAccess, onPlay, onOpenProfile, onOpenLearn, checkoutReturn }: Props) {
  const [year, setYear] = useState<CardYear>(() => (localStorageGet('mgp_card_year') as CardYear) || '2026');
  const [results, setResults] = useState<GameResultRow[] | null>(null);
  const [paywall, setPaywall] = useState(false);
  const [showCard, setShowCard] = useState(false);

  useEffect(() => {
    fetchRecentResults(profile.user_id, 10).then(setResults).catch(() => setResults([]));
  }, [profile.user_id, profile.total_games]);

  useEffect(() => { if (checkoutReturn === 'success') setPaywall(true); }, [checkoutReturn]);

  const winRate = profile.total_games ? Math.round((profile.total_wins / profile.total_games) * 100) : 0;
  const xpPct = Math.min(100, (profile.xp / xpForNextLevel(profile.level)) * 100);
  const stripeSub = access.entitlements.find((e) => e.source === 'stripe');

  function choose(y: CardYear) { setYear(y); localStorageSet('mgp_card_year', y); }


  return (
    <div className="page garden-bg">
      <header className="topbar">
        <div className="brand"><img src="/icon-192.png" alt="" />Mahjong Garden Party</div>
        <div className="spacer" />
        <button className="btn btn-quiet btn-sm" onClick={onOpenLearn}>Learn</button>
        <button className="btn btn-quiet btn-sm" onClick={() => setShowCard(true)}>NMJL card</button>
        <button className="btn btn-quiet btn-sm" onClick={onOpenProfile}>Account</button>
        <button className="btn btn-ghost btn-sm" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </header>

      <main className="home">
        <div className="home-main">
          <section className="card hello">
            <Avatar name={profile.avatar_image} size={68} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <h2>Hi, {profile.display_name === 'Garden Guest' ? 'friend' : profile.display_name}!</h2>
              <div className="level-row">
                <span>Level {profile.level}</span>
                <div className="xpbar" role="progressbar" aria-valuenow={profile.xp} aria-valuemax={xpForNextLevel(profile.level)}><i style={{ width: `${xpPct}%` }} /></div>
                <span>{profile.xp} / {xpForNextLevel(profile.level)} XP</span>
              </div>
            </div>
            <button className="btn btn-ghost btn-sm" onClick={onOpenProfile}>Profile</button>
          </section>

          <section className="stats" aria-label="Your stats">
            <div className="stat"><b>{profile.total_games}</b><span>Games</span></div>
            <div className="stat"><b>{profile.total_wins}</b><span>Wins</span></div>
            <div className="stat"><b>{winRate}%</b><span>Win rate</span></div>
            <div className="stat"><b>{profile.current_streak}</b><span>Streak</span></div>
          </section>

          <section className="card play-card">
            <h2>Solo Practice</h2>
            <p>Play a full NMJL hand against Lily, Rose and Daisy — Charleston, calls, joker swaps and all. Results count toward your stats on every device.</p>
            <div className="chip-row">
              <span style={{ fontSize: 13, fontWeight: 800, opacity: .85 }}>Card</span>
              {CARD_YEARS.map((y) => <button key={y} className={`chip${year === y ? ' on' : ''}`} onClick={() => choose(y)}>NMJL {y}</button>)}
            </div>
            {access.active
              ? <button className="btn btn-gold btn-lg" onClick={() => onPlay(year)}>Start game ▸</button>
              : <button className="btn btn-gold btn-lg" onClick={() => setPaywall(true)}>🔒 Unlock to play</button>}
          </section>

          <button className="card learn-card" onClick={onOpenLearn}>
            <span className="video-ico" aria-hidden="true"><svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M2 5.5c2.5-1.3 6-1.3 10 .8 4-2.1 7.5-2.1 10-.8v13c-2.5-1.3-6-1.3-10 .8-4-2.1-7.5-2.1-10-.8z" /><path d="M12 6.3v13" /></svg></span>
            <span style={{ flex: 1 }}><b>Learn to Play</b><span className="muted" style={{ display: 'block', fontSize: 14 }}>Videos, tips and a guide to every tile</span></span>
            <span className="muted" aria-hidden="true">›</span>
          </button>

          <section className="card soon">
            <div><b>Live multiplayer</b><div className="muted" style={{ fontSize: 14 }}>Coming soon — we’re putting the finishing touches on it.</div></div>
          </section>
        </div>

        <aside className="home-side">
          <section className="card panel">
            <h3 className="section-title">Recent games</h3>
            {results === null && <div className="spinner" />}
            {results && results.length === 0 && <div className="muted" style={{ fontSize: 14 }}>No games yet. Your first win is waiting!</div>}
            {results?.map((r) => (
              <div key={r.id} className="match">
                <span className={`badge ${r.result}`}>{r.result.toUpperCase()}</span>
                <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>vs {r.opponent_names.join(', ')}</span>
                <span className="muted" style={{ fontSize: 12 }}>{timeAgo(r.played_at)}</span>
              </div>
            ))}
          </section>

          <section className="card panel">
            <h3 className="section-title">Membership</h3>
            {access.active ? (
              <div className="device-sync">
                <span style={{ fontSize: 22 }}>🌷</span>
                <span>
                  {access.entitlements.some((e) => e.source === 'app_store') ? 'Active through your iPhone subscription.' : 'Active subscription.'}
                  {stripeSub && <> <button className="btn btn-quiet btn-sm" style={{ padding: '2px 4px' }} onClick={() => openBillingPortal().catch((e) => alert(e.message))}>Manage billing</button></>}
                </span>
              </div>
            ) : (
              <div className="device-sync">
                <span style={{ fontSize: 22 }}>🔒</span>
                <span>Not subscribed yet. <button className="btn btn-quiet btn-sm" style={{ padding: '2px 4px' }} onClick={() => setPaywall(true)}>See plans</button></span>
              </div>
            )}
          </section>

          <div className="device-sync" style={{ padding: '0 6px' }}>
            <span style={{ fontSize: 20 }}>🔄</span>
            <span>Signed in as <b>{profile.email || 'you'}</b>. Stats and level sync with the iPhone app on this account.</span>
          </div>
        </aside>
      </main>
      <footer className="site-footer">
        <a href={PRIVACY_POLICY_URL} target="_blank" rel="noopener noreferrer">Privacy Policy</a>
        <span aria-hidden>·</span>
        <button className="linkish" onClick={onOpenProfile}>Profile &amp; Account</button>
      </footer>

      {paywall && <Paywall access={access} onClose={() => setPaywall(false)} onRefresh={onRefreshAccess} checkoutReturn={checkoutReturn} />}
      {showCard && <Modal title={`NMJL ${year} card`} wide onClose={() => setShowCard(false)}><CardReference year={year} /></Modal>}
    </div>
  );
}

function localStorageGet(k: string) { try { return localStorage.getItem(k); } catch { return null; } }
function localStorageSet(k: string, v: string) { try { localStorage.setItem(k, v); } catch { /* private mode */ } }
