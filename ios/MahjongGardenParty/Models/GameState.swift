import Foundation

nonisolated enum GameMode: String, CaseIterable, Sendable {
    case solo = "Solo Practice"
    case multiplayer = "Multiplayer"
    case async = "Turn-Based"
}

nonisolated enum GameStatus: String, Sendable {
    case waiting = "Waiting"
    case charleston = "Charleston"
    case playing = "Playing"
    case completed = "Completed"
}

nonisolated enum CharlestonDirection: String, Sendable {
    case right = "Pass Right"
    case across = "Pass Across"
    case left = "Pass Left"
    case courtesyAcross = "Courtesy Pass"

    var systemImage: String {
        switch self {
        case .right: return "arrow.right"
        case .across: return "arrow.up"
        case .left: return "arrow.left"
        case .courtesyAcross: return "arrow.up.arrow.down"
        }
    }
}

nonisolated enum CharlestonPhase: Int, Sendable {
    case firstRight = 0
    case firstAcross = 1
    case firstLeft = 2
    case secondLeft = 3
    case secondAcross = 4
    case secondRight = 5
    case courtesyPass = 6

    var direction: CharlestonDirection {
        switch self {
        case .firstRight, .secondRight: return .right
        case .firstAcross, .secondAcross: return .across
        case .firstLeft, .secondLeft: return .left
        case .courtesyPass: return .courtesyAcross
        }
    }

    var displayName: String {
        switch self {
        case .firstRight: return "1st Charleston: Pass Right"
        case .firstAcross: return "1st Charleston: Pass Across"
        case .firstLeft: return "1st Charleston: Pass Left"
        case .secondLeft: return "2nd Charleston: Pass Left"
        case .secondAcross: return "2nd Charleston: Pass Across"
        case .secondRight: return "2nd Charleston: Pass Right"
        case .courtesyPass: return "Courtesy Pass"
        }
    }

    var isFirstCharleston: Bool { rawValue <= 2 }
    var isSecondCharleston: Bool { rawValue >= 3 && rawValue <= 5 }
    var isCourtesy: Bool { self == .courtesyPass }

    var stepInGroup: Int {
        switch self {
        case .firstRight, .secondLeft: return 0
        case .firstAcross, .secondAcross: return 1
        case .firstLeft, .secondRight: return 2
        case .courtesyPass: return 0
        }
    }

    var totalSteps: Int {
        if isCourtesy { return 1 }
        return 3
    }

    var groupLabel: String {
        if isFirstCharleston { return "1st Charleston" }
        if isSecondCharleston { return "2nd Charleston" }
        return "Courtesy Pass"
    }
}

nonisolated enum CallType: String, Sendable {
    case pung = "Pung"
    case kong = "Kong"
    case quint = "Quint"
    case mahjong = "Mahjong!"
}

nonisolated enum MoveType: String, Sendable {
    case draw
    case discard
    case pung
    case kong
    case chow
    case mahjong
    case charleston
    case jokerSwap
}

nonisolated struct GameMove: Identifiable, Sendable {
    let id: UUID
    let playerId: UUID
    let moveType: MoveType
    let tiles: [MahjongTile]
    let timestamp: Date

    init(id: UUID = UUID(), playerId: UUID, moveType: MoveType, tiles: [MahjongTile], timestamp: Date = Date()) {
        self.id = id
        self.playerId = playerId
        self.moveType = moveType
        self.tiles = tiles
        self.timestamp = timestamp
    }
}

nonisolated struct UnlockedAchievementData: Codable, Sendable, Hashable {
    let unlockedDate: Date
    var progress: Double
}

nonisolated struct Achievement: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let targetValue: Double

    var isUnlocked: Bool = false
    var unlockedDate: Date?
    var progress: Double = 0

    static let allAchievements: [Achievement] = [
        Achievement(id: "first_win", title: "First Bloom", description: "Win your first game", iconName: "trophy.fill", targetValue: 1),
        Achievement(id: "win_streak_3", title: "Garden Streak", description: "Win 3 games in a row", iconName: "flame.fill", targetValue: 3),
        Achievement(id: "win_streak_5", title: "Blossom Streak", description: "Win 5 games in a row", iconName: "sparkles", targetValue: 5),
        Achievement(id: "games_10", title: "Regular Guest", description: "Play 10 games", iconName: "person.2.fill", targetValue: 10),
        Achievement(id: "games_50", title: "Garden Regular", description: "Play 50 games", iconName: "laurel.leading", targetValue: 50),
        Achievement(id: "first_mahjong", title: "Mahjong!", description: "Declare your first Mahjong", iconName: "star.fill", targetValue: 1),
        Achievement(id: "host_party", title: "Party Host", description: "Host your first Garden Party", iconName: "party.popper.fill", targetValue: 1),
        Achievement(id: "collector", title: "Tile Collector", description: "Unlock 3 tile sets", iconName: "square.grid.3x3.fill", targetValue: 3),
        Achievement(id: "wins_10", title: "Winning Garden", description: "Win 10 games", iconName: "medal.fill", targetValue: 10),
        Achievement(id: "wins_25", title: "Master Gardener", description: "Win 25 games", iconName: "crown.fill", targetValue: 25),
    ]

    func withProgress(current: Double, unlocked: UnlockedAchievementData?) -> Achievement {
        var copy = self
        if let unlocked {
            copy.isUnlocked = true
            copy.unlockedDate = unlocked.unlockedDate
            copy.progress = 1.0
        } else {
            copy.progress = min(current / targetValue, 1.0)
        }
        return copy
    }
}

nonisolated struct DailyReward: Identifiable, Sendable {
    let id: Int
    let day: Int
    let xpReward: Int
    let description: String
    var isClaimed: Bool
}

nonisolated struct DailyRewardTracker: Codable, Sendable {
    var claimedDates: [String]
    var currentStreakDay: Int
    var lastClaimDate: String?

    init(claimedDates: [String] = [], currentStreakDay: Int = 0, lastClaimDate: String? = nil) {
        self.claimedDates = claimedDates
        self.currentStreakDay = currentStreakDay
        self.lastClaimDate = lastClaimDate
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    static func todayString() -> String {
        dateFormatter.string(from: Date())
    }

    static func yesterdayString() -> String {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        return dateFormatter.string(from: yesterday)
    }

    var hasClaimedToday: Bool {
        lastClaimDate == Self.todayString()
    }

    var effectiveStreakDay: Int {
        guard let last = lastClaimDate else { return 0 }
        let today = Self.todayString()
        let yesterday = Self.yesterdayString()
        if last == today || last == yesterday {
            return currentStreakDay
        }
        return 0
    }

    var nextRewardDay: Int {
        let streak = effectiveStreakDay
        if hasClaimedToday {
            return min(streak + 1, 7)
        }
        if streak == 0 {
            return 1
        }
        return min(streak + 1, 7)
    }

    var xpForNextReward: Int {
        nextRewardDay * 25
    }

    mutating func claim() {
        let today = Self.todayString()
        guard !hasClaimedToday else { return }

        let streak = effectiveStreakDay
        if streak >= 7 {
            currentStreakDay = 1
        } else {
            currentStreakDay = streak + 1
        }

        lastClaimDate = today
        if !claimedDates.contains(today) {
            claimedDates.append(today)
        }
        if claimedDates.count > 30 {
            claimedDates = Array(claimedDates.suffix(30))
        }
    }
}
