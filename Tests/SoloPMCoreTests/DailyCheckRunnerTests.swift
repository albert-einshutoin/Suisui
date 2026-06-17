import XCTest
@testable import SoloPMCore

final class DailyCheckRunnerTests: XCTestCase {
    func testRunnerSkipsWhenAlreadyCheckedToday() throws {
        let stores = try makeStores()
        let stateStore = InMemoryDailyCheckStateStore(lastRunAt: try Date.iso8601("2026-06-17T01:00:00Z"))
        let logger = InMemoryAuditLogger()
        let runner = try makeRunner(stores: stores, stateStore: stateStore, logger: logger)

        let result = try runner.runIfNeeded(reason: .appLaunch)

        XCTAssertEqual(result.status, .skippedAlreadyRanToday)
        XCTAssertEqual(result.scheduledCount, 0)
        XCTAssertEqual(logger.recordedEvents.last?.status, .skipped)
        XCTAssertEqual(logger.recordedEvents.last?.metadata["reason"], "app_launch")
    }

    func testRunnerRunsMissedCheckSchedulesOverdueNotificationAndAuditsResult() throws {
        let stores = try makeStores()
        let overdue = try stores.tasks.create(title: "Review alpha", dueAt: "2026-06-16T12:00:00Z")
        let rule = try stores.rules.create(DeadlineRule(target: .task(overdue.id), kind: .overdueDaily))
        let stateStore = InMemoryDailyCheckStateStore(lastRunAt: try Date.iso8601("2026-06-16T01:00:00Z"))
        let notificationClient = InMemoryNotificationClient()
        let logger = InMemoryAuditLogger()
        let runner = try makeRunner(
            stores: stores,
            stateStore: stateStore,
            notificationClient: notificationClient,
            logger: logger
        )

        let result = try runner.runIfNeeded(reason: .appLaunch)

        XCTAssertEqual(result.status, .ran)
        XCTAssertEqual(result.overdueCount, 1)
        XCTAssertEqual(result.scheduledCount, 1)
        XCTAssertEqual(try notificationClient.listScheduled().first?.title, "Deadline: Review alpha")
        XCTAssertEqual(try stores.rules.get(id: try XCTUnwrap(rule.id)).lastNotifiedAt, try Date.iso8601("2026-06-17T12:00:00Z"))
        XCTAssertEqual(try stateStore.lastRunAt(), try Date.iso8601("2026-06-17T12:00:00Z"))
        XCTAssertEqual(logger.recordedEvents.last?.category, "deadline_watcher")
        XCTAssertEqual(logger.recordedEvents.last?.action, "daily_check")
        XCTAssertEqual(logger.recordedEvents.last?.status, .succeeded)
        XCTAssertEqual(logger.recordedEvents.last?.metadata["scheduled_count"], "1")
    }

    func testLaunchAtLoginClientCanBeToggledForDailyChecks() throws {
        let client = InMemoryLaunchAtLoginClient()

        XCTAssertEqual(try client.setEnabled(true), .enabled)
        XCTAssertEqual(client.status(), .enabled)
        XCTAssertEqual(try client.setEnabled(false), .disabled)
        XCTAssertEqual(client.status(), .disabled)
    }

    func testSQLiteDailyCheckStateStorePersistsLastRunAt() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        let store = SQLiteDailyCheckStateStore(connection: connection)
        let date = try Date.iso8601("2026-06-17T12:00:00Z")

        try store.recordRun(at: date)

        XCTAssertTrue(try connection.tableExists("daily_check_state"))
        XCTAssertEqual(try store.lastRunAt(), date)
    }

    private func makeRunner(
        stores: (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, rules: SQLiteDeadlineRuleStore),
        stateStore: any DailyCheckStateStore,
        notificationClient: InMemoryNotificationClient = InMemoryNotificationClient(),
        logger: InMemoryAuditLogger
    ) throws -> DailyCheckRunner {
        let dateProvider = FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z"))
        let settings = AppSettings(timeZoneIdentifier: "UTC")
        let queryService = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: dateProvider,
            settings: settings
        )
        let overdueChecker = OverdueChecker(
            queryService: queryService,
            ruleStore: stores.rules,
            dateProvider: dateProvider,
            settings: settings
        )
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: notificationClient,
            dateProvider: dateProvider,
            settings: settings
        )

        return DailyCheckRunner(
            overdueChecker: overdueChecker,
            notificationScheduler: scheduler,
            ruleStore: stores.rules,
            stateStore: stateStore,
            dateProvider: dateProvider,
            settings: settings,
            auditLogger: logger
        )
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, rules: SQLiteDeadlineRuleStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteDeadlineRuleStore(connection: connection)
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
