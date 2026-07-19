import Foundation
import SuisuiCore
@preconcurrency import UserNotifications

final class UserNotificationsNotificationClient: NotificationClient, @unchecked Sendable {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
        guard isAuthorized() else {
            throw ToolClientError.permissionDenied("Notification permission is denied.")
        }

        guard let scheduledDate = ISO8601DateFormatter().date(from: draft.scheduledAt) else {
            throw ToolClientError.invalidRequest("Invalid notification date: \(draft.scheduledAt)")
        }

        let content = UNMutableNotificationContent()
        content.title = draft.title
        content.body = draft.body ?? ""
        if let categoryIdentifier = draft.categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        if !draft.userInfo.isEmpty {
            content.userInfo = draft.userInfo
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: scheduledDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = draft.identifierHint ?? "suisui-notification-\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        let callbackError = CallbackBox<Error>()
        let semaphore = DispatchSemaphore(value: 0)
        center.add(request) { error in
            callbackError.value = error
            semaphore.signal()
        }
        semaphore.wait()

        if let callbackError = callbackError.value {
            throw ToolClientError.invalidRequest(callbackError.localizedDescription)
        }

        return NotificationRecord(id: identifier, title: draft.title, body: draft.body, scheduledAt: draft.scheduledAt)
    }

    func cancel(id: String) throws {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    func listScheduled() throws -> [NotificationRecord] {
        let requests = CallbackBox<[UNNotificationRequest]>()
        let semaphore = DispatchSemaphore(value: 0)
        center.getPendingNotificationRequests { pending in
            requests.value = pending
            semaphore.signal()
        }
        semaphore.wait()

        guard let pendingRequests = requests.value else {
            throw ToolClientError.invalidRequest("Pending notification requests could not be loaded.")
        }

        return pendingRequests.map { request in
            NotificationRecord(
                id: request.identifier,
                title: request.content.title,
                body: request.content.body.isEmpty ? nil : request.content.body,
                scheduledAt: Self.scheduledAt(from: request.trigger)
            )
        }
    }

    private func isAuthorized() -> Bool {
        let settings = CallbackBox<UNNotificationSettings>()
        let semaphore = DispatchSemaphore(value: 0)
        center.getNotificationSettings { value in
            settings.value = value
            semaphore.signal()
        }
        semaphore.wait()

        switch settings.value?.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private static func scheduledAt(from trigger: UNNotificationTrigger?) -> String {
        guard let calendarTrigger = trigger as? UNCalendarNotificationTrigger,
              let date = calendarTrigger.nextTriggerDate() else {
            return ""
        }

        return ISO8601DateFormatter().string(from: date)
    }
}

struct UserNotificationsPermissionSnapshotReader {
    static func snapshot(center: UNUserNotificationCenter = .current()) -> PermissionSnapshot {
        let settings = CallbackBox<UNNotificationSettings>()
        let semaphore = DispatchSemaphore(value: 0)
        center.getNotificationSettings { value in
            settings.value = value
            semaphore.signal()
        }
        semaphore.wait()

        var snapshot = PermissionSnapshot.empty
        snapshot.setStatus(permissionStatus(from: settings.value?.authorizationStatus), for: .notifications)
        return snapshot
    }

    private static func permissionStatus(from status: UNAuthorizationStatus?) -> PermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .granted
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        default:
            .restricted
        }
    }
}

private final class CallbackBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value?

    var value: Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedValue = newValue
        }
    }
}
