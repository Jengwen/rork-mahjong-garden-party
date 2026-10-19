import { HANDS_2025, HANDS_2026 } from './cards.generated';
import type { CardYear, NMJLCard, NMJLHand, TileSpec } from './types';

export const CARDS: Record<CardYear, NMJLCard> = {
  '2025': { year: '2025', hands: HANDS_2025 },
  '2026': { year: '2026', hands: HANDS_2026 },
};

export const CARD_YEARS: CardYear[] = ['2026', '2025'];

export function cardForYear(year: CardYear): NMJLCard {
  return CARDS[year];
}

export function cardCategories(card: NMJLCard): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const h of card.hands) if (!seen.has(h.category)) { seen.add(h.category); out.push(h.category); }
  return out;
}

function specLabel(spec: TileSpec): string {
  switch (spec.k) {
    case 'numbered': return `${spec.value}${spec.suit === 'Bamboo' ? 'B' : spec.suit === 'Character' ? 'C' : 'D'}`;
    case 'anySuit': return `${spec.value}`;
    case 'dragon': return ['R', 'G', '0'][Math.max(0, Math.min(spec.value - 1, 2))];
    case 'matchingDragon': return 'D';
    case 'wind': return ['E', 'S', 'W', 'N'][Math.max(0, Math.min(spec.value - 1, 3))];
    case 'flower': return 'F';
    case 'anyWindSlot': return 'W';
    case 'anyDragonSlot': return 'D';
    case 'anyValueAnySuit': return `${spec.allowedValues[0] ?? '#'}`;
  }
}

/** Slot index used to colour a group on the card (suit slot, or 0 for honors). */
export function specColorSlot(spec: TileSpec): number {
  switch (spec.k) {
    case 'anySuit':
    case 'matchingDragon':
      return spec.slot;
    case 'anyValueAnySuit':
      return spec.suitSlot;
    default:
      return 0;
  }
}

export interface DisplayGroup { text: string; slot: number }

export function displayGroups(hand: NMJLHand): DisplayGroup[] {
  return hand.groups.map((g) => ({ text: specLabel(g.tile).repeat(g.count), slot: specColorSlot(g.tile) }));
}
