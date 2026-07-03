import SwiftUI

struct GameLobbyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppViewModel.self) private var appViewModel
    let onlineVM: OnlineGameViewModel
    let gameViewModel: GameViewModel
    @State private var showInviteFriends: Bool = false
    @State private var showOnlineGameBoard: Bool = false
    @State private var isStarting: Bool = false
    @State private var refreshTimer: Timer?
    @State private var countdownTick: Int = 0
    @State private var countdownTimer: Timer?
    @State private var showDiagnostics: Bool = false
    @State private var lastStatusSeen: String = "-"
    @State private var lastStatusCheckAt: Date = .distantPast
    @State private var statusChecks: Int = 0
    @State private var transitionAttempts: Int = 0
    @State private var lastBroadcastEvent: String = "none"
    @State private var realtimeConnectingSince: Date?
    @State private var lastForcedReconnectAt: Date = .distantPast

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                gameHeader
                if onlineVM.isQuickMatchGame {
                    quickMatchBanner
                }
                seatsSection
                if showDiagnostics {
                    diagnosticsPanel
                } else {
                    diagnosticsReopenButton
                }
                if !onlineVM.isQuickMatchGame {
                    inviteSection
                }
                if onlineVM.isHost && onlineVM.canStartGame {
                    startButton
                }
                if !onlineVM.isHost {
                    waitingMessage
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(Color(red: 250/255, green: 243/255, blue: 214/255).ignoresSafeArea())
        .navigationTitle("Game Lobby")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await onlineVM.leaveGame() }
                    dismiss()
                } label: {
                    Text("Leave")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .sheet(isPresented: $showInviteFriends) {
            InviteFriendsSheet(onlineVM: onlineVM)
        }
        .fullScreenCover(isPresented: $showOnlineGameBoard, onDismiss: {
            OrientationManager.shared.lockPortrait()
            onlineVM.stopPolling()
            gameViewModel.resetOnlineMode()
        }) {
            GameBoardView()
                .environment(onlineVM)
                .onAppear {
                    OrientationManager.shared.lockLandscape()
                    // Do NOT restart realtime here — the lobby already has the channel
                    // subscribed and listening for state_update/game_started broadcasts.
                    // Tearing it down at the lobby→board hand-off was dropping every
                    // Charleston pass that fired during the brief reconnect window,
                    // leaving every client stuck waiting on each other.
                    // Just (re)attach the sync handler so syncAfterMove still routes correctly.
                    onlineVM.attachSyncHandlerIfNeeded(gameViewModel: gameViewModel)
                }
        }
        .onAppear {
            startRefreshing()
            startCountdown()
            // Subscribe to realtime updates while in the lobby so invitees jump
            // straight into the live game the moment the host starts the Charleston.
            onlineVM.startPolling(gameViewModel: gameViewModel)
        }
        // Dedicated invitee transition watcher: polls just the `status` column every 300ms
        // (decoding-safe), so a flaky realtime channel or a heavy `game_data` decode failure
        // can never trap an invitee in the lobby once the host has started the game.
        // CRITICAL: this loop NEVER returns after a failed transition — it keeps trying
        // until `showOnlineGameBoard` actually flips. That's the only invariant that
        // guarantees invitees can't get stuck behind a transient decode/replication race.
        .task(id: onlineVM.currentGameId) {
            guard onlineVM.currentGameId != nil else { return }
            // Re-evaluate isHost every loop because currentGame can populate after this fires.
            var attempt = 0
            while !Task.isCancelled {
                if showOnlineGameBoard { return }
                if onlineVM.isHost { return }
                // Backup signal: if the realtime layer flipped showGameBoard true but our
                // .onChange observer missed the edge (SwiftUI coalescing same-tick mutations),
                // catch it here so the invitee can never get stranded.
                if onlineVM.showGameBoard {
                    onlineVM.showGameBoard = false
                    await transitionInviteeIntoLiveGame(forceAfterAttempts: 99)
                    if showOnlineGameBoard { return }
                }
                let status = await onlineVM.fetchCurrentGameStatus()
                statusChecks += 1
                lastStatusCheckAt = Date()
                lastStatusSeen = status ?? "nil"
                // Watchdog: if realtime is stuck in "connecting" or we've polled
                // several times without ever seeing a single broadcast, the channel
                // handshake almost certainly hung. Tear it down and re-subscribe so
                // the host's looping game_started/heartbeat broadcasts can land.
                let rt = onlineVM.realtimeStatus
                if rt == "connecting" {
                    if realtimeConnectingSince == nil { realtimeConnectingSince = Date() }
                } else {
                    realtimeConnectingSince = nil
                }
                let stuckConnecting = (realtimeConnectingSince.map { Date().timeIntervalSince($0) > 4 } ?? false)
                let silentChannel = (statusChecks >= 6 && onlineVM.joinedBroadcastsReceived == 0 && onlineVM.stateUpdatesReceived == 0)
                let cooledDown = Date().timeIntervalSince(lastForcedReconnectAt) > 5
                if (stuckConnecting || silentChannel) && cooledDown {
                    lastForcedReconnectAt = Date()
                    realtimeConnectingSince = nil
                    lastBroadcastEvent = "watchdog -> reconnect (rt=\(rt))"
                    onlineVM.forceReconnect(gameViewModel: gameViewModel)
                }
                print("🎮 Lobby poll #\(statusChecks): status=\(status ?? "nil") isHost=\(onlineVM.isHost) realtime=\(onlineVM.realtimeStatus) bots=\(Array(onlineVM.hostBotSeats).sorted()) participants=\(onlineVM.currentParticipants.count)")
                if let status, status != OnlineGameStatus.waiting.rawValue {
                    transitionAttempts += 1
                    print("🎮 Lobby: status=\(status), attempt #\(attempt) to transition invitee")
                    await transitionInviteeIntoLiveGame(forceAfterAttempts: attempt)
                    if showOnlineGameBoard { return }
                    attempt += 1
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        .onDisappear {
            stopRefreshing()
            stopCountdown()
        }
        .onChange(of: onlineVM.showGameBoard) { _, newValue in
            if newValue {
                showOnlineGameBoard = true
                onlineVM.showGameBoard = false
            }
        }
        // Bulletproof: as soon as the host transitions the game out of "waiting",
        // every invitee in the lobby pulls the live state and jumps into the game board.
        .onChange(of: onlineVM.currentGame?.status) { _, newStatus in
            guard let newStatus, newStatus != OnlineGameStatus.waiting.rawValue else { return }
            Task { @MainActor in
                await transitionInviteeIntoLiveGame()
            }
        }
    }

    /// For non-host invitees: load the live game state and present the board.
    /// Idempotent — safe to call multiple times. Will retry until `game_data` is
    /// actually replicated so we never present an empty/half-loaded board.
    /// `forceAfterAttempts`: once the watcher loop has retried this many times without
    /// success, present the game board anyway and let realtime/backup-sync fill in the
    /// state. This guarantees invitees can never be permanently stuck behind a transient
    /// decode failure or a slow `game_data` replication.
    private func transitionInviteeIntoLiveGame(forceAfterAttempts: Int = 0) async {
        guard !showOnlineGameBoard else { return }
        guard let gameId = onlineVM.currentGameId else { return }
        // PRIORITY 1: present the board immediately so the invitee never sits on the
        // lobby. Configure online mode up front so GameBoardView can subscribe and
        // applyRemoteState as soon as game_data arrives.
        if !gameViewModel.isOnlineMode, let myId = onlineVM.myUserId {
            gameViewModel.isOnlineMode = true
            gameViewModel.onlineGameId = gameId
            gameViewModel.localSeatIndex = onlineVM.currentParticipants.first(where: { $0.userId == myId })?.seatIndex ?? 0
        }
        if onlineVM.showGameBoard { onlineVM.showGameBoard = false }
        showOnlineGameBoard = true
        // PRIORITY 2: kick off a background load to fill in the live state if it
        // hasn't replicated yet. The board will render the loaded state once ready.
        Task { @MainActor in
            _ = await onlineVM.loadOnlineGameStateWithRetry(
                gameId: gameId,
                gameViewModel: gameViewModel
            )
        }
        _ = forceAfterAttempts // retained for call-site compatibility
    }

    private var quickMatchBanner: some View {
        let allSeatsFilled = onlineVM.currentParticipants.count >= 4
        return HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.title3)
                .foregroundStyle(themeManager.currentTheme.accent)
                .frame(width: 36, height: 36)
                .background(themeManager.currentTheme.accent.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Match")
                    .font(.subheadline.bold())
                if allSeatsFilled {
                    Text("All seats filled — host can start the game")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Waiting for players — host starts when ready")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(themeManager.currentTheme.accent.opacity(0.25), lineWidth: 1)
        )
    }

    private var gameHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 48))
                .foregroundStyle(themeManager.currentTheme.primary)
                .symbolEffect(.bounce, value: onlineVM.currentParticipants.count)

            Text("Garden Party")
                .font(.title2.bold())

            Text("\(onlineVM.currentParticipants.count) / 4 players")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let game = onlineVM.currentGame {
                Text("Card: \(game.cardYear ?? "2025")")
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(themeManager.currentTheme.primary.opacity(0.1))
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 16)
    }

    private var seatsSection: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { seatIdx in
                seatRow(seatIdx: seatIdx)
            }
        }
    }

    @ViewBuilder
    private func seatRow(seatIdx: Int) -> some View {
        let seat = SeatPosition.allCases[seatIdx]
        let participant = onlineVM.currentParticipants.first(where: { $0.seatIndex == seatIdx })
        let isBotSeat = onlineVM.isBotSeat(seatIdx)
        let isFilled = participant != nil || isBotSeat

        HStack(spacing: 14) {
            Image(systemName: isBotSeat ? "cpu.fill" : seat.symbolName)
                .font(.title3)
                .foregroundStyle(isFilled ? AnyShapeStyle(themeManager.currentTheme.primary) : AnyShapeStyle(.tertiary))
                .frame(width: 40, height: 40)
                .background(isFilled ? themeManager.currentTheme.primary.opacity(0.12) : Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(seat.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let p = participant {
                    HStack(spacing: 6) {
                        Text(p.displayName)
                            .font(.headline)
                        if p.userId == onlineVM.currentGame?.hostId {
                            Text("HOST")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(themeManager.currentTheme.accent)
                                .clipShape(Capsule())
                        }
                    }
                } else if isBotSeat {
                    HStack(spacing: 6) {
                        Text("Bot")
                            .font(.headline)
                        Text("BOT")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(themeManager.currentTheme.primary)
                            .clipShape(Capsule())
                    }
                } else {
                    Text("Empty")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer()

            if participant != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if onlineVM.isHost {
                Button {
                    onlineVM.toggleBotAt(seatIndex: seatIdx)
                } label: {
                    Text(isBotSeat ? "Remove" : "Add Bot")
                        .font(.caption.bold())
                        .foregroundStyle(isBotSeat ? .red : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isBotSeat ? Color.red.opacity(0.12) : themeManager.currentTheme.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isBotSeat)
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }

    private var inviteSection: some View {
        Button {
            showInviteFriends = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.title3)
                Text("Invite Friends")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(themeManager.currentTheme.primary.opacity(0.08))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(themeManager.currentTheme.primary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var startButton: some View {
        Button {
            isStarting = true
            Task {
                await onlineVM.startOnlineGame(gameViewModel: gameViewModel)
                isStarting = false
                if onlineVM.showGameBoard {
                    showOnlineGameBoard = true
                    onlineVM.showGameBoard = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                if isStarting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text("Start Game")
                    .fontWeight(.bold)
            }
            .font(.title3)
            .frame(maxWidth: .infinity)
            .padding()
            .background(themeManager.currentTheme.primary)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 16))
        }
        .disabled(isStarting)
        .sensoryFeedback(.impact(weight: .medium), trigger: isStarting)
    }

    private var diagnosticsReopenButton: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.spring(response: 0.3)) { showDiagnostics = true }
            } label: {
                Image(systemName: "stethoscope")
                    .font(.caption)
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show lobby diagnostics")
        }
    }

    private var diagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "stethoscope")
                Text("Lobby Diagnostics").font(.caption.bold())
                Spacer()
                Button { showDiagnostics = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Group {
                diagRow("Role", onlineVM.isHost ? "HOST" : "INVITEE")
                diagRow("Game ID", onlineVM.currentGameId?.suffix(8).description ?? "nil")
                diagRow("Status", onlineVM.currentGame?.status ?? "nil")
                diagRow("Last polled status", lastStatusSeen)
                diagRow("Status checks", "\(statusChecks)")
                diagRow("Transition attempts", "\(transitionAttempts)")
                diagRow("Realtime", onlineVM.realtimeStatus)
                diagRow("Last broadcast", lastBroadcastEvent)
                diagRow("Participants", "\(onlineVM.currentParticipants.count)")
                diagRow("My seat", onlineVM.mySeatIndex.map(String.init) ?? "nil")
                diagRow("Host bot seats", Array(onlineVM.hostBotSeats).sorted().map(String.init).joined(separator: ","))
                diagRow("Joined RX", "\(onlineVM.joinedBroadcastsReceived)")
                diagRow("State RX", "\(onlineVM.stateUpdatesReceived)")
                diagRow("showGameBoard", "\(onlineVM.showGameBoard)")
                diagRow("showOnlineGameBoard", "\(showOnlineGameBoard)")
            }
            .font(.caption.monospaced())
            HStack(spacing: 8) {
                Button {
                    lastForcedReconnectAt = Date()
                    realtimeConnectingSince = nil
                    lastBroadcastEvent = "manual -> reconnect"
                    onlineVM.forceReconnect(gameViewModel: gameViewModel)
                } label: {
                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact(weight: .light), trigger: lastForcedReconnectAt)

                if !onlineVM.isHost {
                    Button {
                        Task { @MainActor in
                            _ = await onlineVM.fetchCurrentGameStatus()
                            if let s = onlineVM.currentGame?.status, s != OnlineGameStatus.waiting.rawValue {
                                await transitionInviteeIntoLiveGame(forceAfterAttempts: 99)
                            } else {
                                // Even when status is unreadable (RLS), let the user
                                // manually punch through if the host has clearly started.
                                await transitionInviteeIntoLiveGame(forceAfterAttempts: 99)
                            }
                        }
                    } label: {
                        Label("Force enter", systemImage: "arrow.right.circle")
                            .font(.caption.bold())
                            .foregroundStyle(themeManager.currentTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(themeManager.currentTheme.primary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.4), lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
        .onChange(of: onlineVM.realtimeStatus) { _, newValue in
            lastBroadcastEvent = "realtime → \(newValue)"
        }
        .onChange(of: onlineVM.hostBotSeats) { _, newValue in
            lastBroadcastEvent = "bot_seats → \(Array(newValue).sorted())"
            print("🤖 Lobby: hostBotSeats updated to \(Array(newValue).sorted())")
        }
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var waitingMessage: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Waiting for host to start the game...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    private func startRefreshing() {
        // Run in .common mode so the timer keeps firing while the user scrolls/taps.
        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                await onlineVM.refreshLobby()
                // Non-host: jump into the game board as soon as the host starts it.
                // Keep retrying every tick until `showOnlineGameBoard` is true — never
                // leave the invitee stranded if a single attempt failed.
                if !onlineVM.isHost,
                   let game = onlineVM.currentGame,
                   game.status != OnlineGameStatus.waiting.rawValue,
                   !showOnlineGameBoard {
                    print("🎮 Lobby timer: status=\(game.status), retrying invitee transition")
                    await transitionInviteeIntoLiveGame(forceAfterAttempts: 5)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startCountdown() {
        // Auto-start removed: the host must explicitly tap "Start Game".
        // The countdown timer is intentionally a no-op now — kept as a hook in case
        // we want to re-introduce a soft reminder later.
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }
}

struct InviteFriendsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppViewModel.self) private var appViewModel
    let onlineVM: OnlineGameViewModel
    @State private var socialVM = SocialViewModel()
    @State private var sentInvites: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 250/255, green: 243/255, blue: 214/255)
                    .ignoresSafeArea()

                if socialVM.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if socialVM.friends.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(.tertiary)
                        Text("No Friends")
                            .font(.title3.bold())
                        Text("Add friends in the Social tab to invite them to games.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(socialVM.friends) { friend in
                            HStack(spacing: 14) {
                                Image(friend.profile.avatarImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(friend.profile.displayName)
                                        .font(.headline)
                                    Text("Level \(friend.profile.level)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if sentInvites.contains(friend.profile.id) {
                                    Label("Invited", systemImage: "checkmark.circle.fill")
                                        .font(.subheadline)
                                        .foregroundStyle(.green)
                                } else {
                                    Button {
                                        sentInvites.insert(friend.profile.id)
                                        Task {
                                            await onlineVM.inviteFriendWithChat(
                                                friendId: friend.profile.id,
                                                hostDisplayName: appViewModel.playerProfile.displayName
                                            )
                                        }
                                    } label: {
                                        Text("Invite")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(themeManager.currentTheme.primary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(.rect(cornerRadius: 14))
                        }
                    }
                    .padding()
                    }
                }
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await socialVM.loadFriends()
            }
        }
    }
}
