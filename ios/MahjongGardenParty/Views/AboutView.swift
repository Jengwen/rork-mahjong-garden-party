import SwiftUI

struct AboutView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SettingsManager.self) private var settings

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                VStack(spacing: 12) {
                    Image("logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 220)
                        .padding(.top, 8)

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle("Auto-Sort Hand", isOn: $settings.autoSortHand)
                Toggle("Confirm Discards", isOn: $settings.confirmDiscards)
            } header: {
                Text("Gameplay")
            } footer: {
                Text("Auto-sort arranges your hand by suit. Confirm discards adds a confirmation step before discarding a tile.")
            }

            Section("Game Info") {
                LabeledContent("Card Year", value: "NMJL 2025")
                LabeledContent("Tile Sets", value: "Classic")
            }

            Section("Legal") {
                Label("Terms of Service", systemImage: "doc.text")
                    .font(.subheadline)
                Label("Privacy Policy", systemImage: "hand.raised.fill")
                    .font(.subheadline)
                Label("Acknowledgments", systemImage: "heart.fill")
                    .font(.subheadline)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.currentTheme.primary)
    }
}
