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

    func testLoadSnapshotToleratesCorruptedProjectTagsBecauseBoardDoesNotUseTags() throws {
        let stores = try makeStoreBundle()
        let project = try stores.projects.create(title: "Launch Readiness", tags: ["alpha"])
        _ = try stores.tasks.create(
            title: "Keep board usable",
            projectID: project.id,
            status: "planned"
        )

        try stores.connection.execute("UPDATE projects SET tags_json = 'not-json' WHERE id = \(project.id);")

        XCTAssertThrowsError(try stores.projects.get(id: project.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidStringArray(column: "projects.tags_json"))
        }

        let snapshot = try stores.board.loadSnapshot(includeArchived: true)
        let loadedProject = try XCTUnwrap(snapshot.projects.first { $0.id == project.id })

        XCTAssertEqual(loadedProject.title, "Launch Readiness")
        XCTAssertEqual(loadedProject.column(.planned)?.tasks.map(\.title), ["Keep board usable"])

        let addedTask = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Add follow-up",
            status: .backlog
        ))
        let artifact = try stores.board.createProjectArtifact(
            projectID: project.id,
            expectedPath: "/tmp/solopm/release-plan.md"
        )

        XCTAssertEqual(addedTask.title, "Add follow-up")
        XCTAssertEqual(artifact.projectID, project.id)

        let renamed = try stores.board.updateProject(id: project.id, title: "Alpha Launch Readiness")
        let completed = try stores.board.completeProject(id: project.id)
        let restoresCompletedProject = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Restore active status",
            status: .planned
        ))
        let archived = try stores.board.archiveProject(id: project.id)
        let restored = try stores.board.restoreProject(id: project.id)

        XCTAssertEqual(renamed.title, "Alpha Launch Readiness")
        XCTAssertTrue(completed.isCompleted)
        XCTAssertEqual(restoresCompletedProject.title, "Restore active status")
        XCTAssertTrue(archived.isArchived)
        XCTAssertFalse(restored.isArchived)

        try stores.board.deleteProject(id: project.id)
        XCTAssertFalse(try stores.board.loadSnapshot(includeArchived: true).projects.contains { $0.id == project.id })
    }

    func testCreateProjectArtifactPersistsExpectedArtifactInSnapshot() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")

        let artifact = try stores.board.createProjectArtifact(
            projectID: project.id,
            expectedPath: "/tmp/solopm/release/notes.md"
        )

        XCTAssertEqual(artifact.projectID, project.id)
        XCTAssertNil(artifact.taskID)
        XCTAssertEqual(artifact.expectedPath, "/tmp/solopm/release/notes.md")
        XCTAssertEqual(artifact.createdState, .expected)
        XCTAssertEqual(try stores.artifacts.get(id: artifact.id).workspacePath, "/tmp/solopm/release")

        let loadedProject = try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id })
        XCTAssertEqual(loadedProject.artifacts, [artifact])
    }

    func testCreateProjectArtifactRejectsRelativePathWithoutMutating() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")

        XCTAssertThrowsError(
            try stores.board.createProjectArtifact(
                projectID: project.id,
                expectedPath: "release/notes.md"
            )
        ) { error in
            XCTAssertEqual(error as? ProjectBoardStoreError, .nonAbsoluteArtifactPath)
        }

        XCTAssertTrue(try stores.artifacts.list().isEmpty)
    }

    func testCreateProjectArtifactRejectsArchivedProjectWithoutMutating() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")
        _ = try stores.board.archiveProject(id: project.id)

        XCTAssertThrowsError(
            try stores.board.createProjectArtifact(
                projectID: project.id,
                expectedPath: "/tmp/solopm/release/notes.md"
            )
        ) { error in
            XCTAssertEqual(error as? ProjectBoardStoreError, .archivedProjectCannotAcceptArtifacts)
        }

        XCTAssertTrue(try stores.artifacts.list().isEmpty)
    }

    func testDeleteProjectArtifactRemovesLinkFromSnapshot() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")
        let artifact = try stores.board.createProjectArtifact(
            projectID: project.id,
            expectedPath: "/tmp/solopm/release/notes.md"
        )

        try stores.board.deleteProjectArtifact(id: artifact.id)

        let loadedProject = try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id })
        XCTAssertTrue(loadedProject.artifacts.isEmpty)
        XCTAssertThrowsError(try stores.artifacts.get(id: artifact.id)) { error in
            XCTAssertEqual(error as? ArtifactStoreError, .notFound(artifact.id))
        }
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

    func testUpdateTaskClearsDueDateFromPersistentDueQueries() throws {
        let stores = try makeStoreBundle()
        let projectID = try XCTUnwrap(stores.board.loadSnapshot().projects.first?.id)
        let task = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Clear persistent due date",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-22"
        ))

        _ = try stores.board.updateTask(id: task.id, ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Clear persistent due date",
            status: .planned,
            priority: .medium,
            dueAt: nil
        ))

        XCTAssertNil(try stores.tasks.get(id: task.id).dueAt)
        XCTAssertFalse(try stores.tasks.listDue(onOrBefore: "2026-12-31T23:59:59Z").contains { $0.id == task.id })
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

    func testCompletingProjectRollsBackProjectStatusWhenTaskCompletionFails() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Atomic Completion")
        let task = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Must remain planned",
            status: .planned,
            priority: .medium
        ))
        try stores.connection.execute(
            """
            CREATE TRIGGER fail_task_completion
            BEFORE UPDATE OF status ON tasks
            WHEN NEW.status = 'completed'
            BEGIN
                SELECT RAISE(ABORT, 'task completion failed');
            END;
            """
        )

        XCTAssertThrowsError(try stores.board.completeProject(id: project.id))

        XCTAssertEqual(try stores.projects.get(id: project.id).status, "active")
        XCTAssertEqual(try stores.tasks.get(id: task.id).status, "planned")
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
    func testProjectBoardViewModelCreatesProjectArtifactAndNotifies() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))
        changeCount = 0

        let artifact = try XCTUnwrap(viewModel.createProjectArtifact(
            expectedPath: "/tmp/solopm/release/notes.md",
            projectID: project.id
        ))

        XCTAssertEqual(changeCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedProjectID, project.id)
        XCTAssertEqual(viewModel.selectedProject?.artifacts, [artifact])
        XCTAssertEqual(viewModel.selectedProject?.artifacts.first?.createdState, .expected)
    }

    @MainActor
    func testProjectBoardViewModelRejectsRelativeArtifactPathWithoutNotifying() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))
        changeCount = 0

        let artifact = viewModel.createProjectArtifact(
            expectedPath: "release/notes.md",
            projectID: project.id
        )

        XCTAssertNil(artifact)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Use an absolute artifact path.")
        XCTAssertEqual(viewModel.selectedProject?.artifacts, [])
    }

    @MainActor
    func testProjectBoardViewModelDeletesProjectArtifactAndNotifies() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))
        let artifact = try XCTUnwrap(viewModel.createProjectArtifact(
            expectedPath: "/tmp/solopm/release/notes.md",
            projectID: project.id
        ))
        changeCount = 0

        XCTAssertTrue(viewModel.deleteProjectArtifact(id: artifact.id, projectID: project.id))

        XCTAssertEqual(changeCount, 1)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.selectedProjectID, project.id)
        XCTAssertEqual(viewModel.selectedProject?.artifacts, [])
    }

    @MainActor
    func testProjectBoardViewModelReportsMissingArtifactWithoutNotifying() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))
        changeCount = 0

        XCTAssertFalse(viewModel.deleteProjectArtifact(id: 99, projectID: project.id))

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Artifact link is no longer available.")
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
    func testProjectBoardViewModelQuickCapturesInboxTaskAndNotifies() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()

        let task = try XCTUnwrap(viewModel.createInboxTask(title: "Capture pricing follow-up"))

        XCTAssertEqual(task.title, "Capture pricing follow-up")
        XCTAssertEqual(task.status, .backlog)
        XCTAssertEqual(viewModel.inboxTasks.first?.id, task.id)
        XCTAssertEqual(viewModel.selectedProject?.title, "Inbox")
        XCTAssertEqual(viewModel.selectedTask?.title, "Capture pricing follow-up")
        XCTAssertEqual(changeCount, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelQuickCapturePersistsToSQLiteInbox() throws {
        let store = try makeStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()

        let task = try XCTUnwrap(viewModel.createInboxTask(title: "Persist menu bar capture"))

        let reloadedViewModel = ProjectBoardViewModel(store: store)
        reloadedViewModel.load()
        let reloadedTask = try XCTUnwrap(reloadedViewModel.inboxTasks.first { $0.id == task.id })
        XCTAssertEqual(reloadedTask.title, "Persist menu bar capture")
        XCTAssertEqual(reloadedTask.status, .backlog)
        XCTAssertEqual(reloadedViewModel.inboxProject?.title, "Inbox")
    }

    @MainActor
    func testProjectBoardViewModelFiltersInboxTasksByTriageSourceAndInterpretation() throws {
        let bundle = try makeStoreBundle()
        let captures = SQLiteInboxCaptureStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, inboxCaptureStore: captures)
        viewModel.load()

        let manual = try XCTUnwrap(viewModel.createInboxTask(title: "Manual capture"))
        let voice = try XCTUnwrap(viewModel.createInboxTask(title: "Voice without suggestion"))
        _ = try captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: voice.id,
            audioFilePath: "/Users/example/Library/Application Support/SoloPM/InboxAudio/voice-filter.m4a",
            durationSeconds: 5,
            transcript: "Call supplier",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded
        ))
        let suggested = try XCTUnwrap(viewModel.createInboxTask(title: "AI suggested capture"))
        _ = try captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: suggested.id,
            audioFilePath: "/Users/example/Library/Application Support/SoloPM/InboxAudio/ai-filter.m4a",
            durationSeconds: 8,
            transcript: "Prepare launch brief",
            interpretationSummary: "Likely task: prepare launch brief",
            memo: "Confidence: medium",
            transcriptionStatus: .succeeded
        ))
        let scheduled = try XCTUnwrap(viewModel.createInboxTask(
            title: "Scheduled manual capture",
            dueAt: "2026-06-22T09:00:00Z"
        ))

        XCTAssertEqual(viewModel.inboxTriageCount(for: .all), 4)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .voice), 2)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .aiSuggested), 1)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .manual), 2)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .unprocessed), 3)

        viewModel.setInboxTriageFilter(.voice)
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [suggested.id, voice.id])

        viewModel.setInboxTriageFilter(.aiSuggested)
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [suggested.id])

        viewModel.setInboxTriageFilter(.manual)
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [scheduled.id, manual.id])
    }

    @MainActor
    func testProjectBoardViewModelFallsBackSelectionWhenInboxFilterHidesCurrentTask() throws {
        let bundle = try makeStoreBundle()
        let captures = SQLiteInboxCaptureStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, inboxCaptureStore: captures)
        viewModel.load()

        let manual = try XCTUnwrap(viewModel.createInboxTask(title: "Manual capture"))
        let suggested = try XCTUnwrap(viewModel.createInboxTask(title: "AI suggested capture"))
        _ = try captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: suggested.id,
            audioFilePath: "/Users/example/Library/Application Support/SoloPM/InboxAudio/selection-filter.m4a",
            durationSeconds: 6,
            transcript: "Draft rollout checklist",
            interpretationSummary: "Likely task: draft rollout checklist",
            memo: nil,
            transcriptionStatus: .succeeded
        ))

        viewModel.selectedTaskID = manual.id
        viewModel.setInboxTriageFilter(.aiSuggested)

        XCTAssertEqual(viewModel.selectedTaskID, suggested.id)
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [suggested.id])
    }

    @MainActor
    func testProjectBoardViewModelClassifiesVoiceInboxItemWithoutAISuggestion() throws {
        let bundle = try makeStoreBundle()
        let captures = SQLiteInboxCaptureStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, inboxCaptureStore: captures)
        viewModel.load()

        let voice = try XCTUnwrap(viewModel.createInboxTask(title: "Voice without interpretation"))
        _ = try captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: voice.id,
            audioFilePath: "/Users/example/Library/Application Support/SoloPM/InboxAudio/no-ai-suggestion.m4a",
            durationSeconds: 7,
            transcript: "Follow up on launch QA",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded
        ))

        viewModel.setInboxTriageFilter(.voice)
        viewModel.selectedTaskID = voice.id
        XCTAssertNil(viewModel.selectedInboxCaptureRecords.first?.interpretationSummary)

        viewModel.markSelectedTaskAsTask()

        XCTAssertEqual(viewModel.inboxClassificationFeedback?.message, "Kept \"Voice without interpretation\" as a task.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelQuickCaptureRejectsBlankInboxTitleWithoutNotifying() {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()

        let task = viewModel.createInboxTask(title: "   ")

        XCTAssertNil(task)
        XCTAssertEqual(viewModel.errorMessage, "Task title is required.")
        XCTAssertEqual(changeCount, 0)
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
    func testProjectBoardViewModelTogglesWorkflowTaskCompletionWithRealMutation() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let captured = try XCTUnwrap(viewModel.createTask(
            title: "Finish today from workflow row",
            projectID: inboxID,
            status: .planned,
            dueAt: "2026-06-19T09:00:00Z"
        ))
        viewModel.selectedTaskID = nil
        let selectedProjectIDBeforeToggle = viewModel.selectedProjectID

        viewModel.toggleTaskCompletion(id: captured.id)

        XCTAssertEqual(viewModel.selectedProjectID, selectedProjectIDBeforeToggle)
        XCTAssertNil(viewModel.selectedTaskID)
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == captured.id }?.status, .done)
        XCTAssertFalse(viewModel.inboxTasks.contains { $0.id == captured.id })
        XCTAssertEqual(viewModel.completedInboxTaskCount, 1)
        XCTAssertTrue(viewModel.todayTasks(on: try isoDate("2026-06-19T10:00:00Z")).isEmpty)
        XCTAssertEqual(changeCount, 2)

        viewModel.setShowsCompletedWorkflowTasks(true)

        XCTAssertTrue(viewModel.inboxTasks.contains { $0.id == captured.id })
        XCTAssertTrue(viewModel.todayTasks(on: try isoDate("2026-06-19T10:00:00Z")).contains { $0.id == captured.id })

        viewModel.toggleTaskCompletion(id: captured.id)

        XCTAssertNil(viewModel.selectedTaskID)
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == captured.id }?.status, .planned)
        XCTAssertTrue(viewModel.todayTasks(on: try isoDate("2026-06-19T10:00:00Z")).contains { $0.id == captured.id })
        XCTAssertEqual(changeCount, 3)
    }

    @MainActor
    func testProjectBoardViewModelMovesDroppedInboxTaskIntoTargetProject() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let targetProject = try XCTUnwrap(viewModel.createProject(title: "Launch Plan"))
        let captured = try XCTUnwrap(viewModel.createTask(
            title: "Classify via drag",
            projectID: inboxID,
            status: .backlog
        ))

        XCTAssertTrue(viewModel.moveDroppedTasks(ids: [String(captured.id)], toProjectID: targetProject.id))

        let movedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == captured.id })
        XCTAssertEqual(movedTask.projectID, targetProject.id)
        XCTAssertEqual(movedTask.status, .backlog)
        XCTAssertEqual(viewModel.selectedProjectID, targetProject.id)
        XCTAssertEqual(viewModel.selectedTaskID, captured.id)
        XCTAssertFalse(viewModel.inboxTasks.contains { $0.id == captured.id })
        XCTAssertEqual(viewModel.integrationStatusMessage, "Moved task to project.")
    }

    @MainActor
    func testCompletedProjectsRemainVisibleWhenArchivedProjectsAreHidden() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Completed Initiative"))
        viewModel.selectedProjectID = project.id

        viewModel.completeSelectedProject()

        XCTAssertTrue(viewModel.snapshot.projects.contains { $0.id == project.id && $0.isCompleted })
        XCTAssertFalse(viewModel.showsArchivedProjects)
    }

    @MainActor
    func testProjectBoardViewModelInboxClassificationShowsFeedbackAdvancesSelectionAndUndo() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let first = try XCTUnwrap(viewModel.createTask(
            title: "First capture",
            projectID: inboxID,
            status: .backlog,
            priority: .medium
        ))
        let second = try XCTUnwrap(viewModel.createTask(
            title: "Second capture",
            projectID: inboxID,
            status: .backlog,
            priority: .high
        ))

        viewModel.selectedTaskID = second.id
        viewModel.convertSelectedTaskToProject()

        XCTAssertEqual(viewModel.inboxClassificationFeedback?.message, "Created project \"Second capture\".")
        XCTAssertEqual(viewModel.inboxClassificationFeedback?.systemImage, "folder.badge.plus")
        XCTAssertEqual(viewModel.inboxClassificationFeedback?.canUndo, true)
        XCTAssertEqual(viewModel.selectedTaskID, first.id)
        XCTAssertNotNil(viewModel.snapshot.projects.first { $0.title == "Second capture" })
        XCTAssertEqual(viewModel.inboxTasks.map(\.title), ["First capture"])

        viewModel.undoLastInboxClassification()

        XCTAssertNil(viewModel.inboxClassificationFeedback)
        XCTAssertEqual(viewModel.selectedTask?.title, "Second capture")
        XCTAssertEqual(viewModel.selectedTask?.projectID, inboxID)
        XCTAssertNil(viewModel.snapshot.projects.first { $0.title == "Second capture" && $0.id != inboxID })
        XCTAssertEqual(Set(viewModel.inboxTasks.map(\.title)), ["First capture", "Second capture"])
    }

    @MainActor
    func testProjectBoardViewModelInboxClassificationCanUndoScheduleMutation() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let first = try XCTUnwrap(viewModel.createTask(title: "First capture", projectID: inboxID))
        let second = try XCTUnwrap(viewModel.createTask(title: "Second capture", projectID: inboxID))

        viewModel.selectedTaskID = second.id
        viewModel.scheduleSelectedTaskForToday(referenceDate: try isoDate("2026-06-19T09:00:00Z"))

        XCTAssertEqual(viewModel.inboxClassificationFeedback?.message, "Scheduled \"Second capture\" for today.")
        XCTAssertEqual(viewModel.selectedTaskID, first.id)
        XCTAssertEqual(viewModel.inboxTasks.first { $0.id == second.id }?.dueAt, "2026-06-19T09:00:00Z")

        viewModel.undoLastInboxClassification()

        XCTAssertNil(viewModel.inboxClassificationFeedback)
        XCTAssertEqual(viewModel.selectedTaskID, second.id)
        XCTAssertNil(viewModel.selectedTask?.dueAt)
    }

    @MainActor
    func testSQLiteBoardStorePersistsInboxClassificationUndo() throws {
        let store = try makeStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let captured = try XCTUnwrap(viewModel.createTask(
            title: "Persisted capture",
            detail: "Keep this detail",
            projectID: inboxID,
            status: .backlog,
            priority: .high
        ))

        viewModel.selectedTaskID = captured.id
        viewModel.convertSelectedTaskToProject()

        XCTAssertNotNil(viewModel.snapshot.projects.first { $0.title == "Persisted capture" && $0.id != inboxID })
        XCTAssertTrue(viewModel.inboxTasks.isEmpty)

        viewModel.undoLastInboxClassification()

        let reloadedViewModel = ProjectBoardViewModel(store: store)
        reloadedViewModel.load()

        XCTAssertNil(reloadedViewModel.snapshot.projects.first { $0.title == "Persisted capture" && $0.id != inboxID })
        let restoredTask = try XCTUnwrap(reloadedViewModel.inboxTasks.first { $0.title == "Persisted capture" })
        XCTAssertEqual(restoredTask.detail, "Keep this detail")
        XCTAssertEqual(restoredTask.priority, .high)
        XCTAssertEqual(restoredTask.status, .backlog)
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

    @MainActor
    func testProjectBoardViewModelRedactsUnexpectedLoadErrorMessages() {
        let secret = "sk-" + "projectBoardSecret123"
        let viewModel = ProjectBoardViewModel(
            store: AlwaysFailingProjectBoardStore(
                error: ProjectBoardSecretError(message: "board load failed token=\(secret)&request_id=project-board-1")
            )
        )

        viewModel.load()

        XCTAssertEqual(
            viewModel.errorMessage,
            "board load failed token=[REDACTED_SECRET]&request_id=project-board-1"
        )
        XCTAssertFalse(viewModel.errorMessage?.contains(secret) ?? true)
    }

    @MainActor
    func testProjectBoardViewModelShowsRepairGuidanceForCorruptedLocalJSON() {
        let viewModel = ProjectBoardViewModel(
            store: AlwaysFailingProjectBoardStore(error: LocalStoreDecodingError.invalidStringArray(column: "projects.tags_json"))
        )

        viewModel.load()

        XCTAssertEqual(
            viewModel.errorMessage,
            "Local board data needs repair: projects.tags_json contains invalid list JSON. Restore from backup or repair the local database, then reopen SoloPM."
        )
        XCTAssertFalse(viewModel.isEmptyProjectStateVisible)
    }

    @MainActor
    func testProjectBoardViewModelShowsRepairGuidanceForUnsupportedStoredEnum() {
        let viewModel = ProjectBoardViewModel(
            store: AlwaysFailingProjectBoardStore(error: LocalStoreDecodingError.invalidEnum(column: "projects.status", value: "parked"))
        )

        viewModel.load()

        XCTAssertEqual(
            viewModel.errorMessage,
            "Local board data needs repair: projects.status contains unsupported value \"parked\". Restore from backup or repair the local database, then reopen SoloPM."
        )
        XCTAssertFalse(viewModel.isEmptyProjectStateVisible)
    }

    @MainActor
    func testProjectBoardViewModelTruncatesLongCorruptedValuesInRepairGuidance() {
        let oversizedValue = "\(String(repeating: "x", count: 90))\nnext line"
        let viewModel = ProjectBoardViewModel(
            store: AlwaysFailingProjectBoardStore(error: LocalStoreDecodingError.invalidDate(column: "tasks.due_at", value: oversizedValue))
        )

        viewModel.load()

        XCTAssertEqual(
            viewModel.errorMessage,
            "Local board data needs repair: tasks.due_at contains invalid date value \"\(String(repeating: "x", count: 80))...\". Restore from backup or repair the local database, then reopen SoloPM."
        )
    }

    private func makeStore() throws -> SQLiteProjectBoardStore {
        try makeStoreBundle().board
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }

    private func makeStoreBundle() throws -> (
        connection: SQLiteConnection,
        board: SQLiteProjectBoardStore,
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore,
        artifacts: SQLiteArtifactStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            connection,
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
    private let error: Error

    init(error: Error = ProjectBoardStoreTestError.unavailable) {
        self.error = error
    }

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

    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }

    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        throw error
    }

    func deleteProjectArtifact(id: Int64) throws {
        throw error
    }
}

private struct ProjectBoardSecretError: Error, CustomStringConvertible {
    var message: String

    var description: String {
        message
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

    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        throw ProjectBoardStoreTestError.unavailable
    }

    func deleteTask(id: Int64) throws {
        throw ProjectBoardStoreTestError.unavailable
    }

    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        throw ProjectBoardStoreTestError.unavailable
    }

    func deleteProjectArtifact(id: Int64) throws {
        throw ProjectBoardStoreTestError.unavailable
    }
}

private enum ProjectBoardStoreTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "Project board unavailable"
    }
}
