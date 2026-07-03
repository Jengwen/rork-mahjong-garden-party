import SwiftUI
import UserNotifications

struct NotificationSettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(ThemeManager.self) private var themeManager

    @State private var systemAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showSettingsAlert: Bool = false

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle("Enable Notifications", isOn: Binding(
                    get: { settings.notificationsEnabled && systemAuthStatus.isEffectivelyAuthorized },
                    set: { newValue in handleMasterToggle(newValue) }
                ))
            } footer: {
                Text(masterFooter)
            }

            Section("Game Notifications") {
                Toggle("Turn Reminders", isOn: $settings.turnReminders)
                Toggle("Game Invites", isOn: $settings.gameInvites)
            }
            .disabled(!isOn)

            Section("Social Notifications") {
                Toggle("Friend Requests", isOn: $settings.friendRequests)
            }
            .disabled(!isOn)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.currentTheme.primary)
        .task { await refreshAuthStatus() }
        .alert("Notifications Disabled", isPresented: $showSettingsAlert) {
            Button("Open Settings") { NotificationService.openSystemSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Notifications are turned off for Mahjong Garden Party. Open Settings to enable them.")
        }
    }

    private var isOn: Bool {
        settings.notificationsEnabled && systemAuthStatus.isEffectivelyAuthorized
    }

    private var masterFooter: String {
        switch systemAuthStatus {
        case .denied:
            return "Notifications are disabled in iOS Settings. Tap Enable to open Settings."
        case .notDetermined:
            return "Allow notifications to receive game invites, turn reminders, and friend requests."
        default:
            return "Master toggle for all in-app and push notifications."
        }
    }

    private func handleMasterToggle(_ newValue: Bool) {
        if newValue {
            Task {
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                if status == .denied {
                    settings.notificationsEnabled = false
                    showSettingsAlert = true
                    systemAuthStatus = status
                    return
                }
                let granted = await NotificationService.requestPermission()
                settings.notificationsEnabled = granted
                await refreshAuthStatus()
            }
        } else {
            settings.notificationsEnabled = false
        }
    }

    private func refreshAuthStatus() async {
        systemAuthStatus = await NotificationService.currentAuthorizationStatus()
    }
}

private extension UNAuthorizationStatus {
    var isEffectivelyAuthorized: Bool {
        self == .authorized || self == .provisional || self == .ephemeral
    }
}
