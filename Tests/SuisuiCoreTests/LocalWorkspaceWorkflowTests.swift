import XCTest
@testable import SuisuiCore

final class LocalWorkspaceWorkflowTests: XCTestCase {
    @MainActor
    func testReminderLookupFailureIsUnavailableAndReloadRecoversTheReadModel() throws {
        let connection = try migratedConnection()
        let queue = LookupFailingAssistantQueueStore(store: SQLiteAssistantQueueStore(connection: connection))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T01:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let board = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection), assistantQueueStore: queue,
            readModelNow: { now }, readModelCalendar: { calendar }
        )
        board.load()
        _ = try XCTUnwrap(board.createInboxTask(title: "Due today", dueAt: "2026-10-03T06:00:00Z"))
        queue.failsLookup = true

        board.refreshDerivedReadModels(on: now, calendar: calendar)

        XCTAssertEqual(board.derivedReadModels.todayWorkflowSnapshot.assistantContext.reminderSummary,
                       "Today reminder draft status is unavailable. Reload to try again.")
        guard case .providerFailed = board.failure else {
            return XCTFail("A failed exact queue lookup must publish a recoverable provider failure")
        }
        XCTAssertEqual(board.failureActionLabel, "Reload")
        queue.failsLookup = false
        XCTAssertTrue(board.reloadAfterChange(from: board.changeSourceID))
        XCTAssertEqual(board.derivedReadModels.todayWorkflowSnapshot.assistantContext.reminderSummary,
                       "No Today reminder draft queued.")
        board.retryCurrentFailure()
        XCTAssertNil(board.failure)
        XCTAssertEqual(board.derivedReadModels.todayWorkflowSnapshot.assistantContext.reminderSummary,
                       "No Today reminder draft queued.")
    }

    func testSearchDatabaseFailureIsNotReportedAsNoMatches() throws {
        let connection = try migratedConnection()
        let search = CommandPaletteContentSearchService(
            taskStore: SQLiteTaskStore(connection: connection),
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        try connection.execute("DROP TABLE tasks")

        XCTAssertThrowsError(try search.search(query: "report"))
    }

    @MainActor
    func testFailedEnrichedCaptureDoesNotLeaveAnEmptyInboxProject() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectBoardStore(connection: connection)
        try connection.execute("""
            CREATE TRIGGER reject_capture BEFORE INSERT ON tasks
            BEGIN SELECT RAISE(ABORT, 'capture rejected'); END;
            """)
        let board = ProjectBoardViewModel(store: store)

        XCTAssertNil(board.createInboxTask(title: "Report", dueAt: "2026-10-04T06:00:00Z"))
        XCTAssertTrue(try SQLiteProjectStore(connection: connection).listForProjectBoard().isEmpty)
        XCTAssertNotNil(board.failure)
    }

    @MainActor
    func testPreviewedDateIsSavedWithoutReinterpretingInput() throws {
        let connection = try migratedConnection()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T01:00:00Z"))
        var capture = QuickCaptureDraft(
            input: "明日15時 レポート提出", now: now,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        )
        XCTAssertEqual(capture.draft.title, "レポート提出")
        XCTAssertEqual(capture.draft.dueAt, "2026-10-04T06:00:00Z")
        let editedDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T03:00:00Z"))
        capture.setDueDate(editedDate)
        capture.input = "明日15時 レポート提出 (修正版)"
        let board = ProjectBoardViewModel(store: SQLiteProjectBoardStore(connection: connection))
        let task = try XCTUnwrap(board.createInboxTask(capture.draft))

        XCTAssertEqual(task.title, "レポート提出 (修正版)")
        XCTAssertEqual(task.dueAt, "2026-10-05T03:00:00Z")
        XCTAssertEqual(board.inboxTriageRecord(for: task)?.disposition, .unprocessed)
    }

    @MainActor
    func testRemovingDateInterpretationPreservesOriginalWords() throws {
        var capture = QuickCaptureDraft(input: "明日15時 レポート提出")
        capture.removeInferredDueDate()
        capture.input = "明日15時 レポート提出 (修正版)"
        XCTAssertEqual(capture.draft.title, capture.input)
        XCTAssertNil(capture.draft.dueAt)
        let board = ProjectBoardViewModel(store: SQLiteProjectBoardStore(connection: try migratedConnection()))
        let saved = try XCTUnwrap(board.createInboxTask(capture.draft))
        XCTAssertEqual(saved.title, capture.input)
        XCTAssertNil(saved.dueAt)
    }

    @MainActor
    func testOriginNotificationRefreshesAfterACommittedWriteAndFailedReload() throws {
        let store = InMemoryProjectBoardStore()
        let board = ProjectBoardViewModel(store: store)
        board.load()
        store.snapshotReadError = DatabaseError.busyTimeout(operation: "read")
        let committed = try XCTUnwrap(board.createInboxTask(title: "Committed task"))
        XCTAssertTrue(board.inboxTasks.isEmpty)
        XCTAssertNotNil(board.failure)

        store.snapshotReadError = nil
        XCTAssertTrue(board.reloadAfterChange(from: board.changeSourceID))
        XCTAssertEqual(board.inboxTasks.map(\.id), [committed.id])
        XCTAssertFalse(board.reloadAfterChange(from: board.changeSourceID))
        board.retryCurrentFailure()
        XCTAssertNil(board.failure)
    }

    @MainActor
    func testMenuAndBoardUseTheSameAtomicEnrichedCapture() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectBoardStore(connection: connection)
        let menu = MenuBarQuickCaptureController(store: store)
        let draft = InboxTaskDraft(title: "Report", detail: "Include sources", priority: .high, dueAt: "2026-10-04T06:00:00Z")
        let task = try XCTUnwrap(menu.createInboxTask(draft))
        let board = ProjectBoardViewModel(store: store)
        board.load()

        XCTAssertEqual(board.inboxTasks.map(\.id), [task.id])
        XCTAssertEqual(task.detail, "Include sources")
        XCTAssertEqual(task.priority, .high)
        XCTAssertEqual(task.dueAt, draft.dueAt)
        XCTAssertEqual(board.inboxTriageRecord(for: task)?.disposition, .unprocessed)
    }

    @MainActor
    func testChangeRefreshPreservesOriginSelectionAndUpdatesOtherWindows() throws {
        let store = InMemoryProjectBoardStore()
        let origin = ProjectBoardViewModel(store: store)
        let other = ProjectBoardViewModel(store: store)
        origin.load()
        other.load()
        let task = try XCTUnwrap(origin.createInboxTask(title: "Shared local capture"))

        XCTAssertFalse(origin.reloadAfterChange(from: origin.changeSourceID))
        XCTAssertEqual(origin.selectedTaskID, task.id)
        XCTAssertTrue(other.reloadAfterChange(from: origin.changeSourceID))
        XCTAssertEqual(other.inboxTasks.map(\.id), [task.id])
        XCTAssertTrue(other.reloadAfterChange(from: nil))
    }

    @MainActor
    func testSearchFailureAndSuccessfulEmptySearchHaveDifferentStates() async {
        let empty = CommandPaletteSearchViewModel(provider: { _ in [] })
        await empty.search(query: "report", debounceNanoseconds: 0)
        XCTAssertEqual(empty.state, .loaded([]))
        let failed = CommandPaletteSearchViewModel(provider: { _ in
            throw DatabaseError.executeFailed("test database unavailable")
        })
        await failed.search(query: "report", debounceNanoseconds: 0)
        guard case .failed(let message) = failed.state else { return XCTFail("Expected a visible search failure") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertTrue(failed.matches.isEmpty)
    }

    @MainActor
    func testSearchClearsPreviousMatchesAndRejectsLateResults() async throws {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let model = CommandPaletteSearchViewModel(provider: { query in
            if query == "old" {
                started.signal()
                _ = release.wait(timeout: .now() + 5)
            }
            return [CommandPaletteContentMatch(source: .task(id: 1, projectID: nil), title: query, content: query)]
        })
        await model.search(query: "initial", debounceNanoseconds: 0)
        XCTAssertEqual(model.matches.first?.title, "initial")
        let pending = Task { await model.search(query: "old", debounceNanoseconds: 0) }
        let waitForStart: @Sendable () -> Bool = { started.wait(timeout: .now() + 5) == .success }
        let didStart = await Task.detached { waitForStart() }.value
        defer { release.signal() }
        XCTAssertTrue(didStart)
        XCTAssertEqual(model.state, .loading)
        XCTAssertTrue(model.matches.isEmpty)
        await model.search(query: "new", debounceNanoseconds: 0)
        release.signal()
        await pending.value
        XCTAssertEqual(model.matches.first?.title, "new")
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }
}

private final class LookupFailingAssistantQueueStore: AssistantQueueStore, @unchecked Sendable {
    let store: SQLiteAssistantQueueStore
    var failsLookup = false

    init(store: SQLiteAssistantQueueStore) { self.store = store }
    func get(id: String) throws -> AssistantQueueItem {
        if failsLookup { throw DatabaseError.stepFailed("lookup unavailable") }
        return try store.get(id: id)
    }
    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem { try store.save(item) }
    func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? { try store.insertIfAbsent(item) }
    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] { try store.list(filter: filter) }
    func stateCounts() throws -> AssistantQueueStateCounts { try store.stateCounts() }
    func transition(id: String, _ transform: (AssistantQueueItem) throws -> AssistantQueueItem) throws -> AssistantQueueItem {
        try store.transition(id: id, transform)
    }
}
