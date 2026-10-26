import { useMemo, useState } from 'react';
import { cardCategories, cardForYear, displayGroups } from '../engine/cards';
import { analyzeAllHands } from '../engine/handMatcher';
import type { CardYear, NMJLHand, Tile } from '../engine/types';

function HandRow({ hand }: { hand: NMJLHand }) {
  return (
    <div className="hand-groups">
      {displayGroups(hand).map((g, i) => <span key={i} className={`g${Math.min(g.slot, 3)}`}>{g.text}</span>)}
    </div>
  );
}

/** Browsable card, grouped by category. Colours mark suit slots like the printed card. */
export function CardReference({ year }: { year: CardYear }) {
  const card = cardForYear(year);
  const cats = cardCategories(card);
  const [cat, setCat] = useState(cats[0]);
  const hands = card.hands.filter((h) => h.category === cat);
  // Collapse a/b variants that share a name so the list reads like the printed card.
  const seen = new Set<string>();
  return (
    <>
      <div className="cat-tabs">{cats.map((c) => <button key={c} className={c === cat ? 'on' : ''} onClick={() => setCat(c)}>{c}</button>)}</div>
      <div>
        {hands.map((h) => {
          const first = !seen.has(h.name);
          seen.add(h.name);
          return (
            <div key={h.id} className="hand-line" style={first ? undefined : { borderTop: 'none', paddingTop: 0 }}>
              <span style={{ width: 92, fontWeight: 800, fontSize: 13, flex: 'none', visibility: first ? 'visible' : 'hidden' }}>{h.name.replace(`${h.category} `, '')}</span>
              <HandRow hand={h} />
              {h.concealed && <span className="conc">C</span>}
              <span className="pts">{h.points} pts</span>
            </div>
          );
        })}
      </div>
      <p className="muted" style={{ margin: 0, fontSize: 12 }}>Colours show matching suits (green, red, blue = three different suits). D = dragon, F = flower, 0 = white dragon (soap), C = concealed.</p>
    </>
  );
}

/**
 * Every hand still possible with the player's tiles, fewest tiles needed first.
 * Hands that are impossible (concealed, or clashing with exposed sets) are left out.
 * Number-run variants of one card line ("FF 11111 22 33333", "FF 22222 33 44444", …)
 * collapse to the player's closest one; distinct lines that share a name (a/b) stay.
 */
export function SuggestedHands({ hand, exposed, year }: { hand: Tile[]; exposed: Tile[][]; year: CardYear }) {
  const analysis = useMemo(() => {
    const seen = new Set<string>();
    return analyzeAllHands(hand, exposed, cardForYear(year))
      .map((a, i) => ({ a, i }))
      // Fewest tiles needed first; ties go to the higher-scoring hand, then card order.
      .sort((x, y) => x.a.tilesNeeded - y.a.tilesNeeded || y.a.hand.points - x.a.hand.points || x.i - y.i)
      .map((x) => x.a)
      .filter((a) => {
        const key = `${a.hand.name}|${a.hand.id.replace(/_\d+$/, '')}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
  }, [hand, exposed, year]);

  if (!analysis.length) return <p className="muted">No hands on the card fit your exposures.</p>;
  return (
    <div>
      <p className="muted" style={{ margin: '0 0 4px', fontSize: 13 }}>
        {analysis.length} possible hand{analysis.length === 1 ? '' : 's'}, fewest tiles needed first.
      </p>
      {analysis.map((a) => (
        <div key={a.hand.id} className="suggest">
          <div className="row">
            <b style={{ fontSize: 14 }}>{a.hand.name}</b>
            {a.hand.concealed && <span className="conc">C</span>}
            <span className="spacer" />
            <span className={`need-badge${a.tilesNeeded === 0 ? ' ready' : ''}`}>
              {a.tilesNeeded === 0 ? 'Ready!' : `Need ${a.tilesNeeded}`}
            </span>
            <span className="pts">{a.tilesHave}/{a.totalTiles} · {a.hand.points} pts</span>
          </div>
          <HandRow hand={a.hand} />
          <div className="meter"><i style={{ width: `${(a.tilesHave / a.totalTiles) * 100}%` }} /></div>
          {a.missing.length > 0 && <div className="need">Need: {a.missing.slice(0, 6).join(', ')}{a.missing.length > 6 ? '…' : ''}</div>}
        </div>
      ))}
    </div>
  );
}
