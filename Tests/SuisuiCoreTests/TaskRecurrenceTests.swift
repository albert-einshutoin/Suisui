import XCTest
@testable import SuisuiCore

final class TaskRecurrenceTests: XCTestCase {
    private static let utcIdentifier = "UTC"

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: Self.utcIdentifier) ?? .current
        return calendar
    }

    private func makeConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private func makeTaskStore() throws -> SQLiteTaskStore {
        SQLiteTaskStore(connection: try makeConnection())
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) throws -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return try XCTUnwrap(utcCalendar.date(from: components))
    }

    // MARK: - nextDueDate math

    func testNextDueDateAdvancesByCadence() throws {
        let calendar = utcCalendar
        let base = try utcDate(year: 2026, month: 7, day: 1, hour: 9, minute: 30)

        XCTAssertEqual(
            TaskRecurrence.daily.nextDueDate(after: base, calendar: calendar),
            try utcDate(year: 2026, month: 7, day: 2, hour: 9, minute: 30)
        )
        XCTAssertEqual(
            TaskRecurrence.weekly.nextDueDate(after: base, calendar: calendar),
            try utcDate(year: 2026, month: 7, day: 8, hour: 9, minute: 30)
        )
        XCTAssertEqual(
            TaskRecurrence.monthly.nextDueDate(after: base, calendar: calendar),
            try utcDate(year: 2026, month: 8, day: 1, hour: 9, minute: 30)
        )
    }

    func testMonthlyNextDueDateClampsToEndOfShorterMonth() throws {
        let calendar = utcCalendar
        let endOfJanuary = try utcDate(year: 2026, month: 1, day: 31, hour: 9, minute: 30)

        XCTAssertEqual(
            TaskRecurrence.monthly.nextDueDate(after: endOfJanuary, calendar: calendar),
            try utcDate(year: 2026, month: 2, day: 28, hour: 9, minute: 30)
        )
    }

    // MARK: - regenerationDraft

    func testRegenerationDraftAdvancesOverdueDailyTaskStrictlyIntoTheFuture() throws {
        let record = TaskRecord(
            id: 1,
            projectID: 7,
            title: "Water the plants",
            status: "completed",
            dueAt: "2026-07-01T09:30:00Z",
            priority: "high",
            sourceCommand: "app.project-board",
            detail: "Kitchen and balcony",
            recurrence: "daily"
        )
        let completedAt = try utcDate(year: 2026, month: 7, day: 7, hour: 12)

        let draft = try XCTUnwrap(
            TaskRecurrenceRegenerator.regenerationDraft(
                for: record,
                completedAt: completedAt,
                timeZoneIdentifier: Self.utcIdentifier
            )
        )

        // Overdue occurrences are skipped: the next copy keeps the 09:30
        // time-of-day but lands strictly after the completion instant.
        XCTAssertEqual(draft.dueAt, "2026-07-08T09:30:00Z")
        XCTAssertEqual(draft.title, "Water the plants")
        XCTAssertEqual(draft.projectID, 7)
        XCTAssertEqual(draft.priority, "high")
        XCTAssertEqual(draft.detail, "Kitchen and balcony")
        XCTAssertEqual(draft.status, "open")
        XCTAssertEqual(draft.recurrence, "daily")
        XCTAssertEqual(draft.sourceCommand, "recurrence")
    }

    func testRegenerationDraftPreservesDateOnlyDueFormat() throws {
        let record = TaskRecord(
            id: 2,
            projectID: nil,
            title: "Weekly review",
            status: "completed",
            dueAt: "2026-07-01",
            priority: nil,
            sourceCommand: nil,
            recurrence: "weekly"
        )
        let completedAt = try utcDate(year: 2026, month: 7, day: 7, hour: 12)

        let draft = try XCTUnwrap(
            TaskRecurrenceRegenerator.regenerationDraft(
                for: record,
                completedAt: completedAt,
                timeZoneIdentifier: Self.utcIdentifier
            )
        )

        XCTAssertEqual(draft.dueAt, "2026-07-08")
    }

    func testRegenerationDraftIsNilWithoutRecurrenceOrDueDate() throws {
        let completedAt = try utcDate(year: 2026, month: 7, day: 7, hour: 12)
        let withoutRecurrence = TaskRecord(
            id: 3,
            projectID: nil,
            title: "One-off",
            status: "completed",
            dueAt: "2026-07-01T09:30:00Z",
            priority: nil,
            sourceCommand: nil
        )
        let withoutDueDate = TaskRecord(
            id: 4,
            projectID: nil,
            title: "Recurring but unscheduled",
            status: "completed",
            dueAt: nil,
            priority: nil,
            sourceCommand: nil,
            recurrence: "daily"
        )

        XCTAssertNil(
            TaskRecurrenceRegenerator.regenerationDraft(
                for: withoutRecurrence,
                completedAt: completedAt,
                timeZoneIdentifier: Self.utcIdentifier
            )
        )
        XCTAssertNil(
            TaskRecurrenceRegenerator.regenerationDraft(
                for: withoutDueDate,
                completedAt: completedAt,
                timeZoneIdentifier: Self.utcIdentifier
            )
        )
    }

    // MARK: - completeAndRegenerate

    func testCompleteAndRegenerateCompletesOriginalAndInsertsExactlyOneOpenCopy() throws {
        let taskStore = try makeTaskStore()
        let task = try taskStore.create(
            title: "Send weekly status",
            dueAt: "2026-07-01T09:30:00Z",
            priority: "medium",
            status: "open",
            detail: "Mail the summary",
            recurrence: "weekly"
        )
        let now = try utcDate(year: 2026, month: 7, day: 7, hour: 12)

        let result = try taskStore.completeAndRegenerate(
            id: task.id,
            now: now,
            timeZoneIdentifier: Self.utcIdentifier
        )

        XCTAssertEqual(result.completed.id, task.id)
        XCTAssertEqual(result.completed.status, "completed")
        XCTAssertNotNil(result.completed.completedAt)

        let regenerated = try XCTUnwrap(result.regenerated)
        XCTAssertNotEqual(regenerated.id, task.id)
        XCTAssertEqual(regenerated.status, "open")
        XCTAssertEqual(regenerated.title, "Send weekly status")
        XCTAssertEqual(regenerated.detail, "Mail the summary")
        XCTAssertEqual(regenerated.priority, "medium")
        XCTAssertEqual(regenerated.dueAt, "2026-07-08T09:30:00Z")
        XCTAssertEqual(regenerated.recurrence, "weekly")
        XCTAssertEqual(regenerated.sourceCommand, "recurrence")
        XCTAssertNil(regenerated.completedAt)

        let allTasks = try taskStore.listAll()
        XCTAssertEqual(allTasks.count, 2)
        XCTAssertEqual(allTasks.filter { $0.status == "open" }.count, 1)
    }

    func testCompleteAndRegenerateWithoutRecurrenceCompletesWithoutRegeneration() throws {
        let taskStore = try makeTaskStore()
        let task = try taskStore.create(title: "One-off errand", dueAt: "2026-07-01T09:30:00Z")

        let result = try taskStore.completeAndRegenerate(
            id: task.id,
            now: try utcDate(year: 2026, month: 7, day: 7, hour: 12),
            timeZoneIdentifier: Self.utcIdentifier
        )

        XCTAssertEqual(result.completed.status, "completed")
        XCTAssertNil(result.regenerated)
        XCTAssertEqual(try taskStore.listAll().count, 1)
    }

    func testBoardMoveToDoneRegeneratesRecurringTask() throws {
        let connection = try makeConnection()
        let board = SQLiteProjectBoardStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let project = try board.createProject(title: "Home")
        let task = try board.createTask(
            ProjectBoardTaskDraft(
                projectID: project.id,
                title: "Take out recycling",
                status: .planned,
                priority: .medium,
                dueAt: "2026-07-01T09:30:00Z",
                recurrence: "daily"
            )
        )

        let moved = try board.moveTask(id: task.id, to: .done)

        XCTAssertEqual(moved.status, .done)
        let records = try taskStore.listAll()
        XCTAssertEqual(records.filter { $0.title == "Take out recycling" }.count, 2)
        let regenerated = try XCTUnwrap(
            records.first { $0.title == "Take out recycling" && $0.status == "open" }
        )
        XCTAssertEqual(regenerated.recurrence, "daily")
        XCTAssertEqual(regenerated.sourceCommand, "recurrence")
        let regeneratedDueAt = try XCTUnwrap(regenerated.dueAt)
        let parsedDueAt = try XCTUnwrap(DeadlineDateParser.date(from: regeneratedDueAt))
        XCTAssertGreaterThan(parsedDueAt, Date())
    }

    // MARK: - schema

    func testMigrationAddsRecurrenceColumnAndRoundTripsValues() throws {
        let taskStore = try makeTaskStore()
        let task = try taskStore.create(
            title: "Review finances",
            dueAt: "2026-07-10",
            recurrence: "weekly"
        )

        XCTAssertEqual(try taskStore.get(id: task.id).recurrence, "weekly")

        let cleared = try taskStore.updateFields(id: task.id, recurrence: .clear)
        XCTAssertNil(cleared.recurrence)

        let restored = try taskStore.updateFields(id: task.id, recurrence: .set("monthly"))
        XCTAssertEqual(restored.recurrence, "monthly")

        XCTAssertThrowsError(try taskStore.create(title: "Bad cadence", recurrence: "yearly"))
    }
}
