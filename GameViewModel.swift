import SwiftUI

@Observable
@MainActor
class GameViewModel {
    var players: [GamePlayer] = []
    var wall: [MahjongTile] = []
    var discardPile: [MahjongTile] = []
    var discardPlayerMap: [UUID: String] = [:]
    var currentPlayerIndex: Int = 0
    var gameStatus: GameStatus = .waiting
    var gameMode: GameMode = .solo
    var selectedTileIndex: Int?
    var turnTimer: Int = 30
    var showCallOptions: Bool = false
    var lastDiscardedTile: MahjongTile?
    var lastDiscardPlayerIndex: Int?
    var gameMessage: String = ""
    var showMahjongAnimation: Bool = false
    var moveHistory: [GameMove] = []

    var isOnlineMode: Bool = false
    var onlineGameId: String?
    var localSeatIndex: Int = 0
    var onlineSyncHandler: (() -> Void)?
    private var isApplyingRemoteState: Bool = false

    /// Authoritative seat sets owned by `OnlineGameViewModel`. Kept here so the
    /// game model can self-rectify `isBot` flags at every turn-advancement
    /// chokepoint without depending on an external orchestrator firing in time.
    /// Without this, a stale serialized state can leave the host driving a real
    /// invitee seat as a bot — the exact bug that skips the invitee right after
    /// Charleston completes and on every subsequent turn.
    var authoritativeRealSeats: Set<Int> = []
    var authoritativeHostBotSeats: Set<Int> = []

    /// Self-rectify bot flags using the authoritative seat sets. Safe to call any
    /// time; no-op in solo play.
    private func selfRectifyBotFlags() {
        guard isOnlineMode else { return }
        guard !authoritativeRealSeats.isEmpty || !authoritativeHostBotSeats.isEmpty else { return }
        for seat in 0..<players.count {
            if authoritativeRealSeats.contains(seat) {
                if players[seat].isBot {
                    print("\u{1FA7A} selfRectifyBotFlags: seat \(seat) was isBot=true but has a real participant — forcing false")
                    players[seat].isBot = false
                    players[seat].targetHand = nil
                }
            } else if authoritativeHostBotSeats.contains(seat) {
                if !players[seat].isBot { players[seat].isBot = true }
            }
        }
    }

    /// Whether the host may drive this seat automatically.
    ///
    /// `players[i].isBot` is a SERIALIZED field, so a single bad broadcast from ANY
    /// client can flip a human seat to `isBot = true` — and the moment the host believes
    /// a human is a bot, it starts playing that person's turns for them. That is the
    /// "the game started playing everyone's turns automatically" failure, and it is
    /// self-sustaining: the host re-broadcasts the bad flag straight back out to
    /// everyone, so the corruption spreads and sticks.
    ///
    /// `selfRectifyBotFlags` tries to repair the flag, but it BAILS OUTRIGHT when the
    /// authoritative sets are empty and only touches seats it recognises — so it cannot
    /// be the last line of defence. Consult the participant list DIRECTLY instead: a
    /// seat occupied by a real participant is a human, full stop, no matter what the
    /// mutable serialized flag currently claims.
    func seatIsDrivableBot(_ seat: Int) -> Bool {
        guard seat >= 0, seat < players.count else { return false }
        if isOnlineMode, authoritativeRealSeats.contains(seat) {
            if players[seat].isBot {
                print("🚫 seat \(seat) has a real participant but isBot=true — refusing to auto-drive it")
            }
            return false
        }
        return players[seat].isBot
    }

    private func notifyOnlineSync() {
        guard isOnlineMode, !isApplyingRemoteState else { return }
        onlineSyncHandler?()
    }

    var charlestonPhase: CharlestonPhase = .firstRight
    var charlestonSelectedIndices: Set<Int> = []
    var charlestonComplete: Bool = false
    var charlestonPendingPasses: [Int: [MahjongTile]] = [:]

    var hasSubmittedCharlestonPass: Bool {
        guard let idx = humanPlayerIndex else { return false }
        if isOnlineMode { return charlestonPendingPasses[idx] != nil }
        // Solo: only meaningful during the sequential courtesy pass, where the
        // human submits first and then waits while each bot picks in turn.
        // CRITICAL: while the chooser is still up the human hasn't actually picked
        // a count yet — so even if a stale `charlestonPendingPasses` entry lingers
        // (e.g. a defensive cap left it set), we MUST NOT treat them as submitted.
        // Otherwise the chooser is hidden behind the "Tiles passed" wait screen
        // and the solo game freezes right before courtesy.
        guard charlestonPhase.isCourtesy, courtesyTileCount > 0, !showCourtesyOptions else { return false }
        return charlestonPendingPasses[idx] != nil
    }

    var isOnlineHost: Bool { isOnlineMode && localSeatIndex == 0 }
    var courtesyTileCount: Int = 3
    var showCourtesyOptions: Bool = false
    /// During the courtesy (optional) across pass, the seat that is currently allowed
    /// to pick & submit their tiles. Players take turns starting with East (seat 0)
    /// and proceeding in playing order (1 → 2 → 3). Bots are auto-played by the host.
    var courtesyCurrentSeat: Int = 0

    var jokerSwapMode: Bool = false
    var jokerSwapSourceIndex: Int?

    var callAvailable: Bool = false {
        didSet {
            // Reset the manual-call expansion whenever the call window closes
            // so the next discard starts from a clean state.
            if !callAvailable { manualCallExpanded = false }
            if callAvailable && !oldValue {
                callWindowOpenedAt = Date()
            } else if !callAvailable {
                callWindowOpenedAt = nil
            }
        }
    }
    /// When the current call window (if any) was opened. Used by solo-mode
    /// freeze detection, which — unlike the online path — has no host/heartbeat
    /// watchdog to fall back on if a human simply never sees or acts on the
    /// call prompt.
    var callWindowOpenedAt: Date?
    var availableCalls: [CallType] = []
    /// When the only path to call is via jokers (no natural matching tile in
    /// hand for the discard), the popup is suppressed in favour of a quieter
    /// dedicated "Manual Call" button. Tapping that button flips this flag so
    /// the popup expands with Pung/Kong/Quint/Skip on demand.
    var manualCallExpanded: Bool = false
    var hasDrawnThisTurn: Bool = false
    var awaitingCall: Bool = false

    var selectedCardYear: NMJLCardYear = .year2026
    var winningHand: NMJLHand?
    var winnerName: String = ""
    var invalidMahjongMessage: String?

    var isWallGame: Bool = false
    var showEndGameOverlay: Bool = false

    var pendingCallPlayerIndex: Int?
    var pendingCallType: CallType?

    /// Tracks each non-discarder human seat's response to a call window in the
    /// current online game. Values: "skip", "called", or "hold". A seat that CAN
    /// call but hasn't acted yet is absent. "hold" means the player has explicitly
    /// requested unlimited time to decide — the host watchdog is cancelled and the
    /// window stays open until they switch to "skip" or "called". Cleared whenever
    /// the discard changes.
    var callResponses: [Int: String] = [:]
    /// The discard id that the current `callResponses` map corresponds to.
    var callResponseDiscardId: UUID?
    /// Seats (non-discarder humans) that actually have a non-mahjong call option
    /// on the current discard. Host uses this to know who must respond before
    /// finalizing the call window. Empty for non-host clients.
    var eligibleCallSeats: Set<Int> = []

    /// Tracks the last discard our local game has already processed (for calls / turn
    /// advancement). Prevents the host from re-processing the same discard every time
    /// a remote state echo arrives carrying the same `lastDiscardedTile`.
    var lastProcessedDiscardId: UUID?

    /// Host-only: the discard whose call window has already been finalized (turn
    /// advanced or call executed). Used to reject late `callResponses` echoes that
    /// re-enter `tryFinalizeCallWindow` — WITHOUT mistaking a freshly-opened window
    /// where every eligible seat auto-skipped synchronously for an "already closed"
    /// window (that prior heuristic stranded the turn on the host).
    var lastFinalizedCallDiscardId: UUID?
    /// Guards the stale-pre-exposure re-push so a rejection can never generate traffic
    /// in a loop with a peer that is rejecting us right back.
    private var lastPreExposureRepushDiscardId: UUID?

    /// Host-only watchdog that force-finalizes the call window if any eligible
    /// invitee fails to respond within a few seconds (e.g. dropped network packet,
    /// app backgrounded). Prevents the entire game from freezing on a stuck call.
    private var callWindowWatchdog: Task<Void, Never>?

    /// Host-only watchdog armed once a remote seat has responded "called" but the
    /// caller's exposure (executeCall + discard) hasn't actually landed yet. If the
    /// caller's client is stuck on the tile-selection sheet (sheet dismissed,
    /// app backgrounded, network drop), the whole table waits forever because
    /// `tryFinalizeCallWindow` defers to the caller. After a generous timeout we
    /// give up on the call, downgrade "called" → "skip", and advance the turn so
    /// the game keeps moving.
    private var callerFollowThroughWatchdog: Task<Void, Never>?

    /// Host-only watchdog that protects against a remote human seat going silent
    /// (network drop, app backgrounded, user walked away mid-turn). It first
    /// re-broadcasts state to nudge their client; if the seat is still stalled
    /// after a generous timeout the host takes over and force-draws / force-
    /// discards on their behalf so the rest of the table isn't held hostage.
    private var remoteTurnWatchdog: Task<Void, Never>?

    /// Non-host watchdog. After we (a non-host seat) discard a tile, we depend on
    /// the host to finalize the call window and advance the turn. If the host's
    /// reply state never reaches us (dropped packet, host briefly backgrounded,
    /// realtime hiccup), we sit forever with `currentPlayerIndex == ourSeat` and
    /// `hasDrawnThisTurn == false` — the exact "stuck after my discard" symptom
    /// shown in user diagnostics. This watchdog periodically re-broadcasts our
    /// post-discard state so the host gets another chance to process it.
    private var nonHostPostDiscardWatchdog: Task<Void, Never>?

    var showStopCharlestonOption: Bool = false

    var showCallTileSelection: Bool = false
    var callTileSelectionType: CallType?
    var callSelectedIndices: Set<Int> = []
    var callRequiredCount: Int = 0

    var activeCard: NMJLCard {
        NMJLCard.cardForYear(selectedCardYear)
    }

    var currentPlayer: GamePlayer? {
        guard currentPlayerIndex < players.count else { return nil }
        return players[currentPlayerIndex]
    }

    var humanPlayer: GamePlayer? {
        guard let idx = humanPlayerIndex, idx < players.count else { return nil }
        return players[idx]
    }

    var humanPlayerIndex: Int? {
        if isOnlineMode {
            return localSeatIndex < players.count ? localSeatIndex : nil
        }
        return players.firstIndex(where: { !$0.isBot })
    }

    var isHumanTurn: Bool {
        guard let idx = humanPlayerIndex else { return false }
        return currentPlayerIndex == idx
    }

    /// Single source of truth for whether the local human seat may draw RIGHT
    /// NOW. Used by `GameBoardView` for both the Draw button's enabled state
    /// and its lit/green styling. Returning false here also extinguishes the
    /// button — preventing the "draw button still glows green after I just
    /// discarded" bug while we wait for the call window / turn pointer to
    /// advance.
    var canDrawTile: Bool {
        guard gameStatus == .playing,
              isHumanTurn,
              !hasDrawnThisTurn,
              !callAvailable,
              !showCallTileSelection,
              !awaitingCall,
              !isCallWindowOpen else { return false }
        // If the most recent discard on the pile is OURS, the turn pointer
        // hasn't actually rotated past us yet (call window still finalising,
        // host echo in flight, etc.). Don't light Draw in that limbo state.
        if let me = humanPlayerIndex,
           let lastDiscarder = lastDiscardPlayerIndex,
           lastDiscarder == me,
           lastDiscardedTile != nil {
            return false
        }
        return true
    }

    /// True while a discard is awaiting call resolution (someone may still call
    /// pung/kong/quint/mahjong). The Draw button and other turn actions must be
    /// disabled until this window closes — otherwise the seat that just discarded
    /// can immediately re-draw before the next player's call lands.
    var isCallWindowOpen: Bool {
        guard let discarded = lastDiscardedTile else { return false }

        // A window we have already finalized is closed, whatever else says otherwise.
        if lastFinalizedCallDiscardId == discarded.id { return false }

        // TURN-POINTER INFERENCE — closes the window without waiting for a round trip.
        //
        // The host only calls `proceedWithTurn` AFTER finalizing the call window, so a
        // turn pointer that has moved off the discarder is proof the window is shut.
        // `callResponseDiscardId` is authoritative but SERIALIZED, so an invitee only
        // learns it was cleared when the host's next broadcast lands — which left their
        // Draw button greyed out for a full network round trip after the turn was
        // already theirs. The turn pointer is in the very same packet and says the same
        // thing sooner.
        //
        // This does NOT weaken the no-drawing-while-others-decide rule: for as long as
        // anyone may still claim the discard, the host keeps the turn ON the discarder,
        // so this branch cannot fire.
        if let discardSeat = lastDiscardPlayerIndex, currentPlayerIndex != discardSeat {
            return false
        }

        // AUTHORITATIVE AND TABLE-WIDE. The host owns the call window and nils out
        // `callResponseDiscardId` — which IS serialized — the instant it finalizes.
        // So while that field still points at the current discard, SOMEONE may yet
        // claim it: another human who hasn't answered, or a bot the host is still
        // deciding for. No seat may draw until it closes, INCLUDING a seat that has
        // already skipped.
        if callResponseDiscardId == discarded.id { return true }

        // Local-only signals, for a window this client is still resolving itself.
        return callAvailable || awaitingCall || showCallTileSelection || !eligibleCallSeats.isEmpty
    }

    /// Number of jokers currently in the local human's hand.
    var localJokerCount: Int {
        guard let idx = humanPlayerIndex, idx < players.count else { return 0 }
        return players[idx].hand.filter { $0.suit == .joker }.count
    }

    /// True if the local human has at least one natural (non-joker) match for
    /// the current discarded tile.
    var localHasNaturalMatchForDiscard: Bool {
        guard let idx = humanPlayerIndex, idx < players.count,
              let d = lastDiscardedTile, d.suit != .joker else { return false }
        return players[idx].hand.contains { $0.matchesForGrouping(d) }
    }

    /// Show the regular call-prompt popup automatically when the player has a
    /// natural match (or a Mahjong) — i.e. the "normal" case that a discard
    /// directly hits a tile they already hold. Joker-only manual calls take a
    /// different surface so the prompt isn't shoved in the player's face every
    /// time someone discards.
    var shouldAutoShowCallPrompt: Bool {
        guard callAvailable, !showCallTileSelection else { return false }
        if availableCalls.contains(.mahjong) { return true }
        if localHasNaturalMatchForDiscard { return true }
        return manualCallExpanded
    }

    /// Show a small standalone "Manual Call" button when the only way to call
    /// is through jokers (≥2 jokers, no natural match in hand). Hidden once the
    /// player taps it (popup expands instead).
    var shouldShowManualCallButton: Bool {
        guard callAvailable, !showCallTileSelection, !manualCallExpanded else { return false }
        if availableCalls.contains(.mahjong) { return false }
        if localHasNaturalMatchForDiscard { return false }
        guard localJokerCount >= 2 else { return false }
        return availableCalls.contains { $0 != .mahjong }
    }

    /// Enabled state for the inline "Call" button that sits next to Joker Swap.
    /// Becomes available when the local player has 2+ jokers and a joker-only
    /// call (Pung/Kong/Quint) is legal on the current discard. Tapping it
    /// expands the full call popup so they can pick the call type.
    var canUseManualCallButton: Bool {
        guard callAvailable, !showCallTileSelection, !manualCallExpanded else { return false }
        if availableCalls.contains(.mahjong) { return false }
        if localHasNaturalMatchForDiscard { return false }
        guard localJokerCount >= 2 else { return false }
        return availableCalls.contains { $0 != .mahjong }
    }

    func expandManualCall() {
        manualCallExpanded = true
    }

    func isLocalPlayer(_ player: GamePlayer) -> Bool {
        guard let idx = humanPlayerIndex, idx < players.count else { return false }
        return players[idx].id == player.id
    }

    // MARK: - Game Start

    func startNewGame(mode: GameMode, humanProfile: PlayerProfile? = nil) {
        gameMode = mode
        gameStatus = .charleston
        selectedTileIndex = nil
        discardPile = []
        discardPlayerMap = [:]
        moveHistory = []
        showMahjongAnimation = false
        hasDrawnThisTurn = false
        jokerSwapMode = false
        jokerSwapSourceIndex = nil
        charlestonPhase = .firstRight
        charlestonSelectedIndices = []
        charlestonComplete = false
        courtesyTileCount = 3
        showCourtesyOptions = false
        courtesyCurrentSeat = 0
        callAvailable = false
        availableCalls = []
        awaitingCall = false
        winningHand = nil
        winnerName = ""
        invalidMahjongMessage = nil
        isWallGame = false
        showEndGameOverlay = false
        pendingCallPlayerIndex = nil
        pendingCallType = nil
        lastDiscardPlayerIndex = nil
        showStopCharlestonOption = false
        showCallTileSelection = false
        callTileSelectionType = nil
        callSelectedIndices = []
        callRequiredCount = 0
        callResponses = [:]
        callResponseDiscardId = nil
        eligibleCallSeats = []

        wall = MahjongTile.createFullSet()

        let resolvedHumanProfile: PlayerProfile = {
            if let p = humanProfile, !p.displayName.isEmpty, p.displayName != "Garden Guest" {
                return PlayerProfile(displayName: p.displayName, avatarImage: p.avatarImage)
            }
            return PlayerProfile(displayName: "You", avatarImage: "daffodil")
        }()
        let botNames = [("Lily", "lily"), ("Rose", "pink_rose"), ("Daisy", "pdaisy")]

        var gamePlayers: [GamePlayer] = []
        gamePlayers.append(GamePlayer(
            profile: resolvedHumanProfile,
            seatPosition: .east,
            isCurrentTurn: true,
            isBot: false
        ))

        for (index, bot) in botNames.enumerated() {
            let botProfile = PlayerProfile(displayName: bot.0, avatarImage: bot.1)
            gamePlayers.append(GamePlayer(
                profile: botProfile,
                seatPosition: SeatPosition.allCases[index + 1],
                isBot: true
            ))
        }

        players = gamePlayers

        for i in 0..<players.count {
            var hand: [MahjongTile] = []
            for _ in 0..<13 {
                if !wall.isEmpty {
                    hand.append(wall.removeFirst())
                }
            }
            hand.sort { sortTile($0) < sortTile($1) }
            players[i].hand = hand
        }

        for i in 0..<players.count where players[i].isBot {
            players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
        }

        currentPlayerIndex = 0
        gameMessage = "1st Charleston: Select 3 tiles to pass right"
    }

    // MARK: - Charleston

    func toggleCharlestonSelection(at index: Int) {
        guard gameStatus == .charleston else { return }
        guard let playerIdx = humanPlayerIndex else { return }
        guard index < players[playerIdx].hand.count else { return }

        let maxTiles = charlestonPhase.isCourtesy ? courtesyTileCount : 3
        if charlestonSelectedIndices.contains(index) {
            charlestonSelectedIndices.remove(index)
        } else if charlestonSelectedIndices.count < maxTiles {
            charlestonSelectedIndices.insert(index)
        }
    }

    var canConfirmCharleston: Bool {
        if charlestonPhase.isCourtesy {
            return charlestonSelectedIndices.count == courtesyTileCount
        }
        return charlestonSelectedIndices.count == 3
    }

    var requiredTileCount: Int {
        charlestonPhase.isCourtesy ? courtesyTileCount : 3
    }

    func selectCourtesyCount(_ count: Int) {
        // In online mode only East (seat 0) gets to set the courtesy count.
        if isOnlineMode {
            guard localSeatIndex == 0 else { return }
        }
        courtesyTileCount = count
        charlestonSelectedIndices = []
        showCourtesyOptions = false
        if count == 0 {
            finishCharleston()
            notifyOnlineSync()
            return
        }
        // Sequential turn order — East picks first, then South, West, North.
        courtesyCurrentSeat = 0
        if isOnlineMode {
            updateCourtesyMessage()
            notifyOnlineSync()
            // Host auto-plays any bot that lands at the head of the queue.
            if isOnlineHost {
                advanceCourtesyTurnPastBots()
            }
        } else {
            gameMessage = "Courtesy Pass: Select \(count) tile\(count == 1 ? "" : "s") to pass across"
            notifyOnlineSync()
        }
    }

    private func updateCourtesyMessage() {
        guard charlestonPhase.isCourtesy, courtesyTileCount > 0 else { return }
        let mySeat = localSeatIndex
        if courtesyCurrentSeat == mySeat {
            gameMessage = "Courtesy Pass: Select \(courtesyTileCount) tile\(courtesyTileCount == 1 ? "" : "s") to pass across"
        } else if courtesyCurrentSeat < players.count {
            let name = players[courtesyCurrentSeat].profile.displayName
            gameMessage = "Courtesy Pass: Waiting for \(name) to pick…"
        }
    }

    /// Whether the local human can currently pick courtesy tiles (their seat's turn).
    var isMyCourtesyTurn: Bool {
        guard charlestonPhase.isCourtesy, courtesyTileCount > 0, !showCourtesyOptions else { return true }
        if !isOnlineMode { return true }
        return courtesyCurrentSeat == localSeatIndex
    }

    /// Host-only: if the seat whose turn it is happens to be a bot, auto-pick its
    /// tiles and advance until we land on a human seat (or all 4 seats have submitted).
    private func advanceCourtesyTurnPastBots() {
        guard isOnlineHost, charlestonPhase.isCourtesy, courtesyTileCount > 0 else { return }
        // CRITICAL: rectify bot flags BEFORE we auto-fill any seat. A stale
        // serialized state can momentarily mark a real invitee seat as isBot=true;
        // without this fix the host would auto-pick that seat's tiles and skip the
        // invitee entirely on the very first Charleston step (see user report).
        selfRectifyBotFlags()
        var safety = 0
        // Skip any seats that have already submitted (humans or bots). Whenever the
        // pointer lands on a bot that hasn't submitted yet, auto-pick for them.
        while safety < 16, courtesyCurrentSeat < players.count {
            let i = courtesyCurrentSeat
            if charlestonPendingPasses[i] != nil {
                advanceCourtesyTurn()
                safety += 1
                continue
            }
            if players[i].isBot {
                let indices = HandMatcher.selectBotCharlestonTiles(
                    hand: players[i].hand,
                    targetHand: players[i].targetHand,
                    count: courtesyTileCount
                )
                var botTiles: [MahjongTile] = []
                for idx in indices.sorted(by: >) where idx < players[i].hand.count {
                    botTiles.append(players[i].hand.remove(at: idx))
                }
                charlestonPendingPasses[i] = botTiles
                advanceCourtesyTurn()
                safety += 1
                continue
            }
            // Landed on a human seat that hasn't submitted yet — wait for them.
            break
        }
        if (0..<players.count).allSatisfy({ charlestonPendingPasses[$0] != nil }) {
            tryFinalizeCharlestonPass()
        } else {
            updateCourtesyMessage()
            notifyOnlineSync()
        }
    }

    private func advanceCourtesyTurn() {
        let next = courtesyCurrentSeat + 1
        courtesyCurrentSeat = min(next, players.count)
    }

    /// Solo-only: after the human submits their courtesy pick, walk the remaining
    /// seats (all bots) one at a time on a short delay so the player sees the
    /// turn-by-turn waiting screen. When every seat has submitted, execute the
    /// exchange and advance to gameplay.
    private func runSoloCourtesySequence() {
        guard !isOnlineMode, charlestonPhase.isCourtesy, courtesyTileCount > 0 else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var safety = 0
            while safety < 16,
                  self.charlestonPhase.isCourtesy,
                  self.courtesyTileCount > 0,
                  self.courtesyCurrentSeat < self.players.count {
                let i = self.courtesyCurrentSeat
                if self.charlestonPendingPasses[i] != nil {
                    self.advanceCourtesyTurn()
                    safety += 1
                    continue
                }
                self.updateCourtesyMessage()
                try? await Task.sleep(for: .milliseconds(900))
                if i < self.players.count, self.players[i].isBot {
                    let indices = HandMatcher.selectBotCharlestonTiles(
                        hand: self.players[i].hand,
                        targetHand: self.players[i].targetHand,
                        count: self.courtesyTileCount
                    )
                    var botTiles: [MahjongTile] = []
                    for idx in indices.sorted(by: >) where idx < self.players[i].hand.count {
                        botTiles.append(self.players[i].hand.remove(at: idx))
                    }
                    self.charlestonPendingPasses[i] = botTiles
                }
                self.advanceCourtesyTurn()
                safety += 1
            }
            self.finalizeSoloCourtesyExchange()
        }
    }

    private func finalizeSoloCourtesyExchange() {
        guard !isOnlineMode, charlestonPhase.isCourtesy, courtesyTileCount > 0 else { return }
        guard (0..<players.count).allSatisfy({ charlestonPendingPasses[$0] != nil }) else { return }
        for i in 0..<players.count {
            let receiverIdx: Int
            switch charlestonPhase.direction {
            case .right: receiverIdx = (i + 1) % 4
            case .across, .courtesyAcross: receiverIdx = (i + 2) % 4
            case .left: receiverIdx = (i + 3) % 4
            }
            let tiles = charlestonPendingPasses[i] ?? []
            players[receiverIdx].hand.append(contentsOf: tiles)
        }
        for i in 0..<players.count where players[i].isBot {
            players[i].hand.sort { sortTile($0) < sortTile($1) }
        }
        for i in 0..<players.count where players[i].isBot {
            players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
        }
        charlestonPendingPasses = [:]
        charlestonSelectedIndices = []
        advanceCharlestonPhase()
    }

    func skipCourtesyPass() {
        selectCourtesyCount(0)
    }

    func confirmCharlestonPass() {
        guard canConfirmCharleston else { return }
        guard let playerIdx = humanPlayerIndex else { return }

        let tileCount = charlestonPhase.isCourtesy ? courtesyTileCount : 3

        // Online multiplayer: each human submits their own pass; the host orchestrates the swap
        // once every seat (humans + bots) has submitted.
        if isOnlineMode {
            guard charlestonPendingPasses[playerIdx] == nil else { return }
            // Courtesy pass is sequential by turn order (East first). Block out-of-turn picks.
            if charlestonPhase.isCourtesy && courtesyTileCount > 0 && courtesyCurrentSeat != playerIdx {
                return
            }
            let selectedIndicesSorted = charlestonSelectedIndices.sorted(by: >)
            var passed: [MahjongTile] = []
            for idx in selectedIndicesSorted where idx < players[playerIdx].hand.count {
                passed.append(players[playerIdx].hand.remove(at: idx))
            }
            charlestonPendingPasses[playerIdx] = passed
            charlestonSelectedIndices = []
            if charlestonPhase.isCourtesy && courtesyTileCount > 0 {
                advanceCourtesyTurn()
                updateCourtesyMessage()
            } else {
                gameMessage = "Tiles passed — waiting for other players..."
            }
            notifyOnlineSync()
            if isOnlineHost {
                if charlestonPhase.isCourtesy && courtesyTileCount > 0 {
                    advanceCourtesyTurnPastBots()
                } else {
                    tryFinalizeCharlestonPass()
                }
            }
            return
        }

        // Solo courtesy pass is sequential: human (East) submits first, then each
        // bot picks one at a time on a brief delay so the user sees the waiting
        // screen advance through every seat before gameplay starts.
        if charlestonPhase.isCourtesy && courtesyTileCount > 0 {
            let selectedIndicesSorted = charlestonSelectedIndices.sorted(by: >)
            var passed: [MahjongTile] = []
            for idx in selectedIndicesSorted where idx < players[playerIdx].hand.count {
                passed.append(players[playerIdx].hand.remove(at: idx))
            }
            charlestonPendingPasses[playerIdx] = passed
            charlestonSelectedIndices = []
            advanceCourtesyTurn()
            updateCourtesyMessage()
            runSoloCourtesySequence()
            return
        }

        let selectedIndicesSorted = charlestonSelectedIndices.sorted(by: >)
        var humanPassTiles: [MahjongTile] = []
        for idx in selectedIndicesSorted {
            humanPassTiles.append(players[playerIdx].hand.remove(at: idx))
        }

        var passBuckets: [Int: [MahjongTile]] = [playerIdx: humanPassTiles]
        for i in 0..<players.count where players[i].isBot {
            let indices = HandMatcher.selectBotCharlestonTiles(
                hand: players[i].hand,
                targetHand: players[i].targetHand,
                count: tileCount
            )
            var botTiles: [MahjongTile] = []
            for idx in indices.sorted(by: >) {
                guard idx < players[i].hand.count else { continue }
                botTiles.append(players[i].hand.remove(at: idx))
            }
            passBuckets[i] = botTiles
        }

        for i in 0..<players.count {
            let receiverIdx: Int
            switch charlestonPhase.direction {
            case .right: receiverIdx = (i + 1) % 4
            case .across, .courtesyAcross: receiverIdx = (i + 2) % 4
            case .left: receiverIdx = (i + 3) % 4
            }
            let tiles = passBuckets[i] ?? []
            players[receiverIdx].hand.append(contentsOf: tiles)
        }

        for i in 0..<players.count where players[i].isBot {
            players[i].hand.sort { sortTile($0) < sortTile($1) }
        }

        for i in 0..<players.count where players[i].isBot {
            players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
        }

        charlestonSelectedIndices = []
        advanceCharlestonPhase()
        notifyOnlineSync()
    }

    /// Host-only escape hatch. Previously this auto-picked tiles for any seat
    /// whose Charleston pass never reached the host so the table could keep
    /// progressing. Per product decision the auto-pick is disabled — a missing
    /// seat must submit on their own (or be replaced/booted) rather than have
    /// the host pick tiles for them. Kept as a no-op so call sites continue to
    /// compile while we evaluate a different recovery flow.
    /// Host-only escape hatch invoked by the Charleston watchdog after a long stall.
    ///
    /// STRICT RULE: NEVER auto-pick tiles for a real human seat. Per the
    /// user-facing product rule "do not auto pick a missing seat's tiles",
    /// fabricating an invitee's pass is forbidden — doing so silently spends
    /// their tiles in exchanges they never participated in, so when their
    /// stale client finally syncs their hand has been gutted ("invitee
    /// received no tiles during the Charleston causing them to run out of
    /// tiles" symptom). The watchdog therefore only fills BOTS that the host
    /// has somehow lost track of — and otherwise refuses to advance,
    /// letting the broadcast / DB-pull / channel-rebuild recovery tiers do
    /// their job until the real human's pass finally lands.
    @discardableResult
    func forceFinalizeStuckCharleston(reason: String) -> Bool {
        guard isOnlineHost, isOnlineMode, gameStatus == .charleston else { return false }
        let isCourtesy = charlestonPhase.isCourtesy
        let tileCount = isCourtesy ? courtesyTileCount : 3
        guard tileCount > 0 else {
            // Courtesy with 0 tiles selected — just advance.
            if isCourtesy {
                charlestonPendingPasses = [:]
                charlestonSelectedIndices = []
                advanceCharlestonPhase()
                notifyOnlineSync()
                return true
            }
            return false
        }

        // Make sure bot flags are correct before we touch any seat. This is
        // critical — a stale serialized state can momentarily mark a real
        // invitee seat as isBot=true; without this rectify the watchdog
        // would treat the invitee as a bot and auto-fill their pass.
        selfRectifyBotFlags()

        // BOTS ONLY. Never fabricate a pass for a real human seat — see the
        // doc comment above. If a human seat is missing, abort and let the
        // upstream recovery tiers (broadcast retries, DB pull, channel
        // rebuild) keep trying until their submission actually lands.
        var autoFilled: [Int] = []
        for i in 0..<players.count where players[i].isBot && charlestonPendingPasses[i] == nil {
            let indices = HandMatcher.selectBotCharlestonTiles(
                hand: players[i].hand,
                targetHand: players[i].targetHand,
                count: tileCount
            )
            var picked: [MahjongTile] = []
            for idx in indices.sorted(by: >) where idx < players[i].hand.count {
                picked.append(players[i].hand.remove(at: idx))
            }
            while picked.count < tileCount, !players[i].hand.isEmpty {
                picked.append(players[i].hand.removeFirst())
            }
            guard picked.count == tileCount else { continue }
            charlestonPendingPasses[i] = picked
            autoFilled.append(i)
        }
        if !autoFilled.isEmpty {
            print("\u{1F6A8} forceFinalizeStuckCharleston: \(reason) — auto-filled bot seats \(autoFilled) on \(charlestonPhase.displayName)")
        }

        // If any human seat is still missing, refuse to advance. The host
        // must wait on the real player's broadcast — never fabricate it.
        let missingHumans: [Int] = (0..<players.count).filter { i in
            !players[i].isBot && charlestonPendingPasses[i] == nil
        }
        guard missingHumans.isEmpty else {
            print("⏸ forceFinalizeStuckCharleston: refusing to advance \(charlestonPhase.displayName) — missing human seats \(missingHumans). Will keep waiting for their pass to land.")
            // Persist any bot fills we just made so subsequent ticks don't
            // re-pick for them, and re-broadcast so peers see the partial
            // pending map.
            if !autoFilled.isEmpty { notifyOnlineSync() }
            return false
        }

        guard (0..<players.count).allSatisfy({ charlestonPendingPasses[$0] != nil }) else {
            return false
        }

        if isCourtesy {
            // Mirror the non-courtesy finalize path: defensive normalization +
            // exchange + advance.
            for i in 0..<players.count {
                guard let pass = charlestonPendingPasses[i], !pass.isEmpty else { continue }
                let passIds = Set(pass.map { $0.id })
                players[i].hand.removeAll { passIds.contains($0.id) }
            }
            for i in 0..<players.count {
                let receiverIdx: Int
                switch charlestonPhase.direction {
                case .right: receiverIdx = (i + 1) % 4
                case .across, .courtesyAcross: receiverIdx = (i + 2) % 4
                case .left: receiverIdx = (i + 3) % 4
                }
                let tiles = charlestonPendingPasses[i] ?? []
                players[receiverIdx].hand.append(contentsOf: tiles)
            }
            for i in 0..<players.count where players[i].isBot {
                players[i].hand.sort { sortTile($0) < sortTile($1) }
            }
            for i in 0..<players.count where players[i].isBot {
                players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
            }
            charlestonPendingPasses = [:]
            charlestonSelectedIndices = []
            advanceCharlestonPhase()
            notifyOnlineSync()
            return true
        } else {
            tryFinalizeCharlestonPass()
            return true
        }
    }

    /// Host-only: once every seat has put their tiles into `charlestonPendingPasses`
    /// (bots fill in automatically here), execute the actual exchange and advance.
    func tryFinalizeCharlestonPass() {
        guard isOnlineHost, gameStatus == .charleston else { return }
        let tileCount = charlestonPhase.isCourtesy ? courtesyTileCount : 3
        guard tileCount > 0 else { return }

        // CRITICAL: rectify bot flags BEFORE we auto-fill any seat. A stale
        // serialized state from a non-host can momentarily mark a real invitee
        // seat as isBot=true; without this guard the host auto-fills the
        // invitee's pass and advances the phase, skipping them on the right pass
        // and stranding their real submission for a now-stale phase.
        selfRectifyBotFlags()

        // Auto-fill bots that haven't submitted yet.
        for i in 0..<players.count where players[i].isBot && charlestonPendingPasses[i] == nil {
            let indices = HandMatcher.selectBotCharlestonTiles(
                hand: players[i].hand,
                targetHand: players[i].targetHand,
                count: tileCount
            )
            var botTiles: [MahjongTile] = []
            for idx in indices.sorted(by: >) where idx < players[i].hand.count {
                botTiles.append(players[i].hand.remove(at: idx))
            }
            charlestonPendingPasses[i] = botTiles
        }

        // Wait until every seat has submitted.
        guard (0..<players.count).allSatisfy({ charlestonPendingPasses[$0] != nil }) else {
            notifyOnlineSync()
            return
        }

        // DEFENSIVE NORMALIZATION. A stale remote state can occasionally restore
        // a player's pre-pass hand while ALSO carrying their pendingPass entry —
        // a read-modify-write race where the second writer's payload didn't yet
        // include the first writer's hand reduction. Without this step the
        // exchange below would append the across-pass tiles on top of the un-
        // reduced hand, leaving the receiver with 16 tiles (the "host ended up
        // with too many tiles after the optional pass" symptom). Strip any tile
        // from each seat's hand that is still listed in their pendingPass.
        for i in 0..<players.count {
            guard let pass = charlestonPendingPasses[i], !pass.isEmpty else { continue }
            let passIds = Set(pass.map { $0.id })
            let before = players[i].hand.count
            players[i].hand.removeAll { passIds.contains($0.id) }
            if players[i].hand.count != before - pass.count {
                print("⚠️ tryFinalizeCharlestonPass: normalized seat \(i) hand (\(before) → \(players[i].hand.count)) — was carrying pass tiles that hadn't been removed.")
            }
        }

        // Execute the exchange.
        for i in 0..<players.count {
            let receiverIdx: Int
            switch charlestonPhase.direction {
            case .right: receiverIdx = (i + 1) % 4
            case .across, .courtesyAcross: receiverIdx = (i + 2) % 4
            case .left: receiverIdx = (i + 3) % 4
            }
            let tiles = charlestonPendingPasses[i] ?? []
            players[receiverIdx].hand.append(contentsOf: tiles)
        }

        for i in 0..<players.count where players[i].isBot {
            players[i].hand.sort { sortTile($0) < sortTile($1) }
        }
        for i in 0..<players.count where players[i].isBot {
            players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
        }

        charlestonPendingPasses = [:]
        charlestonSelectedIndices = []
        advanceCharlestonPhase()
        notifyOnlineSync()
    }

    private func advanceCharlestonPhase() {
        // Best-effort cleanup: prune `charleston_passes` rows for the phase we're
        // leaving so the table doesn't accumulate over the full Charleston cycle.
        // Phase-filtered queries already ignore stale rows, but a smaller table
        // shaves index work and keeps later phases as snappy as the first.
        // Host-only; failures are non-fatal (logged inside the service).
        if isOnlineMode, isOnlineHost, let gameId = onlineGameId {
            let leavingPhase = charlestonPhase.rawValue
            Task.detached {
                await OnlineGameService.shared.deleteCharlestonPasses(
                    gameId: gameId,
                    throughPhase: leavingPhase
                )
            }
        }

        guard let nextRaw = CharlestonPhase(rawValue: charlestonPhase.rawValue + 1) else {
            finishCharleston()
            return
        }

        if charlestonPhase == .firstLeft {
            showStopCharlestonOption = true
            // The Charleston only ends early if a bot or the human player explicitly
            // chooses to stop via the prompt — never automatically by code rule.
        }

        if charlestonPhase == .secondLeft {
            showStopCharlestonOption = false
        }

        charlestonPhase = nextRaw

        if nextRaw.isCourtesy {
            // BOUNDARY HYGIENE. Pending passes from the previous (third left or
            // second right) exchange must be cleared before the courtesy chooser
            // is shown — otherwise `hasSubmittedCharlestonPass` would short-circuit
            // the chooser behind the "Tiles passed" screen and freeze solo games
            // right before courtesy.
            charlestonPendingPasses = [:]
            charlestonSelectedIndices = []
            showCourtesyOptions = true
            courtesyCurrentSeat = 0
            gameMessage = isOnlineMode
                ? "Courtesy Pass: Waiting for East to choose how many tiles to pass…"
                : "Courtesy Pass: Choose how many tiles to pass across (0–3)"
            // East-only message override happens in the view; East sees the chooser.
            if isOnlineMode && localSeatIndex == 0 {
                gameMessage = "Courtesy Pass: Choose how many tiles to pass across (0–3)"
            }
        } else {
            let dirLabel = nextRaw.direction.rawValue.lowercased()
            gameMessage = "\(nextRaw.groupLabel): Select 3 tiles to \(dirLabel)"
        }
    }

    /// Whether the Charleston may still be stopped right now.
    ///
    /// The stop is a *boundary* decision: it is offered once the 1st Charleston's
    /// three passes are done, and it stays open only until the 2nd Charleston is
    /// actually underway. The moment ANY seat — human or bot — commits a pass,
    /// the window shuts for everyone.
    ///
    /// This has to be enforced, not just discouraged. `confirmCharlestonPass`
    /// physically REMOVES a seat's three tiles from their hand and parks them in
    /// `charlestonPendingPasses` to await the exchange. If the Charleston is ended
    /// at that point, the exchange never runs and nothing ever hands those tiles
    /// on — the seat walks into the play phase three tiles short, with their tiles
    /// stranded in a dictionary that is about to be discarded.
    ///
    /// Deriving the answer from `charlestonPendingPasses` (rather than a separate
    /// flag) means every client agrees without any extra syncing: the pending map
    /// is already part of the serialized state, so the button disappears on all
    /// four devices the instant the first seat commits.
    var canStopCharleston: Bool {
        showStopCharlestonOption
            && gameStatus == .charleston
            && charlestonPendingPasses.isEmpty
    }

    func stopCharlestonEarly() {
        // Enforce the window rather than trusting the button to have been hidden —
        // a stale tap, a queued gesture, or a remote client racing us can all land
        // here after someone has already committed a pass.
        guard canStopCharleston else {
            print("⛔️ stopCharlestonEarly ignored — 2nd Charleston already underway (pending seats: \(charlestonPendingPasses.keys.sorted()))")
            return
        }

        // Ending the Charleston is a table-wide decision, not a local one. Any seat
        // may make it (host or invitee): `finishCharleston` flips us to `.playing`
        // and `notifyOnlineSync` writes + broadcasts that state, which every peer
        // picks up in `applyRemoteState`. GameBoardView gates the Charleston screen
        // purely on `gameStatus`, so all four clients leave it together.
        showStopCharlestonOption = false
        finishCharleston()
        notifyOnlineSync()
    }

    func continueCharleston() {
        showStopCharlestonOption = false
        notifyOnlineSync()
    }

    private func finishCharleston() {
        // Re-rectify bot flags at the phase boundary. The very next event after
        // this is East's first play-phase draw → discard → proceedWithTurn, which
        // reads players[invitee].isBot to decide whether to auto-play. A stale
        // flag here is what causes the invitee to be skipped post-Charleston.
        selfRectifyBotFlags()

        // STRANDED-PASS RECOVERY. Any seat still holding an uncommitted pass has
        // already had those tiles REMOVED from their hand by `confirmCharlestonPass`
        // — they're parked in `charlestonPendingPasses` waiting for an exchange that
        // is now never going to run. Hand them straight back, or that seat enters the
        // play phase three tiles short.
        //
        // `canStopCharleston` prevents the ordinary route into this state, but two
        // clients can still race — a stop and a pass submission crossing in flight —
        // so the transition itself has to be safe rather than merely unreachable.
        //
        // Dedupe by tile id before returning: a stale remote merge can restore a
        // seat's pre-pass hand while STILL carrying their pendingPass entry (the same
        // read-modify-write race the exchange path guards against), and blindly
        // appending there would hand the seat the same three tiles twice.
        if !charlestonPendingPasses.isEmpty {
            for (seat, tiles) in charlestonPendingPasses where seat >= 0 && seat < players.count {
                guard !tiles.isEmpty else { continue }
                let alreadyHeld = Set(players[seat].hand.map { $0.id })
                let toReturn = tiles.filter { !alreadyHeld.contains($0.id) }
                guard !toReturn.isEmpty else { continue }
                players[seat].hand.append(contentsOf: toReturn)
                players[seat].hand.sort { sortTile($0) < sortTile($1) }
                print("↩️ finishCharleston: returned \(toReturn.count) stranded pass tile(s) to seat \(seat)")
            }
            charlestonPendingPasses = [:]
        }

        // Clear every Charleston-only surface so no client is left sitting behind a
        // "waiting for others" or courtesy screen after the table has moved on.
        charlestonSelectedIndices = []
        showCourtesyOptions = false
        showStopCharlestonOption = false

        // DEFENSIVE HAND-SIZE CAP. No player may enter the play phase with more
        // than 13 tiles — East draws their 14th on the first turn. A stale
        // remote merge that double-applies a courtesy exchange can otherwise
        // leave a seat at 14+ and immediately desync the next discard/call.
        // Trim from the tail (most recently received) so the original 13 stay.
        for i in 0..<players.count {
            if players[i].hand.count > 13 {
                let before = players[i].hand.count
                players[i].hand = Array(players[i].hand.prefix(13))
                print("⚠️ finishCharleston: trimmed seat \(i) hand \(before) → 13 (defensive cap)")
            }
        }

        charlestonComplete = true
        gameStatus = .playing
        let humanName = humanPlayer?.profile.displayName ?? "You"
        gameMessage = "Charleston complete! \(humanName) — draw a tile."

        for i in 0..<players.count where players[i].isBot {
            players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
        }
    }

    private func reevaluateBotTargetIfNeeded(botIdx: Int) {
        guard players[botIdx].isBot else { return }
        let currentScore: Int
        if let target = players[botIdx].targetHand {
            currentScore = HandMatcher.selectBestTargetHand(hand: players[botIdx].hand, card: activeCard) == nil ? 0 : scoreForTarget(hand: players[botIdx].hand, target: target)
        } else {
            currentScore = 0
        }

        if let best = HandMatcher.selectBestTargetHand(hand: players[botIdx].hand, card: activeCard) {
            let bestScore = scoreForTarget(hand: players[botIdx].hand, target: best)
            if bestScore > currentScore + 4 {
                players[botIdx].targetHand = best
            }
        }
    }

    private func scoreForTarget(hand: [MahjongTile], target: NMJLHand) -> Int {
        let scores = HandMatcher.scoreTilesForTarget(hand: hand, target: target)
        return scores.reduce(0) { $0 + $1.score }
    }

    // MARK: - Drawing & Discarding

    func drawTile() {
        guard let playerIdx = humanPlayerIndex,
              gameStatus == .playing,
              currentPlayerIndex == playerIdx,
              !hasDrawnThisTurn,
              !callAvailable,
              !awaitingCall,
              !showCallTileSelection else { return }

        // POST-DISCARD GUARD. After this seat discards in online play, the turn
        // pointer stays parked here until the host finalizes the call window and
        // broadcasts the advance. Because `discardSelectedTile` clears
        // `hasDrawnThisTurn`, without this guard the discarder can hit Draw
        // again immediately — producing the "keeps drawing tiles while other
        // clients are frozen" loop seen in multiplayer diagnostics. If we are
        // the last discarder and the call window for that discard hasn't been
        // resolved yet, refuse to draw.
        if isOnlineMode,
           let lastDiscardSeat = lastDiscardPlayerIndex,
           lastDiscardSeat == playerIdx,
           let lastDiscarded = lastDiscardedTile,
           callResponseDiscardId == lastDiscarded.id,
           lastFinalizedCallDiscardId != lastDiscarded.id {
            print("⏪ drawTile blocked — local seat \(playerIdx) just discarded and the call window hasn't resolved yet")
            return
        }

        guard !wall.isEmpty else {
            declareWallGame()
            return
        }

        var tile = wall.removeFirst()
        tile.isRevealed = true
        players[playerIdx].hand.append(tile)
        hasDrawnThisTurn = true
        invalidMahjongMessage = nil
        callAvailable = false
        availableCalls = []
        let humanName = players[playerIdx].profile.displayName
        // Use the same neutral "is thinking…" wording as bots so the announcement
        // doesn't reveal that the player drew anything — only their discard is
        // announced (matches the rule for what info is shared at the table).
        gameMessage = "\(humanName) is thinking…"
        notifyOnlineSync()
        armOrCancelRemoteHumanTurnWatchdog()
    }

    func selectTile(at index: Int) {
        guard let playerIdx = humanPlayerIndex else { return }

        // Joker swap is allowed at any time (not just on your turn), so
        // handle it BEFORE the turn-ownership guard below.
        if jokerSwapMode {
            handleJokerSwapSelection(at: index)
            return
        }

        guard currentPlayerIndex == playerIdx else { return }

        if selectedTileIndex == index {
            selectedTileIndex = nil
        } else {
            selectedTileIndex = index
        }
    }

    func discardSelectedTile() {
        guard let playerIdx = humanPlayerIndex,
              let tileIndex = selectedTileIndex,
              currentPlayerIndex == playerIdx,
              tileIndex < players[playerIdx].hand.count,
              hasDrawnThisTurn else { return }

        var tile = players[playerIdx].hand.remove(at: tileIndex)
        tile.isDiscarded = true
        discardPile.append(tile)
        discardPlayerMap[tile.id] = players[playerIdx].profile.displayName
        lastDiscardedTile = tile
        lastDiscardPlayerIndex = playerIdx
        lastProcessedDiscardId = tile.id
        selectedTileIndex = nil
        hasDrawnThisTurn = false
        callAvailable = false
        availableCalls = []
        awaitingCall = false
        invalidMahjongMessage = nil

        let move = GameMove(playerId: players[playerIdx].id, moveType: .discard, tiles: [tile])
        moveHistory.append(move)

        checkAllPlayersForCalls(discardedBy: playerIdx)
        notifyOnlineSync()
        armOrCancelRemoteHumanTurnWatchdog()
        armOrCancelNonHostPostDiscardWatchdog()
    }

    // MARK: - Call (NMJL Rules)

    func callTile(type: CallType) {
        guard let playerIdx = humanPlayerIndex,
              let discarded = lastDiscardedTile else { return }
        // NMJL rule: a discarded Joker can never be called.
        if discarded.suit == .joker { return }

        if isOnlineMode, callResponseDiscardId == discarded.id {
            callResponses[playerIdx] = "called"
        }

        executeCall(playerIndex: playerIdx, type: type, discarded: discarded)
    }

    func callBestAvailable() {
        let nonMahjong = availableCalls.filter { $0 != .mahjong }
        let best: CallType
        if nonMahjong.contains(.quint) {
            best = .quint
        } else if nonMahjong.contains(.kong) {
            best = .kong
        } else if nonMahjong.contains(.pung) {
            best = .pung
        } else {
            return
        }
        beginCallTileSelection(type: best)
    }

    func beginCallTileSelection(type: CallType) {
        guard humanPlayerIndex != nil,
              let discarded = lastDiscardedTile else { return }
        // NMJL rule: a discarded Joker can never be called.
        if discarded.suit == .joker { return }

        let requiredFromHand: Int
        switch type {
        case .pung: requiredFromHand = 2
        case .kong: requiredFromHand = 3
        case .quint: requiredFromHand = 4
        case .mahjong:
            callTile(type: .mahjong)
            return
        }

        showCallTileSelection = true
        callTileSelectionType = type
        callSelectedIndices = []
        callRequiredCount = requiredFromHand

        // CRITICAL (online): claim the call window NOW so the host doesn't finalize
        // past us while we pick tiles. Without this, every other seat could skip,
        // the host would proceedWithTurn(), and the next player would draw before
        // this caller's exposure + discard lands.
        //
        // Broadcast a caller-name-prefixed message ("Bob is calling Pung…") so
        // other players see a sensible status; the local picker prompt is set
        // AFTER the sync so it doesn't leak into the broadcast and confuse peers
        // (the previous version showed "Select 2 tiles…" on every player's screen).
        if isOnlineMode,
           let playerIdx = humanPlayerIndex,
           callResponseDiscardId == discarded.id {
            callResponses[playerIdx] = "called"
            let callerName = players[playerIdx].profile.displayName
            gameMessage = "\(callerName) is calling \(type.rawValue)…"
            notifyOnlineSync()
        }
        // Local picker prompt — set after the broadcast so it stays caller-only.
        gameMessage = "Select \(requiredFromHand) tile\(requiredFromHand == 1 ? "" : "s") from your hand for \(type.rawValue)"
    }

    func toggleCallTileSelection(at index: Int) {
        guard let playerIdx = humanPlayerIndex,
              index < players[playerIdx].hand.count else { return }

        if callSelectedIndices.contains(index) {
            callSelectedIndices.remove(index)
        } else if callSelectedIndices.count < callRequiredCount {
            callSelectedIndices.insert(index)
        }
    }

    var canConfirmCallSelection: Bool {
        callSelectedIndices.count == callRequiredCount
    }

    func confirmCallSelection() {
        guard let playerIdx = humanPlayerIndex,
              let discarded = lastDiscardedTile,
              let type = callTileSelectionType else { return }

        // The tile must STILL be in the discard pile. If it isn't — someone else claimed
        // it, or the table moved on while we were choosing — this call is stale, and
        // building an exposure around it now would conjure a duplicate of that tile into
        // existence (the removal below simply finds nothing to remove). Bail cleanly and
        // say so, rather than silently corrupting the deck.
        guard discardPile.contains(where: { $0.id == discarded.id }) else {
            showCallTileSelection = false
            callTileSelectionType = nil
            callSelectedIndices = []
            gameMessage = "That tile is no longer available to call."
            print("⚠️ confirmCallSelection: \(discarded.displayName) is no longer in the discard pile — call abandoned")
            return
        }

        // VALIDATE the picked tiles before exposing. Each selected tile must either
        // match the discarded tile (same suit+value) OR be a joker. Plus we must
        // have exactly the required count. Without this, players could expose a
        // pung/kong/quint with arbitrary tiles, breaking NMJL rules.
        let selectedTiles: [MahjongTile] = callSelectedIndices.compactMap { idx in
            idx < players[playerIdx].hand.count ? players[playerIdx].hand[idx] : nil
        }
        guard selectedTiles.count == callRequiredCount else {
            invalidMahjongMessage = "Select exactly \(callRequiredCount) tile\(callRequiredCount == 1 ? "" : "s") for \(type.rawValue)."
            return
        }
        let allEligible = selectedTiles.allSatisfy { tile in
            tile.suit == .joker || tile.matchesForGrouping(discarded)
        }
        guard allEligible else {
            invalidMahjongMessage = "Invalid \(type.rawValue): each tile must match the \(discarded.displayName) or be a joker."
            gameMessage = "Invalid selection — pick matching tiles or jokers."
            return
        }
        invalidMahjongMessage = nil

        if isOnlineMode, callResponseDiscardId == discarded.id {
            callResponses[playerIdx] = "called"
        }

        var exposedSet: [MahjongTile] = [discarded]
        let sortedIndices = callSelectedIndices.sorted(by: >)
        for idx in sortedIndices {
            exposedSet.append(players[playerIdx].hand.remove(at: idx))
        }

        if let lastIdx = discardPile.lastIndex(where: { $0.id == discarded.id }) {
            discardPile.remove(at: lastIdx)
        }
        players[playerIdx].exposedSets.append(exposedSet)
        currentPlayerIndex = playerIdx
        hasDrawnThisTurn = true

        showCallTileSelection = false
        callTileSelectionType = nil
        callSelectedIndices = []
        callRequiredCount = 0
        callAvailable = false
        availableCalls = []
        pendingCallPlayerIndex = nil
        pendingCallType = nil
        selectedTileIndex = nil
        callResponses = [:]
        callResponseDiscardId = nil
        eligibleCallSeats = []

        let humanName = players[playerIdx].profile.displayName
        gameMessage = "\(humanName) called \(type.rawValue)! Now discard a tile."
        notifyOnlineSync()
    }

    func cancelCallSelection() {
        showCallTileSelection = false
        callTileSelectionType = nil
        callSelectedIndices = []
        callRequiredCount = 0

        // If we had pre-claimed the call window in beginCallTileSelection, release
        // it so the host can finalize normally. We treat this as a skip from our
        // seat unless we've already exposed.
        if isOnlineMode,
           let discarded = lastDiscardedTile,
           let playerIdx = humanPlayerIndex,
           callResponseDiscardId == discarded.id,
           callResponses[playerIdx] == "called" {
            callResponses[playerIdx] = "skip"
            notifyOnlineSync()
        }
    }

    /// Player explicitly requested more time to decide on the current call. Cancels
    /// the host's auto-skip watchdog so the window stays open indefinitely. The
    /// player can later tap Skip or one of the call buttons to resolve.
    func holdCall() {
        guard isOnlineMode else { return }
        guard let discarded = lastDiscardedTile,
              callResponseDiscardId == discarded.id else { return }
        let mySeat = localSeatIndex
        // Don't override an existing call commitment.
        if callResponses[mySeat] == "called" { return }
        callResponses[mySeat] = "hold"
        if isOnlineHost {
            // Cancel our own watchdog — we're explicitly waiting on this seat now.
            callWindowWatchdog?.cancel()
            callWindowWatchdog = nil
        }
        notifyOnlineSync()
    }

    /// True when the local seat has placed the current call on hold.
    var localCallOnHold: Bool {
        guard isOnlineMode,
              let discarded = lastDiscardedTile,
              callResponseDiscardId == discarded.id else { return false }
        return callResponses[localSeatIndex] == "hold"
    }

    /// True when ANY seat has placed the current call on hold (used by host to
    /// suppress the watchdog).
    private var anySeatOnHold: Bool {
        callResponses.values.contains("hold")
    }

    func dismissCallOptions() {
        callAvailable = false
        availableCalls = []

        // Solo owns the whole decision, so the window is finished the moment it's
        // dismissed — retire its timeout. (Online must NOT do this here: the host may
        // still be waiting on other seats, and cancelling would drop the protection.)
        if !isOnlineMode {
            callWindowWatchdog?.cancel()
            callWindowWatchdog = nil
        }

        // Online mode: record this seat's skip and wait for the host to finalize
        // the window. Other humans (and the host) may still call this tile.
        if isOnlineMode {
            let mySeat = localSeatIndex
            if callResponseDiscardId == lastDiscardedTile?.id {
                callResponses[mySeat] = "skip"
            }
            // We have ANSWERED, so this seat is no longer deciding.
            //
            // `eligibleCallSeats` is LOCAL-ONLY — it is never serialized — so the
            // host's cleared copy can never reach us. Every "called" path funnels into
            // `executeCall`, which wipes the set; skip was the one path that didn't.
            // Leaving our own seat in it pins `isCallWindowOpen` true on this client
            // FOREVER, which pins `canDrawTile` false forever: the host finalizes,
            // advances the turn to us, and we can never draw. That is the observed
            // freeze — invitee seat 1 showing `callAvailable: false, calls: []` but
            // still `eligible: [1]`, with a dead Draw button on its own turn.
            eligibleCallSeats.remove(mySeat)
            if isOnlineHost {
                tryFinalizeCallWindow()
            } else {
                notifyOnlineSync()
            }
            return
        }

        // SOLO: this seat is the only decision-maker, so answering closes the window
        // outright. Without this, a skip left `callResponseDiscardId` still pointing at
        // the discard and our own seat still sitting in `eligibleCallSeats` — both of
        // which keep `isCallWindowOpen` true, which keeps `canDrawTile` false. The
        // player skips a call and then finds Draw dead on their own next turn.
        if let discarded = lastDiscardedTile {
            closeCallWindow(for: discarded)
        }

        if let botIdx = pendingCallPlayerIndex, let botCall = pendingCallType {
            guard let discarded = lastDiscardedTile else {
                proceedWithTurn()
                return
            }
            executeCall(playerIndex: botIdx, type: botCall, discarded: discarded)
            pendingCallPlayerIndex = nil
            pendingCallType = nil
        } else {
            proceedWithTurn()
        }
    }

    private func executeCall(playerIndex: Int, type: CallType, discarded: MahjongTile) {
        switch type {
        case .pung:
            executePung(playerIndex: playerIndex, discarded: discarded)
        case .kong:
            executeKong(playerIndex: playerIndex, discarded: discarded)
        case .quint:
            executeQuint(playerIndex: playerIndex, discarded: discarded)
        case .mahjong:
            attemptMahjong(playerIndex: playerIndex, claimedTile: discarded)
            return
        }

        callAvailable = false
        availableCalls = []
        pendingCallPlayerIndex = nil
        pendingCallType = nil
        selectedTileIndex = nil
        callResponses = [:]
        callResponseDiscardId = nil
        eligibleCallSeats = []
        callerFollowThroughWatchdog?.cancel()
        callerFollowThroughWatchdog = nil
        if players[playerIndex].isBot {
            players[playerIndex].hand.sort { sortTile($0) < sortTile($1) }
        }

        if players[playerIndex].isBot {
            performBotJokerSwaps(botIdx: playerIndex)
            notifyOnlineSync()
            Task {
                // Hold the "X called Pung/Kong/Quint!" announcement visible for a
                // beat before the bot's follow-up discard overwrites the message.
                // Trimmed from 4.5-6.0s: this is cosmetic dwell time, and stacked on
                // top of the 3-4.5s call delay it made a single bot call cost the
                // table 7.5-10.5s of dead air.
                try? await Task.sleep(for: .seconds(Double.random(in: 1.5...2.2)))
                executeBotDiscard(botIdx: playerIndex)
            }
        }
        armOrCancelRemoteHumanTurnWatchdog()
    }

    private func executePung(playerIndex: Int, discarded: MahjongTile) {
        let matchingIndices = players[playerIndex].hand.indices.filter {
            players[playerIndex].hand[$0].matchesForGrouping(discarded)
        }

        var exposedSet: [MahjongTile] = [discarded]

        let realMatches = Array(matchingIndices.prefix(2))
        var jokersNeeded = 2 - realMatches.count

        let indicesToRemove = realMatches.sorted(by: >)
        for idx in indicesToRemove {
            exposedSet.append(players[playerIndex].hand.remove(at: idx))
        }

        if jokersNeeded > 0 {
            let jokerIndices = players[playerIndex].hand.indices.filter {
                players[playerIndex].hand[$0].suit == .joker
            }
            for jIdx in jokerIndices.prefix(jokersNeeded).sorted(by: >) {
                exposedSet.append(players[playerIndex].hand.remove(at: jIdx))
                jokersNeeded -= 1
            }
        }

        if let lastIdx = discardPile.lastIndex(where: { $0.id == discarded.id }) {
            discardPile.remove(at: lastIdx)
        }
        players[playerIndex].exposedSets.append(exposedSet)
        currentPlayerIndex = playerIndex
        hasDrawnThisTurn = true
        gameMessage = "\(players[playerIndex].profile.displayName) called Pung! \(players[playerIndex].isBot ? "" : "Now discard a tile.")"
    }

    private func executeKong(playerIndex: Int, discarded: MahjongTile) {
        let matchingIndices = players[playerIndex].hand.indices.filter {
            players[playerIndex].hand[$0].matchesForGrouping(discarded)
        }

        var exposedSet: [MahjongTile] = [discarded]

        let realMatches = Array(matchingIndices.prefix(3))
        var jokersNeeded = 3 - realMatches.count

        let indicesToRemove = realMatches.sorted(by: >)
        for idx in indicesToRemove {
            exposedSet.append(players[playerIndex].hand.remove(at: idx))
        }

        if jokersNeeded > 0 {
            let jokerIndices = players[playerIndex].hand.indices.filter {
                players[playerIndex].hand[$0].suit == .joker
            }
            for jIdx in jokerIndices.prefix(jokersNeeded).sorted(by: >) {
                exposedSet.append(players[playerIndex].hand.remove(at: jIdx))
                jokersNeeded -= 1
            }
        }

        if let lastIdx = discardPile.lastIndex(where: { $0.id == discarded.id }) {
            discardPile.remove(at: lastIdx)
        }
        players[playerIndex].exposedSets.append(exposedSet)
        currentPlayerIndex = playerIndex
        hasDrawnThisTurn = true
        gameMessage = "\(players[playerIndex].profile.displayName) called Kong! \(players[playerIndex].isBot ? "" : "Now discard a tile.")"
    }

    private func executeQuint(playerIndex: Int, discarded: MahjongTile) {
        let matchingIndices = players[playerIndex].hand.indices.filter {
            players[playerIndex].hand[$0].matchesForGrouping(discarded)
        }

        var exposedSet: [MahjongTile] = [discarded]

        let realMatches = Array(matchingIndices.prefix(4))
        var jokersNeeded = 4 - realMatches.count

        let indicesToRemove = realMatches.sorted(by: >)
        for idx in indicesToRemove {
            exposedSet.append(players[playerIndex].hand.remove(at: idx))
        }

        if jokersNeeded > 0 {
            let jokerIndices = players[playerIndex].hand.indices.filter {
                players[playerIndex].hand[$0].suit == .joker
            }
            for jIdx in jokerIndices.prefix(jokersNeeded).sorted(by: >) {
                exposedSet.append(players[playerIndex].hand.remove(at: jIdx))
                jokersNeeded -= 1
            }
        }

        if let lastIdx = discardPile.lastIndex(where: { $0.id == discarded.id }) {
            discardPile.remove(at: lastIdx)
        }
        players[playerIndex].exposedSets.append(exposedSet)
        currentPlayerIndex = playerIndex
        hasDrawnThisTurn = true
        gameMessage = "\(players[playerIndex].profile.displayName) called Quint! \(players[playerIndex].isBot ? "" : "Now discard a tile.")"
    }

    /// Compute non-mahjong call options (pung/kong/quint) for a specific seat
    /// against the current discard. Used to decide who is eligible to respond.
    private func nonMahjongCallsFor(seatIndex i: Int, discarded: MahjongTile) -> [CallType] {
        guard i < players.count else { return [] }
        // NMJL rule: a discarded Joker can never be called for any reason.
        if discarded.suit == .joker { return [] }
        let matchCount = players[i].hand.filter {
            $0.matchesForGrouping(discarded)
        }.count
        let jokerCount = players[i].hand.filter { $0.suit == .joker }.count
        var calls: [CallType] = []
        // NMJL: an exposure must contain at least one natural tile. The discarded
        // tile itself counts as that natural, so a player with only jokers in hand
        // can still call as long as they hold enough jokers to complete the set
        // (discard + jokers from hand). This enables the "manual call when you
        // have jokers and just need the discarded tile" case.
        if (matchCount + jokerCount) >= 2 { calls.append(.pung) }
        if (matchCount + jokerCount) >= 3 { calls.append(.kong) }
        if (matchCount + jokerCount) >= 4 { calls.append(.quint) }
        return calls
    }

    private func checkAllPlayersForCalls(discardedBy discardPlayerIdx: Int) {
        guard let discarded = lastDiscardedTile else {
            proceedWithTurn()
            return
        }

        // NMJL rule: a discarded Joker is dead — it cannot be called for
        // pung/kong/quint/mahjong by any player. Skip the call window entirely.
        if discarded.suit == .joker {
            availableCalls = []
            callAvailable = false
            pendingCallPlayerIndex = nil
            pendingCallType = nil
            callResponses = [:]
            callResponseDiscardId = nil
            eligibleCallSeats = []
            proceedWithTurn()
            return
        }

        // Reset per-discard response tracking when a new discard arrives.
        if callResponseDiscardId != discarded.id {
            callResponses = [:]
            callResponseDiscardId = discarded.id
            eligibleCallSeats = []
            manualCallExpanded = false
        }

        var localHumanCalls: [CallType] = []
        var bestBotCallIdx: Int?
        var bestBotCallType: CallType?
        var botMahjongIdx: Int?

        // In online mode, only inspect the *local* seat for human-call options —
        // each client surfaces calls available to its own player. Bot decisions
        // (mahjong / pung / kong / quint) are made authoritatively by the host.
        let onlyLocalHuman = isOnlineMode
        let localIdx = localSeatIndex

        for i in 0..<players.count {
            guard i != discardPlayerIdx else { continue }
            // Bot decisions are host-only.
            if onlyLocalHuman && players[i].isBot && !isOnlineHost { continue }
            // Other humans' call options are not surfaced on this client.
            if onlyLocalHuman && !players[i].isBot && i != localIdx {
                // Host needs to know which OTHER human seats can call (for window finalization)
                // but must not show those options on its own UI.
                if isOnlineHost {
                    let calls = nonMahjongCallsFor(seatIndex: i, discarded: discarded)
                    let canMahjong = HandMatcher.canCallForMahjong(tile: discarded, hand: players[i].hand, exposedSets: players[i].exposedSets, card: activeCard)
                    if calls.isEmpty && !canMahjong {
                        if callResponses[i] == nil { callResponses[i] = "skip" }
                    } else {
                        eligibleCallSeats.insert(i)
                    }
                }
                continue
            }

            if players[i].isBot {
                if HandMatcher.canCallForMahjong(tile: discarded, hand: players[i].hand, exposedSets: players[i].exposedSets, card: activeCard) {
                    botMahjongIdx = i
                    break
                }

                let botCalls = HandMatcher.canCallTileForExposure(
                    tile: discarded,
                    hand: players[i].hand,
                    exposedSets: players[i].exposedSets,
                    targetHand: players[i].targetHand
                )

                if !botCalls.isEmpty && botCalls.contains(where: { $0 != .mahjong }) {
                    let shouldCall = shouldBotCall(botIndex: i, discarded: discarded, calls: botCalls)
                    if shouldCall {
                        let callType: CallType
                        if botCalls.contains(.quint) {
                            callType = .quint
                        } else if botCalls.contains(.kong) {
                            callType = .kong
                        } else {
                            callType = .pung
                        }
                        bestBotCallIdx = i
                        bestBotCallType = callType
                    }
                }
            } else {
                // Local human (i == localIdx in online, or any human in solo).
                let calls = nonMahjongCallsFor(seatIndex: i, discarded: discarded)
                localHumanCalls.append(contentsOf: calls)

                if HandMatcher.canCallForMahjong(tile: discarded, hand: players[i].hand, exposedSets: players[i].exposedSets, card: activeCard) {
                    localHumanCalls.append(.mahjong)
                }

                if calls.isEmpty && !localHumanCalls.contains(.mahjong) {
                    // No options for me — auto-skip (online) / nothing to record (solo).
                    if isOnlineMode, callResponses[i] == nil { callResponses[i] = "skip" }
                } else {
                    // Populate regardless of mode — this now also feeds solo-mode
                    // freeze detection in GameDiagnosticsView, which previously had
                    // no visibility into a stuck local call window because this set
                    // was only ever filled in online games.
                    eligibleCallSeats.insert(i)
                }
            }
        }

        if let botMjIdx = botMahjongIdx {
            awaitingCall = true
            let capturedDiscardId = discarded.id
            Task { @MainActor [weak self] in
                // Give real players time to register a counter-mahjong / call
                // before the host commits a bot's claim on the discard.
                // Counter-claim window: a human may want to declare Mahjong on this same
                // discard, so the host holds before committing the bot's claim. But
                // 12-15s froze the entire table on every bot Mahjong — by far the
                // longest stall left in the game. 6-8s is still a real window to react
                // in, and the call prompt is already on screen by the time it starts.
                try? await Task.sleep(for: .seconds(Double.random(in: 6.0...8.0)))
                guard let self else { return }
                self.awaitingCall = false
                // Verify the bot still has a winning hand AND we're still on the
                // same discard. If the mahjong attempt would silently fail, fall
                // through to normal call/turn advancement so the game doesn't freeze.
                guard self.lastDiscardedTile?.id == capturedDiscardId,
                      botMjIdx < self.players.count else { return }
                let stillWinning = HandMatcher.canCallForMahjong(
                    tile: discarded,
                    hand: self.players[botMjIdx].hand,
                    exposedSets: self.players[botMjIdx].exposedSets,
                    card: self.activeCard
                )
                if stillWinning {
                    self.attemptMahjong(playerIndex: botMjIdx, claimedTile: discarded)
                    if self.gameStatus == .completed { return }
                }
                // Mahjong didn't actually go through — recover by continuing the
                // normal call/turn flow.
                if self.isOnlineHost {
                    self.tryFinalizeCallWindow()
                } else {
                    self.proceedWithTurn()
                }
            }
            return
        }

        if !localHumanCalls.isEmpty {
            availableCalls = localHumanCalls
            callAvailable = true
            pendingCallPlayerIndex = bestBotCallIdx
            pendingCallType = bestBotCallType
            gameMessage = "\(discarded.displayName) discarded — Call?"
            // Arm the decision timeout in BOTH modes. Solo previously armed nothing:
            // we set `callAvailable = true` and returned, and with no watchdog and no
            // host to finalize, a call window the player never resolved parked the
            // game permanently. Online always recovered via the host's watchdog.
            armCallWindowWatchdog()
            // In online mode, host must still wait for OTHER humans even if its
            // own player can call (those other humans may have higher-priority calls).
            if isOnlineHost {
                tryFinalizeCallWindow()
            }
            return
        }

        // Non-host online client: stop here. Bot calls and turn advancement
        // are driven by the host and arrive via state sync. If we can't call,
        // mark our own seat as skipped and broadcast so the host can finalize.
        if isOnlineMode && !isOnlineHost {
            if callResponses[localIdx] == nil { callResponses[localIdx] = "skip" }
            notifyOnlineSync()
            return
        }

        // Host with no local human options: wait for other humans before deciding.
        if isOnlineHost {
            // Preserve any pending bot call so `tryFinalizeCallWindow` can execute it
            // even when no local human options are available. Without this assignment,
            // a bot's pung/kong on an invitee's discard is silently dropped and the
            // game appears frozen until the watchdog times out.
            pendingCallPlayerIndex = bestBotCallIdx
            pendingCallType = bestBotCallType
            armCallWindowWatchdog()
            tryFinalizeCallWindow()
            return
        }

        if let botIdx = bestBotCallIdx, let botCall = bestBotCallType {
            awaitingCall = true
            let capturedDiscardId = discarded.id
            Task { @MainActor [weak self] in
                // Solo play: give the human a real moment to call before the bot
                // snaps up the discard. Also keeps call announcements readable.
                // Shortened from 12-15s — that length made sense for the mahjong
                // branch above (a human may want to counter-claim mahjong on the
                // same tile) but was an excessive, unexplained pause for an
                // ordinary pung/kong/quint, especially when several bot calls
                // chain together in a row.
                try? await Task.sleep(for: .seconds(Double.random(in: 2.0...3.0)))
                guard let self else { return }
                self.awaitingCall = false
                // Re-validate before acting: if the discard has moved on (a newer
                // discard/call window opened, or this one was already resolved some
                // other way) in the 12-15s we were asleep, blindly calling here would
                // execute on stale state. Previously this branch had no such check —
                // unlike the bot-mahjong branch just above it — which is exactly the
                // kind of gap that produces an occasional stuck game when two
                // call-eligible discards land close together.
                guard self.lastDiscardedTile?.id == capturedDiscardId,
                      botIdx < self.players.count else { return }
                self.executeCall(playerIndex: botIdx, type: botCall, discarded: discarded)
            }
            return
        }

        // Nobody can claim this discard (solo, or no eligible seat at all), so the
        // window is over before it began — close it explicitly. Leaving
        // `callResponseDiscardId` pointing at this discard would keep
        // `isCallWindowOpen` true and kill Draw for the seat we're about to hand the
        // turn to.
        closeCallWindow(for: discarded)
        proceedWithTurn()
    }

    /// Close the call window for a discard that no longer needs one.
    ///
    /// `isCallWindowOpen` treats `callResponseDiscardId` as the AUTHORITATIVE,
    /// table-wide "someone may still claim this discard" signal — so every path that
    /// ends a window has to clear it, or `canDrawTile` stays false and the table sits
    /// with a dead Draw button. The online host does this inside
    /// `tryFinalizeCallWindow`; solo (which has no host) and the "nobody can call"
    /// path had no equivalent, and simply walked away leaving the window flagged open.
    private func closeCallWindow(for discarded: MahjongTile) {
        callAvailable = false
        availableCalls = []
        callResponses = [:]
        callResponseDiscardId = nil
        eligibleCallSeats = []
        lastFinalizedCallDiscardId = discarded.id
        callWindowWatchdog?.cancel()
        callWindowWatchdog = nil
    }

    /// Host-only: check whether every eligible non-discarder human has responded
    /// (skip or called). If so, execute the best pending bot call or advance turn.
    private func tryFinalizeCallWindow(forceTimeout: Bool = false) {
        guard isOnlineHost, isOnlineMode else { return }
        guard let discarded = lastDiscardedTile,
              callResponseDiscardId == discarded.id else { return }

        // ALREADY-FINALIZED GUARD. If we've already advanced past this discard
        // (executed a call, or moved the turn pointer), a late `callResponses` echo
        // from an invitee must not re-enter and call `proceedWithTurn` again. We
        // track that explicitly via `lastFinalizedCallDiscardId` instead of inferring
        // it from the window-state flags — those flags are also false in the
        // legitimate case where every eligible seat auto-skipped synchronously, and
        // the prior heuristic stranded the turn on the host in that scenario.
        if !forceTimeout && lastFinalizedCallDiscardId == discarded.id {
            print("\u{23ED}\u{FE0F} tryFinalizeCallWindow: already finalized discard \(discarded.id) — ignoring late echo")
            return
        }

        // Defensive: ignore eligible seats that are out-of-range, the discarder,
        // or now bots (state desync). They will never produce a human response.
        // Seats explicitly on "hold" are treated as still-waiting.
        let waitingSeats = eligibleCallSeats.filter { seat in
            guard seat < players.count else { return false }
            if seat == lastDiscardPlayerIndex { return false }
            if seatIsDrivableBot(seat) { return false }
            let resp = callResponses[seat]
            return resp == nil || resp == "hold"
        }

        // If any seat has explicitly requested more time, cancel the auto-skip
        // watchdog so the window stays open indefinitely.
        if !forceTimeout && anySeatOnHold {
            callWindowWatchdog?.cancel()
            callWindowWatchdog = nil
        }

        // If any eligible human seat hasn't responded yet, keep waiting (unless we
        // are being force-finalized by the watchdog).
        if !forceTimeout && !waitingSeats.isEmpty {
            return
        }
        if forceTimeout && !waitingSeats.isEmpty {
            print("⏰ call window watchdog firing — auto-skipping seats \(waitingSeats)")
            for seat in waitingSeats { callResponses[seat] = "skip" }
        }

        // If a human already called, the call WILL be executed by that caller's
        // client (their `confirmCallSelection` exposes tiles + broadcasts). The
        // window stays open here — but we arm a follow-through watchdog so a stuck
        // caller can't freeze the game forever (e.g. tile-selection sheet got
        // dismissed by a state echo, app backgrounded, network drop).
        if callResponses.values.contains("called") {
            callWindowWatchdog?.cancel()
            callWindowWatchdog = nil
            armCallerFollowThroughWatchdog()
            return
        }

        // All eligible humans skipped (or none were eligible). Trigger bot call or advance.
        let botIdx = pendingCallPlayerIndex
        let botType = pendingCallType
        callAvailable = false
        availableCalls = []
        callResponses = [:]
        callResponseDiscardId = nil
        eligibleCallSeats = []
        callWindowWatchdog?.cancel()
        callWindowWatchdog = nil
        callerFollowThroughWatchdog?.cancel()
        callerFollowThroughWatchdog = nil
        // Mark this discard as finalized so late echoes can't re-fire the window.
        lastFinalizedCallDiscardId = discarded.id

        if let bIdx = botIdx, let bType = botType {
            awaitingCall = true
            let capturedDiscardId = discarded.id
            Task { @MainActor [weak self] in
                // Slight delay so the "X discarded …" announcement stays on screen
                // and players see the bot's call land deliberately. Shortened from
                // 12-15s to something that actually matches "slight" — all humans
                // have already responded by the time this branch runs, so there's
                // no reason left to wait long here.
                try? await Task.sleep(for: .seconds(Double.random(in: 2.0...3.0)))
                guard let self else { return }
                self.awaitingCall = false
                // Same staleness guard as the solo bot-call branch: don't act on a
                // discard that's no longer current by the time the delay elapses.
                guard self.lastDiscardedTile?.id == capturedDiscardId,
                      bIdx < self.players.count else { return }
                self.executeCall(playerIndex: bIdx, type: bType, discarded: discarded)
            }
            return
        }

        proceedWithTurn()
    }

    private func shouldBotCall(botIndex: Int, discarded: MahjongTile, calls: [CallType]) -> Bool {
        guard let target = players[botIndex].targetHand else { return false }
        if target.concealed { return false }

        let tileKey = TileKey(suit: discarded.suit, value: discarded.value)
        let matchCount = players[botIndex].hand.filter {
            $0.matchesForGrouping(discarded)
        }.count

        for group in target.groups {
            guard group.count >= 3, group.jokersAllowed else { continue }
            if groupMatchesTile(group: group, key: tileKey) && matchCount >= 1 {
                return true
            }
        }
        return false
    }

    private func groupMatchesTile(group: HandGroup, key: TileKey) -> Bool {
        let suits: [TileSuit] = [.bamboo, .character, .dot]
        switch group.tile {
        case .numbered(let suit, let value):
            return key.suit == suit && key.value == value
        case .anySuit(_, let value):
            return key.value == value && suits.contains(key.suit)
        case .dragon(let value):
            return key.suit == .dragon && key.value == value
        case .matchingDragon:
            return key.suit == .dragon
        case .wind(let value):
            return key.suit == .wind && key.value == value
        case .anyWindSlot:
            return key.suit == .wind
        case .anyDragonSlot:
            return key.suit == .dragon
        case .anyValueAnySuit(_, _, let allowedValues):
            return [TileSuit.bamboo, .character, .dot].contains(key.suit) && allowedValues.contains(key.value)
        case .flower:
            return key.suit == .flower
        }
    }

    private func proceedWithTurn() {
        // CRITICAL: rectify bot flags BEFORE we read isBot to decide whether to
        // auto-drive the next seat. A stale state that flagged the invitee as a
        // bot would otherwise cause the host to play the invitee's turn for them,
        // skipping them on every cycle right after Charleston completes.
        selfRectifyBotFlags()
        // After a call, `currentPlayerIndex` is set to the caller in executeCall,
        // so `+1 % count` here correctly hands the next draw to the player to the
        // RIGHT of the caller (seats are ordered counter-clockwise / play passes
        // to the right). Do NOT change without revisiting executeCall.
        let nextIndex = (currentPlayerIndex + 1) % players.count
        currentPlayerIndex = nextIndex

        // CRITICAL: always reset `hasDrawnThisTurn` when the turn pointer moves to
        // a new seat. Previously this only ran in the human branch, so after a bot
        // call (executeCall sets hasDrawnThisTurn=true) → bot discard → next bot
        // turn, `executeBotTurn`'s `hasDrawnThisTurn == false` guard would bail and
        // the game froze on the next bot.
        hasDrawnThisTurn = false
        invalidMahjongMessage = nil
        if seatIsDrivableBot(currentPlayerIndex) {
            gameMessage = "\(players[currentPlayerIndex].profile.displayName) is thinking..."
            // Only the host drives bot turns in online mode; other clients receive
            // the bot's move via state sync.
            if isOnlineMode && !isOnlineHost {
                notifyOnlineSync()
                return
            }
            Task {
                // Slower bot thinking so real players have time to read the table
                // (and to spot any pending call window) before the bot draws.
                try? await Task.sleep(for: .seconds(Double.random(in: 1.0...1.7)))
                executeBotTurn()
            }
        } else {
            let nextName = players[currentPlayerIndex].profile.displayName
            gameMessage = "\(nextName)'s turn — draw a tile."
        }
        notifyOnlineSync()
        armOrCancelRemoteHumanTurnWatchdog()
    }

    // MARK: - Joker Swap

    func startJokerSwap() {
        guard let playerIdx = humanPlayerIndex else { return }
        // Per NMJL rules, a player may redeem a joker from any exposed set at
        // ANY time during the playing phase — not only on their own turn.
        guard gameStatus == .playing else { return }

        let hasJokerInExposed = players.contains { player in
            player.exposedSets.contains { set in
                set.contains { $0.suit == .joker }
            }
        }

        guard hasJokerInExposed else {
            gameMessage = "No jokers in exposed sets to swap."
            return
        }

        let hasMatchingTile = checkHasMatchingTileForJokerSwap(playerIndex: playerIdx)
        guard hasMatchingTile else {
            gameMessage = "No matching tiles in your hand for joker swap."
            return
        }

        jokerSwapMode = true
        jokerSwapSourceIndex = nil
        selectedTileIndex = nil
        gameMessage = "Select a tile from your hand to swap for a joker."
    }

    func cancelJokerSwap() {
        jokerSwapMode = false
        jokerSwapSourceIndex = nil
        if isHumanTurn, let human = humanPlayer {
            gameMessage = hasDrawnThisTurn ? "\(human.profile.displayName) — select a tile to discard." : "\(human.profile.displayName)'s turn — draw a tile."
        } else {
            gameMessage = ""
        }
    }

    private func handleJokerSwapSelection(at index: Int) {
        guard let playerIdx = humanPlayerIndex else { return }
        guard index < players[playerIdx].hand.count else { return }

        let selectedTile = players[playerIdx].hand[index]
        guard selectedTile.suit != .joker else {
            gameMessage = "Select a non-joker tile to swap."
            return
        }

        for pIdx in 0..<players.count {
            for sIdx in 0..<players[pIdx].exposedSets.count {
                if let jIdx = players[pIdx].exposedSets[sIdx].firstIndex(where: { $0.suit == .joker }) {
                    let nonJokerInSet = players[pIdx].exposedSets[sIdx].first { $0.suit != .joker }
                    if let ref = nonJokerInSet,
                       ref.matchesForGrouping(selectedTile) {
                        let jokerTile = players[pIdx].exposedSets[sIdx][jIdx]
                        players[pIdx].exposedSets[sIdx][jIdx] = players[playerIdx].hand[index]
                        players[playerIdx].hand[index] = jokerTile
                        jokerSwapSourceIndex = nil
                        let move = GameMove(playerId: players[playerIdx].id, moveType: .jokerSwap, tiles: [jokerTile])
                        moveHistory.append(move)
                        // CRITICAL (online): broadcast the swap immediately so the
                        // host's next heartbeat doesn't roll the hand/exposed-set
                        // back to the pre-swap snapshot — that's the "swap reverses
                        // itself" symptom invitees see in multiplayer.
                        notifyOnlineSync()
                        let stillHasSwaps = checkHasMatchingTileForJokerSwap(playerIndex: playerIdx)
                        if stillHasSwaps {
                            gameMessage = "Joker swapped! Select another tile to swap, or cancel."
                        } else {
                            jokerSwapMode = false
                            gameMessage = "Joker swapped! No more swaps available."
                        }
                        return
                    }
                }
            }
        }

        gameMessage = "That tile doesn't match any exposed set with a joker."
    }

    private func checkHasMatchingTileForJokerSwap(playerIndex: Int) -> Bool {
        for player in players {
            for set in player.exposedSets {
                guard set.contains(where: { $0.suit == .joker }) else { continue }
                let nonJoker = set.first { $0.suit != .joker }
                guard let ref = nonJoker else { continue }
                if players[playerIndex].hand.contains(where: { $0.matchesForGrouping(ref) }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Mahjong Declaration

    func declareMahjong() {
        guard let playerIdx = humanPlayerIndex else { return }
        attemptMahjong(playerIndex: playerIdx, claimedTile: nil)
    }

    private func attemptMahjong(playerIndex: Int, claimedTile: MahjongTile?) {
        var testHand = players[playerIndex].hand
        if let claimed = claimedTile {
            testHand.append(claimed)
        }

        let result = HandMatcher.checkWin(
            hand: testHand,
            exposedSets: players[playerIndex].exposedSets,
            card: activeCard
        )

        if let matchedHand = result {
            if let claimed = claimedTile {
                players[playerIndex].hand.append(claimed)
                if let lastIdx = discardPile.lastIndex(where: { $0.id == claimed.id }) {
                    discardPile.remove(at: lastIdx)
                }
            }

            winningHand = matchedHand
            winnerName = players[playerIndex].profile.displayName
            players[playerIndex].score += matchedHand.points
            gameStatus = .completed
            isWallGame = false
            showEndGameOverlay = true
            showMahjongAnimation = true

            let isHuman = humanPlayerIndex != nil && playerIndex == humanPlayerIndex
            _ = isHuman
            gameMessage = "🎉 Mahjong! \(winnerName) wins with \(matchedHand.name)!"
            callAvailable = false
            availableCalls = []
            awaitingCall = false
            showCallTileSelection = false
            callResponses = [:]
            callResponseDiscardId = nil
            eligibleCallSeats = []
            // Cancel every in-flight watchdog so a delayed timeout can't fire a
            // proceedWithTurn / drawTile after the win and corrupt the terminal
            // state. Without this, an invitee who declared Mahjong on the last
            // discard could be force-advanced to draw an empty wall → wall game.
            callWindowWatchdog?.cancel()
            callWindowWatchdog = nil
            callerFollowThroughWatchdog?.cancel()
            callerFollowThroughWatchdog = nil
            nonHostPostDiscardWatchdog?.cancel()
            nonHostPostDiscardWatchdog = nil
            notifyOnlineSync()
        } else {
            if !players[playerIndex].isBot {
                invalidMahjongMessage = "Your hand doesn't match any winning hand on the \(selectedCardYear.displayName) card."
                gameMessage = "Not a valid Mahjong hand. Keep playing!"
            }
        }
    }

    // MARK: - Wall Game

    private func declareWallGame() {
        // Idempotent. This is now reachable from the draw paths AND from the host's
        // periodic backstop, which can collide in the same tick — and re-running it
        // would re-broadcast a terminal state. It must also never clobber a Mahjong:
        // if the game is already completed, whatever ended it stands.
        guard gameStatus != .completed, !showEndGameOverlay else { return }

        gameStatus = .completed
        isWallGame = true
        showEndGameOverlay = true
        winningHand = nil
        winnerName = ""
        gameMessage = "Wall Game! No tiles remaining — nobody wins."
        callAvailable = false
        availableCalls = []
        awaitingCall = false
        showCallTileSelection = false
        // CRITICAL: broadcast the end-of-game state so every client surfaces the
        // wall-game overlay. Without this notify, the player who didn't trigger
        // the empty-wall draw never sees the announcement.
        //
        // Peers accept this: `gameStatus`, `isWallGame` and `showEndGameOverlay` are
        // all part of the serialized state, every stale-echo guard in
        // `applyRemoteState` is scoped to `incomingStatus == .playing` so a
        // `.completed` packet passes straight through, and once a client has applied
        // it the COMPLETED IS TERMINAL guard stops any late `.playing` heartbeat from
        // rolling the ending back.
        notifyOnlineSync()
    }

    // MARK: - Bot Turn

    private func executeBotTurn() {
        // Defense in depth: never run a bot turn for a seat that authoritative
        // state says belongs to a real player.
        selfRectifyBotFlags()
        guard currentPlayerIndex < players.count,
              seatIsDrivableBot(currentPlayerIndex) else { return }

        // CRITICAL: a bot must NEVER draw while a call window is open or while
        // another player is still selecting tiles for a pung/kong/quint. Without
        // this guard, the host could race ahead and make the next bot draw before
        // the caller's exposure + discard is committed — leaving the caller stuck
        // with too many tiles and the turn order corrupted.
        guard !callAvailable, !awaitingCall, !showCallTileSelection else { return }
        guard hasDrawnThisTurn == false else { return }

        // POST-DISCARD GUARD (mirror of `drawTile`). If this bot was just the
        // discarder and the call window for that discard hasn't been finalized
        // yet, do NOT draw again. Otherwise a stale state echo could re-fire the
        // bot's draw → discard cycle and desync the table.
        if isOnlineMode,
           let lastDiscardSeat = lastDiscardPlayerIndex,
           lastDiscardSeat == currentPlayerIndex,
           let lastDiscarded = lastDiscardedTile,
           callResponseDiscardId == lastDiscarded.id,
           lastFinalizedCallDiscardId != lastDiscarded.id {
            print("⏪ executeBotTurn blocked — bot at seat \(currentPlayerIndex) just discarded and the call window hasn't resolved yet")
            return
        }

        guard !wall.isEmpty else {
            declareWallGame()
            return
        }

        let botIdx = currentPlayerIndex

        // Bots redeem jokers from any exposure when they hold the matching tile.
        performBotJokerSwaps(botIdx: botIdx)

        var tile = wall.removeFirst()
        tile.isRevealed = false
        players[botIdx].hand.append(tile)

        // Drawn tile may now allow another joker swap.
        performBotJokerSwaps(botIdx: botIdx)

        if let matched = HandMatcher.checkWin(hand: players[botIdx].hand, exposedSets: players[botIdx].exposedSets, card: activeCard) {
            winningHand = matched
            winnerName = players[botIdx].profile.displayName
            players[botIdx].score += matched.points
            gameStatus = .completed
            isWallGame = false
            showEndGameOverlay = true
            showMahjongAnimation = true
            gameMessage = "🎉 \(winnerName) declares Mahjong with \(matched.name)!"
            notifyOnlineSync()
            return
        }

        reevaluateBotTargetIfNeeded(botIdx: botIdx)
        executeBotDiscard(botIdx: botIdx)
    }

    /// Repeatedly swaps any joker in any exposed set for a matching real tile in the bot's hand.
    /// Mirrors the human joker-swap logic: a player may redeem a joker from their own or any
    /// other player's exposure if they hold the tile it represents.
    private func performBotJokerSwaps(botIdx: Int) {
        guard botIdx < players.count, players[botIdx].isBot else { return }

        var didSwap = true
        var safety = 0
        while didSwap && safety < 32 {
            didSwap = false
            safety += 1

            outer: for pIdx in 0..<players.count {
                for sIdx in 0..<players[pIdx].exposedSets.count {
                    guard let jIdx = players[pIdx].exposedSets[sIdx].firstIndex(where: { $0.suit == .joker }) else { continue }
                    guard let ref = players[pIdx].exposedSets[sIdx].first(where: { $0.suit != .joker }) else { continue }
                    if let handIdx = players[botIdx].hand.firstIndex(where: { $0.matchesForGrouping(ref) }) {
                        let jokerTile = players[pIdx].exposedSets[sIdx][jIdx]
                        players[pIdx].exposedSets[sIdx][jIdx] = players[botIdx].hand[handIdx]
                        players[botIdx].hand[handIdx] = jokerTile
                        let move = GameMove(playerId: players[botIdx].id, moveType: .jokerSwap, tiles: [jokerTile])
                        moveHistory.append(move)
                        gameMessage = "\(players[botIdx].profile.displayName) redeemed a Joker from \(players[pIdx].profile.displayName)'s exposure."
                        didSwap = true
                        break outer
                    }
                }
            }
        }
    }

    private func executeBotDiscard(botIdx: Int) {
        guard !players[botIdx].hand.isEmpty else { return }

        let discardIndex = HandMatcher.selectBotDiscard(hand: players[botIdx].hand, targetHand: players[botIdx].targetHand)
        var discarded = players[botIdx].hand.remove(at: discardIndex)
        discarded.isDiscarded = true
        discardPile.append(discarded)
        discardPlayerMap[discarded.id] = players[botIdx].profile.displayName
        lastDiscardedTile = discarded
        lastDiscardPlayerIndex = botIdx
        lastProcessedDiscardId = discarded.id

        // Defensive reset: if this discard followed a bot call, executeCall left
        // `hasDrawnThisTurn = true`. Clearing it here keeps the flag in a sane
        // state even before `proceedWithTurn` gets a chance to run.
        hasDrawnThisTurn = false
        callAvailable = false
        availableCalls = []
        awaitingCall = false

        let move = GameMove(playerId: players[botIdx].id, moveType: .discard, tiles: [discarded])
        moveHistory.append(move)

        gameMessage = "\(players[botIdx].profile.displayName) discarded \(discarded.displayName)"

        // Run call detection BEFORE broadcasting so the serialized state carries
        // the correct callResponseDiscardId and eligibility info. Otherwise invitees
        // receive a state with the new discard but a stale call-window header and
        // briefly wipe their own call UI.
        checkAllPlayersForCalls(discardedBy: botIdx)
        notifyOnlineSync()
        armOrCancelRemoteHumanTurnWatchdog()
    }

    /// Public recovery hook (any client) — surfaces a snapshot of state used by the
    /// game-freeze diagnostics overlay. Read-only.
    var diagnosticsSnapshot: String {
        var lines: [String] = []
        lines.append("status: \(gameStatus.rawValue)")
        lines.append("online: \(isOnlineMode) seat=\(localSeatIndex) host=\(isOnlineHost)")
        if gameStatus == .charleston {
            lines.append("charleston phase: \(charlestonPhase.rawValue)")
            lines.append("pending passes: \(charlestonPendingPasses.keys.sorted())")
        } else {
            lines.append("turn: seat \(currentPlayerIndex)")
            lines.append("hasDrawnThisTurn: \(hasDrawnThisTurn) awaitingCall: \(awaitingCall)")
            lines.append("callAvailable: \(callAvailable) calls: \(availableCalls.map { String(describing: $0) })")
            lines.append("call responses: \(callResponses) eligible: \(eligibleCallSeats.sorted())")
            lines.append("last discard: \(lastDiscardedTile?.displayName ?? "–") by seat \(lastDiscardPlayerIndex.map { String($0) } ?? "–")")
        }
        lines.append("wall: \(wallCount) discards: \(discardCount)")
        return lines.joined(separator: "\n")
    }

    /// Host-only manual override for the diagnostics overlay: force-finalize the
    /// current call window so a stuck game can advance.
    func hostForceResolveCallWindow() {
        guard isOnlineHost, isOnlineMode else { return }
        tryFinalizeCallWindow(forceTimeout: true)
        notifyOnlineSync()
    }

    /// True when the host is currently waiting on a non-local seat (remote human
    /// OR a stalled bot) to draw or discard. Drives the "Force Advance Turn"
    /// diagnostics button.
    var canHostForceAdvanceRemoteTurn: Bool {
        guard isOnlineHost, isOnlineMode, gameStatus == .playing else { return false }
        guard !awaitingCall, !callAvailable, callResponseDiscardId == nil else { return false }
        guard currentPlayerIndex < players.count else { return false }
        if currentPlayerIndex == localSeatIndex { return false }
        return true
    }

    /// Diagnostics recovery: host force-advances a stalled seat. Remote humans
    /// get a draw + safe discard; stalled bots are kicked back into
    /// `executeBotTurn` after clearing any stale call-window flags.
    func hostForceAdvanceRemoteTurn() {
        guard canHostForceAdvanceRemoteTurn else { return }
        let seat = currentPlayerIndex
        if seatIsDrivableBot(seat) {
            hostForceAdvanceBotSeat(seat: seat)
        } else {
            hostForceAdvanceRemoteSeat(seat: seat)
        }
    }

    /// Host-only: nudge a stalled bot whose turn never fired (e.g. its scheduled
    /// `executeBotTurn` was cancelled by a state echo, or the previous turn left
    /// `hasDrawnThisTurn = true`). Clears stale flags and runs the bot's turn now.
    private func hostForceAdvanceBotSeat(seat: Int) {
        guard isOnlineHost, isOnlineMode else { return }
        guard gameStatus == .playing else { return }
        guard seat < players.count, currentPlayerIndex == seat else { return }
        guard seatIsDrivableBot(seat) else { return }
        // Clear any stale call/draw flags that may be blocking executeBotTurn's guards.
        callAvailable = false
        availableCalls = []
        awaitingCall = false
        showCallTileSelection = false
        callTileSelectionType = nil
        callSelectedIndices = []
        callRequiredCount = 0
        hasDrawnThisTurn = false
        executeBotTurn()
    }

    /// Diagnostics recovery: clear any stale local call-window UI state so a frozen
    /// client can re-engage. Safe on any client.
    func clearLocalCallWindowState() {
        callAvailable = false
        availableCalls = []
        showCallTileSelection = false
        callTileSelectionType = nil
        callSelectedIndices = []
        callRequiredCount = 0
        awaitingCall = false
        if !isOnlineHost {
            // Non-hosts should not own pendingCall/responses, but clear our local view.
            pendingCallPlayerIndex = nil
            pendingCallType = nil
        }
    }

    /// Host-only: arm/refresh a watchdog that periodically re-broadcasts state to
    /// nudge a remote human seat whose turn it is. We NEVER auto-draw or auto-discard
    /// for a real human — that's the "host skipped the invited player" symptom. The
    /// invitee is the sole owner of their hand; if a packet was dropped, repeated
    /// re-broadcasts will eventually reach them so they can play their own turn.
    private func armOrCancelRemoteHumanTurnWatchdog() {
        guard isOnlineHost, isOnlineMode else {
            remoteTurnWatchdog?.cancel()
            remoteTurnWatchdog = nil
            return
        }
        guard gameStatus == .playing,
              !showEndGameOverlay,
              !awaitingCall,
              !callAvailable,
              callResponseDiscardId == nil,
              currentPlayerIndex < players.count else {
            remoteTurnWatchdog?.cancel()
            remoteTurnWatchdog = nil
            return
        }
        selfRectifyBotFlags()
        let seat = currentPlayerIndex
        if seat == localSeatIndex || seatIsDrivableBot(seat) {
            remoteTurnWatchdog?.cancel()
            remoteTurnWatchdog = nil
            return
        }

        let drewSnapshot = hasDrawnThisTurn
        let discardCountSnapshot = discardPile.count
        let handCountSnapshot = players[seat].hand.count

        remoteTurnWatchdog?.cancel()
        remoteTurnWatchdog = Task { @MainActor [weak self] in
            // Keep re-broadcasting the current state every few seconds for as long
            // as the remote human's turn hasn't progressed. Each nudge is cheap and
            // idempotent; repeated attempts dramatically increase the chance a
            // single dropped packet self-heals without ever skipping the player.
            var nudgeCount = 0
            while !Task.isCancelled {
                // First nudge fires quickly so a brief drop is recovered fast.
                let delay: Duration = nudgeCount == 0 ? .seconds(4) : .seconds(6)
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
                guard let self else { return }
                guard self.isOnlineHost,
                      self.gameStatus == .playing,
                      !self.showEndGameOverlay,
                      !self.awaitingCall,
                      !self.callAvailable,
                      self.callResponseDiscardId == nil,
                      self.currentPlayerIndex == seat,
                      self.hasDrawnThisTurn == drewSnapshot,
                      self.discardPile.count == discardCountSnapshot,
                      seat < self.players.count,
                      !self.seatIsDrivableBot(seat),
                      self.players[seat].hand.count == handCountSnapshot else { return }
                nudgeCount += 1
                print("⏰ remote turn watchdog: nudge #\(nudgeCount) seat=\(seat) drew=\(drewSnapshot)")
                // Re-push state so the remote client realizes it's their turn.
                self.onlineSyncHandler?()
            }
        }
    }

    /// Host-only: take over for a stalled remote human seat. Draws if they
    /// haven't yet, otherwise discards a safe non-joker tile.
    private func hostForceAdvanceRemoteSeat(seat: Int) {
        guard isOnlineHost, isOnlineMode else { return }
        guard gameStatus == .playing else { return }
        guard !awaitingCall, !callAvailable, callResponseDiscardId == nil else { return }
        guard seat < players.count, currentPlayerIndex == seat else { return }
        guard !seatIsDrivableBot(seat), seat != localSeatIndex else { return }

        if !hasDrawnThisTurn {
            guard !wall.isEmpty else { declareWallGame(); return }
            var tile = wall.removeFirst()
            tile.isRevealed = true
            players[seat].hand.append(tile)
            hasDrawnThisTurn = true
            invalidMahjongMessage = nil
            callAvailable = false
            availableCalls = []
            gameMessage = "\(players[seat].profile.displayName) is thinking…"
            notifyOnlineSync()
            armOrCancelRemoteHumanTurnWatchdog()
            return
        }

        // Force a safe discard: prefer a non-joker tile.
        guard !players[seat].hand.isEmpty else { proceedWithTurn(); return }
        let pickIdx = players[seat].hand.firstIndex(where: { $0.suit != .joker }) ?? 0
        var tile = players[seat].hand.remove(at: pickIdx)
        tile.isDiscarded = true
        discardPile.append(tile)
        discardPlayerMap[tile.id] = players[seat].profile.displayName
        lastDiscardedTile = tile
        lastDiscardPlayerIndex = seat
        lastProcessedDiscardId = tile.id
        hasDrawnThisTurn = false
        callAvailable = false
        availableCalls = []
        awaitingCall = false
        invalidMahjongMessage = nil

        let move = GameMove(playerId: players[seat].id, moveType: .discard, tiles: [tile])
        moveHistory.append(move)
        gameMessage = "\(players[seat].profile.displayName) discarded \(tile.displayName)"

        checkAllPlayersForCalls(discardedBy: seat)
        notifyOnlineSync()
        armOrCancelRemoteHumanTurnWatchdog()
    }

    /// Non-host only: nudge the host when we're parked on our own discard waiting
    /// for the call window to finalize. Cancels itself once the host advances
    /// (turn moves off us, or the discard id changes).
    private func armOrCancelNonHostPostDiscardWatchdog() {
        guard isOnlineMode, !isOnlineHost else {
            nonHostPostDiscardWatchdog?.cancel()
            nonHostPostDiscardWatchdog = nil
            return
        }
        guard gameStatus == .playing,
              !showEndGameOverlay,
              let discarded = lastDiscardedTile,
              let discIdx = lastDiscardPlayerIndex,
              discIdx == localSeatIndex,
              currentPlayerIndex == localSeatIndex,
              !hasDrawnThisTurn else {
            nonHostPostDiscardWatchdog?.cancel()
            nonHostPostDiscardWatchdog = nil
            return
        }
        let discardId = discarded.id
        let mySeat = localSeatIndex
        nonHostPostDiscardWatchdog?.cancel()
        nonHostPostDiscardWatchdog = Task { @MainActor [weak self] in
            var nudgeCount = 0
            while !Task.isCancelled {
                let delay: Duration = nudgeCount == 0 ? .seconds(5) : .seconds(7)
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
                guard let self else { return }
                guard self.isOnlineMode,
                      !self.isOnlineHost,
                      self.gameStatus == .playing,
                      !self.showEndGameOverlay,
                      self.lastDiscardedTile?.id == discardId,
                      self.lastDiscardPlayerIndex == mySeat,
                      self.currentPlayerIndex == mySeat,
                      !self.hasDrawnThisTurn else { return }
                nudgeCount += 1
                print("non-host post-discard watchdog: nudge #\(nudgeCount) seat=\(mySeat)")
                self.onlineSyncHandler?()
                if nudgeCount >= 8 { return }
            }
        }
    }

    /// Host-only: arm a watchdog that force-finalizes the call window after a few
    /// seconds. Protects against frozen games when an invitee's "skip" response
    /// never reaches the host (network drop, backgrounded app, etc.).
    private func armCallWindowWatchdog() {
        // Online: host only — it owns call-window finalization.
        // Solo: always. This guard used to be `isOnlineHost, isOnlineMode`, which
        // meant solo had NO call-window timeout whatsoever.
        //
        // That is the root of the "solo froze on a call" reports. It bites hardest on
        // a JOKER-ONLY call (2+ jokers, no natural match for the discard), because
        // that path deliberately suppresses the auto-popup in favour of a small
        // "Call" button — so there is no visible Skip, nothing signals that the game
        // is blocked on the player, and if they don't spot the button the table sits
        // there indefinitely. Online moved on after 25s; solo never did.
        if isOnlineMode && !isOnlineHost { return }
        // Don't arm if any player has explicitly requested unlimited decide time.
        if anySeatOnHold { return }
        callWindowWatchdog?.cancel()
        let discardId = lastDiscardedTile?.id
        callWindowWatchdog = Task { @MainActor [weak self] in
            // Tight enough to recover from a stalled invitee quickly, but with
            // enough headroom that real players still have time to consider a call.
            // Generous window so players have real time to decide on a
            // pung/kong/quint, especially when relying on jokers. Recovers from
            // a stalled invitee without rushing legitimate decisions.
            try? await Task.sleep(for: .seconds(25))
            guard let self else { return }
            if Task.isCancelled { return }
            // Only fire if we're still waiting on the same discard.
            guard self.lastDiscardedTile?.id == discardId,
                  self.callResponseDiscardId == discardId else { return }
            if self.isOnlineMode {
                self.tryFinalizeCallWindow(forceTimeout: true)
            } else {
                // Solo has no host to finalize the window. `dismissCallOptions` is the
                // equivalent: it closes the window and then either executes a bot's
                // pending call on this discard or advances the turn.
                print("⏱️ solo call window timed out — auto-skipping")
                self.dismissCallOptions()
            }
        }
    }

    /// Host-only: arm a watchdog that fires if a remote caller never follows
    /// through with their exposure. Symptom: `callResponses` has "called" for
    /// some seat, but `currentPlayerIndex` is still the discarder (the caller's
    /// `executeCall` never ran on their client). After the timeout we abandon
    /// the call (downgrade to skip) so the rest of the table isn't frozen.
    private func armCallerFollowThroughWatchdog() {
        guard isOnlineHost, isOnlineMode else { return }
        callerFollowThroughWatchdog?.cancel()
        let discardId = lastDiscardedTile?.id
        let stuckAtSeat = lastDiscardPlayerIndex
        callerFollowThroughWatchdog = Task { @MainActor [weak self] in
            // ABANDONMENT timeout — NOT a decision timer.
            //
            // When it fires it downgrades the caller's "called" back to "skip",
            // force-finalizes, and hands the turn on: the claimed tile snaps back into
            // the discard pile and the caller loses the exposure entirely. At 25s that
            // was firing on people who were simply still choosing — tap Kong, then find
            // THREE matching tiles among thirteen (possibly weighing jokers), then
            // confirm. Blowing 25s is easy, and the punishment was silently losing the
            // kong and being skipped.
            //
            // 25s -> 60s. This only needs to be short enough to rescue the table from a
            // caller who genuinely vanished (backgrounded the app, lost the network);
            // it should never be short enough to guillotine someone who is mid-decision.
            try? await Task.sleep(for: .seconds(60))
            guard let self else { return }
            if Task.isCancelled { return }
            // Bail if the situation already resolved itself (caller exposed, turn
            // advanced, or we moved on to a new discard).
            guard self.isOnlineHost,
                  self.isOnlineMode,
                  self.gameStatus == .playing,
                  self.lastDiscardedTile?.id == discardId,
                  self.callResponseDiscardId == discardId,
                  self.lastFinalizedCallDiscardId != discardId,
                  let stuck = stuckAtSeat,
                  self.currentPlayerIndex == stuck,
                  self.callResponses.values.contains("called") else { return }
            print("⏰ caller follow-through watchdog firing — downgrading stuck \"called\" responses to skip")
            for (seat, value) in self.callResponses where value == "called" {
                self.callResponses[seat] = "skip"
            }
            self.tryFinalizeCallWindow(forceTimeout: true)
        }
    }

    // MARK: - Tile Reordering

    func moveTileInHand(fromIndex: Int, toIndex: Int) {
        guard let playerIdx = humanPlayerIndex else { return }
        guard fromIndex != toIndex,
              fromIndex >= 0, fromIndex < players[playerIdx].hand.count,
              toIndex >= 0, toIndex < players[playerIdx].hand.count else { return }
        let tile = players[playerIdx].hand.remove(at: fromIndex)
        players[playerIdx].hand.insert(tile, at: toIndex)
        selectedTileIndex = nil
    }

    private func sortTile(_ tile: MahjongTile) -> Int {
        let suitOrder: [TileSuit: Int] = [.bamboo: 0, .character: 1, .dot: 2, .wind: 3, .dragon: 4, .flower: 5, .joker: 6]
        return (suitOrder[tile.suit] ?? 0) * 100 + tile.value
    }

    var wallCount: Int { wall.count }
    var discardCount: Int { discardPile.count }

    // MARK: - Online Game Start

    func startOnlineGame(participants: [GameParticipant]) {
        gameMode = .async
        gameStatus = .charleston
        selectedTileIndex = nil
        discardPile = []
        discardPlayerMap = [:]
        moveHistory = []
        showMahjongAnimation = false
        hasDrawnThisTurn = false
        jokerSwapMode = false
        jokerSwapSourceIndex = nil
        charlestonPhase = .firstRight
        charlestonSelectedIndices = []
        charlestonComplete = false
        courtesyTileCount = 3
        showCourtesyOptions = false
        courtesyCurrentSeat = 0
        callAvailable = false
        availableCalls = []
        awaitingCall = false
        winningHand = nil
        winnerName = ""
        invalidMahjongMessage = nil
        isWallGame = false
        showEndGameOverlay = false
        pendingCallPlayerIndex = nil
        pendingCallType = nil
        lastDiscardPlayerIndex = nil
        showStopCharlestonOption = false
        showCallTileSelection = false
        callTileSelectionType = nil
        callSelectedIndices = []
        callRequiredCount = 0
        callResponses = [:]
        callResponseDiscardId = nil
        eligibleCallSeats = []

        wall = MahjongTile.createFullSet()

        let sortedParticipants = participants.sorted { $0.seatIndex < $1.seatIndex }
        let botNames = [("Lily", "lily"), ("Rose", "pink_rose"), ("Daisy", "pdaisy")]
        var botIdx = 0

        var gamePlayers: [GamePlayer] = []
        for seatIdx in 0..<4 {
            let seat = SeatPosition.allCases[seatIdx]
            if let participant = sortedParticipants.first(where: { $0.seatIndex == seatIdx }) {
                let profile = PlayerProfile(displayName: participant.displayName, avatarImage: participant.avatarImage)
                gamePlayers.append(GamePlayer(
                    profile: profile,
                    seatPosition: seat,
                    isCurrentTurn: seatIdx == 0,
                    isBot: false
                ))
            } else {
                let bot = botNames[min(botIdx, botNames.count - 1)]
                let profile = PlayerProfile(displayName: bot.0, avatarImage: bot.1)
                gamePlayers.append(GamePlayer(
                    profile: profile,
                    seatPosition: seat,
                    isBot: true
                ))
                botIdx += 1
            }
        }

        players = gamePlayers

        for i in 0..<players.count {
            var hand: [MahjongTile] = []
            for _ in 0..<13 {
                if !wall.isEmpty {
                    hand.append(wall.removeFirst())
                }
            }
            hand.sort { sortTile($0) < sortTile($1) }
            players[i].hand = hand
        }

        for i in 0..<players.count where players[i].isBot {
            players[i].targetHand = HandMatcher.selectBestTargetHand(hand: players[i].hand, card: activeCard)
        }

        currentPlayerIndex = 0
        gameMessage = "1st Charleston: Select 3 tiles to pass right"
    }

    // MARK: - State Serialization

    func serializeState() -> SerializedGameState {
        let serializedPlayers = players.map { player in
            SerializedPlayer(
                displayName: player.profile.displayName,
                avatarImage: player.profile.avatarImage,
                seatPosition: player.seatPosition.rawValue,
                hand: player.hand,
                exposedSets: player.exposedSets,
                score: player.score,
                isBot: player.isBot,
                userId: nil
            )
        }

        let stringKeyMap = Dictionary(uniqueKeysWithValues: discardPlayerMap.map { (key, value) in
            (key.uuidString, value)
        })

        let pendingPassesStringKey = Dictionary(uniqueKeysWithValues: charlestonPendingPasses.map { (k, v) in
            (String(k), v)
        })

        return SerializedGameState(
            wall: wall,
            players: serializedPlayers,
            discardPile: discardPile,
            discardPlayerMap: stringKeyMap,
            currentPlayerIndex: currentPlayerIndex,
            gameStatus: gameStatus.rawValue,
            charlestonPhase: charlestonPhase.rawValue,
            charlestonComplete: charlestonComplete,
            charlestonPendingPasses: pendingPassesStringKey,
            courtesyTileCount: courtesyTileCount,
            showCourtesyOptions: showCourtesyOptions,
            courtesyCurrentSeat: courtesyCurrentSeat,
            showStopCharlestonOption: showStopCharlestonOption,
            lastDiscardedTile: lastDiscardedTile,
            lastDiscardPlayerIndex: lastDiscardPlayerIndex,
            hasDrawnThisTurn: hasDrawnThisTurn,
            isWallGame: isWallGame,
            showEndGameOverlay: showEndGameOverlay,
            winnerName: winnerName,
            showMahjongAnimation: showMahjongAnimation,
            winningHandName: winningHand?.name,
            winningHandCategory: winningHand?.category,
            winningHandPoints: winningHand?.points,
            gameMessage: gameMessage,
            selectedCardYear: selectedCardYear.rawValue,
            callWindow: nil,
            callResponses: Dictionary(uniqueKeysWithValues: callResponses.map { (String($0.key), $0.value) }),
            callResponseDiscardId: callResponseDiscardId?.uuidString
        )
    }

    func restoreState(from state: SerializedGameState) {
        wall = state.wall
        discardPile = state.discardPile
        currentPlayerIndex = state.currentPlayerIndex
        gameStatus = GameStatus(rawValue: state.gameStatus) ?? .playing
        charlestonPhase = CharlestonPhase(rawValue: state.charlestonPhase) ?? .firstRight
        charlestonComplete = state.charlestonComplete
        if let pending = state.charlestonPendingPasses {
            charlestonPendingPasses = Dictionary(uniqueKeysWithValues: pending.compactMap { (k, v) in
                guard let i = Int(k) else { return nil }
                return (i, v)
            })
        } else {
            charlestonPendingPasses = [:]
        }
        if let count = state.courtesyTileCount { courtesyTileCount = count }
        showCourtesyOptions = state.showCourtesyOptions ?? false
        if let seat = state.courtesyCurrentSeat { courtesyCurrentSeat = seat }
        showStopCharlestonOption = state.showStopCharlestonOption ?? false
        lastDiscardedTile = state.lastDiscardedTile
        lastDiscardPlayerIndex = state.lastDiscardPlayerIndex
        hasDrawnThisTurn = state.hasDrawnThisTurn
        isWallGame = state.isWallGame
        showEndGameOverlay = state.showEndGameOverlay
        winnerName = state.winnerName
        if let anim = state.showMahjongAnimation {
            // Latch the win animation on; never let a later state turn it off
            // (the receiver clears it locally when the overlay is dismissed).
            if anim { showMahjongAnimation = true }
        }
        gameMessage = state.gameMessage

        if let yearStr = NMJLCardYear(rawValue: state.selectedCardYear) {
            selectedCardYear = yearStr
        }

        discardPlayerMap = Dictionary(uniqueKeysWithValues: state.discardPlayerMap.compactMap { (key, value) in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, value)
        })

        var restoredPlayers: [GamePlayer] = []
        for sp in state.players {
            let seat = SeatPosition(rawValue: sp.seatPosition) ?? .east
            let profile = PlayerProfile(displayName: sp.displayName, avatarImage: sp.avatarImage)
            var gp = GamePlayer(
                profile: profile,
                hand: sp.hand,
                exposedSets: sp.exposedSets,
                score: sp.score,
                seatPosition: seat,
                isBot: sp.isBot
            )
            if sp.isBot {
                gp.targetHand = HandMatcher.selectBestTargetHand(hand: sp.hand, card: activeCard)
            }
            restoredPlayers.append(gp)
        }
        // MID-SELECTION HAND FREEZE.
        //
        // While this player is choosing which tiles to expose for a call, their hand is a
        // LIVE TRANSACTION. `callSelectedIndices` holds positional indices INTO that
        // array, and `confirmCallSelection` both reads the picked tiles AND removes them
        // by those same indices. A remote state landing mid-selection swaps the whole hand
        // out from under them: the indices now address DIFFERENT tiles, the eligibility
        // check ("each tile must match the discard or be a joker") fails, and the call is
        // silently dropped — the player watches their confirmed call reverse and the turn
        // move on. When the substituted tiles happen to be eligible it's worse still: they
        // expose tiles they never picked.
        //
        // Whether a broadcast lands inside that window is pure timing, which is exactly
        // why SOME calls survive and some reverse. Nobody else can legitimately change our
        // hand while we're mid-call — we haven't committed the exposure yet, so no peer
        // has anything new to tell us about it — so hold ours and let every other part of
        // the packet apply as normal.
        if showCallTileSelection,
           let me = humanPlayerIndex,
           me < players.count,
           me < restoredPlayers.count {
            restoredPlayers[me].hand = players[me].hand
            print("🔒 holding seat \(me)'s hand — mid call-tile selection")
        }

        players = restoredPlayers

        charlestonSelectedIndices = []
        selectedTileIndex = nil
        invalidMahjongMessage = nil
        // Resolve the winning hand from its serialized name against the active
        // card so the end-game overlay can display the matched pattern on every
        // client (host AND invitees). Without this, non-declaring seats would
        // see a generic completion screen with no hand info.
        if let handName = state.winningHandName {
            winningHand = activeCard.hands.first(where: { $0.name == handName })
        } else {
            winningHand = nil
        }

        // Merge call-window responses from the incoming state. Each client owns its
        // own seat's response; we OR everyone's responses together so the host can
        // finalize once all eligible humans have answered.
        let incomingDiscardId = state.callResponseDiscardId.flatMap { UUID(uuidString: $0) }

        // NEVER let a peer resurrect a call window we have already finalized.
        //
        // A seat that skipped keeps broadcasting its own `callResponses` /
        // `callResponseDiscardId` until it hears otherwise. Once the host finalizes it
        // nils both out — but that stale echo then arrives and the merge below happily
        // re-set them, re-opening a window everybody had moved past. The host then
        // re-broadcast the resurrected window, the peer echoed it straight back, and
        // the two clients ping-ponged indefinitely (the five-figure `state updates rx`
        // counts in the diagnostics). Worse, the re-opened window kept `canDrawTile`
        // false, so the seat whose turn it now was could never draw.
        if let incomingDiscardId, incomingDiscardId == lastFinalizedCallDiscardId {
            callResponses = [:]
            callResponseDiscardId = nil
            callAvailable = false
            availableCalls = []
            eligibleCallSeats = []
            return
        }

        if let incomingDiscardId, incomingDiscardId == lastDiscardedTile?.id {
            var merged: [Int: String] = callResponseDiscardId == incomingDiscardId ? callResponses : [:]
            if let incoming = state.callResponses {
                for (k, v) in incoming {
                    guard let seat = Int(k) else { continue }
                    // "called" beats "skip".
                    if merged[seat] != "called" { merged[seat] = v }
                }
            }
            callResponses = merged
            callResponseDiscardId = incomingDiscardId
        } else {
            // Stale or no discard — reset.
            callResponses = [:]
            callResponseDiscardId = incomingDiscardId
            callAvailable = false
            availableCalls = []
        }
    }

    func resetOnlineMode() {
        isOnlineMode = false
        onlineGameId = nil
        localSeatIndex = 0
        onlineSyncHandler = nil
    }

    /// Force-correct each seat's `isBot` flag from the authoritative seat sets owned
    /// by `OnlineGameViewModel`. Without this safety net, a stale serialized state
    /// (e.g. a payload built before an invitee joined, or a host-bot toggle that
    /// happened mid-game) can leave the host's local player list marking a real
    /// invitee seat as a bot — at which point `proceedWithTurn` and the bot driver
    /// in `applyRemoteState` will auto-play that seat, producing the rapid
    /// "skip past the invitee over and over" loop. Idempotent; safe to call any time.
    func rectifyBotFlags(realParticipantSeats: Set<Int>, hostBotSeats: Set<Int>) {
        guard isOnlineMode else { return }
        for seat in 0..<players.count {
            if realParticipantSeats.contains(seat) {
                if players[seat].isBot {
                    print("🩺 rectifyBotFlags: seat \(seat) was isBot=true but has a real participant — forcing false")
                    players[seat].isBot = false
                    // Drop any bot target hand so HandMatcher/discard helpers never
                    // try to drive a human seat as a bot.
                    players[seat].targetHand = nil
                }
            } else if hostBotSeats.contains(seat) {
                if !players[seat].isBot {
                    players[seat].isBot = true
                }
            }
        }
    }

    func applyRemoteState(_ state: SerializedGameState) {
        // PHASE-ROLLBACK GUARD. Stale broadcasts (invitee heartbeats still in flight
        // when the host has already finalized the exchange and advanced) would otherwise
        // reset our phase/pending and put everyone back into the previous Charleston step
        // — exactly the loop the diagnostics show ([0,1,2] re-appearing forever).
        // If the incoming state is older than our local Charleston progress, ignore it.
        let incomingStatus = GameStatus(rawValue: state.gameStatus) ?? .playing
        let incomingPhase = state.charlestonPhase
        // COMPLETED IS TERMINAL. Once this client has marked the game as completed
        // (Mahjong declared, wall game, etc.), NEVER accept a remote state that
        // tries to roll us back to playing/charleston. This is the bug that caused
        // an invitee to lose their own Mahjong: their local attemptMahjong set
        // gameStatus = .completed and broadcast it, but a stale .playing heartbeat
        // from the host arrived a moment later and reverted the invitee. The
        // invitee was then forced into a normal turn (draw → empty wall → wall
        // game) while the host — having absorbed the .completed broadcast — was
        // showing the Mahjong overlay. The win is authoritative the instant the
        // declaring client sets it locally; no rollback is ever legitimate.
        if isOnlineMode,
           gameStatus == .completed,
           incomingStatus != .completed {
            print("⏪ ignoring stale broadcast — local game is .completed, incoming \(incomingStatus.rawValue)")
            // Re-push our terminal state so peers catch up to the win.
            onlineSyncHandler?()
            return
        }
        // Going from playing back to charleston, or from a higher charleston phase back
        // to a lower one, is never legal — drop the broadcast entirely.
        if isOnlineMode {
            let weArePlaying = gameStatus == .playing
            let theyAreCharleston = incomingStatus == .charleston
            if weArePlaying && theyAreCharleston {
                print("⏪ ignoring stale charleston broadcast — we are already playing")
                return
            }
            if gameStatus == .charleston && incomingStatus == .charleston && incomingPhase < charlestonPhase.rawValue {
                print("⏪ ignoring stale charleston broadcast — incoming phase \(incomingPhase) < local phase \(charlestonPhase.rawValue)")
                return
            }
            // PLAY-PHASE ROLLBACK GUARD. The discard pile is strictly monotonic in
            // the playing phase — it only grows. An incoming state with FEWER
            // discards than we already have is necessarily a stale echo (an
            // invitee's heartbeat / retry broadcast that crossed wires with a
            // newer host advance, or a buffered packet replayed after reconnect).
            //
            // Without this guard, `restoreState` happily rolls `currentPlayerIndex`,
            // `hand`, and `discardPile` back to the older snapshot. The host's bot
            // driver in this same function then re-fires the bot whose turn was
            // already played — producing the "speeding up / playing itself /
            // skipping the real seats" symptom: every stale echo rolls a bot's
            // turn back, host immediately re-runs it, advances, another stale echo
            // rolls it back, etc. The invitee and host never see their own turns.
            //
            // Mahjong / wall games legitimately end the game; the `completed`
            // status check below still allows that transition (an end-of-game
            // payload may have an equal-or-larger discard pile, never smaller).
            if weArePlaying && incomingStatus == .playing
                && state.discardPile.count < discardPile.count {
                // CRITICAL EXCEPTION — non-host caller mid-exposure.
                // When an invitee calls a discard, they remove the called tile
                // from the pile and append it to their exposedSets, but haven't
                // discarded yet. Their broadcast legitimately has ONE FEWER
                // discard than the host. Detect: incoming has new exposedSets
                // for some seat AND the missing discard tile is in that seat's
                // newest exposed set. Without this carve-out the host drops the
                // invitee's exposure broadcast as "rollback", the call window
                // eventually times out, the host force-skips, and the caller's
                // tiles snap back to the rack — exactly the freeze users report.
                let isCallerExposure: Bool = {
                    // Any SMALLER pile, not exactly one smaller.
                    //
                    // This used to demand `== discardPile.count - 1`. But by the time a
                    // caller's exposure broadcast lands, WE may already have moved on — a
                    // bot discarded, the turn advanced — so the gap is often more than one
                    // and this carve-out silently failed. We then rejected a perfectly
                    // legitimate call as a "rollback"; the caller's own guard rejected OUR
                    // state right back (accepting it would erase their exposure) and
                    // re-pushed; and the two clients deadlocked, hammering each other at
                    // network speed — thousands of state updates for a single discard —
                    // until the caller finally gave in and their call visibly reversed.
                    //
                    // The real proof of a caller exposure isn't the arithmetic: it's that
                    // the tile missing from their pile is sitting in their new exposed set.
                    // That test below is exact and can't false-positive, so the count only
                    // has to be smaller.
                    guard state.discardPile.count < discardPile.count else { return false }
                    var callerIdx: Int?
                    for (idx, sp) in state.players.enumerated() where idx < players.count {
                        if sp.exposedSets.count > players[idx].exposedSets.count {
                            callerIdx = idx
                            break
                        }
                    }
                    guard let cIdx = callerIdx,
                          let newSet = state.players[cIdx].exposedSets.last else { return false }
                    let incomingIds = Set(state.discardPile.map { $0.id })
                    let removedIds = discardPile.map { $0.id }.filter { !incomingIds.contains($0) }
                    return newSet.contains { removedIds.contains($0.id) }
                }()
                if isCallerExposure {
                    print("✅ accepting non-host caller exposure (discards \(discardPile.count) → \(state.discardPile.count))")
                } else {
                    print("⏪ ignoring stale play-phase broadcast — incoming discards=\(state.discardPile.count) < local discards=\(discardPile.count)")
                    return
                }
            }
            // STALE PRE-EXPOSURE GUARD — protects ANY seat's call, not just our own.
            //
            // When a seat claims a discard we pull that tile OUT of the discard pile
            // and push it into that seat's exposedSets. A peer whose heartbeat was
            // already in flight still has the tile sitting loose in their pile, so
            // their packet arrives looking "ahead" of us (one MORE discard) — and
            // restoreState would happily undo the call: the tile snaps back into the
            // pile, the exposure vanishes, and the turn pointer rolls back to the
            // discarder.
            //
            // This used to be scoped to `localSeatIndex`, which covers a HUMAN calling
            // on their own device. But the host also drives the BOTS — a bot's exposure
            // lands on a BOT seat, so the old guard never fired for it. An invitee's
            // in-flight pre-call heartbeat would sail through and erase the bot's
            // claim; the host then re-detected the very same discard and the bot
            // claimed it again, over and over: the "bot called, reversed, re-called,
            // stuck" loop. Scope it to every seat we hold an unabsorbed exposure for.
            //
            // The tile-id test keeps this precise: we only drop the packet when the
            // sender still has the exact tile we just claimed sitting in their discard
            // pile, which can only mean their state predates our call.
            if weArePlaying && incomingStatus == .playing
                && state.discardPile.count > discardPile.count {
                let localDiscardIds = Set(discardPile.map { $0.id })
                let extraInIncoming = Set(
                    state.discardPile.map { $0.id }.filter { !localDiscardIds.contains($0) }
                )
                if !extraInIncoming.isEmpty {
                    for seat in 0..<min(players.count, state.players.count) {
                        // Only seats where WE hold an exposure the sender hasn't absorbed yet.
                        guard players[seat].exposedSets.count > state.players[seat].exposedSets.count,
                              let newestSet = players[seat].exposedSets.last else { continue }
                        // ...and the sender still has the claimed tile loose in their pile.
                        guard newestSet.contains(where: { extraInIncoming.contains($0.id) }) else { continue }
                        print("⏪ ignoring stale pre-exposure broadcast — would erase seat \(seat)'s call exposure (local discards=\(discardPile.count), incoming=\(state.discardPile.count))")
                        // Re-push AT MOST ONCE per discard.
                        //
                        // Unthrottled, this is what weaponised the deadlock above: every
                        // stale packet from the peer triggered a re-push from us, their
                        // guard rejected it and re-pushed straight back, and the two
                        // clients hammered each other as fast as the socket allowed. One
                        // nudge is all the sender needs — if they still haven't caught up,
                        // their own heartbeat will ask again. A rejection must never be
                        // able to generate traffic in a loop.
                        if lastPreExposureRepushDiscardId != discarded.id {
                            lastPreExposureRepushDiscardId = discarded.id
                            onlineSyncHandler?()
                        }
                        return
                    }
                }
            }
            // HAS-DRAWN ROLLBACK GUARD. A stale broadcast at the same turn with
            // the same discard pile that has hasDrawnThisTurn=false would otherwise
            // wipe the current player's drawn tile state, letting them "draw again"
            // (the loop where one player keeps drawing over and over until the user
            // hits Force Resolve). Strictly drop these stale echoes.
            //
            // CRITICAL EXCEPTION — call + discard. When a non-host player calls a
            // pung/kong/quint and then discards, the net pile count is unchanged
            // (the called tile is removed from the pile, the follow-up discard
            // is appended), the turn pointer is still the caller, and
            // hasDrawnThisTurn flips from true (set by executeCall) to false
            // (cleared by discardSelectedTile). That looks identical to a stale
            // echo by the count/turn/hasDrawn signature, but the lastDiscardedTile
            // is genuinely new. Without this carve-out the host silently drops
            // the caller's discard broadcast, never runs checkAllPlayersForCalls,
            // and the turn never advances to the player on the right — the
            // "frozen after a call + discard" symptom from multiplayer reports.
            if weArePlaying && incomingStatus == .playing
                && state.discardPile.count == discardPile.count
                && state.currentPlayerIndex == currentPlayerIndex
                && hasDrawnThisTurn
                && !state.hasDrawnThisTurn
                && state.lastDiscardedTile?.id == lastDiscardedTile?.id {
                print("⏪ ignoring stale play-phase broadcast — would roll hasDrawnThisTurn back (turn=\(currentPlayerIndex))")
                return
            }
            // Same idea for equal-discard-count echoes that try to roll the turn
            // pointer backwards — e.g. a buffered broadcast from before the host
            // advanced. CRITICAL: this guard must be one-directional. The legitimate
            // post-discard advance moves the pointer from the discarder to the next
            // seat (discarder+1). The stale-echo case is the REVERSE: local is
            // already at discarder+1, incoming is still parked on the discarder.
            // A previous symmetric ring-distance check rejected BOTH directions,
            // which froze non-hosts: they sit at the discarder's seat waiting for
            // the host to advance, then dropped the host's advance broadcast as
            // "rollback" and stayed on the discarder forever.
            if weArePlaying && incomingStatus == .playing
                && state.discardPile.count == discardPile.count
                && state.currentPlayerIndex != currentPlayerIndex
                && !hasDrawnThisTurn
                && lastDiscardedTile != nil
                && state.lastDiscardedTile?.id == lastDiscardedTile?.id,
               let discarderSeat = lastDiscardPlayerIndex,
               players.count > 0 {
                let expectedNext = (discarderSeat + 1) % players.count
                if currentPlayerIndex == expectedNext && state.currentPlayerIndex == discarderSeat {
                    print("⏪ ignoring stale play-phase pointer rollback — incoming turn=\(state.currentPlayerIndex) local turn=\(currentPlayerIndex)")
                    return
                }
            }
        }

        // Snapshot this seat's own Charleston pass + hand before the merge so we never lose
        // our submission if a concurrent write from another player arrives without it.
        let mySeat = localSeatIndex
        let priorMyPass: [MahjongTile]? = isOnlineMode ? charlestonPendingPasses[mySeat] : nil
        let priorMyHand: [MahjongTile]? = (isOnlineMode && mySeat < players.count) ? players[mySeat].hand : nil
        let priorPhase = charlestonPhase
        let priorStatus = gameStatus
        // The host orchestrates the Charleston, so it must remember every pending pass it
        // has already seen. Concurrent non-host writes can clobber one another's entries
        // (read-modify-write race), so we preserve any pass we already know about across
        // remote merges that share the same Charleston phase.
        let priorPendingPasses = charlestonPendingPasses
        let priorPlayerHands: [Int: [MahjongTile]] = isOnlineMode
            ? Dictionary(uniqueKeysWithValues: players.enumerated().map { ($0.offset, $0.element.hand) })
            : [:]
        // Preserve in-progress local tile selections across the merge — the host
        // broadcasts a Charleston heartbeat ~every second, and restoreState would
        // otherwise wipe `charlestonSelectedIndices` on every tick, making it
        // impossible for the invitee to ever finish picking their pass.
        let priorSelectedIndices = charlestonSelectedIndices
        let priorShowCourtesy = showCourtesyOptions

        isApplyingRemoteState = true
        restoreState(from: state)
        // Rectify bot flags IMMEDIATELY after restoreState so all subsequent
        // host orchestration in this function (tryFinalizeCharlestonPass,
        // advanceCourtesyTurnPastBots, bot drivers) operates against the correct
        // seat ownership. Without this, a non-host's broadcast carrying a stale
        // isBot=true on an invitee seat would cause the host to auto-fill that
        // seat's Charleston pass and skip the real invitee.
        selfRectifyBotFlags()
        isApplyingRemoteState = false

        // PRESERVE LOCAL HAND ORDER. Players manually rearrange their tiles
        // (drag-and-drop on the rack) and that order must persist across remote
        // state merges. The server's payload carries a canonical ordering that
        // would otherwise overwrite the user's arrangement on every heartbeat.
        // Reconcile by reusing the prior local order for any tile IDs that
        // survived the merge, and appending newly-added tiles (e.g. a draw or
        // Charleston receive) at the end so the user can place them themselves.
        if isOnlineMode,
           let priorMyHand,
           mySeat >= 0,
           mySeat < players.count {
            let newHand = players[mySeat].hand
            let newIds = Set(newHand.map { $0.id })
            let kept = priorMyHand.filter { newIds.contains($0.id) }
            let keptIds = Set(kept.map { $0.id })
            let added = newHand.filter { !keptIds.contains($0.id) }
            let merged = kept + added
            if merged.count == newHand.count {
                players[mySeat].hand = merged
            }
        }

        // COURTESY-OPTIONS ONE-WAY LATCH. Once East has chosen the courtesy tile
        // count (or skipped), `showCourtesyOptions` is cleared locally. A stale
        // broadcast from another seat that still has `showCourtesyOptions = true`
        // must NOT reopen the chooser — otherwise East (and everyone else) bounce
        // between the count-picker and the tile-picker screens. Once false in this
        // courtesy phase, stay false.
        if isOnlineMode,
           gameStatus == .charleston,
           priorStatus == .charleston,
           priorPhase == charlestonPhase,
           priorPhase.isCourtesy,
           !priorShowCourtesy,
           showCourtesyOptions {
            print("⏪ ignoring stale courtesy broadcast — would reopen chooser after East already chose")
            showCourtesyOptions = false
        }

        // Re-apply local tile selection if we're still in the same Charleston phase,
        // we haven't submitted yet, and our hand wasn't replaced under us. Indices
        // are only meaningful if both the phase and the hand are unchanged.
        if isOnlineMode,
           gameStatus == .charleston,
           priorStatus == .charleston,
           priorPhase == charlestonPhase,
           priorShowCourtesy == showCourtesyOptions,
           charlestonPendingPasses[mySeat] == nil,
           mySeat < players.count,
           let myHand = priorMyHand,
           players[mySeat].hand == myHand,
           !priorSelectedIndices.isEmpty {
            charlestonSelectedIndices = priorSelectedIndices
        }

        // Re-apply our own Charleston submission if the incoming state is still in the
        // same Charleston phase but lacks our entry (a concurrent write from another seat).
        // CRITICAL: when this happens the SERVER also lost our pass (the other seat's write
        // was a full-state replacement that clobbered ours), so we must re-push it. Otherwise
        // the host will never see our submission and Charleston stalls.
        var inviteeShouldRepushPass = false
        if isOnlineMode,
           gameStatus == .charleston,
           priorStatus == .charleston,
           priorPhase == charlestonPhase,
           let myPass = priorMyPass,
           charlestonPendingPasses[mySeat] == nil,
           mySeat < players.count {
            charlestonPendingPasses[mySeat] = myPass
            if let myHand = priorMyHand {
                players[mySeat].hand = myHand
            }
            inviteeShouldRepushPass = !isOnlineHost
        }

        // COURTESY-TURN STABILIZATION. The host's heartbeat broadcasts a stale
        // courtesyCurrentSeat (e.g. still pointing at us) until it absorbs our
        // submission. restoreState would roll our local pointer back to that
        // stale value every tick — the visible "stuck at courtesy pass" symptom
        // where invitee sat with turn=1 (their own seat) forever even after
        // submitting. If we have a pending pass for our seat AND the merged
        // pointer is still on or before us, advance it past us locally so the
        // UI stays stable and our outgoing broadcasts carry the correct pointer.
        if isOnlineMode,
           gameStatus == .charleston,
           charlestonPhase.isCourtesy,
           courtesyTileCount > 0,
           mySeat >= 0,
           charlestonPendingPasses[mySeat] != nil,
           courtesyCurrentSeat <= mySeat {
            courtesyCurrentSeat = mySeat + 1
        }

        // Host-only: preserve any previously-seen pending passes for OTHER seats that the
        // incoming state is missing. This protects against two non-hosts racing each other:
        // each fetch-then-write only injects its own seat, so the second writer's payload
        // can drop the first writer's entry. Without this guard, the host would forget the
        // first pass and Charleston would stall.
        if isOnlineHost,
           gameStatus == .charleston,
           priorStatus == .charleston,
           priorPhase == charlestonPhase {
            for (seat, pass) in priorPendingPasses where charlestonPendingPasses[seat] == nil {
                charlestonPendingPasses[seat] = pass
                // Also restore that seat's hand snapshot so the post-exchange math stays consistent.
                if seat < players.count, let savedHand = priorPlayerHands[seat] {
                    players[seat].hand = savedHand
                }
            }
        }

        // Host orchestrates the Charleston exchange whenever a remote player submits their pass.
        if isOnlineHost && gameStatus == .charleston && !charlestonPhase.isCourtesy {
            tryFinalizeCharlestonPass()
        } else if isOnlineHost && gameStatus == .charleston && charlestonPhase.isCourtesy && courtesyTileCount > 0 && !showCourtesyOptions {
            // Sequential courtesy: keep auto-playing bots whose turn it is, then
            // finalize once everyone has submitted.
            advanceCourtesyTurnPastBots()
        }

        // Non-host: if the merge restored our own Charleston pass that the incoming state
        // had dropped, re-broadcast so the server (and the host) actually pick it up.
        if inviteeShouldRepushPass {
            onlineSyncHandler?()
        }

        checkForStuckPlayPhase()
    }

    /// Play-phase self-healing: evaluates calls on a not-yet-processed remote
    /// discard, finalizes an open call window if we've received a response,
    /// force-finalizes a call window that's stuck open on the discarder, and
    /// kicks off a bot's turn if one just became active.
    ///
    /// Previously this logic only ran reactively, inline inside
    /// `applyRemoteState` — meaning it only had a chance to self-heal a stuck
    /// game if the host happened to receive ANOTHER remote update after the
    /// one that got it stuck. If nothing else changed (e.g. an invitee
    /// discarded once and then just waited), the host's own heartbeat kept
    /// re-broadcasting the same stuck state forever with nothing to trigger
    /// this check. It's now also called proactively from the host's periodic
    /// play-phase heartbeat, so the game can self-heal even with no further
    /// remote activity at all.
    func checkForStuckPlayPhase() {
        if isOnlineMode, gameStatus == .playing, !showEndGameOverlay {
            // WALL-GAME BACKSTOP (host-authoritative).
            //
            // A wall game is normally declared by whichever draw path first meets an
            // empty wall (`drawTile`, `executeBotTurn`, or the host force-drawing for
            // a stalled remote human). But every one of those paths sits behind
            // guards — an open call window, a blocked post-discard draw, a seat that
            // simply never acts — and if any of them bails early, nobody declares:
            // the table sits on an empty wall with no ending and no overlay, on every
            // device. Checking here as well, on the host's heartbeat, makes the ending
            // depend on the wall being empty rather than on some particular seat
            // successfully taking its turn.
            //
            // TIMING IS THE WHOLE TRICK: an empty wall is NOT by itself a wall game.
            // Whoever drew the last tile still gets to discard, and that final discard
            // is still claimable — someone can legitimately win on it. So we only
            // declare once the turn has actually reached a seat that MUST draw
            // (`!hasDrawnThisTurn`) with no call window open in any form. Those are
            // exactly the conditions the draw paths themselves check, so this doesn't
            // end the game any earlier than a normal draw attempt would — it just
            // guarantees the check happens.
            if isOnlineHost,
               wall.isEmpty,
               !hasDrawnThisTurn,
               !awaitingCall,
               !callAvailable,
               !showCallTileSelection,
               callResponseDiscardId == nil {
                print("🧱 wall-game backstop — wall empty and turn \(currentPlayerIndex) must draw; declaring")
                declareWallGame()
                return
            }

            if let discarded = lastDiscardedTile,
               lastProcessedDiscardId != discarded.id,
               let discIdx = lastDiscardPlayerIndex,
               discIdx != localSeatIndex {
                lastProcessedDiscardId = discarded.id
                // Every client evaluates local human-call options; only the host
                // actually advances the turn / drives bot decisions (the gates inside
                // `checkAllPlayersForCalls` already enforce that for non-hosts).
                checkAllPlayersForCalls(discardedBy: discIdx)
            } else if isOnlineHost,
                      let discarded = lastDiscardedTile,
                      callResponseDiscardId == discarded.id,
                      (callAvailable || !eligibleCallSeats.isEmpty || awaitingCall) {
                // Another player just sent us their call-window response. Try to finalize.
                // CRITICAL: only re-enter the finalize path if the call window is still
                // OPEN. If the host already advanced past this discard, a late echo from
                // an invitee (carrying their auto-skip for the same discard) must NOT
                // trigger another `proceedWithTurn` — that would skip the next seat
                // entirely. The `tryFinalizeCallWindow` body still re-checks this guard
                // as a belt-and-suspenders.
                tryFinalizeCallWindow()
            } else if isOnlineHost,
                      let discarded = lastDiscardedTile,
                      let discIdx = lastDiscardPlayerIndex,
                      currentPlayerIndex == discIdx,
                      lastProcessedDiscardId == discarded.id,
                      lastFinalizedCallDiscardId != discarded.id,
                      !awaitingCall,
                      !showCallTileSelection,
                      !callResponses.values.contains("called") {
                // STUCK-ON-DISCARDER RECOVERY. The host already processed this discard
                // once (lastProcessedDiscardId matches) but the turn pointer is still
                // parked on the discarder and the call window was never finalized.
                // This happens when the initial finalize path was interrupted (e.g. an
                // overlapping broadcast restored the call-window state mid-finalize,
                // or the call watchdog never armed because a transient guard tripped).
                // Force-finalize so the game can advance instead of sitting frozen.
                // Safe because no caller is mid-exposure and no bot mahjong is pending.
                print("🛟 stuck-on-discarder recovery — forcing call window finalization (turn=\(currentPlayerIndex))")
                tryFinalizeCallWindow(forceTimeout: true)
            } else if isOnlineHost,
                      currentPlayerIndex < players.count,
                      { selfRectifyBotFlags(); return seatIsDrivableBot(currentPlayerIndex) }(),
                      !hasDrawnThisTurn,
                      !awaitingCall,
                      !callAvailable,
                      !showCallTileSelection {
                // Host drives a bot whose turn just became active via remote state.
                let captured = currentPlayerIndex
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Double.random(in: 1.0...1.7)))
                    guard let self else { return }
                    if self.currentPlayerIndex == captured,
                       captured < self.players.count,
                       self.seatIsDrivableBot(captured),
                       !self.hasDrawnThisTurn,
                       !self.awaitingCall,
                       !self.callAvailable,
                       !self.showCallTileSelection,
                       self.gameStatus == .playing {
                        self.executeBotTurn()
                    }
                }
            }
            armOrCancelRemoteHumanTurnWatchdog()
            armOrCancelNonHostPostDiscardWatchdog()
        }
    }
}
