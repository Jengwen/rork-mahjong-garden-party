import Foundation

nonisolated struct Friendship: Codable, Identifiable, Sendable {
    let id: String?
    let userId: String
    let friendId: String
    let status: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case friendId = "friend_id"
        case status
        case createdAt = "created_at"
    }
}

nonisolated enum FriendshipStatus: String, Codable, Sendable {
    case pending = "pending"
    case accepted = "accepted"
    case blocked = "blocked"
}

nonisolated struct DirectMessage: Codable, Identifiable, Sendable {
    let id: String?
    let senderId: String
    let receiverId: String
    let content: String
    let isRead: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case senderId = "sender_id"
        case receiverId = "receiver_id"
        case content
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

nonisolated struct FriendProfile: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let avatarImage: String
    let level: Int
    let totalWins: Int
    let totalGames: Int

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case displayName = "display_name"
        case avatarImage = "avatar_image"
        case level
        case totalWins = "total_wins"
        case totalGames = "total_games"
    }
}

struct FriendWithProfile: Identifiable {
    let id: String
    let friendship: Friendship
    let profile: FriendProfile
    var lastMessage: DirectMessage?
    var unreadCount: Int

    var isOnline: Bool {
        [true, false, false].randomElement() ?? false
    }
}

struct Conversation: Identifiable {
    let id: String
    let friend: FriendProfile
    var messages: [DirectMessage]
    var unreadCount: Int

    var lastMessage: DirectMessage? {
        messages.last
    }
}
