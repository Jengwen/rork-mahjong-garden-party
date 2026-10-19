import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react';
import { Avatar, Tile, TileBack } from '../components/Tile';
import { Modal } from '../components/Modal';
import { CardReference, SuggestedHands } from '../components/CardReference';
import { SoloGame } from '../engine/game';
import type { GameState } from '../engine/game';
import { displayName, sortTiles } from '../engine/tiles';
import { CharlestonPhase, phaseDirection, phaseGroupLabel, phaseStep } from '../engine/types';
import type { CardYear, GamePlayer, Tile as TileT } from '../engine/types';
import type { MatchResult, ProfileSettings } from '../lib/profile';

export interface FinishedGame { result: MatchResult; score: number; opponents: string[] }

interface Props {
  playerName: string;
  avatar: string;
  cardYear: CardYear;
  settings: ProfileSettings;
  onFinished: (g: FinishedGame) => void;
  onExit: () => void;
  /** Delay multiplier for bot turns (dev preview only). */
  speed?: number;
}

function useViewportWidth() {
  const [w, setW] = useState(() => window.innerWidth);
  useEffect(() => {
    const on = () => setW(window.innerWidth);
    window.addEventListener('resize', on);
    return () => window.removeEventListener('resize', on);
  }, []);
  return w;
}

export function GameScreen({ playerName, avatar, cardYear, settings, onFinished, onExit, speed }: Props) {
  const gameRef = useRef<SoloGame | null>(null);
  if (!gameRef.current) gameRef.current = new SoloGame({ playerName, playerAvatar: avatar, cardYear, speed });
  const game = gameRef.current;
  useEffect(() => () => game.dispose(), [game]);
  const s = useSyncExternalStore(game.subscribe, game.getState);

  const [sheet, setSheet] = useState<'hands' | 'card' | 'leave' | null>(null);
  const recorded = useRef(false);

  // Record the result once, the moment the game completes (same rule as iOS GameBoardView).
  useEffect(() => {
    if (s.status !== 'completed' || recorded.current) return;
    recorded.current = true;
    const opponents = s.players.slice(1).map((p) => p.name);
    const result: MatchResult = s.isWallGame ? 'Draw' : s.winnerIndex === 0 ? 'Win' : 'Loss';
    onFinished({ result, score: result === 'Win' ? s.winningHand?.points ?? 0 : 0, opponents });
  }, [s, onFinished]);

  const playAgain = () => { recorded.current = false; game.restart(); };
  const leave = () => { if (s.status === 'completed' || s.status === 'waiting') onExit(); else setSheet('leave'); };

  const sheets = (
    <>
      {sheet === 'hands' && (
        <Modal title="Suggested hands" onClose={() => setSheet(null)}>
          <SuggestedHands hand={s.players[0].hand} exposed={s.players[0].exposedSets} year={s.cardYear} />
        </Modal>
      )}
      {sheet === 'card' && <Modal title={`NMJL ${s.cardYear} card`} wide onClose={() => setSheet(null)}><CardReference year={s.cardYear} /></Modal>}
      {sheet === 'leave' && (
        <Modal title="Leave this game?" onClose={() => setSheet(null)}>
          <p style={{ margin: 0 }}>Unfinished games don’t count toward your stats.</p>
          <div className="row"><button className="btn btn-ghost" onClick={() => setSheet(null)}>Keep playing</button><span className="spacer" /><button className="btn btn-pink" onClick={onExit}>Leave game</button></div>
        </Modal>
      )}
    </>
  );

  if (s.status === 'charleston') {
    return <><Charleston game={game} s={s} onLeave={leave} onHands={() => setSheet('hands')} onCard={() => setSheet('card')} />{sheets}</>;
  }
  return (
    <>
      <Board game={game} s={s} settings={settings} onLeave={leave} onHands={() => setSheet('hands')} onCard={() => setSheet('card')} onPlayAgain={playAgain} onExit={onExit} sheetOpen={sheet !== null} />
      {sheets}
    </>
  );
}

// ───────────────────────── Charleston ─────────────────────────

function Charleston({ game, s, onLeave, onHands, onCard }: { game: SoloGame; s: GameState; onLeave: () => void; onHands: () => void; onCard: () => void }) {
  const vw = useViewportWidth();
  const size = Math.max(40, Math.min(66, Math.floor((Math.min(vw, 1040) - 60) / 14.5)));
  const me = s.players[0];
  const phase = s.charlestonPhase;
  const isCourtesy = phase === CharlestonPhase.Courtesy;
  const need = game.requiredCharlestonCount(s);
  const waiting = !!s.pendingPasses[0];
  const dir = phaseDirection(phase);
  const arrow = dir === 'right' ? '→' : dir === 'left' ? '←' : '↑';
  const toName = dir === 'right' ? s.players[1].name : dir === 'left' ? s.players[3].name : s.players[2].name;
  const canStop = game.canStopCharleston(s);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement) return;
      if (e.key === 'Enter' && game.canConfirmCharleston() && !s.showCourtesyOptions && !canStop) { e.preventDefault(); game.confirmCharlestonPass(); }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [game, s.showCourtesyOptions, canStop]);

  const groups = [0, 1].map((g) => (
    <div key={g} className="grp">
      <div className="dots">
        {[0, 1, 2].map((i) => {
          const idx = g * 3 + i;
          return <i key={i} className={idx < phase ? 'done' : idx === phase ? 'now' : ''} />;
        })}
      </div>
      {g === 0 ? '1st Charleston' : '2nd Charleston'}
    </div>
  ));

  let body;
  if (s.showCourtesyOptions) {
    body = (
      <>
        <div className="dir">⇅</div>
        <h1 className="ch-title">Courtesy pass</h1>
        <p className="muted" style={{ margin: 0, textAlign: 'center' }}>Optional: pass up to three tiles across to {s.players[2].name}.</p>
        <div className="choice-row">{[0, 1, 2, 3].map((n) => <button key={n} className="choice" onClick={() => game.selectCourtesyCount(n)}>{n}</button>)}</div>
        <div className="ch-hand">{me.hand.map((t) => <Tile key={t.id} tile={t} size={size} />)}</div>
      </>
    );
  } else if (canStop) {
    body = (
      <>
        <div className="dir">✿</div>
        <h1 className="ch-title">First Charleston done!</h1>
        <p className="muted" style={{ margin: 0, textAlign: 'center', maxWidth: 460 }}>Keep going with the second Charleston, or stop here and start playing.</p>
        <div className="row"><button className="btn btn-ghost btn-lg" onClick={() => game.stopCharlestonEarly()}>Stop Charleston</button><button className="btn btn-primary btn-lg" onClick={() => game.continueCharleston()}>Continue</button></div>
        <div className="ch-hand">{me.hand.map((t) => <Tile key={t.id} tile={t} size={size} />)}</div>
      </>
    );
  } else if (waiting) {
    const seatsDone = [0, 1, 2, 3].filter((i) => s.pendingPasses[i]).length;
    body = (
      <>
        <div className="spinner" style={{ width: 54, height: 54, borderWidth: 5 }} />
        <h1 className="ch-title">Tiles passed</h1>
        <p className="muted" style={{ margin: 0 }}>Waiting for {s.players[Math.min(s.courtesyCurrentSeat, 3)].name}… ({seatsDone}/4 ready)</p>
        <div className="ch-hand">{me.hand.map((t) => <Tile key={t.id} tile={t} size={size} dim />)}</div>
      </>
    );
  } else {
    body = (
      <>
        <div className="dir" aria-hidden>{arrow}</div>
        <h1 className="ch-title">{isCourtesy ? `Pass ${need} across` : `Pass 3 ${dir}`}</h1>
        <p className="muted" style={{ margin: 0 }}>{isCourtesy ? 'Courtesy Pass' : `${phaseGroupLabel(phase)} · step ${phaseStep(phase) + 1} of 3`} — to {toName}</p>
        <div className="ch-hand" role="group" aria-label="Your hand">
          {me.hand.map((t) => (
            <Tile key={t.id} tile={t} size={size} selected={s.charlestonSelectedIds.includes(t.id)} onClick={() => game.toggleCharlestonSelection(t.id)} />
          ))}
        </div>
        <div className="ch-hint">{s.charlestonSelectedIds.length} of {need} selected</div>
        <button className="btn btn-pink btn-lg" disabled={!game.canConfirmCharleston(s)} onClick={() => game.confirmCharlestonPass()}>
          Pass tiles {arrow}<kbd>Enter</kbd>
        </button>
      </>
    );
  }

  return (
    <div className="ch-wrap">
      <div className="t-top">
        <button className="btn btn-ghost btn-sm" onClick={onLeave}>✕ Leave</button>
        <span className="spacer" />
        <div className="progress">{groups}</div>
        <span className="spacer" />
        <button className="btn btn-ghost btn-sm" onClick={onCard}>Card</button>
        <button className="btn btn-gold btn-sm" onClick={onHands}>💡 Hands</button>
      </div>
      <div className="ch-body">{body}</div>
    </div>
  );
}

// ───────────────────────── Table ─────────────────────────

function Opponent({ p, turn, side, compact }: { p: GamePlayer; turn: boolean; side?: 'left' | 'right' | 'top'; compact?: boolean }) {
  const backs = Array.from({ length: p.hand.length });
  return (
    <div className={`opp${side === 'left' || side === 'right' ? ' side' : ''}`}>
      <div className={`opp-head${turn ? ' turn' : ''}`}>
        <Avatar name={p.avatar} size={30} />
        <span>{p.name}</span>
        <small>{p.seat} · {p.hand.length}</small>
      </div>
      {!compact && (
        <div className={`opp-backs${side === 'top' ? ' horiz' : ''}`}>
          {backs.map((_, i) => <TileBack key={i} size={side === 'top' ? 20 : 18} />)}
        </div>
      )}
      {p.exposedSets.length > 0 && (
        <div className="exposures">
          {p.exposedSets.map((set, i) => <div key={i} className="exposure">{set.map((t) => <Tile key={t.id} tile={t} size={compact ? 22 : 26} />)}</div>)}
        </div>
      )}
    </div>
  );
}

interface BoardProps {
  game: SoloGame; s: GameState; settings: ProfileSettings; sheetOpen: boolean;
  onLeave: () => void; onHands: () => void; onCard: () => void; onPlayAgain: () => void; onExit: () => void;
}

function Board({ game, s, settings, sheetOpen, onLeave, onHands, onCard, onPlayAgain, onExit }: BoardProps) {
  const vw = useViewportWidth();
  const me = s.players[0];
  const myTurn = s.currentPlayerIndex === 0;
  const canDraw = game.canDrawTile(s);
  const canDiscard = myTurn && s.hasDrawnThisTurn && !s.showCallTileSelection && !s.jokerSwapMode;
  const hand = useMemo(() => (settings.autoSortHand ? sortTiles(me.hand) : me.hand), [me.hand, settings.autoSortHand]);
  const exposedCount = me.exposedSets.reduce((n, x) => n + x.length, 0);
  const sideCols = vw > 1100 ? 300 : vw > 760 ? 220 : 0;
  const handSize = Math.max(32, Math.min(62, Math.floor((vw - sideCols * 0 - 40 - (exposedCount > 0 ? exposedCount * 28 + 24 : 0)) / 15)));
  const discardSize = vw > 1100 ? 34 : 28;
  const [dragId, setDragId] = useState<string | null>(null);
  const [overId, setOverId] = useState<string | null>(null);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    if (!s.callWindowDeadline) return;
    const id = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(id);
  }, [s.callWindowDeadline]);

  const onTile = useCallback((t: TileT) => {
    if (s.showCallTileSelection) { game.toggleCallTileSelection(t.id); return; }
    if (s.jokerSwapMode) { game.selectTile(t.id); return; }
    if (!myTurn) return;
    if (!settings.confirmDiscards && s.hasDrawnThisTurn) {
      if (s.selectedTileId !== t.id) game.selectTile(t.id);
      game.discardSelectedTile();
      return;
    }
    if (s.selectedTileId === t.id && s.hasDrawnThisTurn) { game.discardSelectedTile(); return; }
    game.selectTile(t.id);
  }, [game, s.showCallTileSelection, s.jokerSwapMode, s.hasDrawnThisTurn, s.selectedTileId, myTurn, settings.confirmDiscards]);

  // Desktop keyboard shortcuts.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (sheetOpen || e.metaKey || e.ctrlKey || e.target instanceof HTMLInputElement) return;
      const k = e.key.toLowerCase();
      if (k === 'd' && game.canDrawTile()) { e.preventDefault(); game.drawTile(); }
      else if ((k === 'enter') && s.selectedTileId && canDiscard) { e.preventDefault(); game.discardSelectedTile(); }
      else if (k === 'm' && myTurn && s.hasDrawnThisTurn) { e.preventDefault(); game.declareMahjong(); }
      else if (k === 's' && !settings.autoSortHand) { e.preventDefault(); game.sortHand(); }
      else if (k === 'escape') {
        if (s.showCallTileSelection) game.cancelCallSelection();
        else if (s.jokerSwapMode) game.cancelJokerSwap();
        else if (s.callAvailable) game.dismissCallOptions();
      } else if ((k === 'arrowleft' || k === 'arrowright') && myTurn && hand.length) {
        e.preventDefault();
        const i = hand.findIndex((t) => t.id === s.selectedTileId);
        const next = i < 0 ? (k === 'arrowright' ? 0 : hand.length - 1) : (i + (k === 'arrowright' ? 1 : -1) + hand.length) % hand.length;
        game.selectTile(hand[next].id);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [game, s, canDiscard, myTurn, hand, settings.autoSortHand, sheetOpen]);

  const last = s.lastDiscardedTile;
  const showPrompt = game.shouldAutoShowCallPrompt(s);
  const manualCall = game.canUseManualCallButton(s);
  const remain = s.callWindowDeadline ? Math.max(0, s.callWindowDeadline - now) : 0;

  const turnName = s.players[s.currentPlayerIndex]?.name;

  return (
    <div className="table">
      <div className="t-top">
        <button className="btn btn-ghost btn-sm" onClick={onLeave}>✕ Leave</button>
        <span className="t-pill" title="Tiles left in the wall">🀫 {s.wall.length}</span>
        <span className="t-pill" title="Card">NMJL {s.cardYear}</span>
        <span className="spacer" />
        {vw > 760 && <Opponent p={s.players[2]} turn={s.currentPlayerIndex === 2} side="top" />}
        <span className="spacer" />
        <button className="btn btn-ghost btn-sm" onClick={onCard}>Card</button>
        <button className="btn btn-gold btn-sm" onClick={onHands}>💡 Hands</button>
      </div>

      <div className="t-mid">
        {vw > 760 && <Opponent p={s.players[3]} turn={s.currentPlayerIndex === 3} side="left" />}
        <div className="center-area">
          <div className="mobile-opps">
            {[1, 2, 3].map((i) => <Opponent key={i} p={s.players[i]} turn={s.currentPlayerIndex === i} compact />)}
          </div>
          <div className="message" aria-live="polite">{s.invalidMahjongMessage ?? s.gameMessage}</div>
          <div className="discards" aria-label="Discard pile">
            {s.discardPile.length === 0 && <span className="discards-empty">Discards will appear here</span>}
            {s.discardPile.map((d) => (
              <Tile key={d.tile.id} tile={d.tile} size={discardSize} lastDiscard={last?.id === d.tile.id} title={`${displayName(d.tile)} — discarded by ${d.by}`} />
            ))}
          </div>
        </div>
        {vw > 760 && <Opponent p={s.players[1]} turn={s.currentPlayerIndex === 1} side="right" />}
      </div>

      <div className="t-bottom">
        {s.showCallTileSelection && (
          <div className="banner">
            <span>Pick {s.callRequiredCount} tiles for {s.callTileSelectionType} ({s.callSelectedIds.length}/{s.callRequiredCount})</span>
            <button className="btn btn-ghost btn-sm" onClick={() => game.autoPickCallTiles()}>Auto-pick</button>
            <button className="btn btn-primary btn-sm" disabled={!game.canConfirmCallSelection(s)} onClick={() => game.confirmCallSelection()}>Expose</button>
            <button className="btn btn-quiet btn-sm" onClick={() => game.cancelCallSelection()}>Cancel</button>
          </div>
        )}
        {s.jokerSwapMode && (
          <div className="banner"><span>Click a tile in your hand that matches an exposed joker’s set.</span><button className="btn btn-quiet btn-sm" onClick={() => game.cancelJokerSwap()}>Cancel</button></div>
        )}
        <div className="me-row">
          {me.exposedSets.length > 0 && (
            <div className="exposures" aria-label="Your exposures">
              {me.exposedSets.map((set, i) => <div key={i} className="exposure">{set.map((t) => <Tile key={t.id} tile={t} size={28} />)}</div>)}
            </div>
          )}
          <div className="hand" role="group" aria-label="Your hand">
            {myTurn && <span className="turn-dot" style={{ alignSelf: 'center', marginRight: 6 }} title="Your turn" />}
            {hand.map((t, i) => (
              <Tile
                key={t.id}
                tile={t}
                size={handSize}
                selected={!s.showCallTileSelection && s.selectedTileId === t.id}
                picked={s.showCallTileSelection && s.callSelectedIds.includes(t.id)}
                fresh={s.lastDrawnTileId === t.id && s.selectedTileId !== t.id}
                onClick={() => onTile(t)}
                draggable={!settings.autoSortHand}
                dragging={dragId === t.id}
                dropBefore={overId === t.id && dragId !== t.id}
                onDragStart={(e) => { setDragId(t.id); e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', t.id); }}
                onDragOver={(e) => { if (dragId) { e.preventDefault(); setOverId(t.id); } }}
                onDrop={(e) => {
                  e.preventDefault();
                  const from = me.hand.findIndex((x) => x.id === dragId);
                  if (from >= 0) game.moveTile(from, from < i ? i - 1 : i);
                  setDragId(null); setOverId(null);
                }}
                onDragEnd={() => { setDragId(null); setOverId(null); }}
              />
            ))}
          </div>
        </div>
        <div className="actions">
          <button className={`btn btn-primary${canDraw ? ' btn-glow' : ''}`} disabled={!canDraw} onClick={() => game.drawTile()}>Draw<kbd>D</kbd></button>
          <button className="btn btn-pink" disabled={!canDiscard || !s.selectedTileId} onClick={() => game.discardSelectedTile()}>Discard<kbd>Enter</kbd></button>
          <button className="btn btn-gold" disabled={!(myTurn && s.hasDrawnThisTurn)} onClick={() => game.declareMahjong()}>Mahjong!<kbd>M</kbd></button>
          <button className="btn btn-ghost" disabled={!game.hasJokerSwapAvailable(s) || s.showCallTileSelection} onClick={() => game.startJokerSwap()}>Joker swap</button>
          {manualCall && <button className="btn btn-ghost" onClick={() => game.expandManualCall()}>Call with jokers…</button>}
          {manualCall && <button className="btn btn-quiet" onClick={() => game.dismissCallOptions()}>Skip call<kbd>Esc</kbd></button>}
          {!settings.autoSortHand && <button className="btn btn-quiet" onClick={() => game.sortHand()}>Sort<kbd>S</kbd></button>}
        </div>
        {!myTurn && s.status === 'playing' && !s.callAvailable && <div className="muted" style={{ fontSize: 13, fontWeight: 700 }}>{turnName}’s turn</div>}
      </div>

      {showPrompt && last && (
        <div className="card call-pop" role="dialog" aria-label="Call the discard">
          <div className="row"><Tile tile={last} size={44} /><div><b>{displayName(last)}</b><div className="muted" style={{ fontSize: 13 }}>discarded — call it?</div></div></div>
          <div className="row" style={{ flexWrap: 'wrap', justifyContent: 'center' }}>
            {s.availableCalls.includes('Mahjong!') && <button className="btn btn-gold" onClick={() => game.callTile('Mahjong!')}>Mahjong!</button>}
            {s.availableCalls.filter((c) => c !== 'Mahjong!').map((c) => (
              <button key={c} className="btn btn-primary" onClick={() => game.beginCallTileSelection(c)}>{c}</button>
            ))}
            <button className="btn btn-ghost" onClick={() => game.dismissCallOptions()}>Skip<kbd>Esc</kbd></button>
          </div>
          {s.callWindowDeadline && <div className="countdown" aria-hidden><i style={{ width: `${Math.min(100, (remain / s.callWindowTotalMs) * 100)}%` }} /></div>}
        </div>
      )}

      {s.showEndGameOverlay && <EndOverlay s={s} onPlayAgain={onPlayAgain} onExit={onExit} />}
    </div>
  );
}

function EndOverlay({ s, onPlayAgain, onExit }: { s: GameState; onPlayAgain: () => void; onExit: () => void }) {
  const won = s.winnerIndex === 0;
  const winner = s.winnerIndex >= 0 ? s.players[s.winnerIndex] : null;
  const confetti = useMemo(() => Array.from({ length: won ? 40 : 0 }, (_, i) => ({
    left: Math.random() * 100, delay: Math.random() * 1.2, dur: 2.4 + Math.random() * 2, ch: ['✿', '❀', '🌸', '🌼', '🌷'][i % 5], size: 14 + Math.random() * 18,
  })), [won]);
  return (
    <div className="overlay">
      <div className="confetti">{confetti.map((c, i) => <i key={i} style={{ left: `${c.left}%`, animationDelay: `${c.delay}s`, animationDuration: `${c.dur}s`, fontSize: c.size, color: i % 2 ? 'var(--pink)' : 'var(--gold)' }}>{c.ch}</i>)}</div>
      <div className="card endcard">
        {s.isWallGame ? (
          <><div style={{ fontSize: 46 }}>🀫</div><h2>Wall game</h2><p className="muted" style={{ margin: 0 }}>The wall ran out — nobody wins this one.</p></>
        ) : (
          <>
            <Avatar name={winner!.avatar} size={72} />
            <h2>{won ? 'Mahjong! You win!' : `${winner!.name} wins`}</h2>
            <p className="muted" style={{ margin: 0 }}>{s.winningHand?.name} · {s.winningHand?.points} points</p>
            <div className="row" style={{ flexWrap: 'wrap', justifyContent: 'center', gap: 6 }}>
              {winner!.exposedSets.map((set, i) => <div key={i} className="exposure">{set.map((t) => <Tile key={t.id} tile={t} size={30} />)}</div>)}
              <div className="row" style={{ gap: 2 }}>{sortTiles(winner!.hand).map((t) => <Tile key={t.id} tile={t} size={30} />)}</div>
            </div>
          </>
        )}
        <div className="muted" style={{ fontSize: 13 }}>{won ? '+100 XP' : '+25 XP'} · saved to your stats</div>
        <div className="row"><button className="btn btn-ghost btn-lg" onClick={onExit}>Home</button><button className="btn btn-primary btn-lg" onClick={onPlayAgain}>Play again</button></div>
      </div>
    </div>
  );
}
