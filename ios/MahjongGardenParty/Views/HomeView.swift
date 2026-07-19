import SwiftUI

struct HomeView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTab: AppTab
    @State private var showDailyReward: Bool = false
    @State private var appeared: Bool = false
    @State private var showGameBoard: Bool = false
    @State private var showPaywall: Bool = false
    @State private var isResuming: Bool = false
    @State private var store = StoreManager.shared
    @State private var onlineVM = OnlineGameViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    welcomeHeader
                    if onlineVM.resumableGame != nil {
                        resumeGameBanner
                    }
                    dailyRewardBanner
                    quickPlaySection
                    learningResourcesButton
                    recentMatchesSection
                    achievementsPreview
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(gardenBackground)
            .navigationTitle("Garden Party")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showDailyReward = true
                    } label: {
                        Image(systemName: "gift.fill")
                            .symbolEffect(.bounce, value: !appViewModel.dailyRewardClaimed)
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showDailyReward) {
                DailyRewardSheet()
            }
            .fullScreenCover(isPresented: $showGameBoard, onDismiss: {
                OrientationManager.shared.lockPortrait()
            }) {
                GameBoardView()
                    .environment(onlineVM)
                    .onAppear {
                        OrientationManager.shared.lockLandscape()
                    }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .navigationDestination(for: String.self) { destination in
                if destination == "learningResources" {
                    LearningResourcesView()
                } else if destination == "matchHistory" {
                    MatchHistoryView()
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.6)) {
                    appeared = true
                }
            }
            .task {
                await onlineVM.refreshResumableGame()
            }
            .onChange(of: scenePhase) { _, phase in
                // Re-check when the app returns to the foreground — the most common
                // moment right after an accidental close/relaunch.
                if phase == .active {
                    Task { await onlineVM.refreshResumableGame() }
                }
            }
            .onChange(of: showGameBoard) { _, isShowing in
                // Coming back from the board — recompute so the banner reflects
                // whether the game is still live (or was left/finished).
                if !isShowing {
                    Task { await onlineVM.refreshResumableGame() }
                }
            }
        }
    }

    private var resumeGameBanner: some View {
        Button {
            resumeGame()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(themeManager.currentTheme.primary.opacity(0.15))
                        .frame(width: 44, height: 44)
                    if isResuming {
                        ProgressView()
                    } else {
                        Image(systemName: "gamecontroller.fill")
                            .font(.title3)
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Game in progress")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(isResuming ? "Rejoining…" : "Tap to rejoin your table")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline.bold())
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [
                        themeManager.currentTheme.primary.opacity(0.12),
                        themeManager.currentTheme.accent.opacity(0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(themeManager.currentTheme.primary.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isResuming)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.6).delay(0.05), value: appeared)
    }

    private func resumeGame() {
        guard let summary = onlineVM.resumableGame, !isResuming else { return }
        isResuming = true
        Task {
            let ok = await onlineVM.loadOnlineGameState(gameId: summary.id, gameViewModel: gameViewModel)
            isResuming = false
            if ok {
                // loadOnlineGameState flips onlineVM.showGameBoard; this view drives
                // its own cover, so hand off and clear the VM flag (same pattern as
                // OnlineGamesView) to avoid a lingering cross-view present signal.
                onlineVM.showGameBoard = false
                showGameBoard = true
            } else {
                // Couldn't load it (finished, left, or transient) — recompute so a
                // dead banner disappears instead of bouncing the user nowhere.
                await onlineVM.refreshResumableGame()
            }
        }
    }

    private var welcomeHeader: some View {
        HStack(spacing: 16) {
            Image(appViewModel.playerProfile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .background(
                    Circle()
                        .fill(themeManager.currentTheme.primary.opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back,")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(appViewModel.playerProfile.displayName)
                    .font(.title2.bold())

                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(themeManager.currentTheme.accent)
                    Text("Level \(appViewModel.playerProfile.level)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(themeManager.currentTheme.primary)

                    GeometryReader { geo in
                        Capsule()
                            .fill(themeManager.currentTheme.primary.opacity(0.15))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(themeManager.currentTheme.primary)
                                    .frame(width: geo.size.width * appViewModel.playerProfile.levelProgress)
                            }
                    }
                    .frame(height: 6)
                }
            }

            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .onTapGesture {
            selectedTab = .profile
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
    }

    private var dailyRewardBanner: some View {
        Button {
            showDailyReward = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(themeManager.currentTheme.accent)
                        Text("Daily Garden Gift")
                            .font(.headline)
                    }
                    Text(appViewModel.dailyRewardClaimed ? "Come back tomorrow!" : "Tap to claim your reward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !appViewModel.dailyRewardClaimed {
                    Text("Claim")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(themeManager.currentTheme.primary)
                        .clipShape(Capsule())
                }
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [
                        themeManager.currentTheme.primary.opacity(0.08),
                        themeManager.currentTheme.accent.opacity(0.08)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(themeManager.currentTheme.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.6).delay(0.1), value: appeared)
    }

    private var quickPlaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Play")
                .font(.title3.bold())

            HStack(spacing: 12) {
                Button {
                    guard store.hasActiveSubscription else {
                        showPaywall = true
                        return
                    }
                    gameViewModel.resetOnlineMode()
                    gameViewModel.startNewGame(mode: .solo, humanProfile: appViewModel.playerProfile)
                    showGameBoard = true
                } label: {
                    QuickPlayCard(
                        title: "Solo",
                        subtitle: store.hasActiveSubscription ? "Practice against AI bots and sharpen your Mahjong skills" : "Unlock to practice against AI bots",
                        icon: store.hasActiveSubscription ? "person.fill" : "lock.fill",
                        color: themeManager.currentTheme.secondary
                    )
                }
                .buttonStyle(.plain)

            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.6).delay(0.2), value: appeared)
    }

    private var recentMatchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Matches")
                    .font(.title3.bold())
                Spacer()
                NavigationLink(value: "matchHistory") {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }

            if appViewModel.recentMatches.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "gamecontroller")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No matches yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Play a game to see your results here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(appViewModel.recentMatches.prefix(5)) { match in
                    RecentMatchRow(match: match)
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.6).delay(0.3), value: appeared)
    }

    private var achievementsPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Achievements")
                    .font(.title3.bold())
                Spacer()
                Button("View All") {}
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.primary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(appViewModel.resolvedAchievements().prefix(4)) { achievement in
                        AchievementBadge(achievement: achievement)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
            .scrollIndicators(.hidden)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.6).delay(0.4), value: appeared)
    }

    private var learningResourcesButton: some View {
        NavigationLink(value: "learningResources") {
            HStack(spacing: 14) {
                Image(systemName: "book.and.wrench.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(themeManager.currentTheme.secondary)
                    .clipShape(.rect(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Learn to Play")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Videos, tips & resources")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 20)
        .animation(.spring(response: 0.6).delay(0.25), value: appeared)
    }

    private var gardenBackground: some View {
        Color.white
            .ignoresSafeArea()
    }
}

struct QuickPlayCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var isWide: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.12))
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }
}

struct RecentMatchRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let match: RecentMatch

    private var resultColor: Color {
        switch match.result {
        case .win: return .green
        case .loss: return .red
        case .draw: return .orange
        }
    }

    private var resultIcon: String {
        switch match.result {
        case .win: return "trophy.fill"
        case .loss: return "xmark"
        case .draw: return "equal.circle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(resultColor.opacity(0.15))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: resultIcon)
                        .font(.subheadline)
                        .foregroundStyle(resultColor)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("vs \(match.opponentNames.joined(separator: ", "))")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(match.gameMode)
                        .font(.caption2)
                        .foregroundStyle(themeManager.currentTheme.primary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(match.date, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(match.result.rawValue)
                    .font(.caption.bold())
                    .foregroundStyle(match.result == .win ? .green : (match.result == .draw ? .orange : .red))
                if match.score > 0 {
                    Text("\(match.score) pts")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let handName = match.winningHandName {
                    Text(handName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct AchievementBadge: View {
    @Environment(ThemeManager.self) private var themeManager
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 8) {
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
                        radius: 8,
                        x: 0,
                        y: 3
                    )

                Group {
                    if achievement.isUnlocked {
                        Image(systemName: achievement.iconName)
                            // .monochrome, NOT .multicolor. `.multicolor` makes SF Symbols
                            // draw with its OWN built-in palette, which overrides
                            // `foregroundStyle` — so 7 of the 10 badges (trophy, flame,
                            // sparkles, star, party.popper, medal, crown all ship
                            // multicolor variants) silently ignored `badgeGradient` and
                            // rendered as stock Apple yellow, while the 3 without variants
                            // (person.2, laurel, grid) picked up the real palette. The wall
                            // came out a mix of generic symbols and tinted ones. Monochrome
                            // lets the gradient actually land on all ten.
                            .symbolRenderingMode(.monochrome)
                            .font(.title2)
                            .foregroundStyle(achievement.badgeGradient)
                    } else {
                        Image(systemName: achievement.iconName)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 56, height: 56)
            .opacity(achievement.isUnlocked ? 1.0 : 0.55)

            Text(achievement.title)
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(achievement.isUnlocked ? .primary : .secondary)
        }
        .frame(width: 80)
    }
}

struct DailyRewardSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .symbolEffect(.bounce)

                Text("Daily Garden Gift")
                    .font(.title.bold())

                Text("Come back every day to earn XP and unlock special rewards!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(appViewModel.dailyRewards) { reward in
                        let isNext = !appViewModel.dailyRewardClaimed && reward.day == appViewModel.dailyRewardTracker.nextRewardDay
                        VStack(spacing: 4) {
                            Text("Day")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(reward.day)")
                                .font(.headline)
                            Image(systemName: reward.isClaimed ? "checkmark.circle.fill" : (isNext ? "gift.fill" : "gift"))
                                .font(.caption)
                                .foregroundStyle(reward.isClaimed ? .green : (isNext ? themeManager.currentTheme.accent : themeManager.currentTheme.primary))
                            Text("+\(reward.xpReward)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            reward.isClaimed
                                ? Color.green.opacity(0.1)
                                : (isNext ? themeManager.currentTheme.accent.opacity(0.12) : themeManager.currentTheme.primary.opacity(0.05))
                        )
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            isNext ? RoundedRectangle(cornerRadius: 10).strokeBorder(themeManager.currentTheme.accent, lineWidth: 1.5) : nil
                        )
                    }
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 8) {
                    if !appViewModel.dailyRewardClaimed {
                        Text("Day \(appViewModel.dailyRewardTracker.nextRewardDay) Reward")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        appViewModel.claimDailyReward()
                        dismiss()
                    } label: {
                        Text(appViewModel.dailyRewardClaimed ? "Already Claimed" : "Claim +\(appViewModel.dailyRewardTracker.xpForNextReward) XP")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(appViewModel.dailyRewardClaimed ? Color(.tertiarySystemFill) : themeManager.currentTheme.primary)
                            .foregroundStyle(appViewModel.dailyRewardClaimed ? Color.secondary : Color.white)
                            .clipShape(.rect(cornerRadius: 16))
                    }
                    .disabled(appViewModel.dailyRewardClaimed)
                }
                .padding(.horizontal)
            }
            .padding(.top, 32)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationContentInteraction(.scrolls)
    }
}
