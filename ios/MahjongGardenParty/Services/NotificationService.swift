import UserNotifications
import UIKit
import Supabase
import Functions

@MainActor
struct NotificationService {
    /// Returns true if user has granted notification permission.
    static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Requests permission if not yet determined; always re-registers for
    /// remote notifications when authorized so APNs can deliver pushes.
    @discardableResult
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        switch status {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                if granted {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                return granted
            } catch {
                print("⚠️ Notification permission error: \(error)")
                return false
            }
        case .authorized, .provisional, .ephemeral:
            // Already authorized — make sure APNs token is current.
            UIApplication.shared.registerForRemoteNotifications()
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// Opens iOS Settings for this app so the user can toggle notifications.
    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func scheduleLocalNotification(
        title: String,
        body: String,
        identifier: String,
        userInfo: [AnyHashable: Any] = [:],
        delay: TimeInterval = 1
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(0.1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("⚠️ scheduleLocalNotification: \(error)")
            }
        }
    }

    static func notifyGameInvite(from senderName: String, gameId: String) {
        scheduleLocalNotification(
            title: "Game Invite",
            body: "\(senderName) invited you to play Mahjong",
            identifier: "invite-\(gameId)",
            userInfo: ["type": "invite", "gameId": gameId]
        )
    }

    /// Best-effort remote push: invokes a Supabase Edge Function (`send-game-invite-push`)
    /// so the invitee's device receives an APNs push even when the app is closed.
    /// Silently no-ops if the function isn't deployed or fails — the in-app realtime
    /// watcher (GameInviteWatcher) still fires a local notification while the app runs.
    static func sendInvitePush(receiverId: String, gameId: String, senderName: String) async {
        nonisolated struct Payload: Encodable {
            let receiverId: String
            let gameId: String
            let senderName: String
        }
        let payload = Payload(receiverId: receiverId, gameId: gameId, senderName: senderName)
        do {
            try await SupabaseService.shared.client.functions.invoke(
                "send-game-invite-push",
                options: .init(body: payload)
            )
        } catch {
            // Edge function missing or transient failure — non-fatal.
            print("ℹ️ sendInvitePush (non-fatal): \(error)")
        }
    }

    /// Convenience: requests notification permission if the user hasn't been asked yet
    /// AND has the in-app notifications setting enabled. Idempotent.
    static func requestPermissionIfNeeded() async {
        let masterEnabled = UserDefaults.standard.object(forKey: "settings_notifications_enabled") as? Bool ?? true
        guard masterEnabled else { return }
        let status = await currentAuthorizationStatus()
        guard status == .notDetermined else {
            if status == .authorized || status == .provisional || status == .ephemeral {
                UIApplication.shared.registerForRemoteNotifications()
            }
            return
        }
        _ = await requestPermission()
    }

    static func notifyTurnReminder(gameId: String) {
        scheduleLocalNotification(
            title: "Your Turn",
            body: "It's your turn to play.",
            identifier: "turn-\(gameId)-\(Int(Date().timeIntervalSince1970))",
            userInfo: ["type": "turn", "gameId": gameId]
        )
    }

    static func notifyFriendRequest(from senderName: String, requestId: String) {
        scheduleLocalNotification(
            title: "Friend Request",
            body: "\(senderName) sent you a friend request",
            identifier: "friend-\(requestId)",
            userInfo: ["type": "friend", "requestId": requestId]
        )
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }
}
