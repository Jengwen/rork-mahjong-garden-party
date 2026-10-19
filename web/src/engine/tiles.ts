import type { Suit, Tile } from './types';

let idCounter = 0;
export function newTileId(): string {
  idCounter += 1;
  const rand = typeof crypto !== 'undefined' && 'randomUUID' in crypto
    ? crypto.randomUUID()
    : Math.random().toString(36).slice(2);
  return `${rand}-${idCounter}`;
}

export function makeTile(suit: Suit, value: number): Tile {
  return { id: newTileId(), suit, value };
}

/** Fisher–Yates shuffle (returns a new array). */
export function shuffled<T>(arr: T[], rng: () => number = Math.random): T[] {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/** 152-tile American set: 108 suited, 16 winds, 12 dragons, 8 flowers, 8 jokers. */
export function createFullSet(rng: () => number = Math.random): Tile[] {
  const tiles: Tile[] = [];
  for (const suit of ['Bamboo', 'Character', 'Dot'] as Suit[]) {
    for (let v = 1; v <= 9; v++) for (let c = 0; c < 4; c++) tiles.push(makeTile(suit, v));
  }
  for (let v = 1; v <= 4; v++) for (let c = 0; c < 4; c++) tiles.push(makeTile('Wind', v));
  for (let v = 1; v <= 3; v++) for (let c = 0; c < 4; c++) tiles.push(makeTile('Dragon', v));
  for (let v = 1; v <= 8; v++) tiles.push(makeTile('Flower', v));
  for (let c = 0; c < 8; c++) tiles.push(makeTile('Joker', 1));
  return shuffled(tiles, rng);
}

/**
 * Whether this tile can stand in for `other` in a pung/kong/quint/exposure.
 * All eight Flowers are interchangeable under NMJL rules; every other suit
 * matches on suit and value. Jokers are handled separately by callers.
 */
export function matchesForGrouping(a: Tile, b: Tile): boolean {
  if (a.suit === 'Flower' && b.suit === 'Flower') return true;
  return a.suit === b.suit && a.value === b.value;
}

const WINDS = ['East', 'South', 'West', 'North'];
const DRAGONS = ['Red', 'Green', 'White'];

export function displayName(t: Tile): string {
  switch (t.suit) {
    case 'Wind': return WINDS[Math.min(t.value - 1, 3)];
    case 'Dragon': return DRAGONS[Math.min(t.value - 1, 2)];
    case 'Flower': return `Flower ${t.value}`;
    case 'Joker': return 'Joker';
    default: return `${t.value} ${t.suit}`;
  }
}

const SUIT_ORDER: Record<Suit, number> = {
  Bamboo: 0, Character: 1, Dot: 2, Wind: 3, Dragon: 4, Flower: 5, Joker: 6,
};

export function sortKey(t: Tile): number {
  return SUIT_ORDER[t.suit] * 100 + t.value;
}

export function sortTiles(tiles: Tile[]): Tile[] {
  return tiles.slice().sort((a, b) => sortKey(a) - sortKey(b));
}
