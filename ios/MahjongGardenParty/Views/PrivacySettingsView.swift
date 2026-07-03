import SwiftUI

struct PrivacySettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle("Show Online Status", isOn: $settings.showOnlineStatus)
                Toggle("Show Game History", isOn: $settings.showGameHistory)
                Toggle("Allow Friend Requests", isOn: $settings.allowFriendRequests)
            } header: {
                Text("Visibility")
            } footer: {
                Text("Control what other players can see about you.")
            }

            Section {
                Button {
                    clearGameCache()
                } label: {
                    HStack {
                        Text("Clear Local Cache")
                        Spacer()
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                }

                Button(role: .destructive) {
                    settings.resetAllSettings()
                } label: {
                    HStack {
                        Text("Reset All Settings")
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Clear cached data or reset all settings to defaults.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.currentTheme.primary)
    }

    private func clearGameCache() {
        URLCache.shared.removeAllCachedResponses()
    }
}
