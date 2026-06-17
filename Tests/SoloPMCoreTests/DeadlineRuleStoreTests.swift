import XCTest
@testable import SoloPMCore

final class DeadlineRuleStoreTests: XCTestCase {
    func testPhase4MigrationCreatesDeadlineRulesTable() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)

        XCTAssertTrue(try connection.tableExists("deadline_rules"))
    }

    func testDeadlineRuleCalculatesNotifyAtFromDueDate() throws {
        let dueAt = try Date.iso8601("2026-06-30T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let t3 = DeadlineRule(target: .project(1), kind: .tMinus3)
        let dayOf = DeadlineRule(target: .task(2), kind: .dayOf)
        let custom = DeadlineRule(
            target: .task(2),
            kind: .custom,
            customNotifyAt: try Date.iso8601("2026-06-29T09:00:00Z")
        )
        let overdueDaily = DeadlineRule(target: .task(2), kind: .overdueDaily)

        XCTAssertEqual(t3.notifyAt(forDueAt: dueAt, calendar: calendar), try Date.iso8601("2026-06-27T12:00:00Z"))
        XCTAssertEqual(dayOf.notifyAt(forDueAt: dueAt, calendar: calendar), dueAt)
        XCTAssertEqual(custom.notifyAt(forDueAt: dueAt, calendar: calendar), try Date.iso8601("2026-06-29T09:00:00Z"))
        XCTAssertEqual(overdueDaily.notifyAt(forDueAt: dueAt, calendar: calendar), try Date.iso8601("2026-07-01T12:00:00Z"))
    }

    func testDeadlineRuleStorePersistsProjectAndTaskRules() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        let store = SQLiteDeadlineRuleStore(connection: connection)

        let projectRule = try store.create(DeadlineRule(target: .project(10), kind: .tMinus7))
        let taskRule = try store.create(DeadlineRule(target: .task(20), kind: .dayOf))

        XCTAssertNotNil(projectRule.id)
        XCTAssertEqual(try store.list(for: .project(10)).map(\.kind), [.tMinus7])
        XCTAssertEqual(try store.list(for: .task(20)).map(\.kind), [.dayOf])
        XCTAssertEqual(try store.list().map(\.id), [projectRule.id, taskRule.id])
    }
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
