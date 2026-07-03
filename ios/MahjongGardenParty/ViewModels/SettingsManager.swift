import SwiftUI

@Observable
@MainActor
class SettingsManager {
    var onSettingsChanged: (() -> Void)?

    var soundEnabled: Bool {
        didSet { saveAndSync("settings_sound_enabled", soundEnabled) }
    }
    var hapticsEnabled: Bool {
        didSet { saveAndSync("settings_haptics_enabled", hapticsEnabled) }
    }
    var musicEnabled: Bool {
        didSet { saveAndSync("settings_music_enabled", musicEnabled) }
    }
    var soundVolume: Double {
        didSet { saveAndSync("settings_sound_volume", soundVolume) }
    }
    var notificationsEnabled: Bool {
        didSet { saveAndSync("settings_notifications_enabled", notificationsEnabled) }
    }
    var turnReminders: Bool {
        didSet { saveAndSync("settings_turn_reminders", turnReminders) }
    }
    var friendRequests: Bool {
        didSet { saveAndSync("settings_friend_requests", friendRequests) }
    }
    var gameInvites: Bool {
        didSet { saveAndSync("settings_game_invites", gameInvites) }
    }
    var showOnlineStatus: Bool {
        didSet { saveAndSync("settings_show_online_status", showOnlineStatus) }
    }
    var showGameHistory: Bool {
        didSet { saveAndSync("settings_show_game_history", showGameHistory) }
    }
    var allowFriendRequests: Bool {
        didSet { saveAndSync("settings_allow_friend_requests", allowFriendRequests) }
    }
    var autoSortHand: Bool {
        didSet { saveAndSync("settings_auto_sort_hand", autoSortHand) }
    }
    var confirmDiscards: Bool {
        didSet { saveAndSync("settings_confirm_discards", confirmDiscards) }
    }

    private var syncTask: Task<Void, Never>?

    private func saveAndSync(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            onSettingsChanged?()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        self.soundEnabled = defaults.object(forKey: "settings_sound_enabled") as? Bool ?? true
        self.hapticsEnabled = defaults.object(forKey: "settings_haptics_enabled") as? Bool ?? true
        self.musicEnabled = defaults.object(forKey: "settings_music_enabled") as? Bool ?? true
        self.soundVolume = defaults.object(forKey: "settings_sound_volume") as? Double ?? 0.8
        self.notificationsEnabled = defaults.object(forKey: "settings_notifications_enabled") as? Bool ?? true
        self.turnReminders = defaults.object(forKey: "settings_turn_reminders") as? Bool ?? true
        self.friendRequests = defaults.object(forKey: "settings_friend_requests") as? Bool ?? true
        self.gameInvites = defaults.object(forKey: "settings_game_invites") as? Bool ?? true
        self.showOnlineStatus = defaults.object(forKey: "settings_show_online_status") as? Bool ?? true
        self.showGameHistory = defaults.object(forKey: "settings_show_game_history") as? Bool ?? true
        self.allowFriendRequests = defaults.object(forKey: "settings_allow_friend_requests") as? Bool ?? true
        self.autoSortHand = defaults.object(forKey: "settings_auto_sort_hand") as? Bool ?? false
        self.confirmDiscards = defaults.object(forKey: "settings_confirm_discards") as? Bool ?? true
    }

    func resetAllSettings() {
        soundEnabled = true
        hapticsEnabled = true
        musicEnabled = true
        soundVolume = 0.8
        notificationsEnabled = true
        turnReminders = true
        friendRequests = true
        gameInvites = true
        showOnlineStatus = true
        showGameHistory = true
        allowFriendRequests = true
        autoSortHand = false
        confirmDiscards = true
    }
}
