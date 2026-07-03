import Foundation

nonisolated struct PlayerProfile: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    var displayName: String
    var avatarImage: String
    var email: String
    var level: Int
    var xp: Int
    var totalWins: Int
    var totalGames: Int
    var currentStreak: Int
    var joinDate: Date
    var bestStreak: Int
    var selectedThemeId: String
    var unlockedThemes: [String]
    var unlockedTileSets: [String]
    var unlockedAchievements: [String: UnlockedAchievementData]
    var settingsData: ProfileSettings

    init(
        id: UUID = UUID(),
        displayName: String = "Garden Guest",
        avatarImage: String = "daffodil",
        email: String = "",
        level: Int = 1,
        xp: Int = 0,
        totalWins: Int = 0,
        totalGames: Int = 0,
        currentStreak: Int = 0,
        bestStreak: Int = 0,
        joinDate: Date = Date(),
        selectedThemeId: String = "garden_party",
        unlockedThemes: [String] = ["garden_party"],
        unlockedTileSets: [String] = ["classic"],
        unlockedAchievements: [String: UnlockedAchievementData] = [:],
        settingsData: ProfileSettings = ProfileSettings()
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarImage = avatarImage
        self.email = email
        self.level = level
        self.xp = xp
        self.totalWins = totalWins
        self.totalGames = totalGames
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.joinDate = joinDate
        self.selectedThemeId = selectedThemeId
        self.unlockedThemes = unlockedThemes
        self.unlockedTileSets = unlockedTileSets
        self.unlockedAchievements = unlockedAchievements
        self.settingsData = settingsData
    }

    var winRate: Double {
        guard totalGames > 0 else { return 0 }
        return Double(totalWins) / Double(totalGames) * 100
    }

    var xpForNextLevel: Int {
        level * 500
    }

    var levelProgress: Double {
        Double(xp) / Double(xpForNextLevel)
    }
}

nonisolated struct GamePlayer: Identifiable, Sendable {
    let id: UUID
    let profile: PlayerProfile
    var hand: [MahjongTile]
    var exposedSets: [[MahjongTile]]
    var score: Int
    var seatPosition: SeatPosition
    var isCurrentTurn: Bool
    var isBot: Bool
    var charlestonSelections: Set<UUID> = []
    var targetHand: NMJLHand?

    init(
        id: UUID = UUID(),
        profile: PlayerProfile,
        hand: [MahjongTile] = [],
        exposedSets: [[MahjongTile]] = [],
        score: Int = 0,
        seatPosition: SeatPosition = .east,
        isCurrentTurn: Bool = false,
        isBot: Bool = false,
        targetHand: NMJLHand? = nil
    ) {
        self.id = id
        self.profile = profile
        self.hand = hand
        self.exposedSets = exposedSets
        self.score = score
        self.seatPosition = seatPosition
        self.isCurrentTurn = isCurrentTurn
        self.isBot = isBot
        self.targetHand = targetHand
    }
}

nonisolated enum SeatPosition: String, CaseIterable, Sendable {
    case east = "East"
    case south = "South"
    case west = "West"
    case north = "North"

    var symbolName: String {
        switch self {
        case .east: return "sunrise.fill"
        case .south: return "sun.max.fill"
        case .west: return "sunset.fill"
        case .north: return "moon.stars.fill"
        }
    }
}
