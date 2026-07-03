import SwiftUI

@Observable
@MainActor
class AppViewModel {
    var playerProfile: PlayerProfile = PlayerProfile()
    var hasCompletedOnboarding: Bool = false
    var dailyRewardTracker: DailyRewardTracker = DailyRewardTracker()
    var showDailyReward: Bool = false
    var notifications: [GameNotification] = []
    var isAuthenticated: Bool = false
    var isCheckingAuth: Bool = true
    var databaseStatus: DatabaseStatus?
    var syncError: String?
    var passwordResetSent: Bool = false
    var passwordResetError: String?
    weak var settingsManagerRef: SettingsManager?

    private let supabase = SupabaseService.shared
    private static let dailyRewardKey = "saved_daily_reward_tracker"

    var dailyRewardClaimed: Bool {
        dailyRewardTracker.hasClaimedToday
    }

    var dailyRewards: [DailyReward] {
        let streak = dailyRewardTracker.effectiveStreakDay
        return (1...7).map { day in
            DailyReward(
                id: day,
                day: day,
                xpReward: day * 25,
                description: day == 7 ? "Bonus Theme Preview" : "+\(day * 25) XP",
                isClaimed: day <= streak
            )
        }
    }

    var recentMatches: [RecentMatch] = []

    private static let matchesKey = "saved_recent_matches"
    private static let profileKey = "saved_player_profile"

    func loadLocalMatches() {
        guard let data = UserDefaults.standard.data(forKey: Self.matchesKey),
              let saved = try? JSONDecoder().decode([RecentMatch].self, from: data) else { return }
        recentMatches = saved
    }

    private func saveLocalMatches() {
        if let data = try? JSONEncoder().encode(recentMatches) {
            UserDefaults.standard.set(data, forKey: Self.matchesKey)
        }
    }

    private func saveProfileLocally() {
        if let data = try? JSONEncoder().encode(playerProfile) {
            UserDefaults.standard.set(data, forKey: Self.profileKey)
        }
    }

    private func loadLocalProfile() {
        guard let data = UserDefaults.standard.data(forKey: Self.profileKey),
              let saved = try? JSONDecoder().decode(PlayerProfile.self, from: data) else { return }
        playerProfile = saved
    }

    func recordGameResult(opponents: [String], result: MatchResult, score: Int, gameMode: String, winningHandName: String?) {
        let match = RecentMatch(
            id: UUID(),
            opponentNames: opponents,
            result: result,
            score: score,
            date: Date(),
            gameMode: gameMode,
            winningHandName: winningHandName
        )
        recentMatches.insert(match, at: 0)
        if recentMatches.count > 50 {
            recentMatches = Array(recentMatches.prefix(50))
        }
        saveLocalMatches()

        playerProfile.totalGames += 1
        if result == .win {
            playerProfile.totalWins += 1
            playerProfile.currentStreak += 1
            if playerProfile.currentStreak > playerProfile.bestStreak {
                playerProfile.bestStreak = playerProfile.currentStreak
            }
            addXP(100)
        } else {
            playerProfile.currentStreak = 0
            addXP(25)
        }

        evaluateAchievements(didWin: result == .win, declaredMahjong: result == .win)
        saveProfileLocally()

        Task {
            await saveGameResult(
                result: result.rawValue,
                score: score,
                opponents: opponents,
                mode: gameMode
            )
            await syncProfileToSupabase()
        }
    }

    func loadMatchesFromSupabase() async {
        do {
            let results = try await supabase.fetchGameHistory(limit: 50)
            let mapped = results.map { r in
                RecentMatch(
                    id: UUID(),
                    opponentNames: r.opponentNames,
                    result: MatchResult(rawValue: r.result) ?? .loss,
                    score: r.score,
                    date: ISO8601DateFormatter().date(from: r.playedAt ?? "") ?? Date(),
                    gameMode: r.gameMode,
                    winningHandName: nil
                )
            }
            if !mapped.isEmpty {
                recentMatches = mapped
                saveLocalMatches()
            }
        } catch {
            print("⚠️ Failed to load matches from Supabase: \(error)")
        }
    }

    func claimDailyReward() {
        guard !dailyRewardTracker.hasClaimedToday else { return }
        let xpAmount = dailyRewardTracker.xpForNextReward
        dailyRewardTracker.claim()
        saveDailyRewardTracker()
        addXP(xpAmount)
        showDailyReward = false
    }

    private func saveDailyRewardTracker() {
        if let data = try? JSONEncoder().encode(dailyRewardTracker) {
            UserDefaults.standard.set(data, forKey: Self.dailyRewardKey)
        }
    }

    private func loadDailyRewardTracker() {
        guard let data = UserDefaults.standard.data(forKey: Self.dailyRewardKey),
              let saved = try? JSONDecoder().decode(DailyRewardTracker.self, from: data) else { return }
        dailyRewardTracker = saved
    }

    func evaluateAchievements(didWin: Bool = false, declaredMahjong: Bool = false) {
        let now = Date()

        func unlock(_ id: String) {
            guard playerProfile.unlockedAchievements[id] == nil else { return }
            playerProfile.unlockedAchievements[id] = UnlockedAchievementData(unlockedDate: now, progress: 1.0)
        }

        if didWin && playerProfile.totalWins >= 1 {
            unlock("first_win")
        }
        if playerProfile.currentStreak >= 3 {
            unlock("win_streak_3")
        }
        if playerProfile.currentStreak >= 5 {
            unlock("win_streak_5")
        }
        if playerProfile.totalGames >= 10 {
            unlock("games_10")
        }
        if playerProfile.totalGames >= 50 {
            unlock("games_50")
        }
        if declaredMahjong {
            unlock("first_mahjong")
        }
        if playerProfile.unlockedTileSets.count >= 3 {
            unlock("collector")
        }
        if playerProfile.totalWins >= 10 {
            unlock("wins_10")
        }
        if playerProfile.totalWins >= 25 {
            unlock("wins_25")
        }

        saveAchievementsLocally()
    }

    func resolvedAchievements() -> [Achievement] {
        Achievement.allAchievements.map { achievement in
            let currentValue: Double
            switch achievement.id {
            case "first_win": currentValue = Double(playerProfile.totalWins)
            case "win_streak_3": currentValue = Double(playerProfile.bestStreak)
            case "win_streak_5": currentValue = Double(playerProfile.bestStreak)
            case "games_10": currentValue = Double(playerProfile.totalGames)
            case "games_50": currentValue = Double(playerProfile.totalGames)
            case "first_mahjong": currentValue = playerProfile.unlockedAchievements["first_mahjong"] != nil ? 1 : 0
            case "host_party": currentValue = playerProfile.unlockedAchievements["host_party"] != nil ? 1 : 0
            case "collector": currentValue = Double(playerProfile.unlockedTileSets.count)
            case "wins_10": currentValue = Double(playerProfile.totalWins)
            case "wins_25": currentValue = Double(playerProfile.totalWins)
            default: currentValue = 0
            }
            return achievement.withProgress(current: currentValue, unlocked: playerProfile.unlockedAchievements[achievement.id])
        }
    }

    private static let achievementsKey = "saved_achievements"

    private func saveAchievementsLocally() {
        if let data = try? JSONEncoder().encode(playerProfile.unlockedAchievements) {
            UserDefaults.standard.set(data, forKey: Self.achievementsKey)
        }
    }

    func loadLocalAchievements() {
        guard let data = UserDefaults.standard.data(forKey: Self.achievementsKey),
              let saved = try? JSONDecoder().decode([String: UnlockedAchievementData].self, from: data) else { return }
        playerProfile.unlockedAchievements = saved
    }

    func addXP(_ amount: Int) {
        playerProfile.xp += amount
        if playerProfile.xp >= playerProfile.xpForNextLevel {
            playerProfile.xp -= playerProfile.xpForNextLevel
            playerProfile.level += 1
        }
        saveProfileLocally()
        Task { await syncProfileToSupabase() }
    }

    // MARK: - Supabase Integration

    func checkAuthStatus() async {
        isCheckingAuth = true
        await supabase.restoreSession()
        isAuthenticated = supabase.isAuthenticated

        loadLocalProfile()
        loadLocalMatches()
        loadLocalAchievements()
        loadDailyRewardTracker()

        if isAuthenticated {
            await populateEmailFromAuth()
            await loadProfileFromSupabase()
            await loadMatchesFromSupabase()
            databaseStatus = await supabase.checkDatabaseSetup()
            await NotificationService.requestPermission()
        }
        isCheckingAuth = false
    }

    func handleAuthenticated() {
        isAuthenticated = true
        Task {
            await populateEmailFromAuth()
            await loadProfileFromSupabase()
            await loadMatchesFromSupabase()
            databaseStatus = await supabase.checkDatabaseSetup()
            await NotificationService.requestPermission()
        }
    }

    func signOut() async {
        do {
            try await supabase.signOut()
            isAuthenticated = false
            playerProfile = PlayerProfile()
            syncError = nil
            databaseStatus = nil
        } catch {
            print("⚠️ Sign out failed: \(error)")
        }
    }

    func sendPasswordReset() async {
        let email = playerProfile.email
        guard !email.isEmpty else {
            passwordResetError = "No email associated with this account."
            return
        }
        do {
            try await supabase.resetPassword(for: email)
            passwordResetSent = true
            passwordResetError = nil
        } catch {
            passwordResetError = error.localizedDescription
            passwordResetSent = false
        }
    }

    private func populateEmailFromAuth() async {
        if let email = await supabase.getCurrentUserEmail(), !email.isEmpty {
            playerProfile.email = email
            saveProfileLocally()
        }
    }

    func syncSettingsFromManager(_ settings: SettingsManager) {
        playerProfile.settingsData = ProfileSettings(
            soundEnabled: settings.soundEnabled,
            hapticsEnabled: settings.hapticsEnabled,
            musicEnabled: settings.musicEnabled,
            soundVolume: settings.soundVolume,
            notificationsEnabled: settings.notificationsEnabled,
            turnReminders: settings.turnReminders,
            friendRequests: settings.friendRequests,
            gameInvites: settings.gameInvites,
            showOnlineStatus: settings.showOnlineStatus,
            showGameHistory: settings.showGameHistory,
            allowFriendRequests: settings.allowFriendRequests,
            autoSortHand: settings.autoSortHand,
            confirmDiscards: settings.confirmDiscards
        )
        saveProfileLocally()
        Task { await syncProfileToSupabase() }
    }

    func applySettingsToManager(_ settings: SettingsManager) {
        let s = playerProfile.settingsData
        settings.soundEnabled = s.soundEnabled
        settings.hapticsEnabled = s.hapticsEnabled
        settings.musicEnabled = s.musicEnabled
        settings.soundVolume = s.soundVolume
        settings.notificationsEnabled = s.notificationsEnabled
        settings.turnReminders = s.turnReminders
        settings.friendRequests = s.friendRequests
        settings.gameInvites = s.gameInvites
        settings.showOnlineStatus = s.showOnlineStatus
        settings.showGameHistory = s.showGameHistory
        settings.allowFriendRequests = s.allowFriendRequests
        settings.autoSortHand = s.autoSortHand
        settings.confirmDiscards = s.confirmDiscards
    }

    private func loadProfileFromSupabase() async {
        do {
            if let profile = try await supabase.fetchPlayerProfile() {
                let remoteProfile = profile.toPlayerProfile()
                if remoteProfile.totalGames >= playerProfile.totalGames {
                    playerProfile = remoteProfile
                }
                saveProfileLocally()
                if let settings = settingsManagerRef {
                    applySettingsToManager(settings)
                }
                syncError = nil
            } else {
                await syncProfileToSupabase()
            }
        } catch {
            syncError = "Failed to load profile: \(error.localizedDescription)"
            print("⚠️ loadProfileFromSupabase: \(error)")
        }
    }

    func syncProfileToSupabase() async {
        guard let userId = supabase.currentUserId else { return }
        let supabaseProfile = SupabasePlayerProfile(from: playerProfile, userId: userId.uuidString.lowercased())
        do {
            try await supabase.upsertPlayerProfile(supabaseProfile)
            syncError = nil
        } catch {
            syncError = "Failed to save profile: \(error.localizedDescription)"
            print("⚠️ syncProfileToSupabase: \(error)")
        }
    }

    func saveGameResult(result: String, score: Int, opponents: [String], mode: String) async {
        guard let userId = supabase.currentUserId else { return }
        let gameResult = SupabaseGameResult(
            id: nil,
            userId: userId.uuidString.lowercased(),
            result: result,
            score: score,
            opponentNames: opponents,
            gameMode: mode,
            playedAt: nil
        )
        do {
            try await supabase.saveGameResult(gameResult)
        } catch {
            print("⚠️ saveGameResult: \(error)")
        }
    }
}

nonisolated struct GameNotification: Identifiable, Sendable {
    let id: UUID
    let message: String
    let type: NotificationType
    let timestamp: Date

    init(id: UUID = UUID(), message: String, type: NotificationType, timestamp: Date = Date()) {
        self.id = id
        self.message = message
        self.type = type
        self.timestamp = timestamp
    }
}

nonisolated enum NotificationType: Sendable {
    case invite
    case turnReminder
    case achievement
    case reward
}

nonisolated struct RecentMatch: Identifiable, Codable, Sendable {
    let id: UUID
    let opponentNames: [String]
    let result: MatchResult
    let score: Int
    let date: Date
    let gameMode: String
    let winningHandName: String?
}

nonisolated enum MatchResult: String, Codable, Sendable {
    case win = "Win"
    case loss = "Loss"
    case draw = "Draw"
}
