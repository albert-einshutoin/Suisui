import Foundation

public enum DeadlineNotificationScheduleStatus: Equatable, Sendable {
    case scheduled
    case skippedDuplicate
    case skippedPastDate
    case skippedMissingDate
    case failed
}

public struct DeadlineNotificationScheduleResult: Equatable, Sendable {
    public var status: DeadlineNotificationScheduleStatus
    public var notificationID: String?
    public var scheduledAt: Date?
    public var idempotencyKey: String?
    public var message: String

    public init(
        status: DeadlineNotificationScheduleStatus,
        notificationID: String? = nil,
        scheduledAt: Date? = nil,
        idempotencyKey: String? = nil,
        message: String
    ) {
        self.status = status
        self.notificationID = notificationID
        self.scheduledAt = scheduledAt
        self.idempotencyKey = idempotencyKey
        self.message = message
    }
}

public final class DeadlineNotificationScheduler: @unchecked Sendable {
    private let notificationClient: any NotificationClient
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        notificationClient: any NotificationClient,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.notificationClient = notificationClient
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func schedule(
        rule: DeadlineRule,
        item: DeadlineItem,
        openTasks: [DeadlineItem] = []
    ) -> DeadlineNotificationScheduleResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current

        guard let notifyAt = rule.notifyAt(forDueAt: item.dueAt, calendar: calendar) else {
            return DeadlineNotificationScheduleResult(
                status: .skippedMissingDate,
                message: "Deadline rule does not have a notification date."
            )
        }

        guard notifyAt > dateProvider.now else {
            return DeadlineNotificationScheduleResult(
                status: .skippedPastDate,
                scheduledAt: notifyAt,
                message: "Deadline notification date is in the past."
            )
        }

        let scheduledAt = DeadlineDateParser.string(from: notifyAt)
        let idempotencyKey = makeID(rule: rule, item: item, scheduledAt: scheduledAt)

        do {
            if try notificationClient.listScheduled().contains(where: { $0.id == idempotencyKey }) {
                return DeadlineNotificationScheduleResult(
                    status: .skippedDuplicate,
                    scheduledAt: notifyAt,
                    idempotencyKey: idempotencyKey,
                    message: "Deadline notification is already scheduled."
                )
            }

            let record = try notificationClient.schedule(
                NotificationDraft(
                    title: "Deadline: \(item.title)",
                    body: makeBody(item: item, openTasks: openTasks),
                    scheduledAt: scheduledAt,
                    identifierHint: idempotencyKey
                )
            )

            return DeadlineNotificationScheduleResult(
                status: .scheduled,
                notificationID: record.id,
                scheduledAt: notifyAt,
                idempotencyKey: idempotencyKey,
                message: "Scheduled deadline notification."
            )
        } catch let error as ToolClientError {
            return DeadlineNotificationScheduleResult(
                status: .failed,
                scheduledAt: notifyAt,
                idempotencyKey: idempotencyKey,
                message: error.message
            )
        } catch {
            return DeadlineNotificationScheduleResult(
                status: .failed,
                scheduledAt: notifyAt,
                idempotencyKey: idempotencyKey,
                message: String(describing: error)
            )
        }
    }

    private func makeID(rule: DeadlineRule, item: DeadlineItem, scheduledAt: String) -> String {
        if let ruleID = rule.id {
            return "deadline-rule-\(ruleID)-\(rule.target.targetType)-\(rule.target.targetID)-\(rule.kind.rawValue)-\(scheduledAt)"
        }

        return "deadline-\(item.kind.rawValue)-\(item.id)-\(rule.kind.rawValue)-\(scheduledAt)"
    }

    private func makeBody(item: DeadlineItem, openTasks: [DeadlineItem]) -> String {
        let taskCandidates = openTasks.filter { $0.kind == .task }
        let nextTask = taskCandidates.deadlineTaskSorted().first ?? (item.kind == .task ? item : nil)
        let unfinishedCount = taskCandidates.isEmpty && item.kind == .task ? 1 : taskCandidates.count

        guard let nextTask else {
            return "\(unfinishedCount) unfinished."
        }

        return "\(unfinishedCount) unfinished. Next: \(nextTask.title)"
    }
}

private extension Array where Element == DeadlineItem {
    func deadlineTaskSorted() -> [DeadlineItem] {
        sorted { lhs, rhs in
            if lhs.dueAt != rhs.dueAt {
                return lhs.dueAt < rhs.dueAt
            }
            if priorityRank(lhs.priority) != priorityRank(rhs.priority) {
                return priorityRank(lhs.priority) < priorityRank(rhs.priority)
            }
            if lhs.title != rhs.title {
                return lhs.title < rhs.title
            }
            return lhs.id < rhs.id
        }
    }

    private func priorityRank(_ priority: String?) -> Int {
        switch priority?.lowercased() {
        case "urgent":
            0
        case "high":
            1
        case "medium":
            2
        case "low":
            3
        default:
            4
        }
    }
}
