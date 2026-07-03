import Foundation

nonisolated struct SupabasePlayerProfile: Codable, Sendable {
    let userId: String
    var displayName: String
    var avatarImage: String
    var email: String
    var level: Int
    var xp: Int
    var totalWins: Int
    var totalGames: Int
    var currentStreak: Int
    var bestStreak: Int
    var selectedThemeId: String
    var unlockedThemes: [String]
    var unlockedTileSets: [String]
    var unlockedAchievements: [String: UnlockedAchievementData]
    var settingsData: ProfileSettings
    let createdAt: String?
    var updatedAt: String?

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
        case bestStreak = "best_streak"
        case selectedThemeId = "selected_theme_id"
        case unlockedThemes = "unlocked_themes"
        case unlockedTileSets = "unlocked_tile_sets"
        case unlockedAchievements = "unlocked_achievements"
        case settingsData = "settings_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarImage = try container.decodeIfPresent(String.self, forKey: .avatarImage) ?? "daffodil"
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        xp = try container.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        totalWins = try container.decodeIfPresent(Int.self, forKey: .totalWins) ?? 0
        totalGames = try container.decodeIfPresent(Int.self, forKey: .totalGames) ?? 0
        currentStreak = try container.decodeIfPresent(Int.self, forKey: .currentStreak) ?? 0
        bestStreak = try container.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        selectedThemeId = try container.decodeIfPresent(String.self, forKey: .selectedThemeId) ?? "garden_party"
        unlockedThemes = try container.decodeIfPresent([String].self, forKey: .unlockedThemes) ?? ["garden_party"]
        unlockedTileSets = try container.decodeIfPresent([String].self, forKey: .unlockedTileSets) ?? ["classic"]
        unlockedAchievements = try container.decodeIfPresent([String: UnlockedAchievementData].self, forKey: .unlockedAchievements) ?? [:]
        settingsData = try container.decodeIfPresent(ProfileSettings.self, forKey: .settingsData) ?? ProfileSettings()
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    init(from profile: PlayerProfile, userId: String) {
        self.userId = userId
        self.displayName = profile.displayName
        self.avatarImage = profile.avatarImage
        self.email = profile.email
        self.level = profile.level
        self.xp = profile.xp
        self.totalWins = profile.totalWins
        self.totalGames = profile.totalGames
        self.currentStreak = profile.currentStreak
        self.bestStreak = profile.bestStreak
        self.selectedThemeId = profile.selectedThemeId
        self.unlockedThemes = profile.unlockedThemes
        self.unlockedTileSets = profile.unlockedTileSets
        self.unlockedAchievements = profile.unlockedAchievements
        self.settingsData = profile.settingsData
        self.createdAt = nil
        self.updatedAt = nil
    }

    func toPlayerProfile() -> PlayerProfile {
        PlayerProfile(
            displayName: displayName,
            avatarImage: avatarImage,
            email: email,
            level: level,
            xp: xp,
            totalWins: totalWins,
            totalGames: totalGames,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            selectedThemeId: selectedThemeId,
            unlockedThemes: unlockedThemes,
            unlockedTileSets: unlockedTileSets,
            unlockedAchievements: unlockedAchievements,
            settingsData: settingsData
        )
    }
}

nonisolated struct SupabaseGameResult: Codable, Sendable {
    let id: String?
    let userId: String
    let result: String
    let score: Int
    let opponentNames: [String]
    let gameMode: String
    let playedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case result
        case score
        case opponentNames = "opponent_names"
        case gameMode = "game_mode"
        case playedAt = "played_at"
    }
}

nonisolated struct SupabaseLeaderboardEntry: Codable, Sendable {
    let userId: String
    let displayName: String
    let avatarImage: String
    let level: Int
    let totalWins: Int
    let totalGames: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarImage = "avatar_image"
        case level
        case totalWins = "total_wins"
        case totalGames = "total_games"
    }
}
