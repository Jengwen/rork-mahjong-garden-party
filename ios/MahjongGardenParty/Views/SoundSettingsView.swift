import SwiftUI

struct SoundSettingsView: View {
    @Environment(SettingsManager.self) private var settings
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Toggle("Sound Effects", isOn: $settings.soundEnabled)
                Toggle("Background Music", isOn: $settings.musicEnabled)
            } footer: {
                Text("Toggle game sounds and background music.")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(settings.soundVolume * 100))%")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Slider(value: $settings.soundVolume, in: 0...1, step: 0.05)
                            .tint(themeManager.currentTheme.primary)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
            .disabled(!settings.soundEnabled && !settings.musicEnabled)

            Section {
                Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
            } footer: {
                Text("Vibration feedback when placing tiles, drawing, and other game actions.")
            }
        }
        .navigationTitle("Sound & Haptics")
        .navigationBarTitleDisplayMode(.inline)
        .tint(themeManager.currentTheme.primary)
    }
}
