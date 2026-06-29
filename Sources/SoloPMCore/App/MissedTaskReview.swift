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

public protocol MissedTaskReviewStateStore: Sendable {
    func lastReviewedAt(taskID: Int64) throws -> Date?
    func markReviewed(taskID: Int64, at date: Date) throws
    func lastNotifiedDay() throws -> String?
    func recordNotification(day: String, at date: Date) throws
}

public final class InMemoryMissedTaskReviewStateStore: MissedTaskReviewStateStore, @unchecked Sendable {
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
            "SELECT last_reviewed_at FROM missed_task_review_state WHERE task_id = \(taskID) LIMIT 1;"
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
            VALUES (\(taskID), '\(SQLMissedTaskReview.escape(reviewedAt))', '\(SQLMissedTaskReview.escape(reviewedDay))', CURRENT_TIMESTAMP)
            ON CONFLICT(task_id) DO UPDATE SET
              last_reviewed_at = excluded.last_reviewed_at,
              last_reviewed_day = excluded.last_reviewed_day,
              updated_at = CURRENT_TIMESTAMP;
            """
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
            VALUES (0, '\(SQLMissedTaskReview.escape(day))', '\(SQLMissedTaskReview.escape(notifiedAt))')
            ON CONFLICT(task_id) DO UPDATE SET
              last_notified_day = excluded.last_notified_day,
              updated_at = excluded.updated_at;
            """
        )
    }
}

private enum SQLMissedTaskReview {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
