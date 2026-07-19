import XCTest
@testable import SoloPMCore

final class WeeklyReviewSummaryTests: XCTestCase {
    private struct FixedDateProvider: DateProvider {
        let now: Date
    }

    private struct Fixture {
        var connection: SQLiteConnection
        var taskStore: SQLiteTaskStore
        var client: InMemoryNotificationClient

        func makeScheduler(now: Date, notificationsEnabled: Bool = true) -> WeeklyReviewSummaryScheduler {
            let settings = AppSettings(
                notificationsEnabled: notificationsEnabled,
                timeZoneIdentifier: "UTC"
            )
            return WeeklyReviewSummaryScheduler(
                taskStore: taskStore,
                stateStore: SQLiteWeeklyReviewSummaryStateStore(connection: connection),
                notificationClient: client,
                dateProvider: FixedDateProvider(now: now),
                settings: settings
            )
        }

        // Inserted directly so the completion timestamp is deterministic:
        // SQLiteTaskStore stamps completed_at with SQLite 'now', which would
        // drift outside the fixture week whenever these tests actually run.
        func insertCompletedTask(title: String, completedAt: String) throws {
            try connection.execute(
                "INSERT INTO tasks (title, status, completed_at) VALUES (?, 'completed', ?);",
                parameters: [.text(title), .text(completedAt)]
            )
        }
    }

    private func makeFixture() throws -> Fixture {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return Fixture(
            connection: connection,
            taskStore: SQLiteTaskStore(connection: connection),
            client: InMemoryNotificationClient()
        )
    }

    // 2026-07-10T17:00:00Z, a Friday in ISO week 2026-W28
    private let fridayAfterDeliveryHour = Date(timeIntervalSince1970: 1_783_702_800)
    // 2026-07-10T10:00:00Z, the same Friday before the delivery hour
    private let fridayBeforeDeliveryHour = Date(timeIntervalSince1970: 1_783_677_600)
    // 2026-07-09T17:00:00Z, a Thursday
    private let thursdayAfterDeliveryHour = Date(timeIntervalSince1970: 1_783_616_400)

    func testSummaryWaitsUntilFridayDeliveryHour() throws {
        let fixture = try makeFixture()
        try fixture.insertCompletedTask(title: "Done item", completedAt: "2026-07-08T09:00:00Z")

        let beforeHour = fixture.makeScheduler(now: fridayBeforeDeliveryHour).scheduleIfNeeded()
        let wrongDay = fixture.makeScheduler(now: thursdayAfterDeliveryHour).scheduleIfNeeded()

        XCTAssertEqual(beforeHour.status, .skippedOutsideDeliveryWindow)
        XCTAssertEqual(wrongDay.status, .skippedOutsideDeliveryWindow)
        XCTAssertTrue(try fixture.client.listScheduled().isEmpty)
    }

    func testSummarySchedulesCountOnlyNotificationOncePerWeek() throws {
        let fixture = try makeFixture()
        try fixture.insertCompletedTask(title: "Done this week", completedAt: "2026-07-08T09:00:00Z")
        try fixture.insertCompletedTask(title: "Done Monday", completedAt: "2026-07-06T08:00:00Z")
        try fixture.insertCompletedTask(title: "Done last week", completedAt: "2026-07-03T09:00:00Z")
        _ = try fixture.taskStore.create(title: "Still open item")
        let scheduler = fixture.makeScheduler(now: fridayAfterDeliveryHour)

        let first = scheduler.scheduleIfNeeded()
        let second = scheduler.scheduleIfNeeded()

        XCTAssertEqual(first.status, .scheduled)
        XCTAssertEqual(first.notificationID, "solopm-weekly-review-2026-W28")
        XCTAssertEqual(first.week, "2026-W28")
        XCTAssertEqual(second.status, .skippedAlreadyDeliveredThisWeek)

        let scheduled = try fixture.client.listScheduled()
        XCTAssertEqual(scheduled.count, 1)
        let record = try XCTUnwrap(scheduled.first)
        XCTAssertEqual(record.title, "Suisui Weekly Review")
        XCTAssertEqual(record.body, "2 completed this week, 1 still open.")
        XCTAssertFalse(record.body?.contains("Done this week") ?? true)
        XCTAssertFalse(record.body?.contains("Still open item") ?? true)
    }

    func testSummarySkipsWhenNotificationsDisabled() throws {
        let fixture = try makeFixture()
        try fixture.insertCompletedTask(title: "Done item", completedAt: "2026-07-08T09:00:00Z")

        let result = fixture.makeScheduler(
            now: fridayAfterDeliveryHour,
            notificationsEnabled: false
        ).scheduleIfNeeded()

        XCTAssertEqual(result.status, .skippedNotificationsDisabled)
        XCTAssertTrue(try fixture.client.listScheduled().isEmpty)
    }

    func testQuietWeekDoesNotConsumeTheSummarySlot() throws {
        let fixture = try makeFixture()
        let scheduler = fixture.makeScheduler(now: fridayAfterDeliveryHour)

        let quiet = scheduler.scheduleIfNeeded()
        XCTAssertEqual(quiet.status, .skippedNothingToReport)
        XCTAssertTrue(try fixture.client.listScheduled().isEmpty)

        // Work appears later the same Friday: the next check should still
        // deliver the first useful summary of the week.
        try fixture.insertCompletedTask(title: "Late finish", completedAt: "2026-07-10T17:30:00Z")
        let laterResult = fixture.makeScheduler(
            now: fridayAfterDeliveryHour.addingTimeInterval(2 * 3_600)
        ).scheduleIfNeeded()

        XCTAssertEqual(laterResult.status, .scheduled)
    }

    func testTaskStoreCountsCompletedWithinWindowAndOpenTasks() throws {
        let fixture = try makeFixture()
        try fixture.insertCompletedTask(title: "Inside window", completedAt: "2026-07-08T09:00:00Z")
        try fixture.insertCompletedTask(title: "Before window", completedAt: "2026-07-03T09:00:00Z")
        _ = try fixture.taskStore.create(title: "Open one")
        _ = try fixture.taskStore.create(title: "Open two")

        XCTAssertEqual(
            try fixture.taskStore.completedCount(since: "2026-07-06T00:00:00Z", until: "2026-07-10T17:00:00Z"),
            1
        )
        XCTAssertEqual(
            try fixture.taskStore.completedCount(since: "1970-01-01T00:00:00Z", until: "9999-12-31T00:00:00Z"),
            2
        )
        XCTAssertEqual(try fixture.taskStore.openCount(), 2)
    }

    func testStateStoreRoundTripsSummaryWeek() throws {
        let fixture = try makeFixture()
        let store = SQLiteWeeklyReviewSummaryStateStore(connection: fixture.connection)

        XCTAssertNil(try store.lastSummaryWeek())
        try store.recordSummary(week: "2026-W28", at: fridayAfterDeliveryHour)
        XCTAssertEqual(try store.lastSummaryWeek(), "2026-W28")
        try store.recordSummary(week: "2026-W29", at: fridayAfterDeliveryHour)
        XCTAssertEqual(try store.lastSummaryWeek(), "2026-W29")
    }
}
