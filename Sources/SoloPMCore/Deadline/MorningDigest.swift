import Foundation

public enum MorningDigestStatus: Equatable, Sendable {
    case scheduled
    case skippedNotificationsDisabled
    case skippedBeforeDigestHour
    case skippedAlreadyDeliveredToday
    case skippedNothingToReport
    case failed
}

public struct MorningDigestResult: Equatable, Sendable {
    public var status: MorningDigestStatus
    public var notificationID: String?
    public var day: String
    public var message: String

    public init(status: MorningDigestStatus, notificationID: String? = nil, day: String, message: String) {
        self.status = status
        self.notificationID = notificationID
        self.day = day
        self.message = message
    }
}

public protocol MorningDigestStateStore: Sendable {
    func lastDigestDay() throws -> String?
    func recordDigest(day: String, at date: Date) throws
}

public final class SQLiteMorningDigestStateStore: MorningDigestStateStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func lastDigestDay() throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        let value = try connection.queryStrings(
            "SELECT last_digest_day FROM morning_digest_state WHERE id = 1 LIMIT 1;"
        ).first
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    public func recordDigest(day: String, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO morning_digest_state (id, last_digest_day, recorded_at, updated_at)
            VALUES (1, ?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(id) DO UPDATE SET
              last_digest_day = excluded.last_digest_day,
              recorded_at = excluded.recorded_at,
              updated_at = CURRENT_TIMESTAMP;
            """,
            parameters: [.text(day), .text(DeadlineDateParser.string(from: date))]
        )
    }
}

/// Delivers one glanceable "here is your day" notification per day, the
/// first time SoloPM checks deadlines at or after the digest hour.
///
/// The digest is count-only by design, matching the missed-task follow-up:
/// task titles, project names, and paths stay inside the board UI so
/// lock-screen surfaces cannot leak customer content.
public final class MorningDigestScheduler: @unchecked Sendable {
    public static let defaultDigestHour = 9

    private let queryService: DeadlineQueryService
    private let stateStore: any MorningDigestStateStore
    private let notificationClient: any NotificationClient
    private let dateProvider: any DateProvider
    private let settings: AppSettings
    private let digestHour: Int

    public init(
        queryService: DeadlineQueryService,
        stateStore: any MorningDigestStateStore,
        notificationClient: any NotificationClient,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default,
        digestHour: Int = MorningDigestScheduler.defaultDigestHour
    ) {
        self.queryService = queryService
        self.stateStore = stateStore
        self.notificationClient = notificationClient
        self.dateProvider = dateProvider
        self.settings = settings
        self.digestHour = digestHour
    }

    public func scheduleIfNeeded() -> MorningDigestResult {
        let now = dateProvider.now
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current
        calendar.timeZone = timeZone
        let day = Self.dayString(for: now, timeZone: timeZone)

        guard settings.notificationsEnabled else {
            return MorningDigestResult(
                status: .skippedNotificationsDisabled,
                day: day,
                message: "Morning digest is disabled because notifications are off."
            )
        }

        guard calendar.component(.hour, from: now) >= digestHour else {
            return MorningDigestResult(
                status: .skippedBeforeDigestHour,
                day: day,
                message: "Morning digest waits until the digest hour."
            )
        }

        do {
            guard try stateStore.lastDigestDay() != day else {
                return MorningDigestResult(
                    status: .skippedAlreadyDeliveredToday,
                    day: day,
                    message: "Morning digest already delivered today."
                )
            }

            let summary = try queryService.summary()
            let overdueCount = summary.overdue.count
            let dueTodayCount = summary.today.count
            // DeadlineSummary.thisWeek spans from the start of today, so
            // subtract today's items to report the rest of the week.
            let dueLaterThisWeekCount = max(0, summary.thisWeek.count - dueTodayCount)

            guard overdueCount > 0 || dueTodayCount > 0 || dueLaterThisWeekCount > 0 else {
                // Do not record the day: if deadlines appear later today the
                // next check can still deliver the first useful digest.
                return MorningDigestResult(
                    status: .skippedNothingToReport,
                    day: day,
                    message: "No deadlines need attention today."
                )
            }

            let identifier = "solopm-daily-digest-\(day)"
            if try notificationClient.listScheduled().contains(where: { $0.id == identifier }) {
                try stateStore.recordDigest(day: day, at: now)
                return MorningDigestResult(
                    status: .skippedAlreadyDeliveredToday,
                    notificationID: identifier,
                    day: day,
                    message: "Morning digest is already scheduled."
                )
            }

            let record = try notificationClient.schedule(
                NotificationDraft(
                    title: "SoloPM Daily Digest",
                    body: Self.makeBody(
                        overdueCount: overdueCount,
                        dueTodayCount: dueTodayCount,
                        dueLaterThisWeekCount: dueLaterThisWeekCount
                    ),
                    scheduledAt: DeadlineDateParser.string(from: now),
                    identifierHint: identifier
                )
            )
            try stateStore.recordDigest(day: day, at: now)
            return MorningDigestResult(
                status: .scheduled,
                notificationID: record.id,
                day: day,
                message: "Scheduled the morning digest."
            )
        } catch let error as ToolClientError {
            return MorningDigestResult(
                status: .failed,
                day: day,
                message: UserFacingErrorMessageSanitizer.message(from: error.message)
            )
        } catch {
            return MorningDigestResult(
                status: .failed,
                day: day,
                message: UserFacingErrorMessageSanitizer.message(from: error)
            )
        }
    }

    static func makeBody(overdueCount: Int, dueTodayCount: Int, dueLaterThisWeekCount: Int) -> String {
        "\(overdueCount) overdue, \(dueTodayCount) due today, \(dueLaterThisWeekCount) more this week."
    }

    static func dayString(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
