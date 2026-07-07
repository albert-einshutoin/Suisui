import Foundation

public enum MissedTaskReviewReason: String, CaseIterable, Sendable {
    case overdue
    case dueToday = "due_today"
    case blocked
    case unscheduled
    case stale

    public var title: String {
        switch self {
        case .overdue:
            "Overdue"
        case .dueToday:
            "Due Today"
        case .blocked:
            "Blocked"
        case .unscheduled:
            "Unscheduled"
        case .stale:
            "Stale"
        }
    }
}

public struct MissedTaskReviewItem: Identifiable, Equatable, Sendable {
    public var id: Int64 { task.id }
    public var task: ProjectBoardTask
    public var projectTitle: String
    public var reasons: [MissedTaskReviewReason]
    public var lastReviewedAt: Date?
    public var isNewlyMissed: Bool

    public init(
        task: ProjectBoardTask,
        projectTitle: String,
        reasons: [MissedTaskReviewReason],
        lastReviewedAt: Date?,
        isNewlyMissed: Bool
    ) {
        self.task = task
        self.projectTitle = projectTitle
        self.reasons = reasons
        self.lastReviewedAt = lastReviewedAt
        self.isNewlyMissed = isNewlyMissed
    }
}

public struct MissedTaskReviewSummary: Equatable, Sendable {
    public var items: [MissedTaskReviewItem]
    public var immediateQueue: [MissedTaskReviewItem]
    public var overdueCount: Int
    public var dueTodayCount: Int
    public var blockedCount: Int
    public var unscheduledCount: Int
    public var staleCount: Int
    public var newlyMissedCount: Int
    public var stateErrorMessage: String?

    public init(
        items: [MissedTaskReviewItem],
        immediateQueue: [MissedTaskReviewItem],
        overdueCount: Int,
        dueTodayCount: Int,
        blockedCount: Int,
        unscheduledCount: Int,
        staleCount: Int,
        newlyMissedCount: Int,
        stateErrorMessage: String? = nil
    ) {
        self.items = items
        self.immediateQueue = immediateQueue
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.blockedCount = blockedCount
        self.unscheduledCount = unscheduledCount
        self.staleCount = staleCount
        self.newlyMissedCount = newlyMissedCount
        self.stateErrorMessage = stateErrorMessage
    }

    public static let empty = MissedTaskReviewSummary(
        items: [],
        immediateQueue: [],
        overdueCount: 0,
        dueTodayCount: 0,
        blockedCount: 0,
        unscheduledCount: 0,
        staleCount: 0,
        newlyMissedCount: 0,
        stateErrorMessage: nil
    )
}

public enum MissedTaskDailyFollowUpStatus: Equatable, Sendable {
    case scheduled
    case skippedNotificationsDisabled
    case skippedNoMissedTasks
    case skippedAlreadyNotifiedToday
    case skippedAlreadyScheduled
    case failed
}

public struct MissedTaskDailyFollowUpResult: Equatable, Sendable {
    public var status: MissedTaskDailyFollowUpStatus
    public var notificationID: String?
    public var day: String
    public var missedCount: Int
    public var message: String

    public init(
        status: MissedTaskDailyFollowUpStatus,
        notificationID: String? = nil,
        day: String,
        missedCount: Int,
        message: String
    ) {
        self.status = status
        self.notificationID = notificationID
        self.day = day
        self.missedCount = missedCount
        self.message = message
    }
}

public final class MissedTaskDailyFollowUpScheduler: @unchecked Sendable {
    private let stateStore: any MissedTaskReviewStateStore
    private let notificationClient: any NotificationClient
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        stateStore: any MissedTaskReviewStateStore,
        notificationClient: any NotificationClient,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.stateStore = stateStore
        self.notificationClient = notificationClient
        self.dateProvider = dateProvider
        self.settings = settings.normalizedForRuntime
    }

    public func scheduleIfNeeded(summary: MissedTaskReviewSummary) -> MissedTaskDailyFollowUpResult {
        let now = dateProvider.now
        let day = configuredDay(for: now)
        let missedCount = summary.immediateQueue.count

        guard settings.notificationsEnabled else {
            return MissedTaskDailyFollowUpResult(
                status: .skippedNotificationsDisabled,
                day: day,
                missedCount: missedCount,
                message: "Missed task review follow-up is disabled."
            )
        }

        guard missedCount > 0 else {
            return MissedTaskDailyFollowUpResult(
                status: .skippedNoMissedTasks,
                day: day,
                missedCount: 0,
                message: "No missed task review follow-up is needed."
            )
        }

        do {
            guard try stateStore.lastNotifiedDay() != day else {
                return MissedTaskDailyFollowUpResult(
                    status: .skippedAlreadyNotifiedToday,
                    day: day,
                    missedCount: missedCount,
                    message: "Missed task review follow-up already ran today."
                )
            }

            let identifier = "missed-task-review-\(day)"
            if try notificationClient.listScheduled().contains(where: { $0.id == identifier }) {
                try stateStore.recordNotification(day: day, at: now)
                return MissedTaskDailyFollowUpResult(
                    status: .skippedAlreadyScheduled,
                    notificationID: identifier,
                    day: day,
                    missedCount: missedCount,
                    message: "Missed task review follow-up is already scheduled."
                )
            }

            let record = try notificationClient.schedule(
                NotificationDraft(
                    title: "SoloPM Catch Up",
                    body: makeCountOnlyBody(from: summary.immediateQueue),
                    scheduledAt: DeadlineDateParser.string(from: now),
                    identifierHint: identifier
                )
            )
            // Daily follow-up notifications are count-only by design. Task
            // titles, details, project names, and file paths stay inside the
            // board UI so lock-screen and audit surfaces cannot leak customer
            // content.
            try stateStore.recordNotification(day: day, at: now)
            return MissedTaskDailyFollowUpResult(
                status: .scheduled,
                notificationID: record.id,
                day: day,
                missedCount: missedCount,
                message: "Scheduled missed task review follow-up."
            )
        } catch let error as ToolClientError {
            return failureResult(day: day, missedCount: missedCount, message: error.message)
        } catch {
            return failureResult(day: day, missedCount: missedCount, error: error)
        }
    }

    private func configuredDay(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    private func makeCountOnlyBody(from items: [MissedTaskReviewItem]) -> String {
        let overdue = reasonCount(.overdue, in: items)
        let dueToday = reasonCount(.dueToday, in: items)
        let blocked = reasonCount(.blocked, in: items)
        let unscheduled = reasonCount(.unscheduled, in: items)
        let stale = reasonCount(.stale, in: items)
        return "\(items.count) tasks need review. Overdue: \(overdue), due today: \(dueToday), blocked: \(blocked), unscheduled: \(unscheduled), stale: \(stale)."
    }

    private func reasonCount(_ reason: MissedTaskReviewReason, in items: [MissedTaskReviewItem]) -> Int {
        items.filter { $0.reasons.contains(reason) }.count
    }

    private func failureResult(day: String, missedCount: Int, message: String) -> MissedTaskDailyFollowUpResult {
        MissedTaskDailyFollowUpResult(
            status: .failed,
            day: day,
            missedCount: missedCount,
            message: UserFacingErrorMessageSanitizer.message(from: message)
        )
    }

    private func failureResult(day: String, missedCount: Int, error: Error) -> MissedTaskDailyFollowUpResult {
        MissedTaskDailyFollowUpResult(
            status: .failed,
            day: day,
            missedCount: missedCount,
            message: UserFacingErrorMessageSanitizer.message(from: error)
        )
    }
}

public protocol MissedTaskReviewStateStore: Sendable {
    func lastReviewedAt(taskID: Int64) throws -> Date?
    func markReviewed(taskID: Int64, at date: Date) throws
    func lastNotifiedDay() throws -> String?
    func recordNotification(day: String, at date: Date) throws
}

public final class VolatileMissedTaskReviewStateStore: MissedTaskReviewStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var reviewedAtByTaskID: [Int64: Date] = [:]
    private var notifiedDay: String?

    public init() {}

    public func lastReviewedAt(taskID: Int64) throws -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return reviewedAtByTaskID[taskID]
    }

    public func markReviewed(taskID: Int64, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        reviewedAtByTaskID[taskID] = date
    }

    public func lastNotifiedDay() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return notifiedDay
    }

    public func recordNotification(day: String, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        notifiedDay = day
    }
}

public final class SQLiteMissedTaskReviewStateStore: MissedTaskReviewStateStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func lastReviewedAt(taskID: Int64) throws -> Date? {
        lock.lock()
        defer { lock.unlock() }

        let value = try connection.queryStrings(
            "SELECT last_reviewed_at FROM missed_task_review_state WHERE task_id = ? LIMIT 1;",
            parameters: [.integer(taskID)]
        ).first
        guard let value, !value.isEmpty else {
            return nil
        }
        return DeadlineDateParser.date(from: value)
    }

    public func markReviewed(taskID: Int64, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        let reviewedAt = DeadlineDateParser.string(from: date)
        let reviewedDay = String(reviewedAt.prefix(10))
        // The review state intentionally stores only IDs and dates. Task titles
        // stay in the task table so notifications/audit state cannot leak content.
        try connection.execute(
            """
            INSERT INTO missed_task_review_state (task_id, last_reviewed_at, last_reviewed_day, updated_at)
            VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(task_id) DO UPDATE SET
              last_reviewed_at = excluded.last_reviewed_at,
              last_reviewed_day = excluded.last_reviewed_day,
              updated_at = CURRENT_TIMESTAMP;
            """,
            parameters: [.integer(taskID), .text(reviewedAt), .text(reviewedDay)]
        )
    }

    public func lastNotifiedDay() throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryStrings(
            """
            SELECT last_notified_day
            FROM missed_task_review_state
            WHERE last_notified_day IS NOT NULL AND last_notified_day != ''
            ORDER BY updated_at DESC
            LIMIT 1;
            """
        ).first
    }

    public func recordNotification(day: String, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        let notifiedAt = DeadlineDateParser.string(from: date)
        try connection.execute(
            """
            INSERT INTO missed_task_review_state (task_id, last_notified_day, updated_at)
            VALUES (0, ?, ?)
            ON CONFLICT(task_id) DO UPDATE SET
              last_notified_day = excluded.last_notified_day,
              updated_at = excluded.updated_at;
            """,
            parameters: [.text(day), .text(notifiedAt)]
        )
    }
}
