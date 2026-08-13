import XCTest
@testable import SuisuiCore

final class DeadlineRuleStoreTests: XCTestCase {
    func testPhase4MigrationCreatesDeadlineRulesTable() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)

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
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        let store = SQLiteDeadlineRuleStore(connection: connection)

        let projectRule = try store.create(DeadlineRule(target: .project(10), kind: .tMinus7))
        let taskRule = try store.create(DeadlineRule(target: .task(20), kind: .dayOf))

        XCTAssertNotNil(projectRule.id)
        XCTAssertEqual(try store.list(for: .project(10)).map(\.kind), [.tMinus7])
        XCTAssertEqual(try store.list(for: .task(20)).map(\.kind), [.dayOf])
        XCTAssertEqual(try store.list().map(\.id), [projectRule.id, taskRule.id])
    }

    func testDeadlineRuleStoreThrowsWhenListFindsCorruptRuleKind() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        try connection.execute(
            """
            INSERT INTO deadline_rules (target_type, target_id, kind)
            VALUES ('task', 20, 'bogus');
            """
        )
        let store = SQLiteDeadlineRuleStore(connection: connection)

        XCTAssertThrowsError(try store.list()) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidEnum(column: "deadline_rules.kind", value: "bogus")
            )
        }
        XCTAssertThrowsError(try store.list(for: .task(20))) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidEnum(column: "deadline_rules.kind", value: "bogus")
            )
        }
    }

    func testDeadlineRuleStoreThrowsWhenGetFindsCorruptRuleKind() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        try connection.execute(
            """
            INSERT INTO deadline_rules (target_type, target_id, kind)
            VALUES ('project', 10, 'bogus');
            """
        )
        let store = SQLiteDeadlineRuleStore(connection: connection)

        XCTAssertThrowsError(try store.get(id: connection.lastInsertedRowID)) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidEnum(column: "deadline_rules.kind", value: "bogus")
            )
        }
    }

    func testDeadlineRuleStoreThrowsWhenListFindsCorruptTargetID() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        try connection.execute(
            """
            INSERT INTO deadline_rules (target_type, target_id, kind)
            VALUES ('task', 'oops', 'day_of');
            """
        )
        let store = SQLiteDeadlineRuleStore(connection: connection)

        XCTAssertThrowsError(try store.list()) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidInt64(column: "deadline_rules.target_id", value: "oops")
            )
        }
    }

    func testDeadlineRuleStoreThrowsWhenListFindsCorruptCustomDate() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        try connection.execute(
            """
            INSERT INTO deadline_rules (target_type, target_id, kind, custom_notify_at)
            VALUES ('task', 20, 'custom', 'not-a-date');
            """
        )
        let store = SQLiteDeadlineRuleStore(connection: connection)

        XCTAssertThrowsError(try store.list()) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidDate(column: "deadline_rules.custom_notify_at", value: "not-a-date")
            )
        }
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
