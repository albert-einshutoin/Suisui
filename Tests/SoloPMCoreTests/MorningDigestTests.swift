import XCTest
@testable import SoloPMCore

final class MorningDigestTests: XCTestCase {
    private struct FixedDateProvider: DateProvider {
        let now: Date
    }

    private struct Fixture {
        var connection: SQLiteConnection
        var taskStore: SQLiteTaskStore
        var client: InMemoryNotificationClient

        func makeScheduler(now: Date, notificationsEnabled: Bool = true) -> MorningDigestScheduler {
            let settings = AppSettings(
                notificationsEnabled: notificationsEnabled,
                timeZoneIdentifier: "UTC"
            )
            return MorningDigestScheduler(
                queryService: DeadlineQueryService(
                    projectStore: SQLiteProjectStore(connection: connection),
                    taskStore: taskStore,
                    dateProvider: FixedDateProvider(now: now),
                    settings: settings
                ),
                stateStore: SQLiteMorningDigestStateStore(connection: connection),
                notificationClient: client,
                dateProvider: FixedDateProvider(now: now),
                settings: settings
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

    // 2026-07-07T10:00:00Z
    private let morningAfterDigestHour = Date(timeIntervalSince1970: 1_783_418_400)
    // 2026-07-07T07:00:00Z
    private let beforeDigestHour = Date(timeIntervalSince1970: 1_783_407_600)

    func testDigestWaitsUntilDigestHour() throws {
        let fixture = try makeFixture()
        _ = try fixture.taskStore.create(title: "Overdue item", dueAt: "2026-07-01T09:00:00Z")

        let result = fixture.makeScheduler(now: beforeDigestHour).scheduleIfNeeded()

        XCTAssertEqual(result.status, .skippedBeforeDigestHour)
        XCTAssertTrue(try fixture.client.listScheduled().isEmpty)
    }

    func testDigestSchedulesCountOnlyNotificationOncePerDay() throws {
        let fixture = try makeFixture()
        _ = try fixture.taskStore.create(title: "Overdue item", dueAt: "2026-07-01T09:00:00Z")
        _ = try fixture.taskStore.create(title: "Due today", dueAt: "2026-07-07T18:00:00Z")
        let scheduler = fixture.makeScheduler(now: morningAfterDigestHour)

        let first = scheduler.scheduleIfNeeded()
        let second = scheduler.scheduleIfNeeded()

        XCTAssertEqual(first.status, .scheduled)
        XCTAssertEqual(first.notificationID, "solopm-daily-digest-2026-07-07")
        XCTAssertEqual(second.status, .skippedAlreadyDeliveredToday)

        let scheduled = try fixture.client.listScheduled()
        XCTAssertEqual(scheduled.count, 1)
        let record = try XCTUnwrap(scheduled.first)
        XCTAssertEqual(record.title, "SoloPM Daily Digest")
        XCTAssertEqual(record.body, "1 overdue, 1 due today, 0 more this week.")
        XCTAssertFalse(record.body?.contains("Overdue item") ?? true)
    }

    func testDigestSkipsWhenNotificationsDisabled() throws {
        let fixture = try makeFixture()
        _ = try fixture.taskStore.create(title: "Overdue item", dueAt: "2026-07-01T09:00:00Z")

        let result = fixture.makeScheduler(
            now: morningAfterDigestHour,
            notificationsEnabled: false
        ).scheduleIfNeeded()

        XCTAssertEqual(result.status, .skippedNotificationsDisabled)
        XCTAssertTrue(try fixture.client.listScheduled().isEmpty)
    }

    func testQuietDayDoesNotConsumeTheDigestSlot() throws {
        let fixture = try makeFixture()
        let scheduler = fixture.makeScheduler(now: morningAfterDigestHour)

        let quiet = scheduler.scheduleIfNeeded()
        XCTAssertEqual(quiet.status, .skippedNothingToReport)
        XCTAssertTrue(try fixture.client.listScheduled().isEmpty)

        // A deadline appears later the same day: the next check should still
        // deliver the first useful digest of the day.
        _ = try fixture.taskStore.create(title: "New overdue", dueAt: "2026-07-06T09:00:00Z")
        let laterResult = fixture.makeScheduler(
            now: morningAfterDigestHour.addingTimeInterval(2 * 3_600)
        ).scheduleIfNeeded()

        XCTAssertEqual(laterResult.status, .scheduled)
    }

    func testStateStoreRoundTripsDigestDay() throws {
        let fixture = try makeFixture()
        let store = SQLiteMorningDigestStateStore(connection: fixture.connection)

        XCTAssertNil(try store.lastDigestDay())
        try store.recordDigest(day: "2026-07-07", at: morningAfterDigestHour)
        XCTAssertEqual(try store.lastDigestDay(), "2026-07-07")
        try store.recordDigest(day: "2026-07-08", at: morningAfterDigestHour)
        XCTAssertEqual(try store.lastDigestDay(), "2026-07-08")
    }
}
