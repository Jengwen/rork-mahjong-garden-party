import SwiftUI

struct SocialView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SocialViewModel.self) private var socialVM
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: SocialSection = .friends
    @State private var showAddFriend: Bool = false
    @State private var selectedFriend: FriendWithProfile?

    var body: some View {
        NavigationStack {
            Group {
                if horizontalSizeClass == .regular {
                    iPadLayout
                } else {
                    iPhoneLayout
                }
            }
            .background(Color.white.ignoresSafeArea())
            .navigationTitle("Social")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddFriend = true } label: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(themeManager.currentTheme.primary)
                    }
                }
            }
            .sheet(isPresented: $showAddFriend) {
                AddFriendSheet(socialVM: socialVM)
            }
            .navigationDestination(for: FriendWithProfile.self) { friend in
                ConversationView(friend: friend, socialVM: socialVM)
            }
            .task {
                await socialVM.loadFriends()
            }
            .refreshable {
                await socialVM.loadFriends()
            }
        }
    }

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            sectionPicker

            Group {
                switch selectedSection {
                case .friends:
                    friendsContent
                case .messages:
                    messagesContent
                case .requests:
                    requestsContent
                }
            }
        }
    }

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                iPadMainPicker

                Group {
                    switch selectedSection {
                    case .friends:
                        friendsContent
                    case .messages:
                        messagesContent
                    case .requests:
                        requestsContent
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider()

            iPadSidePanel
                .frame(width: 340)
        }
    }

    private var iPadMainPicker: some View {
        HStack(spacing: 0) {
            ForEach(SocialSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.snappy) { selectedSection = section }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(section.rawValue)
                                .font(.subheadline)
                                .fontWeight(selectedSection == section ? .bold : .regular)

                            if section == .requests && !socialVM.pendingRequests.isEmpty {
                                Text("\(socialVM.pendingRequests.count)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(themeManager.currentTheme.accent)
                                    .clipShape(Circle())
                            }

                            if section == .messages {
                                let totalUnread = socialVM.friends.reduce(0) { $0 + $1.unreadCount }
                                if totalUnread > 0 {
                                    Text("\(totalUnread)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(.red)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .foregroundStyle(selectedSection == section ? themeManager.currentTheme.primary : .secondary)

                        Rectangle()
                            .fill(selectedSection == section ? themeManager.currentTheme.primary : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    private var iPadSidePanel: some View {
        VStack(spacing: 0) {
            iPadAddFriendSection

            Divider()
                .padding(.vertical, 8)

            iPadRequestsSection
        }
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var iPadAddFriendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Add Friend", systemImage: "person.badge.plus")
                    .font(.headline)
                    .foregroundStyle(themeManager.currentTheme.primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            Button {
                showAddFriend = true
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("Search for players...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    private var iPadRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Friend Requests", systemImage: "envelope.badge")
                    .font(.headline)
                    .foregroundStyle(themeManager.currentTheme.primary)
                Spacer()
                if !socialVM.pendingRequests.isEmpty {
                    Text("\(socialVM.pendingRequests.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(themeManager.currentTheme.accent)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)

            if socialVM.pendingRequests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "envelope.open")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No pending requests")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(socialVM.pendingRequests) { request in
                            iPadRequestRow(request: request)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.top, 4)
    }

    private func iPadRequestRow(request: FriendWithProfile) -> some View {
        HStack(spacing: 10) {
            Image(request.profile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .background(
                    Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                        .frame(width: 44, height: 44)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(request.profile.displayName)
                    .font(.subheadline.bold())
                Label("Lvl \(request.profile.level)", systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await socialVM.acceptRequest(request) }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(themeManager.currentTheme.primary)
            }

            Button {
                Task { await socialVM.removeFriend(request) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var sectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(SocialSection.allCases, id: \.self) { section in
                Button {
                    withAnimation(.snappy) { selectedSection = section }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(section.rawValue)
                                .font(.subheadline)
                                .fontWeight(selectedSection == section ? .bold : .regular)

                            if section == .requests && !socialVM.pendingRequests.isEmpty {
                                Text("\(socialVM.pendingRequests.count)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(themeManager.currentTheme.accent)
                                    .clipShape(Circle())
                            }

                            if section == .messages {
                                let totalUnread = socialVM.friends.reduce(0) { $0 + $1.unreadCount }
                                if totalUnread > 0 {
                                    Text("\(totalUnread)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(.red)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .foregroundStyle(selectedSection == section ? themeManager.currentTheme.primary : .secondary)

                        Rectangle()
                            .fill(selectedSection == section ? themeManager.currentTheme.primary : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Friends

    private var friendsContent: some View {
        ScrollView {
            if socialVM.isLoading && socialVM.friends.isEmpty {
                loadingState
            } else if socialVM.friends.isEmpty {
                emptyFriendsState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(socialVM.friends) { friend in
                        FriendCardRow(friend: friend, socialVM: socialVM)
                    }
                }
                .padding()
            }
        }
    }

    private var emptyFriendsState: some View {
        VStack(spacing: 16) {
            if socialVM.tableMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.orange)
                Text("Database Setup Required")
                    .font(.title3.bold())
                Text(socialVM.errorMessage ?? "The friendships table needs to be created in your Supabase database.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Image(systemName: "person.2.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("No Friends Yet")
                    .font(.title3.bold())
                Text("Search for players and send them a friend request to start playing together.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Button {
                    showAddFriend = true
                } label: {
                    Label("Find Friends", systemImage: "magnifyingglass")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(themeManager.currentTheme.primary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Messages

    private var messagesContent: some View {
        ScrollView {
            if socialVM.friends.isEmpty {
                emptyMessagesState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(socialVM.friends) { friend in
                        NavigationLink(value: friend) {
                            MessagePreviewRow(friend: friend)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private var emptyMessagesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No Messages")
                .font(.title3.bold())
            Text("Add friends to start chatting!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Requests

    private var requestsContent: some View {
        ScrollView {
            if socialVM.pendingRequests.isEmpty {
                emptyRequestsState
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(socialVM.pendingRequests) { request in
                        FriendRequestRow(request: request, socialVM: socialVM)
                    }
                }
                .padding()
            }
        }
    }

    private var emptyRequestsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No Pending Requests")
                .font(.title3.bold())
            Text("When someone sends you a friend request, it will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

enum SocialSection: String, CaseIterable {
    case friends = "Friends"
    case messages = "Messages"
    case requests = "Requests"
}

// MARK: - Friend Card Row

struct FriendCardRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let friend: FriendWithProfile
    let socialVM: SocialViewModel
    @State private var showRemoveConfirm: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(friend.profile.avatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .background(
                        Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                            .frame(width: 52, height: 52)
                    )

                Circle()
                    .fill(friend.isOnline ? .green : .gray)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.profile.displayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Label("Lvl \(friend.profile.level)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(friend.profile.totalWins)W / \(friend.profile.totalGames)G")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            NavigationLink(value: friend) {
                Image(systemName: "message.fill")
                    .font(.subheadline)
                    .foregroundStyle(themeManager.currentTheme.primary)
                    .frame(width: 36, height: 36)
                    .background(themeManager.currentTheme.primary.opacity(0.1))
                    .clipShape(Circle())
            }

            Menu {
                Button(role: .destructive) {
                    showRemoveConfirm = true
                } label: {
                    Label("Remove Friend", systemImage: "person.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 36)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .confirmationDialog("Remove \(friend.profile.displayName)?", isPresented: $showRemoveConfirm) {
            Button("Remove Friend", role: .destructive) {
                Task { await socialVM.removeFriend(friend) }
            }
        }
    }
}

// MARK: - Message Preview Row

struct MessagePreviewRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let friend: FriendWithProfile

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(friend.profile.avatarImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .background(
                        Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                            .frame(width: 52, height: 52)
                    )

                if friend.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.profile.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let lastMsg = friend.lastMessage {
                    Text(lastMsg.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Tap to start chatting")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let lastMsg = friend.lastMessage, let ts = lastMsg.createdAt {
                    Text(formatTimestamp(ts))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if friend.unreadCount > 0 {
                    Text("\(friend.unreadCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(themeManager.currentTheme.accent)
                        .clipShape(Capsule())
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }

    private func formatTimestamp(_ ts: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: ts) else {
            let fallback = ISO8601DateFormatter()
            guard let d = fallback.date(from: ts) else { return "" }
            return RelativeDateTimeFormatter().localizedString(for: d, relativeTo: Date())
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Friend Request Row

struct FriendRequestRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let request: FriendWithProfile
    let socialVM: SocialViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image(request.profile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(Circle())
                .background(
                    Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                        .frame(width: 52, height: 52)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(request.profile.displayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Label("Lvl \(request.profile.level)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                Task { await socialVM.acceptRequest(request) }
            } label: {
                Text("Accept")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(themeManager.currentTheme.primary)
                    .clipShape(Capsule())
            }

            Button {
                Task { await socialVM.removeFriend(request) }
            } label: {
                Text("Decline")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 14))
    }
}

// MARK: - Add Friend Sheet

struct AddFriendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager
    let socialVM: SocialViewModel
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by display name...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { performSearch() }
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemFill))
                .clipShape(.rect(cornerRadius: 12))
                .padding()

                ScrollView {
                    if isSearching {
                        ProgressView()
                            .padding(.top, 40)
                    } else if socialVM.searchResults.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.slash")
                                .font(.system(size: 36))
                                .foregroundStyle(.tertiary)
                            Text("No players found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(socialVM.searchResults) { profile in
                                SearchResultRow(profile: profile, socialVM: socialVM)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .background(Color(red: 250/255, green: 243/255, blue: 214/255).ignoresSafeArea())
            .navigationTitle("Find Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: searchText) { _, newValue in
                socialVM.searchQuery = newValue
                guard newValue.count >= 2 else {
                    socialVM.searchResults = []
                    return
                }
                performSearch()
            }
        }
    }

    private func performSearch() {
        isSearching = true
        Task {
            await socialVM.searchPlayers()
            isSearching = false
        }
    }
}

struct SearchResultRow: View {
    @Environment(ThemeManager.self) private var themeManager
    let profile: FriendProfile
    let socialVM: SocialViewModel
    @State private var requestSent: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(profile.avatarImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
                .background(
                    Circle().fill(themeManager.currentTheme.primary.opacity(0.1))
                        .frame(width: 48, height: 48)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Label("Lvl \(profile.level)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(profile.totalWins) wins")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if requestSent {
                Label("Sent", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            } else {
                Button {
                    requestSent = true
                    Task { await socialVM.sendFriendRequest(to: profile.id) }
                } label: {
                    Label("Add", systemImage: "person.badge.plus")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
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

extension FriendWithProfile: @retroactive Hashable {
    static func == (lhs: FriendWithProfile, rhs: FriendWithProfile) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
