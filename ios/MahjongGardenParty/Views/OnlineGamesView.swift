import SwiftUI

struct OnlineGamesView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameViewModel.self) private var gameViewModel
    @State private var onlineVM = OnlineGameViewModel()
    @State private var showCreateGame: Bool = false
    @State private var selectedGameId: String?
    @State private var showLobby: Bool = false
    @State private var showOnlineGameBoard: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if !onlineVM.pendingInvites.isEmpty {
                    invitesSection
                }
                activeGamesSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(red: 250/255, green: 243/255, blue: 214/255).ignoresSafeArea())
        .navigationTitle("Online Games")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreateGame = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(themeManager.currentTheme.primary)
                }
            }
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
        // Parent-level safety net: the moment the host flips the game out of "waiting",
        // force the invitee out of the lobby and into the live board — regardless of
        // whether the lobby's internal transition machinery has fired.
        .onChange(of: onlineVM.showGameBoard) { _, newValue in
            guard newValue else { return }
            forceTransitionToGameBoard()
        }
        .onChange(of: onlineVM.currentGame?.status) { _, newStatus in
            guard let newStatus, newStatus != OnlineGameStatus.waiting.rawValue else { return }
            forceTransitionToGameBoard()
        }
        .task {
            await onlineVM.loadActiveGames()
        }
        .refreshable {
            await onlineVM.loadActiveGames()
        }
    }

    /// Fallback transition: only fires when the lobby is NOT currently on screen.
    /// When the lobby IS showing, it owns the fullScreenCover transition itself —
    /// popping the lobby AND presenting a cover from the parent simultaneously
    /// causes SwiftUI to cancel the cover, leaving the invitee stuck.
    private func forceTransitionToGameBoard() {
        guard !showOnlineGameBoard else { return }
        // When the lobby IS visible, it owns the transition. Do NOT reset
        // `onlineVM.showGameBoard` here — SwiftUI coalesces same-tick mutations
        // and the lobby's own `.onChange` observer may never see the true value,
        // stranding the invitee in the lobby.
        guard !showLobby else { return }
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

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.badge.fill")
                    .foregroundStyle(themeManager.currentTheme.accent)
                Text("Game Invites")
                    .font(.headline)
                Spacer()
                Text("\(onlineVM.pendingInvites.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(themeManager.currentTheme.accent)
                    .clipShape(Circle())
            }

            ForEach(onlineVM.pendingInvites) { invite in
                InviteRow(
                    invite: invite,
                    senderProfile: onlineVM.inviteSenderProfiles[invite.senderId],
                    onAccept: {
                        Task {
                            await onlineVM.acceptInvite(
                                invite,
                                displayName: appViewModel.playerProfile.displayName,
                                avatarImage: appViewModel.playerProfile.avatarImage
                            )
                            // Drop straight into the lobby so the invitee
                            // joins the host's game the moment Start is pressed.
                            await onlineVM.loadLobby(gameId: invite.gameId)
                            showLobby = true
                        }
                    },
                    onDecline: {
                        Task { await onlineVM.declineInvite(invite) }
                    }
                )
            }
        }
    }

    private var activeGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(themeManager.currentTheme.primary)
                Text("Active Games")
                    .font(.headline)
                Spacer()
            }

            if onlineVM.isLoading && onlineVM.activeGames.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading games...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if onlineVM.activeGames.isEmpty {
                emptyGamesState
            } else {
                ForEach(onlineVM.activeGames) { summary in
                    ActiveGameRow(summary: summary) {
                        Task {
                            if summary.game.status == OnlineGameStatus.waiting.rawValue {
                                await onlineVM.loadLobby(gameId: summary.id)
                                showLobby = true
                            } else {
                                await onlineVM.loadOnlineGameState(gameId: summary.id, gameViewModel: gameViewModel)
                                if onlineVM.showGameBoard {
                                    showOnlineGameBoard = true
                                    onlineVM.showGameBoard = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyGamesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No Active Games")
                .font(.title3.bold())
            Text("Create a game and invite friends to play turn-based Mahjong!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showCreateGame = true
            } label: {
                Label("Create Game", systemImage: "plus")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

struct InviteRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let invite: GameInvite
    let senderProfile: FriendProfile?
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(senderProfile?.avatarImage ?? "daffodil")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .background(Circle().fill(themeManager.currentTheme.primary.opacity(0.1)).frame(width: 48, height: 48))

            VStack(alignment: .leading, spacing: 3) {
                Text(senderProfile?.displayName ?? "A player")
                    .font(.headline)
                Text("invited you to a game")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onAccept) {
                Text("Join")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.currentTheme.primary)
                    .clipShape(Capsule())
            }

            Button(action: onDecline) {
                Image(systemName: "xmark")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }
}

struct ActiveGameRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let summary: OnlineGameSummary
    let onTap: () -> Void

    private var statusLabel: String {
        switch summary.game.status {
        case OnlineGameStatus.waiting.rawValue: return "Waiting for players"
        case OnlineGameStatus.charleston.rawValue: return "Charleston"
        case OnlineGameStatus.playing.rawValue: return summary.isMyTurn ? "Your Turn!" : "Waiting for opponent"
        case OnlineGameStatus.completed.rawValue: return "Completed"
        default: return summary.game.status
        }
    }

    private var statusColor: Color {
        if summary.isMyTurn { return .green }
        switch summary.game.status {
        case OnlineGameStatus.waiting.rawValue: return .orange
        case OnlineGameStatus.completed.rawValue: return .secondary
        default: return .blue
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: summary.isMyTurn ? "hand.raised.fill" : "clock.fill")
                            .font(.title3)
                            .foregroundStyle(statusColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ForEach(summary.participants, id: \.userId) { p in
                            Text(p.displayName)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(p.userId == summary.myUserId ? themeManager.currentTheme.primary.opacity(0.12) : Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }

                    Text(statusLabel)
                        .font(.subheadline.bold())
                        .foregroundStyle(statusColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct CreateGameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    let onlineVM: OnlineGameViewModel
    let appViewModel: AppViewModel
    let gameViewModel: GameViewModel
    let onCreated: () -> Void

    @State private var isCreating: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(themeManager.currentTheme.primary)

                VStack(spacing: 8) {
                    Text("Host a Garden Party")
                        .font(.title2.bold())
                    Text("Create an online game and invite friends to play turn-based Mahjong.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("Invite up to 3 friends", systemImage: "person.3.fill")
                    Label("Bots fill empty seats", systemImage: "cpu")
                    Label("Take turns at your own pace", systemImage: "clock.fill")
                    Label("Get notified when it's your turn", systemImage: "bell.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Button {
                    isCreating = true
                    Task {
                        let cardYear = gameViewModel.selectedCardYear.rawValue
                        let _ = await onlineVM.createGame(
                            displayName: appViewModel.playerProfile.displayName,
                            avatarImage: appViewModel.playerProfile.avatarImage,
                            cardYear: cardYear
                        )
                        isCreating = false
                        onCreated()
                    }
                } label: {
                    HStack {
                        if isCreating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                        Text("Create Game")
                            .fontWeight(.bold)
                    }
                    .font(.title3)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.currentTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 16))
                }
                .disabled(isCreating)
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
    }
}
