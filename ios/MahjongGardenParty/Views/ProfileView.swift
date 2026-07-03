import SwiftUI

struct ProfileView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager
    @State private var showEditProfile: Bool = false
    @State private var showPasswordResetAlert: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    profileHeader
                    statsGrid
                    achievementsSection
                    settingsSection
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(gardenBackground)
            .navigationTitle("Profile")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .notifications:
                    NotificationSettingsView()
                case .sound:
                    SoundSettingsView()
                case .privacy:
                    PrivacySettingsView()
                case .help:
                    HelpSupportView()
                case .about:
                    AboutView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showEditProfile = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileSheet()
            }
            .alert("Password Reset", isPresented: $showPasswordResetAlert) {
                Button("OK") {
                    appViewModel.passwordResetSent = false
                    appViewModel.passwordResetError = nil
                }
            } message: {
                if appViewModel.passwordResetSent {
                    Text("A password reset link has been sent to \(appViewModel.playerProfile.email). Check your inbox.")
                } else if let error = appViewModel.passwordResetError {
                    Text(error)
                }
            }
            .onChange(of: appViewModel.passwordResetSent) { _, newValue in
                if newValue { showPasswordResetAlert = true }
            }
            .onChange(of: appViewModel.passwordResetError) { _, newValue in
                if newValue != nil { showPasswordResetAlert = true }
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            Image(appViewModel.playerProfile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 100, height: 100)
                .clipShape(Circle())
                .background(
                    Circle()
                        .fill(themeManager.currentTheme.primary.opacity(0.15))
                )
                .overlay(
                    Circle()
                        .strokeBorder(themeManager.currentTheme.primary.opacity(0.3), lineWidth: 3)
                )

            VStack(spacing: 4) {
                Text(appViewModel.playerProfile.displayName)
                    .font(.title2.bold())

                if !appViewModel.playerProfile.email.isEmpty {
                    Text(appViewModel.playerProfile.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(themeManager.currentTheme.accent)
                    Text("Level \(appViewModel.playerProfile.level)")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.primary)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("\(appViewModel.playerProfile.xp) / \(appViewModel.playerProfile.xpForNextLevel) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(appViewModel.playerProfile.levelProgress * 100))%")
                        .font(.caption.bold())
                        .foregroundStyle(themeManager.currentTheme.primary)
                }

                GeometryReader { geo in
                    Capsule()
                        .fill(themeManager.currentTheme.primary.opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [themeManager.currentTheme.primary, themeManager.currentTheme.accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * appViewModel.playerProfile.levelProgress)
                        }
                }
                .frame(height: 8)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 20))
    }

    private var statsGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatCard(title: "Total XP", value: formattedXP, icon: "sparkle", color: themeManager.currentTheme.accent)
                StatCard(title: "Games Played", value: "\(appViewModel.playerProfile.totalGames)", icon: "gamecontroller.fill", color: themeManager.currentTheme.primary)
            }
            HStack(spacing: 12) {
                StatCard(title: "Wins", value: "\(appViewModel.playerProfile.totalWins)", icon: "trophy.fill", color: .yellow)
                StatCard(title: "Win Rate", value: String(format: "%.0f%%", appViewModel.playerProfile.winRate), icon: "chart.bar.fill", color: themeManager.currentTheme.secondary)
            }
            HStack(spacing: 12) {
                StatCard(title: "Current Streak", value: "\(appViewModel.playerProfile.currentStreak)", icon: "flame.fill", color: .orange)
                StatCard(title: "Best Streak", value: "\(appViewModel.playerProfile.bestStreak)", icon: "flame.circle.fill", color: .red)
            }
        }
    }

    private var formattedXP: String {
        let totalXP = (appViewModel.playerProfile.level - 1) * 500 + appViewModel.playerProfile.xp
        if totalXP >= 1000 {
            return String(format: "%.1fK", Double(totalXP) / 1000.0)
        }
        return "\(totalXP)"
    }

    private var achievementsSection: some View {
        let resolved = appViewModel.resolvedAchievements()
        let unlocked = resolved.filter { $0.isUnlocked }
        let locked = resolved.filter { !$0.isUnlocked }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements")
                    .font(.title3.bold())
                Spacer()
                Text("\(unlocked.count)/\(resolved.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            if !unlocked.isEmpty {
                ForEach(unlocked) { achievement in
                    AchievementRow(achievement: achievement)
                }
            }

            if !locked.isEmpty {
                ForEach(locked) { achievement in
                    AchievementRow(achievement: achievement)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.title3.bold())

            VStack(spacing: 0) {
                NavigationLink(value: SettingsDestination.notifications) {
                    SettingsRow(icon: "bell.fill", title: "Notifications", color: .red)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: SettingsDestination.sound) {
                    SettingsRow(icon: "speaker.wave.2.fill", title: "Sound & Haptics", color: .blue)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: SettingsDestination.privacy) {
                    SettingsRow(icon: "hand.raised.fill", title: "Privacy", color: .green)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: SettingsDestination.help) {
                    SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support", color: .purple)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 52)
                NavigationLink(value: SettingsDestination.about) {
                    SettingsRow(icon: "info.circle.fill", title: "About", color: .gray)
                }
                .buttonStyle(.plain)
            }
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 16))

            Button {
                Task { await appViewModel.sendPasswordReset() }
            } label: {
                HStack {
                    Image(systemName: "key.fill")
                    Text("Reset Password")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(themeManager.currentTheme.primary.opacity(0.1))
                .foregroundStyle(themeManager.currentTheme.primary)
                .clipShape(.rect(cornerRadius: 14))
            }

            Button(role: .destructive) {
                Task { await appViewModel.signOut() }
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                    Text("Sign Out")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
                .clipShape(.rect(cornerRadius: 14))
            }
        }
    }

    private var gardenBackground: some View {
        Color.white
            .ignoresSafeArea()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)

            Text(value)
                .font(.title.bold())

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct AchievementRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let achievement: Achievement

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        achievement.isUnlocked
                        ? AnyShapeStyle(achievement.badgePrimaryColor.opacity(0.18))
                        : AnyShapeStyle(Color(.tertiarySystemFill))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                achievement.isUnlocked
                                ? achievement.badgePrimaryColor.opacity(0.55)
                                : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .shadow(
                        color: achievement.isUnlocked
                        ? achievement.badgePrimaryColor.opacity(0.45)
                        : .clear,
                        radius: 6,
                        x: 0,
                        y: 2
                    )

                Group {
                    if achievement.isUnlocked {
                        Image(systemName: achievement.iconName)
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                            .foregroundStyle(achievement.badgeGradient)
                    } else {
                        Image(systemName: achievement.iconName)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(achievement.title)
                        .font(.subheadline.bold())
                    Spacer()
                    if achievement.isUnlocked {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if let date = achievement.unlockedDate {
                                Text(date, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("\(Int(achievement.progress * 100))%")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                Text(achievement.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !achievement.isUnlocked {
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color(.tertiarySystemFill))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(achievement.badgeGradient)
                                    .frame(width: max(0, geo.size.width * achievement.progress))
                            }
                    }
                    .frame(height: 4)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .opacity(achievement.isUnlocked ? 1.0 : 0.8)
    }
}

enum SettingsDestination: Hashable {
    case notifications
    case sound
    case privacy
    case help
    case about
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color)
                .clipShape(.rect(cornerRadius: 7))

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager
    @State private var editName: String = ""
    @State private var selectedAvatar: String = ""

    private let avatarOptions: [(name: String, asset: String)] = [
        ("Daffodil", "daffodil"),
        ("Daylily", "daylily"),
        ("Dogwood", "dogwood"),
        ("Hydrangea", "hydrangea"),
        ("Lily", "lily"),
        ("Daisy", "pdaisy"),
        ("Pink Rose", "pink_rose"),
        ("Pink Flower", "pink_flower"),
        ("Tulip", "tulip"),
        ("Peony", "peony")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Your name", text: $editName)
                }

                Section("Avatar") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(avatarOptions, id: \.asset) { option in
                            Button {
                                selectedAvatar = option.asset
                            } label: {
                                VStack(spacing: 4) {
                                    Image(option.asset)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 52, height: 52)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    selectedAvatar == option.asset ? themeManager.currentTheme.primary : .clear,
                                                    lineWidth: 3
                                                )
                                        )
                                    Text(option.name)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(4)
                                .background(
                                    selectedAvatar == option.asset
                                    ? themeManager.currentTheme.primary.opacity(0.15)
                                    : Color.clear
                                )
                                .clipShape(.rect(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        appViewModel.playerProfile.displayName = editName
                        appViewModel.playerProfile.avatarImage = selectedAvatar
                        Task { await appViewModel.syncProfileToSupabase() }
                        dismiss()
                    }
                    .disabled(editName.isEmpty)
                }
            }
            .onAppear {
                editName = appViewModel.playerProfile.displayName
                selectedAvatar = appViewModel.playerProfile.avatarImage
            }
        }
    }
}
