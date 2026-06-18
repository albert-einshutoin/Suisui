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

    func testLoadSnapshotIncludesProjectAndTaskArtifactsWithoutMockRows() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")
        let task = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Write release notes",
            status: .planned
        ))
        _ = try stores.artifacts.create(
            projectID: project.id,
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/release/checklist.md",
            createdState: .expected
        )
        _ = try stores.artifacts.create(
            taskID: task.id,
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/release/notes.md",
            createdState: .created,
            lastModifiedAt: try isoDate("2026-06-19T10:00:00Z")
        )
        _ = try stores.artifacts.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/unlinked.md",
            createdState: .created
        )

        let snapshot = try stores.board.loadSnapshot()
        let loadedProject = try XCTUnwrap(snapshot.projects.first { $0.id == project.id })

        XCTAssertEqual(loadedProject.artifacts.map(\.expectedPath), [
            "/tmp/solopm/release/checklist.md",
            "/tmp/solopm/release/notes.md"
        ])
        XCTAssertEqual(loadedProject.artifacts.map(\.createdState), [.expected, .created])
        XCTAssertEqual(loadedProject.artifacts.last?.taskID, task.id)
    }

    func testMoveTaskAssignsUnassignedPersistentTaskToInbox() throws {
        let stores = try makeStoreBundle()
        let orphan = try stores.tasks.create(title: "Move loose task", projectID: nil, status: "planned")
        let snapshot = try stores.board.loadSnapshot()
        let inbox = try XCTUnwrap(snapshot.projects.first { $0.title == "Inbox" })

        let moved = try stores.board.moveTask(id: orphan.id, to: .inProgress)

        XCTAssertEqual(moved.projectID, inbox.id)
        XCTAssertEqual(moved.status, .inProgress)
        XCTAssertEqual(try stores.tasks.get(id: orphan.id).projectID, inbox.id)
    }

    func testLoadSnapshotRejectsCorruptedTaskPriorityInsteadOfDefaultingToMedium() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let board = SQLiteProjectBoardStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let inbox = try XCTUnwrap(board.loadSnapshot().projects.first)
        let task = try tasks.create(title: "Review launch risk", projectID: inbox.id, priority: "high")

        try connection.execute("UPDATE tasks SET priority = 'urgent' WHERE id = \(task.id);")

        XCTAssertThrowsError(try board.loadSnapshot()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidEnum(column: "tasks.priority", value: "urgent"))
        }
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

    func testSQLiteBoardStoreRollsBackBulkTaskMoveWhenAnyTaskFails() throws {
        let store = try makeStore()
        let projectID = try XCTUnwrap(store.loadSnapshot().projects.first?.id)
        let firstTask = try store.createTask(ProjectBoardTaskDraft(projectID: projectID, title: "First card", status: .planned))
        let secondTask = try store.createTask(ProjectBoardTaskDraft(projectID: projectID, title: "Second card", status: .planned))

        XCTAssertThrowsError(try store.moveTasks(ids: [firstTask.id, 999_999, secondTask.id], to: .inProgress))

        let snapshot = try store.loadSnapshot()
        let project = try XCTUnwrap(snapshot.projects.first)

        XCTAssertEqual(Set(project.column(.planned)?.tasks.map(\.id) ?? []), Set([firstTask.id, secondTask.id]))
        XCTAssertEqual(project.column(.inProgress)?.tasks, [])
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

    func testDeleteProjectRemovesProjectAndTasksFromPersistentBoard() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Remove Candidate")
        let task = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Remove child task",
            status: .planned,
            priority: .medium
        ))

        try stores.board.deleteProject(id: project.id)

        let snapshot = try stores.board.loadSnapshot()

        XCTAssertFalse(snapshot.projects.contains { $0.id == project.id })
        XCTAssertFalse(snapshot.projects.flatMap(\.tasks).contains { $0.id == task.id })
        XCTAssertThrowsError(try stores.projects.get(id: project.id))
        XCTAssertThrowsError(try stores.tasks.get(id: task.id))
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
        viewModel.deleteSelectedProject()

        XCTAssertEqual(changeCount, 7)
        XCTAssertEqual(viewModel.selectedProject?.title, "Inbox")
    }

    @MainActor
    func testProjectBoardViewModelDeletesSelectedProjectAndNotifies() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let project = viewModel.createProject(title: "Remove Candidate")
        _ = viewModel.createTask(title: "Remove child task", status: .planned)
        changeCount = 0

        viewModel.deleteSelectedProject()

        XCTAssertEqual(changeCount, 1)
        XCTAssertFalse(viewModel.snapshot.projects.contains { $0.id == project?.id })
        XCTAssertFalse(viewModel.snapshot.projects.flatMap(\.tasks).contains { $0.title == "Remove child task" })
        XCTAssertNil(viewModel.selectedTaskID)
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
    func testProjectBoardViewModelRejectsInvalidDroppedTaskIDsWithoutPartialMove() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = viewModel.createTask(title: "Drag from board", status: .planned)
        guard let task else {
            XCTFail("Expected task creation to succeed before testing dropped payload validation.")
            return
        }
        changeCount = 0

        let didMove = viewModel.moveDroppedTasks(ids: [String(task.id), "invalid-id"], to: .inProgress)

        XCTAssertFalse(didMove)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Could not move task: invalid drag payload.")
        XCTAssertEqual(viewModel.selectedTask?.status, .planned)
    }

    @MainActor
    func testProjectBoardViewModelMovesDroppedTaskAndNotifiesOnce() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = viewModel.createTask(title: "Drop on board", status: .planned)
        guard let task else {
            XCTFail("Expected task creation to succeed before testing dropped payload movement.")
            return
        }
        changeCount = 0

        let didMove = viewModel.moveDroppedTasks(ids: [String(task.id)], to: .inProgress)

        XCTAssertTrue(didMove)
        XCTAssertEqual(changeCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedTaskID, task.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .inProgress)
    }

    @MainActor
    func testProjectBoardViewModelMovesTypedDroppedTaskIDsAndNotifiesOnce() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = viewModel.createTask(title: "Drop typed task payload", status: .planned)
        guard let task else {
            XCTFail("Expected task creation to succeed before testing typed dropped payload movement.")
            return
        }
        changeCount = 0

        let didMove = viewModel.moveDroppedTasks(ids: [task.id], to: .blocked)

        XCTAssertTrue(didMove)
        XCTAssertEqual(changeCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedTaskID, task.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .blocked)
    }

    @MainActor
    func testProjectBoardViewModelRollsBackMultiTaskDropWhenStoreFailsMidMove() {
        var changeCount = 0
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(
            store: store,
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let taskIDs = store.snapshot.projects.flatMap(\.tasks).map(\.id)

        let didMove = viewModel.moveDroppedTasks(ids: taskIDs, to: .inProgress)

        XCTAssertFalse(didMove)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Project board unavailable")

        viewModel.load()

        XCTAssertEqual(viewModel.snapshot.projects.first?.column(.planned)?.tasks.map(\.id), taskIDs)
        XCTAssertEqual(viewModel.snapshot.projects.first?.column(.inProgress)?.tasks, [])
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
    func testProjectBoardViewModelBuildsInboxAndTodayWorkflowTasksFromLiveSnapshot() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.snapshot.projects.first?.id)
        _ = viewModel.createTask(title: "Triage captured note", projectID: inboxID, status: .backlog)
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Fix overdue blocker",
            projectID: launch.id,
            status: .inProgress,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Ship today update",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Completed today task",
            projectID: launch.id,
            status: .done,
            dueAt: "2026-06-19T10:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Future follow-up",
            projectID: launch.id,
            status: .planned,
            dueAt: "2026-06-20T12:00:00Z"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let today = viewModel.todayTasks(
            on: try isoDate("2026-06-19T13:00:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(viewModel.inboxTasks.map(\.title), ["Triage captured note"])
        XCTAssertEqual(today.map(\.title), ["Fix overdue blocker", "Ship today update"])
        XCTAssertEqual(viewModel.projectTitle(for: try XCTUnwrap(today.first)), "Launch")
    }

    @MainActor
    func testProjectBoardViewModelBuildsDeterministicTodayPlanWithTimeBlocks() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Fix overdue blocker",
            projectID: launch.id,
            status: .inProgress,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Ship today update",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Low priority cleanup",
            projectID: launch.id,
            status: .planned,
            priority: .low,
            dueAt: "2026-06-19T15:00:00Z"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let plan = viewModel.todayPlan(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(plan.tasks.map(\.title), ["Fix overdue blocker", "Ship today update", "Low priority cleanup"])
        XCTAssertEqual(plan.overdueCount, 1)
        XCTAssertEqual(plan.dueTodayCount, 2)
        XCTAssertEqual(plan.recommendedTask?.title, "Fix overdue blocker")
        XCTAssertEqual(plan.recommendationReason, "Overdue high-priority work should be cleared first.")
        XCTAssertEqual(plan.timeBlocks.map(\.label), ["09:00-09:30", "09:30-10:00", "10:00-10:30"])
        XCTAssertEqual(plan.timeBlocks.map(\.task.title), ["Fix overdue blocker", "Ship today update", "Low priority cleanup"])
    }

    @MainActor
    func testProjectBoardViewModelClassifiesInboxTasksWithRealMutations() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.snapshot.projects.first?.id)
        let captured = try XCTUnwrap(viewModel.createTask(
            title: "Turn idea into project",
            projectID: inboxID,
            status: .backlog,
            priority: .high
        ))

        viewModel.selectedTaskID = captured.id
        viewModel.convertSelectedTaskToProject()

        let project = try XCTUnwrap(viewModel.snapshot.projects.first { $0.title == "Turn idea into project" })
        XCTAssertEqual(viewModel.selectedTask?.projectID, project.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .planned)

        viewModel.scheduleSelectedTaskForToday(referenceDate: try isoDate("2026-06-19T09:00:00Z"))
        XCTAssertEqual(viewModel.selectedTask?.dueAt, "2026-06-19T09:00:00Z")

        viewModel.deferSelectedTaskForLater()
        XCTAssertEqual(viewModel.selectedTask?.status, .backlog)
        XCTAssertNil(viewModel.selectedTask?.dueAt)
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

    @MainActor
    func testProjectBoardViewModelDoesNotShowEmptyProjectStateWhenLoadFails() {
        let viewModel = ProjectBoardViewModel(store: AlwaysFailingProjectBoardStore())

        viewModel.load()

        XCTAssertEqual(viewModel.errorMessage, "Project board unavailable")
        XCTAssertFalse(viewModel.isEmptyProjectStateVisible)
    }

    private func makeStore() throws -> SQLiteProjectBoardStore {
        try makeStoreBundle().board
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }

    private func makeStoreBundle() throws -> (
        board: SQLiteProjectBoardStore,
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore,
        artifacts: SQLiteArtifactStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            SQLiteProjectBoardStore(connection: connection),
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteArtifactStore(connection: connection)
        )
    }
}

private extension ProjectBoardProject {
    func column(_ status: ProjectTaskStatus) -> ProjectBoardColumn? {
        columns.first { $0.status == status }
    }
}

private struct AlwaysFailingProjectBoardStore: ProjectBoardStore {
    private var error: Error { ProjectBoardStoreTestError.unavailable }

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        throw error
    }

    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        throw error
    }

    func createProject(title: String) throws -> ProjectBoardProject {
        throw error
    }

    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        throw error
    }

    func completeProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func archiveProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func restoreProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func deleteProject(id: Int64) throws {
        throw error
    }

    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        throw error
    }

    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }
}

private final class PartiallyFailingBulkMoveProjectBoardStore: ProjectBoardStore, @unchecked Sendable {
    private var currentSnapshot: ProjectBoardSnapshot

    init() {
        let plannedTasks = [
            ProjectBoardTask(
                id: 1,
                projectID: 1,
                title: "First dropped card",
                detail: "",
                status: .planned,
                priority: .medium,
                dueAt: nil
            ),
            ProjectBoardTask(
                id: 2,
                projectID: 1,
                title: "Second dropped card",
                detail: "",
                status: .planned,
                priority: .medium,
                dueAt: nil
            )
        ]
        currentSnapshot = ProjectBoardSnapshot(projects: [
            ProjectBoardProject(
                id: 1,
                title: "Inbox",
                status: "active",
                subtitle: "2 open / 2 total",
                columns: ProjectTaskStatus.allCases.map { status in
                    ProjectBoardColumn(status: status, tasks: status == .planned ? plannedTasks : [])
                }
            )
        ])
    }

    var snapshot: ProjectBoardSnapshot {
        currentSnapshot
    }

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        currentSnapshot
    }

    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
        currentSnapshot
    }

    func createProject(title: String) throws -> ProjectBoardProject {
        throw ProjectBoardStoreTestError.unavailable
    }

    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        throw ProjectBoardStoreTestError.unavailable
    }

    func completeProject(id: Int64) throws -> ProjectBoardProject {
        throw ProjectBoardStoreTestError.unavailable
    }

    func archiveProject(id: Int64) throws -> ProjectBoardProject {
        throw ProjectBoardStoreTestError.unavailable
    }

    func restoreProject(id: Int64) throws -> ProjectBoardProject {
        throw ProjectBoardStoreTestError.unavailable
    }

    func deleteProject(id: Int64) throws {
        throw ProjectBoardStoreTestError.unavailable
    }

    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw ProjectBoardStoreTestError.unavailable
    }

    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw ProjectBoardStoreTestError.unavailable
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        guard id == 1 else {
            throw ProjectBoardStoreTestError.unavailable
        }

        guard let projectIndex = currentSnapshot.projects.firstIndex(where: { $0.id == 1 }),
              let task = currentSnapshot.projects[projectIndex].tasks.first(where: { $0.id == id }) else {
            throw ProjectBoardStoreTestError.unavailable
        }
        let movedTask = ProjectBoardTask(
            id: task.id,
            projectID: task.projectID,
            title: task.title,
            detail: task.detail,
            status: status,
            priority: task.priority,
            dueAt: task.dueAt
        )
        for columnIndex in currentSnapshot.projects[projectIndex].columns.indices {
            currentSnapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll { $0.id == id }
        }
        if let targetColumnIndex = currentSnapshot.projects[projectIndex].columns.firstIndex(where: { $0.status == status }) {
            currentSnapshot.projects[projectIndex].columns[targetColumnIndex].tasks.insert(movedTask, at: 0)
        }
        return movedTask
    }

    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        let originalSnapshot = currentSnapshot
        do {
            return try ids.map { try moveTask(id: $0, to: status) }
        } catch {
            currentSnapshot = originalSnapshot
            throw error
        }
    }

    func deleteTask(id: Int64) throws {
        throw ProjectBoardStoreTestError.unavailable
    }
}

private enum ProjectBoardStoreTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "Project board unavailable"
    }
}
