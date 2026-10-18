import { describe, expect, it } from 'vitest';
import { CARDS } from './cards';
import { SoloGame } from './game';
import type { Scheduler } from './game';
import { analyzeAllHands, checkWin, matchHand, selectBestTargetHand } from './handMatcher';
import { createFullSet, makeTile } from './tiles';
import { CharlestonPhase } from './types';
import type { NMJLHand, Suit, Tile } from './types';

/** Deterministic manual scheduler so tests drive time explicitly. */
class FakeScheduler implements Scheduler {
  private q: { at: number; fn: () => void; id: number }[] = [];
  private now = 0;
  private seq = 0;
  setTimeout(fn: () => void, ms: number) { const id = ++this.seq; this.q.push({ at: this.now + ms, fn, id }); return id; }
  clearTimeout(h: unknown) { this.q = this.q.filter((t) => t.id !== h); }
  get pending() { return this.q.length; }
  /** Run the next timer; returns false when idle. */
  step(): boolean {
    if (!this.q.length) return false;
    this.q.sort((a, b) => a.at - b.at || a.id - b.id);
    const t = this.q.shift()!;
    this.now = t.at;
    t.fn();
    return true;
  }
}

function seeded(seed: number) {
  let x = seed >>> 0 || 1;
  return () => { x ^= x << 13; x >>>= 0; x ^= x >>> 17; x ^= x << 5; x >>>= 0; return x / 0x100000000; };
}

const totalTiles = (g: SoloGame) => {
  const s = g.getState();
  return s.wall.length + s.discardPile.length
    + s.players.reduce((n, p) => n + p.hand.length + p.exposedSets.flat().length, 0)
    + Object.values(s.pendingPasses).flat().length;
};

/** Build concrete tiles that satisfy a hand pattern (first valid assignment, no jokers). */
function tilesForHand(h: NMJLHand): Tile[] | null {
  const suits: Suit[] = ['Bamboo', 'Character', 'Dot'];
  const slots = [...new Set(h.groups.flatMap((g) => g.tile.k === 'anySuit' || g.tile.k === 'matchingDragon' ? [g.tile.slot] : g.tile.k === 'anyValueAnySuit' ? [g.tile.suitSlot] : []))];
  const perms: Record<number, Suit>[] = [];
  const rec = (i: number, cur: Record<number, Suit>) => {
    if (i === slots.length) { perms.push({ ...cur }); return; }
    for (const s of suits) { if (h.requireUniqueSuits && Object.values(cur).includes(s)) continue; cur[slots[i]] = s; rec(i + 1, cur); }
  };
  rec(0, {});
  for (const sa of perms) {
    const out: Tile[] = [];
    for (const g of h.groups) {
      const t = g.tile;
      for (let c = 0; c < g.count; c++) {
        switch (t.k) {
          case 'numbered': out.push(makeTile(t.suit, t.value)); break;
          case 'anySuit': out.push(makeTile(sa[t.slot], t.value)); break;
          case 'dragon': out.push(makeTile('Dragon', t.value)); break;
          case 'matchingDragon': out.push(makeTile('Dragon', sa[t.slot] === 'Bamboo' ? 2 : sa[t.slot] === 'Character' ? 1 : 3)); break;
          case 'wind': out.push(makeTile('Wind', t.value)); break;
          case 'flower': out.push(makeTile('Flower', 1 + (c % 8))); break;
          case 'anyWindSlot': out.push(makeTile('Wind', 1)); break;
          case 'anyDragonSlot': out.push(makeTile('Dragon', 1)); break;
          case 'anyValueAnySuit': out.push(makeTile(sa[t.suitSlot], t.allowedValues[0])); break;
        }
      }
    }
    if (matchHand(out, h)) return out;
  }
  return null;
}

describe('tiles', () => {
  it('full set has 152 tiles with the right composition', () => {
    const set = createFullSet();
    expect(set.length).toBe(152);
    expect(set.filter((t) => t.suit === 'Joker').length).toBe(8);
    expect(set.filter((t) => t.suit === 'Flower').length).toBe(8);
    expect(new Set(set.map((t) => t.id)).size).toBe(152);
  });
});

describe('card data', () => {
  it('matches the iOS card counts', () => {
    expect(CARDS['2025'].hands.length).toBe(82);
    expect(CARDS['2026'].hands.length).toBe(92);
  });

  it('every hand on both cards totals 14 tiles', () => {
    for (const card of Object.values(CARDS)) for (const h of card.hands) {
      expect(h.groups.reduce((s, g) => s + g.count, 0), h.id).toBe(14);
    }
  });

  it('every hand is satisfiable and recognised by checkWin', () => {
    for (const card of Object.values(CARDS)) for (const h of card.hands) {
      const tiles = tilesForHand(h);
      expect(tiles, `no concrete tiles for ${h.id}`).not.toBeNull();
      expect(checkWin(tiles!, [], card), h.id).not.toBeNull();
    }
  });
});

describe('hand matcher', () => {
  const card = CARDS['2026'];
  it('jokers substitute in groups of 3+ but not in pairs/singles', () => {
    const h = card.hands.find((x) => x.groups.some((g) => g.count === 2) && x.groups.some((g) => g.count >= 3))!;
    const tiles = tilesForHand(h)!;
    // Replace one tile from a 3+ group with a joker → still wins.
    const bigIdx = (() => { let i = 0; for (const g of h.groups) { if (g.count >= 3 && g.tile.k !== 'flower') return i; i += g.count; } return -1; })();
    const withJoker = tiles.slice(); withJoker[bigIdx] = makeTile('Joker', 1);
    expect(matchHand(withJoker, h)).toBe(true);
    // Replace a pair tile with a joker → no longer this hand.
    const pairIdx = (() => { let i = 0; for (const g of h.groups) { if (g.count === 2) return i; i += g.count; } return -1; })();
    const badJoker = tiles.slice(); badJoker[pairIdx] = makeTile('Joker', 1);
    expect(matchHand(badJoker, h)).toBe(false);
  });

  it('concealed hands cannot win with exposures', () => {
    const h = card.hands.find((x) => x.concealed)!;
    const tiles = tilesForHand(h)!;
    expect(checkWin(tiles.slice(3), [tiles.slice(0, 3)], { year: '2026', hands: [h] })).toBeNull();
  });

  it('analysis and target selection run on a random 13', () => {
    const hand = createFullSet().slice(0, 13);
    expect(selectBestTargetHand(hand, card)).not.toBeNull();
    const a = analyzeAllHands(hand, [], card);
    expect(a.length).toBe(card.hands.length);
    expect(a[0].tilesNeeded).toBeLessThanOrEqual(a[a.length - 1].tilesNeeded);
  });
});

describe('solo game (ported iOS tests)', () => {
  const mk = (seed = 1) => { const sch = new FakeScheduler(); return { g: new SoloGame({ scheduler: sch, rng: seeded(seed), speed: 0 }), sch }; };

  it('deals 13 to each of 4 players, 100 left in the wall, bots have targets', () => {
    const { g } = mk();
    const s = g.getState();
    expect(s.players.map((p) => p.seat)).toEqual(['East', 'South', 'West', 'North']);
    expect(s.players.map((p) => p.name).slice(1)).toEqual(['Lily', 'Rose', 'Daisy']);
    s.players.forEach((p) => expect(p.hand.length).toBe(13));
    expect(s.wall.length).toBe(100);
    s.players.forEach((p) => expect(p.targetHand !== null).toBe(p.isBot));
    expect(s.status).toBe('charleston');
    expect(s.charlestonPhase).toBe(CharlestonPhase.FirstRight);
  });

  it('caps Charleston selection at three and toggles off', () => {
    const { g } = mk();
    const ids = g.getState().players[0].hand.map((t) => t.id);
    ids.slice(0, 5).forEach((id) => g.toggleCharlestonSelection(id));
    expect(g.getState().charlestonSelectedIds.length).toBe(3);
    g.toggleCharlestonSelection(ids[0]);
    expect(g.getState().charlestonSelectedIds).toEqual([ids[1], ids[2]]);
  });

  it('first pass moves the human tiles right and advances phase', () => {
    const { g } = mk();
    const passed = g.getState().players[0].hand.slice(0, 3).map((t) => t.id);
    passed.forEach((id) => g.toggleCharlestonSelection(id));
    g.confirmCharlestonPass();
    const s = g.getState();
    expect(s.charlestonPhase).toBe(CharlestonPhase.FirstAcross);
    const southIds = s.players[1].hand.map((t) => t.id);
    passed.forEach((id) => expect(southIds).toContain(id));
    s.players.forEach((p) => expect(p.hand.length).toBe(13));
  });

  it('second Charleston reverses direction (first pass of it goes left)', () => {
    const { g } = mk();
    const pass = () => { g.getState().players[0].hand.slice(0, 3).forEach((t) => g.toggleCharlestonSelection(t.id)); g.confirmCharlestonPass(); };
    pass(); pass(); pass();
    expect(g.getState().showStopCharlestonOption).toBe(true);
    expect(g.canStopCharleston()).toBe(true);
    const passed = g.getState().players[0].hand.slice(0, 3).map((t) => t.id);
    passed.forEach((id) => g.toggleCharlestonSelection(id));
    g.confirmCharlestonPass();
    const northIds = g.getState().players[3].hand.map((t) => t.id);
    passed.forEach((id) => expect(northIds).toContain(id));
  });

  it('stopping early and a zero courtesy both start play', () => {
    const a = mk().g;
    for (let i = 0; i < 3; i++) { a.getState().players[0].hand.slice(0, 3).forEach((t) => a.toggleCharlestonSelection(t.id)); a.confirmCharlestonPass(); }
    a.stopCharlestonEarly();
    expect(a.getState().status).toBe('playing');

    const b = mk().g;
    for (let i = 0; i < 6; i++) { b.getState().players[0].hand.slice(0, 3).forEach((t) => b.toggleCharlestonSelection(t.id)); b.confirmCharlestonPass(); }
    expect(b.getState().showCourtesyOptions).toBe(true);
    b.selectCourtesyCount(0);
    expect(b.getState().status).toBe('playing');
  });

  it('courtesy pass with tiles runs bots in sequence and conserves tiles', () => {
    const { g, sch } = mk(7);
    for (let i = 0; i < 6; i++) { g.getState().players[0].hand.slice(0, 3).forEach((t) => g.toggleCharlestonSelection(t.id)); g.confirmCharlestonPass(); }
    g.selectCourtesyCount(2);
    g.getState().players[0].hand.slice(0, 2).forEach((t) => g.toggleCharlestonSelection(t.id));
    g.confirmCharlestonPass();
    expect(totalTiles(g)).toBe(152);
    while (g.getState().status === 'charleston' && sch.step()) { /* run bots */ }
    expect(g.getState().status).toBe('playing');
    g.getState().players.forEach((p) => expect(p.hand.length).toBe(13));
    expect(totalTiles(g)).toBe(152);
  });
});

describe('solo game soak', () => {
  /** Auto-pilot the human: random Charleston, draw, random discard, skip/accept calls, declare when winning. */
  function playOut(seed: number) {
    const rng = seeded(seed);
    const sch = new FakeScheduler();
    const g = new SoloGame({ scheduler: sch, rng, speed: 0, cardYear: seed % 2 ? '2025' : '2026' });
    let guard = 0;
    while (g.getState().status !== 'completed') {
      if (++guard > 20000) throw new Error(`seed ${seed}: game did not finish`);
      const s = g.getState();
      expect(totalTiles(g), `seed ${seed} conservation`).toBe(152);
      if (s.status === 'charleston') {
        if (s.showCourtesyOptions) { g.selectCourtesyCount(Math.floor(rng() * 4)); continue; }
        if (g.canStopCharleston() && rng() < 0.3) { g.stopCharlestonEarly(); continue; }
        if (s.pendingPasses[0]) { if (!sch.step()) throw new Error('courtesy stalled'); continue; }
        const need = g.requiredCharlestonCount();
        s.players[0].hand.slice(0, need).forEach((t) => g.toggleCharlestonSelection(t.id));
        g.confirmCharlestonPass();
        continue;
      }
      if (s.showCallTileSelection) {
        g.autoPickCallTiles();
        if (g.canConfirmCallSelection()) g.confirmCallSelection(); else g.cancelCallSelection();
        continue;
      }
      if (s.callAvailable) {
        if (s.availableCalls.includes('Mahjong!')) { g.callTile('Mahjong!'); continue; }
        if (rng() < 0.25) g.callBestAvailable(); else g.dismissCallOptions();
        continue;
      }
      if (g.canDrawTile()) { g.drawTile(); continue; }
      if (s.currentPlayerIndex === 0 && s.hasDrawnThisTurn) {
        const before = g.getState().status;
        g.declareMahjong();
        if (g.getState().status === 'completed' || before === 'completed') continue;
        const hand = g.getState().players[0].hand;
        const nonJ = hand.filter((t) => t.suit !== 'Joker');
        const pick = (nonJ.length ? nonJ : hand)[Math.floor(rng() * (nonJ.length || hand.length))];
        g.selectTile(pick.id);
        g.discardSelectedTile();
        continue;
      }
      if (!sch.step()) {
        throw new Error(`seed ${seed}: stalled — turn=${s.currentPlayerIndex} drawn=${s.hasDrawnThisTurn} msg="${s.gameMessage}" window=${g.isCallWindowOpen(s)}`);
      }
    }
    const s = g.getState();
    expect(totalTiles(g)).toBe(152);
    if (!s.isWallGame) {
      const w = s.players[s.winnerIndex];
      expect(checkWin(w.hand, w.exposedSets, CARDS[s.cardYear])).not.toBeNull();
    }
    return s;
  }

  it('300 seeded games all finish with tiles conserved and valid winners', () => {
    let wins = 0; let walls = 0;
    for (let seed = 1; seed <= 300; seed++) {
      const s = playOut(seed);
      if (s.isWallGame) walls++; else wins++;
    }
    expect(wins + walls).toBe(300);
    // Bots should actually win some games against a random human.
    expect(wins).toBeGreaterThan(10);
  }, 120_000);
});
