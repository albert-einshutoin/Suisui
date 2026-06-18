import XCTest
@testable import SoloPMCore

final class ProjectBoardStoreTests: XCTestCase {
    func testSQLiteBoardStoreCreatesDefaultProjectWithoutMockTasks() throws {
        let store = try makeStore()

        let snapshot = try store.loadSnapshot()

        XCTAssertEqual(snapshot.projects.map(\.title), ["Inbox"])
        XCTAssertEqual(snapshot.projects.first?.columns.flatMap(\.tasks), [])
    }

    func testCreateTaskPersistsRequestedColumnMetadataAndDetail() throws {
        let store = try makeStore()
        let projectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)

        _ = try store.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Write onboarding issue",
            detail: "Capture expected setup steps for the alpha release.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-20"
        ))

        let snapshot = try store.loadSnapshot()
        let plannedTasks = try XCTUnwrap(snapshot.projects.first?.column(.planned)?.tasks)

        XCTAssertEqual(plannedTasks.map(\.title), ["Write onboarding issue"])
        XCTAssertEqual(plannedTasks.first?.detail, "Capture expected setup steps for the alpha release.")
        XCTAssertEqual(plannedTasks.first?.status, .planned)
        XCTAssertEqual(plannedTasks.first?.priority, .high)
        XCTAssertEqual(plannedTasks.first?.dueLabel, "2026-06-20")
    }

    func testLoadSnapshotShowsUnassignedPersistentTasksInInbox() throws {
        let stores = try makeStoreBundle()
        _ = try stores.projects.create(title: "Launch Readiness")
        _ = try stores.tasks.create(
            title: "Triage loose task",
            projectID: nil,
            status: "planned",
            detail: "Created outside the board UI."
        )

        let snapshot = try stores.board.loadSnapshot()
        let inbox = try XCTUnwrap(snapshot.projects.first { $0.title == "Inbox" })

        XCTAssertEqual(inbox.column(.planned)?.tasks.map(\.title), ["Triage loose task"])
        XCTAssertEqual(inbox.subtitle, "1 open / 1 total")
    }

    func testUpdateTaskMovesCardAcrossColumnsAndUpdatesMetadata() throws {
        let store = try makeStore()
        let projectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let task = try store.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Draft release checklist",
            detail: "",
            status: .backlog,
            priority: .medium,
            dueAt: nil
        ))

        _ = try store.updateTask(
            id: task.id,
            ProjectBoardTaskDraft(
                projectID: projectID,
                title: "Finalize release checklist",
                detail: "Confirm notarization and Sparkle metadata.",
                status: .inProgress,
                priority: .high,
                dueAt: "2026-06-21"
            )
        )

        let snapshot = try store.loadSnapshot()

        XCTAssertEqual(snapshot.projects.first?.column(.backlog)?.tasks, [])
        let inProgressTasks = try XCTUnwrap(snapshot.projects.first?.column(.inProgress)?.tasks)
        XCTAssertEqual(inProgressTasks.first?.title, "Finalize release checklist")
        XCTAssertEqual(inProgressTasks.first?.detail, "Confirm notarization and Sparkle metadata.")
        XCTAssertEqual(inProgressTasks.first?.priority, .high)
        XCTAssertEqual(inProgressTasks.first?.dueLabel, "2026-06-21")
    }

    func testMoveTaskPersistsNewStatusWithoutLosingMetadata() throws {
        let store = try makeStore()
        let projectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let task = try store.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Wire task drag flow",
            detail: "Keep details while changing columns.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))

        _ = try store.moveTask(id: task.id, to: .inProgress)

        let snapshot = try store.loadSnapshot()

        XCTAssertEqual(snapshot.projects.first?.column(.planned)?.tasks, [])
        let moved = try XCTUnwrap(snapshot.projects.first?.column(.inProgress)?.tasks.first)
        XCTAssertEqual(moved.id, task.id)
        XCTAssertEqual(moved.title, "Wire task drag flow")
        XCTAssertEqual(moved.detail, "Keep details while changing columns.")
        XCTAssertEqual(moved.priority, .high)
        XCTAssertEqual(moved.dueAt, "2026-06-22")
    }

    func testUpdateTaskCanClearDueDate() throws {
        let store = try makeStore()
        let projectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let task = try store.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Clear due date",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-22"
        ))

        _ = try store.updateTask(id: task.id, ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Clear due date",
            status: .planned,
            priority: .medium,
            dueAt: nil
        ))

        let snapshot = try store.loadSnapshot()
        let updated = try XCTUnwrap(snapshot.projects.first?.column(.planned)?.tasks.first)
        XCTAssertNil(updated.dueAt)
    }

    func testDeleteTaskRemovesCardFromPersistentSnapshot() throws {
        let store = try makeStore()
        let projectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let task = try store.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Remove stale release task",
            status: .blocked,
            priority: .medium
        ))

        try store.deleteTask(id: task.id)

        let snapshot = try store.loadSnapshot()

        XCTAssertFalse(snapshot.projects.flatMap(\.tasks).contains { $0.id == task.id })
        XCTAssertEqual(snapshot.projects.first?.column(.blocked)?.tasks, [])
    }

    func testCreateUpdateAndCompleteProjectAppearInBoardSnapshot() throws {
        let store = try makeStore()

        let project = try store.createProject(title: "Launch Readiness")
        _ = try store.updateProject(id: project.id, title: "Alpha Launch Readiness")
        _ = try store.completeProject(id: project.id)

        let snapshot = try store.loadSnapshot()
        let updated = try XCTUnwrap(snapshot.projects.first { $0.id == project.id })

        XCTAssertEqual(updated.title, "Alpha Launch Readiness")
        XCTAssertTrue(updated.isCompleted)
        XCTAssertEqual(updated.subtitle, "0 open / 0 total")
    }

    func testCompletingProjectMarksOpenTasksDone() throws {
        let store = try makeStore()
        let project = try store.createProject(title: "Launch Readiness")
        _ = try store.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Prepare launch checklist",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T00:00:00Z"
        ))

        _ = try store.completeProject(id: project.id)

        let snapshot = try store.loadSnapshot()
        let completed = try XCTUnwrap(snapshot.projects.first { $0.id == project.id })

        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(completed.column(.planned)?.tasks, [])
        XCTAssertEqual(completed.column(.done)?.tasks.map(\.title), ["Prepare launch checklist"])
        XCTAssertEqual(completed.subtitle, "0 open / 1 total")
    }

    func testCreatingOpenTaskReopensCompletedProject() throws {
        let store = try makeStore()
        let project = try store.createProject(title: "Launch Readiness")
        _ = try store.completeProject(id: project.id)

        _ = try store.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Follow-up from release review",
            status: .planned,
            priority: .medium
        ))

        let snapshot = try store.loadSnapshot()
        let reopened = try XCTUnwrap(snapshot.projects.first { $0.id == project.id })

        XCTAssertFalse(reopened.isCompleted)
        XCTAssertEqual(reopened.column(.planned)?.tasks.map(\.title), ["Follow-up from release review"])
        XCTAssertEqual(reopened.subtitle, "1 open / 1 total")
    }

    func testArchivedProjectRejectsNewTaskCreation() throws {
        let store = try makeStore()
        let project = try store.createProject(title: "Paused Initiative")
        _ = try store.archiveProject(id: project.id)

        XCTAssertThrowsError(
            try store.createTask(ProjectBoardTaskDraft(
                projectID: project.id,
                title: "Hidden work should not be created",
                status: .planned,
                priority: .medium
            ))
        ) { error in
            XCTAssertEqual(error as? ProjectBoardStoreError, .archivedProjectCannotAcceptTasks)
        }
    }

    func testArchiveProjectRemovesItFromActiveBoardWithoutDeletingRows() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Stale Initiative")
        _ = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Keep historical context",
            status: .planned,
            priority: .medium
        ))

        _ = try stores.board.archiveProject(id: project.id)

        let snapshot = try stores.board.loadSnapshot()

        XCTAssertFalse(snapshot.projects.contains { $0.id == project.id })
        XCTAssertEqual(try stores.projects.get(id: project.id).status, "archived")
        XCTAssertEqual(
            try stores.tasks.listAll().filter { $0.projectID == project.id }.map(\.title),
            ["Keep historical context"]
        )
    }

    func testArchivedProjectCanBeLoadedAndRestoredToActiveBoard() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Restore Candidate")
        _ = try stores.board.archiveProject(id: project.id)

        let archivedSnapshot = try stores.board.loadSnapshot(includeArchived: true)
        let archivedProject = try XCTUnwrap(archivedSnapshot.projects.first { $0.id == project.id })

        XCTAssertTrue(archivedProject.isArchived)

        _ = try stores.board.restoreProject(id: project.id)

        let activeSnapshot = try stores.board.loadSnapshot()
        let restoredProject = try XCTUnwrap(activeSnapshot.projects.first { $0.id == project.id })

        XCTAssertFalse(restoredProject.isArchived)
    }

    func testArchivingLastVisibleProjectCreatesFreshInboxForFirstRunContinuity() throws {
        let store = try makeStore()
        let inbox = try XCTUnwrap(store.loadSnapshot().projects.first)

        _ = try store.archiveProject(id: inbox.id)

        let snapshot = try store.loadSnapshot()

        XCTAssertEqual(snapshot.projects.map(\.title), ["Inbox"])
        XCTAssertNotEqual(snapshot.projects.first?.id, inbox.id)
    }

    @MainActor
    func testProjectBoardViewModelNotifiesAfterSuccessfulMutations() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()

        _ = viewModel.createProject(title: "Launch Readiness")
        _ = viewModel.createTask(title: "Prepare release notes", status: .planned, priority: .high)
        viewModel.updateSelectedTask(
            title: "Prepare investor release notes",
            detail: "Focus on working CRUD and local-first data.",
            status: .inProgress,
            priority: .high,
            dueAt: "2026-06-21"
        )
        viewModel.deleteSelectedTask()
        viewModel.completeSelectedProject()
        viewModel.archiveSelectedProject()

        XCTAssertEqual(changeCount, 6)
        XCTAssertEqual(viewModel.selectedProject?.title, "Inbox")
    }

    @MainActor
    func testProjectBoardViewModelMovesSelectedTaskAndNotifies() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = viewModel.createTask(
            title: "Move card by context menu",
            detail: "This should keep metadata.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        )
        changeCount = 0

        viewModel.moveSelectedTask(to: .inProgress)

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(viewModel.selectedTaskID, task?.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .inProgress)
        XCTAssertEqual(viewModel.selectedTask?.title, "Move card by context menu")
        XCTAssertEqual(viewModel.selectedTask?.detail, "This should keep metadata.")
        XCTAssertEqual(viewModel.selectedTask?.priority, .high)
        XCTAssertEqual(viewModel.selectedTask?.dueAt, "2026-06-22")
    }

    @MainActor
    func testProjectBoardViewModelCanShowAndRestoreArchivedProjects() {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let archived = viewModel.createProject(title: "Restore Candidate")
        viewModel.archiveSelectedProject()

        XCTAssertFalse(viewModel.snapshot.projects.contains { $0.id == archived?.id })

        viewModel.setShowsArchivedProjects(true)
        viewModel.selectedProjectID = archived?.id

        XCTAssertTrue(viewModel.selectedProject?.isArchived == true)

        viewModel.restoreSelectedProject()

        XCTAssertTrue(viewModel.showsArchivedProjects)
        XCTAssertEqual(viewModel.selectedProject?.id, archived?.id)
        XCTAssertFalse(viewModel.selectedProject?.isArchived == true)
    }

    @MainActor
    func testProjectBoardViewModelDoesNotNotifyAfterFailedMutation() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()

        _ = viewModel.createTask(title: "   ")

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Task title is required.")
    }

    private func makeStore() throws -> SQLiteProjectBoardStore {
        try makeStoreBundle().board
    }

    private func makeStoreBundle() throws -> (
        board: SQLiteProjectBoardStore,
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            SQLiteProjectBoardStore(connection: connection),
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection)
        )
    }
}

private extension ProjectBoardProject {
    func column(_ status: ProjectTaskStatus) -> ProjectBoardColumn? {
        columns.first { $0.status == status }
    }
}
