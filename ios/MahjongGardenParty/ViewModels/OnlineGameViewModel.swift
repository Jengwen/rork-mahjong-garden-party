import SwiftUI
import Supabase
import Realtime

@Observable
@MainActor
class OnlineGameViewModel {
    var activeGames: [OnlineGameSummary] = []
    var pendingInvites: [GameInvite] = []
    var inviteSenderProfiles: [String: FriendProfile] = [:]
    var currentGameId: String?
    var currentGame: OnlineGame?
    var currentParticipants: [GameParticipant] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var isPolling: Bool = false
    var showGameBoard: Bool = false
    var realtimeStatus: String = "disconnected"
    var sentInvitesCount: Int = 0
    var pendingInviteCountForCurrentGame: Int = 0
    var didAutoStart: Bool = false
    var isQuickMatchGame: Bool = false
    var quickMatchStartedAt: Date?
    /// Seats the host has explicitly chosen to fill with a bot before starting the game.
    var hostBotSeats: Set<Int> = []
    let quickMatchAutoStartSeconds: TimeInterval = 120
    /// Cached identity for the local player so we can re-broadcast `joined` presence
    /// events even after a channel reconnect.
    var myDisplayName: String = ""
    var myAvatarImage: String = ""
    /// The seat this user joined into. Source of truth used to re-synthesize our own
    /// participant entry whenever an RLS-restricted fetch returns a list missing us.
    /// Without this, an invitee whose SELECT on `game_participants` is blocked ends up
    /// with `mySeatIndex == nil`, `localSeatIndex == 0`, and Charleston routing breaks.
    var myKnownSeat: Int?
    /// Tracks how many state-update broadcasts we've received (for diagnostics).
    var stateUpdatesReceived: Int = 0
    /// Tracks how many `joined` presence broadcasts we've received (for diagnostics).
    var joinedBroadcastsReceived: Int = 0
    private var charlestonHeartbeatTask: Task<Void, Never>?
    private var charlestonPassHeartbeatTask: Task<Void, Never>?
    private var charlestonInviteePullTask: Task<Void, Never>?
    /// Persisted across heartbeat restarts so a self-initiated reconnect (which
    /// cancels and re-arms the heartbeat) can't reset the watchdog timer back to
    /// nil and indefinitely defer the force-finalize escape hatch. Keyed by the
    /// charleston phase rawValue so a real phase advance still resets it.
    private var charlestonIncompleteSince: Date? = nil
    private var charlestonIncompletePhase: Int = -1
    private var charlestonLastForceFinalizeAt: Date = .distantPast
    private var charlestonLastReconnectAt: Date = .distantPast
    /// Invitee-side phase-stuck watchdog state. Persisted on the VM (rather than
    /// kept as task-local vars) so a self-initiated forceReconnect — which cancels
    /// and re-creates the invitee pull task — can't reset the clock back to zero
    /// and indefinitely defer the auto-clear escape hatch. Without this, an
    /// invitee whose host→invitee channel is silently dead reconnects every ~8s
    /// (tier 3), restarting the pull task with a fresh `lastPhaseChangedAt = now`,
    /// so the 10s phase-stuck threshold is never reached. Symptom: invitee sits
    /// on "Tiles passed" forever after the 1st right while the host is many
    /// phases ahead. Reset only on a real phase advance or when leaving Charleston.
    private var inviteeLastPhaseSeen: Int = -1
    private var inviteeLastPhaseChangedAt: Date = Date()
    private var inviteeLastWatchdogClearAt: Date = .distantPast
    private var inviteeLastReconnectAt: Date = .distantPast
    /// Tracks (seat -> phase) for which the host has acknowledged our lightweight
    /// `charleston_pass` broadcast. Lets the invitee stop heartbeating once it
    /// knows the host actually has the pass — even if the larger `state_update`
    /// echoes are being silently dropped in the host->invitee direction.
    private var charlestonPassAckedFor: [Int: Int] = [:]
    private var lobbyBotSeatsHeartbeatTask: Task<Void, Never>?
    /// Host: periodic re-broadcast of the latest play-phase state so a single
    /// lost packet can't strand the table for the rest of the game.
    private var playPhaseHostHeartbeatTask: Task<Void, Never>?
    /// Non-host: periodic state-sync pull during the play phase so we recover
    /// even when our own SELECT on `online_games` is blocked by RLS.
    private var playPhaseInviteePullTask: Task<Void, Never>?
    /// Tracks the seats whose pending Charleston pass we've ever observed in the
    /// current phase. Used by the GameBoard diagnostics overlay so the user can
    /// verify that broadcasts from the other clients are actually arriving.
    var observedCharlestonPasses: Set<Int> = []
    var lastCharlestonPhaseObserved: Int = -1
    /// Last seat we received a `state_update` broadcast from. -1 means none yet.
    var lastStateUpdateSenderSeat: Int = -1
    /// Wall-clock time of the last received `state_update`. Used to surface staleness
    /// in the Charleston diagnostics overlay.
    var lastStateUpdateAt: Date?
    /// Throttle for our own `joined` re-broadcasts in response to peer `joined`
    /// events. Without this, receive→broadcast→receive→broadcast forms a tight
    /// infinite ping-pong between every pair of clients that floods the realtime
    /// channel and starves out `state_update` deliveries — exactly the symptom
    /// where invitees stop seeing the host's turn advances after a discard.
    private var lastJoinedRebroadcastAt: Date = .distantPast

    private let service = OnlineGameService.shared
    private var pollTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var realtimeChannel: RealtimeChannelV2?
    private var lastAppliedUpdatedAt: String = ""
    private var pendingLocalSync: Bool = false
    private var notifiedInviteIds: Set<String> = []
    /// Option B — highest `game_actions.seq` we've observed for the current game.
    /// Used as the recovery cursor: any insert with `seq > lastObservedActionSeq`
    /// from a remote seat triggers a `backupSync` so we can never miss the
    /// authoritative state, even if the realtime broadcast was dropped.
    private var lastObservedActionSeq: Int64 = 0

    nonisolated struct BotSeatsPayload: Codable, Sendable {
        let seats: [Int]
    }

    /// Sent by an invitee right after they subscribe so the host can immediately
    /// re-broadcast bot_seats / participants — independent of postgres replication.
    nonisolated struct LobbySyncRequestPayload: Codable, Sendable {
        let gameId: String
        let userId: String
    }

    /// Sent by any client during Charleston that has missing pending passes — every
    /// other client responds with their own state_update so convergence is guaranteed.
    nonisolated struct StateSyncRequestPayload: Codable, Sendable {
        let gameId: String
        let requesterSeat: Int
        let phase: Int
    }

    nonisolated struct GameStartedPayload: Codable, Sendable {
        let gameId: String
        let status: String
        let state: SerializedGameState?
        let participants: [GameParticipant]?
        let cardYear: String?
    }

    nonisolated struct StateUpdatePayload: Codable, Sendable {
        let gameId: String
        let status: String
        let state: SerializedGameState
        let senderSeat: Int
    }

    /// TINY liveness ping sent by the host's routine play-phase heartbeat instead
    /// of a full `state_update`. Real changes already propagate reliably through
    /// the immediate move broadcast + retry burst + durable `game_actions` insert
    /// in `syncAfterMove` — this ping carries no game state at all. Its only job
    /// is to keep an invitee's `lastStateUpdateAt` fresh during a quiet stretch
    /// (e.g. the invitee is still deciding their move) so the staleness-escalation
    /// tiers in `ensurePlayPhaseInviteePull` don't misfire a sync request, DB
    /// pull, or — worst case — a disruptive realtime reconnect over nothing.
    /// Replacing a ~6s full-state re-serialize/broadcast/merge with this avoids
    /// paying that cost on every tick for the entire lifetime of a game.
    nonisolated struct HeartbeatPingPayload: Codable, Sendable {
        let gameId: String
        let senderSeat: Int
    }

    /// LIGHTWEIGHT CHARLESTON PASS BROADCAST. Carries only the minimum data the
    /// host needs to record a seat's pass: the seat index, current phase, the
    /// chosen tiles, and the seat's hand AFTER removing those tiles. Sent in
    /// addition to the full `state_update` broadcast — when the channel
    /// silently drops large payloads or RLS blocks the DB write, this tiny
    /// event survives where the full state does not, breaking the long
    /// Charleston stalls users see at the 1st pass right / across boundaries.
    nonisolated struct CharlestonPassPayload: Codable, Sendable {
        let gameId: String
        let seat: Int
        let phase: Int
        let tiles: [MahjongTile]
        let handAfter: [MahjongTile]
    }

    /// HOST → INVITEE acknowledgement that the host has recorded that seat's
    /// pending pass. The invitee uses this to stop its pass-heartbeat and
    /// trust that the host will drive the rest of the exchange.
    nonisolated struct CharlestonPassAckPayload: Codable, Sendable {
        let gameId: String
        let seat: Int
        let phase: Int
    }

    /// HOST → INVITEE direct request: "I'm missing your Charleston pass — please
    /// re-broadcast it RIGHT NOW." Sent when the host has been stuck for several
    /// seconds without recovering a missing human seat's pass via either realtime
    /// or the periodic DB pull. The targeted invitee responds by clearing any
    /// local 'acked' flag, immediately re-broadcasting `charleston_pass`, AND
    /// re-writing the merged DB row. Breaks the deadlock when the channel is
    /// silently dead in one direction so neither the surgical merge nor the
    /// passive heartbeat is converging the pending-pass map.
    nonisolated struct RequestPendingPassPayload: Codable, Sendable {
        let gameId: String
        let phase: Int
        /// Seats the host is still missing. The receiver only responds if its
        /// own seat index is in this list.
        let missingSeats: [Int]
    }

    /// Lightweight presence event: every client announces their participant row to the
    /// channel on subscribe. This is the RLS-proof way for invitees to learn about the
    /// host (and vice versa) when the database SELECT is blocked by RLS policies.
    nonisolated struct JoinedPayload: Codable, Sendable {
        let gameId: String
        let userId: String
        let seatIndex: Int
        let displayName: String
        let avatarImage: String
        let isHost: Bool
        let cardYear: String?

        // Back-compat: older clients didn't include cardYear in the joined payload.
        nonisolated init(gameId: String, userId: String, seatIndex: Int, displayName: String, avatarImage: String, isHost: Bool, cardYear: String? = nil) {
            self.gameId = gameId
            self.userId = userId
            self.seatIndex = seatIndex
            self.displayName = displayName
            self.avatarImage = avatarImage
            self.isHost = isHost
            self.cardYear = cardYear
        }

        nonisolated init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.gameId = try c.decode(String.self, forKey: .gameId)
            self.userId = try c.decode(String.self, forKey: .userId)
            self.seatIndex = try c.decode(Int.self, forKey: .seatIndex)
            self.displayName = try c.decode(String.self, forKey: .displayName)
            self.avatarImage = try c.decode(String.self, forKey: .avatarImage)
            self.isHost = try c.decode(Bool.self, forKey: .isHost)
            self.cardYear = try c.decodeIfPresent(String.self, forKey: .cardYear)
        }
    }

    var myUserId: String? { service.currentUserId }

    var isHost: Bool {
        guard let game = currentGame, let myId = myUserId else { return false }
        return game.hostId == myId
    }

    var canStartGame: Bool {
        guard isHost else { return false }
        let filledSeats = Set(currentParticipants.map(\.seatIndex)).union(hostBotSeats)
        return filledSeats.count >= 2
    }

    /// Returns true if a seat will be filled by a bot (either explicitly added by host
    /// or auto-filled because it's empty when the game starts).
    func isBotSeat(_ seatIndex: Int) -> Bool {
        hostBotSeats.contains(seatIndex)
    }

    func toggleBotAt(seatIndex: Int) {
        guard isHost else { return }
        // Don't allow toggling a seat that already has a real participant.
        if currentParticipants.contains(where: { $0.seatIndex == seatIndex }) { return }
        if hostBotSeats.contains(seatIndex) {
            hostBotSeats.remove(seatIndex)
        } else {
            hostBotSeats.insert(seatIndex)
        }
        // Tell every invitee in the lobby about the updated bot lineup.
        Task { await broadcastBotSeats() }
    }

    /// Host broadcasts the current bot lineup so invitees see bot seats live in the lobby.
    /// Safe to call before the channel is subscribed — falls back to REST.
    func broadcastBotSeats() async {
        guard isHost, let channel = realtimeChannel else { return }
        let payload = BotSeatsPayload(seats: Array(hostBotSeats).sorted())
        do {
            try await channel.broadcast(event: "bot_seats", message: payload)
        } catch {
            print("⚠️ broadcastBotSeats: \(error)")
        }
    }

    var mySeatIndex: Int? {
        guard let myId = myUserId else { return nil }
        return currentParticipants.first(where: { $0.userId == myId })?.seatIndex
    }

    func loadActiveGames() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activeGames = try await service.fetchMyActiveGames()
            let invites = try await service.fetchMyInvites()
            for invite in invites {
                if inviteSenderProfiles[invite.senderId] == nil {
                    inviteSenderProfiles[invite.senderId] = try await service.fetchInviteSenderProfile(senderId: invite.senderId)
                }
            }
            // Fire local notifications for newly arrived invites.
            let invitesEnabled = UserDefaults.standard.object(forKey: "settings_game_invites") as? Bool ?? true
            let masterEnabled = UserDefaults.standard.object(forKey: "settings_notifications_enabled") as? Bool ?? true
            if masterEnabled && invitesEnabled {
                for invite in invites {
                    guard let inviteId = invite.id, !notifiedInviteIds.contains(inviteId) else { continue }
                    notifiedInviteIds.insert(inviteId)
                    let senderName = inviteSenderProfiles[invite.senderId]?.displayName ?? "A friend"
                    NotificationService.notifyGameInvite(from: senderName, gameId: invite.gameId)
                }
            } else {
                for invite in invites {
                    if let inviteId = invite.id { notifiedInviteIds.insert(inviteId) }
                }
            }
            pendingInvites = invites
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createGame(displayName: String, avatarImage: String, cardYear: String) async -> String? {
        isLoading = true
        defer { isLoading = false }
        do {
            let game = try await service.createGame(cardYear: cardYear)
            guard let gameId = game.id else { return nil }
            // Host always sits at East (seat 0); invitees and bots fill South/West/North.
            try await service.joinGame(gameId: gameId, seatIndex: 0, displayName: displayName, avatarImage: avatarImage)
            myDisplayName = displayName
            myAvatarImage = avatarImage
            currentGameId = gameId
            currentGame = game
            currentParticipants = try await service.fetchParticipants(gameId: gameId)
            ensureSelfInParticipants(gameId: gameId, seatIndex: 0)
            errorMessage = nil
            return gameId
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// If the participants fetch returned no rows for our own user (commonly because RLS
    /// blocks the SELECT), synthesize a local entry so UI/diagnostics aren't blank.
    private func ensureSelfInParticipants(gameId: String, seatIndex: Int) {
        guard let myId = myUserId else { return }
        myKnownSeat = seatIndex
        if currentParticipants.contains(where: { $0.userId == myId }) { return }
        // If something else already claims our seat, don't double-occupy it — overwrite it
        // with our identity so the lobby always renders us at the seat we actually joined.
        currentParticipants.removeAll { $0.seatIndex == seatIndex }
        currentParticipants.append(GameParticipant(
            id: nil,
            gameId: gameId,
            userId: myId,
            seatIndex: seatIndex,
            displayName: myDisplayName,
            avatarImage: myAvatarImage,
            createdAt: nil
        ))
        currentParticipants.sort { $0.seatIndex < $1.seatIndex }
    }

    /// Re-inject our own participant entry whenever a server fetch overwrites the list
    /// without including us. This is the RLS-proof safety net every refresh path runs.
    private func mergeSelfIntoParticipants() {
        guard let myId = myUserId, let gameId = currentGameId else { return }
        if currentParticipants.contains(where: { $0.userId == myId }) { return }
        guard let seat = myKnownSeat else { return }
        ensureSelfInParticipants(gameId: gameId, seatIndex: seat)
    }

    /// Find an existing waiting game with an open seat (that the user isn't already in),
    /// or create a new one. Joins the game and sets it as the current game.
    /// Returns the game id on success.
    func quickMatch(displayName: String, avatarImage: String, cardYear: String) async -> String? {
        isLoading = true
        defer { isLoading = false }
        guard let myId = myUserId else {
            errorMessage = "You must be signed in."
            return nil
        }
        do {
            let openGames = try await service.fetchOpenWaitingGames()
            // Only consider games created via quick-match (not invite-only games).
            // We approximate this by trying any open waiting game; invite-only hosts will
            // typically have already moved to playing by the time other quick-matchers arrive.
            for game in openGames {
                guard let gameId = game.id else { continue }
                if game.hostId == myId { continue }
                let participants = try await service.fetchParticipants(gameId: gameId)
                if participants.contains(where: { $0.userId == myId }) { continue }
                if participants.count >= 4 { continue }
                let takenSeats = Set(participants.map(\.seatIndex))
                guard let openSeat = (0..<4).first(where: { !takenSeats.contains($0) }) else { continue }
                try await service.joinGame(gameId: gameId, seatIndex: openSeat, displayName: displayName, avatarImage: avatarImage)
                myDisplayName = displayName
                myAvatarImage = avatarImage
                currentGameId = gameId
                currentGame = game
                currentParticipants = try await service.fetchParticipants(gameId: gameId)
                ensureSelfInParticipants(gameId: gameId, seatIndex: openSeat)
                errorMessage = nil
                isQuickMatchGame = true
                quickMatchStartedAt = Date()
                return gameId
            }

            // No open game found — create a new one and mark it as a quick match.
            let newGameId = await createGame(displayName: displayName, avatarImage: avatarImage, cardYear: cardYear)
            if newGameId != nil {
                isQuickMatchGame = true
                quickMatchStartedAt = Date()
            }
            return newGameId
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Returns the seconds remaining until quick-match auto-start. nil if not a quick match.
    var quickMatchSecondsRemaining: Int? {
        guard isQuickMatchGame, let startedAt = quickMatchStartedAt else { return nil }
        let remaining = quickMatchAutoStartSeconds - Date().timeIntervalSince(startedAt)
        return max(0, Int(remaining.rounded(.up)))
    }

    /// Lightweight, decode-safe status check used by the lobby's invitee transition path.
    /// Returns the raw status string, or nil if the row can't be read.
    /// Also mirrors the result onto `currentGame.status` so the lobby UI / diagnostics
    /// reflect the live status even when RLS blocks the full row SELECT.
    func fetchCurrentGameStatus() async -> String? {
        guard let gameId = currentGameId else { return nil }
        let status = try? await service.fetchGameStatus(gameId: gameId)
        if let status {
            if var game = currentGame {
                game.status = status
                currentGame = game
            } else {
                currentGame = OnlineGame(
                    id: gameId,
                    hostId: "",
                    status: status,
                    gameData: nil,
                    currentTurnUserId: nil,
                    cardYear: nil,
                    createdAt: nil,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            }
        }
        return status
    }

    func loadLobby(gameId: String) async {
        currentGameId = gameId
        do {
            // RLS-tolerant: keep any previous currentGame value if the fetch returns nil
            // (RLS may block the SELECT for invitees) — broadcasts will fill it in later.
            if let game = try await service.fetchGame(gameId: gameId) {
                currentGame = game
            }
            let fetched = try await service.fetchParticipants(gameId: gameId)
            // Don't let an empty/partial fetch wipe out a list we already populated
            // via broadcasts (`joined`) or our own self-injection.
            if !fetched.isEmpty {
                currentParticipants = fetched
            }
            mergeSelfIntoParticipants()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            mergeSelfIntoParticipants()
        }
    }

    func refreshLobby() async {
        guard let gameId = currentGameId else { return }
        do {
            if let game = try await service.fetchGame(gameId: gameId) {
                currentGame = game
            }
            let fetched = try await service.fetchParticipants(gameId: gameId)
            if !fetched.isEmpty {
                currentParticipants = fetched
            }
            mergeSelfIntoParticipants()
            pendingInviteCountForCurrentGame = (try? await service.fetchPendingInviteCount(gameId: gameId)) ?? pendingInviteCountForCurrentGame
        } catch {
            print("⚠️ refreshLobby: \(error)")
            mergeSelfIntoParticipants()
        }
    }

    func inviteFriend(friendId: String) async {
        guard let gameId = currentGameId else { return }
        do {
            try await service.sendInvite(gameId: gameId, receiverId: friendId)
            await NotificationService.sendInvitePush(
                receiverId: friendId,
                gameId: gameId,
                senderName: myDisplayName.isEmpty ? "A friend" : myDisplayName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sends a game invite to a friend AND posts a chat message they can tap to accept.
    func inviteFriendWithChat(friendId: String, hostDisplayName: String) async {
        guard let gameId = currentGameId else { return }
        let cardYear = currentGame?.cardYear ?? "2025"
        do {
            try await service.sendInvite(gameId: gameId, receiverId: friendId)
            let payload = "__GAME_INVITE__|\(gameId)|\(cardYear)|\(hostDisplayName)"
            try await SupabaseService.shared.sendMessage(to: friendId, content: payload)
            sentInvitesCount += 1
            // Fire an APNs push so the invitee's device wakes up even if the
            // app is fully closed. Falls back gracefully to the in-app local
            // notification path if the edge function isn't deployed yet.
            await NotificationService.sendInvitePush(
                receiverId: friendId,
                gameId: gameId,
                senderName: hostDisplayName.isEmpty ? "A friend" : hostDisplayName
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Accepts a game invite that was received via chat. Joins the game and loads the lobby.
    func acceptGameInviteFromChat(gameId: String, displayName: String, avatarImage: String) async -> Bool {
        do {
            let invites = try await service.fetchMyInvites()
            if let invite = invites.first(where: { $0.gameId == gameId }), let inviteId = invite.id {
                try await service.respondToInvite(inviteId: inviteId, accept: true)
            }
            let participants = try await service.fetchParticipants(gameId: gameId)
            myDisplayName = displayName
            myAvatarImage = avatarImage
            var mySeat: Int? = participants.first(where: { $0.userId == myUserId })?.seatIndex
            if let myId = myUserId, !participants.contains(where: { $0.userId == myId }) {
                let seatIndex = (try? await service.nextAvailableSeat(gameId: gameId)) ?? 0
                try await service.joinGame(gameId: gameId, seatIndex: seatIndex, displayName: displayName, avatarImage: avatarImage)
                mySeat = seatIndex
            }
            await loadLobby(gameId: gameId)
            if let seat = mySeat { ensureSelfInParticipants(gameId: gameId, seatIndex: seat) }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func acceptInvite(_ invite: GameInvite, displayName: String, avatarImage: String) async {
        guard let inviteId = invite.id else { return }
        do {
            try await service.respondToInvite(inviteId: inviteId, accept: true)
            let seatIndex = try await service.nextAvailableSeat(gameId: invite.gameId)
            try await service.joinGame(gameId: invite.gameId, seatIndex: seatIndex, displayName: displayName, avatarImage: avatarImage)
            myDisplayName = displayName
            myAvatarImage = avatarImage
            // Pin the seat we joined so every later refresh can re-synthesize our row
            // even when RLS blocks the SELECT on `game_participants`.
            currentGameId = invite.gameId
            myKnownSeat = seatIndex
            ensureSelfInParticipants(gameId: invite.gameId, seatIndex: seatIndex)
            pendingInvites.removeAll { $0.id == inviteId }
            await loadActiveGames()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func declineInvite(_ invite: GameInvite) async {
        guard let inviteId = invite.id else { return }
        do {
            try await service.respondToInvite(inviteId: inviteId, accept: false)
            pendingInvites.removeAll { $0.id == inviteId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startOnlineGame(gameViewModel: GameViewModel) async {
        guard let gameId = currentGameId, isHost else { return }

        // Pull the freshest participant list so every accepted invitee that just
        // joined is included before the game state is created.
        currentParticipants = (try? await service.fetchParticipants(gameId: gameId)) ?? currentParticipants

        gameViewModel.isOnlineMode = true
        gameViewModel.onlineGameId = gameId
        // Host sits at East (seat 0).
        let hostSeat = currentParticipants.first(where: { $0.userId == myUserId })?.seatIndex ?? 0
        gameViewModel.localSeatIndex = hostSeat
        attachSyncHandler(to: gameViewModel)

        gameViewModel.startOnlineGame(participants: currentParticipants)
        rectifyBotFlags(gameViewModel)

        let state = gameViewModel.serializeState()
        let currentTurnUserId = userIdForPlayerIndex(gameViewModel.currentPlayerIndex)
        let status = gameViewModel.gameStatus == .charleston
            ? OnlineGameStatus.charleston.rawValue
            : OnlineGameStatus.playing.rawValue

        do {
            print("🚀 Host startOnlineGame: writing status=\(status) gameId=\(gameId) participants=\(currentParticipants.count) bots=\(Array(hostBotSeats).sorted())")
            try await service.updateGameState(gameId: gameId, gameData: state, currentTurnUserId: currentTurnUserId, status: status)
            // Push an instant realtime nudge so invitees jump into the Charleston without
            // waiting on postgres-changes replication or the lobby's polling timer.
            // CRITICAL: include the full serialized state + participants in the payload so
            // invitees can transition even when RLS blocks them from reading `online_games`.
            await broadcastGameStarted(gameId: gameId, status: status, state: state, participants: currentParticipants)
            print("🚀 Host startOnlineGame: broadcast sent, flipping showGameBoard")
            showGameBoard = true
        } catch {
            print("❌ Host startOnlineGame failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    /// Host: announce that the game has just started so every invitee in the lobby
    /// transitions to the game board immediately. Safe to no-op if the channel
    /// hasn't been subscribed yet (the postgres UPDATE will still drive the transition).
    private func broadcastGameStarted(gameId: String, status: String, state: SerializedGameState, participants: [GameParticipant]) async {
        guard let channel = realtimeChannel else { return }
        let payload = GameStartedPayload(gameId: gameId, status: status, state: state, participants: participants, cardYear: currentGame?.cardYear)
        do {
            try await channel.broadcast(event: "game_started", message: payload)
            // Send a few follow-up broadcasts so an invitee that subscribed slightly late
            // still receives the start event (broadcasts are not replayed on subscribe).
            for delayMs in [400, 1200, 3000] {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    guard let self, let channel = self.realtimeChannel else { return }
                    try? await channel.broadcast(event: "game_started", message: payload)
                }
            }
        } catch {
            print("⚠️ broadcastGameStarted: \(error)")
        }
    }

    /// Loads the live game state for an invitee. Returns true only if the full state
    /// (including non-nil gameData) was successfully applied. The caller can use the
    /// return value to decide whether to surface the game board or retry.
    @discardableResult
    func loadOnlineGameState(gameId: String, gameViewModel: GameViewModel) async -> Bool {
        do {
            guard let game = try await service.fetchGame(gameId: gameId) else { return false }
            let participants = try await service.fetchParticipants(gameId: gameId)
            guard let gameData = game.gameData else {
                // Status may have flipped before game_data replicated. Surface the latest
                // game/participants so observers update, but signal "not ready" so the
                // caller retries instead of presenting an empty board.
                currentGame = game
                currentGameId = gameId
                currentParticipants = participants
                return false
            }
            guard let myId = myUserId else { return false }

            let mySeat = participants.first(where: { $0.userId == myId })?.seatIndex ?? myKnownSeat ?? 0
            myKnownSeat = mySeat

            gameViewModel.isOnlineMode = true
            gameViewModel.onlineGameId = gameId
            gameViewModel.localSeatIndex = mySeat
            // Use freshly fetched participants for sanitization so we never strand
            // a late-joining invitee on a bot-flagged seat.
            if !participants.isEmpty { currentParticipants = participants }
            let sanitized = sanitizeStatePlayers(gameData)
            gameViewModel.restoreState(from: sanitized)
            rectifyBotFlags(gameViewModel)
            attachSyncHandler(to: gameViewModel)

            currentGame = game
            currentGameId = gameId
            if !participants.isEmpty { currentParticipants = participants }
            mergeSelfIntoParticipants()
            lastAppliedUpdatedAt = game.updatedAt ?? ""
            showGameBoard = true
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Invitee-side helper: keep retrying `loadOnlineGameState` until the full state
    /// (with non-nil game_data) is available, then flip `showGameBoard`. This is the
    /// race-proof path the lobby relies on once the host kicks off the Charleston —
    /// it survives postgres replication lag, broadcast-before-write, and decode hiccups.
    func loadOnlineGameStateWithRetry(gameId: String, gameViewModel: GameViewModel, maxAttempts: Int = 20) async -> Bool {
        for attempt in 0..<maxAttempts {
            let ok = await loadOnlineGameState(gameId: gameId, gameViewModel: gameViewModel)
            if ok { return true }
            // Exponential-ish backoff capped at ~750ms; total budget ~10s for 20 tries.
            let delayMs = min(750, 150 + attempt * 50)
            try? await Task.sleep(for: .milliseconds(delayMs))
        }
        return false
    }

    func syncAfterMove(gameViewModel: GameViewModel) async {
        guard let gameId = currentGameId else { return }
        // During Charleston, every seat submits its own pass concurrently. To prevent
        // simultaneous writes from clobbering one another, non-host clients fetch the
        // freshest server state and merge in only their own hand & pending-pass entry.
        if gameViewModel.gameStatus == .charleston && !isHost {
            await submitCharlestonPassMerged(gameViewModel: gameViewModel)
            startCharlestonPassHeartbeat(gameViewModel: gameViewModel)
            return
        }
        // Host's Charleston writes also need to merge — otherwise a host write that races
        // with a non-host's submission will overwrite the non-host's pending pass on the
        // server, leaving the host blind to it and stalling the phase.
        if gameViewModel.gameStatus == .charleston && isHost {
            await submitCharlestonPassMergedHost(gameViewModel: gameViewModel)
            startCharlestonHostHeartbeat(gameViewModel: gameViewModel)
            return
        }
        // Non-charleston move: stop any lingering charleston heartbeats and
        // make sure the play-phase heartbeats are running so dropped broadcasts
        // self-heal.
        stopCharlestonHeartbeats()
        if gameViewModel.gameStatus == .playing && !gameViewModel.showEndGameOverlay {
            if isHost {
                ensurePlayPhaseHostHeartbeat(gameViewModel: gameViewModel)
            } else {
                ensurePlayPhaseInviteePull(gameViewModel: gameViewModel)
            }
        }

        let state = gameViewModel.serializeState()
        let currentTurnUserId = userIdForPlayerIndex(gameViewModel.currentPlayerIndex)
        let status: String
        switch gameViewModel.gameStatus {
        case .charleston: status = OnlineGameStatus.charleston.rawValue
        case .playing: status = OnlineGameStatus.playing.rawValue
        case .completed: status = OnlineGameStatus.completed.rawValue
        default: status = OnlineGameStatus.playing.rawValue
        }

        // CRITICAL: "absorb if server is ahead" guard for play-phase syncs.
        // Mirrors the charleston-side guard. If a remote client has already advanced
        // the turn past us (their discard/draw/call landed first while ours was in
        // flight) — or the game has already completed — we must NOT write our stale
        // local state back. Doing so rolls the DB row back, strands every other
        // client, and freezes the turn (the exact race that hung the host on the 2nd
        // Charleston left and the invitee on the 1st left in the prior incident).
        // Instead, absorb the newer server snapshot and bail.
        if let serverGame = try? await service.fetchGame(gameId: gameId),
           let serverData = serverGame.gameData {
            let localDiscardCount = state.discardPile.count
            let serverDiscardCount = serverData.discardPile.count
            let serverCompletedAhead =
                serverData.gameStatus == OnlineGameStatus.completed.rawValue
                && status != OnlineGameStatus.completed.rawValue
            // Server moved on from charleston while we're still trying to write a
            // play-phase move (shouldn't normally happen, but covers the edge case
            // where a buffered move fires after a remote phase change).
            let serverPlayingWhileLocalCharleston =
                serverData.gameStatus == OnlineGameStatus.playing.rawValue
                && status == OnlineGameStatus.charleston.rawValue
            // Strictly greater — equal counts mean we're current (our just-made move
            // matches what the server already has, or we're racing harmlessly).
            var serverDiscardAhead = serverDiscardCount > localDiscardCount

            // CRITICAL CARVE-OUT — non-host caller mid-exposure.
            // When an invitee calls a pung/kong/quint, they remove the called tile
            // from the discard pile and append the new exposed set BEFORE the
            // follow-up discard happens. Their local discardPile is therefore
            // exactly server-1. Without this carve-out, syncAfterMove sees
            // `serverDiscardAhead = true`, absorbs the older server snapshot, and
            // wipes the caller's exposure — exactly the "tiles snap back to the
            // rack, game freezes asking to draw" symptom users reported. Detect:
            // our local discards are server-1, the missing tile is in our newest
            // exposedSet, and we now own the turn pointer (executeCall/confirm set
            // currentPlayerIndex to us, hasDrawnThisTurn=true).
            if serverDiscardAhead, serverDiscardCount == localDiscardCount + 1 {
                let mySeat = gameViewModel.localSeatIndex
                let localExposedCount = (mySeat < state.players.count) ? state.players[mySeat].exposedSets.count : 0
                let serverExposedCount = (mySeat < serverData.players.count) ? serverData.players[mySeat].exposedSets.count : 0
                if localExposedCount > serverExposedCount,
                   mySeat < state.players.count,
                   let newSet = state.players[mySeat].exposedSets.last {
                    let localIds = Set(state.discardPile.map { $0.id })
                    let missingFromLocal = serverData.discardPile.map { $0.id }.filter { !localIds.contains($0) }
                    if newSet.contains(where: { missingFromLocal.contains($0.id) }),
                       state.currentPlayerIndex == mySeat,
                       state.hasDrawnThisTurn {
                        print("✅ syncAfterMove: local state is a fresh caller-exposure (server discards=\(serverDiscardCount) local=\(localDiscardCount)) — pushing instead of absorbing")
                        serverDiscardAhead = false
                    }
                }
            }

            if serverCompletedAhead || serverPlayingWhileLocalCharleston || serverDiscardAhead {
                print("⏩ syncAfterMove: server already ahead (serverStatus=\(serverData.gameStatus) serverDiscards=\(serverDiscardCount) localDiscards=\(localDiscardCount) localStatus=\(status)) — absorbing newer state, skipping write")
                gameViewModel.applyRemoteState(serverData)
                // Re-broadcast the absorbed state so any other client that's also
                // behind catches up off our broadcast (RLS-proof path).
                await broadcastStateUpdate(
                    gameId: gameId,
                    status: serverData.gameStatus,
                    state: serverData,
                    senderSeat: gameViewModel.localSeatIndex
                )
                return
            }
        }

        pendingLocalSync = true
        do {
            try await service.updateGameState(gameId: gameId, gameData: state, currentTurnUserId: currentTurnUserId, status: status)
            await broadcastStateUpdate(gameId: gameId, status: status, state: state, senderSeat: gameViewModel.localSeatIndex)
            if status == OnlineGameStatus.completed.rawValue {
                // Game just finished — sweep both the play-phase action log and any
                // charleston_passes rows still lingering (e.g. from an earlier retry
                // that eventually gave up). Detached and best-effort: cleanup failing
                // must never block the end-game UI. Safe to call from every client
                // that reaches this write, since delete is idempotent.
                Task.detached {
                    await OnlineGameService.shared.deleteGameActions(gameId: gameId)
                    await OnlineGameService.shared.deleteCharlestonPasses(gameId: gameId, throughPhase: Int.max)
                }
            }
        } catch {
            print("⚠️ syncAfterMove: \(error)")
        }
        pendingLocalSync = false

        // Option B: durable wake-up signal. Even if both the postgres UPDATE
        // replication and the realtime broadcast above are dropped on a peer,
        // this small append-only INSERT will fan out via postgres_changes and
        // cause every other seat to pull the latest state. Fire-and-forget;
        // failures are non-fatal because the broadcast remains the fast path.
        if status != OnlineGameStatus.waiting.rawValue {
            let actionKind: String
            switch gameViewModel.gameStatus {
            case .charleston: actionKind = "charleston_state"
            case .completed:  actionKind = "completed"
            default:          actionKind = "play_state"
            }
            let seat = gameViewModel.localSeatIndex
            let discardCount = state.discardPile.count
            let currentTurn = state.currentPlayerIndex
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.service.insertGameAction(
                        gameId: gameId,
                        seat: seat,
                        kind: actionKind,
                        discardCount: discardCount,
                        currentTurn: currentTurn
                    )
                } catch {
                    print("⚠️ insertGameAction (\(actionKind)) failed: \(error)")
                }
            }
        }

        // Belt-and-suspenders: re-broadcast a couple of times so a single dropped
        // packet in the playing phase can't freeze the table. Charleston already does
        // this; without it, a play-phase discard whose broadcast is lost strands the
        // host on the previous turn and the game appears frozen.
        let capturedSeat = gameViewModel.localSeatIndex
        let capturedDiscardId = gameViewModel.lastDiscardedTile?.id
        let capturedTurn = gameViewModel.currentPlayerIndex
        for delayMs in [600, 1800] {
            Task { @MainActor [weak self, weak gameViewModel] in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard let self, let gameViewModel else { return }
                // Only re-broadcast if our local state still represents the same move —
                // don't push stale state on top of a newer remote update we just absorbed.
                guard gameViewModel.gameStatus != .charleston,
                      gameViewModel.lastDiscardedTile?.id == capturedDiscardId,
                      gameViewModel.currentPlayerIndex == capturedTurn else { return }
                let freshState = gameViewModel.serializeState()
                await self.broadcastStateUpdate(
                    gameId: gameId,
                    status: status,
                    state: freshState,
                    senderSeat: capturedSeat
                )
            }
        }
    }

    /// Broadcast the latest serialized state to every connected client. This is the
    /// belt-and-suspenders path for invitees whose RLS may block the postgres UPDATE
    /// stream — without this, a non-host whose SELECT is blocked never sees the host's
    /// merged Charleston state and stalls showing only their own pending pass.
    private func broadcastStateUpdate(gameId: String, status: String, state: SerializedGameState, senderSeat: Int) async {
        guard let channel = realtimeChannel else {
            print("⚠️ broadcastStateUpdate skipped: no realtime channel (seat=\(senderSeat))")
            return
        }
        let payload = StateUpdatePayload(gameId: gameId, status: status, state: state, senderSeat: senderSeat)
        do {
            try await channel.broadcast(event: "state_update", message: payload)
            print("📡 broadcastStateUpdate sent seat=\(senderSeat) status=\(status) phase=\(state.charlestonPhase) pending=\(state.charlestonPendingPasses?.keys.sorted() ?? [])")
        } catch {
            print("⚠️ broadcastStateUpdate: \(error)")
        }
    }

    /// See `HeartbeatPingPayload`. Sends just `{gameId, senderSeat}` — no wall,
    /// hands, discard pile, or anything else — so the routine play-phase
    /// heartbeat tick doesn't pay full serialize/broadcast/decode/merge cost
    /// when nothing has actually changed since the last real move.
    private func broadcastHeartbeatPing(gameId: String, senderSeat: Int) async {
        guard let channel = realtimeChannel else { return }
        let payload = HeartbeatPingPayload(gameId: gameId, senderSeat: senderSeat)
        do {
            try await channel.broadcast(event: "heartbeat_ping", message: payload)
        } catch {
            print("⚠️ broadcastHeartbeatPing: \(error)")
        }
    }

    /// Host Charleston sync. Writes the host's full state but UNIONs the server's
    /// `charlestonPendingPasses` with the host's own — so a concurrent invitee write
    /// that landed after the host's last fetch is preserved (the host will pick up that
    /// invitee's pass on the next realtime update and finalize the exchange).
    private func submitCharlestonPassMergedHost(gameViewModel: GameViewModel) async {
        guard let gameId = currentGameId else { return }
        pendingLocalSync = true
        defer { pendingLocalSync = false }
        var state = gameViewModel.serializeState()
        do {
            if let game = try await service.fetchGame(gameId: gameId),
               let serverData = game.gameData,
               serverData.gameStatus == OnlineGameStatus.charleston.rawValue,
               serverData.charlestonPhase == state.charlestonPhase,
               let serverPending = serverData.charlestonPendingPasses {
                var merged = state.charlestonPendingPasses ?? [:]
                for (seatKey, tiles) in serverPending where merged[seatKey] == nil {
                    merged[seatKey] = tiles
                    // Preserve that seat's hand from the server snapshot too, so the
                    // post-exchange math stays consistent.
                    if let seat = Int(seatKey),
                       seat < state.players.count,
                       seat < serverData.players.count {
                        state.players[seat].hand = serverData.players[seat].hand
                    }
                }
                state.charlestonPendingPasses = merged
            }
            let currentTurnUserId = userIdForPlayerIndex(gameViewModel.currentPlayerIndex)
            try await service.updateGameState(
                gameId: gameId,
                gameData: state,
                currentTurnUserId: currentTurnUserId,
                status: OnlineGameStatus.charleston.rawValue
            )
            await broadcastStateUpdate(
                gameId: gameId,
                status: OnlineGameStatus.charleston.rawValue,
                state: state,
                senderSeat: gameViewModel.localSeatIndex
            )
            // Lightweight redundant signal of the host's own pass too — invitees
            // can pick up the host's pass even when full state echoes get lost.
            await broadcastCharlestonPass(gameViewModel: gameViewModel)
            // RLS-PROOF PHASE-ADVANCE SIDE-CHANNEL. Upsert the host's own seat
            // (and any bot seats it controls) into `charleston_passes` for the
            // current phase. The non-host invitee pull task uses the highest
            // phase in this table as its phase-advance detector — without
            // host-side rows, a phase like 3 (host + bots) has zero rows in
            // the table even though the host has long advanced, and the
            // invitee never escapes a stale pending pass at the previous
            // phase. Best-effort; a write failure is non-fatal.
            await uploadHostControlledPasses(gameViewModel: gameViewModel)
            // Option B durable wake-up: append a `game_actions` row so an
            // invitee whose state_update broadcast was dropped still gets a
            // postgres_changes insert event and pulls the new phase state.
            // Fire-and-forget; failures are non-fatal.
            let actionSeat = gameViewModel.localSeatIndex
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.service.insertGameAction(
                        gameId: gameId,
                        seat: actionSeat,
                        kind: "charleston_state",
                        discardCount: 0,
                        currentTurn: gameViewModel.currentPlayerIndex
                    )
                } catch {
                    print("⚠️ insertGameAction (charleston host) failed: \(error)")
                }
            }
            // BOUNDARY RETRY BURST. Phase-advance broadcasts (e.g. secondRight -> courtesy)
            // are uniquely fragile: there's exactly one moment when the new phase is
            // announced, and if that single packet is dropped the invitee sits forever on
            // the "Tiles passed" waiting screen because their local pendingPass for the
            // OLD phase keeps `hasSubmittedCharlestonPass` true. Send 3 follow-up
            // broadcasts AND re-write the DB row so even a flaky realtime delivery and a
            // slow DB replication can both be tolerated. Guarded so we don't replay a
            // stale snapshot if the host has already moved on (e.g. East skipped courtesy).
            let capturedPhase = state.charlestonPhase
            let capturedStatus = state.gameStatus
            // Drop the long 2500ms tail — the 350/1100ms retries already cover
            // realtime hiccups, and the trailing task lingers across phase
            // boundaries adding latency to the next pass with no real benefit.
            for delayMs in [200, 600, 1400] {
                Task { @MainActor [weak self, weak gameViewModel] in
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    guard let self, let gameViewModel else { return }
                    let stillSamePhase = gameViewModel.gameStatus == .charleston
                        && gameViewModel.charlestonPhase.rawValue == capturedPhase
                    let advancedToPlay = capturedStatus == OnlineGameStatus.charleston.rawValue
                        && gameViewModel.gameStatus == .playing
                    guard stillSamePhase || advancedToPlay else { return }
                    let freshState = gameViewModel.serializeState()
                    let freshStatus: String
                    switch gameViewModel.gameStatus {
                    case .playing: freshStatus = OnlineGameStatus.playing.rawValue
                    case .completed: freshStatus = OnlineGameStatus.completed.rawValue
                    default: freshStatus = OnlineGameStatus.charleston.rawValue
                    }
                    await self.broadcastStateUpdate(
                        gameId: gameId,
                        status: freshStatus,
                        state: freshState,
                        senderSeat: gameViewModel.localSeatIndex
                    )
                }
            }
        } catch {
            print("⚠️ submitCharlestonPassMergedHost: \(error)")
        }
    }

    /// Non-host Charleston submit. Tries to fetch the latest server state and merge
    /// only this seat's hand + pending-pass entry on top — so other players' concurrent
    /// submissions are never overwritten.
    /// CRITICAL: if the server read fails or returns no `game_data` (RLS, replication
    /// lag, transient error), we MUST still broadcast our pass — otherwise the host
    /// will never see it and Charleston stalls. The realtime broadcast path is
    /// RLS-proof and is what the host actually depends on.
    func submitCharlestonPassMerged(gameViewModel: GameViewModel) async {
        guard let gameId = currentGameId else { return }
        let mySeat = gameViewModel.localSeatIndex
        guard mySeat >= 0, mySeat < gameViewModel.players.count else { return }
        pendingLocalSync = true
        defer { pendingLocalSync = false }

        // FAST PATH — broadcast our local state immediately so the host sees our
        // pass within a single network hop (was ~3 hops: fetch → write → broadcast).
        // The host's applyRemoteState preserves other seats' pending passes via
        // priorPendingPasses, so this won't clobber concurrent submissions. The
        // merged DB write below is still issued as a durability safety net.
        let immediateState = gameViewModel.serializeState()
        await broadcastStateUpdate(
            gameId: gameId,
            status: OnlineGameStatus.charleston.rawValue,
            state: immediateState,
            senderSeat: mySeat
        )
        // Also send the lightweight charleston_pass broadcast. Its small payload
        // is much more likely to land than the full state_update when the
        // realtime channel is silently dropping packets in our->host direction.
        await broadcastCharlestonPass(gameViewModel: gameViewModel)

        // SERVER-SIDE ATOMIC MERGE. Routes our pass through the
        // `submit-charleston-pass` edge function (service-role privileges) so
        // RLS can never block our write AND the cross-client read-modify-write
        // race that would let another client clobber our seat's entry can
        // never occur. This is the single most reliable recovery path —
        // independent of realtime broadcast delivery and per-client RLS.
        if let myPass = gameViewModel.charlestonPendingPasses[mySeat] {
            do {
                try await service.submitCharlestonPassViaEdge(
                    gameId: gameId,
                    seat: mySeat,
                    phase: gameViewModel.charlestonPhase.rawValue,
                    tiles: myPass,
                    handAfter: gameViewModel.players[mySeat].hand
                )
                print("\u{1F310} submit-charleston-pass edge OK seat=\(mySeat) phase=\(gameViewModel.charlestonPhase.rawValue)")
            } catch {
                print("\u{26A0}\u{FE0F} submit-charleston-pass edge failed (non-fatal): \(error)")
            }
        }

        // Start from the server snapshot when we can read it; fall back to our own
        // local state so an RLS-blocked SELECT or replication race can't swallow the pass.
        var data: SerializedGameState
        var hasServerSnapshot = false
        // CRITICAL: track whether we got ANY server response (even an empty row).
        // If the SELECT is RLS-blocked or the network is flaky, we MUST NOT write
        // our local stale state to the DB — otherwise an invitee that hasn't
        // observed the host's newer phase silently rolls the DB row back,
        // stranding the host (its `pullAndMergeCharlestonFromDB` then refuses to
        // merge a server row whose phase trails its own). The original symptom:
        // host on 1st Across, invitee on 1st Right, neither ever progresses.
        var serverFetchSucceeded = false
        let serverGame = try? await service.fetchGame(gameId: gameId)
        if serverGame != nil { serverFetchSucceeded = true }
        if let serverData = serverGame?.gameData {
            // CRITICAL: if the server has already MOVED PAST our local Charleston phase
            // (host advanced after a finalize) — or has already left Charleston entirely —
            // we must NOT write our stale local state back. Doing so rolls the DB row
            // back to the previous phase and strands every other client. Instead, absorb
            // the newer server snapshot, drop our now-stale pending pass, and bail.
            let serverIsPlaying = serverData.gameStatus == OnlineGameStatus.playing.rawValue
            let serverCharlestonAhead = serverData.gameStatus == OnlineGameStatus.charleston.rawValue
                && serverData.charlestonPhase > gameViewModel.charlestonPhase.rawValue
            if serverIsPlaying || serverCharlestonAhead {
                print("⏩ submitCharlestonPassMerged: server already ahead (status=\(serverData.gameStatus) phase=\(serverData.charlestonPhase) local=\(gameViewModel.charlestonPhase.rawValue)) — absorbing newer state, skipping write")
                gameViewModel.applyRemoteState(serverData)
                // Re-broadcast the absorbed state so any other client that's also behind
                // catches up off our broadcast (RLS-proof path).
                await broadcastStateUpdate(
                    gameId: gameId,
                    status: serverData.gameStatus,
                    state: serverData,
                    senderSeat: mySeat
                )
                return
            }
            if serverData.gameStatus == OnlineGameStatus.charleston.rawValue,
               serverData.charlestonPhase == gameViewModel.charlestonPhase.rawValue {
                data = serverData
                hasServerSnapshot = true
            } else {
                data = gameViewModel.serializeState()
                print("📤 submitCharlestonPassMerged: server snapshot phase=\(serverData.charlestonPhase) status=\(serverData.gameStatus) doesn't match local phase=\(gameViewModel.charlestonPhase.rawValue), using local")
            }
        } else {
            data = gameViewModel.serializeState()
            print("📤 submitCharlestonPassMerged: no server snapshot available, falling back to local state for seat=\(mySeat)")
        }

        // Overwrite only this seat's hand on top of the server snapshot.
        if mySeat < data.players.count {
            data.players[mySeat].hand = gameViewModel.players[mySeat].hand
        }
        // Merge in this seat's pending pass (preserving everyone else's).
        var pending = data.charlestonPendingPasses ?? [:]
        if let myPass = gameViewModel.charlestonPendingPasses[mySeat] {
            pending[String(mySeat)] = myPass
        }
        data.charlestonPendingPasses = pending

        // Best-effort DB write. Failures here are non-fatal because the broadcast
        // is also issued — but the DB write is the critical recovery path when
        // the realtime channel is silently dead.
        //
        // PREVIOUS GUARD (too conservative): skipped the write whenever we
        // didn't have a same-phase server snapshot. That stranded the invitee's
        // pass entirely when SELECT was RLS-blocked AND broadcasts were
        // silently dropped — the exact 60s-stuck-after-1st-pass-right symptom
        // from diagnostics (host pending=[0,2,3], invitee pending=[1,2,3],
        // neither converging because the invitee's [1] existed nowhere except
        // in lost broadcasts).
        //
        // NEW POLICY: always write. Rollback risk is bounded — if the server
        // was already AHEAD we absorbed and bailed earlier; otherwise our
        // local state is at-least-as-fresh as the row, and the host's
        // `pullAndMergeCharlestonFromDB` heartbeat re-asserts host truth
        // every 3s while preserving its own pending-pass map.
        do {
            try await service.updateGameState(
                gameId: gameId,
                gameData: data,
                currentTurnUserId: nil,
                status: OnlineGameStatus.charleston.rawValue
            )
            print("📤 submitCharlestonPassMerged: DB write OK seat=\(mySeat) hadServerSnapshot=\(hasServerSnapshot) pending=\(pending.keys.sorted())")
        } catch {
            print("⚠️ submitCharlestonPassMerged DB write failed (relying on broadcast): \(error)")
        }

        // Always broadcast — this is the RLS-proof path the host depends on.
        await broadcastStateUpdate(
            gameId: gameId,
            status: OnlineGameStatus.charleston.rawValue,
            state: data,
            senderSeat: mySeat
        )
        // Option B durable wake-up so the host pulls our pass even if every
        // realtime path silently drops in our->host direction.
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.insertGameAction(
                    gameId: gameId,
                    seat: mySeat,
                    kind: "charleston_state",
                    discardCount: 0,
                    currentTurn: gameViewModel.currentPlayerIndex
                )
            } catch {
                print("⚠️ insertGameAction (charleston invitee) failed: \(error)")
            }
        }
        // Send a couple of follow-up broadcasts so a momentarily-disconnected host
        // (e.g. mid-reconnect) can still receive our pass on the next attempt.
        // CRITICAL: only re-broadcast if our local game state is STILL on the same
        // Charleston phase. Otherwise the host has already finalized the exchange and
        // a stale re-broadcast would roll everyone back to the previous phase.
        let capturedPhase = data.charlestonPhase
        for delayMs in [400, 1200] {
            Task { @MainActor [weak self, weak gameViewModel] in
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard let self, let gameViewModel else { return }
                guard gameViewModel.gameStatus == .charleston,
                      gameViewModel.charlestonPhase.rawValue == capturedPhase else {
                    print("⏪ skipping stale charleston re-broadcast (capturedPhase=\(capturedPhase) currentPhase=\(gameViewModel.charlestonPhase.rawValue) status=\(gameViewModel.gameStatus))")
                    return
                }
                await self.broadcastStateUpdate(
                    gameId: gameId,
                    status: OnlineGameStatus.charleston.rawValue,
                    state: data,
                    senderSeat: mySeat
                )
            }
        }
    }

    /// Host: while in charleston, periodically re-broadcast the latest state so invitees
    /// always see the current pending-pass map even if intermediate broadcasts were lost.
    ///
    /// CRITICAL: this heartbeat is ALSO the host's recovery path for invitee passes that
    /// arrived via DB write but whose realtime broadcast was lost. If realtime is silently
    /// broken in one direction (Supabase channel claims "connected" but no inbound packets),
    /// the only way the host learns about the invitee's pending pass is by fetching the
    /// row directly. So every few ticks we pull from the DB and merge in any peer entries
    /// our local map is missing.
    private func startCharlestonHostHeartbeat(gameViewModel: GameViewModel) {
        charlestonHeartbeatTask?.cancel()
        charlestonHeartbeatTask = Task { @MainActor [weak self, weak gameViewModel] in
            var tick = 0
            // Watchdog timers are now PERSISTED on the VM (charlestonIncompleteSince
            // etc.) so a self-initiated forceReconnect — which cancels and re-arms
            // this very task — can't keep resetting the clock and indefinitely
            // defer the force-finalize escape hatch. Without that fix, the host
            // sat stuck on the 1st across pass (and similar) because every 10s the
            // reconnect tier would restart the heartbeat with a fresh nil timer.
            while !Task.isCancelled {
                // Widened from 600ms now that the online_games RLS self-join bug is
                // fixed (see migration fix_online_games_rls_self_join_bug) — the direct
                // postgres_changes subscription on online_games actually delivers to
                // invitees now, so this heartbeat is a safety net, not the primary path.
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                guard let self, let gameViewModel else { break }
                guard self.isHost,
                      let gameId = self.currentGameId,
                      gameViewModel.gameStatus == .charleston else { break }
                let state = gameViewModel.serializeState()
                await self.broadcastStateUpdate(
                    gameId: gameId,
                    status: OnlineGameStatus.charleston.rawValue,
                    state: state,
                    senderSeat: gameViewModel.localSeatIndex
                )
                // Lightweight redundant signal so invitees pick up the host's own
                // pending pass even when state_update echoes are silently dropped.
                await self.broadcastCharlestonPass(gameViewModel: gameViewModel)
                // Keep the RLS-proof phase-advance signal fresh in `charleston_passes`
                // for the host's seat + any bot seats. Without periodic upserts, an
                // invitee whose host->invitee channel is silently dead can't observe
                // the phase advance and stays stuck at the previous phase forever.
                await self.uploadHostControlledPasses(gameViewModel: gameViewModel)
                let pendingCount = gameViewModel.charlestonPendingPasses.count
                let isIncomplete = pendingCount < gameViewModel.players.count
                let currentPhase = gameViewModel.charlestonPhase.rawValue
                if self.charlestonIncompletePhase != currentPhase {
                    // Phase advanced (or first observation) — reset the watchdog clock.
                    self.charlestonIncompletePhase = currentPhase
                    self.charlestonIncompleteSince = nil
                }
                if isIncomplete {
                    // Realtime nudge — every peer with state re-broadcasts on receipt.
                    await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)
                    if self.charlestonIncompleteSince == nil { self.charlestonIncompleteSince = Date() }
                    // TARGETED PASS REQUEST. Once we've been stuck for a few seconds,
                    // explicitly ask each missing human seat to re-push their pass.
                    // This is the recovery path that finally breaks the deadlock when
                    // realtime is silently dead in the invitee→host direction so neither
                    // their broadcast nor the surgical DB merge ever recovers their pass.
                    if let since = self.charlestonIncompleteSince,
                       Date().timeIntervalSince(since) > 4 {
                        let missingHumans: [Int] = (0..<gameViewModel.players.count).filter { i in
                            !gameViewModel.players[i].isBot
                                && gameViewModel.charlestonPendingPasses[i] == nil
                                && i != gameViewModel.localSeatIndex
                        }
                        if !missingHumans.isEmpty {
                            await self.broadcastRequestPendingPass(
                                missingSeats: missingHumans,
                                phase: currentPhase
                            )
                        }
                    }
                } else {
                    self.charlestonIncompleteSince = nil
                }
                // RLS / dead-socket recovery: ~every 3s while still incomplete, pull
                // from DB and merge any peer pending passes we're missing locally.
                // This is what lets the host pick up an invitee's pass when their
                // broadcasts never reach us — without it the Charleston stalls forever.
                tick += 1
                if isIncomplete && tick % 5 == 0 {
                    await self.pullAndMergeCharlestonFromDB(gameViewModel: gameViewModel, gameId: gameId)
                }
                // FORCE-RECONNECT TIER. If the pending map has been incomplete
                // for too long and we haven't rebuilt the channel recently,
                // tear down and re-subscribe. A Supabase channel can report
                // "connected" while silently dropping inbound packets in one
                // direction; rebuilding is the only way to recover. Pre-
                // courtesy passes are bot-fast and should never sit incomplete
                // for long, so use a tighter threshold there.
                let reconnectThreshold: TimeInterval = gameViewModel.charlestonPhase.isCourtesy ? 14 : 8
                if let since = self.charlestonIncompleteSince,
                   Date().timeIntervalSince(since) > reconnectThreshold,
                   Date().timeIntervalSince(self.charlestonLastReconnectAt) > 20 {
                    print("⚠️ charleston host heartbeat: incomplete \(Int(Date().timeIntervalSince(since)))s during \(gameViewModel.charlestonPhase.displayName) pending=\(gameViewModel.charlestonPendingPasses.keys.sorted()) — rebuilding realtime channel")
                    self.charlestonLastReconnectAt = Date()
                    // Do NOT reset charlestonIncompleteSince here — the force-finalize
                    // escape hatch must keep counting toward its threshold so a single
                    // failed reconnect can't postpone recovery indefinitely.
                    self.forceReconnect(gameViewModel: gameViewModel)
                }
                // FINAL ESCAPE HATCH. If reconnects + DB pulls have failed for
                // long enough that the table has clearly been frozen (>25s for
                // pre-courtesy, >35s for courtesy where humans pace it), the
                // missing seat's pass is unreachable for now — auto-pick tiles
                // on their behalf and advance the phase. Better to keep the
                // game moving than to freeze indefinitely. Throttled so we
                // don't double-fire while waiting for the broadcast to land.
                // Pre-courtesy phases are bot-fast (no humans pacing them on host's
                // side except the host's own pick), so a long stall is almost always
                // a silently-dead realtime path; recover quickly. Courtesy is paced
                // by humans picking their tile counts, so allow more breathing room.
                let forceThreshold: TimeInterval = gameViewModel.charlestonPhase.isCourtesy ? 30 : 12
                if let since = self.charlestonIncompleteSince,
                   Date().timeIntervalSince(since) > forceThreshold,
                   Date().timeIntervalSince(self.charlestonLastForceFinalizeAt) > 20 {
                    self.charlestonLastForceFinalizeAt = Date()
                    self.charlestonIncompleteSince = Date()
                    let phaseLabel = gameViewModel.charlestonPhase.displayName
                    let didProgress = gameViewModel.forceFinalizeStuckCharleston(reason: "host heartbeat \(Int(Date().timeIntervalSince(since)))s on \(phaseLabel)")
                    if didProgress {
                        // Push the post-finalize state immediately so invitees
                        // see the new phase / playing status without waiting
                        // for the next regular tick.
                        let freshState = gameViewModel.serializeState()
                        let freshStatus: String
                        switch gameViewModel.gameStatus {
                        case .playing: freshStatus = OnlineGameStatus.playing.rawValue
                        case .completed: freshStatus = OnlineGameStatus.completed.rawValue
                        default: freshStatus = OnlineGameStatus.charleston.rawValue
                        }
                        await self.broadcastStateUpdate(
                            gameId: gameId,
                            status: freshStatus,
                            state: freshState,
                            senderSeat: gameViewModel.localSeatIndex
                        )
                    }
                }
            }
        }
    }

    /// Host-only safety net. Fetches the latest `online_games` row directly, merges any
    /// peer pending-pass entries our local map is missing, and finalizes the Charleston
    /// exchange if everyone has now submitted. Used by the host heartbeat to recover from
    /// a silently-dead realtime channel (channel reports "connected" but no broadcasts
    /// are actually being delivered — the exact symptom in the stuck-Charleston diagnostics).
    private func pullAndMergeCharlestonFromDB(gameViewModel: GameViewModel, gameId: String) async {
        guard isHost, gameViewModel.gameStatus == .charleston else { return }
        let phaseNow = gameViewModel.charlestonPhase.rawValue

        // PRIMARY PATH — dedicated `charleston_passes` table.
        // Run this FIRST and UNCONDITIONALLY for the host's current local phase,
        // independent of whatever stale `online_games.game_data` snapshot we may
        // pull next. Each seat UPSERTs their own row, so the dedicated table is
        // the authoritative source for missing passes — gating it behind a
        // gameData phase match is what caused the host to keep missing the
        // invitee's pass at the 1st Left boundary (DB row's gameData was rolled
        // back to phase 1 by an invitee write while host had already advanced
        // to phase 2; the early-return below skipped the dedicated table pull).
        var injectedFromTable = false
        do {
            let passRows = try await service.fetchCharlestonPasses(gameId: gameId, phase: phaseNow)
            print("🔎 pullAndMergeCharlestonFromDB: charleston_passes phase=\(phaseNow) returned \(passRows.count) row(s) — seats=\(passRows.map(\.seatIndex).sorted())")
            for row in passRows {
                let seat = row.seatIndex
                guard seat >= 0, seat < gameViewModel.players.count,
                      gameViewModel.charlestonPendingPasses[seat] == nil else { continue }
                gameViewModel.charlestonPendingPasses[seat] = row.tiles
                gameViewModel.players[seat].hand = row.handAfter
                injectedFromTable = true
                print("\u{1F504} pullAndMergeCharlestonFromDB: injected pending pass for seat \(seat) from charleston_passes table")
            }
        } catch {
            print("⚠️ pullAndMergeCharlestonFromDB: fetchCharlestonPasses failed: \(error)")
        }

        // If the table pull alone produced a complete map, finalize immediately
        // and skip the gameData merge below (it can't add anything we don't
        // already have, and a stale snapshot might fight our progress).
        if injectedFromTable,
           (0..<gameViewModel.players.count).allSatisfy({ gameViewModel.charlestonPendingPasses[$0] != nil }) {
            gameViewModel.tryFinalizeCharlestonPass()
            return
        }

        do {
            guard let game = try await service.fetchGame(gameId: gameId),
                  let serverData = game.gameData else {
                if injectedFromTable { gameViewModel.tryFinalizeCharlestonPass() }
                return
            }
            // SOURCE-OF-TRUTH RECOVERY. If the DB row trails our local Charleston
            // phase (an invitee with a silently-dead inbound realtime channel
            // wrote their stale phase back over our newer write), forcibly
            // re-write our current state so the row matches the host again.
            let serverIsCharleston = serverData.gameStatus == OnlineGameStatus.charleston.rawValue
            let serverIsBehind = serverIsCharleston && serverData.charlestonPhase < gameViewModel.charlestonPhase.rawValue
            let serverIsWaiting = serverData.gameStatus == OnlineGameStatus.waiting.rawValue
            let serverIsPlayingButLocalCharleston = serverData.gameStatus == OnlineGameStatus.playing.rawValue
                && gameViewModel.gameStatus == .charleston
            if serverIsBehind || serverIsWaiting || serverIsPlayingButLocalCharleston {
                print("🛟 pullAndMergeCharlestonFromDB: DB trails local (server phase=\(serverData.charlestonPhase) status=\(serverData.gameStatus), local phase=\(gameViewModel.charlestonPhase.rawValue)) — re-writing host state to restore source of truth")
                let freshState = gameViewModel.serializeState()
                let currentTurnUserId = userIdForPlayerIndex(gameViewModel.currentPlayerIndex)
                try? await service.updateGameState(
                    gameId: gameId,
                    gameData: freshState,
                    currentTurnUserId: currentTurnUserId,
                    status: OnlineGameStatus.charleston.rawValue
                )
                await broadcastStateUpdate(
                    gameId: gameId,
                    status: OnlineGameStatus.charleston.rawValue,
                    state: freshState,
                    senderSeat: gameViewModel.localSeatIndex
                )
                // Even when the gameData was stale, the dedicated table pull
                // above may have surfaced new passes — try to finalize.
                if injectedFromTable { gameViewModel.tryFinalizeCharlestonPass() }
                return
            }
            guard serverIsCharleston,
                  serverData.charlestonPhase == gameViewModel.charlestonPhase.rawValue else {
                if injectedFromTable { gameViewModel.tryFinalizeCharlestonPass() }
                return
            }
            var injected = injectedFromTable
            let serverPending = serverData.charlestonPendingPasses ?? [:]
            for (seatKey, tiles) in serverPending {
                guard let seat = Int(seatKey),
                      seat >= 0, seat < gameViewModel.players.count,
                      gameViewModel.charlestonPendingPasses[seat] == nil else { continue }
                gameViewModel.charlestonPendingPasses[seat] = tiles
                if seat < serverData.players.count {
                    gameViewModel.players[seat].hand = serverData.players[seat].hand
                }
                injected = true
                print("\u{1F504} pullAndMergeCharlestonFromDB: injected pending pass for seat \(seat) (DB had it, realtime lost it)")
            }
            if injected {
                // Try to finalize now that we have a complete map.
                gameViewModel.tryFinalizeCharlestonPass()
                return
            }
            // FULL-MERGE FALLBACK. Surgical inject produced no progress — the row
            // either doesn't yet have the missing seat's pending pass, or the surgical
            // path silently couldn't apply it. If we've been stuck a while, escalate
            // to a full applyRemoteGame so the broader merge logic (priorPendingPasses
            // preservation, hand reconciliation, finalize tries) gets a chance. Reset
            // `lastAppliedUpdatedAt` first so a snapshot we already 'saw' but failed
            // to actually apply is re-evaluated.
            if let since = self.charlestonIncompleteSince,
               Date().timeIntervalSince(since) > 6 {
                self.lastAppliedUpdatedAt = ""
                await self.applyRemoteGame(game, gameViewModel: gameViewModel)
            }
        } catch {
            print("\u{26A0}\u{FE0F} pullAndMergeCharlestonFromDB: \(error)")
        }
    }

    /// Non-host: while we have a pending charleston pass and the phase hasn't advanced,
    /// periodically re-broadcast our submission so the host eventually sees it even if
    /// the initial broadcasts were lost during a channel reconnect.
    private func startCharlestonPassHeartbeat(gameViewModel: GameViewModel) {
        charlestonPassHeartbeatTask?.cancel()
        let startingPhase = gameViewModel.charlestonPhase.rawValue
        let mySeat = gameViewModel.localSeatIndex
        charlestonPassHeartbeatTask = Task { @MainActor [weak self, weak gameViewModel] in
            // UNBOUNDED loop: keep re-broadcasting AND re-writing the DB merge as long
            // as we're still in the same Charleston phase with our pass pending. The
            // previous 30-tick cap silently quit after ~30s and stranded the table when
            // the host hadn't picked up our pass yet (exact symptom in the stuck
            // diagnostics: invitee submitted, host never sees it, both wait forever).
            var tick = 0
            // Track how long we've been waiting for the host to acknowledge our
            // pass. If too much time passes without progress, the realtime channel
            // is likely silently dead in our→host direction — rebuild it.
            let pendingSince = Date()
            var lastReconnectAt: Date = .distantPast
            while !Task.isCancelled {
                // Widened from 600ms — safety net now, not primary path (see RLS fix note above).
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                guard let self, let gameViewModel else { break }
                guard !self.isHost,
                      let gameId = self.currentGameId,
                      gameViewModel.gameStatus == .charleston,
                      gameViewModel.charlestonPhase.rawValue == startingPhase,
                      gameViewModel.charlestonPendingPasses[mySeat] != nil else { break }
                let state = gameViewModel.serializeState()
                await self.broadcastStateUpdate(
                    gameId: gameId,
                    status: OnlineGameStatus.charleston.rawValue,
                    state: state,
                    senderSeat: mySeat
                )
                // Server-side atomic merge — guarantees the host's DB pull sees our
                // pass even if realtime is silently dropping every broadcast.
                // Surface errors so a silently-failing UPSERT (RLS, FK, etc.)
                // doesn't keep stranding the table.
                if let myPass = gameViewModel.charlestonPendingPasses[mySeat] {
                    do {
                        try await self.service.submitCharlestonPassViaEdge(
                            gameId: gameId,
                            seat: mySeat,
                            phase: startingPhase,
                            tiles: myPass,
                            handAfter: gameViewModel.players[mySeat].hand
                        )
                    } catch {
                        print("⚠️ charleston pass heartbeat upsert failed seat=\(mySeat) phase=\(startingPhase): \(error)")
                    }
                }
                // Lightweight redundant signal — survives where state_update doesn't.
                // Skip if the host has already acked our pass for this phase, so we
                // don't keep hammering the channel after the host already has it.
                let alreadyAcked = self.charlestonPassAckedFor[mySeat] == startingPhase
                if !alreadyAcked {
                    await self.broadcastCharlestonPass(gameViewModel: gameViewModel)
                }
                // Realtime peer-pull: every peer that's still in this phase re-broadcasts.
                await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)
                // RLS / dead-socket recovery: ~every 3s, re-issue the merged DB write so
                // our pending pass is durable on the row even if every realtime packet
                // is being silently dropped. The host's heartbeat pulls the row directly
                // to recover.
                tick += 1
                // Normal cadence: write the merged DB row every 5 ticks (~3s).
                // STUCK ESCALATION: once we've been pending for >5s, write every
                // 2 ticks (~1.2s) so the host's surgical DB pull picks our pass
                // up much faster when realtime is silently dropping our broadcasts.
                let pendingForNow = Date().timeIntervalSince(pendingSince)
                let writeInterval = pendingForNow > 5 ? 2 : 5
                if tick % writeInterval == 0 {
                    _ = gameId
                    await self.submitCharlestonPassMerged(gameViewModel: gameViewModel)
                }
                // FORCE-RECONNECT TIER. After our pass has been pending too
                // long without the host advancing the phase, rebuild the
                // realtime channel. Throttled to once every 20s so we don't
                // thrash. Pre-courtesy phases use a tighter threshold because
                // they normally finalize in under 5s once everyone submits.
                let pendingFor = Date().timeIntervalSince(pendingSince)
                let reconnectThreshold: TimeInterval = gameViewModel.charlestonPhase.isCourtesy ? 14 : 10
                if pendingFor > reconnectThreshold, Date().timeIntervalSince(lastReconnectAt) > 20 {
                    print("⚠️ charleston pass heartbeat: pending \(Int(pendingFor))s on seat \(mySeat) during \(gameViewModel.charlestonPhase.displayName) — rebuilding realtime channel")
                    lastReconnectAt = Date()
                    self.forceReconnect(gameViewModel: gameViewModel)
                }
            }
        }
    }

    private func stopCharlestonHeartbeats(resetWatchdogClock: Bool = true) {
        charlestonHeartbeatTask?.cancel()
        charlestonHeartbeatTask = nil
        charlestonPassHeartbeatTask?.cancel()
        charlestonPassHeartbeatTask = nil
        charlestonInviteePullTask?.cancel()
        charlestonInviteePullTask = nil
        // Reset the watchdog clock when truly leaving the charleston phase so a
        // future Charleston (e.g. next game) starts with a clean slate. Callers
        // that are merely rebuilding the heartbeat (forceReconnect path) MUST
        // pass false so the force-finalize escape hatch keeps counting toward
        // its threshold across the reconnect.
        if resetWatchdogClock {
            charlestonIncompleteSince = nil
            charlestonIncompletePhase = -1
            charlestonLastForceFinalizeAt = .distantPast
            charlestonLastReconnectAt = .distantPast
            // Invitee-side phase-stuck watchdog state. Same persistence rule as
            // the host clocks above: only reset when truly leaving Charleston.
            inviteeLastPhaseSeen = -1
            inviteeLastPhaseChangedAt = Date()
            inviteeLastWatchdogClearAt = .distantPast
            inviteeLastReconnectAt = .distantPast
            charlestonPassAckedFor = [:]
        }
    }

    private func stopPlayPhaseHeartbeats() {
        playPhaseHostHeartbeatTask?.cancel()
        playPhaseHostHeartbeatTask = nil
        playPhaseInviteePullTask?.cancel()
        playPhaseInviteePullTask = nil
    }

    /// Host: while in the play phase, re-broadcast the latest serialized state
    /// every few seconds. Idempotent for receivers (applyRemoteState rejects
    /// stale echoes via the discard-count guard) and cheap. This is the
    /// belt-and-suspenders path that lets the game self-heal after a single
    /// dropped broadcast — without it, an invitee whose move broadcast was lost
    /// (or whose host-side response was lost) sits frozen until the user hits
    /// Force Resolve.
    func ensurePlayPhaseHostHeartbeat(gameViewModel: GameViewModel) {
        guard isHost else { return }
        if let existing = playPhaseHostHeartbeatTask, !existing.isCancelled { return }
        let gameIdSnapshot = currentGameId
        playPhaseHostHeartbeatTask = Task { @MainActor [weak self, weak gameViewModel] in
            // Push state immediately on start so a freshly-armed heartbeat doesn't
            // wait a full tick before everyone catches up.
            if let self, let gameViewModel, let gameId = gameIdSnapshot,
               gameViewModel.gameStatus == .playing, !gameViewModel.showEndGameOverlay {
                let state = gameViewModel.serializeState()
                await self.broadcastStateUpdate(
                    gameId: gameId,
                    status: OnlineGameStatus.playing.rawValue,
                    state: state,
                    senderSeat: gameViewModel.localSeatIndex
                )
            }
            var lastReconnectAt: Date = .distantPast
            while !Task.isCancelled {
                // Widened from 3s — safety net now that direct online_games sync works.
                try? await Task.sleep(for: .seconds(6))
                if Task.isCancelled { break }
                guard let self, let gameViewModel else { break }
                guard self.isHost,
                      let gameId = self.currentGameId,
                      gameViewModel.gameStatus == .playing,
                      !gameViewModel.showEndGameOverlay else { break }
                // Routine tick: a tiny liveness ping, not a full state re-serialize.
                // Real moves already propagate via the immediate broadcast + retry
                // burst + durable `game_actions` insert in `syncAfterMove` — this
                // heartbeat's job is just to keep invitees' staleness clock fresh
                // during quiet stretches, not to re-deliver state nothing needs.
                await self.broadcastHeartbeatPing(gameId: gameId, senderSeat: gameViewModel.localSeatIndex)

                // Proactive self-heal: previously this whole check only ran when
                // `applyRemoteState` fired in response to a fresh incoming update,
                // so a stuck call window sat frozen forever if nothing else
                // happened to arrive and trigger it again. Running it here on every
                // heartbeat tick means the host can recover with no dependence on
                // further remote activity at all.
                gameViewModel.checkForStuckPlayPhase()

                // HOST-SIDE PEER PULL & RECONNECT RECOVERY.
                // When it's not the host's turn (i.e. a remote seat owes us a move),
                // we can't make progress without their state_update. If broadcasts
                // from that seat go missing — silently dead socket, dropped packets,
                // RLS-blocked DB write — the host would sit frozen forever, because
                // pushing our own stale state doesn't pull theirs.
                //
                // Mirror the invitee's escalating recovery tiers:
                //   >3s stale  -> broadcast request_state_sync (pull peers)
                //   >6s stale  -> direct DB fetch fallback
                //   >14s stale -> tear down and rebuild the realtime channel
                let turnSeat = gameViewModel.currentPlayerIndex
                let mySeat = gameViewModel.localSeatIndex
                let realSeats = Set(self.currentParticipants.map(\.seatIndex))
                let waitingOnRemoteHuman = turnSeat != mySeat
                    && turnSeat >= 0
                    && turnSeat < gameViewModel.players.count
                    && realSeats.contains(turnSeat)
                if waitingOnRemoteHuman {
                    let staleSeconds: TimeInterval
                    if let at = self.lastStateUpdateAt {
                        staleSeconds = Date().timeIntervalSince(at)
                    } else {
                        staleSeconds = .greatestFiniteMagnitude
                    }
                    if staleSeconds > 3 {
                        await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)
                    }
                    if staleSeconds > 6 {
                        if let game = try? await self.service.fetchGame(gameId: gameId) {
                            await self.applyRemoteGame(game, gameViewModel: gameViewModel)
                        }
                    }
                    if staleSeconds > 14, Date().timeIntervalSince(lastReconnectAt) > 20 {
                        print("⚠️ host play-phase heartbeat: stale \(Int(staleSeconds))s waiting on seat \(turnSeat) — rebuilding realtime channel")
                        lastReconnectAt = Date()
                        self.forceReconnect(gameViewModel: gameViewModel)
                    }
                }
            }
            // Don't nil-out the task reference here — if forceReconnect just
            // armed a fresh heartbeat, this stale cleanup would clobber the new
            // task and leave the host with no self-healing. The cancel() in
            // stopPlayPhaseHeartbeats already handles teardown.
        }
    }

    /// Non-host: while in the play phase, periodically ask peers to re-send
    /// their state if we haven't received a fresh update recently. Recovers
    /// from RLS-blocked SELECTs and dropped broadcasts alike.
    ///
    /// Three escalating recovery tiers based on staleness:
    ///  - >3s stale: ask peers to re-broadcast (cheap, RLS-proof).
    ///  - >6s stale: also pull latest state directly from the DB.
    ///  - >14s stale: tear down and rebuild the realtime channel — a silently
    ///    dead socket is the only way a connected channel can stop delivering
    ///    broadcasts for this long without surfacing an error.
    func ensurePlayPhaseInviteePull(gameViewModel: GameViewModel) {
        guard !isHost else { return }
        if let existing = playPhaseInviteePullTask, !existing.isCancelled { return }
        playPhaseInviteePullTask = Task { @MainActor [weak self, weak gameViewModel] in
            var lastReconnectAt: Date = .distantPast
            var lastSelfPushAt: Date = .distantPast
            var lastDbWriteAt: Date = .distantPast
            while !Task.isCancelled {
                // Widened from 2s — safety net now that direct online_games sync works.
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { break }
                guard let self, let gameViewModel else { break }
                guard !self.isHost,
                      gameViewModel.gameStatus == .playing,
                      !gameViewModel.showEndGameOverlay else { break }
                let staleSeconds: TimeInterval
                if let at = self.lastStateUpdateAt {
                    staleSeconds = Date().timeIntervalSince(at)
                } else {
                    staleSeconds = .greatestFiniteMagnitude
                }
                if staleSeconds > 3 {
                    await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)
                }

                // SYMMETRIC SELF-PUSH. The host runs a play-phase heartbeat that
                // continuously re-broadcasts its state, plus a remote-human-turn
                // watchdog that re-pushes whenever it's waiting on an invitee.
                // Invitees had no equivalent: if a single move broadcast was
                // dropped (network blip after a discard, etc.) and the host's
                // DB pull was RLS-blocked, the host would sit forever on the
                // pre-discard state — exactly the "stuck on invitee turn after
                // host called a quint" freeze users reported.
                //
                // Re-push our local state when it represents an unacknowledged
                // move: either it's our turn (host needs to know what we did)
                // or we're the discarder waiting on the host to finalize the
                // call window. Throttled so we don't spam during normal play.
                //
                // CRITICAL: do NOT gate on `staleSeconds > 3` here. The host's
                // play-phase heartbeat broadcasts its own state every 3s, which
                // continuously freshens our `lastStateUpdateAt`. When the host
                // hasn't yet absorbed our discard, those broadcasts are STALE
                // (pre-discard) — our `applyRemoteState` correctly rejects them
                // via the rollback guard, but `lastStateUpdateAt` still ticks.
                // The previous staleness gate therefore silently suppressed our
                // self-push forever and the discard never made it to the host
                // — exactly the "game freezing on invitee turn discard" symptom.
                let mySeat = gameViewModel.localSeatIndex
                let weAreCurrent = gameViewModel.currentPlayerIndex == mySeat
                let weDiscardedAwaitingFinalize =
                    gameViewModel.lastDiscardPlayerIndex == mySeat
                    && gameViewModel.callResponses[mySeat] != nil
                    && gameViewModel.callResponseDiscardId != nil
                let weAreUnacknowledged = weAreCurrent || weDiscardedAwaitingFinalize
                let now = Date()
                if weAreUnacknowledged,
                   now.timeIntervalSince(lastSelfPushAt) > 3,
                   let gameId = self.currentGameId {
                    lastSelfPushAt = now
                    let state = gameViewModel.serializeState()
                    await self.broadcastStateUpdate(
                        gameId: gameId,
                        status: OnlineGameStatus.playing.rawValue,
                        state: state,
                        senderSeat: mySeat
                    )
                    // Also re-write to DB so a host whose realtime channel silently
                    // dropped our broadcasts can still recover via its heartbeat's
                    // DB pull. Tighter throttle (4s) when we're the discarder
                    // awaiting finalization — every second the host doesn't see
                    // our discard, the table looks frozen to every player.
                    let dbThrottle: TimeInterval = weDiscardedAwaitingFinalize ? 4 : 8
                    if now.timeIntervalSince(lastDbWriteAt) > dbThrottle {
                        lastDbWriteAt = now
                        do {
                            try await self.service.updateGameState(
                                gameId: gameId,
                                gameData: state,
                                currentTurnUserId: self.userIdForPlayerIndex(gameViewModel.currentPlayerIndex),
                                status: OnlineGameStatus.playing.rawValue
                            )
                        } catch {
                            // RLS may block invitee writes — that's fine, the
                            // broadcast above is the primary recovery path.
                            print("⚠️ invitee self-push DB write failed: \(error)")
                        }
                    }
                }

                if staleSeconds > 6 {
                    // RLS may block, but when it works this is the most reliable
                    // recovery path — it goes around any dead realtime channel.
                    if let gameId = self.currentGameId,
                       let game = try? await self.service.fetchGame(gameId: gameId) {
                        await self.applyRemoteGame(game, gameViewModel: gameViewModel)
                    }
                }
                if staleSeconds > 14, Date().timeIntervalSince(lastReconnectAt) > 20 {
                    print("⚠️ invitee play-phase pull: stale \(Int(staleSeconds))s — rebuilding realtime channel")
                    lastReconnectAt = Date()
                    self.forceReconnect(gameViewModel: gameViewModel)
                }
            }
            // See note in ensurePlayPhaseHostHeartbeat — don't nil the reference
            // here, or a forceReconnect-armed successor task gets clobbered.
        }
    }

    /// Non-host invitee: while we are in Charleston (regardless of whether we've
    /// submitted our own pass yet), keep pulling peer state every 750ms so a missed
    /// broadcast during the lobby→board transition (or a slow host advance) can
    /// never strand us with an empty pending-pass map. Idempotent — safe to call
    /// repeatedly.
    func startCharlestonInviteePull(gameViewModel: GameViewModel) {
        guard !isHost else { return }
        charlestonInviteePullTask?.cancel()
        charlestonInviteePullTask = Task { @MainActor [weak self, weak gameViewModel] in
            // Send an immediate sync request so we don't have to wait the full tick.
            if let self, let gameViewModel {
                await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)
            }
            // Three escalating recovery tiers based on how long it's been since
            // we received any state update from a peer. Mirrors the play-phase
            // invitee pull. Covers EVERY Charleston phase — the regular
            // right/across/left passes, the 2nd Charleston, AND the courtesy
            // pass — because the same silently-dead-realtime failure mode
            // (channel reports "connected" but inbound packets dropped) can
            // strand an invitee at any phase boundary. Without these tiers, a
            // dropped phase-advance broadcast leaves the invitee sitting
            // forever ("Waiting for Jen to pick 2 tiles", or stuck on a
            // first-pass receive screen with stale tiles). Pre-courtesy
            // phases use tighter thresholds since they normally finalize in
            // under 5s once everyone has submitted.
            var lastDbPullAt: Date = .distantPast
            // PHASE-PROGRESS WATCHDOG. Track when we last observed a phase change.
            // Heartbeats keep `lastStateUpdateAt` fresh even when the table is stuck
            // at a boundary (e.g. secondRight finalized on host but invitee still sees
            // "Tiles passed"), so the stale-seconds tiers above never trigger. This
            // watchdog fires on phase-stagnation instead, force-pulling the DB and —
            // if that doesn't break the deadlock — clearing our local pending pass
            // and rebuilding the channel so the host's newer state can land.
            //
            // CRITICAL: these MUST persist across task recreation. forceReconnect
            // cancels this task and starts a new one; if the watchdog clock lived
            // task-local, every ~8s reconnect would reset the timer and the 10s
            // auto-clear could never fire — exactly the bug where an invitee sat
            // on phase 0 for 100+ seconds while the host was at phase 6.
            while !Task.isCancelled {
                // Widened from 400ms — safety net now that direct online_games sync works.
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                guard let self, let gameViewModel else { break }
                guard !self.isHost,
                      gameViewModel.gameStatus == .charleston else { break }
                await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)

                // Update phase-change tracker. These persist on the VM so
                // task recreation (forceReconnect) doesn't reset the clock.
                let currentPhase = gameViewModel.charlestonPhase.rawValue
                if currentPhase != self.inviteeLastPhaseSeen {
                    self.inviteeLastPhaseSeen = currentPhase
                    self.inviteeLastPhaseChangedAt = Date()
                }

                let staleSeconds: TimeInterval
                if let at = self.lastStateUpdateAt {
                    staleSeconds = Date().timeIntervalSince(at)
                } else {
                    staleSeconds = .greatestFiniteMagnitude
                }

                // Pre-courtesy passes (right/across/left/2nd Charleston) are
                // bot-fast and should not stay quiet for long; trigger Tier 2
                // earlier. Courtesy is human-paced, so a longer threshold
                // avoids hammering the DB while a player is still picking.
                // Pre-courtesy phases finalize in well under a second once every
                // seat has submitted, so any silence > 2.5s on the invitee side is
                // already long enough to suspect a dropped phase-advance broadcast.
                // Pulling from the DB at that point is the cheapest, most reliable
                // way to recover the new phase before the user notices a freeze.
                let isCourtesy = gameViewModel.charlestonPhase.isCourtesy
                let tier2Threshold: TimeInterval = isCourtesy ? 6 : 1.2
                let tier3Threshold: TimeInterval = isCourtesy ? 14 : 6
                let mySeatNow = gameViewModel.localSeatIndex
                let mySubmittedNow = mySeatNow >= 0
                    && gameViewModel.charlestonPendingPasses[mySeatNow] != nil

                // Tier 2: pull the latest game row directly from the DB and
                // merge it. Recovers from a silently-dropped broadcast even
                // if the channel itself is fine. Throttled so we don't hammer
                // the DB.
                // Throttle DB pulls more loosely during pre-courtesy phases so a
                // dropped phase-advance broadcast is recovered within a couple of
                // seconds instead of waiting a full 4s round.
                let dbPullThrottle: TimeInterval = isCourtesy ? 4 : 0.8
                if staleSeconds > tier2Threshold,
                   Date().timeIntervalSince(lastDbPullAt) > dbPullThrottle,
                   let gameId = self.currentGameId {
                    lastDbPullAt = Date()
                    if let game = try? await self.service.fetchGame(gameId: gameId) {
                        await self.applyRemoteGame(game, gameViewModel: gameViewModel)
                    }
                }

                // TIER 0 (submitted + pinned): once our pass is in and the phase
                // hasn't budged for >2s, pull the row directly — do NOT gate on
                // `staleSeconds`. The host's heartbeat broadcasts arrive every
                // 600ms keeping `lastStateUpdateAt` fresh, but if those broadcasts
                // carry a state that `applyRemoteState` silently rejects (e.g.
                // a stale echo crossed wires with the real advance), the table
                // freezes with the invitee 3 tiles short. Forcing
                // `lastAppliedUpdatedAt = ""` ensures any snapshot we already saw
                // is re-evaluated against our now-newer local pending map.
                let phasePinnedFor = Date().timeIntervalSince(self.inviteeLastPhaseChangedAt)
                let pinnedThreshold: TimeInterval = isCourtesy ? 8 : 0.8
                if mySubmittedNow,
                   phasePinnedFor > pinnedThreshold,
                   Date().timeIntervalSince(lastDbPullAt) > dbPullThrottle,
                   let gameId = self.currentGameId {
                    lastDbPullAt = Date()
                    self.lastAppliedUpdatedAt = ""
                    if let game = try? await self.service.fetchGame(gameId: gameId) {
                        await self.applyRemoteGame(game, gameViewModel: gameViewModel)
                    }
                }

                // Tier 3: tear down and rebuild the realtime channel. A
                // Supabase channel can report "connected" while silently
                // dropping inbound packets in one direction; the only way to
                // recover is to re-subscribe. Throttled to once every 20s so
                // we don't thrash.
                if staleSeconds > tier3Threshold,
                   Date().timeIntervalSince(self.inviteeLastReconnectAt) > 20 {
                    let phaseLabel = gameViewModel.charlestonPhase.displayName
                    print("⚠️ charleston invitee pull: stale \(Int(staleSeconds))s during \(phaseLabel) — rebuilding realtime channel")
                    self.inviteeLastReconnectAt = Date()
                    self.forceReconnect(gameViewModel: gameViewModel)
                }

                // CHARLESTON_PASSES PHASE-ADVANCE DETECTOR (RLS-proof side-channel).
                // The `charleston_passes` table SELECT policy lets any seated
                // participant read every row for their game. So even when:
                //   - the host->invitee realtime channel is silently dead, AND
                //   - RLS blocks the invitee's SELECT on `online_games`,
                // we can STILL learn that the host has advanced by reading
                // the table directly. If ANY row exists at a phase > our
                // local phase, the world has moved on and our pending pass is
                // stale. Recover by clearing the pass + tearing down the
                // socket so a fresh subscribe can land the host's newer state.
                let myDetectorSeat = gameViewModel.localSeatIndex
                if let gameId = self.currentGameId {
                    if let maxPhase = try? await self.service.fetchHighestCharlestonPhase(gameId: gameId),
                       maxPhase > currentPhase {
                        print("\u{1F50E} charleston invitee pull: charleston_passes shows phase \(maxPhase) > local \(currentPhase) — host has advanced; clearing stale local pass and forcing reconnect")
                        if myDetectorSeat >= 0 {
                            gameViewModel.charlestonPendingPasses[myDetectorSeat] = nil
                        }
                        self.lastAppliedUpdatedAt = ""
                        if let game = try? await self.service.fetchGame(gameId: gameId) {
                            await self.applyRemoteGame(game, gameViewModel: gameViewModel)
                        }
                        // If our local phase still hasn't advanced (online_games
                        // SELECT was RLS-blocked), force a real socket reconnect.
                        if gameViewModel.charlestonPhase.rawValue == currentPhase,
                           Date().timeIntervalSince(self.inviteeLastReconnectAt) > 8 {
                            self.inviteeLastReconnectAt = Date()
                            self.forceReconnect(gameViewModel: gameViewModel)
                        }
                        // Don't run the rest of this tick — let the next tick
                        // observe the new world.
                        continue
                    }
                }

                // PHASE-PROGRESS WATCHDOG: auto-clear when boundary-stuck.
                // Trigger when we've been pinned to the same Charleston phase for too
                // long AND we've already submitted our pass. The recovery escalates:
                //   1) force a DB pull (cheap, recovers a dropped phase-advance)
                //   2) if still stuck a few ticks later, clear our stale local
                //      pending pass + re-broadcast so the host can re-sync us
                //   3) finally rebuild the realtime channel
                let mySeat = gameViewModel.localSeatIndex
                let mySubmitted = mySeat >= 0 && gameViewModel.charlestonPendingPasses[mySeat] != nil
                let phaseStuckFor = Date().timeIntervalSince(self.inviteeLastPhaseChangedAt)
                // Pre-courtesy phases normally finalize in well under 1s once every
                // seat has submitted. A 4s pin with our pass submitted means the
                // phase-advance broadcast was dropped — keeping the threshold at
                // 10s caused real-world freezes where the invitee sat at the old
                // phase missing 3 tiles (their pass was applied locally but the
                // post-exchange hand never landed). Courtesy stays loose because
                // East may take seconds to choose a tile count.
                let phaseStuckThreshold: TimeInterval = isCourtesy ? 22 : 1.5
                // Cooldown trimmed (8s → 3s → 1s) so we can re-try the recovery cycle
                // quickly when the first DB pull also missed the new phase.
                if mySubmitted,
                   phaseStuckFor > phaseStuckThreshold,
                   Date().timeIntervalSince(self.inviteeLastWatchdogClearAt) > 1,
                   let gameId = self.currentGameId {
                    self.inviteeLastWatchdogClearAt = Date()
                    let phaseLabel = gameViewModel.charlestonPhase.displayName
                    print("⚠️ charleston invitee watchdog: stuck on \(phaseLabel) for \(Int(phaseStuckFor))s with pass submitted — auto-clearing")
                    // Step 1: force DB pull (independent of staleSeconds gating).
                    // CRITICAL: bypass the `lastAppliedUpdatedAt > newUpdated` guard
                    // in `applyRemoteGame` so a server snapshot we already saw
                    // (but failed to land because the channel was silently dead
                    // or the merge was clobbered) gets re-applied. Without
                    // resetting the timestamp the watchdog can fire forever
                    // without ever advancing the local phase.
                    self.lastAppliedUpdatedAt = ""
                    if let game = try? await self.service.fetchGame(gameId: gameId) {
                        await self.applyRemoteGame(game, gameViewModel: gameViewModel)
                    }
                    // If the DB pull advanced the phase, we're done.
                    if gameViewModel.charlestonPhase.rawValue != currentPhase {
                        self.inviteeLastPhaseSeen = gameViewModel.charlestonPhase.rawValue
                        self.inviteeLastPhaseChangedAt = Date()
                    } else if phaseStuckFor > phaseStuckThreshold + 1 {
                        // Step 2: still stuck after a DB pull. Clear our stale local
                        // pending pass so the UI unfreezes from the "Tiles passed"
                        // screen, re-broadcast, and rebuild realtime as a backstop.
                        if mySeat >= 0 {
                            gameViewModel.charlestonPendingPasses[mySeat] = nil
                        }
                        await self.broadcastStateSyncRequest(gameViewModel: gameViewModel)
                        if Date().timeIntervalSince(self.inviteeLastReconnectAt) > 20 {
                            self.inviteeLastReconnectAt = Date()
                            self.forceReconnect(gameViewModel: gameViewModel)
                        }
                    }
                }
            }
        }
    }

    /// Diagnostics: re-broadcast the full local state to every connected client.
    /// Works in both charleston and play phases. Used by the game-freeze overlay
    /// to nudge a stuck table back into sync.
    func forceResync(gameViewModel: GameViewModel) async {
        guard let gameId = currentGameId else { return }
        let state = gameViewModel.serializeState()
        let status: String
        switch gameViewModel.gameStatus {
        case .charleston: status = OnlineGameStatus.charleston.rawValue
        case .playing: status = OnlineGameStatus.playing.rawValue
        case .completed: status = OnlineGameStatus.completed.rawValue
        default: status = OnlineGameStatus.playing.rawValue
        }
        // Push to DB (best-effort) then broadcast.
        if isHost {
            let currentTurnUserId = userIdForPlayerIndex(gameViewModel.currentPlayerIndex)
            do {
                try await service.updateGameState(gameId: gameId, gameData: state, currentTurnUserId: currentTurnUserId, status: status)
                if status == OnlineGameStatus.completed.rawValue {
                    Task.detached {
                        await OnlineGameService.shared.deleteGameActions(gameId: gameId)
                        await OnlineGameService.shared.deleteCharlestonPasses(gameId: gameId, throughPhase: Int.max)
                    }
                }
            } catch {
                print("⚠️ forceResync DB write failed: \(error)")
            }
        }
        await broadcastStateUpdate(gameId: gameId, status: status, state: state, senderSeat: gameViewModel.localSeatIndex)
        // Ask peers to re-broadcast their state too — in any phase. In the playing
        // phase this is the recovery path when a single move broadcast was lost.
        await broadcastStateSyncRequest(gameViewModel: gameViewModel)
    }

    /// Lightweight diagnostics summary string for the freeze overlay.
    var diagnosticsSnapshot: String {
        var lines: [String] = []
        lines.append("gameId: \(currentGameId ?? "–")")
        lines.append("realtime: \(realtimeStatus)")
        lines.append("participants: \(currentParticipants.count) bots: \(Array(hostBotSeats).sorted())")
        lines.append("state updates rx: \(stateUpdatesReceived) from seat \(lastStateUpdateSenderSeat)")
        if let at = lastStateUpdateAt {
            let age = Int(Date().timeIntervalSince(at))
            lines.append("last update: \(age)s ago")
        } else {
            lines.append("last update: never")
        }
        lines.append("joined broadcasts rx: \(joinedBroadcastsReceived)")
        return lines.joined(separator: "\n")
    }

    /// Manual nudge for the diagnostics overlay's "Sync" button. Forces an immediate
    /// state-sync round-trip; every connected client re-broadcasts their full state.
    func forceCharlestonSync(gameViewModel: GameViewModel) async {
        await broadcastStateSyncRequest(gameViewModel: gameViewModel)
        // Also re-push our own state so peers can absorb it on this round-trip.
        guard let gameId = currentGameId else { return }
        let state = gameViewModel.serializeState()
        await broadcastStateUpdate(
            gameId: gameId,
            status: OnlineGameStatus.charleston.rawValue,
            state: state,
            senderSeat: gameViewModel.localSeatIndex
        )
    }

    private func attachSyncHandler(to gameViewModel: GameViewModel) {
        gameViewModel.onlineSyncHandler = { [weak self, weak gameViewModel] in
            guard let self, let gameViewModel else { return }
            Task { @MainActor in
                await self.syncAfterMove(gameViewModel: gameViewModel)
            }
        }
    }

    /// Public hook for views (e.g. GameBoardView's onAppear) to ensure their
    /// GameViewModel still routes moves through this VM, without disturbing the
    /// existing realtime channel. Idempotent.
    func attachSyncHandlerIfNeeded(gameViewModel: GameViewModel) {
        attachSyncHandler(to: gameViewModel)
        // If we somehow lost the channel (app cold-started straight into the board
        // without going through the lobby), bring realtime back up.
        if realtimeChannel == nil {
            startRealtime(gameViewModel: gameViewModel)
        }
        // Ensure the appropriate play-phase heartbeat is running so dropped
        // broadcasts can self-heal even if we entered the board directly.
        if gameViewModel.gameStatus == .playing && !gameViewModel.showEndGameOverlay {
            if isHost {
                ensurePlayPhaseHostHeartbeat(gameViewModel: gameViewModel)
            } else {
                ensurePlayPhaseInviteePull(gameViewModel: gameViewModel)
            }
        }
    }

    // MARK: - Realtime

    func startPolling(gameViewModel: GameViewModel) {
        startRealtime(gameViewModel: gameViewModel)
    }

    func stopPolling() {
        stopRealtime()
    }

    /// Force-rebuild the realtime channel. Used by the lobby watchdog when the
    /// initial subscribe hangs in "connecting" -- without this, an invitee whose
    /// channel never finished its handshake will silently miss every broadcast
    /// (including game_started) and sit forever in the lobby.
    func forceReconnect(gameViewModel: GameViewModel) {
        print("forceReconnect: tearing down stuck channel (status=\(realtimeStatus), joinedRX=\(joinedBroadcastsReceived), stateRX=\(stateUpdatesReceived))")
        // Preserve the charleston watchdog clock across the reconnect so the
        // force-finalize escape hatch keeps counting. Without this, every 8–10s
        // reconnect would reset the timer and the table could stay frozen forever.
        let savedIncompleteSince = charlestonIncompleteSince
        let savedIncompletePhase = charlestonIncompletePhase
        let savedLastForceFinalizeAt = charlestonLastForceFinalizeAt
        let savedLastReconnectAt = charlestonLastReconnectAt
        // Preserve the invitee-side phase-stuck watchdog clocks across the
        // reconnect for the same reason: forceReconnect is itself called from
        // the watchdog loop, and resetting them here would let a stuck invitee
        // reconnect every 8s forever without the 10s auto-clear ever firing.
        let savedInviteeLastPhaseSeen = inviteeLastPhaseSeen
        let savedInviteeLastPhaseChangedAt = inviteeLastPhaseChangedAt
        let savedInviteeLastWatchdogClearAt = inviteeLastWatchdogClearAt
        let savedInviteeLastReconnectAt = inviteeLastReconnectAt

        // Mark immediately as disconnected so any concurrent code observes the
        // tear-down state.
        realtimeStatus = "reconnecting"

        // CRITICAL ORDERING: the previous version kicked off `disconnect()` in a
        // detached Task and called `startRealtime()` synchronously RIGHT AFTER —
        // so the new channel was being subscribed on the OLD socket while the
        // disconnect was still in flight. The racing disconnect would then kill
        // the freshly-built channel a moment later, leaving the table with a
        // half-dead realtime path that broadcasts no longer flow on. This was
        // the silent killer of the 2nd-game-stuck-after-first-pass diagnostics:
        // the 8s reconnect tier fired, but the rebuilt channel was immediately
        // re-broken, so 60+ seconds passed without any state_update flowing.
        //
        // Now: tear down the old channel + socket FIRST, await both, THEN
        // start the new realtime layer. Same Task so we keep ordering on the
        // MainActor.
        let client = SupabaseService.shared.client
        let oldChannel = realtimeChannel
        realtimeChannel = nil
        // Cancel current realtime/heartbeat tasks synchronously so they can't
        // continue running on the dead channel while we wait for disconnect.
        realtimeTask?.cancel()
        realtimeTask = nil
        lobbyBotSeatsHeartbeatTask?.cancel()
        lobbyBotSeatsHeartbeatTask = nil
        Task { @MainActor [weak self, weak gameViewModel] in
            if let oldChannel { await oldChannel.unsubscribe() }
            await client.realtimeV2.disconnect()
            guard let self, let gameViewModel else { return }
            self.startRealtime(gameViewModel: gameViewModel)
            self.charlestonIncompleteSince = savedIncompleteSince
            self.charlestonIncompletePhase = savedIncompletePhase
            self.charlestonLastForceFinalizeAt = savedLastForceFinalizeAt
            self.charlestonLastReconnectAt = savedLastReconnectAt
            self.inviteeLastPhaseSeen = savedInviteeLastPhaseSeen
            self.inviteeLastPhaseChangedAt = savedInviteeLastPhaseChangedAt
            self.inviteeLastWatchdogClearAt = savedInviteeLastWatchdogClearAt
            self.inviteeLastReconnectAt = savedInviteeLastReconnectAt
            // CRITICAL: startRealtime() called stopRealtime() which cancelled the
            // play-phase / charleston heartbeat tasks (including the very task that
            // invoked us). Re-arm the appropriate heartbeat for the current phase so
            // self-healing keeps running after a reconnect — without this, a single
            // dead-socket recovery silently disables every future recovery and the
            // table stays frozen until the user manually nudges it.
            if gameViewModel.gameStatus == .playing && !gameViewModel.showEndGameOverlay {
                if self.isHost {
                    self.ensurePlayPhaseHostHeartbeat(gameViewModel: gameViewModel)
                } else {
                    self.ensurePlayPhaseInviteePull(gameViewModel: gameViewModel)
                }
            } else if gameViewModel.gameStatus == .charleston {
                // Re-arm the appropriate charleston self-healing tasks. forceReconnect
                // is itself called from inside these heartbeats when they detect a
                // silently-dead channel — if we don't re-arm here, a single recovery
                // permanently disables future recoveries and the table re-freezes.
                if self.isHost {
                    self.startCharlestonHostHeartbeat(gameViewModel: gameViewModel)
                } else {
                    self.startCharlestonInviteePull(gameViewModel: gameViewModel)
                    if gameViewModel.charlestonPendingPasses[gameViewModel.localSeatIndex] != nil {
                        self.startCharlestonPassHeartbeat(gameViewModel: gameViewModel)
                    }
                }
            }
        }
    }

    func startRealtime(gameViewModel: GameViewModel) {
        stopRealtime()
        guard let gameId = currentGameId else { return }
        isPolling = true
        realtimeStatus = "connecting"
        attachSyncHandler(to: gameViewModel)

        let client = SupabaseService.shared.client

        realtimeTask = Task { [weak self, weak gameViewModel] in
            guard let self else { return }
            let channel = client.channel("online-game-\(gameId)")

            let gameUpdates = channel.postgresChange(
                UpdateAction.self,
                schema: "public",
                table: "online_games",
                filter: "id=eq.\(gameId)"
            )
            let participantInserts = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "game_participants",
                filter: "game_id=eq.\(gameId)"
            )
            let participantDeletes = channel.postgresChange(
                DeleteAction.self,
                schema: "public",
                table: "game_participants",
                filter: "game_id=eq.\(gameId)"
            )
            // Option B: durable action-log wake-up. Every play/charleston move
            // appends a row here; any insert from a remote seat with seq beyond
            // our cursor triggers a full-state pull.
            let gameActionInserts = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "game_actions",
                filter: "game_id=eq.\(gameId)"
            )
            let botSeatsBroadcast = channel.broadcastStream(event: "bot_seats")
            let gameStartedBroadcast = channel.broadcastStream(event: "game_started")
            let stateUpdateBroadcast = channel.broadcastStream(event: "state_update")
            let heartbeatPingBroadcast = channel.broadcastStream(event: "heartbeat_ping")
            let joinedBroadcast = channel.broadcastStream(event: "joined")
            let charlestonPassBroadcast = channel.broadcastStream(event: "charleston_pass")
            let charlestonPassAckBroadcast = channel.broadcastStream(event: "charleston_pass_ack")
            let requestPendingPassBroadcast = channel.broadcastStream(event: "request_pending_pass")

            await channel.subscribe()
            await MainActor.run {
                self.realtimeChannel = channel
                self.realtimeStatus = "connected"
            }
            // Host: announce the current bot lineup as soon as the channel is live
            // so any invitees already in the lobby render the bots immediately.
            await self.broadcastBotSeats()
            // Everyone announces their own presence so participant lists fill in even when
            // RLS blocks the database SELECT on `game_participants`.
            await self.broadcastJoinedSelf()
            // Re-broadcast our presence a few times in case other clients subscribed slightly
            // after we did (broadcasts are not replayed on subscribe).
            for delayMs in [400, 1500, 4000] {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    await self?.broadcastJoinedSelf()
                }
            }
            // Invitees: ask the host to re-send bot_seats + participant identity
            // immediately. This is the RLS-proof, race-proof path for filling in
            // the lobby state regardless of when the host added the bots.
            await self.requestLobbySyncIfInvitee()
            for delayMs in [600, 1800, 4500] {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    await self?.requestLobbySyncIfInvitee()
                }
            }
            // Host: keep re-broadcasting the bot lineup every 2s while in the lobby
            // (status=waiting). Cheap, idempotent, eliminates any subscribe-race window.
            await self.startLobbyBotSeatsHeartbeat()

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self, weak gameViewModel] in
                    for await update in gameUpdates {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleGameUpdate(update, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self] in
                    for await _ in participantInserts {
                        if Task.isCancelled { break }
                        guard let self else { break }
                        await self.refreshParticipants()
                        // Host: re-broadcast the bot lineup so the freshly-joined invitee
                        // (who almost certainly missed the original at-subscribe broadcast)
                        // sees the bot seats turn green right away.
                        if await self.isHost {
                            await self.broadcastBotSeats()
                        }
                    }
                }
                group.addTask { [weak self] in
                    for await _ in participantDeletes {
                        if Task.isCancelled { break }
                        await self?.refreshParticipants()
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(8))
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.backupSync(gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self] in
                    for await event in botSeatsBroadcast {
                        if Task.isCancelled { break }
                        guard let self else { break }
                        await self.handleBotSeatsBroadcast(event)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in gameStartedBroadcast {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleGameStartedBroadcastWithPayload(event, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in stateUpdateBroadcast {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleStateUpdateBroadcast(event, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in heartbeatPingBroadcast {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleHeartbeatPingBroadcast(event, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self] in
                    for await event in joinedBroadcast {
                        if Task.isCancelled { break }
                        guard let self else { break }
                        await self.handleJoinedBroadcast(event)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in charlestonPassBroadcast {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleCharlestonPassBroadcast(event, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in charlestonPassAckBroadcast {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleCharlestonPassAckBroadcast(event, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in requestPendingPassBroadcast {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleRequestPendingPassBroadcast(event, gameViewModel: gameViewModel)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await insert in gameActionInserts {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleGameActionInsert(insert, gameViewModel: gameViewModel)
                    }
                }
                let lobbySyncRequests = channel.broadcastStream(event: "request_lobby_sync")
                let stateSyncRequests = channel.broadcastStream(event: "request_state_sync")
                group.addTask { [weak self] in
                    for await event in lobbySyncRequests {
                        if Task.isCancelled { break }
                        guard let self else { break }
                        await self.handleLobbySyncRequest(event)
                    }
                }
                group.addTask { [weak self, weak gameViewModel] in
                    for await event in stateSyncRequests {
                        if Task.isCancelled { break }
                        guard let self, let gameViewModel else { break }
                        await self.handleStateSyncRequest(event, gameViewModel: gameViewModel)
                    }
                }
            }
        }
    }

    /// Broadcast our own participant identity to the channel. Other clients merge the
    /// payload into `currentParticipants` so participant lists are visible even when
    /// RLS blocks the database SELECT.
    func broadcastJoinedSelf() async {
        guard let channel = realtimeChannel,
              let gameId = currentGameId,
              let myId = myUserId else { return }
        // Resolve our seat from any source we can: server-fetched participants, or the
        // host-default seat 0 (East), or the first slot we know we joined into.
        let mySeat: Int = currentParticipants.first(where: { $0.userId == myId })?.seatIndex
            ?? myKnownSeat
            ?? (isHost ? 0 : -1)
        guard mySeat >= 0 else { return }
        let payload = JoinedPayload(
            gameId: gameId,
            userId: myId,
            seatIndex: mySeat,
            displayName: myDisplayName,
            avatarImage: myAvatarImage,
            isHost: isHost,
            cardYear: currentGame?.cardYear
        )
        do {
            try await channel.broadcast(event: "joined", message: payload)
            print("👋 broadcastJoinedSelf seat=\(mySeat) host=\(isHost) name=\(myDisplayName)")
        } catch {
            print("⚠️ broadcastJoinedSelf: \(error)")
        }
    }

    private func handleJoinedBroadcast(_ event: JSONObject) async {
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        do {
            let data = try JSONEncoder().encode(payloadObject)
            let payload = try JSONDecoder().decode(JoinedPayload.self, from: data)
            // Don't store our own echo.
            if payload.userId == myUserId { return }
            joinedBroadcastsReceived += 1
            // Detect whether this announcement actually changes our knowledge.
            // If the peer is already known at the same seat with the same display
            // info, we must NOT re-broadcast our own presence — that creates a
            // self-perpetuating ping-pong loop with every connected client
            // (each receive triggers another send), which floods the realtime
            // channel and starves real game broadcasts (state_update). 28k+
            // joined events in diagnostics is the fingerprint of this loop.
            let existing = currentParticipants.first { $0.userId == payload.userId }
            let isNewOrChanged: Bool = {
                guard let existing else { return true }
                if existing.seatIndex != payload.seatIndex { return true }
                if existing.displayName != payload.displayName { return true }
                if existing.avatarImage != payload.avatarImage { return true }
                return false
            }()
            print("👋 received joined: seat=\(payload.seatIndex) host=\(payload.isHost) name=\(payload.displayName) new=\(isNewOrChanged)")
            // Merge into participants list (replace any existing entry for the same seat/user).
            currentParticipants.removeAll { $0.userId == payload.userId || $0.seatIndex == payload.seatIndex }
            currentParticipants.append(GameParticipant(
                id: nil,
                gameId: payload.gameId,
                userId: payload.userId,
                seatIndex: payload.seatIndex,
                displayName: payload.displayName,
                avatarImage: payload.avatarImage,
                createdAt: nil
            ))
            currentParticipants.sort { $0.seatIndex < $1.seatIndex }
            // If the announcer is the host, synthesize/update currentGame so the lobby's
            // diagnostics + status checks reflect that we know who the host is — even when
            // RLS blocks the `online_games` SELECT.
            if payload.isHost {
                if currentGame == nil {
                    currentGame = OnlineGame(
                        id: payload.gameId,
                        hostId: payload.userId,
                        status: OnlineGameStatus.waiting.rawValue,
                        gameData: nil,
                        currentTurnUserId: nil,
                        cardYear: payload.cardYear,
                        createdAt: nil,
                        updatedAt: ISO8601DateFormatter().string(from: Date())
                    )
                } else {
                    if currentGame?.hostId.isEmpty == true {
                        currentGame?.hostId = payload.userId
                    }
                    // Always trust the host's authoritative card year so every invitee's
                    // lobby reflects the same NMJL card the host is actually using.
                    if let hostCardYear = payload.cardYear, !hostCardYear.isEmpty {
                        if currentGame?.cardYear != hostCardYear {
                            currentGame?.cardYear = hostCardYear
                        }
                    }
                }
            }
            // Re-broadcast our own presence so the joiner sees us too — but ONLY
            // when the peer is actually new/changed AND we haven't already echoed
            // very recently. The initial subscribe path already re-broadcasts our
            // presence on a 400ms / 1.5s / 4s schedule, so newly-arrived peers
            // converge without us needing to echo every joined event we receive.
            let now = Date()
            let recentlyEchoed = now.timeIntervalSince(lastJoinedRebroadcastAt) < 5
            if isNewOrChanged && !recentlyEchoed {
                lastJoinedRebroadcastAt = now
                await broadcastJoinedSelf()
            }
        } catch {
            print("⚠️ joined broadcast decode failed: \(error)")
        }
    }

    /// Apply a `state_update` broadcast. This is the RLS-proof companion to the
    /// postgres-changes UPDATE stream: every state-write also broadcasts the full
    /// serialized state so every connected client (host + invitees) sees the latest
    /// Charleston pending passes regardless of their SELECT permissions.
    private func handleStateUpdateBroadcast(_ event: JSONObject, gameViewModel: GameViewModel) async {
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        do {
            let data = try JSONEncoder().encode(payloadObject)
            let payload = try JSONDecoder().decode(StateUpdatePayload.self, from: data)
            // Ignore our own echo — we already have the freshest local state.
            if payload.senderSeat == gameViewModel.localSeatIndex { return }
            print("📡 state_update from seat \(payload.senderSeat) status=\(payload.status) phase=\(payload.state.charlestonPhase) pending=\(payload.state.charlestonPendingPasses?.keys.sorted() ?? [])")
            stateUpdatesReceived += 1
            lastStateUpdateSenderSeat = payload.senderSeat
            lastStateUpdateAt = Date()
            // Track which seats we've ever seen submit during this phase, for diagnostics.
            if payload.state.charlestonPhase != lastCharlestonPhaseObserved {
                lastCharlestonPhaseObserved = payload.state.charlestonPhase
                observedCharlestonPasses = []
            }
            for seatKey in payload.state.charlestonPendingPasses?.keys ?? [:].keys {
                if let i = Int(seatKey) { observedCharlestonPasses.insert(i) }
            }
            let sanitized = sanitizeStatePlayers(payload.state)
            gameViewModel.applyRemoteState(sanitized)
            rectifyBotFlags(gameViewModel)
            // Non-host: ensure the passive Charleston pull is running so we keep
            // catching up even if subsequent broadcasts are dropped during a reconnect.
            if !isHost && gameViewModel.gameStatus == .charleston {
                startCharlestonInviteePull(gameViewModel: gameViewModel)
            }
            if gameViewModel.gameStatus == .playing && !gameViewModel.showEndGameOverlay {
                if isHost {
                    ensurePlayPhaseHostHeartbeat(gameViewModel: gameViewModel)
                } else {
                    ensurePlayPhaseInviteePull(gameViewModel: gameViewModel)
                }
            }
            // Keep the local OnlineGame mirror in sync so any UI that observes it updates too.
            // Synthesize a minimal OnlineGame if RLS blocked our initial SELECT — otherwise
            // the lobby diagnostics would forever show status=nil.
            if currentGame == nil {
                currentGame = OnlineGame(
                    id: payload.gameId,
                    hostId: "",
                    status: payload.status,
                    gameData: payload.state,
                    currentTurnUserId: nil,
                    cardYear: nil,
                    createdAt: nil,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            } else {
                currentGame?.status = payload.status
                currentGame?.gameData = payload.state
            }
            if currentGameId == nil { currentGameId = payload.gameId }
            if payload.status != OnlineGameStatus.waiting.rawValue && !showGameBoard { showGameBoard = true }
        } catch {
            print("⚠️ state_update decode failed: \(error)")
        }
    }

    /// Apply a `heartbeat_ping` broadcast. See `HeartbeatPingPayload` — this
    /// carries no game state, so unlike `handleStateUpdateBroadcast` there is
    /// nothing to merge: just refresh the staleness clock that
    /// `ensurePlayPhaseInviteePull` / `ensurePlayPhaseHostHeartbeat` use to
    /// decide whether to escalate (sync request → DB pull → reconnect).
    private func handleHeartbeatPingBroadcast(_ event: JSONObject, gameViewModel: GameViewModel) async {
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        guard let data = try? JSONEncoder().encode(payloadObject),
              let payload = try? JSONDecoder().decode(HeartbeatPingPayload.self, from: data) else {
            return
        }
        // Ignore our own echo.
        if payload.senderSeat == gameViewModel.localSeatIndex { return }
        lastStateUpdateSenderSeat = payload.senderSeat
        lastStateUpdateAt = Date()

        // TERMINAL RE-ASSERT. The play-phase heartbeat loop only runs while the
        // sender is still `.playing`, so receiving a ping means that peer has NOT
        // seen the end of the game. If WE have already finished — declared Mahjong
        // or a wall game — that peer is behind and needs our terminal state.
        //
        // This restores a recovery path that used to be implicit: when the host
        // heartbeat re-broadcast a FULL playing `state_update`, it reached the
        // winner's `applyRemoteState` and tripped the COMPLETED IS TERMINAL guard,
        // which re-pushed the win. The lightweight ping carries no state and never
        // enters `applyRemoteState`, so without this an invitee's win whose
        // original broadcast was dropped never reaches the host — the invitee's
        // own retry loops stop the instant it completes, and its DB write may be
        // RLS-blocked. The host would sit parked on its own turn forever (exactly
        // the "host never got the Mahjong end-of-game" report). Re-broadcasting is
        // self-limiting: once the host absorbs our terminal state it leaves
        // `.playing` and stops pinging, so this stops firing.
        //
        // Broadcast the terminal state DIRECTLY rather than via `syncAfterMove`:
        // a completed hand is authoritative and must never be suppressed by that
        // method's "server is ahead on discard count" guard, which trips when the
        // win was declared on a CALLED discard (the winner removed the claimed
        // tile, so its pile is one shorter than the host's still-`.playing` row).
        if gameViewModel.gameStatus == .completed, let gameId = currentGameId {
            let state = gameViewModel.serializeState()
            await broadcastStateUpdate(
                gameId: gameId,
                status: OnlineGameStatus.completed.rawValue,
                state: state,
                senderSeat: gameViewModel.localSeatIndex
            )
        }
    }

    /// Invitee fast-path: when the host broadcasts "game_started", pull the live state
    /// and surface the game board immediately — don't wait on postgres replication.
    /// Retries until `game_data` is fully replicated so the broadcast can never arrive
    /// faster than the row write and leave the invitee on a half-loaded screen.
    private func handleGameStartedBroadcast(gameViewModel: GameViewModel) async {
        // Kept for back-compat — payload-less path. Falls back to DB load.
        print("📡 Invitee received game_started broadcast (isHost=\(isHost), gameId=\(currentGameId ?? "nil"))")
        if isHost { return }
        guard let gameId = currentGameId else { return }
        let ok = await loadOnlineGameStateWithRetry(gameId: gameId, gameViewModel: gameViewModel)
        print("📡 Invitee game_started DB load result: \(ok)")
    }

    /// Apply a `game_started` broadcast that includes the full serialized state inline.
    /// This is the bullet-proof path: it does NOT depend on the invitee being able to
    /// SELECT the `online_games` row (which RLS may block). The host stamps every start
    /// payload with the live state so invitees can transition immediately.
    private func handleGameStartedBroadcastWithPayload(_ event: JSONObject, gameViewModel: GameViewModel) async {
        if isHost { return }
        // Unwrap the broadcast envelope: { event, type, payload: {...} }
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        // Re-encode the inner object then decode as our typed payload.
        do {
            let data = try JSONEncoder().encode(payloadObject)
            let payload = try JSONDecoder().decode(GameStartedPayload.self, from: data)
            print("📡 Invitee got game_started payload: status=\(payload.status) hasState=\(payload.state != nil) participants=\(payload.participants?.count ?? 0)")
            if currentGameId == nil { currentGameId = payload.gameId }
            if let participants = payload.participants, !participants.isEmpty {
                currentParticipants = participants
            }
            mergeSelfIntoParticipants()
            guard let myId = myUserId else { return }
            let mySeat = currentParticipants.first(where: { $0.userId == myId })?.seatIndex ?? myKnownSeat ?? 0
            myKnownSeat = mySeat
            gameViewModel.isOnlineMode = true
            gameViewModel.onlineGameId = payload.gameId
            gameViewModel.localSeatIndex = mySeat
            attachSyncHandler(to: gameViewModel)
            if let state = payload.state {
                let sanitized = sanitizeStatePlayers(state)
                gameViewModel.restoreState(from: sanitized)
                rectifyBotFlags(gameViewModel)
            }
            // Non-host invitee: kick off the passive Charleston pull immediately so
            // we never sit on a stale empty pending-pass map waiting for a heartbeat.
            if gameViewModel.gameStatus == .charleston {
                startCharlestonInviteePull(gameViewModel: gameViewModel)
            }
            // Synthesize a minimal currentGame so the lobby's status checks pass even
            // when RLS blocks the SELECT.
            if currentGame == nil {
                currentGame = OnlineGame(
                    id: payload.gameId,
                    hostId: currentParticipants.first(where: { p in payload.participants?.contains(where: { $0.userId == p.userId }) ?? true })?.userId ?? "",
                    status: payload.status,
                    gameData: payload.state,
                    currentTurnUserId: nil,
                    cardYear: payload.cardYear,
                    createdAt: nil,
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            } else {
                currentGame?.status = payload.status
                if let state = payload.state { currentGame?.gameData = state }
                if let cy = payload.cardYear, !cy.isEmpty, currentGame?.cardYear != cy {
                    currentGame?.cardYear = cy
                }
            }
            showGameBoard = true
        } catch {
            print("⚠️ game_started payload decode failed, falling back to DB: \(error)")
            await handleGameStartedBroadcast(gameViewModel: gameViewModel)
        }
    }

    private func handleBotSeatsBroadcast(_ event: JSONObject) async {
        // The host owns the bot lineup — ignore our own echo.
        if isHost { return }
        // Payload comes wrapped under a "payload" key when sent via broadcast.
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        if case .array(let seatsJSON) = payloadObject["seats"] ?? .null {
            var seats: Set<Int> = []
            for value in seatsJSON {
                if case .integer(let i) = value { seats.insert(i) }
                else if case .double(let d) = value { seats.insert(Int(d)) }
            }
            print("🤖 Invitee received bot_seats broadcast: \(Array(seats).sorted())")
            hostBotSeats = seats
        } else {
            print("⚠️ bot_seats broadcast missing 'seats' array. payload=\(payloadObject)")
        }
    }

    /// Invitee → host: "please re-send the lobby state". Host responds with bot_seats
    /// and a `joined` broadcast for itself. Cheap and idempotent.
    func requestLobbySyncIfInvitee() async {
        guard !isHost, let channel = realtimeChannel,
              let gameId = currentGameId, let myId = myUserId else { return }
        let payload = LobbySyncRequestPayload(gameId: gameId, userId: myId)
        do {
            try await channel.broadcast(event: "request_lobby_sync", message: payload)
            print("📨 requestLobbySyncIfInvitee sent")
        } catch {
            print("⚠️ requestLobbySyncIfInvitee: \(error)")
        }
    }

    private func handleLobbySyncRequest(_ event: JSONObject) async {
        // Only the host responds.
        guard isHost else { return }
        print("📨 host received request_lobby_sync — re-broadcasting bot_seats + joined")
        await broadcastBotSeats()
        await broadcastJoinedSelf()
    }

    /// Any client that has Charleston state to share responds to a sync request by
    /// re-broadcasting their full local state. Within a couple of round-trips this
    /// guarantees every client converges on the same pending-pass map.
    private func handleStateSyncRequest(_ event: JSONObject, gameViewModel: GameViewModel) async {
        // Respond in both Charleston and Playing phases. Without the playing-phase
        // path, a force-sync during play never pulls peer state and a frozen turn
        // (caused by a dropped move broadcast) can never recover.
        guard let gameId = currentGameId else { return }
        guard gameViewModel.gameStatus == .charleston || gameViewModel.gameStatus == .playing else { return }
        let status: String = gameViewModel.gameStatus == .charleston
            ? OnlineGameStatus.charleston.rawValue
            : OnlineGameStatus.playing.rawValue
        let state = gameViewModel.serializeState()
        await broadcastStateUpdate(
            gameId: gameId,
            status: status,
            state: state,
            senderSeat: gameViewModel.localSeatIndex
        )
    }

    /// Lightweight Charleston-pass broadcast for THIS seat. Sent in addition to
    /// the full `state_update` so the host has a tiny redundant signal carrying
    /// just enough information to record the pass. The smaller payload is far
    /// more likely to survive a flaky realtime channel that silently drops
    /// large state echoes (the exact failure mode behind the long stalls users
    /// see at the 1st pass right / across boundaries).
    func broadcastCharlestonPass(gameViewModel: GameViewModel) async {
        guard let channel = realtimeChannel,
              let gameId = currentGameId else { return }
        let mySeat = gameViewModel.localSeatIndex
        guard mySeat >= 0, mySeat < gameViewModel.players.count else { return }
        guard let tiles = gameViewModel.charlestonPendingPasses[mySeat], !tiles.isEmpty else { return }
        let payload = CharlestonPassPayload(
            gameId: gameId,
            seat: mySeat,
            phase: gameViewModel.charlestonPhase.rawValue,
            tiles: tiles,
            handAfter: gameViewModel.players[mySeat].hand
        )
        do {
            try await channel.broadcast(event: "charleston_pass", message: payload)
            print("📡 broadcastCharlestonPass seat=\(mySeat) phase=\(payload.phase) tiles=\(tiles.count)")
        } catch {
            print("⚠️ broadcastCharlestonPass: \(error)")
        }
    }

    /// Host-only: upload the host's seat (and any bot seats) into the
    /// `charleston_passes` table for the current phase. Bots and the host
    /// don't otherwise write rows there — only invitee submits do via the
    /// edge-function path — which means a phase advance involving only host +
    /// bots leaves zero rows at the new phase. The non-host invitee-pull
    /// `fetchHighestCharlestonPhase` detector then can't see that the world
    /// moved on and the invitee stays pinned to the previous phase forever.
    /// Idempotent UPSERT keyed on (game_id, seat_index, phase). Best-effort
    /// — a failed write is non-fatal because the host heartbeat retries.
    func uploadHostControlledPasses(gameViewModel: GameViewModel) async {
        guard isHost, let gameId = currentGameId else { return }
        let phase = gameViewModel.charlestonPhase.rawValue
        let mySeat = gameViewModel.localSeatIndex
        // Determine which seats the host "owns": its own seat plus every bot.
        var seatsToUpload: [Int] = []
        for i in 0..<gameViewModel.players.count {
            if i == mySeat || gameViewModel.players[i].isBot {
                seatsToUpload.append(i)
            }
        }
        for seat in seatsToUpload {
            guard let tiles = gameViewModel.charlestonPendingPasses[seat], !tiles.isEmpty else { continue }
            let handAfter = (seat < gameViewModel.players.count) ? gameViewModel.players[seat].hand : []
            do {
                try await service.submitCharlestonPass(
                    gameId: gameId,
                    seat: seat,
                    phase: phase,
                    tiles: tiles,
                    handAfter: handAfter
                )
            } catch {
                // RLS may reject host-driven inserts for bot seats (user_id is
                // the host's id, not the bot's) — that's fine, the row for
                // the host's own seat alone is enough to advance the
                // phase-detector watermark.
                print("⚠️ uploadHostControlledPasses seat=\(seat) phase=\(phase): \(error)")
            }
        }
    }

    /// Host -> invitee acknowledgement that the host recorded a seat's pass at
    /// the given phase. Lets the invitee stop heartbeating its pass-broadcast
    /// once the host has actually picked it up.
    private func broadcastCharlestonPassAck(seat: Int, phase: Int) async {
        guard let channel = realtimeChannel,
              let gameId = currentGameId else { return }
        let payload = CharlestonPassAckPayload(gameId: gameId, seat: seat, phase: phase)
        do {
            try await channel.broadcast(event: "charleston_pass_ack", message: payload)
            print("✅ broadcastCharlestonPassAck seat=\(seat) phase=\(phase)")
        } catch {
            print("⚠️ broadcastCharlestonPassAck: \(error)")
        }
    }

    /// Host: a peer sent us their pending pass via the lightweight event.
    /// Inject directly into local `charlestonPendingPasses` and try to finalize.
    /// This bypasses the full-state merge so a single missing seat is enough
    /// to break a stuck phase.
    private func handleCharlestonPassBroadcast(_ event: JSONObject, gameViewModel: GameViewModel) async {
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        do {
            let data = try JSONEncoder().encode(payloadObject)
            let payload = try JSONDecoder().decode(CharlestonPassPayload.self, from: data)
            // Ignore our own echo.
            if payload.seat == gameViewModel.localSeatIndex { return }
            print("📥 charleston_pass from seat \(payload.seat) phase=\(payload.phase) tiles=\(payload.tiles.count)")
            // Update freshness signals so the staleness watchdogs know we got
            // SOMETHING from the network even if state_update echoes were lost.
            lastStateUpdateAt = Date()
            lastStateUpdateSenderSeat = payload.seat
            stateUpdatesReceived += 1
            if payload.phase != lastCharlestonPhaseObserved {
                lastCharlestonPhaseObserved = payload.phase
                observedCharlestonPasses = []
            }
            observedCharlestonPasses.insert(payload.seat)
            // Only the host actually orchestrates the exchange. Non-hosts simply
            // refresh diagnostics and move on.
            guard isHost else { return }
            guard gameViewModel.gameStatus == .charleston else {
                // We've already left Charleston — ack so the sender stops retrying.
                await broadcastCharlestonPassAck(seat: payload.seat, phase: payload.phase)
                return
            }
            // Phase mismatch — stale pass. Ack so the sender stops retrying for
            // this old phase; their newer pass will arrive next.
            if gameViewModel.charlestonPhase.rawValue != payload.phase {
                await broadcastCharlestonPassAck(seat: payload.seat, phase: payload.phase)
                return
            }
            guard payload.seat >= 0, payload.seat < gameViewModel.players.count else { return }
            // If we already have this seat's pass, just re-ack and return.
            if gameViewModel.charlestonPendingPasses[payload.seat] != nil {
                await broadcastCharlestonPassAck(seat: payload.seat, phase: payload.phase)
                return
            }
            // Record the pass + mirror the seat's post-pass hand so the exchange
            // math stays consistent with what they actually have client-side.
            gameViewModel.charlestonPendingPasses[payload.seat] = payload.tiles
            gameViewModel.players[payload.seat].hand = payload.handAfter
            print("🔄 host injected charleston_pass for seat \(payload.seat)")
            await broadcastCharlestonPassAck(seat: payload.seat, phase: payload.phase)
            // Try to finalize now that we may have a full pending map.
            gameViewModel.tryFinalizeCharlestonPass()
        } catch {
            print("⚠️ charleston_pass decode failed: \(error)")
        }
    }

    /// HOST → missing peers: "please push your Charleston pass NOW." Targeted
    /// recovery for the silently-dead-channel case where neither realtime nor
    /// the surgical DB merge has picked a seat's pass up after many tries.
    private func broadcastRequestPendingPass(missingSeats: [Int], phase: Int) async {
        guard let channel = realtimeChannel,
              let gameId = currentGameId else { return }
        let payload = RequestPendingPassPayload(gameId: gameId, phase: phase, missingSeats: missingSeats)
        do {
            try await channel.broadcast(event: "request_pending_pass", message: payload)
            print("📨 broadcastRequestPendingPass missing=\(missingSeats) phase=\(phase)")
        } catch {
            print("⚠️ broadcastRequestPendingPass: \(error)")
        }
    }

    /// Invitee: the host is asking us to push our pending Charleston pass directly.
    /// Clear any cached ack flag, re-broadcast our pass, and re-write the DB row.
    private func handleRequestPendingPassBroadcast(_ event: JSONObject, gameViewModel: GameViewModel) async {
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        do {
            let data = try JSONEncoder().encode(payloadObject)
            let payload = try JSONDecoder().decode(RequestPendingPassPayload.self, from: data)
            // Freshness signal — host is alive and asking for us.
            lastStateUpdateAt = Date()
            let mySeat = gameViewModel.localSeatIndex
            // Only respond if we ARE one of the missing seats AND we actually
            // have a pending pass for the requested phase.
            guard mySeat >= 0,
                  payload.missingSeats.contains(mySeat),
                  gameViewModel.gameStatus == .charleston,
                  gameViewModel.charlestonPhase.rawValue == payload.phase,
                  gameViewModel.charlestonPendingPasses[mySeat] != nil else { return }
            print("📨 received request_pending_pass — re-pushing seat \(mySeat) phase=\(payload.phase)")
            // Drop any ack cache so we definitely re-send.
            charlestonPassAckedFor[mySeat] = nil
            await broadcastCharlestonPass(gameViewModel: gameViewModel)
            // Re-write the DB row too so the host's next surgical pull picks it up.
            await submitCharlestonPassMerged(gameViewModel: gameViewModel)
        } catch {
            print("⚠️ request_pending_pass decode failed: \(error)")
        }
    }

    /// Invitee: the host acknowledged our pass for a given phase. Mark it so
    /// the heartbeat can stop hammering the channel for that phase.
    private func handleCharlestonPassAckBroadcast(_ event: JSONObject, gameViewModel: GameViewModel) async {
        let payloadObject: JSONObject
        if case .object(let inner) = event["payload"] ?? .null {
            payloadObject = inner
        } else {
            payloadObject = event
        }
        do {
            let data = try JSONEncoder().encode(payloadObject)
            let payload = try JSONDecoder().decode(CharlestonPassAckPayload.self, from: data)
            // We only care about acks targeting OUR seat.
            if payload.seat != gameViewModel.localSeatIndex { return }
            print("✅ received charleston_pass_ack for our seat=\(payload.seat) phase=\(payload.phase)")
            charlestonPassAckedFor[payload.seat] = payload.phase
            // Treat ack as a freshness signal too — the host is alive and heard us.
            lastStateUpdateAt = Date()
        } catch {
            print("⚠️ charleston_pass_ack decode failed: \(error)")
        }
    }

    func broadcastStateSyncRequest(gameViewModel: GameViewModel) async {
        guard let channel = realtimeChannel,
              let gameId = currentGameId else { return }
        let payload = StateSyncRequestPayload(
            gameId: gameId,
            requesterSeat: gameViewModel.localSeatIndex,
            phase: gameViewModel.charlestonPhase.rawValue
        )
        do {
            try await channel.broadcast(event: "request_state_sync", message: payload)
        } catch {
            print("⚠️ broadcastStateSyncRequest: \(error)")
        }
    }

    /// Host: while still in the lobby (status=waiting), keep re-broadcasting the bot
    /// lineup every 2s so any invitee that subscribed late still picks it up.
    private func startLobbyBotSeatsHeartbeat() async {
        guard isHost else { return }
        lobbyBotSeatsHeartbeatTask?.cancel()
        lobbyBotSeatsHeartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let status = self.currentGame?.status ?? OnlineGameStatus.waiting.rawValue
                guard status == OnlineGameStatus.waiting.rawValue else { break }
                await self.broadcastBotSeats()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopRealtime() {
        isPolling = false
        realtimeStatus = "disconnected"
        realtimeTask?.cancel()
        realtimeTask = nil
        lobbyBotSeatsHeartbeatTask?.cancel()
        lobbyBotSeatsHeartbeatTask = nil
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
            realtimeChannel = nil
        }
        pollTask?.cancel()
        pollTask = nil
        stopCharlestonHeartbeats()
        stopPlayPhaseHeartbeats()
        // Option B: reset the action-log cursor so the next game starts clean.
        lastObservedActionSeq = 0
    }

    /// Option B: a peer appended an action row. If it's from a remote seat and
    /// beyond our recovery cursor, pull the authoritative `online_games` row.
    /// This is the durable safety net behind the realtime broadcast — even if
    /// the broadcast was dropped or RLS quietly blocked the postgres_changes
    /// stream on `online_games`, this small INSERT will reach every seat.
    nonisolated struct GameActionRecord: Codable, Sendable {
        let seq: Int64
        let seat: Int
        let kind: String
    }

    private func handleGameActionInsert(_ insert: InsertAction, gameViewModel: GameViewModel) async {
        do {
            let row = try insert.decodeRecord(as: GameActionRecord.self, decoder: JSONDecoder())
            if row.seq > lastObservedActionSeq {
                lastObservedActionSeq = row.seq
            }
            // Ignore our own actions — we already have the freshest local state.
            if row.seat == gameViewModel.localSeatIndex { return }
            print("📥 game_action seq=\(row.seq) seat=\(row.seat) kind=\(row.kind) — pulling state")
            await backupSync(gameViewModel: gameViewModel)
        } catch {
            print("⚠️ handleGameActionInsert decode: \(error)")
            // Decode failure is itself a signal something happened; pull anyway.
            await backupSync(gameViewModel: gameViewModel)
        }
    }

    private func handleGameUpdate(_ update: UpdateAction, gameViewModel: GameViewModel) async {
        do {
            let game = try update.decodeRecord(as: OnlineGame.self, decoder: JSONDecoder())
            await applyRemoteGame(game, gameViewModel: gameViewModel)
        } catch {
            print("⚠️ handleGameUpdate decode: \(error)")
            await backupSync(gameViewModel: gameViewModel)
        }
    }

    func applyRemoteGame(_ game: OnlineGame, gameViewModel: GameViewModel) async {
        // HOST-ABANDONED RECOVERY — deliberately BEFORE the `updatedAt` guard below.
        //
        // `leaveGame()` deletes the leaver's participant row, so a LIVE game whose
        // participant list no longer contains the HOST has been abandoned. That is
        // terminal for everyone else: the host drives every bot turn and owns call-window
        // finalization, so nothing will ever move again. The invitee is left staring at a
        // dead table — status "playing", a bot's turn that will never come, no state
        // updates — with no way out but force-quitting the app.
        //
        // The DB-completed fallback below cannot rescue this, because the game was never
        // marked completed: the row still says "playing" with an empty winnerName. The
        // host simply walked away mid-game — won and tapped through the overlay before the
        // completion write landed, force-quit, or crashed.
        //
        // This check MUST run before `guard newUpdated > lastAppliedUpdatedAt`: an
        // abandoned game's `updated_at` never changes again, so anything after that guard
        // would never execute.
        if let gameId = game.id,
           game.status != OnlineGameStatus.waiting.rawValue,
           game.status != OnlineGameStatus.completed.rawValue,
           let myId = myUserId,
           game.hostId != myId,
           !currentParticipants.isEmpty,
           !currentParticipants.contains(where: { $0.userId == game.hostId }) {
            // Re-fetch before ending someone's game on the strength of a stale list.
            let fresh = (try? await service.fetchParticipants(gameId: gameId)) ?? []
            if !fresh.isEmpty, !fresh.contains(where: { $0.userId == game.hostId }) {
                currentParticipants = fresh
                if !gameViewModel.showEndGameOverlay {
                    gameViewModel.gameStatus = .completed
                    gameViewModel.showEndGameOverlay = true
                    gameViewModel.isWallGame = false
                    gameViewModel.winnerName = ""
                    gameViewModel.gameMessage = "The host left — this game has ended."
                    print("🚪 host is no longer a participant — ending the abandoned game")
                }
                stopCharlestonHeartbeats()
                stopPlayPhaseHeartbeats()
                return
            }
        }

        let newUpdated = game.updatedAt ?? ""
        guard newUpdated > lastAppliedUpdatedAt else { return }
        lastAppliedUpdatedAt = newUpdated
        currentGame = game

        // CRITICAL: invitees must transition the moment status leaves "waiting" —
        // do NOT wait for game_data to replicate. If gameData is still nil, we kick
        // off a retry that fills it in once it arrives. This guarantees invitees can
        // never be stranded behind a postgres replication lag.
        let statusIsLive = game.status != OnlineGameStatus.waiting.rawValue
        if statusIsLive, !gameViewModel.isOnlineMode, let gameId = game.id, let myId = myUserId {
            // Make sure participants are fresh so we pick the correct local seat.
            if !currentParticipants.contains(where: { $0.userId == myId }) {
                if let fetched = try? await service.fetchParticipants(gameId: gameId), !fetched.isEmpty {
                    currentParticipants = fetched
                }
                mergeSelfIntoParticipants()
            }
            let mySeat = currentParticipants.first(where: { $0.userId == myId })?.seatIndex ?? myKnownSeat ?? 0
            myKnownSeat = mySeat
            gameViewModel.isOnlineMode = true
            gameViewModel.onlineGameId = gameId
            gameViewModel.localSeatIndex = mySeat
            attachSyncHandler(to: gameViewModel)
        }

        if let gameData = game.gameData {
            let sanitized = sanitizeStatePlayers(gameData)
            gameViewModel.applyRemoteState(sanitized)
            rectifyBotFlags(gameViewModel)
            if !isHost && gameViewModel.gameStatus == .charleston {
                startCharlestonInviteePull(gameViewModel: gameViewModel)
            }
            if gameViewModel.gameStatus == .playing && !gameViewModel.showEndGameOverlay {
                if isHost {
                    ensurePlayPhaseHostHeartbeat(gameViewModel: gameViewModel)
                } else {
                    ensurePlayPhaseInviteePull(gameViewModel: gameViewModel)
                }
            }
        } else if statusIsLive, let gameId = game.id, !isHost {
            // Status flipped but game_data hasn't replicated yet — kick off a background
            // retry so the live state lands as soon as it's available.
            Task { [weak self, weak gameViewModel] in
                guard let self, let gameViewModel else { return }
                _ = await self.loadOnlineGameStateWithRetry(gameId: gameId, gameViewModel: gameViewModel)
            }
        }

        // Surface the game board for invitees still sitting in the lobby the moment
        // the host kicks off the Charleston — even if gameData hasn't arrived yet.
        if statusIsLive, !showGameBoard {
            showGameBoard = true
        }

        if game.status == OnlineGameStatus.completed.rawValue {
            // AUTHORITATIVE END OF GAME — the DB row is the source of truth.
            //
            // This was an empty `// game over` stub. The `applyRemoteState` call above
            // only ends the game when `game.gameData` is present, so an invitee that
            // missed the realtime `.completed` broadcast AND whose `game_data` hadn't
            // replicated yet had NO fallback whatsoever. It sat on a live board
            // indefinitely, watching a table that no longer existed: status still
            // "Playing", the host already gone from participants, no state update for
            // 38 seconds, and no way out but force-quitting the app.
            //
            // That is exactly what happens when the host declares Mahjong and leaves
            // immediately — the broadcast and the host both vanish in the same moment,
            // and this poll is the only thing left that could have saved the invitee.
            //
            // If the row says completed, the game is over for everyone. Surface the
            // end-game overlay whether or not `game_data` ever arrived, and stop the
            // polling tasks so we aren't heartbeating at a dead game.
            if !gameViewModel.showEndGameOverlay {
                gameViewModel.gameStatus = .completed
                gameViewModel.showEndGameOverlay = true
                if gameViewModel.winnerName.isEmpty, !gameViewModel.isWallGame {
                    gameViewModel.gameMessage = "Game over."
                }
                print("🏁 applyRemoteGame: DB says completed — forcing end-game overlay")
            }
            stopCharlestonHeartbeats()
            stopPlayPhaseHeartbeats()
            return
        }
    }

    private func refreshParticipants() async {
        guard let gameId = currentGameId else { return }
        do {
            let fetched = try await service.fetchParticipants(gameId: gameId)
            // Same RLS guard as loadLobby — never replace a populated list with an empty
            // one returned by a SELECT-blocked invitee.
            if !fetched.isEmpty {
                currentParticipants = fetched
            }
            mergeSelfIntoParticipants()
        } catch {
            print("⚠️ refreshParticipants: \(error)")
            mergeSelfIntoParticipants()
        }
    }

    private func backupSync(gameViewModel: GameViewModel) async {
        guard let gameId = currentGameId, !pendingLocalSync else { return }
        // Option B: also advance our action-log cursor so we don't ping-pong
        // backupSync forever on missed inserts after a reconnect. If any new
        // actions exist beyond our cursor, the fetchGame below pulls the
        // resulting authoritative state.
        if let rows = try? await service.fetchGameActionsSince(gameId: gameId, sinceSeq: lastObservedActionSeq),
           let maxSeq = rows.map(\.seq).max() {
            lastObservedActionSeq = maxSeq
        }
        do {
            guard let game = try await service.fetchGame(gameId: gameId) else { return }
            await applyRemoteGame(game, gameViewModel: gameViewModel)
        } catch {
            print("⚠️ backupSync: \(error)")
        }
    }

    func leaveGame() async {
        guard let gameId = currentGameId else { return }

        // A HOST leaving a LIVE game must kill the game for everyone, FIRST.
        //
        // The host drives every bot turn and owns call-window finalization, so once they
        // walk away nothing at the table can ever advance again. If the row is left saying
        // "playing", every other player is stranded on a dead board with no way out but
        // force-quitting — a bot's turn that will never come, and no state updates.
        //
        // We can't rely on the normal end-of-game write having landed. A host who wins and
        // immediately taps through the overlay to exit races their own completion write
        // against this very teardown (`stopRealtime`, the socket disconnect, and
        // `currentGameId = nil` below all fire while it's still in flight) — which is
        // exactly how a finished, won game ends up persisted as `status: playing` with an
        // empty `winnerName`. This runs BEFORE any of that teardown, and is a status-only
        // patch so it stays small and doesn't clobber `game_data`.
        if isHost,
           let game = currentGame,
           game.status != OnlineGameStatus.completed.rawValue,
           game.status != OnlineGameStatus.waiting.rawValue {
            do {
                try await service.markGameCompleted(gameId: gameId)
                print("🏁 host left a live game — marked it completed so no one is stranded")
            } catch {
                print("⚠️ leaveGame: failed to mark game completed: \(error)")
            }
        }

        stopRealtime()
        // FRESH-SOCKET GUARANTEE FOR THE NEXT GAME.
        // stopRealtime() cancels the realtime task and unsubscribes the channel
        // in a fire-and-forget Task, but it does NOT tear down the underlying
        // WebSocket. When the user starts a 2nd game in the same session, that
        // older socket is reused — and if it's accumulated any silent
        // half-dead state (a channel teardown still in flight, a stale
        // subscription handle, etc.), the new game's broadcasts get dropped
        // and the table sits frozen at the very first Charleston pass even
        // though both clients show "Realtime: connected". Awaiting an explicit
        // disconnect here forces the next startRealtime() to perform a clean
        // socket handshake, which is the only way to recover from a silently
        // dead V2 socket.
        await SupabaseService.shared.client.realtimeV2.disconnect()
        do {
            try await service.leaveGame(gameId: gameId)
        } catch {
            print("⚠️ leaveGame: \(error)")
        }
        currentGameId = nil
        currentGame = nil
        currentParticipants = []
        lastAppliedUpdatedAt = ""
        showGameBoard = false
        sentInvitesCount = 0
        pendingInviteCountForCurrentGame = 0
        didAutoStart = false
        isQuickMatchGame = false
        quickMatchStartedAt = nil
        hostBotSeats = []
        myKnownSeat = nil
    }



    /// Force-correct `isBot` on every serialized seat against the authoritative
    /// participant list before the state is applied locally. Without this, a stale
    /// payload (built before an invitee joined, or echoed from a client whose own
    /// view of the lineup was wrong) can leave the host treating a real invitee
    /// seat as a bot — causing `proceedWithTurn` and the bot driver inside
    /// `applyRemoteState` to auto-play that seat repeatedly. This is the single
    /// chokepoint every state-load path runs through.
    private func sanitizeStatePlayers(_ state: SerializedGameState) -> SerializedGameState {
        var s = state
        let realSeats = Set(currentParticipants.map(\.seatIndex))
        for i in 0..<s.players.count {
            if realSeats.contains(i) {
                if s.players[i].isBot {
                    print("🩺 sanitizeStatePlayers: seat \(i) was isBot=true but has a real participant — forcing false")
                    s.players[i].isBot = false
                }
            } else if hostBotSeats.contains(i) {
                if !s.players[i].isBot {
                    s.players[i].isBot = true
                }
            }
        }
        return s
    }

    private func rectifyBotFlags(_ gameViewModel: GameViewModel) {
        let realSeats = Set(currentParticipants.map(\.seatIndex))
        // Mirror the authoritative seat sets onto the GameViewModel so it can
        // self-rectify at every turn-advancement chokepoint — critical for
        // preventing the host from auto-playing the invitee's seat after
        // Charleston completes (a stale isBot=true would skip them otherwise).
        gameViewModel.authoritativeRealSeats = realSeats
        gameViewModel.authoritativeHostBotSeats = hostBotSeats
        gameViewModel.rectifyBotFlags(realParticipantSeats: realSeats, hostBotSeats: hostBotSeats)
    }

    private func userIdForPlayerIndex(_ index: Int) -> String? {
        guard index < currentParticipants.count else { return nil }
        let sorted = currentParticipants.sorted { $0.seatIndex < $1.seatIndex }
        guard index < sorted.count else { return nil }
        return sorted[index].userId
    }
}
