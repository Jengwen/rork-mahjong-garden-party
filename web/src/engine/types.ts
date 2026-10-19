// Core game types — a direct port of the iOS models
// (MahjongTile.swift, NMJLCard.swift, GameState.swift).

export type Suit = 'Bamboo' | 'Character' | 'Dot' | 'Wind' | 'Dragon' | 'Flower' | 'Joker';

export const NUMBER_SUITS: Suit[] = ['Bamboo', 'Character', 'Dot'];

export interface Tile {
  id: string;
  suit: Suit;
  value: number;
}

export type TileSpec =
  | { k: 'numbered'; suit: Suit; value: number }
  | { k: 'anySuit'; slot: number; value: number }
  | { k: 'dragon'; value: number }
  | { k: 'matchingDragon'; slot: number }
  | { k: 'wind'; value: number }
  | { k: 'flower' }
  | { k: 'anyWindSlot'; slot: number }
  | { k: 'anyDragonSlot'; slot: number }
  | { k: 'anyValueAnySuit'; suitSlot: number; valueSlot: number; allowedValues: number[] };

export interface HandGroup {
  count: number;
  tile: TileSpec;
}

export interface NMJLHand {
  id: string;
  category: string;
  name: string;
  groups: HandGroup[];
  points: number;
  concealed: boolean;
  requireUniqueSuits?: boolean;
}

export type CardYear = '2025' | '2026';

export interface NMJLCard {
  year: CardYear;
  hands: NMJLHand[];
}

export type CallType = 'Pung' | 'Kong' | 'Quint' | 'Sextet' | 'Mahjong!';

export type GameStatus = 'waiting' | 'charleston' | 'playing' | 'completed';

/** Mirrors CharlestonPhase raw values 0…6. */
export const CharlestonPhase = {
  FirstRight: 0,
  FirstAcross: 1,
  FirstLeft: 2,
  SecondLeft: 3,
  SecondAcross: 4,
  SecondRight: 5,
  Courtesy: 6,
} as const;
export type CharlestonPhase = (typeof CharlestonPhase)[keyof typeof CharlestonPhase];

export type PassDirection = 'right' | 'across' | 'left';

export function phaseDirection(p: CharlestonPhase): PassDirection {
  switch (p) {
    case CharlestonPhase.FirstRight:
    case CharlestonPhase.SecondRight:
      return 'right';
    case CharlestonPhase.FirstLeft:
    case CharlestonPhase.SecondLeft:
      return 'left';
    default:
      return 'across';
  }
}

export function phaseGroupLabel(p: CharlestonPhase): string {
  if (p <= 2) return '1st Charleston';
  if (p <= 5) return '2nd Charleston';
  return 'Courtesy Pass';
}

export function phaseDisplayName(p: CharlestonPhase): string {
  const dir = phaseDirection(p);
  if (p === CharlestonPhase.Courtesy) return 'Courtesy Pass';
  const label = dir === 'right' ? 'Pass Right' : dir === 'left' ? 'Pass Left' : 'Pass Across';
  return `${phaseGroupLabel(p)}: ${label}`;
}

/** Step within the current group of three passes (0-based). */
export function phaseStep(p: CharlestonPhase): number {
  if (p === CharlestonPhase.Courtesy) return 0;
  return p <= 2 ? p : p - 3;
}

export function receiverSeat(from: number, dir: PassDirection): number {
  if (dir === 'right') return (from + 1) % 4;
  if (dir === 'across') return (from + 2) % 4;
  return (from + 3) % 4;
}

export interface GamePlayer {
  name: string;
  avatar: string;
  seat: 'East' | 'South' | 'West' | 'North';
  isBot: boolean;
  hand: Tile[];
  exposedSets: Tile[][];
  score: number;
  targetHand: NMJLHand | null;
}
