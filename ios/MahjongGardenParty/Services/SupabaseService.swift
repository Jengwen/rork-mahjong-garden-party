import Foundation
import Supabase

@MainActor
@Observable
class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    var isAuthenticated: Bool = false
    var currentUserId: UUID?
    var isLoading: Bool = false
    var errorMessage: String?
    var lastError: String?

    private static let supabaseURL = "https://nzfrxpnksrqcqxphtdye.supabase.co"
    private static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im56ZnJ4cG5rc3JxY3F4cGh0ZHllIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4OTY4MzQsImV4cCI6MjA5MDQ3MjgzNH0.Te92nt173H8t4nIGBnDMgBWSV-pIGNKzD-BlNx4iNJ8"

    private var knownMissingTables: Set<String> = []

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Self.supabaseURL)!,
            supabaseKey: Self.supabaseAnonKey
        )
    }

    var isConfigured: Bool {
        true
    }

    // MARK: - Auth

    func signUpWithEmail(_ email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let response = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
        currentUserId = response.user.id
        isAuthenticated = true

        try await createInitialProfile(userId: response.user.id.uuidString.lowercased(), displayName: displayName, email: email)
    }

    func signInWithEmail(_ email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        currentUserId = session.user.id
        isAuthenticated = true
    }

    func signOut() async throws {
        try await client.auth.signOut()
        currentUserId = nil
        isAuthenticated = false
        knownMissingTables = []
    }

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            currentUserId = session.user.id
            isAuthenticated = true
        } catch {
            isAuthenticated = false
            currentUserId = nil
        }
    }

    func getCurrentUserEmail() async -> String? {
        do {
            let session = try await client.auth.session
            return session.user.email
        } catch {
            return nil
        }
    }

    func resetPassword(for email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - Player Profiles

    private func createInitialProfile(userId: String, displayName: String, email: String) async throws {
        nonisolated struct InitialProfile: Codable, Sendable {
            let userId: String
            let displayName: String
            let avatarImage: String
            let email: String
            let selectedThemeId: String
            let settingsData: ProfileSettings

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case displayName = "display_name"
                case avatarImage = "avatar_image"
                case email
                case selectedThemeId = "selected_theme_id"
                case settingsData = "settings_data"
            }
        }

        let profile = InitialProfile(
            userId: userId,
            displayName: displayName,
            avatarImage: "daffodil",
            email: email,
            selectedThemeId: "garden_party",
            settingsData: ProfileSettings()
        )
        do {
            try await client
                .from("player_profiles")
                .insert(profile)
                .execute()
        } catch {
            logError("createInitialProfile", error)
        }
    }

    func fetchPlayerProfile() async throws -> SupabasePlayerProfile? {
        guard let userId = currentUserId else { return nil }

        let response: [SupabasePlayerProfile] = try await client
            .from("player_profiles")
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .execute()
            .value

        return response.first
    }

    func upsertPlayerProfile(_ profile: SupabasePlayerProfile) async throws {
        do {
            try await client
                .from("player_profiles")
                .upsert(profile)
                .execute()
        } catch {
            let errorStr = "\(error)"
            if errorStr.contains("best_streak") || errorStr.contains("unlocked_achievements") || errorStr.contains("column") {
                try await upsertProfileCoreFields(profile)
            } else {
                throw error
            }
        }
    }

    private func upsertProfileCoreFields(_ profile: SupabasePlayerProfile) async throws {
        nonisolated struct CoreProfile: Codable, Sendable {
            let userId: String
            var displayName: String
            var avatarImage: String
            var email: String
            var level: Int
            var xp: Int
            var totalWins: Int
            var totalGames: Int
            var currentStreak: Int
            var selectedThemeId: String
            var unlockedThemes: [String]
            var unlockedTileSets: [String]
            var settingsData: ProfileSettings

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case displayName = "display_name"
                case avatarImage = "avatar_image"
                case email
                case level
                case xp
                case totalWins = "total_wins"
                case totalGames = "total_games"
                case currentStreak = "current_streak"
                case selectedThemeId = "selected_theme_id"
                case unlockedThemes = "unlocked_themes"
                case unlockedTileSets = "unlocked_tile_sets"
                case settingsData = "settings_data"
            }
        }

        let core = CoreProfile(
            userId: profile.userId,
            displayName: profile.displayName,
            avatarImage: profile.avatarImage,
            email: profile.email,
            level: profile.level,
            xp: profile.xp,
            totalWins: profile.totalWins,
            totalGames: profile.totalGames,
            currentStreak: profile.currentStreak,
            selectedThemeId: profile.selectedThemeId,
            unlockedThemes: profile.unlockedThemes,
            unlockedTileSets: profile.unlockedTileSets,
            settingsData: profile.settingsData
        )

        try await client
            .from("player_profiles")
            .upsert(core)
            .execute()
    }

    // MARK: - Game History

    func saveGameResult(_ result: SupabaseGameResult) async throws {
        try await client
            .from("game_results")
            .insert(result)
            .execute()
    }

    func fetchGameHistory(limit: Int = 20) async throws -> [SupabaseGameResult] {
        guard let userId = currentUserId else { return [] }

        let response: [SupabaseGameResult] = try await client
            .from("game_results")
            .select()
            .eq("user_id", value: userId.uuidString.lowercased())
            .order("played_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    // MARK: - Leaderboard

    func fetchLeaderboard(limit: Int = 50) async throws -> [SupabaseLeaderboardEntry] {
        // Reads go through the `public_player_profiles` view (public display
        // columns only) — the base table is own-row-only under RLS so other
        // players' private columns (email, settings) never leave the server.
        // Explicit column list also stops shipping 50 rows of unneeded blobs.
        let response: [SupabaseLeaderboardEntry] = try await client
            .from("public_player_profiles")
            .select("user_id,display_name,avatar_image,level,total_wins,total_games")
            .order("total_wins", ascending: false)
            .limit(limit)
            .execute()
            .value

        return response
    }

    // MARK: - Friendships

    func sendFriendRequest(to friendId: String) async throws {
        guard let userId = currentUserId else {
            throw DatabaseError.notAuthenticated
        }
        knownMissingTables.remove("friendships")
        nonisolated struct FriendshipInsert: Codable, Sendable {
            let userId: String
            let friendId: String
            let status: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case friendId = "friend_id"
                case status
            }
        }
        let insert = FriendshipInsert(
            userId: userId.uuidString.lowercased(),
            friendId: friendId,
            status: FriendshipStatus.pending.rawValue
        )
        do {
            try await client
                .from("friendships")
                .insert(insert)
                .execute()
        } catch {
            markTableMissingIfNeeded("friendships", error: error)
            throw error
        }
    }

    func acceptFriendRequest(friendshipId: String) async throws {
        knownMissingTables.remove("friendships")
        do {
            try await client
                .from("friendships")
                .update(["status": FriendshipStatus.accepted.rawValue])
                .eq("id", value: friendshipId)
                .execute()
        } catch {
            markTableMissingIfNeeded("friendships", error: error)
            throw error
        }
    }

    func removeFriend(friendshipId: String) async throws {
        knownMissingTables.remove("friendships")
        do {
            try await client
                .from("friendships")
                .delete()
                .eq("id", value: friendshipId)
                .execute()
        } catch {
            markTableMissingIfNeeded("friendships", error: error)
            throw error
        }
    }

    func fetchFriendships() async throws -> [Friendship] {
        guard let userId = currentUserId else { return [] }
        knownMissingTables.remove("friendships")
        do {
            let sent: [Friendship] = try await client
                .from("friendships")
                .select()
                .eq("user_id", value: userId.uuidString.lowercased())
                .execute()
                .value
            let received: [Friendship] = try await client
                .from("friendships")
                .select()
                .eq("friend_id", value: userId.uuidString.lowercased())
                .execute()
                .value
            return sent + received
        } catch {
            markTableMissingIfNeeded("friendships", error: error)
            throw error
        }
    }

    func fetchFriendProfile(userId: String) async throws -> FriendProfile? {
        // Other players' profiles come from the public view — base-table RLS
        // is own-row-only, and the view carries no private columns.
        let response: [FriendProfile] = try await client
            .from("public_player_profiles")
            .select("user_id,display_name,avatar_image,level,total_wins,total_games")
            .eq("user_id", value: userId)
            .execute()
            .value
        return response.first
    }

    func searchPlayers(query: String) async throws -> [FriendProfile] {
        guard let userId = currentUserId else { return [] }
        let response: [FriendProfile] = try await client
            .from("public_player_profiles")
            .select("user_id,display_name,avatar_image,level,total_wins,total_games")
            .ilike("display_name", pattern: "%\(query)%")
            .neq("user_id", value: userId.uuidString.lowercased())
            .limit(20)
            .execute()
            .value
        return response
    }

    // MARK: - Messages

    func sendMessage(to receiverId: String, content: String) async throws {
        guard let userId = currentUserId else {
            throw DatabaseError.notAuthenticated
        }
        knownMissingTables.remove("messages")
        nonisolated struct MessageInsert: Codable, Sendable {
            let senderId: String
            let receiverId: String
            let content: String
            let isRead: Bool
            enum CodingKeys: String, CodingKey {
                case senderId = "sender_id"
                case receiverId = "receiver_id"
                case content
                case isRead = "is_read"
            }
        }
        let insert = MessageInsert(
            senderId: userId.uuidString.lowercased(),
            receiverId: receiverId,
            content: content,
            isRead: false
        )
        do {
            try await client
                .from("messages")
                .insert(insert)
                .execute()
        } catch {
            markTableMissingIfNeeded("messages", error: error)
            throw error
        }
    }

    func fetchMessages(with friendId: String) async throws -> [DirectMessage] {
        guard let userId = currentUserId else { return [] }
        knownMissingTables.remove("messages")
        do {
            let sent: [DirectMessage] = try await client
                .from("messages")
                .select()
                .eq("sender_id", value: userId.uuidString.lowercased())
                .eq("receiver_id", value: friendId)
                .order("created_at", ascending: true)
                .execute()
                .value
            let received: [DirectMessage] = try await client
                .from("messages")
                .select()
                .eq("sender_id", value: friendId)
                .eq("receiver_id", value: userId.uuidString.lowercased())
                .order("created_at", ascending: true)
                .execute()
                .value
            return (sent + received).sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        } catch {
            markTableMissingIfNeeded("messages", error: error)
            throw error
        }
    }

    func deleteMessage(messageId: String) async throws {
        guard let userId = currentUserId else {
            throw DatabaseError.notAuthenticated
        }
        do {
            // Permanently delete the row. Constrained to messages the current user sent
            // so RLS-compatible policies still pass.
            try await client
                .from("messages")
                .delete()
                .eq("id", value: messageId)
                .eq("sender_id", value: userId.uuidString.lowercased())
                .execute()
        } catch {
            markTableMissingIfNeeded("messages", error: error)
            throw error
        }
    }

    func messageExists(messageId: String) async throws -> Bool {
        do {
            let rows: [DirectMessage] = try await client
                .from("messages")
                .select()
                .eq("id", value: messageId)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            markTableMissingIfNeeded("messages", error: error)
            throw error
        }
    }

    func markMessagesAsRead(from senderId: String) async throws {
        guard let userId = currentUserId else { return }
        do {
            try await client
                .from("messages")
                .update(["is_read": true])
                .eq("sender_id", value: senderId)
                .eq("receiver_id", value: userId.uuidString.lowercased())
                .eq("is_read", value: false)
                .execute()
        } catch {
            markTableMissingIfNeeded("messages", error: error)
        }
    }

    func fetchUnreadCounts() async throws -> [String: Int] {
        guard let userId = currentUserId else { return [:] }
        // Only the sender_id column — this previously downloaded every unread
        // message in full (including content) just to count per sender.
        nonisolated struct SenderRow: Codable, Sendable {
            let senderId: String
            enum CodingKeys: String, CodingKey { case senderId = "sender_id" }
        }
        do {
            let rows: [SenderRow] = try await client
                .from("messages")
                .select("sender_id")
                .eq("receiver_id", value: userId.uuidString.lowercased())
                .eq("is_read", value: false)
                .execute()
                .value
            var counts: [String: Int] = [:]
            for row in rows {
                counts[row.senderId, default: 0] += 1
            }
            return counts
        } catch {
            markTableMissingIfNeeded("messages", error: error)
            return [:]
        }
    }

    // MARK: - Connection Test

    func testConnection() async -> (success: Bool, message: String) {
        guard isConfigured else {
            return (false, "Supabase not configured. Missing URL or API key.")
        }

        do {
            let _: [SupabasePlayerProfile] = try await client
                .from("player_profiles")
                .select()
                .limit(1)
                .execute()
                .value
            return (true, "Connected to Supabase successfully!")
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    func checkDatabaseSetup() async -> DatabaseStatus {
        var status = DatabaseStatus()

        do {
            let _: [SupabasePlayerProfile] = try await client
                .from("player_profiles")
                .select()
                .limit(1)
                .execute()
                .value
            status.playerProfilesExists = true
        } catch {
            status.playerProfilesExists = false
        }

        do {
            let _: [SupabaseGameResult] = try await client
                .from("game_results")
                .select()
                .limit(1)
                .execute()
                .value
            status.gameResultsExists = true
        } catch {
            status.gameResultsExists = false
        }

        do {
            let _: [Friendship] = try await client
                .from("friendships")
                .select()
                .limit(1)
                .execute()
                .value
            status.friendshipsExists = true
        } catch {
            let errorStr = "\(error)"
            if errorStr.contains("PGRST205") || errorStr.contains("Could not find the table") {
                status.friendshipsExists = false
                knownMissingTables.insert("friendships")
            }
        }

        do {
            let _: [DirectMessage] = try await client
                .from("messages")
                .select()
                .limit(1)
                .execute()
                .value
            status.messagesExists = true
        } catch {
            let errorStr = "\(error)"
            if errorStr.contains("PGRST205") || errorStr.contains("Could not find the table") {
                status.messagesExists = false
                knownMissingTables.insert("messages")
            }
        }

        return status
    }

    // MARK: - Push Token

    func savePushToken(_ token: String) async {
        guard let userId = currentUserId else { return }
        nonisolated struct PushTokenInsert: Codable, Sendable {
            let userId: String
            let token: String
            let platform: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case token
                case platform
            }
        }
        let insert = PushTokenInsert(
            userId: userId.uuidString.lowercased(),
            token: token,
            platform: "ios"
        )
        do {
            try await client
                .from("push_tokens")
                .upsert(insert)
                .execute()
        } catch {
            print("⚠️ savePushToken: \(error)")
        }
    }

    // MARK: - Helpers

    private func checkTableAvailable(_ table: String) throws {
        if knownMissingTables.contains(table) {
            throw DatabaseError.tableMissing(table)
        }
    }

    private func markTableMissingIfNeeded(_ table: String, error: Error) {
        let errorStr = "\(error)"
        if errorStr.contains("PGRST205") || errorStr.contains("Could not find the table") {
            knownMissingTables.insert(table)
        }
    }

    private func logError(_ context: String, _ error: Error) {
        lastError = "[\(context)] \(error.localizedDescription)"
        print("⚠️ SupabaseService.\(context): \(error)")
    }
}

struct DatabaseStatus {
    var playerProfilesExists: Bool = false
    var gameResultsExists: Bool = false
    var friendshipsExists: Bool = false
    var messagesExists: Bool = false

    var allTablesExist: Bool {
        playerProfilesExists && gameResultsExists && friendshipsExists && messagesExists
    }

    var missingTables: [String] {
        var missing: [String] = []
        if !playerProfilesExists { missing.append("player_profiles") }
        if !gameResultsExists { missing.append("game_results") }
        if !friendshipsExists { missing.append("friendships") }
        if !messagesExists { missing.append("messages") }
        return missing
    }
}

nonisolated enum DatabaseError: LocalizedError, Sendable {
    case notAuthenticated
    case tableMissing(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to perform this action."
        case .tableMissing(let table):
            return "The '\(table)' table has not been created in the database yet. Please set up the database tables in your Supabase dashboard."
        }
    }
}
