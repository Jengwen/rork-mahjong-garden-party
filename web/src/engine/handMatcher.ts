// Port of ios/MahjongGardenParty/Services/HandMatcher.swift.
// Behaviour is kept identical to the iOS app; comments mark the few places
// that are JS-specific (caching, keys).
import { matchesForGrouping } from './tiles';
import { NUMBER_SUITS } from './types';
import type { CallType, HandGroup, NMJLCard, NMJLHand, Suit, Tile, TileSpec } from './types';

type SuitAssign = Map<number, Suit>;
type IntAssign = Map<number, number>;

interface Assignment { sa: SuitAssign; wa: IntAssign; da: IntAssign; va: IntAssign }

const key = (suit: Suit, value: number) => `${suit}:${value}`;

function collectSlots(groups: HandGroup[], isSuit: boolean): number[] {
  const s = new Set<number>();
  for (const g of groups) {
    const t = g.tile;
    if ((t.k === 'anySuit' || t.k === 'matchingDragon') && isSuit) s.add(t.slot);
    else if (t.k === 'anyValueAnySuit' && isSuit) s.add(t.suitSlot);
    else if (t.k === 'anyWindSlot' && !isSuit) s.add(t.slot);
  }
  return [...s];
}

function collectDragonSlots(groups: HandGroup[]): number[] {
  const s = new Set<number>();
  for (const g of groups) if (g.tile.k === 'anyDragonSlot') s.add(g.tile.slot);
  return [...s];
}

function collectValueSlots(groups: HandGroup[]): Map<number, number[]> {
  const m = new Map<number, number[]>();
  for (const g of groups) if (g.tile.k === 'anyValueAnySuit') m.set(g.tile.valueSlot, g.tile.allowedValues);
  return m;
}

function expand<V>(slots: number[], values: (slot: number) => V[]): Map<number, V>[] {
  let result: Map<number, V>[] = [new Map()];
  for (const slot of slots) {
    const next: Map<number, V>[] = [];
    for (const existing of result) {
      for (const v of values(slot)) {
        const copy = new Map(existing);
        copy.set(slot, v);
        next.push(copy);
      }
    }
    result = next;
  }
  return result;
}

// JS-specific: assignment lists depend only on the hand pattern, so cache them.
const assignmentCache = new Map<string, Assignment[]>();

function assignmentsFor(hand: NMJLHand): Assignment[] {
  const cached = assignmentCache.get(hand.id);
  if (cached) return cached;
  let suitPerms = expand(collectSlots(hand.groups, true), () => NUMBER_SUITS);
  if (hand.requireUniqueSuits) {
    suitPerms = suitPerms.filter((a) => new Set(a.values()).size === a.size);
  }
  const windPerms = expand(collectSlots(hand.groups, false), () => [1, 2, 3, 4]);
  const dragonPerms = expand(collectDragonSlots(hand.groups), () => [1, 2, 3]);
  const valueInfo = collectValueSlots(hand.groups);
  const valuePerms = expand([...valueInfo.keys()], (slot) => valueInfo.get(slot) ?? []);
  const out: Assignment[] = [];
  for (const sa of suitPerms) for (const wa of windPerms) for (const da of dragonPerms) for (const va of valuePerms) {
    out.push({ sa, wa, da, va });
  }
  assignmentCache.set(hand.id, out);
  return out;
}

const jokersAllowed = (g: HandGroup) => g.count >= 3;

interface ResolvedKey { suit: Suit; value: number; k: string }

function resolveTileSpec(spec: TileSpec, a: Assignment): ResolvedKey | null {
  const mk = (suit: Suit, value: number): ResolvedKey => ({ suit, value, k: key(suit, value) });
  switch (spec.k) {
    case 'numbered': return mk(spec.suit, spec.value);
    case 'anySuit': {
      const suit = a.sa.get(spec.slot);
      return suit ? mk(suit, spec.value) : null;
    }
    case 'dragon': return mk('Dragon', spec.value);
    case 'matchingDragon': {
      const suit = a.sa.get(spec.slot);
      if (suit === 'Bamboo') return mk('Dragon', 2);
      if (suit === 'Character') return mk('Dragon', 1);
      if (suit === 'Dot') return mk('Dragon', 3);
      return null;
    }
    case 'wind': return mk('Wind', spec.value);
    case 'flower': return null;
    case 'anyWindSlot': {
      const v = a.wa.get(spec.slot);
      return v ? mk('Wind', v) : null;
    }
    case 'anyDragonSlot': {
      const v = a.da.get(spec.slot);
      return v ? mk('Dragon', v) : null;
    }
    case 'anyValueAnySuit': {
      const suit = a.sa.get(spec.suitSlot);
      const v = a.va.get(spec.valueSlot);
      return suit && v ? mk(suit, v) : null;
    }
  }
}

interface Freq { freq: Map<string, number>; jokers: number; flowers: number }

function frequencies(tiles: Tile[]): Freq {
  const freq = new Map<string, number>();
  let jokers = 0;
  let flowers = 0;
  for (const t of tiles) {
    if (t.suit === 'Joker') jokers++;
    else if (t.suit === 'Flower') flowers++;
    else freq.set(key(t.suit, t.value), (freq.get(key(t.suit, t.value)) ?? 0) + 1);
  }
  return { freq, jokers, flowers };
}

function tryMatch(base: Freq, groups: HandGroup[], a: Assignment): boolean {
  const freq = new Map(base.freq);
  let flowerCount = base.flowers;
  let jokersNeeded = 0;
  for (const g of groups) {
    if (g.tile.k === 'flower') {
      const used = Math.min(flowerCount, g.count);
      const deficit = g.count - used;
      if (deficit > 0 && !jokersAllowed(g)) return false;
      flowerCount -= used;
      jokersNeeded += deficit;
      continue;
    }
    const r = resolveTileSpec(g.tile, a);
    if (!r) return false;
    const available = freq.get(r.k) ?? 0;
    const used = Math.min(available, g.count);
    const deficit = g.count - used;
    if (deficit > 0 && !jokersAllowed(g)) return false;
    freq.set(r.k, available - used);
    jokersNeeded += deficit;
  }
  return jokersNeeded <= base.jokers;
}

export function matchHand(tiles: Tile[], pattern: NMJLHand): boolean {
  const base = frequencies(tiles);
  for (const a of assignmentsFor(pattern)) {
    if (tryMatch(base, pattern.groups, a)) return true;
  }
  return false;
}

const totalTiles = (h: NMJLHand) => h.groups.reduce((s, g) => s + g.count, 0);

export function checkWin(hand: Tile[], exposedSets: Tile[][], card: NMJLCard): NMJLHand | null {
  const all = [...hand, ...exposedSets.flat()];
  const hasExposed = exposedSets.length > 0;
  for (const h of card.hands) {
    if (h.concealed && hasExposed) continue;
    if (all.length !== totalTiles(h)) continue;
    if (hasExposed && !exposedSetsCompatible(exposedSets, h)) continue;
    if (matchHand(all, h)) return h;
  }
  return null;
}

// MARK: - Call validation

function groupsNeedingTile(tile: Tile, target: NMJLHand): HandGroup[] {
  const out: HandGroup[] = [];
  for (const g of target.groups) {
    if (g.count < 3) continue;
    if (tileMatchesGroup(tile.suit, tile.value, g)) out.push(g);
  }
  return out;
}

export function tileMatchesGroup(suit: Suit, value: number, group: HandGroup): boolean {
  const t = group.tile;
  switch (t.k) {
    case 'numbered': return suit === t.suit && value === t.value;
    case 'anySuit': return value === t.value && NUMBER_SUITS.includes(suit);
    case 'dragon': return suit === 'Dragon' && value === t.value;
    case 'matchingDragon': return suit === 'Dragon';
    case 'wind': return suit === 'Wind' && value === t.value;
    case 'anyWindSlot': return suit === 'Wind';
    case 'anyDragonSlot': return suit === 'Dragon';
    case 'anyValueAnySuit': return NUMBER_SUITS.includes(suit) && t.allowedValues.includes(value);
    case 'flower': return suit === 'Flower';
  }
}

function basicCallCheck(tile: Tile, hand: Tile[]): CallType[] {
  const matchCount = hand.filter((t) => matchesForGrouping(t, tile)).length;
  const jokerCount = hand.filter((t) => t.suit === 'Joker').length;
  const calls: CallType[] = [];
  if (matchCount + jokerCount >= 2) calls.push('Pung');
  if (matchCount + jokerCount >= 3) calls.push('Kong');
  if (matchCount + jokerCount >= 4) calls.push('Quint');
  calls.push('Mahjong!');
  return calls;
}

export function canCallTileForExposure(
  tile: Tile, hand: Tile[], exposedSets: Tile[][], target: NMJLHand | null,
): CallType[] {
  if (tile.suit === 'Joker') return [];
  if (!target) return basicCallCheck(tile, hand);
  if (target.concealed) return [];

  const calls: CallType[] = [];
  const matchCount = hand.filter((t) => matchesForGrouping(t, tile)).length;
  const jokerCount = hand.filter((t) => t.suit === 'Joker').length;
  for (const g of groupsNeedingTile(tile, target)) {
    if (g.count === 3 && matchCount + jokerCount >= 2 && !calls.includes('Pung')) calls.push('Pung');
    if (g.count === 4 && matchCount + jokerCount >= 3 && !calls.includes('Kong')) calls.push('Kong');
    if (g.count >= 5 && matchCount + jokerCount >= g.count - 1 && !calls.includes('Quint')) calls.push('Quint');
  }
  if (checkWin([...hand, tile], exposedSets, { year: '2025', hands: [target] })) calls.push('Mahjong!');
  return calls;
}

export function canCallForMahjong(tile: Tile, hand: Tile[], exposedSets: Tile[][], card: NMJLCard): boolean {
  if (tile.suit === 'Joker') return false;
  return checkWin([...hand, tile], exposedSets, card) !== null;
}

// MARK: - Exposed-set compatibility

function exposedSetsCompatible(exposedSets: Tile[][], target: NMJLHand): boolean {
  const exposedKeys: { suit: Suit; value: number; count: number }[] = [];
  for (const set of exposedSets) {
    const rep = set.find((t) => t.suit !== 'Joker');
    if (!rep) continue;
    exposedKeys.push({ suit: rep.suit, value: rep.value, count: set.length });
  }
  for (const a of assignmentsFor(target)) {
    const used = new Array(target.groups.length).fill(false);
    if (matchExposed(exposedKeys, 0, target.groups, used, a)) return true;
  }
  return false;
}

function matchExposed(
  keys: { suit: Suit; value: number; count: number }[], idx: number, groups: HandGroup[], used: boolean[], a: Assignment,
): boolean {
  if (idx >= keys.length) return true;
  const ex = keys[idx];
  for (let i = 0; i < groups.length; i++) {
    if (used[i]) continue;
    const g = groups[i];
    if (g.count !== ex.count) continue;
    let ok = false;
    if (g.tile.k === 'flower') ok = ex.suit === 'Flower';
    else {
      const r = resolveTileSpec(g.tile, a);
      ok = !!r && r.suit === ex.suit && r.value === ex.value;
    }
    if (!ok) continue;
    used[i] = true;
    if (matchExposed(keys, idx + 1, groups, used, a)) return true;
    used[i] = false;
  }
  return false;
}

// MARK: - Suggested hands analysis

export interface HandAnalysis {
  hand: NMJLHand;
  tilesNeeded: number;
  tilesHave: number;
  totalTiles: number;
  missing: string[];
}

export function describeKey(suit: Suit, value: number): string {
  switch (suit) {
    case 'Bamboo': return `${value} Bam`;
    case 'Character': return `${value} Crak`;
    case 'Dot': return `${value} Dot`;
    case 'Wind': return ['East', 'South', 'West', 'North'][Math.max(0, Math.min(value - 1, 3))];
    case 'Dragon': return ['Red Dr', 'Green Dr', 'White Dr'][Math.max(0, Math.min(value - 1, 2))];
    case 'Flower': return 'Flower';
    case 'Joker': return 'Joker';
  }
}

function scoreAnalysis(base: Freq, groups: HandGroup[], a: Assignment): { have: number; missing: string[] } {
  const freq = new Map(base.freq);
  let flowerCount = base.flowers;
  let have = 0;
  const missing: string[] = [];
  const jokerCandidates: { desc: string; deficit: number }[] = [];
  for (const g of groups) {
    if (g.tile.k === 'flower') {
      const used = Math.min(flowerCount, g.count);
      have += used;
      flowerCount -= used;
      const deficit = g.count - used;
      if (deficit > 0) {
        if (jokersAllowed(g)) jokerCandidates.push({ desc: 'Flower', deficit });
        else missing.push(`${deficit}x Flower`);
      }
      continue;
    }
    const r = resolveTileSpec(g.tile, a);
    if (!r) { missing.push(`${g.count}x ?`); continue; }
    const available = freq.get(r.k) ?? 0;
    const used = Math.min(available, g.count);
    have += used;
    freq.set(r.k, available - used);
    const deficit = g.count - used;
    if (deficit > 0) {
      if (jokersAllowed(g)) jokerCandidates.push({ desc: describeKey(r.suit, r.value), deficit });
      else missing.push(`${deficit}x ${describeKey(r.suit, r.value)}`);
    }
  }
  let remaining = base.jokers;
  const unfilled: { desc: string; deficit: number }[] = [];
  for (const c of jokerCandidates) {
    const j = Math.min(remaining, c.deficit);
    have += j;
    remaining -= j;
    if (c.deficit - j > 0) unfilled.push({ desc: c.desc, deficit: c.deficit - j });
  }
  for (const u of unfilled) missing.push(`${u.deficit}x ${u.desc}`);
  return { have, missing };
}

export function analyzeAllHands(hand: Tile[], exposedSets: Tile[][], card: NMJLCard): HandAnalysis[] {
  const all = [...hand, ...exposedSets.flat()];
  const hasExposed = exposedSets.length > 0;
  const base = frequencies(all);
  const results: HandAnalysis[] = [];
  for (const h of card.hands) {
    if (hasExposed && (h.concealed || !exposedSetsCompatible(exposedSets, h))) continue;
    let bestHave = 0;
    let bestMissing: string[] = [];
    for (const a of assignmentsFor(h)) {
      const { have, missing } = scoreAnalysis(base, h.groups, a);
      if (have > bestHave) { bestHave = have; bestMissing = missing; }
    }
    const total = totalTiles(h);
    results.push({ hand: h, tilesNeeded: Math.max(total - bestHave, 0), tilesHave: bestHave, totalTiles: total, missing: bestMissing });
  }
  // Stable sort, matching Swift's sort on tilesNeeded.
  return results.map((r, i) => ({ r, i })).sort((x, y) => x.r.tilesNeeded - y.r.tilesNeeded || x.i - y.i).map((x) => x.r);
}

// MARK: - Bot target selection

function scoreAssignment(base: Freq, groups: HandGroup[], a: Assignment): number {
  const freq = new Map(base.freq);
  let flowerCount = base.flowers;
  let score = 0;
  for (const g of groups) {
    if (g.tile.k === 'flower') {
      const used = Math.min(flowerCount, g.count);
      score += used * 2;
      flowerCount -= used;
      continue;
    }
    const r = resolveTileSpec(g.tile, a);
    if (!r) continue;
    const available = freq.get(r.k) ?? 0;
    const used = Math.min(available, g.count);
    score += used * 2;
    freq.set(r.k, available - used);
  }
  return score + base.jokers;
}

function scoreHandFit(hand: Tile[], target: NMJLHand): number {
  const base = frequencies(hand);
  let best = 0;
  for (const a of assignmentsFor(target)) best = Math.max(best, scoreAssignment(base, target.groups, a));
  return best;
}

export function selectBestTargetHand(hand: Tile[], card: NMJLCard): NMJLHand | null {
  let best: NMJLHand | null = null;
  let bestScore = -1;
  for (const h of card.hands) {
    const s = scoreHandFit(hand, h);
    if (s > bestScore) { bestScore = s; best = h; }
  }
  return best;
}

// MARK: - Bot discard / Charleston picks

export function scoreTilesForTarget(hand: Tile[], target: NMJLHand): { index: number; score: number }[] {
  const base = frequencies(hand);
  let bestAssignment: Assignment | null = null;
  let bestTotal = -1;
  for (const a of assignmentsFor(target)) {
    const s = scoreAssignment(base, target.groups, a);
    if (s > bestTotal) { bestTotal = s; bestAssignment = a; }
  }
  const flowerNeeded = target.groups.some((g) => g.tile.k === 'flower');
  return hand.map((tile, index) => {
    if (tile.suit === 'Joker') return { index, score: 1000 };
    if (tile.suit === 'Flower') return { index, score: flowerNeeded ? 50 : 0 };
    let relevance = 0;
    if (bestAssignment) {
      for (const g of target.groups) {
        const r = resolveTileSpec(g.tile, bestAssignment);
        if (r && r.suit === tile.suit && r.value === tile.value) relevance += g.count * 5;
      }
    }
    if (relevance === 0) {
      for (const g of target.groups) if (tileMatchesGroup(tile.suit, tile.value, g)) relevance += g.count * 2;
    }
    const dupes = hand.filter((t) => matchesForGrouping(t, tile)).length;
    if (dupes >= 2) relevance += dupes * 3;
    return { index, score: relevance };
  });
}

export function selectBotDiscard(hand: Tile[], target: NMJLHand | null, rng: () => number = Math.random): number {
  if (hand.length === 0) return 0;
  if (!target) return Math.floor(rng() * hand.length);
  const scores = scoreTilesForTarget(hand, target);
  const min = Math.min(...scores.map((s) => s.score));
  const worst = scores.filter((s) => s.score === min);
  return worst[Math.floor(rng() * worst.length)].index;
}

export function selectBotCharlestonTiles(
  hand: Tile[], target: NMJLHand | null, count: number, rng: () => number = Math.random,
): number[] {
  if (hand.length === 0 || count <= 0) return [];
  if (!target) {
    const idx = hand.map((_, i) => i);
    for (let i = idx.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [idx[i], idx[j]] = [idx[j], idx[i]];
    }
    return idx.slice(0, Math.min(count, hand.length));
  }
  // Swift's sort isn't stable, but a stable sort is a valid ordering of it.
  const sorted = scoreTilesForTarget(hand, target).slice().sort((a, b) => a.score - b.score);
  return sorted.slice(0, Math.min(count, sorted.length)).map((s) => s.index);
}
