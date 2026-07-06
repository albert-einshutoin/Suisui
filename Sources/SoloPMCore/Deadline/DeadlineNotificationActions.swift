import Foundation

/// Identifiers shared between the deadline scheduler, the notification
/// adapter, and the app-side notification responder so a delivered deadline
/// notification can offer actionable buttons.
public enum DeadlineNotificationInteraction {
    /// Notification category carrying task deadline actions.
    public static let taskCategoryIdentifier = "solopm.deadline.task"
    /// userInfo key holding the local task id the notification refers to.
    public static let taskIDUserInfoKey = "solopm.task.id"
    /// Action: mark the referenced task as completed.
    public static let completeTaskActionIdentifier = "solopm.deadline.action.complete-task"
    /// Action: reschedule the same notification one hour from now.
    public static let snoozeOneHourActionIdentifier = "solopm.deadline.action.snooze-1h"

    public static let snoozeInterval: TimeInterval = 3_600
}

public enum DeadlineNotificationActionOutcome: Equatable, Sendable {
    case completedTask(taskID: Int64)
    case snoozed(notificationID: String, until: Date)
    case ignoredUnknownAction
    case ignoredMissingTaskReference
    case failed(String)
}

/// Applies a notification action (from a delivered deadline notification)
/// to local state. Kept framework-free so the logic is unit-testable; the
/// app target adapts UNNotificationResponse into this call.
public struct DeadlineNotificationActionHandler {
    private let taskStore: SQLiteTaskStore
    private let notificationClient: any NotificationClient
    private let dateProvider: any DateProvider

    public init(
        taskStore: SQLiteTaskStore,
        notificationClient: any NotificationClient,
        dateProvider: any DateProvider = SystemDateProvider()
    ) {
        self.taskStore = taskStore
        self.notificationClient = notificationClient
        self.dateProvider = dateProvider
    }

    public func handle(
        actionIdentifier: String,
        notificationTitle: String,
        notificationBody: String?,
        userInfo: [String: String]
    ) -> DeadlineNotificationActionOutcome {
        guard let taskIDText = userInfo[DeadlineNotificationInteraction.taskIDUserInfoKey],
              let taskID = Int64(taskIDText) else {
            return .ignoredMissingTaskReference
        }

        switch actionIdentifier {
        case DeadlineNotificationInteraction.completeTaskActionIdentifier:
            return completeTask(id: taskID)
        case DeadlineNotificationInteraction.snoozeOneHourActionIdentifier:
            return snooze(
                taskID: taskID,
                notificationTitle: notificationTitle,
                notificationBody: notificationBody,
                userInfo: userInfo
            )
        default:
            return .ignoredUnknownAction
        }
    }

    private func completeTask(id: Int64) -> DeadlineNotificationActionOutcome {
        do {
            _ = try taskStore.updateFields(id: id, status: "completed")
            return .completedTask(taskID: id)
        } catch {
            return .failed(UserFacingErrorMessageSanitizer.message(from: error))
        }
    }

    private func snooze(
        taskID: Int64,
        notificationTitle: String,
        notificationBody: String?,
        userInfo: [String: String]
    ) -> DeadlineNotificationActionOutcome {
        let notifyAt = dateProvider.now.addingTimeInterval(DeadlineNotificationInteraction.snoozeInterval)
        let scheduledAt = DeadlineDateParser.string(from: notifyAt)

        do {
            let record = try notificationClient.schedule(
                NotificationDraft(
                    title: notificationTitle,
                    body: notificationBody,
                    scheduledAt: scheduledAt,
                    identifierHint: "solopm-snooze-\(taskID)-\(scheduledAt)",
                    categoryIdentifier: DeadlineNotificationInteraction.taskCategoryIdentifier,
                    userInfo: userInfo
                )
            )
            return .snoozed(notificationID: record.id, until: notifyAt)
        } catch {
            return .failed(UserFacingErrorMessageSanitizer.message(from: error))
        }
    }
}
