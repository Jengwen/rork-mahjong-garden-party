import SwiftUI

struct ConversationView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(AppViewModel.self) private var appViewModel
    @Environment(GameViewModel.self) private var gameViewModel
    @Environment(\.dismiss) private var dismiss
    let friend: FriendWithProfile
    let socialVM: SocialViewModel
    @State private var messageText: String = ""
    @State private var scrollToBottom: Bool = false
    @State private var onlineVM = OnlineGameViewModel()
    @State private var showLobby: Bool = false
    @State private var showOnlineGameBoard: Bool = false
    @State private var acceptingInviteId: String?
    @State private var messageToDelete: DirectMessage?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messagesList

            Divider()

            inputBar
        }
        .background(Color(red: 250/255, green: 243/255, blue: 214/255).ignoresSafeArea())
        .navigationTitle(friend.profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(friend.profile.avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 0) {
                        Text(friend.profile.displayName)
                            .font(.subheadline.bold())
                        Text(friend.isOnline ? "Online" : "Offline")
                            .font(.caption2)
                            .foregroundStyle(friend.isOnline ? .green : .secondary)
                    }
                }
            }
        }
        .task {
            await socialVM.loadMessages(with: friend.profile.id)
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
        // "waiting", force this invitee out of the lobby and into the board —
        // independent of any internal lobby transition path.
        .onChange(of: onlineVM.showGameBoard) { _, newValue in
            guard newValue else { return }
            forceTransitionToGameBoard()
        }
        .onChange(of: onlineVM.currentGame?.status) { _, newStatus in
            guard let newStatus, newStatus != OnlineGameStatus.waiting.rawValue else { return }
            forceTransitionToGameBoard()
        }
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(
                get: { messageToDelete != nil },
                set: { if !$0 { messageToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let message = messageToDelete {
                    Task { await socialVM.deleteMessage(message) }
                }
                messageToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                messageToDelete = nil
            }
        } message: {
            Text("This will remove the message for everyone.")
        }
    }

    /// Fallback invitee transition. Only fires when the lobby is NOT currently on
    /// screen — when the lobby IS visible, it owns the fullScreenCover transition
    /// itself. Popping the lobby AND presenting a cover from the parent at the
    /// same time causes SwiftUI to cancel the cover, leaving the invitee stuck.
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

    private func acceptInvite(gameId: String, messageId: String?) {
        acceptingInviteId = messageId
        Task {
            let ok = await onlineVM.acceptGameInviteFromChat(
                gameId: gameId,
                displayName: appViewModel.playerProfile.displayName,
                avatarImage: appViewModel.playerProfile.avatarImage
            )
            acceptingInviteId = nil
            if ok { showLobby = true }
        }
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if socialVM.currentMessages.isEmpty {
                        emptyConversation
                    } else {
                        let rows = buildRows(from: socialVM.currentMessages)
                        ForEach(rows, id: \.stableId) { row in
                            let isMe = row.message.senderId == socialVM.currentUserId

                            if row.showTimestamp {
                                Text(formatGroupTimestamp(row.message.createdAt))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.bottom, 2)
                            }

                            if let invite = GameInvitePayload.parse(row.message.content) {
                                GameInviteBubble(
                                    invite: invite,
                                    isMe: isMe,
                                    theme: themeManager.currentTheme,
                                    isAccepting: acceptingInviteId == row.message.id,
                                    onAccept: { acceptInvite(gameId: invite.gameId, messageId: row.message.id) }
                                )
                                .id(row.stableId)
                                .contextMenu {
                                    if row.message.id != nil {
                                        Button(role: .destructive) {
                                            messageToDelete = row.message
                                        } label: {
                                            Label("Delete Invite", systemImage: "trash")
                                        }
                                    }
                                }
                            } else {
                                MessageBubble(
                                    message: row.message,
                                    isMe: isMe,
                                    theme: themeManager.currentTheme
                                )
                                .id(row.stableId)
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = row.message.content
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    if isMe && row.message.id != nil {
                                        Button(role: .destructive) {
                                            messageToDelete = row.message
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: socialVM.currentMessages.count) { _, _ in
                scrollToLast(proxy: proxy)
            }
            .onChange(of: scrollToBottom) { _, _ in
                scrollToLast(proxy: proxy)
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 16) {
            Image(friend.profile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .background(
                    Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                        .frame(width: 72, height: 72)
                )

            Text(friend.profile.displayName)
                .font(.title3.bold())

            Text("This is the beginning of your conversation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Message...", text: $messageText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 20))
                .focused($isInputFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(.tertiaryLabel)
                        : themeManager.currentTheme.primary
                    )
            }
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .sensoryFeedback(.impact(weight: .light), trigger: socialVM.currentMessages.count)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func sendMessage() {
        let content = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        messageText = ""
        Task {
            await socialVM.sendMessage(to: friend.profile.id, content: content)
            scrollToBottom.toggle()
        }
    }

    private struct ChatRow: Identifiable {
        let id: String
        let stableId: String
        let message: DirectMessage
        let showTimestamp: Bool
    }

    private func buildRows(from messages: [DirectMessage]) -> [ChatRow] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()

        var rows: [ChatRow] = []
        rows.reserveCapacity(messages.count)
        var prevDate: Date?
        for (index, message) in messages.enumerated() {
            var showTimestamp = (index == 0)
            let currentDate: Date? = {
                guard let ts = message.createdAt else { return nil }
                return formatter.date(from: ts) ?? fallback.date(from: ts)
            }()
            if let cur = currentDate, let prev = prevDate, cur.timeIntervalSince(prev) > 300 {
                showTimestamp = true
            }
            let key = message.id ?? "local-\(index)-\(message.senderId)-\(message.createdAt ?? "")"
            rows.append(ChatRow(id: key, stableId: key, message: message, showTimestamp: showTimestamp))
            if let cur = currentDate { prevDate = cur }
        }
        return rows
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        guard let last = socialVM.currentMessages.last else { return }
        let key = last.id ?? "local-\(socialVM.currentMessages.count - 1)-\(last.senderId)-\(last.createdAt ?? "")"
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(key, anchor: .bottom)
        }
    }

    private func formatGroupTimestamp(_ ts: String?) -> String {
        guard let ts else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let date = formatter.date(from: ts) ?? fallback.date(from: ts) else { return "" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let df = DateFormatter()
            df.timeStyle = .short
            return "Today \(df.string(from: date))"
        } else if calendar.isDateInYesterday(date) {
            let df = DateFormatter()
            df.timeStyle = .short
            return "Yesterday \(df.string(from: date))"
        } else {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return df.string(from: date)
        }
    }
}

struct MessageBubble: View {
    let message: DirectMessage
    let isMe: Bool
    let theme: AppTheme

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 60) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.subheadline)
                    .foregroundStyle(isMe ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(isMe ? theme.primary : Color(.tertiarySystemFill))
                    .clipShape(
                        .rect(
                            topLeadingRadius: isMe ? 16 : 4,
                            bottomLeadingRadius: 16,
                            bottomTrailingRadius: isMe ? 4 : 16,
                            topTrailingRadius: 16
                        )
                    )

                if let ts = message.createdAt {
                    Text(formatTime(ts))
                        .font(.system(size: 10))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 4)
                }
            }

            if !isMe { Spacer(minLength: 60) }
        }
    }

    private func formatTime(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        guard let date = formatter.date(from: ts) ?? fallback.date(from: ts) else { return "" }
        let df = DateFormatter()
        df.timeStyle = .short
        return df.string(from: date)
    }
}

struct GameInvitePayload {
    let gameId: String
    let cardYear: String
    let hostName: String

    static func parse(_ content: String) -> GameInvitePayload? {
        guard content.hasPrefix("__GAME_INVITE__|") else { return nil }
        let parts = content.split(separator: "|", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }
        return GameInvitePayload(gameId: parts[1], cardYear: parts[2], hostName: parts[3])
    }
}

struct GameInviteBubble: View {
    let invite: GameInvitePayload
    let isMe: Bool
    let theme: AppTheme
    let isAccepting: Bool
    let onAccept: () -> Void

    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "party.popper.fill")
                        .font(.title3)
                        .foregroundStyle(theme.primary)
                        .frame(width: 36, height: 36)
                        .background(theme.primary.opacity(0.15))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Garden Party Invite")
                            .font(.subheadline.bold())
                        Text("\(invite.hostName) invited you to play")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "menucard.fill")
                        .font(.caption2)
                    Text("NMJL \(invite.cardYear)")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)

                if isMe {
                    Text("Invite sent")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(.rect(cornerRadius: 10))
                } else {
                    Button(action: onAccept) {
                        HStack(spacing: 6) {
                            if isAccepting {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isAccepting ? "Joining..." : "Accept & Join")
                                .fontWeight(.bold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(theme.primary)
                        .clipShape(.rect(cornerRadius: 10))
                    }
                    .disabled(isAccepting)
                }
            }
            .padding(12)
            .frame(maxWidth: 280, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(theme.primary.opacity(0.3), lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 16))

            if !isMe { Spacer(minLength: 40) }
        }
    }
}
