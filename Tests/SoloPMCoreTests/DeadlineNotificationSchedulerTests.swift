import XCTest
@testable import SoloPMCore

final class DeadlineNotificationSchedulerTests: XCTestCase {
    func testSchedulerCreatesDeterministicNotificationAndSkipsDuplicate() throws {
        let client = InMemoryNotificationClient()
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: client,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )
        let rule = DeadlineRule(id: 7, target: .project(10), kind: .tMinus1)
        let item = DeadlineItem(id: 10, kind: .project, title: "Alpha launch", dueAt: try Date.iso8601("2026-06-30T12:00:00Z"))
        let openTasks = [
            DeadlineItem(id: 1, kind: .task, title: "Low task", dueAt: try Date.iso8601("2026-06-19T09:00:00Z"), priority: "low"),
            DeadlineItem(id: 2, kind: .task, title: "High task", dueAt: try Date.iso8601("2026-06-18T09:00:00Z"), priority: "high")
        ]

        let first = scheduler.schedule(rule: rule, item: item, openTasks: openTasks)
        let second = scheduler.schedule(rule: rule, item: item, openTasks: openTasks)
        let scheduled = try client.listScheduled()

        XCTAssertEqual(first.status, .scheduled)
        XCTAssertEqual(second.status, .skippedDuplicate)
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.id, "deadline-rule-7-project-10-T-1-2026-06-29T12:00:00Z")
        XCTAssertEqual(scheduled.first?.title, "Deadline: Alpha launch")
        XCTAssertEqual(scheduled.first?.body, "2 unfinished. Next: High task")
    }

    func testSchedulerAppliesLeadTimeThenQuietHoursToDeadlineReminders() throws {
        let client = InMemoryNotificationClient()
        let preferences = NotificationPreferences(
            quietHours: NotificationQuietHoursSettings(
                enabled: true,
                startMinuteOfDay: 22 * 60,
                endMinuteOfDay: 8 * 60
            ),
            deadlineReminderLeadTime: .oneHourBefore
        )
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: client,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(notificationPreferences: preferences, timeZoneIdentifier: "UTC")
        )
        // Day-of reminder due at 23:30: one hour earlier is 22:30, inside the
        // quiet window, so the reminder fires at 08:00 the next morning.
        let rule = DeadlineRule(id: 11, target: .task(30), kind: .dayOf)
        let item = DeadlineItem(id: 30, kind: .task, title: "Late task", dueAt: try Date.iso8601("2026-06-20T23:30:00Z"))

        let result = scheduler.schedule(rule: rule, item: item)

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.scheduledAt, try Date.iso8601("2026-06-21T08:00:00Z"))
        XCTAssertEqual(try client.listScheduled().first?.scheduledAt, "2026-06-21T08:00:00Z")
    }

    func testSchedulerAppliesLeadTimeOutsideQuietHoursWithoutDeferral() throws {
        let client = InMemoryNotificationClient()
        let preferences = NotificationPreferences(deadlineReminderLeadTime: .oneDayBefore)
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: client,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(notificationPreferences: preferences, timeZoneIdentifier: "UTC")
        )
        let rule = DeadlineRule(id: 12, target: .task(31), kind: .dayOf)
        let item = DeadlineItem(id: 31, kind: .task, title: "Planned task", dueAt: try Date.iso8601("2026-06-20T12:00:00Z"))

        let result = scheduler.schedule(rule: rule, item: item)

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.scheduledAt, try Date.iso8601("2026-06-19T12:00:00Z"))
    }

    func testSchedulerSkipsPastNotificationDate() throws {
        let client = InMemoryNotificationClient()
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: client,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )
        let rule = DeadlineRule(id: 8, target: .task(20), kind: .dayOf)
        let item = DeadlineItem(id: 20, kind: .task, title: "Past task", dueAt: try Date.iso8601("2026-06-16T12:00:00Z"))

        let result = scheduler.schedule(rule: rule, item: item)

        XCTAssertEqual(result.status, .skippedPastDate)
        XCTAssertEqual(try client.listScheduled(), [])
    }

    func testSchedulerReportsPermissionDeniedWithoutCrashing() throws {
        let client = InMemoryNotificationClient(authorizationStatus: .denied)
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: client,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )
        let rule = DeadlineRule(id: 9, target: .task(20), kind: .tMinus1)
        let item = DeadlineItem(id: 20, kind: .task, title: "Blocked task", dueAt: try Date.iso8601("2026-06-20T12:00:00Z"))

        let result = scheduler.schedule(rule: rule, item: item)

        XCTAssertEqual(result.status, .failed)
        XCTAssertTrue(result.message.contains("permission is denied"))
    }

    func testSchedulerRedactsToolClientFailureMessages() throws {
        let secret = "sk-notification-tool-secret"
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: FailingNotificationClient(error: ToolClientError.invalidRequest("token=\(secret) could not schedule")),
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )
        let rule = DeadlineRule(id: 10, target: .task(20), kind: .tMinus1)
        let item = DeadlineItem(id: 20, kind: .task, title: "Secret task", dueAt: try Date.iso8601("2026-06-20T12:00:00Z"))

        let result = scheduler.schedule(rule: rule, item: item)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "token=[REDACTED_SECRET] could not schedule")
        XCTAssertFalse(result.message.contains(secret))
    }

    func testSchedulerRedactsUnexpectedClientFailureMessages() throws {
        let secret = "sk-notification-system-secret"
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: FailingNotificationClient(error: SecretNotificationClientError(secret: secret)),
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )
        let rule = DeadlineRule(id: 11, target: .task(20), kind: .tMinus1)
        let item = DeadlineItem(id: 20, kind: .task, title: "Secret task", dueAt: try Date.iso8601("2026-06-20T12:00:00Z"))

        let result = scheduler.schedule(rule: rule, item: item)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "notification failed token=[REDACTED_SECRET]")
        XCTAssertFalse(result.message.contains(secret))
    }
}

private struct FixedDateProvider: DateProvider {
    let now: Date
}

private struct FailingNotificationClient: NotificationClient {
    let error: Error

    func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
        throw error
    }

    func cancel(id: String) throws {
        throw error
    }

    func listScheduled() throws -> [NotificationRecord] {
        []
    }
}

private struct SecretNotificationClientError: Error, CustomStringConvertible {
    let secret: String

    var description: String {
        "notification failed token=\(secret)"
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
