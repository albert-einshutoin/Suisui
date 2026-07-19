import Foundation

public enum WeeklyReviewSummaryStatus: Equatable, Sendable {
    case scheduled
    case skippedNotificationsDisabled
    case skippedOutsideDeliveryWindow
    case skippedAlreadyDeliveredThisWeek
    case skippedNothingToReport
    case failed
}

public struct WeeklyReviewSummaryResult: Equatable, Sendable {
    public var status: WeeklyReviewSummaryStatus
    public var notificationID: String?
    public var week: String
    public var message: String

    public init(status: WeeklyReviewSummaryStatus, notificationID: String? = nil, week: String, message: String) {
        self.status = status
        self.notificationID = notificationID
        self.week = week
        self.message = message
    }
}

public protocol WeeklyReviewSummaryStateStore: Sendable {
    func lastSummaryWeek() throws -> String?
    func recordSummary(week: String, at date: Date) throws
}

public final class SQLiteWeeklyReviewSummaryStateStore: WeeklyReviewSummaryStateStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func lastSummaryWeek() throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        let value = try connection.queryStrings(
            "SELECT last_summary_week FROM weekly_review_state WHERE id = 1 LIMIT 1;"
        ).first
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    public func recordSummary(week: String, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO weekly_review_state (id, last_summary_week, recorded_at, updated_at)
            VALUES (1, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(id) DO UPDATE SET
              last_summary_week = excluded.last_summary_week,
              recorded_at = excluded.recorded_at,
              updated_at = CURRENT_TIMESTAMP;
            """,
            parameters: [.text(week), .text(DeadlineDateParser.string(from: date))]
        )
    }
}

/// Delivers one "how did the week go" notification per ISO week, the first
/// time SoloPM checks deadlines on Friday at or after the delivery hour.
///
/// The summary is count-only by design, matching the morning digest: task
/// titles, project names, and paths stay inside the board UI so lock-screen
/// surfaces cannot leak customer content.
public final class WeeklyReviewSummaryScheduler: @unchecked Sendable {
    /// Friday in the Gregorian calendar, where Sunday == 1.
    public static let deliveryWeekday = 6
    public static let deliveryHour = 16

    private let taskStore: SQLiteTaskStore
    private let stateStore: any WeeklyReviewSummaryStateStore
    private let notificationClient: any NotificationClient
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        taskStore: SQLiteTaskStore,
        stateStore: any WeeklyReviewSummaryStateStore,
        notificationClient: any NotificationClient,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.taskStore = taskStore
        self.stateStore = stateStore
        self.notificationClient = notificationClient
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func scheduleIfNeeded() -> WeeklyReviewSummaryResult {
        let now = dateProvider.now
        let timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // ISO 8601 weeks start on Monday and give an unambiguous
        // year-for-week-of-year around New Year boundaries.
        var isoCalendar = Calendar(identifier: .iso8601)
        isoCalendar.timeZone = timeZone
        let week = Self.weekKey(for: now, calendar: isoCalendar)

        guard settings.notificationsEnabled else {
            return WeeklyReviewSummaryResult(
                status: .skippedNotificationsDisabled,
                week: week,
                message: "Weekly review summary is disabled because notifications are off."
            )
        }

        guard calendar.component(.weekday, from: now) == Self.deliveryWeekday,
              calendar.component(.hour, from: now) >= Self.deliveryHour else {
            return WeeklyReviewSummaryResult(
                status: .skippedOutsideDeliveryWindow,
                week: week,
                message: "Weekly review summary waits for Friday afternoon."
            )
        }

        do {
            guard try stateStore.lastSummaryWeek() != week else {
                return WeeklyReviewSummaryResult(
                    status: .skippedAlreadyDeliveredThisWeek,
                    week: week,
                    message: "Weekly review summary already delivered this week."
                )
            }

            let weekStart = isoCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let completedCount = try taskStore.completedCount(
                since: DeadlineDateParser.string(from: weekStart),
                until: DeadlineDateParser.string(from: now)
            )
            let openCount = try taskStore.openCount()

            guard completedCount > 0 || openCount > 0 else {
                // Do not record the week: if work appears later on Friday the
                // next check can still deliver the first useful summary.
                return WeeklyReviewSummaryResult(
                    status: .skippedNothingToReport,
                    week: week,
                    message: "No completed or open tasks to summarize this week."
                )
            }

            let identifier = "solopm-weekly-review-\(week)"
            if try notificationClient.listScheduled().contains(where: { $0.id == identifier }) {
                try stateStore.recordSummary(week: week, at: now)
                return WeeklyReviewSummaryResult(
                    status: .skippedAlreadyDeliveredThisWeek,
                    notificationID: identifier,
                    week: week,
                    message: "Weekly review summary is already scheduled."
                )
            }

            // Quiet hours defer (never drop) the weekly review summary; it
            // still counts as this week's summary but fires after the window.
            let fireDate = NotificationSchedulingPolicy.finalFireDate(
                proposed: now,
                kind: .fixedTime,
                preferences: settings.notificationPreferences,
                timeZone: timeZone
            )
            let record = try notificationClient.schedule(
                NotificationDraft(
                    title: "Suisui Weekly Review",
                    body: Self.makeBody(completedCount: completedCount, openCount: openCount),
                    scheduledAt: DeadlineDateParser.string(from: fireDate),
                    identifierHint: identifier
                )
            )
            try stateStore.recordSummary(week: week, at: now)
            return WeeklyReviewSummaryResult(
                status: .scheduled,
                notificationID: record.id,
                week: week,
                message: "Scheduled the weekly review summary."
            )
        } catch let error as ToolClientError {
            return WeeklyReviewSummaryResult(
                status: .failed,
                week: week,
                message: UserFacingErrorMessageSanitizer.message(from: error.message)
            )
        } catch {
            return WeeklyReviewSummaryResult(
                status: .failed,
                week: week,
                message: UserFacingErrorMessageSanitizer.message(from: error)
            )
        }
    }

    static func makeBody(completedCount: Int, openCount: Int) -> String {
        "\(completedCount) completed this week, \(openCount) still open."
    }

    static func weekKey(for date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let week = calendar.component(.weekOfYear, from: date)
        return String(format: "%04d-W%02d", year, week)
    }
}
