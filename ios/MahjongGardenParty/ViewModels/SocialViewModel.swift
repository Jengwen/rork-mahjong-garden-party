import SwiftUI

@Observable
@MainActor
class SocialViewModel {
    var friends: [FriendWithProfile] = []
    var pendingRequests: [FriendWithProfile] = []
    var searchResults: [FriendProfile] = []
    var conversations: [Conversation] = []
    var currentMessages: [DirectMessage] = []
    var isLoading: Bool = false
    var searchQuery: String = ""
    var errorMessage: String?
    var tableMissing: Bool = false

    private let supabase = SupabaseService.shared

    // Persisted set of message IDs the user has deleted locally.
    // Ensures deletions stick even if server-side RLS silently blocks the delete.
    private static let hiddenMessagesKey = "hiddenMessageIds.v1"
    private var hiddenMessageIds: Set<String> = {
        let stored = UserDefaults.standard.stringArray(forKey: SocialViewModel.hiddenMessagesKey) ?? []
        return Set(stored)
    }()

    private func persistHiddenIds() {
        UserDefaults.standard.set(Array(hiddenMessageIds), forKey: SocialViewModel.hiddenMessagesKey)
    }

    private func filterHidden(_ messages: [DirectMessage]) -> [DirectMessage] {
        guard !hiddenMessageIds.isEmpty else { return messages }
        return messages.filter { msg in
            guard let id = msg.id else { return true }
            return !hiddenMessageIds.contains(id)
        }
    }

    // MARK: - Moderation (App Store Guideline 1.2)

    /// Everyone this user has blocked, lowercased. Refreshed alongside friends.
    /// Kept in memory because it filters several lists on every render; the
    /// server copy in `blocked_users` is the source of truth.
    private(set) var blockedUserIds: Set<String> = []

    /// Profiles for the blocked set, for the management screen. Loaded lazily —
    /// the common case is an empty block list, which should cost nothing.
    private(set) var blockedProfiles: [FriendProfile] = []

    func isBlocked(_ userId: String) -> Bool {
        blockedUserIds.contains(userId.lowercased())
    }

    private func filterBlocked(_ messages: [DirectMessage]) -> [DirectMessage] {
        guard !blockedUserIds.isEmpty else { return messages }
        return messages.filter { !blockedUserIds.contains($0.senderId.lowercased()) }
    }

    func refreshBlockedUsers() async {
        blockedUserIds = (try? await supabase.fetchBlockedUserIds()) ?? []
    }

    /// Block a user and drop them from every list immediately, so the UI
    /// responds at once rather than waiting for the next refresh.
    func blockUser(_ userId: String) async {
        do {
            try await supabase.blockUser(userId)
            let key = userId.lowercased()
            blockedUserIds.insert(key)
            friends.removeAll { $0.profile.id.lowercased() == key }
            pendingRequests.removeAll { $0.profile.id.lowercased() == key }
            searchResults.removeAll { $0.id.lowercased() == key }
            conversations.removeAll { $0.friend.id.lowercased() == key }
            currentMessages = filterBlocked(currentMessages)
        } catch {
            errorMessage = "Couldn't block this user: \(error.localizedDescription)"
            print("⚠️ blockUser: \(error)")
        }
    }

    func unblockUser(_ userId: String) async {
        do {
            try await supabase.unblockUser(userId)
            let key = userId.lowercased()
            blockedUserIds.remove(key)
            blockedProfiles.removeAll { $0.id.lowercased() == key }
            await loadFriends()
        } catch {
            errorMessage = "Couldn't unblock this user: \(error.localizedDescription)"
            print("⚠️ unblockUser: \(error)")
        }
    }

    func loadBlockedProfiles() async {
        await refreshBlockedUsers()
        var loaded: [FriendProfile] = []
        for id in blockedUserIds {
            if let profile = try? await supabase.fetchFriendProfile(userId: id) {
                loaded.append(profile)
            }
        }
        blockedProfiles = loaded.sorted { $0.displayName < $1.displayName }
    }

    /// File a report. Returns true on success so the view can show confirmation.
    /// Reporting deliberately does NOT auto-block — Apple wants both mechanisms,
    /// and someone may want to flag a one-off message without cutting ties. The
    /// UI offers blocking as a follow-up instead.
    @discardableResult
    func reportContent(
        reportedUserId: String,
        contentType: String,
        contentId: String?,
        contentSnapshot: String?,
        reason: String,
        details: String? = nil
    ) async -> Bool {
        do {
            try await supabase.submitReport(
                reportedUserId: reportedUserId,
                contentType: contentType,
                contentId: contentId,
                contentSnapshot: contentSnapshot,
                reason: reason,
                details: details
            )
            return true
        } catch {
            errorMessage = "Couldn't submit the report: \(error.localizedDescription)"
            print("⚠️ reportContent: \(error)")
            return false
        }
    }

    var currentUserId: String? {
        supabase.currentUserId?.uuidString.lowercased()
    }

    var totalNotificationCount: Int {
        let unreadMessages = friends.reduce(0) { $0 + $1.unreadCount }
        return unreadMessages + pendingRequests.count
    }

    func loadFriends() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load the block list first — everything below is filtered against
            // it, so a blocked user never materialises in the UI at all.
            await refreshBlockedUsers()

            let friendships = try await supabase.fetchFriendships()
            guard let myId = currentUserId else { return }

            var loadedFriends: [FriendWithProfile] = []
            var loadedPending: [FriendWithProfile] = []

            for friendship in friendships {
                let otherUserId = friendship.userId == myId ? friendship.friendId : friendship.userId
                guard !isBlocked(otherUserId) else { continue }
                guard let profile = try await supabase.fetchFriendProfile(userId: otherUserId) else { continue }

                let item = FriendWithProfile(
                    id: friendship.id ?? UUID().uuidString,
                    friendship: friendship,
                    profile: profile,
                    lastMessage: nil,
                    unreadCount: 0
                )

                if friendship.status == FriendshipStatus.accepted.rawValue {
                    loadedFriends.append(item)
                } else if friendship.status == FriendshipStatus.pending.rawValue && friendship.friendId == myId {
                    loadedPending.append(item)
                }
            }

            let unreadCounts = try await supabase.fetchUnreadCounts()
            friends = loadedFriends.map { friend in
                var updated = friend
                updated.unreadCount = unreadCounts[friend.profile.id] ?? 0
                return updated
            }
            pendingRequests = loadedPending
            tableMissing = false
            errorMessage = nil
        } catch let error as DatabaseError {
            tableMissing = true
            errorMessage = error.localizedDescription
            print("⚠️ loadFriends: \(error)")
        } catch {
            errorMessage = "Failed to load friends: \(error.localizedDescription)"
            print("⚠️ loadFriends: \(error)")
        }
    }

    func searchPlayers() async {
        guard searchQuery.count >= 2 else {
            searchResults = []
            return
        }
        do {
            searchResults = try await supabase.searchPlayers(query: searchQuery)
            let friendIds = Set(friends.map(\.profile.id))
            let pendingIds = Set(pendingRequests.map(\.profile.id))
            searchResults = searchResults.filter {
                !friendIds.contains($0.id)
                    && !pendingIds.contains($0.id)
                    // A blocked user must not be findable again by search —
                    // otherwise blocking is trivially undone by looking them up.
                    && !isBlocked($0.id)
            }
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("⚠️ searchPlayers: \(error)")
        }
    }

    func sendFriendRequest(to userId: String) async {
        do {
            try await supabase.sendFriendRequest(to: userId)
            searchResults.removeAll { $0.id == userId }
            await loadFriends()
        } catch let error as DatabaseError {
            tableMissing = true
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to send friend request: \(error.localizedDescription)"
            print("⚠️ sendFriendRequest: \(error)")
        }
    }

    func acceptRequest(_ friendWithProfile: FriendWithProfile) async {
        guard let friendshipId = friendWithProfile.friendship.id else { return }
        do {
            try await supabase.acceptFriendRequest(friendshipId: friendshipId)
            await loadFriends()
        } catch {
            errorMessage = "Failed to accept request: \(error.localizedDescription)"
            print("⚠️ acceptRequest: \(error)")
        }
    }

    func removeFriend(_ friendWithProfile: FriendWithProfile) async {
        guard let friendshipId = friendWithProfile.friendship.id else { return }
        do {
            try await supabase.removeFriend(friendshipId: friendshipId)
            friends.removeAll { $0.id == friendWithProfile.id }
            pendingRequests.removeAll { $0.id == friendWithProfile.id }
        } catch {
            errorMessage = "Failed to remove friend: \(error.localizedDescription)"
            print("⚠️ removeFriend: \(error)")
        }
    }

    func loadMessages(with friendId: String) async {
        do {
            let fetched = try await supabase.fetchMessages(with: friendId)
            currentMessages = filterBlocked(filterHidden(fetched))
            try await supabase.markMessagesAsRead(from: friendId)
        } catch let error as DatabaseError {
            tableMissing = true
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to load messages: \(error.localizedDescription)"
            print("⚠️ loadMessages: \(error)")
        }
    }

    func sendMessage(to friendId: String, content: String) async {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try await supabase.sendMessage(to: friendId, content: content)
            let fetched = try await supabase.fetchMessages(with: friendId)
            currentMessages = filterBlocked(filterHidden(fetched))
        } catch let error as DatabaseError {
            tableMissing = true
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            print("⚠️ sendMessage: \(error)")
        }
    }

    func deleteMessage(_ message: DirectMessage) async {
        guard let messageId = message.id else { return }
        // Always hide locally (and persist) so the deletion is permanent for this user,
        // even if server-side RLS silently blocks the delete.
        hiddenMessageIds.insert(messageId)
        persistHiddenIds()
        currentMessages.removeAll { $0.id == messageId }
        do {
            try await supabase.deleteMessage(messageId: messageId)
        } catch {
            errorMessage = nil
            print("\u{26A0}\u{FE0F} deleteMessage: \(error)")
        }
    }

    func refreshMessages(with friendId: String) async {
        do {
            let fetched = try await supabase.fetchMessages(with: friendId)
            currentMessages = filterBlocked(filterHidden(fetched))
            try await supabase.markMessagesAsRead(from: friendId)
        } catch {
            print("⚠️ refreshMessages: \(error)")
        }
    }
}
