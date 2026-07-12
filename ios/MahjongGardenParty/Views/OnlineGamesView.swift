import SwiftUI

struct OnlineGamesView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameViewModel.self) private var gameViewModel
    @State private var onlineVM = OnlineGameViewModel()
    /// Drives the spinner on the "+" button while the game is being created.
    /// Replaces `showCreateGame` — there is no "Host a Garden Party" interstitial
    /// any more; the create happens inline on the way to the lobby.
    @State private var isCreatingGame: Bool = false
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
                    createGameAndOpenLobby()
                } label: {
                    if isCreatingGame {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }
                // Real async work sits behind this now, so block a second tap
                // from creating a duplicate game.
                .disabled(isCreatingGame)
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

    /// Create the game and go straight to the lobby.
    ///
    /// This used to route through CreateGameSheet ("Host a Garden Party") — a splash
    /// screen with an icon, a feature list, and a "Create Game" button, i.e. a second
    /// confirmation of a choice the player had already made by tapping "+".
    private func createGameAndOpenLobby() {
        Task {
            isCreatingGame = true
            let cardYear = gameViewModel.selectedCardYear.rawValue
            let _ = await onlineVM.createGame(
                displayName: appViewModel.playerProfile.displayName,
                avatarImage: appViewModel.playerProfile.avatarImage,
                cardYear: cardYear
            )
            isCreatingGame = false
            // Only advance if the game actually exists. The lobby reads
            // `currentGameId`, so pushing it after a failed create lands the player on
            // an empty screen — which the old sheet did, since it called `onCreated()`
            // unconditionally regardless of whether `createGame` returned nil.
            if onlineVM.currentGameId != nil {
                showLobby = true
            }
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
                createGameAndOpenLobby()
            } label: {
                Label(isCreatingGame ? "Creating…" : "Create Game", systemImage: "plus")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.primary)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .disabled(isCreatingGame)
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
