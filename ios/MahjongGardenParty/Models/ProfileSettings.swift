import Foundation

nonisolated struct ProfileSettings: Codable, Sendable, Hashable {
    var soundEnabled: Bool
    var hapticsEnabled: Bool
    var musicEnabled: Bool
    var soundVolume: Double
    var notificationsEnabled: Bool
    var turnReminders: Bool
    var friendRequests: Bool
    var gameInvites: Bool
    var showOnlineStatus: Bool
    var showGameHistory: Bool
    var allowFriendRequests: Bool
    var autoSortHand: Bool
    var confirmDiscards: Bool

    init(
        soundEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        musicEnabled: Bool = true,
        soundVolume: Double = 0.8,
        notificationsEnabled: Bool = true,
        turnReminders: Bool = true,
        friendRequests: Bool = true,
        gameInvites: Bool = true,
        showOnlineStatus: Bool = true,
        showGameHistory: Bool = true,
        allowFriendRequests: Bool = true,
        autoSortHand: Bool = false,
        confirmDiscards: Bool = true
    ) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.musicEnabled = musicEnabled
        self.soundVolume = soundVolume
        self.notificationsEnabled = notificationsEnabled
        self.turnReminders = turnReminders
        self.friendRequests = friendRequests
        self.gameInvites = gameInvites
        self.showOnlineStatus = showOnlineStatus
        self.showGameHistory = showGameHistory
        self.allowFriendRequests = allowFriendRequests
        self.autoSortHand = autoSortHand
        self.confirmDiscards = confirmDiscards
    }
}
