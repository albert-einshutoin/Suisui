import XCTest
@testable import SuisuiCore

final class OverdueCheckerTests: XCTestCase {
    func testCheckerFindsOverdueDailyCandidatesAndSkipsMutedCompletedAndThrottledItems() throws {
        let stores = try makeStores()
        let dueOpen = try stores.tasks.create(title: "Open overdue", dueAt: "2026-06-16T12:00:00Z")
        let completed = try stores.tasks.create(title: "Completed overdue", dueAt: "2026-06-16T12:00:00Z")
        _ = try stores.tasks.update(id: completed.id, status: "completed")
        let muted = try stores.tasks.create(title: "Muted overdue", dueAt: "2026-06-16T12:00:00Z")
        let throttled = try stores.tasks.create(title: "Throttled overdue", dueAt: "2026-06-16T12:00:00Z")
        let future = try stores.tasks.create(title: "Future task", dueAt: "2026-06-18T12:00:00Z")

        _ = try stores.rules.create(DeadlineRule(target: .task(dueOpen.id), kind: .overdueDaily))
        _ = try stores.rules.create(
            DeadlineRule(
                target: .task(muted.id),
                kind: .overdueDaily,
                mutedAt: try Date.iso8601("2026-06-16T23:00:00Z")
            )
        )
        _ = try stores.rules.create(
            DeadlineRule(
                target: .task(throttled.id),
                kind: .overdueDaily,
                lastNotifiedAt: try Date.iso8601("2026-06-17T01:00:00Z")
            )
        )
        _ = try stores.rules.create(DeadlineRule(target: .task(future.id), kind: .overdueDaily))

        let checker = OverdueChecker(
            queryService: DeadlineQueryService(
                projectStore: stores.projects,
                taskStore: stores.tasks,
                dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
                settings: AppSettings(timeZoneIdentifier: "UTC")
            ),
            ruleStore: stores.rules,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        let result = try checker.check()

        XCTAssertEqual(result.candidates.map(\.item.title), ["Open overdue"])
        XCTAssertEqual(result.skipped.map(\.reason), [.muted, .alreadyNotifiedToday])
    }

    func testRuleStoreMarksRuleAsNotifiedForDailyThrottle() throws {
        let stores = try makeStores()
        let rule = try stores.rules.create(DeadlineRule(target: .task(1), kind: .overdueDaily))

        let updated = try stores.rules.markNotified(id: try XCTUnwrap(rule.id), at: try Date.iso8601("2026-06-17T12:00:00Z"))

        XCTAssertEqual(updated.lastNotifiedAt, try Date.iso8601("2026-06-17T12:00:00Z"))
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, rules: SQLiteDeadlineRuleStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
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

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
