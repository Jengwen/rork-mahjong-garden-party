// Solo game controller — a port of the SOLO paths of
// ios/MahjongGardenParty/ViewModels/GameViewModel.swift.
//
// The iOS view model also carries the whole online-multiplayer sync layer
// (host/invitee merges, latches, watchdogs, seat revisions). None of that
// applies to a single-player table, so only the solo branches are ported here.
// Timings, bot behaviour, call priority and messages match the app.
import { cardForYear } from './cards';
import {
  canCallForMahjong, canCallTileForExposure, checkWin, selectBestTargetHand,
  selectBotCharlestonTiles, selectBotDiscard, scoreTilesForTarget, tileMatchesGroup,
} from './handMatcher';
import { createFullSet, displayName, matchesForGrouping, sortTiles } from './tiles';
import {
  CharlestonPhase, phaseDirection, phaseGroupLabel, receiverSeat,
} from './types';
import type { CallType, CardYear, GamePlayer, GameStatus, NMJLHand, Tile } from './types';

export interface Scheduler {
  setTimeout(fn: () => void, ms: number): unknown;
  clearTimeout(handle: unknown): void;
}

const realScheduler: Scheduler = {
  setTimeout: (fn, ms) => globalThis.setTimeout(fn, ms),
  clearTimeout: (h) => globalThis.clearTimeout(h as ReturnType<typeof setTimeout>),
};

export interface GameOptions {
  playerName?: string;
  playerAvatar?: string;
  cardYear?: CardYear;
  scheduler?: Scheduler;
  rng?: () => number;
  /** Multiplies every bot/announcement delay. Tests pass 0. */
  speed?: number;
}

export interface DiscardEntry { tile: Tile; by: string }

export interface GameState {
  players: GamePlayer[];
  wall: Tile[];
  discardPile: DiscardEntry[];
  currentPlayerIndex: number;
  status: GameStatus;
  cardYear: CardYear;
  gameMessage: string;

  // Charleston
  charlestonPhase: CharlestonPhase;
  charlestonSelectedIds: string[];
  pendingPasses: Record<number, Tile[]>;
  courtesyTileCount: number;
  showCourtesyOptions: boolean;
  courtesyCurrentSeat: number;
  showStopCharlestonOption: boolean;

  // Play
  selectedTileId: string | null;
  hasDrawnThisTurn: boolean;
  lastDrawnTileId: string | null;
  lastDiscardedTile: Tile | null;
  lastDiscardPlayerIndex: number | null;
  callAvailable: boolean;
  availableCalls: CallType[];
  awaitingCall: boolean;
  manualCallExpanded: boolean;
  callResponseDiscardId: string | null;
  eligibleCallSeats: number[];
  lastFinalizedCallDiscardId: string | null;
  showCallTileSelection: boolean;
  callTileSelectionType: CallType | null;
  callSelectedIds: string[];
  callRequiredCount: number;
  callWindowDeadline: number | null;
  callWindowTotalMs: number;
  jokerSwapMode: boolean;

  // End
  winningHand: NMJLHand | null;
  winnerName: string;
  winnerIndex: number;
  invalidMahjongMessage: string | null;
  isWallGame: boolean;
  showEndGameOverlay: boolean;
}

const HUMAN = 0;
const SEATS: GamePlayer['seat'][] = ['East', 'South', 'West', 'North'];
const BOTS: [string, string][] = [['Lily', 'lily'], ['Rose', 'pink_rose'], ['Daisy', 'pdaisy']];
const CALL_WINDOW_MS = 25_000;

export class SoloGame {
  private s: GameState;
  private snapshot: GameState;
  private listeners = new Set<() => void>();
  private timers = new Set<unknown>();
  private callWatchdog: unknown = null;
  private pendingBotCall: { idx: number; type: CallType } | null = null;
  private generation = 0;
  private readonly scheduler: Scheduler;
  private readonly rng: () => number;
  private readonly speed: number;
  private readonly opts: GameOptions;

  constructor(opts: GameOptions = {}) {
    this.opts = opts;
    this.scheduler = opts.scheduler ?? realScheduler;
    this.rng = opts.rng ?? Math.random;
    this.speed = opts.speed ?? 1;
    this.s = this.freshState();
    this.snapshot = this.s;
    this.start();
  }

  // MARK: - Store plumbing (useSyncExternalStore-compatible)

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => { this.listeners.delete(fn); };
  };

  getState = () => this.snapshot;

  private emit() {
    const s = this.s;
    this.snapshot = {
      ...s,
      players: s.players.map((p) => ({ ...p, hand: [...p.hand], exposedSets: p.exposedSets.map((x) => [...x]) })),
      discardPile: [...s.discardPile],
      wall: s.wall,
      pendingPasses: { ...s.pendingPasses },
    };
    this.listeners.forEach((l) => l());
  }

  dispose() {
    this.generation++;
    this.timers.forEach((t) => this.scheduler.clearTimeout(t));
    this.timers.clear();
    this.callWatchdog = null;
  }

  private after(minSec: number, maxSec: number, fn: () => void): unknown {
    const gen = this.generation;
    const ms = (minSec + this.rng() * (maxSec - minSec)) * 1000 * this.speed;
    const handle = this.scheduler.setTimeout(() => {
      this.timers.delete(handle);
      if (gen !== this.generation) return;
      fn();
    }, ms);
    this.timers.add(handle);
    return handle;
  }

  private cancel(handle: unknown) {
    if (handle == null) return;
    this.scheduler.clearTimeout(handle);
    this.timers.delete(handle);
  }

  private get card() { return cardForYear(this.s.cardYear); }

  // MARK: - Setup

  private freshState(): GameState {
    return {
      players: [], wall: [], discardPile: [], currentPlayerIndex: 0, status: 'waiting',
      cardYear: this.opts.cardYear ?? '2026', gameMessage: '',
      charlestonPhase: CharlestonPhase.FirstRight, charlestonSelectedIds: [], pendingPasses: {},
      courtesyTileCount: 3, showCourtesyOptions: false, courtesyCurrentSeat: 0, showStopCharlestonOption: false,
      selectedTileId: null, hasDrawnThisTurn: false, lastDrawnTileId: null, lastDiscardedTile: null,
      lastDiscardPlayerIndex: null, callAvailable: false, availableCalls: [], awaitingCall: false,
      manualCallExpanded: false, callResponseDiscardId: null, eligibleCallSeats: [],
      lastFinalizedCallDiscardId: null, showCallTileSelection: false, callTileSelectionType: null,
      callSelectedIds: [], callRequiredCount: 0, callWindowDeadline: null, callWindowTotalMs: CALL_WINDOW_MS, jokerSwapMode: false,
      winningHand: null, winnerName: '', winnerIndex: -1, invalidMahjongMessage: null,
      isWallGame: false, showEndGameOverlay: false,
    };
  }

  private start() {
    this.dispose();
    this.pendingBotCall = null;
    const s = this.freshState();
    s.status = 'charleston';
    s.wall = createFullSet(this.rng);
    const rawName = (this.opts.playerName ?? '').trim();
    const humanName = rawName && rawName !== 'Garden Guest' ? rawName : 'You';
    s.players = [
      { name: humanName, avatar: this.opts.playerAvatar ?? 'daffodil', seat: 'East', isBot: false, hand: [], exposedSets: [], score: 0, targetHand: null },
      ...BOTS.map(([name, avatar], i): GamePlayer => ({ name, avatar, seat: SEATS[i + 1], isBot: true, hand: [], exposedSets: [], score: 0, targetHand: null })),
    ];
    for (const p of s.players) {
      p.hand = sortTiles(s.wall.splice(0, 13));
    }
    this.s = s;
    for (const p of s.players) if (p.isBot) p.targetHand = selectBestTargetHand(p.hand, this.card);
    s.gameMessage = '1st Charleston: Select 3 tiles to pass right';
    this.emit();
  }

  restart() { this.start(); }

  // MARK: - Derived

  get human() { return this.s.players[HUMAN]; }

  isCallWindowOpen(s: GameState = this.s): boolean {
    const d = s.lastDiscardedTile;
    if (!d) return false;
    if (s.lastFinalizedCallDiscardId === d.id) return false;
    if (s.lastDiscardPlayerIndex != null && s.currentPlayerIndex !== s.lastDiscardPlayerIndex) return false;
    if (s.callResponseDiscardId === d.id) return true;
    return s.callAvailable || s.awaitingCall || s.showCallTileSelection || s.eligibleCallSeats.length > 0;
  }

  canDrawTile(s: GameState = this.snapshot): boolean {
    if (s.status !== 'playing' || s.currentPlayerIndex !== HUMAN || s.hasDrawnThisTurn) return false;
    if (s.callAvailable || s.showCallTileSelection || s.awaitingCall || this.isCallWindowOpen(s)) return false;
    // "My own discard is still the latest" means the turn hasn't truly rotated —
    // unless that discard's window was already finalized (e.g. a bot called it and
    // the turn came back around). iOS lacks this exception, which can freeze solo
    // play when a bot's call consumes its whole concealed hand.
    if (s.lastDiscardPlayerIndex === HUMAN && s.lastDiscardedTile
      && s.lastFinalizedCallDiscardId !== s.lastDiscardedTile.id) return false;
    return true;
  }

  canStopCharleston(s: GameState = this.snapshot) {
    return s.showStopCharlestonOption && s.status === 'charleston' && Object.keys(s.pendingPasses).length === 0;
  }

  requiredCharlestonCount(s: GameState = this.snapshot) {
    return s.charlestonPhase === CharlestonPhase.Courtesy ? s.courtesyTileCount : 3;
  }

  localJokerCount(s: GameState = this.snapshot) {
    return s.players[HUMAN]?.hand.filter((t) => t.suit === 'Joker').length ?? 0;
  }

  localHasNaturalMatch(s: GameState = this.snapshot) {
    const d = s.lastDiscardedTile;
    if (!d || d.suit === 'Joker') return false;
    return s.players[HUMAN].hand.some((t) => matchesForGrouping(t, d));
  }

  shouldAutoShowCallPrompt(s: GameState = this.snapshot) {
    if (!s.callAvailable || s.showCallTileSelection) return false;
    if (s.availableCalls.includes('Mahjong!')) return true;
    if (this.localHasNaturalMatch(s)) return true;
    return s.manualCallExpanded;
  }

  /** Joker-only call: shown as a small button instead of an auto popup. */
  canUseManualCallButton(s: GameState = this.snapshot) {
    if (!s.callAvailable || s.showCallTileSelection || s.manualCallExpanded) return false;
    if (s.availableCalls.includes('Mahjong!')) return false;
    if (this.localHasNaturalMatch(s)) return false;
    if (this.localJokerCount(s) < 2) return false;
    return s.availableCalls.some((c) => c !== 'Mahjong!');
  }

  hasJokerSwapAvailable(s: GameState = this.snapshot) {
    if (s.status !== 'playing') return false;
    return this.matchingTileForJokerSwap(s.players, HUMAN);
  }

  // MARK: - Hand ordering

  moveTile(fromIndex: number, toIndex: number) {
    const hand = this.human.hand;
    if (fromIndex === toIndex || fromIndex < 0 || toIndex < 0 || fromIndex >= hand.length || toIndex >= hand.length) return;
    const [t] = hand.splice(fromIndex, 1);
    hand.splice(toIndex, 0, t);
    this.emit();
  }

  sortHand() {
    this.human.hand = sortTiles(this.human.hand);
    this.emit();
  }

  // MARK: - Charleston

  toggleCharlestonSelection(tileId: string) {
    const s = this.s;
    if (s.status !== 'charleston') return;
    if (!this.human.hand.some((t) => t.id === tileId)) return;
    const max = s.charlestonPhase === CharlestonPhase.Courtesy ? s.courtesyTileCount : 3;
    const i = s.charlestonSelectedIds.indexOf(tileId);
    if (i >= 0) s.charlestonSelectedIds.splice(i, 1);
    else if (s.charlestonSelectedIds.length < max) s.charlestonSelectedIds.push(tileId);
    this.emit();
  }

  canConfirmCharleston(s: GameState = this.snapshot) {
    return s.charlestonSelectedIds.length === this.requiredCharlestonCount(s);
  }

  selectCourtesyCount(count: number) {
    const s = this.s;
    s.courtesyTileCount = count;
    s.charlestonSelectedIds = [];
    s.showCourtesyOptions = false;
    if (count === 0) {
      this.finishCharleston();
      this.emit();
      return;
    }
    s.courtesyCurrentSeat = 0;
    s.gameMessage = `Courtesy Pass: Select ${count} tile${count === 1 ? '' : 's'} to pass across`;
    this.emit();
  }

  skipCourtesyPass() { this.selectCourtesyCount(0); }

  private removeFromHand(p: GamePlayer, ids: string[]): Tile[] {
    const set = new Set(ids);
    const out = p.hand.filter((t) => set.has(t.id));
    p.hand = p.hand.filter((t) => !set.has(t.id));
    return out;
  }

  private botPick(p: GamePlayer, count: number): Tile[] {
    const indices = selectBotCharlestonTiles(p.hand, p.targetHand, count, this.rng);
    const ids = indices.filter((i) => i < p.hand.length).map((i) => p.hand[i].id);
    return this.removeFromHand(p, ids);
  }

  confirmCharlestonPass() {
    const s = this.s;
    if (!this.canConfirmCharleston(s)) return;

    if (s.charlestonPhase === CharlestonPhase.Courtesy && s.courtesyTileCount > 0) {
      s.pendingPasses[HUMAN] = this.removeFromHand(this.human, s.charlestonSelectedIds);
      s.charlestonSelectedIds = [];
      s.courtesyCurrentSeat = Math.min(s.courtesyCurrentSeat + 1, 4);
      s.gameMessage = 'Tiles passed — waiting for other players...';
      this.emit();
      this.runSoloCourtesySequence();
      return;
    }

    const buckets: Record<number, Tile[]> = { [HUMAN]: this.removeFromHand(this.human, s.charlestonSelectedIds) };
    s.players.forEach((p, i) => { if (p.isBot) buckets[i] = this.botPick(p, 3); });
    this.exchange(buckets);
    s.charlestonSelectedIds = [];
    this.advanceCharlestonPhase();
    this.emit();
  }

  private exchange(buckets: Record<number, Tile[]>) {
    const s = this.s;
    const dir = phaseDirection(s.charlestonPhase);
    for (let i = 0; i < 4; i++) s.players[receiverSeat(i, dir)].hand.push(...(buckets[i] ?? []));
    for (const p of s.players) if (p.isBot) p.hand = sortTiles(p.hand);
    for (const p of s.players) if (p.isBot) p.targetHand = selectBestTargetHand(p.hand, this.card);
  }

  private runSoloCourtesySequence() {
    const step = () => {
      const s = this.s;
      if (s.charlestonPhase !== CharlestonPhase.Courtesy || s.courtesyTileCount <= 0) return;
      // Skip seats that already submitted.
      while (s.courtesyCurrentSeat < 4 && s.pendingPasses[s.courtesyCurrentSeat]) s.courtesyCurrentSeat++;
      if (s.courtesyCurrentSeat >= 4) { this.finalizeSoloCourtesyExchange(); return; }
      this.after(0.9, 0.9, () => {
        const i = this.s.courtesyCurrentSeat;
        const p = this.s.players[i];
        if (p?.isBot) this.s.pendingPasses[i] = this.botPick(p, this.s.courtesyTileCount);
        this.s.courtesyCurrentSeat = Math.min(i + 1, 4);
        this.emit();
        step();
      });
    };
    step();
  }

  private finalizeSoloCourtesyExchange() {
    const s = this.s;
    if (![0, 1, 2, 3].every((i) => s.pendingPasses[i])) return;
    this.exchange(s.pendingPasses);
    s.pendingPasses = {};
    s.charlestonSelectedIds = [];
    this.advanceCharlestonPhase();
    this.emit();
  }

  private advanceCharlestonPhase() {
    const s = this.s;
    if (s.charlestonPhase === CharlestonPhase.Courtesy) { this.finishCharleston(); return; }
    if (s.charlestonPhase === CharlestonPhase.FirstLeft) s.showStopCharlestonOption = true;
    if (s.charlestonPhase === CharlestonPhase.SecondLeft) s.showStopCharlestonOption = false;
    const next = (s.charlestonPhase + 1) as CharlestonPhase;
    s.charlestonPhase = next;
    if (next === CharlestonPhase.Courtesy) {
      s.pendingPasses = {};
      s.charlestonSelectedIds = [];
      s.showCourtesyOptions = true;
      s.courtesyCurrentSeat = 0;
      s.gameMessage = 'Courtesy Pass: Choose how many tiles to pass across (0–3)';
    } else {
      s.gameMessage = `${phaseGroupLabel(next)}: Select 3 tiles to pass ${phaseDirection(next)}`;
    }
  }

  stopCharlestonEarly() {
    if (!this.canStopCharleston(this.s)) return;
    this.s.showStopCharlestonOption = false;
    this.finishCharleston();
    this.emit();
  }

  continueCharleston() {
    this.s.showStopCharlestonOption = false;
    this.emit();
  }

  private finishCharleston() {
    const s = this.s;
    // Return any stranded pass tiles (defensive, mirrors iOS).
    for (const [seatStr, tiles] of Object.entries(s.pendingPasses)) {
      const p = s.players[Number(seatStr)];
      if (!p) continue;
      const held = new Set(p.hand.map((t) => t.id));
      const back = tiles.filter((t) => !held.has(t.id));
      if (back.length) p.hand = sortTiles([...p.hand, ...back]);
    }
    s.pendingPasses = {};
    s.charlestonSelectedIds = [];
    s.showCourtesyOptions = false;
    s.showStopCharlestonOption = false;
    for (const p of s.players) if (p.hand.length > 13) p.hand = p.hand.slice(0, 13);
    s.status = 'playing';
    s.gameMessage = `Charleston complete! ${this.human.name} — draw a tile.`;
    for (const p of s.players) if (p.isBot) p.targetHand = selectBestTargetHand(p.hand, this.card);
  }

  // MARK: - Draw / discard

  drawTile() {
    const s = this.s;
    if (s.status !== 'playing' || s.currentPlayerIndex !== HUMAN || s.hasDrawnThisTurn) return;
    if (s.callAvailable || s.awaitingCall || s.showCallTileSelection) return;
    if (s.wall.length === 0) { this.declareWallGame(); this.emit(); return; }
    const tile = s.wall.shift()!;
    this.human.hand.push(tile);
    s.hasDrawnThisTurn = true;
    s.lastDrawnTileId = tile.id;
    s.invalidMahjongMessage = null;
    s.callAvailable = false;
    s.availableCalls = [];
    s.gameMessage = `${this.human.name} is thinking…`;
    this.emit();
  }

  /** Tap on a hand tile: joker swap, Charleston/call picking, or discard selection. */
  selectTile(tileId: string) {
    const s = this.s;
    if (s.jokerSwapMode) { this.handleJokerSwapSelection(tileId); return; }
    if (s.currentPlayerIndex !== HUMAN) return;
    s.selectedTileId = s.selectedTileId === tileId ? null : tileId;
    this.emit();
  }

  discardSelectedTile() {
    const s = this.s;
    if (s.currentPlayerIndex !== HUMAN || !s.hasDrawnThisTurn || !s.selectedTileId) return;
    const idx = this.human.hand.findIndex((t) => t.id === s.selectedTileId);
    if (idx < 0) return;
    const [tile] = this.human.hand.splice(idx, 1);
    s.discardPile.push({ tile, by: this.human.name });
    s.lastDiscardedTile = tile;
    s.lastDiscardPlayerIndex = HUMAN;
    s.selectedTileId = null;
    s.hasDrawnThisTurn = false;
    s.lastDrawnTileId = null;
    s.callAvailable = false;
    s.availableCalls = [];
    s.awaitingCall = false;
    s.invalidMahjongMessage = null;
    s.gameMessage = `${this.human.name} discarded ${displayName(tile)}`;
    this.checkAllPlayersForCalls(HUMAN);
    this.emit();
  }

  // MARK: - Calls

  expandManualCall() { this.s.manualCallExpanded = true; this.emit(); }

  callTile(type: CallType) {
    const d = this.s.lastDiscardedTile;
    if (!d || d.suit === 'Joker') return;
    this.executeCall(HUMAN, type, d);
    this.emit();
  }

  callBestAvailable() {
    const order: CallType[] = ['Sextet', 'Quint', 'Kong', 'Pung'];
    const best = order.find((c) => this.s.availableCalls.includes(c));
    if (best) this.beginCallTileSelection(best);
  }

  beginCallTileSelection(type: CallType) {
    const s = this.s;
    const d = s.lastDiscardedTile;
    if (!d || d.suit === 'Joker') return;
    if (type === 'Mahjong!') { this.callTile('Mahjong!'); return; }
    const required = { Pung: 2, Kong: 3, Quint: 4, Sextet: 5 }[type];
    s.showCallTileSelection = true;
    s.callTileSelectionType = type;
    s.callSelectedIds = [];
    s.callRequiredCount = required;
    s.gameMessage = `Select ${required} tile${required === 1 ? '' : 's'} from your hand for ${type}`;
    // Picking tiles is the player's answer — hold the window open while they choose.
    this.cancel(this.callWatchdog);
    this.callWatchdog = null;
    s.callWindowDeadline = null;
    this.emit();
  }

  toggleCallTileSelection(tileId: string) {
    const s = this.s;
    if (!this.human.hand.some((t) => t.id === tileId)) return;
    const i = s.callSelectedIds.indexOf(tileId);
    if (i >= 0) s.callSelectedIds.splice(i, 1);
    else if (s.callSelectedIds.length < s.callRequiredCount) s.callSelectedIds.push(tileId);
    this.emit();
  }

  /** Auto-pick matching naturals first, then jokers — a convenience the web adds. */
  autoPickCallTiles() {
    const s = this.s;
    const d = s.lastDiscardedTile;
    if (!d || !s.showCallTileSelection) return;
    const naturals = this.human.hand.filter((t) => t.suit !== 'Joker' && matchesForGrouping(t, d));
    const jokers = this.human.hand.filter((t) => t.suit === 'Joker');
    s.callSelectedIds = [...naturals, ...jokers].slice(0, s.callRequiredCount).map((t) => t.id);
    this.emit();
  }

  canConfirmCallSelection(s: GameState = this.snapshot) {
    return s.callSelectedIds.length === s.callRequiredCount;
  }

  confirmCallSelection() {
    const s = this.s;
    const d = s.lastDiscardedTile;
    const type = s.callTileSelectionType;
    if (!d || !type) return;
    const selected = this.human.hand.filter((t) => s.callSelectedIds.includes(t.id));
    if (selected.length !== s.callRequiredCount) {
      s.invalidMahjongMessage = `Select exactly ${s.callRequiredCount} tile${s.callRequiredCount === 1 ? '' : 's'} for ${type}.`;
      this.emit();
      return;
    }
    if (!selected.every((t) => t.suit === 'Joker' || matchesForGrouping(t, d))) {
      s.invalidMahjongMessage = `Invalid ${type}: each tile must match the ${displayName(d)} or be a joker.`;
      s.gameMessage = 'Invalid selection — pick matching tiles or jokers.';
      this.emit();
      return;
    }
    s.invalidMahjongMessage = null;
    const exposed = [d, ...this.removeFromHand(this.human, s.callSelectedIds)];
    this.removeFromDiscardPile(d);
    this.human.exposedSets.push(exposed);
    s.currentPlayerIndex = HUMAN;
    s.hasDrawnThisTurn = true;
    s.showCallTileSelection = false;
    s.callTileSelectionType = null;
    s.callSelectedIds = [];
    s.callRequiredCount = 0;
    s.selectedTileId = null;
    this.pendingBotCall = null;
    this.closeCallWindow(d);
    s.gameMessage = `${this.human.name} called ${type}! Now discard a tile.`;
    // Edge case (mirrors the bot guard in executeBotDiscard): a call that uses up
    // every concealed tile leaves nothing to discard — check for a win, else move on.
    if (this.human.hand.length === 0) {
      this.attemptMahjong(HUMAN, null);
      if (s.status !== 'completed') {
        s.invalidMahjongMessage = null;
        this.proceedWithTurn();
      }
    }
    this.emit();
  }

  cancelCallSelection() {
    const s = this.s;
    s.showCallTileSelection = false;
    s.callTileSelectionType = null;
    s.callSelectedIds = [];
    s.callRequiredCount = 0;
    // Back to the prompt; re-arm the decision timer.
    if (s.callAvailable) this.armCallWindowWatchdog();
    this.emit();
  }

  dismissCallOptions() {
    const s = this.s;
    s.callAvailable = false;
    s.availableCalls = [];
    s.showCallTileSelection = false;
    s.callTileSelectionType = null;
    s.callSelectedIds = [];
    this.cancel(this.callWatchdog);
    this.callWatchdog = null;
    const d = s.lastDiscardedTile;
    if (d) this.closeCallWindow(d);
    const pending = this.pendingBotCall;
    this.pendingBotCall = null;
    if (pending && d) this.executeCall(pending.idx, pending.type, d);
    else this.proceedWithTurn();
    this.emit();
  }

  private removeFromDiscardPile(t: Tile) {
    const pile = this.s.discardPile;
    for (let i = pile.length - 1; i >= 0; i--) if (pile[i].tile.id === t.id) { pile.splice(i, 1); return; }
  }

  private executeCall(idx: number, type: CallType, discarded: Tile) {
    const s = this.s;
    if (type === 'Mahjong!') { this.attemptMahjong(idx, discarded); return; }
    const needed = { Pung: 2, Kong: 3, Quint: 4, Sextet: 5 }[type];
    const p = s.players[idx];
    const naturals = p.hand.filter((t) => t.suit !== 'Joker' && matchesForGrouping(t, discarded)).slice(0, needed);
    const jokers = p.hand.filter((t) => t.suit === 'Joker').slice(0, needed - naturals.length);
    const exposed = [discarded, ...this.removeFromHand(p, [...naturals, ...jokers].map((t) => t.id))];
    this.removeFromDiscardPile(discarded);
    p.exposedSets.push(exposed);
    s.currentPlayerIndex = idx;
    s.hasDrawnThisTurn = true;
    s.gameMessage = `${p.name} called ${type}! ${p.isBot ? '' : 'Now discard a tile.'}`.trim();

    s.callAvailable = false;
    s.availableCalls = [];
    this.pendingBotCall = null;
    s.selectedTileId = null;
    this.closeCallWindow(discarded);
    if (p.isBot) {
      p.hand = sortTiles(p.hand);
      this.performBotJokerSwaps(idx);
      this.after(1.5, 2.2, () => { this.executeBotDiscard(idx); this.emit(); });
    }
  }

  private nonMahjongCallsFor(i: number, d: Tile): CallType[] {
    if (d.suit === 'Joker') return [];
    const hand = this.s.players[i].hand;
    const m = hand.filter((t) => matchesForGrouping(t, d)).length;
    const j = hand.filter((t) => t.suit === 'Joker').length;
    const calls: CallType[] = [];
    if (m + j >= 2) calls.push('Pung');
    if (m + j >= 3) calls.push('Kong');
    if (m + j >= 4) calls.push('Quint');
    if (d.suit === 'Flower' && m + j >= 5) calls.push('Sextet');
    return calls;
  }

  private shouldBotCall(i: number, d: Tile): boolean {
    const p = this.s.players[i];
    const target = p.targetHand;
    if (!target || target.concealed) return false;
    const m = p.hand.filter((t) => matchesForGrouping(t, d)).length;
    return target.groups.some((g) => g.count >= 3 && tileMatchesGroup(d.suit, d.value, g) && m >= 1);
  }

  private checkAllPlayersForCalls(discarder: number) {
    const s = this.s;
    const d = s.lastDiscardedTile;
    if (!d) { this.proceedWithTurn(); return; }
    if (d.suit === 'Joker') {
      s.availableCalls = [];
      s.callAvailable = false;
      this.pendingBotCall = null;
      s.callResponseDiscardId = null;
      s.eligibleCallSeats = [];
      this.proceedWithTurn();
      return;
    }
    if (s.callResponseDiscardId !== d.id) {
      s.callResponseDiscardId = d.id;
      s.eligibleCallSeats = [];
      s.manualCallExpanded = false;
    }

    const humanCalls: CallType[] = [];
    let botCall: { idx: number; type: CallType } | null = null;
    let botMahjong: number | null = null;

    for (let i = 0; i < 4; i++) {
      if (i === discarder) continue;
      const p = s.players[i];
      if (p.isBot) {
        if (canCallForMahjong(d, p.hand, p.exposedSets, this.card)) { botMahjong = i; break; }
        const calls = canCallTileForExposure(d, p.hand, p.exposedSets, p.targetHand);
        if (calls.some((c) => c !== 'Mahjong!') && this.shouldBotCall(i, d)) {
          const type: CallType = calls.includes('Sextet') ? 'Sextet' : calls.includes('Quint') ? 'Quint' : calls.includes('Kong') ? 'Kong' : 'Pung';
          botCall = { idx: i, type };
        }
      } else {
        const calls = this.nonMahjongCallsFor(i, d);
        humanCalls.push(...calls);
        if (canCallForMahjong(d, p.hand, p.exposedSets, this.card)) humanCalls.push('Mahjong!');
        if (humanCalls.length) s.eligibleCallSeats.push(i);
      }
    }

    if (botMahjong != null) {
      const idx = botMahjong;
      // Matches iOS solo: the bot's claim wins; the table pauses so the
      // announcement is readable, then the bot declares.
      s.awaitingCall = true;
      const discardId = d.id;
      this.after(6, 8, () => {
        s.awaitingCall = false;
        if (s.lastDiscardedTile?.id !== discardId || s.status !== 'playing') return;
        const p = s.players[idx];
        if (canCallForMahjong(d, p.hand, p.exposedSets, this.card)) {
          this.attemptMahjong(idx, d);
          if ((s.status as GameStatus) === 'completed') { this.emit(); return; }
        }
        this.closeCallWindow(d);
        this.proceedWithTurn();
        this.emit();
      });
      return;
    }

    if (humanCalls.length) {
      s.availableCalls = humanCalls;
      s.callAvailable = true;
      this.pendingBotCall = botCall;
      s.gameMessage = `${displayName(d)} discarded — Call?`;
      this.armCallWindowWatchdog();
      return;
    }

    if (botCall) {
      const call = botCall;
      s.awaitingCall = true;
      const discardId = d.id;
      this.after(2, 3, () => {
        s.awaitingCall = false;
        if (s.lastDiscardedTile?.id !== discardId) return;
        this.executeCall(call.idx, call.type, d);
        this.emit();
      });
      return;
    }

    this.closeCallWindow(d);
    this.proceedWithTurn();
  }

  private closeCallWindow(d: Tile) {
    const s = this.s;
    s.callAvailable = false;
    s.availableCalls = [];
    s.callResponseDiscardId = null;
    s.eligibleCallSeats = [];
    s.lastFinalizedCallDiscardId = d.id;
    s.callWindowDeadline = null;
    this.cancel(this.callWatchdog);
    this.callWatchdog = null;
  }

  private armCallWindowWatchdog() {
    this.cancel(this.callWatchdog);
    const discardId = this.s.lastDiscardedTile?.id;
    this.s.callWindowTotalMs = CALL_WINDOW_MS * this.speed;
    this.s.callWindowDeadline = Date.now() + this.s.callWindowTotalMs;
    this.callWatchdog = this.after(CALL_WINDOW_MS / 1000, CALL_WINDOW_MS / 1000, () => {
      this.callWatchdog = null;
      if (this.s.lastDiscardedTile?.id !== discardId || this.s.callResponseDiscardId !== discardId) return;
      if (this.s.showCallTileSelection) return;
      this.dismissCallOptions();
    });
  }

  private proceedWithTurn() {
    const s = this.s;
    s.currentPlayerIndex = (s.currentPlayerIndex + 1) % 4;
    s.hasDrawnThisTurn = false;
    s.invalidMahjongMessage = null;
    const p = s.players[s.currentPlayerIndex];
    if (p.isBot) {
      s.gameMessage = `${p.name} is thinking...`;
      this.after(1.0, 1.7, () => { this.executeBotTurn(); this.emit(); });
    } else {
      s.gameMessage = `${p.name}'s turn — draw a tile.`;
    }
  }

  // MARK: - Joker swap

  startJokerSwap() {
    const s = this.s;
    if (s.status !== 'playing') return;
    const anyJoker = s.players.some((p) => p.exposedSets.some((set) => set.some((t) => t.suit === 'Joker')));
    if (!anyJoker) { s.gameMessage = 'No jokers in exposed sets to swap.'; this.emit(); return; }
    if (!this.matchingTileForJokerSwap(s.players, HUMAN)) { s.gameMessage = 'No matching tiles in your hand for joker swap.'; this.emit(); return; }
    s.jokerSwapMode = true;
    s.selectedTileId = null;
    s.gameMessage = 'Select a tile from your hand to swap for a joker.';
    this.emit();
  }

  cancelJokerSwap() {
    const s = this.s;
    s.jokerSwapMode = false;
    if (s.currentPlayerIndex === HUMAN) {
      s.gameMessage = s.hasDrawnThisTurn ? `${this.human.name} — select a tile to discard.` : `${this.human.name}'s turn — draw a tile.`;
    } else s.gameMessage = '';
    this.emit();
  }

  private matchingTileForJokerSwap(players: GamePlayer[], idx: number) {
    for (const p of players) for (const set of p.exposedSets) {
      if (!set.some((t) => t.suit === 'Joker')) continue;
      const ref = set.find((t) => t.suit !== 'Joker');
      if (ref && players[idx].hand.some((t) => matchesForGrouping(t, ref))) return true;
    }
    return false;
  }

  private handleJokerSwapSelection(tileId: string) {
    const s = this.s;
    const hand = this.human.hand;
    const hi = hand.findIndex((t) => t.id === tileId);
    if (hi < 0) return;
    const selected = hand[hi];
    if (selected.suit === 'Joker') { s.gameMessage = 'Select a non-joker tile to swap.'; this.emit(); return; }
    for (const p of s.players) for (const set of p.exposedSets) {
      const ji = set.findIndex((t) => t.suit === 'Joker');
      if (ji < 0) continue;
      const ref = set.find((t) => t.suit !== 'Joker');
      if (ref && matchesForGrouping(ref, selected)) {
        const joker = set[ji];
        set[ji] = selected;
        hand[hi] = joker;
        if (this.matchingTileForJokerSwap(s.players, HUMAN)) s.gameMessage = 'Joker swapped! Select another tile to swap, or cancel.';
        else { s.jokerSwapMode = false; s.gameMessage = 'Joker swapped! No more swaps available.'; }
        this.emit();
        return;
      }
    }
    s.gameMessage = "That tile doesn't match any exposed set with a joker.";
    this.emit();
  }

  // MARK: - Mahjong

  declareMahjong() {
    this.attemptMahjong(HUMAN, null);
    this.emit();
  }

  private attemptMahjong(idx: number, claimed: Tile | null) {
    const s = this.s;
    const p = s.players[idx];
    const test = claimed ? [...p.hand, claimed] : p.hand;
    const result = checkWin(test, p.exposedSets, this.card);
    if (result) {
      if (claimed) { p.hand.push(claimed); this.removeFromDiscardPile(claimed); }
      this.endWithWinner(idx, result, `🎉 Mahjong! ${p.name} wins with ${result.name}!`);
    } else if (!p.isBot) {
      s.invalidMahjongMessage = `Your hand doesn't match any winning hand on the NMJL ${s.cardYear} card.`;
      s.gameMessage = 'Not a valid Mahjong hand. Keep playing!';
    }
  }

  private endWithWinner(idx: number, hand: NMJLHand, message: string) {
    const s = this.s;
    s.winningHand = hand;
    s.winnerName = s.players[idx].name;
    s.winnerIndex = idx;
    s.players[idx].score += hand.points;
    s.status = 'completed';
    s.isWallGame = false;
    s.showEndGameOverlay = true;
    s.gameMessage = message;
    s.callAvailable = false;
    s.availableCalls = [];
    s.awaitingCall = false;
    s.showCallTileSelection = false;
    s.callResponseDiscardId = null;
    s.eligibleCallSeats = [];
    s.callWindowDeadline = null;
    this.dispose();
  }

  private declareWallGame() {
    const s = this.s;
    if (s.status === 'completed' || s.showEndGameOverlay) return;
    s.status = 'completed';
    s.isWallGame = true;
    s.showEndGameOverlay = true;
    s.winningHand = null;
    s.winnerName = '';
    s.winnerIndex = -1;
    s.gameMessage = 'Wall Game! No tiles remaining — nobody wins.';
    s.callAvailable = false;
    s.availableCalls = [];
    s.awaitingCall = false;
    s.showCallTileSelection = false;
    s.callWindowDeadline = null;
    this.dispose();
  }

  // MARK: - Bots

  private executeBotTurn() {
    const s = this.s;
    const idx = s.currentPlayerIndex;
    const p = s.players[idx];
    if (s.status !== 'playing' || !p?.isBot) return;
    if (s.callAvailable || s.awaitingCall || s.showCallTileSelection || s.hasDrawnThisTurn) return;
    if (s.wall.length === 0) { this.declareWallGame(); return; }
    this.performBotJokerSwaps(idx);
    p.hand.push(s.wall.shift()!);
    this.performBotJokerSwaps(idx);
    const win = checkWin(p.hand, p.exposedSets, this.card);
    if (win) {
      this.endWithWinner(idx, win, `🎉 ${p.name} declares Mahjong with ${win.name}!`);
      return;
    }
    this.reevaluateBotTarget(idx);
    this.executeBotDiscard(idx);
  }

  private reevaluateBotTarget(idx: number) {
    const p = this.s.players[idx];
    const sum = (h: NMJLHand) => scoreTilesForTarget(p.hand, h).reduce((a, b) => a + b.score, 0);
    const current = p.targetHand ? sum(p.targetHand) : 0;
    const best = selectBestTargetHand(p.hand, this.card);
    if (best && sum(best) > current + 4) p.targetHand = best;
  }

  private performBotJokerSwaps(botIdx: number) {
    const s = this.s;
    const bot = s.players[botIdx];
    if (!bot?.isBot) return;
    for (let safety = 0; safety < 32; safety++) {
      let swapped = false;
      outer: for (const p of s.players) for (const set of p.exposedSets) {
        const ji = set.findIndex((t) => t.suit === 'Joker');
        if (ji < 0) continue;
        const ref = set.find((t) => t.suit !== 'Joker');
        if (!ref) continue;
        const hi = bot.hand.findIndex((t) => matchesForGrouping(t, ref));
        if (hi >= 0) {
          const joker = set[ji];
          set[ji] = bot.hand[hi];
          bot.hand[hi] = joker;
          s.gameMessage = `${bot.name} redeemed a Joker from ${p === s.players[HUMAN] ? 'your' : `${p.name}'s`} exposure.`;
          swapped = true;
          break outer;
        }
      }
      if (!swapped) return;
    }
  }

  private executeBotDiscard(idx: number) {
    const s = this.s;
    const p = s.players[idx];
    if (s.status !== 'playing') return;
    if (p.hand.length === 0) { this.proceedWithTurn(); return; }
    const di = selectBotDiscard(p.hand, p.targetHand, this.rng);
    const [tile] = p.hand.splice(di, 1);
    s.discardPile.push({ tile, by: p.name });
    s.lastDiscardedTile = tile;
    s.lastDiscardPlayerIndex = idx;
    s.hasDrawnThisTurn = false;
    s.callAvailable = false;
    s.availableCalls = [];
    s.awaitingCall = false;
    s.gameMessage = `${p.name} discarded ${displayName(tile)}`;
    this.checkAllPlayersForCalls(idx);
  }
}
