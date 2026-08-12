import XCTest
@testable import SuisuiCore

final class BoardOperationUndoTests: XCTestCase {
    // MARK: - Stack semantics

    func testStackPopsEntriesInLIFOOrder() {
        var stack = BoardOperationUndoStack()
        let first = makeTaskSnapshot(id: 1, title: "First")
        let second = makeTaskSnapshot(id: 2, title: "Second")

        stack.push(.revertStatus(snapshot: first))
        stack.push(.restoreTask(snapshot: second))

        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.pop(), .restoreTask(snapshot: second))
        XCTAssertEqual(stack.pop(), .revertStatus(snapshot: first))
        XCTAssertNil(stack.pop())
        XCTAssertTrue(stack.isEmpty)
    }

    func testStackCapsAtTenEntriesDroppingOldestFirst() {
        var stack = BoardOperationUndoStack()
        for id in Int64(1)...12 {
            stack.push(.revertStatus(snapshot: makeTaskSnapshot(id: id, title: "Task \(id)")))
        }

        XCTAssertEqual(BoardOperationUndoStack.maxEntries, 10)
        XCTAssertEqual(stack.count, 10)
        XCTAssertEqual(
            stack.entries.first,
            .revertStatus(snapshot: makeTaskSnapshot(id: 3, title: "Task 3"))
        )
        XCTAssertEqual(
            stack.last,
            .revertStatus(snapshot: makeTaskSnapshot(id: 12, title: "Task 12"))
        )
    }

    func testStackRemoveAllClearsEveryEntry() {
        var stack = BoardOperationUndoStack()
        stack.push(.revertStatus(snapshot: makeTaskSnapshot(id: 1, title: "Task")))
        stack.push(.restoreTask(snapshot: makeTaskSnapshot(id: 2, title: "Task")))

        stack.removeAll()

        XCTAssertTrue(stack.isEmpty)
        XCTAssertNil(stack.last)
    }

    // MARK: - Undo plain completion

    @MainActor
    func testUndoTaskCompletionReopensTaskAndFiresChangeNotification() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Ship weekly report",
            status: .planned
        ))
        subject.viewModel.load()
        let changeCountBeforeCompletion = subject.changeCount()

        subject.viewModel.toggleTaskCompletion(id: task.id)
        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .done)
        XCTAssertTrue(subject.viewModel.canUndoBoardOperation)

        subject.viewModel.undoLastBoardOperation()

        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .planned)
        XCTAssertFalse(subject.viewModel.canUndoBoardOperation)
        XCTAssertNotNil(subject.viewModel.boardUndoFeedback)
        XCTAssertNil(subject.viewModel.errorMessage)
        // One change for the completion, one for the undo.
        XCTAssertEqual(subject.changeCount(), changeCountBeforeCompletion + 2)
    }

    // MARK: - Undo recurrence completion

    @MainActor
    func testUndoRecurrenceCompletionDeletesRegeneratedOccurrenceAndReopensOriginal() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Water plants",
            status: .planned,
            dueAt: "2026-07-10",
            recurrence: "daily"
        ))
        subject.viewModel.load()

        subject.viewModel.moveTask(id: task.id, to: .done)

        let tasksAfterCompletion = allTasks(subject.viewModel)
        XCTAssertEqual(tasksAfterCompletion.count, 2)
        let regenerated = try XCTUnwrap(tasksAfterCompletion.first { $0.id != task.id })
        XCTAssertEqual(regenerated.recurrence, "daily")
        XCTAssertNotEqual(regenerated.status, .done)

        subject.viewModel.undoLastBoardOperation()

        let tasksAfterUndo = allTasks(subject.viewModel)
        XCTAssertEqual(tasksAfterUndo.map(\.id), [task.id])
        let restored = try XCTUnwrap(tasksAfterUndo.first)
        XCTAssertEqual(restored.status, .planned)
        XCTAssertEqual(restored.dueAt, "2026-07-10")
        XCTAssertEqual(restored.recurrence, "daily")
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testUndoRecurrenceCompletionKeepsRegeneratedOccurrenceTheUserAlreadyModified() throws {
        // Rule: undoing a recurrence completion deletes the regenerated next
        // occurrence only while it is untouched. Once the user modified (or
        // completed) it, undo keeps it and only reopens the original task.
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Review finances",
            status: .planned,
            dueAt: "2026-07-10",
            recurrence: "weekly"
        ))
        subject.viewModel.load()

        subject.viewModel.moveTask(id: task.id, to: .done)
        let regenerated = try XCTUnwrap(allTasks(subject.viewModel).first { $0.id != task.id })

        // Modify the regenerated occurrence outside the undo stack (as an
        // external mutation would) so the completion entry stays on top.
        _ = try subject.store.updateTask(id: regenerated.id, ProjectBoardTaskDraft(
            projectID: regenerated.projectID,
            title: "Review finances and taxes",
            detail: regenerated.detail,
            status: regenerated.status,
            priority: regenerated.priority,
            dueAt: regenerated.dueAt,
            recurrence: regenerated.recurrence
        ))
        subject.viewModel.load()

        subject.viewModel.undoLastBoardOperation()

        let tasksAfterUndo = allTasks(subject.viewModel)
        XCTAssertEqual(Set(tasksAfterUndo.map(\.id)), [task.id, regenerated.id])
        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .planned)
        XCTAssertEqual(currentTask(subject.viewModel, id: regenerated.id)?.title, "Review finances and taxes")
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testUndoReopenDoesNotRegenerateAnotherRecurrenceOccurrence() throws {
        // Reverting a reopen puts the task back to done through the undo
        // snapshot path, which must bypass completion-driven regeneration.
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Daily standup notes",
            status: .planned,
            dueAt: "2026-07-10",
            recurrence: "daily"
        ))
        subject.viewModel.load()

        subject.viewModel.moveTask(id: task.id, to: .done)
        let taskCountAfterCompletion = allTasks(subject.viewModel).count

        subject.viewModel.reopenCompletedTask(id: task.id)
        subject.viewModel.undoLastBoardOperation()

        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .done)
        XCTAssertEqual(allTasks(subject.viewModel).count, taskCountAfterCompletion)
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    // MARK: - Undo status move

    @MainActor
    func testUndoStatusMoveRestoresPreviousStatus() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Draft proposal",
            status: .planned
        ))
        subject.viewModel.load()

        subject.viewModel.moveTask(id: task.id, to: .inProgress)
        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .inProgress)

        subject.viewModel.undoLastBoardOperation()

        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .planned)
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testUndoDroppedBatchStatusMoveRestoresEachPreviousStatus() throws {
        let subject = try makeBoardSubject()
        let backlogTask = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Backlog item",
            status: .backlog
        ))
        let plannedTask = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Planned item",
            status: .planned
        ))
        subject.viewModel.load()

        XCTAssertTrue(subject.viewModel.moveDroppedTasks(ids: [backlogTask.id, plannedTask.id], to: .inProgress))
        XCTAssertEqual(currentTask(subject.viewModel, id: backlogTask.id)?.status, .inProgress)
        XCTAssertEqual(currentTask(subject.viewModel, id: plannedTask.id)?.status, .inProgress)
        XCTAssertEqual(subject.viewModel.boardOperationUndo.count, 1)

        subject.viewModel.undoLastBoardOperation()

        XCTAssertEqual(currentTask(subject.viewModel, id: backlogTask.id)?.status, .backlog)
        XCTAssertEqual(currentTask(subject.viewModel, id: plannedTask.id)?.status, .planned)
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    // MARK: - Undo delete

    @MainActor
    func testUndoDeleteRestoresEveryPersistedField() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Prepare launch checklist",
            detail: "Cover signing, notarization, and evidence.",
            status: .inProgress,
            priority: .high,
            dueAt: "2026-07-20",
            recurrence: "weekly"
        ))
        subject.viewModel.load()
        subject.viewModel.selectedProjectID = task.projectID
        subject.viewModel.selectedTaskID = task.id

        subject.viewModel.deleteSelectedTask()
        XCTAssertNil(currentTask(subject.viewModel, id: task.id))

        subject.viewModel.undoLastBoardOperation()

        let restored = try XCTUnwrap(allTasks(subject.viewModel).first { $0.title == "Prepare launch checklist" })
        XCTAssertEqual(restored.detail, "Cover signing, notarization, and evidence.")
        XCTAssertEqual(restored.status, .inProgress)
        XCTAssertEqual(restored.priority, .high)
        XCTAssertEqual(restored.dueAt, "2026-07-20")
        XCTAssertEqual(restored.recurrence, "weekly")
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testUndoDeleteOfCompletedTaskPreservesOriginalCompletionTimestamp() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Archive old receipts",
            status: .planned
        ))
        _ = try subject.store.moveTask(id: task.id, to: .done)
        subject.viewModel.load()
        let completedAt = try XCTUnwrap(currentTask(subject.viewModel, id: task.id)?.completedAt)
        subject.viewModel.selectedProjectID = task.projectID
        subject.viewModel.selectedTaskID = task.id

        subject.viewModel.deleteSelectedTask()
        subject.viewModel.undoLastBoardOperation()

        let restored = try XCTUnwrap(allTasks(subject.viewModel).first { $0.title == "Archive old receipts" })
        XCTAssertEqual(restored.status, .done)
        XCTAssertEqual(restored.completedAt, completedAt)
    }

    @MainActor
    func testUndoDeleteRestoresInboxVoiceCaptureMetadataAndAudioPath() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteProjectBoardStore(connection: connection)
        let captureStore = SQLiteInboxCaptureStore(connection: connection)
        let inboxProjectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let task = try store.createTask(ProjectBoardTaskDraft(
            projectID: inboxProjectID,
            title: "Prepare tomorrow's presentation",
            detail: "Voice memo task",
            status: .backlog
        ))
        let originalPath = "/Users/example/Library/Application Support/Suisui/InboxAudio/capture.m4a"
        let capture = try captureStore.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: task.id,
            audioFilePath: originalPath,
            durationSeconds: 84,
            transcript: "Create the presentation materials.",
            interpretationSummary: "Prepare presentation materials",
            memo: "Use the new product screenshots.",
            classificationStatus: .classified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-08-12T10:15:00Z"
        ))
        let viewModel = ProjectBoardViewModel(
            store: store,
            inboxCaptureStore: captureStore
        )
        viewModel.load()
        viewModel.selectedProjectID = task.projectID
        viewModel.selectedTaskID = task.id

        viewModel.deleteSelectedTask()
        XCTAssertThrowsError(try captureStore.get(id: capture.id))

        viewModel.undoLastBoardOperation()

        let restoredTaskID = try XCTUnwrap(viewModel.selectedTaskID)
        let restored = try XCTUnwrap(captureStore.list(taskID: restoredTaskID).first)
        XCTAssertEqual(restored.audioFilePath, originalPath)
        XCTAssertEqual(restored.transcript, capture.transcript)
        XCTAssertEqual(restored.interpretationSummary, capture.interpretationSummary)
        XCTAssertEqual(restored.memo, capture.memo)
        XCTAssertEqual(restored.classificationStatus, capture.classificationStatus)
        XCTAssertEqual(restored.transcriptionStatus, capture.transcriptionStatus)
        XCTAssertNil(viewModel.errorMessage)
    }

    // MARK: - Undo inspector edit

    @MainActor
    func testUndoInspectorEditRestoresPreviousFieldValues() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Write release notes",
            detail: "Original detail",
            status: .planned,
            priority: .medium,
            dueAt: "2026-07-15"
        ))
        subject.viewModel.load()
        subject.viewModel.selectedProjectID = task.projectID
        subject.viewModel.selectedTaskID = task.id

        subject.viewModel.updateSelectedTask(
            title: "Write and publish release notes",
            detail: "Edited detail",
            status: .inProgress,
            priority: .high,
            dueAt: "2026-07-18"
        )
        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.priority, .high)

        subject.viewModel.undoLastBoardOperation()

        let restored = try XCTUnwrap(currentTask(subject.viewModel, id: task.id))
        XCTAssertEqual(restored.title, "Write release notes")
        XCTAssertEqual(restored.detail, "Original detail")
        XCTAssertEqual(restored.status, .planned)
        XCTAssertEqual(restored.priority, .medium)
        XCTAssertEqual(restored.dueAt, "2026-07-15")
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testInspectorSaveWithoutChangesDoesNotPushUndoEntry() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Stable task",
            detail: "Same detail",
            status: .planned,
            priority: .medium,
            dueAt: "2026-07-15"
        ))
        subject.viewModel.load()
        subject.viewModel.selectedProjectID = task.projectID
        subject.viewModel.selectedTaskID = task.id

        subject.viewModel.updateSelectedTask(
            title: "Stable task",
            detail: "Same detail",
            status: .planned,
            priority: .medium,
            dueAt: "2026-07-15"
        )

        XCTAssertFalse(subject.viewModel.canUndoBoardOperation)
    }

    @MainActor
    func testUndoInspectorCompletionSaveRemovesRegeneratedOccurrence() throws {
        let subject = try makeBoardSubject()
        let task = try subject.store.createTask(ProjectBoardTaskDraft(
            projectID: subject.inboxProjectID,
            title: "Weekly review",
            status: .planned,
            dueAt: "2026-07-10",
            recurrence: "weekly"
        ))
        subject.viewModel.load()
        subject.viewModel.selectedProjectID = task.projectID
        subject.viewModel.selectedTaskID = task.id

        subject.viewModel.updateSelectedTask(
            title: "Weekly review",
            detail: "",
            status: .done,
            priority: .medium,
            dueAt: "2026-07-10",
            recurrence: "weekly"
        )
        XCTAssertEqual(allTasks(subject.viewModel).count, 2)

        subject.viewModel.undoLastBoardOperation()

        XCTAssertEqual(allTasks(subject.viewModel).map(\.id), [task.id])
        XCTAssertEqual(currentTask(subject.viewModel, id: task.id)?.status, .planned)
    }

    // MARK: - Undo notification and feedback

    @MainActor
    func testUndoWithEmptyStackIsSilentNoOp() throws {
        let subject = try makeBoardSubject()
        subject.viewModel.load()
        let changeCountBefore = subject.changeCount()

        subject.viewModel.undoLastBoardOperation()

        XCTAssertEqual(subject.changeCount(), changeCountBefore)
        XCTAssertNil(subject.viewModel.boardUndoFeedback)
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    // MARK: - Helpers

    private func makeTaskSnapshot(id: Int64, title: String) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: 1,
            title: title,
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: nil
        )
    }

    @MainActor
    private func makeBoardSubject() throws -> BoardUndoSubject {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteProjectBoardStore(connection: connection)
        let inboxProjectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let changeCounter = ChangeCounter()
        let viewModel = ProjectBoardViewModel(
            store: store,
            onChange: { changeCounter.count += 1 }
        )
        return BoardUndoSubject(
            viewModel: viewModel,
            store: store,
            inboxProjectID: inboxProjectID,
            changeCounter: changeCounter
        )
    }

    @MainActor
    private func allTasks(_ viewModel: ProjectBoardViewModel) -> [ProjectBoardTask] {
        viewModel.snapshot.projects.flatMap(\.tasks)
    }

    @MainActor
    private func currentTask(_ viewModel: ProjectBoardViewModel, id: Int64) -> ProjectBoardTask? {
        allTasks(viewModel).first { $0.id == id }
    }
}

private final class ChangeCounter {
    var count = 0
}

private struct BoardUndoSubject {
    let viewModel: ProjectBoardViewModel
    let store: SQLiteProjectBoardStore
    let inboxProjectID: Int64
    private let changeCounter: ChangeCounter

    init(
        viewModel: ProjectBoardViewModel,
        store: SQLiteProjectBoardStore,
        inboxProjectID: Int64,
        changeCounter: ChangeCounter
    ) {
        self.viewModel = viewModel
        self.store = store
        self.inboxProjectID = inboxProjectID
        self.changeCounter = changeCounter
    }

    func changeCount() -> Int {
        changeCounter.count
    }
}
