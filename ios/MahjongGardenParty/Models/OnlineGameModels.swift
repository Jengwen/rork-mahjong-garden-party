import Foundation

nonisolated struct OnlineGame: Codable, Identifiable, Sendable {
    let id: String?
    var hostId: String
    var status: String
    var gameData: SerializedGameState?
    var currentTurnUserId: String?
    var cardYear: String?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case hostId = "host_id"
        case status
        case gameData = "game_data"
        case currentTurnUserId = "current_turn_user_id"
        case cardYear = "card_year"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

nonisolated struct GameParticipant: Codable, Identifiable, Sendable {
    let id: String?
    let gameId: String
    let userId: String
    let seatIndex: Int
    let displayName: String
    let avatarImage: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gameId = "game_id"
        case userId = "user_id"
        case seatIndex = "seat_index"
        case displayName = "display_name"
        case avatarImage = "avatar_image"
        case createdAt = "created_at"
    }
}

nonisolated struct GameInvite: Codable, Identifiable, Sendable {
    let id: String?
    let gameId: String
    let senderId: String
    let receiverId: String
    var status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case gameId = "game_id"
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case status
        case createdAt = "created_at"
    }
}

nonisolated struct SerializedGameState: Codable, Sendable {
    var wall: [MahjongTile]
    var players: [SerializedPlayer]
    var discardPile: [MahjongTile]
    var discardPlayerMap: [String: String]
    var currentPlayerIndex: Int
    var gameStatus: String
    var charlestonPhase: Int
    var charlestonComplete: Bool
    var charlestonPendingPasses: [String: [MahjongTile]]?
    var courtesyTileCount: Int?
    var showCourtesyOptions: Bool?
    var courtesyCurrentSeat: Int?
    var showStopCharlestonOption: Bool?
    var lastDiscardedTile: MahjongTile?
    var lastDiscardPlayerIndex: Int?
    var hasDrawnThisTurn: Bool
    var isWallGame: Bool
    var showEndGameOverlay: Bool
    var winnerName: String
    var showMahjongAnimation: Bool?
    var winningHandName: String?
    var winningHandCategory: String?
    var winningHandPoints: Int?
    var gameMessage: String
    var selectedCardYear: String
    var callWindow: CallWindowState?
    /// Per-discard human call responses. Keyed by seat index (as String). Values:
    /// "skip" (player explicitly passed or had no calls available) or "called".
    /// Cleared whenever `lastDiscardedTile` changes.
    var callResponses: [String: String]?
    /// The discard id that `callResponses` corresponds to. When `lastDiscardedTile.id`
    /// no longer matches this, responses are stale and reset.
    var callResponseDiscardId: String?
}

nonisolated struct SerializedPlayer: Codable, Sendable {
    var displayName: String
    var avatarImage: String
    var seatPosition: String
    var hand: [MahjongTile]
    var exposedSets: [[MahjongTile]]
    var score: Int
    var isBot: Bool
    var userId: String?
}

nonisolated struct CallWindowState: Codable, Sendable {
    var active: Bool
    var discardedTile: MahjongTile?
    var discardedByIndex: Int
    var responses: [String: String]
    var expectedResponders: [String]
    var bestCallType: String?
    var bestCallPlayerIndex: Int?
}

nonisolated enum OnlineGameStatus: String, Sendable {
    case waiting = "waiting"
    case charleston = "charleston"
    case playing = "playing"
    case completed = "completed"
}

nonisolated enum InviteStatus: String, Sendable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
}

nonisolated struct CharlestonPassRow: Codable, Sendable {
    let gameId: String
    let seatIndex: Int
    let phase: Int
    let userId: String
    let tiles: [MahjongTile]
    let handAfter: [MahjongTile]
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case seatIndex = "seat_index"
        case phase
        case userId = "user_id"
        case tiles
        case handAfter = "hand_after"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One row of the append-only `game_actions` log. Used as a durable
/// wake-up signal so dropped realtime broadcasts can't strand any seat.
/// Payload is intentionally not decoded — we only need the metadata to
/// know we missed an action and pull the latest `online_games` row.
nonisolated struct GameActionRow: Codable, Sendable {
    let gameId: String
    let seq: Int64
    let seat: Int
    let kind: String

    enum CodingKeys: String, CodingKey {
        case gameId = "game_id"
        case seq
        case seat
        case kind
    }
}

nonisolated struct OnlineGameSummary: Identifiable, Sendable {
    let id: String
    let game: OnlineGame
    let participants: [GameParticipant]
    let isMyTurn: Bool
    let myUserId: String
}
