import Foundation
import UserNotifications
import AppKit

@MainActor
final class CountdownNotification: NSObject, UNUserNotificationCenterDelegate {
    static let joinActionId = "JOIN_RECORD"
    static let skipActionId = "SKIP"
    static let categoryId = "MEETING_SOON"

    var onJoin: ((String) -> Void)?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let join = UNNotificationAction(identifier: Self.joinActionId, title: "Join + Record", options: [.foreground])
        let skip = UNNotificationAction(identifier: Self.skipActionId, title: "Skip", options: [])
        let cat = UNNotificationCategory(identifier: Self.categoryId, actions: [join, skip],
                                          intentIdentifiers: [], options: [])
        center.setNotificationCategories([cat])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(meeting: UpcomingMeeting) {
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        content.body = "Starts in 1 minute"
        content.categoryIdentifier = Self.categoryId
        content.userInfo = ["meetingId": meeting.id]
        content.sound = .default
        let req = UNNotificationRequest(identifier: "meeting.\(meeting.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["meetingId"] as? String ?? ""
        if response.actionIdentifier == Self.joinActionId {
            Task { @MainActor in self.onJoin?(id) }
        }
        completionHandler()
    }
}
