import { useEffect } from 'react';
import { Tile } from '../components/Tile';
import type { Suit, Tile as TileT } from '../engine/types';
import { supabase } from '../lib/supabase';

// Web version of the iOS "Learn to Play" screen (LearningResourcesView), plus the
// in-game Tile Guide (TileGuideView), so new players can study before a game.

interface Video { title: string; subtitle: string; url: string }

const VIDEOS: Video[] = [
  { title: 'How to Play American Mahjong', subtitle: 'Complete beginner’s guide', url: 'https://www.youtube.com/shorts/QXMz29oyIAs' },
  { title: 'American Mahjong Tiles Explained', subtitle: 'Get to know each tile in the set', url: 'https://www.youtube.com/shorts/BYhdlm0dUKQ' },
  { title: 'The Charleston Explained', subtitle: 'Tile passing strategy tips', url: 'https://www.youtube.com/shorts/8NJDs1-JzIg' },
  { title: 'Understanding the NMJL Card', subtitle: 'Learn to read the card of hands', url: 'https://www.youtube.com/shorts/eKE41OjGjSs' },
  { title: 'Calling, Exposing & Winning', subtitle: 'Pungs, kongs, quints & Mahjong', url: 'https://www.youtube.com/results?search_query=american+mahjong+calling+exposing+tutorial' },
  { title: 'Tips for New Players', subtitle: 'Common mistakes and how to improve', url: 'https://www.youtube.com/results?search_query=american+mahjong+tips+for+beginners' },
];

const TIPS = [
  'Start with Solo Practice to learn at your own pace.',
  'Use the NMJL card to study winning hands before each game.',
  'During the Charleston, pass tiles that don’t fit your target hand.',
  'Keep your options open early — don’t commit to one hand too soon.',
  'Watch what others discard to figure out what hands they’re building.',
];

const t = (suit: Suit, value: number): TileT => ({ id: `${suit}-${value}`, suit, value });
const range = (n: number) => Array.from({ length: n }, (_, i) => i + 1);

const SUITS: { title: string; suit: Suit; dragon: number; dragonLabel: string }[] = [
  { title: 'Dots', suit: 'Dot', dragon: 3, dragonLabel: 'White dragon (soap)' },
  { title: 'Bamboo', suit: 'Bamboo', dragon: 2, dragonLabel: 'Green dragon' },
  { title: 'Cracks', suit: 'Character', dragon: 1, dragonLabel: 'Red dragon' },
];

const SUMMARY: [string, number][] = [
  ['Dots + White Dragon', 40], ['Bamboo + Green Dragon', 40], ['Cracks + Red Dragon', 40],
  ['Winds', 16], ['Flowers', 8], ['Jokers', 8],
];

function PlayIcon() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true"><path d="M8 5.5v13l10.5-6.5z" fill="currentColor" /></svg>
  );
}

export function LearnScreen({ onBack }: { onBack: () => void }) {
  useEffect(() => { window.scrollTo(0, 0); }, []);
  return (
    <div className="page garden-bg">
      <header className="topbar">
        <button className="btn btn-ghost btn-sm" onClick={onBack}>← Home</button>
        <div className="spacer" />
        <div className="brand"><img src="/icon-192.png" alt="" />Mahjong Garden Party</div>
        <div className="spacer" />
        <button className="btn btn-ghost btn-sm" onClick={() => supabase.auth.signOut()}>Sign out</button>
      </header>

      <main className="learn">
        <div className="learn-head">
          <h1 className="account-title">Learn to Play</h1>
          <p className="muted">Everything you need to master American Mahjong, from the basics to advanced strategy.</p>
        </div>

        <section className="card panel">
          <h3 className="section-title">Video tutorials</h3>
          <div className="video-grid">
            {VIDEOS.map((v) => (
              <a key={v.title} className="video-card" href={v.url} target="_blank" rel="noopener noreferrer">
                <span className="video-ico"><PlayIcon /></span>
                <span className="video-text"><b>{v.title}</b><span>{v.subtitle}</span></span>
                <span className="video-go" aria-hidden="true">↗</span>
              </a>
            ))}
          </div>
        </section>

        <section className="card panel">
          <h3 className="section-title">Quick tips</h3>
          <ol className="tips">
            {TIPS.map((tip) => <li key={tip}>{tip}</li>)}
          </ol>
        </section>

        <section className="card panel">
          <h3 className="section-title">Tile guide</h3>
          <p className="muted" style={{ margin: '0 0 6px', fontSize: 14 }}>An American Mahjong set has 152 tiles. Each suit is paired with its own dragon.</p>

          {SUITS.map((s) => (
            <div key={s.suit} className="guide-row">
              <div className="guide-label"><b>{s.title}</b><span>4 of each number · 4 of each dragon</span></div>
              <div className="guide-tiles">
                {range(9).map((v) => <Tile key={v} tile={t(s.suit, v)} size={38} title={`${v} ${s.title}`} />)}
                <span className="guide-sep" />
                <Tile tile={t('Dragon', s.dragon)} size={38} title={s.dragonLabel} />
                <span className="guide-note">{s.dragonLabel}</span>
              </div>
            </div>
          ))}

          <div className="guide-row">
            <div className="guide-label"><b>Winds</b><span>East, South, West, North · 4 of each · 16 total</span></div>
            <div className="guide-tiles">
              {range(4).map((v) => <Tile key={v} tile={t('Wind', v)} size={38} />)}
            </div>
          </div>

          <div className="guide-row">
            <div className="guide-label"><b>Flowers</b><span>8 in the set · used in many hands</span></div>
            <div className="guide-tiles"><Tile tile={t('Flower', 1)} size={38} title="Flower" /></div>
          </div>

          <div className="guide-row">
            <div className="guide-label"><b>Jokers</b><span>8 in the set</span></div>
            <div className="guide-tiles">
              <Tile tile={t('Joker', 0)} size={38} title="Joker" />
              <span className="guide-note">Wild tile — stands in for any tile in a pung, kong, quint or sextet. Never in a pair or a single.</span>
            </div>
          </div>

          <table className="guide-table">
            <tbody>
              {SUMMARY.map(([label, n]) => <tr key={label}><td>{label}</td><td>{n}</td></tr>)}
              <tr className="total"><td>Total</td><td>152 tiles</td></tr>
            </tbody>
          </table>
        </section>
      </main>
    </div>
  );
}
