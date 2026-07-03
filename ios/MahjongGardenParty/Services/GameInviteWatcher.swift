import Foundation
import Supabase
import Realtime

/// App-wide watcher that listens for new game invites in real time and
/// fires a local push notification when one arrives — even if the user
/// is not currently on the Online Games screen.
@Observable
@MainActor
final class GameInviteWatcher {
    static let shared = GameInviteWatcher()

    private var task: Task<Void, Never>?
    private var channel: RealtimeChannelV2?
    private var notifiedInviteIds: Set<String> = []
    private var startedForUserId: String?

    private init() {}

    /// Starts listening for invites for the currently signed-in user.
    /// Safe to call multiple times — only one subscription is kept active.
    func start() {
        guard let userId = OnlineGameService.shared.currentUserId else { return }
        if startedForUserId == userId, task != nil { return }
        stop()
        startedForUserId = userId

        // Auto-request notification permission so invitees actually receive
        // the device push when an invite arrives. Respects the master setting.
        Task { await NotificationService.requestPermissionIfNeeded() }

        // Seed with already-pending invites so we don't re-notify for old ones.
        Task { [weak self] in
            guard let self else { return }
            if let existing = try? await OnlineGameService.shared.fetchMyInvites() {
                for invite in existing {
                    if let id = invite.id { self.notifiedInviteIds.insert(id) }
                }
            }
        }

        let client = SupabaseService.shared.client
        task = Task { [weak self] in
            guard let self else { return }
            let channel = client.channel("invites-watcher-\(userId)")
            let inserts = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "game_invites",
                filter: "receiver_id=eq.\(userId)"
            )
            await channel.subscribe()
            await MainActor.run { self.channel = channel }

            for await action in inserts {
                if Task.isCancelled { break }
                await self.handleInsert(action)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let channel {
            Task { await channel.unsubscribe() }
            self.channel = nil
        }
        startedForUserId = nil
    }

    private func handleInsert(_ action: InsertAction) async {
        do {
            let invite = try action.decodeRecord(as: GameInvite.self, decoder: JSONDecoder())
            // Only notify on pending invites for this user.
            guard invite.status == InviteStatus.pending.rawValue else { return }
            if let id = invite.id {
                if notifiedInviteIds.contains(id) { return }
                notifiedInviteIds.insert(id)
            }

            // Respect user notification settings.
            let masterEnabled = UserDefaults.standard.object(forKey: "settings_notifications_enabled") as? Bool ?? true
            let invitesEnabled = UserDefaults.standard.object(forKey: "settings_game_invites") as? Bool ?? true
            guard masterEnabled && invitesEnabled else { return }

            // Resolve sender display name (fall back to "A friend" if unavailable).
            var senderName = "A friend"
            if let profile = (try? await OnlineGameService.shared.fetchInviteSenderProfile(senderId: invite.senderId)) ?? nil,
               !profile.displayName.isEmpty {
                senderName = profile.displayName
            }

            NotificationService.notifyGameInvite(from: senderName, gameId: invite.gameId)
        } catch {
            print("⚠️ GameInviteWatcher decode: \(error)")
        }
    }
}
