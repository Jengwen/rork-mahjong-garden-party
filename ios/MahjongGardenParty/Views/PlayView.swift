import SwiftUI

struct PlayView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(AppViewModel.self) private var appViewModel
    @State private var showGameBoard: Bool = false
    @State private var selectedMode: GameMode = .solo
    @State private var showCardPreview: Bool = false
    @State private var showMultiplayerOptions: Bool = false
    @State private var onlineVM = OnlineGameViewModel()
    @State private var showCreateGame: Bool = false
    @State private var showLobby: Bool = false
    @State private var isQuickMatching: Bool = false
    @State private var showOnlineGameBoard: Bool = false
    @State private var store = StoreManager.shared
    @State private var showPaywall: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    cardSelector
                    gameModePicker
                    selectedModeDetail
                    startGameButton
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background(gardenBackground)
            .navigationTitle("Play")
            .fullScreenCover(isPresented: $showGameBoard, onDismiss: {
                OrientationManager.shared.lockPortrait()
            }) {
                GameBoardView()
                    .environment(onlineVM)
                    .onAppear {
                        OrientationManager.shared.lockLandscape()
                    }
            }
            .sheet(isPresented: $showCardPreview) {
                CardReferenceView(card: gameViewModel.activeCard)
            }
            .sheet(isPresented: $showMultiplayerOptions) {
                MultiplayerOptionsSheet(
                    isQuickMatching: $isQuickMatching,
                    onQuickMatch: {
                        Task {
                            isQuickMatching = true
                            let cardYear = gameViewModel.selectedCardYear.rawValue
                            let _ = await onlineVM.quickMatch(
                                displayName: appViewModel.playerProfile.displayName,
                                avatarImage: appViewModel.playerProfile.avatarImage,
                                cardYear: cardYear
                            )
                            isQuickMatching = false
                            if onlineVM.currentGameId != nil {
                                showMultiplayerOptions = false
                                showLobby = true
                            }
                        }
                    },
                    onInvitePlayers: {
                        showMultiplayerOptions = false
                        showCreateGame = true
                    }
                )
            }
            .sheet(isPresented: $showCreateGame) {
                CreateGameSheet(onlineVM: onlineVM, appViewModel: appViewModel, gameViewModel: gameViewModel) {
                    showCreateGame = false
                    showLobby = true
                }
            }
            .navigationDestination(isPresented: $showLobby) {
                GameLobbyView(onlineVM: onlineVM, gameViewModel: gameViewModel)
            }
            .fullScreenCover(isPresented: $showOnlineGameBoard, onDismiss: {
                OrientationManager.shared.lockPortrait()
                onlineVM.stopPolling()
                gameViewModel.resetOnlineMode()
                showLobby = false
            }) {
                GameBoardView()
                    .environment(onlineVM)
                    .onAppear {
                        OrientationManager.shared.lockLandscape()
                        onlineVM.startPolling(gameViewModel: gameViewModel)
                    }
            }
            // Parent-level safety net: as soon as the host moves the game out of
            // "waiting", force this player out of the lobby and into the live board.
            .onChange(of: onlineVM.showGameBoard) { _, newValue in
                guard newValue else { return }
                forceTransitionToGameBoard()
            }
            .onChange(of: onlineVM.currentGame?.status) { _, newStatus in
                guard let newStatus, newStatus != OnlineGameStatus.waiting.rawValue else { return }
                forceTransitionToGameBoard()
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    /// Fallback transition: only fires when the lobby is NOT currently on screen.
    /// When the lobby IS showing, it owns the fullScreenCover transition itself —
    /// the parent must not pop the lobby AND present a cover at the same time, or
    /// SwiftUI cancels the cover and the invitee gets stranded.
    private func forceTransitionToGameBoard() {
        guard !showOnlineGameBoard else { return }
        guard !showLobby else {
            // Lobby will present its own cover. Just consume the showGameBoard flag.
            if onlineVM.showGameBoard { onlineVM.showGameBoard = false }
            return
        }
        guard let gameId = onlineVM.currentGameId else { return }
        if onlineVM.showGameBoard { onlineVM.showGameBoard = false }
        showOnlineGameBoard = true
        Task { @MainActor in
            _ = await onlineVM.loadOnlineGameStateWithRetry(
                gameId: gameId,
                gameViewModel: gameViewModel
            )
        }
    }

    private var gameModePicker: some View {
        VStack(spacing: 16) {
            ForEach(GameMode.allCases.filter { $0 != .async }, id: \.self) { mode in
                GameModeCard(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    onTap: { selectedMode = mode }
                )
            }
        }
    }

    private var selectedModeDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch selectedMode {
            case .solo:
                modeInfoCard(
                    title: "Solo Practice",
                    description: "Sharpen your skills against AI opponents. Perfect for learning American Mahjong rules and trying new strategies.",
                    features: ["Adjustable difficulty", "No time pressure", "Learn at your pace"]
                )
            case .multiplayer:
                modeInfoCard(
                    title: "Live Multiplayer",
                    description: "Play real-time Mahjong with 3 other players. Match with friends or find new garden companions.",
                    features: ["Real-time gameplay", "In-game chat", "Ranked matches"]
                )
            case .async:
                modeInfoCard(
                    title: "Turn-Based",
                    description: "Play at your own pace! Take turns when it's convenient — perfect for busy schedules.",
                    features: ["Play anytime", "Push notifications", "Multiple games at once"]
                )
            }
        }
    }

    private func modeInfoCard(title: String, description: String, features: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                ForEach(features, id: \.self) { feature in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(themeManager.currentTheme.secondary)
                        Text(feature)
                            .font(.caption2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
    }

    private var cardSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NMJL Card")
                .font(.system(.caption, design: .serif, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(1)

            HStack(spacing: 12) {
                @Bindable var vm = gameViewModel
                Menu {
                    ForEach(NMJLCardYear.allCases) { year in
                        Button {
                            gameViewModel.selectedCardYear = year
                        } label: {
                            HStack {
                                Text(year.displayName)
                                if !year.isAvailable {
                                    Text("Coming Soon")
                                        .foregroundStyle(.secondary)
                                }
                                if gameViewModel.selectedCardYear == year {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .disabled(!year.isAvailable)
                    }
                } label: {
                    HStack {
                        Image(systemName: "menucard.fill")
                            .font(.title3)
                            .foregroundStyle(themeManager.currentTheme.primary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(gameViewModel.selectedCardYear.displayName)
                                .font(.headline)
                            Text("Tap to change card year")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(.rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    showCardPreview = true
                } label: {
                    Image(systemName: "eye.fill")
                        .font(.title3)
                        .frame(width: 52, height: 52)
                        .background(themeManager.currentTheme.primary.opacity(0.12))
                        .foregroundStyle(themeManager.currentTheme.primary)
                        .clipShape(.rect(cornerRadius: 14))
                }
            }
        }
    }

    private var startGameButton: some View {
        Button {
            guard store.hasActiveSubscription else {
                showPaywall = true
                return
            }
            if selectedMode == .multiplayer {
                showMultiplayerOptions = true
            } else {
                gameViewModel.resetOnlineMode()
                gameViewModel.startNewGame(mode: selectedMode, humanProfile: appViewModel.playerProfile)
                showGameBoard = true
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: store.hasActiveSubscription ? "play.fill" : "lock.fill")
                Text(store.hasActiveSubscription ? "Start Game" : "Unlock to Play")
                    .fontWeight(.bold)
            }
            .font(.title3)
            .frame(maxWidth: .infinity)
            .padding()
            .background(themeManager.currentTheme.primary)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 16))
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showGameBoard)
    }

    private var gardenBackground: some View {
        Color.white
            .ignoresSafeArea()
    }
}

struct MultiplayerOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Binding var isQuickMatching: Bool
    let onQuickMatch: () -> Void
    let onInvitePlayers: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("How do you want to play?")
                    .font(.title2.bold())
                    .padding(.top, 8)

                Text("Create a private game and invite your friends to play.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Quick Match is temporarily hidden — will return in a later build.
                // Suppress unused-binding warnings for the preserved API surface.
                let _ = isQuickMatching
                let _ = onQuickMatch

                Button {
                    onInvitePlayers()
                } label: {
                    OptionCard(
                        title: "Invite Players",
                        subtitle: "Create a private game and invite friends",
                        icon: "person.badge.plus",
                        accent: themeManager.currentTheme.accent,
                        isLoading: false
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 16)
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
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

struct OptionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.12))
                    .frame(width: 56, height: 56)
                if isLoading {
                    ProgressView()
                        .tint(accent)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(accent)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(accent.opacity(0.2), lineWidth: 1)
        )
    }
}

struct GameModeCard: View {
    @Environment(ThemeManager.self) private var themeManager
    let mode: GameMode
    let isSelected: Bool
    let onTap: () -> Void

    private var modeIcon: String {
        switch mode {
        case .solo: return "person.fill"
        case .multiplayer: return "person.3.fill"
        case .async: return "clock.fill"
        }
    }

    private var modeSubtitle: String {
        switch mode {
        case .solo: return "vs AI Bots"
        case .multiplayer: return "Real-time 4P"
        case .async: return "Play anytime"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: modeIcon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : themeManager.currentTheme.primary)
                    .frame(width: 52, height: 52)
                    .background(isSelected ? themeManager.currentTheme.primary : themeManager.currentTheme.primary.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.headline)
                    Text(modeSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(themeManager.currentTheme.primary)
                        .font(.title3)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? themeManager.currentTheme.primary : .clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
