import Foundation
import Supabase

@MainActor
@Observable
class OnlineGameService {
    static let shared = OnlineGameService()

    private let client = SupabaseService.shared.client
    var errorMessage: String?

    private init() {}

    var currentUserId: String? {
        SupabaseService.shared.currentUserId?.uuidString.lowercased()
    }

    func createGame(cardYear: String) async throws -> OnlineGame {
        guard let userId = currentUserId else { throw DatabaseError.notAuthenticated }

        nonisolated struct GameInsert: Codable, Sendable {
            let hostId: String
            let status: String
            let cardYear: String
            enum CodingKeys: String, CodingKey {
                case hostId = "host_id"
                case status
                case cardYear = "card_year"
            }
        }

        let insert = GameInsert(hostId: userId, status: OnlineGameStatus.waiting.rawValue, cardYear: cardYear)
        let result: [OnlineGame] = try await client
            .from("online_games")
            .insert(insert)
            .select()
            .execute()
            .value
        guard let game = result.first else { throw OnlineGameError.createFailed }
        return game
    }

    func joinGame(gameId: String, seatIndex: Int, displayName: String, avatarImage: String) async throws {
        guard let userId = currentUserId else { throw DatabaseError.notAuthenticated }

        nonisolated struct ParticipantInsert: Codable, Sendable {
            let gameId: String
            let userId: String
            let seatIndex: Int
            let displayName: String
            let avatarImage: String
            enum CodingKeys: String, CodingKey {
                case gameId = "game_id"
                case userId = "user_id"
                case seatIndex = "seat_index"
                case displayName = "display_name"
                case avatarImage = "avatar_image"
            }
        }

        let insert = ParticipantInsert(
            gameId: gameId,
            userId: userId,
            seatIndex: seatIndex,
            displayName: displayName,
            avatarImage: avatarImage
        )
        try await client
            .from("game_participants")
            .insert(insert)
            .execute()
    }

    /// Lightweight status-only fetch. Used by the lobby's invitee transition path so a
    /// decoding failure on the heavy `game_data` JSON can't prevent the transition.
    func fetchGameStatus(gameId: String) async throws -> String? {
        nonisolated struct StatusRow: Codable, Sendable { let status: String }
        let rows: [StatusRow] = try await client
            .from("online_games")
            .select("status")
            .eq("id", value: gameId)
            .execute()
            .value
        return rows.first?.status
    }

    func fetchGame(gameId: String) async throws -> OnlineGame? {
        let result: [OnlineGame] = try await client
            .from("online_games")
            .select()
            .eq("id", value: gameId)
            .execute()
            .value
        return result.first
    }

    func fetchParticipants(gameId: String) async throws -> [GameParticipant] {
        let result: [GameParticipant] = try await client
            .from("game_participants")
            .select()
            .eq("game_id", value: gameId)
            .order("seat_index", ascending: true)
            .execute()
            .value
        return result
    }

    func updateGameState(gameId: String, gameData: SerializedGameState, currentTurnUserId: String?, status: String) async throws {
        nonisolated struct GameUpdate: Codable, Sendable {
            let gameData: SerializedGameState
            let currentTurnUserId: String?
            let status: String
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case gameData = "game_data"
                case currentTurnUserId = "current_turn_user_id"
                case status
                case updatedAt = "updated_at"
            }
        }

        let update = GameUpdate(
            gameData: gameData,
            currentTurnUserId: currentTurnUserId,
            status: status,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )
        try await client
            .from("online_games")
            .update(update)
            .eq("id", value: gameId)
            .execute()
    }

    /// Idempotent UPSERT of a single seat's Charleston pass into the dedicated
    /// `charleston_passes` table. One INSERT per seat per phase — no
    /// fetch/merge/write race, no edge function, no cross-client clobbering.
    /// Realtime postgres_changes on this table notify the host immediately.
    func submitCharlestonPass(
        gameId: String,
        seat: Int,
        phase: Int,
        tiles: [MahjongTile],
        handAfter: [MahjongTile]
    ) async throws {
        guard let userId = currentUserId else { throw DatabaseError.notAuthenticated }
        nonisolated struct PassUpsert: Codable, Sendable {
            let gameId: String
            let seatIndex: Int
            let phase: Int
            let userId: String
            let tiles: [MahjongTile]
            let handAfter: [MahjongTile]
            enum CodingKeys: String, CodingKey {
                case gameId = "game_id"
                case seatIndex = "seat_index"
                case phase
                case userId = "user_id"
                case tiles
                case handAfter = "hand_after"
            }
        }
        let row = PassUpsert(
            gameId: gameId,
            seatIndex: seat,
            phase: phase,
            userId: userId,
            tiles: tiles,
            handAfter: handAfter
        )
        try await client
            .from("charleston_passes")
            .upsert(row, onConflict: "game_id,seat_index,phase")
            .execute()
    }

    /// Fetch the single highest charleston phase ever submitted for a game.
    /// Used by invitees to detect that the host has already advanced past their
    /// local phase even when `online_games` SELECT is RLS-blocked AND the
    /// host->invitee realtime channel is silently dead. The `charleston_passes`
    /// table SELECT policy explicitly allows any seated participant to read
    /// every row for their game, so this works even when full game-state reads
    /// are blocked.
    func fetchHighestCharlestonPhase(gameId: String) async throws -> Int? {
        nonisolated struct PhaseRow: Codable, Sendable { let phase: Int }
        let rows: [PhaseRow] = try await client
            .from("charleston_passes")
            .select("phase")
            .eq("game_id", value: gameId)
            .order("phase", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first?.phase
    }

    /// Fetch every seat's submitted pass for a given game/phase. Used by the
    /// host to assemble the full pending-pass map and finalize the round.
    func fetchCharlestonPasses(gameId: String, phase: Int) async throws -> [CharlestonPassRow] {
        let rows: [CharlestonPassRow] = try await client
            .from("charleston_passes")
            .select()
            .eq("game_id", value: gameId)
            .eq("phase", value: phase)
            .execute()
            .value
        return rows
    }

    /// Best-effort cleanup of pass rows once the round has advanced. Stale rows
    /// are also filtered out by phase mismatch at read time, so this is purely
    /// a table-size optimization, not correctness-critical — but a bare "log
    /// and forget" on failure meant a single transient network blip silently
    /// leaked rows for that game forever. One retry after a short backoff
    /// covers the common transient case; a repeat failure is still logged
    /// (nothing here is worth blocking gameplay to surface further).
    func deleteCharlestonPasses(gameId: String, throughPhase: Int) async {
        for attempt in 0..<2 {
            do {
                try await client
                    .from("charleston_passes")
                    .delete()
                    .eq("game_id", value: gameId)
                    .lte("phase", value: throughPhase)
                    .execute()
                return
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(2))
                } else {
                    print("⚠️ deleteCharlestonPasses: failed after retry: \(error)")
                }
            }
        }
    }

    // MARK: - game_actions (Option B durable wake-up log)

    /// Append a play-phase action row. Server-side trigger assigns the
    /// per-game monotonic `seq`. Fire-and-forget durable signal that survives
    /// dropped realtime broadcasts — other clients see the insert via
    /// postgres_changes and pull the latest `online_games` row.
    ///
    /// Payload is kept tiny on purpose: the kind + seat + seq is enough for
    /// peers to know they missed something; the authoritative state still
    /// lives in `online_games.game_data`.
    func insertGameAction(
        gameId: String,
        seat: Int,
        kind: String,
        discardCount: Int? = nil,
        currentTurn: Int? = nil
    ) async throws {
        guard let userId = currentUserId else { throw DatabaseError.notAuthenticated }
        nonisolated struct ActionPayload: Codable, Sendable {
            let discardCount: Int?
            let currentTurn: Int?
            enum CodingKeys: String, CodingKey {
                case discardCount = "discard_count"
                case currentTurn = "current_turn"
            }
        }
        nonisolated struct ActionInsert: Codable, Sendable {
            let gameId: String
            let seat: Int
            let userId: String
            let kind: String
            let payload: ActionPayload
            enum CodingKeys: String, CodingKey {
                case gameId = "game_id"
                case seat
                case userId = "user_id"
                case kind
                case payload
            }
        }
        let row = ActionInsert(
            gameId: gameId,
            seat: seat,
            userId: userId,
            kind: kind,
            payload: ActionPayload(discardCount: discardCount, currentTurn: currentTurn)
        )
        try await client
            .from("game_actions")
            .insert(row)
            .execute()
    }

    /// Fetch every action for a game whose `seq` is strictly greater than
    /// `sinceSeq`. Used by clients on reconnect / periodic backup to detect
    /// missed actions and trigger a full-state pull.
    func fetchGameActionsSince(gameId: String, sinceSeq: Int64) async throws -> [GameActionRow] {
        let rows: [GameActionRow] = try await client
            .from("game_actions")
            .select("game_id,seq,seat,kind")
            .eq("game_id", value: gameId)
            .gt("seq", value: Int(sinceSeq))
            .order("seq", ascending: true)
            .execute()
            .value
        return rows
    }

    /// Best-effort cleanup of action rows when a game completes.
    ///
    /// NOTE: as of the multiplayer cleanup pass, this is now actually called
    /// (from `OnlineGameViewModel.syncAfterMove` when a status write of
    /// "completed" succeeds) — previously this function existed but had no
    /// call site anywhere in the app, so `game_actions` rows accumulated
    /// forever for every game ever played. Same one-retry pattern as
    /// `deleteCharlestonPasses` so a transient failure doesn't leak rows.
    func deleteGameActions(gameId: String) async {
        for attempt in 0..<2 {
            do {
                try await client
                    .from("game_actions")
                    .delete()
                    .eq("game_id", value: gameId)
                    .execute()
                return
            } catch {
                if attempt == 0 {
                    try? await Task.sleep(for: .seconds(2))
                } else {
                    print("⚠️ deleteGameActions: failed after retry: \(error)")
                }
            }
        }
    }

    /// Legacy edge-function entry point — retained as a thin shim so any
    /// remaining call sites compile. Delegates to the table-based path.
    func submitCharlestonPassViaEdge(
        gameId: String,
        seat: Int,
        phase: Int,
        tiles: [MahjongTile],
        handAfter: [MahjongTile]
    ) async throws {
        try await submitCharlestonPass(
            gameId: gameId,
            seat: seat,
            phase: phase,
            tiles: tiles,
            handAfter: handAfter
        )
    }

    func sendInvite(gameId: String, receiverId: String) async throws {
        guard let userId = currentUserId else { throw DatabaseError.notAuthenticated }

        nonisolated struct InviteInsert: Codable, Sendable {
            let gameId: String
            let senderId: String
            let receiverId: String
            let status: String
            enum CodingKeys: String, CodingKey {
                case gameId = "game_id"
                case senderId = "sender_id"
                case receiverId = "receiver_id"
                case status
            }
        }

        let insert = InviteInsert(
            gameId: gameId,
            senderId: userId,
            receiverId: receiverId,
            status: InviteStatus.pending.rawValue
        )
        try await client
            .from("game_invites")
            .insert(insert)
            .execute()
    }

    func fetchMyInvites() async throws -> [GameInvite] {
        guard let userId = currentUserId else { return [] }
        let result: [GameInvite] = try await client
            .from("game_invites")
            .select()
            .eq("receiver_id", value: userId)
            .eq("status", value: InviteStatus.pending.rawValue)
            .order("created_at", ascending: false)
            .execute()
            .value
        return result
    }

    func respondToInvite(inviteId: String, accept: Bool) async throws {
        let newStatus = accept ? InviteStatus.accepted.rawValue : InviteStatus.declined.rawValue
        try await client
            .from("game_invites")
            .update(["status": newStatus])
            .eq("id", value: inviteId)
            .execute()
    }

    /// Batched replacement for the previous N+1 implementation, which did
    /// `1 + 2×N` sequential round trips (one `fetchGame` + one `fetchParticipants`
    /// awaited per game, one at a time, in a for-loop). This does 3 total: the
    /// caller's own participant rows, then the matching games and the full
    /// participant lists for those games fetched concurrently. Round-trip count
    /// no longer scales with how many active games the user has.
    func fetchMyActiveGames() async throws -> [OnlineGameSummary] {
        guard let userId = currentUserId else { return [] }

        let myParticipantRows: [GameParticipant] = try await client
            .from("game_participants")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        let gameIds = Array(Set(myParticipantRows.map(\.gameId)))
        guard !gameIds.isEmpty else { return [] }

        async let gamesTask: [OnlineGame] = client
            .from("online_games")
            .select()
            .in("id", value: gameIds)
            .neq("status", value: OnlineGameStatus.completed.rawValue)
            .execute()
            .value
        async let participantsTask: [GameParticipant] = client
            .from("game_participants")
            .select()
            .in("game_id", value: gameIds)
            .execute()
            .value

        let (games, allParticipants) = try await (gamesTask, participantsTask)
        let participantsByGame = Dictionary(grouping: allParticipants, by: \.gameId)

        let summaries: [OnlineGameSummary] = games.compactMap { game in
            guard let gameId = game.id else { return nil }
            return OnlineGameSummary(
                id: gameId,
                game: game,
                participants: participantsByGame[gameId] ?? [],
                isMyTurn: game.currentTurnUserId == userId,
                myUserId: userId
            )
        }
        return summaries.sorted { ($0.game.updatedAt ?? "") > ($1.game.updatedAt ?? "") }
    }

    func fetchInviteSenderProfile(senderId: String) async throws -> FriendProfile? {
        try await SupabaseService.shared.fetchFriendProfile(userId: senderId)
    }

    func leaveGame(gameId: String) async throws {
        guard let userId = currentUserId else { return }
        try await client
            .from("game_participants")
            .delete()
            .eq("game_id", value: gameId)
            .eq("user_id", value: userId)
            .execute()
    }

    func fetchOpenWaitingGames() async throws -> [OnlineGame] {
        let result: [OnlineGame] = try await client
            .from("online_games")
            .select()
            .eq("status", value: OnlineGameStatus.waiting.rawValue)
            .order("created_at", ascending: true)
            .limit(50)
            .execute()
            .value
        return result
    }

    func fetchAcceptedInvites(gameId: String) async throws -> [GameInvite] {
        let result: [GameInvite] = try await client
            .from("game_invites")
            .select()
            .eq("game_id", value: gameId)
            .eq("status", value: InviteStatus.accepted.rawValue)
            .execute()
            .value
        return result
    }

    func fetchPendingInviteCount(gameId: String) async throws -> Int {
        let result: [GameInvite] = try await client
            .from("game_invites")
            .select()
            .eq("game_id", value: gameId)
            .eq("status", value: InviteStatus.pending.rawValue)
            .execute()
            .value
        return result.count
    }

    func nextAvailableSeat(gameId: String) async throws -> Int {
        let participants = try await fetchParticipants(gameId: gameId)
        let takenSeats = Set(participants.map(\.seatIndex))
        for i in 0..<4 {
            if !takenSeats.contains(i) { return i }
        }
        throw OnlineGameError.gameFull
    }
}

nonisolated enum OnlineGameError: LocalizedError, Sendable {
    case createFailed
    case gameFull
    case gameNotFound
    case notYourTurn
    case invalidState

    var errorDescription: String? {
        switch self {
        case .createFailed: return "Failed to create online game."
        case .gameFull: return "This game is already full."
        case .gameNotFound: return "Game not found."
        case .notYourTurn: return "It's not your turn."
        case .invalidState: return "Invalid game state."
        }
    }
}
