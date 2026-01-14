import Foundation
import UserNotifications
import AppKit

actor NotificationService {
    static let shared = NotificationService()

    private init() {}

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }

    func sendNotification(
        title: String,
        body: String,
        url: String?,
        action: NotificationAction
    ) async {
        guard action != .mute else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        if action == .soundAndBanner {
            content.sound = .default
        }

        if let url = url {
            content.userInfo = ["url": url]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to send notification: \(error)")
        }
    }

    func updateBadge(count: Int) async {
        await MainActor.run {
            NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
    }
}
