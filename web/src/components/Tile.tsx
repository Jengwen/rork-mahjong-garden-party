import type { CSSProperties, DragEvent, MouseEvent } from 'react';
import { displayName } from '../engine/tiles';
import type { Tile as TileT } from '../engine/types';

// Mirrors ios/.../Views/TileView.swift: same artwork, same upper-left index
// numbers and colours, proportions derived from the 44×60 reference tile.

const WIND_IMG = ['east', 'south', 'west', 'north'];

function art(t: TileT): { src: string; cls: string } | null {
  switch (t.suit) {
    case 'Joker': return { src: '/tiles/joker.webp', cls: 'g-large' };
    case 'Flower': return { src: '/tiles/flower.webp', cls: 'g-large' };
    case 'Wind': return { src: `/tiles/${WIND_IMG[Math.min(t.value - 1, 3)]}.webp`, cls: 'g-large' };
    case 'Dragon':
      if (t.value === 1) return { src: '/tiles/red_dragon.webp', cls: 'g-full' };
      if (t.value === 2) return { src: '/tiles/green_dragon.webp', cls: 'g-large' };
      return { src: '/tiles/white_dragon.webp', cls: 'g-large' };
    case 'Bamboo':
      return t.value === 1 ? { src: '/tiles/bam1.webp', cls: 'g-full' } : { src: `/tiles/bam${t.value}.webp`, cls: 'g-suit' };
    case 'Character': return { src: `/tiles/crack${t.value}.webp`, cls: 'g-suit' };
    case 'Dot': return { src: `/tiles/dot_${t.value}.webp`, cls: 'g-suit' };
  }
}

function corner(t: TileT): { text: string; color: string; small: boolean } | null {
  if (t.suit === 'Dragon' && t.value === 1) return { text: 'R', color: 'var(--dragon-red)', small: true };
  if (t.suit === 'Dragon' && t.value === 2) return { text: 'G', color: 'var(--bam)', small: true };
  if (t.suit === 'Bamboo') return { text: `${t.value}`, color: 'var(--bam)', small: t.value === 1 };
  if (t.suit === 'Character') return { text: `${t.value}`, color: 'var(--crak)', small: false };
  if (t.suit === 'Dot') return { text: `${t.value}`, color: 'var(--dot)', small: false };
  return null;
}

interface Props {
  tile: TileT;
  size?: number;
  selected?: boolean;
  picked?: boolean;
  dim?: boolean;
  fresh?: boolean;
  lastDiscard?: boolean;
  dragging?: boolean;
  dropBefore?: boolean;
  onClick?: (e: MouseEvent) => void;
  draggable?: boolean;
  onDragStart?: (e: DragEvent) => void;
  onDragOver?: (e: DragEvent) => void;
  onDrop?: (e: DragEvent) => void;
  onDragEnd?: (e: DragEvent) => void;
  title?: string;
}

export function Tile({ tile, size = 48, selected, picked, dim, fresh, lastDiscard, dragging, dropBefore, onClick, title, ...drag }: Props) {
  const a = art(tile);
  const c = corner(tile);
  const cls = ['tile',
    onClick && 'clickable', selected && 'selected', picked && 'picked', dim && 'dim',
    fresh && 'fresh', lastDiscard && 'last-discard', dragging && 'dragging', dropBefore && 'drop-before',
  ].filter(Boolean).join(' ');
  const name = displayName(tile);
  return (
    <div
      className={cls}
      style={{ '--tw': `${size}px` } as CSSProperties}
      onClick={onClick}
      role={onClick ? 'button' : 'img'}
      aria-label={name}
      aria-pressed={onClick ? !!(selected || picked) : undefined}
      tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); e.stopPropagation(); onClick(e as unknown as MouseEvent); } } : undefined}
      title={title ?? name}
      {...drag}
    >
      {a && <img className={a.cls} src={a.src} alt="" draggable={false} />}
      {c && <span className={`num${c.small ? ' sm' : ''}`} style={{ color: c.color }}>{c.text}</span>}
    </div>
  );
}

export function TileBack({ size = 22 }: { size?: number }) {
  return <div className="tile-back" style={{ '--tw': `${size}px` } as CSSProperties} aria-hidden>✿</div>;
}

export function Avatar({ name, size = 44 }: { name: string; size?: number }) {
  return <img className="avatar" src={`/avatars/${name}.webp`} width={size} height={size} alt="" onError={(e) => { (e.target as HTMLImageElement).src = '/avatars/daffodil.webp'; }} />;
}
