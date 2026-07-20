import XCTest
@testable import SuisuiCore

final class DeadlineQueryServiceTests: XCTestCase {
    func testSummaryGroupsActiveProjectAndTaskDeadlinesWithFixedClock() throws {
        let stores = try makeStores()
        _ = try stores.projects.create(title: "Today project", deadline: "2026-06-17T06:00:00Z")
        _ = try stores.tasks.create(title: "Tomorrow task", dueAt: "2026-06-18T03:00:00Z")
        _ = try stores.tasks.create(title: "Three day task", dueAt: "2026-06-19T09:00:00Z")
        _ = try stores.projects.create(title: "Next week project", deadline: "2026-06-23T09:00:00Z")
        _ = try stores.tasks.create(title: "Overdue task", dueAt: "2026-06-15T23:00:00Z")
        let completed = try stores.tasks.create(title: "Completed task", dueAt: "2026-06-17T05:00:00Z")
        _ = try stores.tasks.update(id: completed.id, status: "completed")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "Asia/Tokyo")
        )

        let summary = try service.summary()

        XCTAssertEqual(summary.today.map(\.title), ["Today project"])
        XCTAssertEqual(summary.tomorrow.map(\.title), ["Tomorrow task"])
        XCTAssertEqual(summary.nextThreeDays.map(\.title), ["Today project", "Tomorrow task", "Three day task"])
        XCTAssertEqual(summary.thisWeek.map(\.title), ["Today project", "Tomorrow task", "Three day task", "Next week project"])
        XCTAssertEqual(summary.overdue.map(\.title), ["Overdue task"])
    }

    func testSummaryUsesSettingsTimeZoneForDayBoundaries() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "JST tomorrow", dueAt: "2026-06-17T15:30:00Z")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T14:30:00Z")),
            settings: AppSettings(timeZoneIdentifier: "Asia/Tokyo")
        )

        let summary = try service.summary()

        XCTAssertEqual(summary.today.map(\.title), [])
        XCTAssertEqual(summary.tomorrow.map(\.title), ["JST tomorrow"])
    }

    func testSummaryIncludesDateOnlyTaskDueDatesFromBoardUI() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Board date-only task", dueAt: "2026-06-17")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        XCTAssertEqual(try service.summary().today.map(\.title), ["Board date-only task"])
    }

    func testSummaryThrowsWhenTaskDueDateIsInvalid() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Broken due date", dueAt: "not-a-date")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        XCTAssertThrowsError(try service.summary()) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidDate(column: "tasks.due_at", value: "not-a-date")
            )
        }
    }

    func testSummaryThrowsWhenProjectDeadlineIsInvalid() throws {
        let stores = try makeStores()
        _ = try stores.projects.create(title: "Broken deadline", deadline: "not-a-date")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        XCTAssertThrowsError(try service.summary()) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidDate(column: "projects.deadline", value: "not-a-date")
            )
        }
    }

    func testSummaryExcludesArchivedProjectAndItsTaskDeadlines() throws {
        let stores = try makeStores()
        let archived = try stores.projects.create(title: "Archived project", deadline: "2026-06-17T06:00:00Z")
        _ = try stores.projects.update(id: archived.id, status: "archived")
        _ = try stores.tasks.create(
            title: "Archived project task",
            projectID: archived.id,
            dueAt: "2026-06-17T07:00:00Z"
        )
        _ = try stores.tasks.create(title: "Visible task", dueAt: "2026-06-17T08:00:00Z")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        let summary = try service.summary()

        XCTAssertEqual(summary.today.map(\.title), ["Visible task"])
    }

    func testMenuBarSummaryCanBeBuiltFromDeadlineSummary() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Today task", dueAt: "2026-06-17T03:00:00Z")
        _ = try stores.tasks.create(title: "Overdue task", dueAt: "2026-06-16T03:00:00Z")
        _ = try stores.tasks.create(title: "Week task", dueAt: "2026-06-21T03:00:00Z")
        _ = try stores.projects.create(title: "Recent project", deadline: "2026-06-24T03:00:00Z")

        let service = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        let menuSummary = MenuBarSummary(deadlineSummary: try service.summary(), recentProjectTitles: ["Recent project"])

        XCTAssertEqual(menuSummary.todayTaskCount, 1)
        XCTAssertEqual(menuSummary.overdueTaskCount, 1)
        XCTAssertEqual(menuSummary.dueThisWeekCount, 2)
        XCTAssertEqual(menuSummary.recentProjectTitles, ["Recent project"])
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection)
        )
    }
}

private struct FixedDateProvider: DateProvider {
    let now: Date
}

private enum TestMigrationRunner {
    static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
