import Foundation
import UserNotifications
import WorkProxyCore

final class NotificationService: FailureNotifying, @unchecked Sendable {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    func notifyFailure(_ message: String) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = "workProxy 执行失败"
        content.body = message
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        try? await center.add(request)
    }
}
