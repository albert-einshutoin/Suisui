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

    func testTaskCompletionPersistsCompletedAtMigrationAndSnapshot() throws {
        let stores = try makeStoreBundle()
        let columns = try stores.connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
        let projectID = try XCTUnwrap(stores.board.loadSnapshot().projects.first?.id)
        let task = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Ship Done analytics",
            status: .planned
        ))

        _ = try stores.board.moveTask(id: task.id, to: .done)

        let completedTask = try XCTUnwrap(stores.board.loadSnapshot().projects.first?.column(.done)?.tasks.first)
        XCTAssertTrue(columns.contains("completed_at"))
        XCTAssertNotNil(completedTask.completedAt)
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

    func testLoadSnapshotShowsDanglingProjectTasksInInboxWithoutRepairingAutomatically() throws {
        let stores = try makeStoreBundle()
        _ = try stores.tasks.create(
            title: "Recover dangling task",
            projectID: 99_999,
            status: "planned"
        )

        let snapshot = try stores.board.loadSnapshot()
        let inbox = try XCTUnwrap(snapshot.projects.first { $0.title == "Inbox" })

        XCTAssertEqual(inbox.column(.planned)?.tasks.map(\.title), ["Recover dangling task"])
        XCTAssertEqual(inbox.subtitle, "1 open / 1 total")
        XCTAssertEqual(try stores.tasks.listAll().first?.projectID, 99_999)
    }

    func testLoadSnapshotAuditsDanglingProjectRepairCandidateWithoutRawContent() throws {
        let stores = try makeStoreBundle()
        let logger = InMemoryAuditLogger()
        let board = SQLiteProjectBoardStore(connection: stores.connection, auditLogger: logger)
        let task = try stores.tasks.create(
            title: "Recover dangling task",
            projectID: 99_999,
            status: "planned"
        )

        _ = try board.loadSnapshot()

        let event = try XCTUnwrap(logger.recordedEvents.first)
        XCTAssertEqual(event.category, "persistence")
        XCTAssertEqual(event.action, "project_board.repair_candidate")
        XCTAssertEqual(event.status, .skipped)
        XCTAssertEqual(event.metadata["record_type"], "task")
        XCTAssertEqual(event.metadata["record_id"], "\(task.id)")
        XCTAssertEqual(event.metadata["column"], "tasks.project_id")
        XCTAssertEqual(event.metadata["reason"], "dangling_project_reference")
        XCTAssertFalse(event.metadata.values.contains { $0.contains("Recover dangling task") })
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
        let completedTasks = try XCTUnwrap(stores.board.loadSnapshot(includeArchived: true).projects.first { $0.id == project.id }?.column(.done)?.tasks)
        let restoresCompletedProject = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Restore active status",
            status: .planned
        ))
        let archived = try stores.board.archiveProject(id: project.id)
        let restored = try stores.board.restoreProject(id: project.id)

        XCTAssertEqual(renamed.title, "Alpha Launch Readiness")
        XCTAssertTrue(completed.isCompleted)
        XCTAssertTrue(completedTasks.allSatisfy { $0.completedAt != nil })
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

    func testProjectWorkspacePathCanBeAssignedAndCleared() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")
        let bookmarkData = Data("local-bookmark".utf8)

        let assigned = try stores.board.setProjectWorkspacePath(
            id: project.id,
            path: "/tmp/solopm-launch",
            bookmarkData: bookmarkData
        )

        XCTAssertTrue(assigned.hasWorkspaceDirectory)
        XCTAssertEqual(assigned.workspaceDisplayName, "solopm-launch")
        XCTAssertEqual(try stores.projects.get(id: project.id).workspacePath, "/tmp/solopm-launch")
        XCTAssertEqual(try stores.projects.get(id: project.id).workspaceBookmarkData, bookmarkData)
        let loadedProject = try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id })
        XCTAssertTrue(loadedProject.hasWorkspaceDirectory)
        XCTAssertEqual(loadedProject.workspaceDisplayName, "solopm-launch")
        XCTAssertNotEqual(loadedProject.workspaceDisplayName, "/tmp/solopm-launch")

        let cleared = try stores.board.setProjectWorkspacePath(id: project.id, path: nil)

        XCTAssertFalse(cleared.hasWorkspaceDirectory)
        XCTAssertNil(cleared.workspaceDisplayName)
        XCTAssertNil(try stores.projects.get(id: project.id).workspacePath)
        XCTAssertNil(try stores.projects.get(id: project.id).workspaceBookmarkData)
        XCTAssertFalse(try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id }).hasWorkspaceDirectory)
    }

    @MainActor
    func testProjectBoardViewModelAssignsProjectWorkspacePathWithoutChangingTasks() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))
        let task = try XCTUnwrap(viewModel.createTask(title: "Keep task", projectID: project.id))

        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/solopm-launch",
            bookmarkData: Data("local-bookmark".utf8),
            projectID: project.id
        ))

        let loadedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        XCTAssertTrue(loadedProject.hasWorkspaceDirectory)
        XCTAssertEqual(loadedProject.workspaceDisplayName, "solopm-launch")
        XCTAssertNotEqual(loadedProject.workspaceDisplayName, "/tmp/solopm-launch")
        XCTAssertEqual(loadedProject.tasks.map(\.id), [task.id])

        XCTAssertTrue(viewModel.clearProjectWorkspacePath(projectID: project.id))
        XCTAssertFalse(try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id }).hasWorkspaceDirectory)
    }

    @MainActor
    func testProjectBoardViewModelRejectsWorkspacePathWithoutBookmark() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))

        XCTAssertFalse(viewModel.assignProjectWorkspacePath("/tmp/solopm-launch", projectID: project.id))
        XCTAssertEqual(viewModel.errorMessage, "Project directory permission could not be saved. Choose the directory again.")
        XCTAssertNil(try stores.projects.get(id: project.id).workspacePath)
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

    func testProjectMilestoneCRUDPersistsToSnapshot() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")

        let milestone = try stores.board.createProjectMilestone(
            projectID: project.id,
            title: "Public beta",
            dueAt: "2026-07-01"
        )
        let updated = try stores.board.updateProjectMilestone(
            id: milestone.id,
            title: "Public beta launch",
            dueAt: "2026-07-03",
            isCompleted: true
        )

        XCTAssertEqual(updated.title, "Public beta launch")
        XCTAssertEqual(updated.dueAt, "2026-07-03")
        XCTAssertTrue(updated.isCompleted)
        let stored = try stores.milestones.get(id: milestone.id)
        XCTAssertEqual(stored.title, updated.title)
        XCTAssertEqual(stored.dueAt, updated.dueAt)
        XCTAssertEqual(stored.isCompleted, updated.isCompleted)
        XCTAssertEqual(
            try stores.board.loadSnapshot().projects.first { $0.id == project.id }?.milestones,
            [updated]
        )

        try stores.board.deleteProjectMilestone(id: milestone.id)

        XCTAssertTrue(try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id }).milestones.isEmpty)
    }

    func testProjectSnapshotIncludesMilestoneSummarySeparateFromTasks() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Milestone Plan")
        _ = try stores.board.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Implement task",
            status: .planned,
            dueAt: "2026-07-02"
        ))
        _ = try stores.board.createProjectMilestone(
            projectID: project.id,
            title: "Design freeze",
            dueAt: "2026-06-30"
        )

        let loaded = try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id })

        XCTAssertEqual(loaded.milestones.map(\.title), ["Design freeze"])
        XCTAssertEqual(loaded.tasks.map(\.title), ["Implement task"])
        XCTAssertEqual(loaded.milestoneSummary, "0/1 milestones complete")
    }

    func testProjectMilestoneRejectsBlankTitleAndRequiresExistingProject() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Milestone Boundaries")

        XCTAssertThrowsError(try stores.board.createProjectMilestone(
            projectID: project.id,
            title: "   ",
            dueAt: "2026-07-01"
        )) { error in
            XCTAssertEqual(error as? ProjectBoardStoreError, .emptyTitle)
        }

        XCTAssertThrowsError(try stores.board.createProjectMilestone(
            projectID: 99_999,
            title: "Missing project milestone",
            dueAt: nil
        ))

        XCTAssertTrue(try stores.board.loadSnapshot().projects.first { $0.id == project.id }?.milestones.isEmpty == true)
    }

    func testDeletingProjectCascadesProjectMilestones() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Cascade Milestones")
        let milestone = try stores.board.createProjectMilestone(
            projectID: project.id,
            title: "Release candidate",
            dueAt: "2026-07-10"
        )

        try stores.board.deleteProject(id: project.id)

        XCTAssertThrowsError(try stores.milestones.get(id: milestone.id)) { error in
            XCTAssertEqual(error as? ProjectMilestoneStoreError, .notFound(milestone.id))
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

    func testLoadSnapshotSkipsCorruptedTaskPriorityWithoutMakingBoardUnavailable() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let board = SQLiteProjectBoardStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let inbox = try XCTUnwrap(board.loadSnapshot().projects.first)
        let task = try tasks.create(title: "Review launch risk", projectID: inbox.id, priority: "high")
        _ = try tasks.create(title: "Keep board usable", projectID: inbox.id, priority: "medium")

        try connection.execute("UPDATE tasks SET priority = 'urgent' WHERE id = \(task.id);")

        let snapshot = try board.loadSnapshot()
        let loadedInbox = try XCTUnwrap(snapshot.projects.first { $0.id == inbox.id })

        XCTAssertEqual(loadedInbox.tasks.map(\.title), ["Keep board usable"])
        XCTAssertEqual(loadedInbox.subtitle, "1 open / 1 total")
    }

    func testLoadSnapshotAuditsSkippedCorruptedTaskWithoutRawValue() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let logger = InMemoryAuditLogger()
        let board = SQLiteProjectBoardStore(connection: connection, auditLogger: logger)
        let tasks = SQLiteTaskStore(connection: connection)
        let inbox = try XCTUnwrap(board.loadSnapshot().projects.first)
        let task = try tasks.create(title: "Review launch risk", projectID: inbox.id, priority: "high")
        _ = try tasks.create(title: "Keep board usable", projectID: inbox.id, priority: "medium")

        try connection.execute("UPDATE tasks SET priority = 'urgent' WHERE id = \(task.id);")
        _ = try board.loadSnapshot()

        let event = try XCTUnwrap(logger.recordedEvents.first)
        XCTAssertEqual(event.category, "persistence")
        XCTAssertEqual(event.action, "project_board.record_skipped")
        XCTAssertEqual(event.status, .skipped)
        XCTAssertEqual(event.metadata["record_type"], "task")
        XCTAssertEqual(event.metadata["record_id"], "\(task.id)")
        XCTAssertEqual(event.metadata["column"], "tasks.priority")
        XCTAssertEqual(event.metadata["reason"], "unsupported_priority")
        XCTAssertFalse(event.metadata.values.contains { $0.contains("urgent") })
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
    func testProjectBoardViewModelRequiresReviewBeforeApprovedTaskAutomationExecution() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Draft release notes",
            detail: "Use the selected docs to prepare a reviewed artifact.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        changeCount = 0

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.selectedTask?.status, .planned)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Review the automation plan before running it.")
        XCTAssertNil(viewModel.taskAutomationReviewDecision)

        viewModel.prepareAutomationReviewForSelectedTask()
        let decision = try XCTUnwrap(viewModel.taskAutomationReviewDecision)

        XCTAssertEqual(decision.status, .readyForReview)
        XCTAssertEqual(decision.selectedTasks.map(\.id), [task.id])
        XCTAssertTrue(decision.requiresUserApproval)
        XCTAssertFalse(decision.allowsDirectExecution)

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(viewModel.selectedTask?.status, .inProgress)
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
    }

    @MainActor
    func testProjectBoardViewModelRecordsTaskContentExecutionWhenApprovedAutomationRuns() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Run release note task",
            detail: "Use docs/release/checklist.md to draft the operator note.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        let executedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        XCTAssertEqual(executedTask.status, .inProgress)
        XCTAssertTrue(executedTask.detail.contains("Use docs/release/checklist.md to draft the operator note."))
        XCTAssertTrue(executedTask.detail.contains("SoloPM approved automation execution"))
        XCTAssertTrue(executedTask.detail.contains("Run approved plan"))
        XCTAssertEqual(viewModel.todayCommandFeedback, "Executed approved automation for \"Run release note task\".")
    }

    @MainActor
    func testProjectBoardViewModelRecordsRedactedApprovedAutomationExecutionReceipt() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Run provider handoff token=secret-title",
            detail: "Create docs from sk-proj-live-secret and api_key=do-not-leak.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        let receipt = try XCTUnwrap(viewModel.lastApprovedAutomationExecutionReceipt)
        XCTAssertEqual(receipt.taskID, task.id)
        XCTAssertEqual(receipt.projectID, task.projectID)
        XCTAssertEqual(receipt.statusBefore, .planned)
        XCTAssertEqual(receipt.statusAfter, .inProgress)
        XCTAssertEqual(receipt.priority, .high)
        XCTAssertEqual(receipt.dueAt, "2026-06-22")
        XCTAssertEqual(receipt.reviewReason, "Selected task is ready for review-only automation.")
        XCTAssertTrue(receipt.redactedTaskTitle.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(receipt.redactedTaskDetail.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(receipt.redactedTaskTitle.contains("secret-title"))
        XCTAssertFalse(receipt.redactedTaskDetail.contains("sk-proj-live-secret"))
        XCTAssertFalse(receipt.redactedTaskDetail.contains("do-not-leak"))
    }

    @MainActor
    func testProjectBoardViewModelLoadsGlobalExecutionReceiptHistory() throws {
        let receiptStore = InMemoryExecutionReceiptStore(receipts: [
            ExecutionReceipt(
                id: "receipt-board-history",
                runID: "run-board-history",
                createdAt: Date(timeIntervalSince1970: 100),
                finishedAt: Date(timeIntervalSince1970: 120),
                status: .succeeded,
                inputPreview: "Raw prompt token=history-secret",
                outputSummary: "Created visible audit row",
                primaryToolName: ActionTool.taskCreate.rawValue,
                usage: ExecutionReceiptUsage(inputTokens: 4, outputTokens: 6, estimatedCostCents: 0.5, currencyCode: "USD"),
                references: [ExecutionReceiptReference(kind: .task, id: "1", label: "History task")],
                visibleSurfaces: [.auditLog]
            )
        ])
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        let row = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot.rows.first)
        XCTAssertTrue(row.id.hasPrefix("receipt-"))
        XCTAssertEqual(row.id.count, "receipt-".count + 16)
        XCTAssertFalse(row.receiptIDLabel.contains("receipt-board-history"))
        XCTAssertEqual(row.statusLabel, "Succeeded")
        XCTAssertEqual(row.toolLabel, ActionTool.taskCreate.rawValue)
        XCTAssertEqual(row.outcomeSummary, "Created visible audit row")
        XCTAssertTrue(row.usageLabel.contains("10 tokens"))
        XCTAssertFalse(row.accessibilityValue.contains("history-secret"))
        XCTAssertNil(viewModel.executionReceiptHistorySnapshot.unavailableMessage)
    }

    @MainActor
    func testProjectBoardViewModelHidesNonAuditReceiptsFromDoneHistoryAndExport() throws {
        let receiptStore = InMemoryExecutionReceiptStore(receipts: [
            ExecutionReceipt(
                id: "receipt-audit-visible",
                runID: "run-audit-visible",
                createdAt: Date(timeIntervalSince1970: 100),
                finishedAt: Date(timeIntervalSince1970: 120),
                status: .succeeded,
                inputPreview: "Visible audit prompt",
                outputSummary: "Visible audit outcome",
                primaryToolName: ActionTool.taskUpdate.rawValue,
                visibleSurfaces: [.auditLog]
            ),
            ExecutionReceipt(
                id: "receipt-queue-hidden",
                runID: "run-queue-hidden",
                createdAt: Date(timeIntervalSince1970: 130),
                finishedAt: Date(timeIntervalSince1970: 140),
                status: .succeeded,
                inputPreview: "Queue-only prompt",
                outputSummary: "Queue-only hidden outcome",
                primaryToolName: ActionTool.taskCreate.rawValue,
                visibleSurfaces: [.assistantQueue]
            ),
            ExecutionReceipt(
                id: "receipt-surfaceless-hidden",
                runID: "run-surfaceless-hidden",
                createdAt: Date(timeIntervalSince1970: 150),
                finishedAt: Date(timeIntervalSince1970: 160),
                status: .succeeded,
                inputPreview: "Surface-less prompt",
                outputSummary: "Surface-less hidden outcome",
                primaryToolName: ActionTool.calendarCreateWorkBlock.rawValue
            )
        ])
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )

        viewModel.load()
        viewModel.prepareExecutionReceiptHistoryExport(exportedAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot.rows.map(\.outcomeSummary), ["Visible audit outcome"])
        let exportData = try XCTUnwrap(viewModel.executionReceiptHistoryExportData)
        let exportText = try XCTUnwrap(String(data: exportData, encoding: .utf8))
        XCTAssertTrue(exportText.contains("Visible audit outcome"))
        XCTAssertFalse(exportText.contains("Queue-only hidden outcome"))
        XCTAssertFalse(exportText.contains("Surface-less hidden outcome"))
        XCTAssertFalse(exportText.contains("receipt-queue-hidden"))
        XCTAssertFalse(exportText.contains("receipt-surfaceless-hidden"))
    }

    @MainActor
    func testProjectBoardViewModelFiltersAndExportsExecutionReceiptHistory() throws {
        let rawReceiptID = "receipt:https://docs.example.com/export?token=board-export-secret"
        let taskReferenceID = "task-board-export-secret"
        let receiptStore = InMemoryExecutionReceiptStore(receipts: [
            ExecutionReceipt(
                id: "receipt-unrelated-board-export",
                runID: "run-unrelated-board-export",
                createdAt: Date(timeIntervalSince1970: 90),
                finishedAt: Date(timeIntervalSince1970: 110),
                status: .failed,
                inputPreview: "Wrong prompt",
                outputSummary: "Calendar failed",
                primaryToolName: ActionTool.calendarCreateWorkBlock.rawValue,
                references: [ExecutionReceiptReference(kind: .calendarEvent, id: "event-board-export")],
                visibleSurfaces: [.auditLog]
            ),
            ExecutionReceipt(
                id: rawReceiptID,
                runID: "run-board-export",
                createdAt: Date(timeIntervalSince1970: 100),
                finishedAt: Date(timeIntervalSince1970: 120),
                status: .succeeded,
                inputPreview: "Raw prompt sk-proj-board-export-secret from /Users/alice/board-export.md",
                outputSummary: "Created board launch audit",
                primaryToolName: ActionTool.taskCreate.rawValue,
                usage: ExecutionReceiptUsage(inputTokens: 10, outputTokens: 5, estimatedCostCents: 1.2, currencyCode: "USD"),
                references: [
                    ExecutionReceiptReference(kind: .task, id: taskReferenceID, label: "Board launch token=board-reference-secret")
                ],
                sourceLinks: [
                    ExecutionReceiptSourceLink(kind: .document, title: "Board spec", url: "file:///Users/alice/board-export.md")
                ],
                visibleSurfaces: [.auditLog]
            )
        ])
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )

        viewModel.load()
        viewModel.setExecutionReceiptHistorySearchText("board launch")
        viewModel.setExecutionReceiptHistoryStatusFilter(.succeeded)
        viewModel.setExecutionReceiptHistoryReferenceKindFilter(.task)
        viewModel.prepareExecutionReceiptHistoryExport(exportedAt: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot.rows.map(\.toolLabel), [ActionTool.taskCreate.rawValue])
        XCTAssertEqual(viewModel.executionReceiptHistorySearchText, "board launch")
        XCTAssertEqual(viewModel.executionReceiptHistoryStatusFilter, .succeeded)
        XCTAssertEqual(viewModel.executionReceiptHistoryReferenceKindFilter, .task)
        XCTAssertTrue(viewModel.executionReceiptHistoryExportMessage?.contains("Prepared 1 redacted receipt export row") ?? false)

        let exportData = try XCTUnwrap(viewModel.executionReceiptHistoryExportData)
        let exportText = try XCTUnwrap(String(data: exportData, encoding: .utf8))
        XCTAssertTrue(exportText.contains("Created board launch audit"))
        XCTAssertTrue(exportText.contains(ActionTool.taskCreate.rawValue))
        XCTAssertFalse(exportText.contains(rawReceiptID))
        XCTAssertFalse(exportText.contains(taskReferenceID))
        XCTAssertFalse(exportText.contains("board-export-secret"))
        XCTAssertFalse(exportText.contains("board-reference-secret"))
        XCTAssertFalse(exportText.contains("file://"))
        XCTAssertFalse(exportText.contains("/Users/alice/board-export.md"))
        XCTAssertFalse(exportText.contains("Raw prompt"))

        viewModel.recordExecutionReceiptHistoryExportCompleted()
        XCTAssertNil(viewModel.executionReceiptHistoryExportData)
        XCTAssertEqual(viewModel.executionReceiptHistoryExportMessage, "Saved redacted receipt export JSON.")
    }

    @MainActor
    func testProjectBoardViewModelPersistsApprovedAutomationReceiptToGlobalHistory() throws {
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Launch token=approved-history-secret",
            detail: "Use sk-proj-approved-history-secret before drafting.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        let storedReceipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(storedReceipt.status, .succeeded)
        XCTAssertEqual(storedReceipt.primaryToolName, ActionTool.taskUpdate.rawValue)
        XCTAssertEqual(storedReceipt.visibleSurfaces, [.doneList, .taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(storedReceipt.inputPreview.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("approved-history-secret"))

        let row = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot.rows.first)
        let rowText = [
            row.id,
            row.toolLabel,
            row.outcomeSummary,
            row.referenceSummary,
            row.sourceSummary,
            row.receiptIDLabel,
            row.accessibilityValue
        ].joined(separator: " ")
        XCTAssertTrue(row.id.hasPrefix("receipt-"))
        XCTAssertEqual(row.status, .succeeded)
        XCTAssertEqual(row.toolLabel, ActionTool.taskUpdate.rawValue)
        XCTAssertTrue(row.outcomeSummary.contains("Moved task"))
        XCTAssertFalse(rowText.contains(storedReceipt.id))
        XCTAssertFalse(rowText.contains("approved-history-secret"))
        XCTAssertNil(viewModel.executionReceiptHistorySnapshot.unavailableMessage)
    }

    @MainActor
    func testProjectBoardViewModelPersistsDocumentDeliverableReceiptToGlobalAndScopedHistory() throws {
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Prepare release docs token=document-task-secret",
            detail: "Use sk-proj-document-task-secret before drafting.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        ))
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Prepare release notes and the pull request plan from selected docs.",
            documents: [
                ScopedAutomationDocument(
                    id: "phase14-token=document-source-id-secret",
                    title: "Phase14 release source token=document-source-title-secret",
                    scope: .appDocs,
                    redactedSummary: "Release notes and pull request plan use sk-proj-document-source-secret.",
                    inclusionReason: "Selected because token=document-source-reason-secret matched."
                )
            ]
        )

        _ = try viewModel.makeTaskAutomationPlanningRequest(
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 1,
                dailyLLMCallLimit: 3,
                lookaheadHours: 72
            ),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC",
            documentDeliverableDrafts: drafts
        )

        let storedReceipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(storedReceipt.status, .succeeded)
        XCTAssertEqual(storedReceipt.primaryToolName, "document.deliverable.prepare")
        XCTAssertEqual(storedReceipt.visibleSurfaces, [.taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(storedReceipt.references.contains(ExecutionReceiptReference(kind: .task, id: String(task.id), label: "Prepare release docs [REDACTED_SECRET]")))
        XCTAssertTrue(storedReceipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(task.projectID))))
        XCTAssertTrue(storedReceipt.references.contains { $0.kind == .document })
        XCTAssertTrue(storedReceipt.references.contains { $0.kind == .file })
        XCTAssertTrue(storedReceipt.inputPreview.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("document-task-secret"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("document-source-id-secret"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("document-source-title-secret"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("document-source-secret"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("document-source-reason-secret"))

        let globalRow = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot.rows.first)
        let taskRow = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.first)
        let projectRow = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot(forProjectID: task.projectID).rows.first)
        XCTAssertEqual(globalRow.toolLabel, "document.deliverable.prepare")
        XCTAssertEqual(taskRow.toolLabel, "document.deliverable.prepare")
        XCTAssertEqual(projectRow.toolLabel, "document.deliverable.prepare")
        XCTAssertTrue(globalRow.outcomeSummary.contains("No files were written"))
        XCTAssertTrue(globalRow.referenceSummary.contains("Document"))
        XCTAssertTrue(globalRow.sourceSummary.contains("Document"))

        viewModel.prepareExecutionReceiptHistoryExport()
        let exportData = try XCTUnwrap(viewModel.executionReceiptHistoryExportData)
        let exportText = String(decoding: exportData, as: UTF8.self)
        XCTAssertFalse(exportText.contains(storedReceipt.id))
        XCTAssertFalse(exportText.contains("document-task-secret"))
        XCTAssertFalse(exportText.contains("document-source-id-secret"))
        XCTAssertFalse(exportText.contains("document-source-title-secret"))
        XCTAssertFalse(exportText.contains("document-source-secret"))
        XCTAssertFalse(exportText.contains("document-source-reason-secret"))
        XCTAssertFalse(exportText.contains("sk-proj"))
        XCTAssertFalse(exportText.contains("file://"))
    }

    @MainActor
    func testProjectBoardViewModelLoadsTaskAndProjectScopedExecutionReceiptHistory() throws {
        let scopedReceipt = ExecutionReceipt(
            id: "receipt-task-project-history",
            runID: "run-task-project-history",
            createdAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 120),
            status: .succeeded,
            inputPreview: "Raw prompt token=scoped-history-secret",
            outputSummary: "Updated task and project audit row",
            primaryToolName: ActionTool.taskUpdate.rawValue,
            references: [
                ExecutionReceiptReference(kind: .task, id: "42", label: "Scoped task token=scoped-history-secret"),
                ExecutionReceiptReference(kind: .project, id: "7", label: "Scoped project")
            ],
            visibleSurfaces: [.taskDetail, .projectDetail]
        )
        let newerUnrelatedReceipts = (0..<120).map { index in
            ExecutionReceipt(
                id: "receipt-global-only-\(index)",
                runID: "run-global-only-\(index)",
                createdAt: Date(timeIntervalSince1970: 1_000 + TimeInterval(index)),
                finishedAt: Date(timeIntervalSince1970: 1_010 + TimeInterval(index)),
                status: .succeeded,
                inputPreview: "Global only",
                outputSummary: "Should only show globally",
                primaryToolName: "calendar.create",
                references: [ExecutionReceiptReference(kind: .task, id: "420")],
                visibleSurfaces: [.doneList]
            )
        }
        let receiptStore = InMemoryExecutionReceiptStore(receipts: [scopedReceipt] + newerUnrelatedReceipts + [
            ExecutionReceipt(
                id: "receipt-global-only",
                runID: "run-global-only",
                createdAt: Date(timeIntervalSince1970: 110),
                finishedAt: Date(timeIntervalSince1970: 130),
                status: .succeeded,
                inputPreview: "Global only",
                outputSummary: "Should only show globally",
                primaryToolName: "calendar.create",
                references: [ExecutionReceiptReference(kind: .task, id: "42")],
                visibleSurfaces: [.doneList]
            )
        ])
        let task = ProjectBoardTask(
            id: 42,
            projectID: 7,
            title: "Scoped history task",
            detail: "Inspect scoped receipt history.",
            status: .planned,
            priority: .medium,
            dueAt: nil
        )
        let project = ProjectBoardProject(
            id: 7,
            title: "Scoped history project",
            status: "active",
            subtitle: "1 open / 1 total",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: status == .planned ? [task] : [])
            }
        )
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [project])),
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        let taskSnapshot = viewModel.executionReceiptHistorySnapshot(forTaskID: 42)
        let projectSnapshot = viewModel.executionReceiptHistorySnapshot(forProjectID: 7)
        XCTAssertEqual(taskSnapshot.rows.map(\.toolLabel), [ActionTool.taskUpdate.rawValue])
        XCTAssertEqual(projectSnapshot.rows.map(\.toolLabel), [ActionTool.taskUpdate.rawValue])
        XCTAssertFalse(taskSnapshot.rows[0].accessibilityValue.contains("scoped-history-secret"))
        XCTAssertFalse(projectSnapshot.rows[0].accessibilityValue.contains("scoped-history-secret"))
    }

    @MainActor
    func testProjectBoardViewModelRejectsDoneAndBlockedTasksBeforeAutomationReview() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()

        _ = viewModel.createTask(title: "Already shipped", status: .done, priority: .high)
        viewModel.prepareAutomationReviewForSelectedTask()

        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Only open unblocked tasks can be reviewed for automation.")

        _ = viewModel.createTask(title: "Waiting on signing identity", status: .blocked, priority: .high)
        viewModel.prepareAutomationReviewForSelectedTask()

        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Only open unblocked tasks can be reviewed for automation.")
    }

    @MainActor
    func testProjectBoardViewModelStopsApprovedAutomationWhenReviewedTaskBecomesBlocked() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Prepare release machine plan",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()
        XCTAssertEqual(viewModel.taskAutomationReviewDecision?.selectedTasks.map(\.id), [task.id])

        viewModel.moveSelectedTask(to: .blocked)
        changeCount = 0

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.selectedTaskID, task.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .blocked)
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Task automation stopped because the task is blocked or complete.")
    }

    @MainActor
    func testProjectBoardViewModelRequiresFreshAutomationReviewAfterTaskContentChanges() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Draft launch notes",
            detail: "Use the initial document set.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()
        XCTAssertEqual(viewModel.taskAutomationReviewDecision?.selectedTasks.map(\.id), [task.id])

        viewModel.updateSelectedTask(
            title: "Draft launch notes",
            detail: "Use the revised document set.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        )
        changeCount = 0

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.selectedTaskID, task.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .planned)
        XCTAssertEqual(viewModel.selectedTask?.detail, "Use the revised document set.")
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Review the automation plan again because the task changed after review.")
    }

    @MainActor
    func testProjectBoardViewModelPreparesTaskAutomationReviewFromConfiguredTaskList() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "Low future", status: .planned, priority: .low, dueAt: "2026-06-24T08:00:00Z")
        _ = viewModel.createTask(title: "Done overdue", status: .done, priority: .high, dueAt: "2026-06-21T08:00:00Z")
        _ = viewModel.createTask(title: "High without due date", status: .planned, priority: .high)
        _ = viewModel.createTask(title: "Medium due today", status: .planned, priority: .medium, dueAt: "2026-06-22T18:00:00Z")
        _ = viewModel.createTask(title: "High overdue", status: .planned, priority: .high, dueAt: "2026-06-21T08:00:00Z")

        let decision = viewModel.prepareTaskAutomationReview(
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 3,
                dailyLLMCallLimit: 4,
                lookaheadHours: 48
            ),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .readyForReview)
        XCTAssertEqual(viewModel.taskAutomationReviewDecision?.selectedTasks.map(\.title), [
            "High overdue",
            "Medium due today",
            "High without due date"
        ])
        XCTAssertEqual(viewModel.taskAutomationReviewDecision?.llmCallBudgetRemaining, 4)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Prepared review-only automation for 3 tasks.")
        XCTAssertEqual(viewModel.selectedTask?.title, "High overdue")
    }

    @MainActor
    func testProjectBoardViewModelPreservesBatchReviewAndReceiptHistoryAcrossApprovedTaskExecution() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "Low future", status: .planned, priority: .low, dueAt: "2026-06-24T08:00:00Z")
        let first = try XCTUnwrap(viewModel.createTask(
            title: "High overdue token=secret-first",
            detail: "Use sk-proj-first-secret before drafting.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        ))
        let second = try XCTUnwrap(viewModel.createTask(
            title: "Medium due today",
            detail: "Prepare the second reviewed task.",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-22T18:00:00Z"
        ))

        let decision = viewModel.prepareTaskAutomationReview(
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 2,
                dailyLLMCallLimit: 4,
                lookaheadHours: 48
            ),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.selectedTasks.map(\.id), [first.id, second.id])
        XCTAssertEqual(viewModel.approvedAutomationExecutionReceipts, [])

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(viewModel.selectedTask?.id, first.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .inProgress)
        XCTAssertEqual(viewModel.taskAutomationReviewDecision?.selectedTasks.map(\.id), [second.id])
        XCTAssertEqual(viewModel.approvedAutomationExecutionReceipts.map(\.taskID), [first.id])
        XCTAssertEqual(viewModel.lastApprovedAutomationExecutionReceipt?.taskID, first.id)
        XCTAssertEqual(viewModel.approvedAutomationExecutionReceipts.first?.statusBefore, .planned)
        XCTAssertEqual(viewModel.approvedAutomationExecutionReceipts.first?.statusAfter, .inProgress)
        XCTAssertTrue(viewModel.approvedAutomationExecutionReceipts.first?.redactedTaskTitle.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(viewModel.approvedAutomationExecutionReceipts.first?.redactedTaskTitle.contains("secret-first") ?? true)
        XCTAssertFalse(viewModel.approvedAutomationExecutionReceipts.first?.redactedTaskDetail.contains("sk-proj-first-secret") ?? true)

        viewModel.selectedTaskID = second.id
        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(viewModel.selectedTask?.id, second.id)
        XCTAssertEqual(viewModel.selectedTask?.status, .inProgress)
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.approvedAutomationExecutionReceipts.map(\.taskID), [first.id, second.id])
        XCTAssertEqual(viewModel.lastApprovedAutomationExecutionReceipt?.taskID, second.id)
    }

    @MainActor
    func testProjectBoardViewModelBuildsTaskAutomationPlanningRequestWithDocumentDeliverables() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "Low future", status: .planned, priority: .low, dueAt: "2026-06-24T08:00:00Z")
        _ = viewModel.createTask(
            title: "High release note task",
            detail: "Use selected release docs before writing anything. sk-proj-task-secret123",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        )
        let documents = [
            ScopedAutomationDocument(
                id: "phase14",
                title: "Phase14 release notes and PR plan",
                scope: .appDocs,
                redactedSummary: "Release notes, pull request plan, implementation risk, and sk-proj-doc-secret123.",
                inclusionReason: "Selected by the user for release automation review."
            ),
            ScopedAutomationDocument(
                id: "external-issue",
                title: "External issue with release notes",
                scope: .externalSources,
                redactedSummary: "External connector preview should not be sent yet.",
                inclusionReason: "External source without connector-specific approval."
            )
        ]
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Prepare release notes and a pull request plan from selected docs.",
            documents: documents
        )

        let request = try viewModel.makeTaskAutomationPlanningRequest(
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 1,
                dailyLLMCallLimit: 3,
                lookaheadHours: 72
            ),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC",
            documentDeliverableDrafts: drafts
        )

        let payload = try jsonPayload(from: request.userInput)
        let selectedTasks = try XCTUnwrap(payload["selectedTasks"] as? [[String: Any]])
        let deliverables = try XCTUnwrap(payload["documentDeliverables"] as? [[String: Any]])

        XCTAssertEqual(viewModel.taskAutomationReviewDecision?.selectedTasks.map(\.title), ["High release note task"])
        XCTAssertEqual(selectedTasks.map { $0["title"] as? String }, ["High release note task"])
        XCTAssertEqual(
            deliverables.compactMap { $0["kind"] as? String }.sorted(),
            ["preparationChecklist", "pullRequestPlan", "releaseNotes"]
        )
        XCTAssertTrue(deliverables.allSatisfy { $0["requiresApproval"] as? Bool == true })
        XCTAssertEqual(Set(deliverables.compactMap { $0["riskLevel"] as? String }), ["draft"])
        XCTAssertTrue(deliverables.allSatisfy { ($0["sourceDocumentIDs"] as? [String]) == ["phase14"] })
        let sourceDocuments = deliverables.flatMap { ($0["sourceDocuments"] as? [[String: Any]]) ?? [] }
        XCTAssertFalse(sourceDocuments.isEmpty)
        XCTAssertTrue(sourceDocuments.allSatisfy { $0["id"] as? String == "phase14" })
        XCTAssertTrue(sourceDocuments.allSatisfy { $0["title"] as? String == "Phase14 release notes and PR plan" })
        XCTAssertTrue(sourceDocuments.allSatisfy { ($0["redactedSummary"] as? String)?.contains("[REDACTED_SECRET]") == true })
        XCTAssertTrue(request.availableTools.contains(.filesystemCreateMarkdownFile))
        XCTAssertTrue(request.userInput.contains("Document deliverables are draft-only"))
        XCTAssertFalse(request.userInput.contains("sk-proj-task-secret123"))
        XCTAssertFalse(request.userInput.contains("sk-proj-doc-secret123"))
        XCTAssertFalse(request.userInput.contains("external-issue"))
    }

    @MainActor
    func testProjectBoardViewModelExposesDocumentDeliverableSourcesForAutomationReviewUI() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(
            title: "High release documentation task",
            detail: "Prepare the reviewed release artifact.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        )
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Prepare release notes and the PR plan from selected docs.",
            documents: [
                ScopedAutomationDocument(
                    id: "phase14",
                    title: "Phase14 release notes source",
                    scope: .appDocs,
                    redactedSummary: "Release notes and pull request plan use sk-proj-ui-secret123.",
                    inclusionReason: "Selected by the user for review."
                ),
                ScopedAutomationDocument(
                    id: "external-issue",
                    title: "External issue",
                    scope: .externalSources,
                    redactedSummary: "External preview must not be rendered.",
                    inclusionReason: "Needs connector-specific approval."
                )
            ]
        )

        _ = try viewModel.makeTaskAutomationPlanningRequest(
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 1,
                dailyLLMCallLimit: 3,
                lookaheadHours: 72
            ),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC",
            documentDeliverableDrafts: drafts
        )

        XCTAssertEqual(
            viewModel.taskAutomationDocumentDeliverableReviews.map(\.title).sorted(),
            ["Preparation checklist", "Pull request plan", "Release notes draft"]
        )
        XCTAssertTrue(viewModel.taskAutomationDocumentDeliverableReviews.allSatisfy(\.requiresApproval))
        let sourcePreviews = viewModel.taskAutomationDocumentDeliverableReviews.flatMap(\.sourceDocuments)
        XCTAssertFalse(sourcePreviews.isEmpty)
        XCTAssertTrue(sourcePreviews.allSatisfy { $0.id == "phase14" })
        XCTAssertTrue(sourcePreviews.allSatisfy { $0.title == "Phase14 release notes source" })
        XCTAssertTrue(sourcePreviews.allSatisfy { $0.redactedSummary.contains("[REDACTED_SECRET]") })
        XCTAssertFalse(sourcePreviews.contains { $0.id == "external-issue" })
        XCTAssertFalse(sourcePreviews.contains { $0.redactedSummary.contains("sk-proj-ui-secret123") })
    }

    @MainActor
    func testProjectBoardViewModelShowsOnlyProviderReviewableDocumentDeliverables() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(
            title: "High document automation task",
            detail: "Only reviewed draft files should reach the provider and UI.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        )
        let releaseSource = DocumentAutomationDeliverableSource(
            id: "release",
            title: "Release notes source",
            redactedSummary: "Release evidence.",
            inclusionReason: "Selected for release notes."
        )
        let implementationSource = DocumentAutomationDeliverableSource(
            id: "implementation",
            title: "Implementation source",
            redactedSummary: "Implementation evidence.",
            inclusionReason: "Selected for PR planning."
        )
        let drafts = [
            DocumentAutomationDeliverableDraft(
                kind: .releaseNotes,
                title: "Release notes draft",
                suggestedPath: ".tmp/document-automation/shared-output.md",
                sourceDocumentIDs: ["release"],
                sourceDocuments: [releaseSource],
                rationale: "Create release notes from selected release evidence.",
                riskLevel: .draft,
                requiresApproval: true
            ),
            DocumentAutomationDeliverableDraft(
                kind: .pullRequestPlan,
                title: "Duplicate path PR plan",
                suggestedPath: ".tmp/document-automation/shared-output.md",
                sourceDocumentIDs: ["implementation"],
                sourceDocuments: [implementationSource],
                rationale: "Create a PR plan from selected implementation evidence.",
                riskLevel: .draft,
                requiresApproval: true
            ),
            DocumentAutomationDeliverableDraft(
                kind: .taskDraft,
                title: "Task mutation draft",
                suggestedPath: ".tmp/document-automation/task-draft.md",
                sourceDocumentIDs: ["release"],
                sourceDocuments: [releaseSource],
                rationale: "Task mutations belong in selected task review, not document output.",
                riskLevel: .write,
                requiresApproval: true
            ),
            DocumentAutomationDeliverableDraft(
                kind: .statusChange,
                title: "Status mutation draft",
                suggestedPath: ".tmp/document-automation/status-change.md",
                sourceDocumentIDs: ["release"],
                sourceDocuments: [releaseSource],
                rationale: "Status mutations must not render as document deliverables.",
                riskLevel: .write,
                requiresApproval: true
            ),
            DocumentAutomationDeliverableDraft(
                kind: .preparationChecklist,
                title: "Mismatched source checklist",
                suggestedPath: ".tmp/document-automation/mismatch.md",
                sourceDocumentIDs: ["missing"],
                sourceDocuments: [releaseSource],
                rationale: "The source preview is not bound to the declared ID.",
                riskLevel: .draft,
                requiresApproval: true
            ),
            DocumentAutomationDeliverableDraft(
                kind: .releaseNotes,
                title: "Write-risk release notes",
                suggestedPath: ".tmp/document-automation/write-risk.md",
                sourceDocumentIDs: ["release"],
                sourceDocuments: [releaseSource],
                rationale: "Allowed output kinds still must remain draft-only.",
                riskLevel: .write,
                requiresApproval: true
            )
        ]

        let request = try viewModel.makeTaskAutomationPlanningRequest(
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 1,
                dailyLLMCallLimit: 3,
                lookaheadHours: 72
            ),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC",
            documentDeliverableDrafts: drafts
        )
        let payload = try jsonPayload(from: request.userInput)
        let deliverables = try XCTUnwrap(payload["documentDeliverables"] as? [[String: Any]])

        XCTAssertEqual(deliverables.map { $0["title"] as? String }, ["Release notes draft"])
        XCTAssertEqual(viewModel.taskAutomationDocumentDeliverableReviews.map(\.title), ["Release notes draft"])
        XCTAssertEqual(viewModel.taskAutomationDocumentDeliverableReviews.map(\.suggestedPath), [".tmp/document-automation/shared-output.md"])
        XCTAssertFalse(viewModel.taskAutomationDocumentDeliverableReviews.contains { $0.title == "Task mutation draft" })
        XCTAssertFalse(viewModel.taskAutomationDocumentDeliverableReviews.contains { $0.title == "Status mutation draft" })
        XCTAssertFalse(viewModel.taskAutomationDocumentDeliverableReviews.contains { $0.title == "Duplicate path PR plan" })
        XCTAssertFalse(viewModel.taskAutomationDocumentDeliverableReviews.contains { $0.title == "Mismatched source checklist" })
        XCTAssertFalse(viewModel.taskAutomationDocumentDeliverableReviews.contains { $0.title == "Write-risk release notes" })
    }

    @MainActor
    func testProjectBoardViewModelClearsTaskAutomationReviewWhenCadenceThrottles() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "High due today", status: .planned, priority: .high, dueAt: "2026-06-22T18:00:00Z")
        _ = viewModel.prepareTaskAutomationReview(
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly),
            history: .empty,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar()
        )
        XCTAssertNotNil(viewModel.taskAutomationReviewDecision)

        let throttled = viewModel.prepareTaskAutomationReview(
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly),
            history: .init(lastRunAt: try isoDate("2026-06-22T08:30:00Z"), llmCallsToday: 0),
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(throttled.status, .throttled)
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Task automation cadence has not elapsed.")
    }

    @MainActor
    func testProjectBoardViewModelSessionHistoryThrottlesRepeatedTaskAutomationPlanningRequests() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "High due today", status: .planned, priority: .high, dueAt: "2026-06-22T18:00:00Z")

        let settings = TaskAutoExecutionSettings(isEnabled: true, mode: .reviewOnly, cadence: .hourly)
        let first = try viewModel.makeTaskAutomationPlanningRequest(
            settings: settings,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertTrue(first.userInput.contains("High due today"))
        XCTAssertThrowsError(
            try viewModel.makeTaskAutomationPlanningRequest(
                settings: settings,
                referenceDate: try isoDate("2026-06-22T09:30:00Z"),
                calendar: utcCalendar(),
                timeZoneIdentifier: "UTC"
            )
        ) { error in
            XCTAssertEqual(error as? TaskAutoExecutionPlanningRequestError, .noReviewableTasks)
        }
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Task automation cadence has not elapsed.")
    }

    @MainActor
    func testProjectBoardViewModelLocalAutomationPreparationDoesNotSpendLLMCallBudget() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "High local review task", status: .planned, priority: .high, dueAt: "2026-06-22T18:00:00Z")
        let settings = TaskAutoExecutionSettings(
            isEnabled: true,
            mode: .reviewOnly,
            cadence: .hourly,
            dailyLLMCallLimit: 1
        )

        let first = viewModel.prepareTaskAutomationReview(
            settings: settings,
            referenceDate: try isoDate("2026-06-22T09:00:00Z"),
            calendar: utcCalendar()
        )
        let second = viewModel.prepareTaskAutomationReview(
            settings: settings,
            referenceDate: try isoDate("2026-06-22T09:30:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(first.status, .readyForReview)
        XCTAssertEqual(second.status, .readyForReview)
        XCTAssertEqual(second.llmCallBudgetRemaining, 1)
        XCTAssertEqual(second.selectedTasks.map(\.title), ["High local review task"])

        _ = try viewModel.makeTaskAutomationPlanningRequest(
            settings: settings,
            referenceDate: try isoDate("2026-06-22T10:00:00Z"),
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertThrowsError(
            try viewModel.makeTaskAutomationPlanningRequest(
                settings: settings,
                referenceDate: try isoDate("2026-06-22T11:30:00Z"),
                calendar: utcCalendar(),
                timeZoneIdentifier: "UTC"
            )
        ) { error in
            XCTAssertEqual(error as? TaskAutoExecutionPlanningRequestError, .noReviewableTasks)
        }
        XCTAssertEqual(viewModel.todayCommandFeedback, "Daily LLM automation budget is exhausted.")
    }

    @MainActor
    func testProjectBoardViewModelScheduledAutomationHonorsManualFrequency() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "Manual frequency due task", status: .planned, priority: .high, dueAt: "2026-06-22T18:00:00Z")
        let settings = TaskAutoExecutionSettings(isEnabled: true, mode: .reviewOnly, cadence: .manual)
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")

        let scheduled = viewModel.prepareTaskAutomationReview(
            settings: settings,
            trigger: .scheduled,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )
        let manual = viewModel.prepareTaskAutomationReview(
            settings: settings,
            trigger: .manual,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(scheduled.status, .throttled)
        XCTAssertEqual(scheduled.reason, "Task automation frequency is manual; scheduled review will not call the LLM.")
        XCTAssertFalse(scheduled.shouldCallLLM)
        XCTAssertEqual(manual.status, .readyForReview)
        XCTAssertEqual(manual.selectedTasks.map(\.title), ["Manual frequency due task"])
        XCTAssertTrue(manual.shouldCallLLM)
    }

    @MainActor
    func testProjectBoardPlanningRequestDoesNotSpendManualCadenceBudgetForScheduledRun() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(title: "Manual request due task", status: .planned, priority: .high, dueAt: "2026-06-22T18:00:00Z")
        let settings = TaskAutoExecutionSettings(isEnabled: true, mode: .reviewOnly, cadence: .manual)
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")

        XCTAssertThrowsError(
            try viewModel.makeTaskAutomationPlanningRequest(
                settings: settings,
                trigger: .scheduled,
                referenceDate: referenceDate,
                calendar: utcCalendar(),
                timeZoneIdentifier: "UTC"
            )
        ) { error in
            XCTAssertEqual(error as? TaskAutoExecutionPlanningRequestError, .noReviewableTasks)
        }

        let request = try viewModel.makeTaskAutomationPlanningRequest(
            settings: settings,
            trigger: .manual,
            referenceDate: referenceDate,
            calendar: utcCalendar(),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertTrue(request.userInput.contains("cadence: manual"))
        XCTAssertTrue(request.userInput.contains("Manual request due task"))
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
    func testProjectBoardViewModelAnswersProjectAssistantQuestionWithoutExternalLLM() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Assistant Plan"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Resolve blocker", projectID: project.id, status: .blocked, dueAt: "2026-06-21"))
        _ = try XCTUnwrap(viewModel.createProjectMilestone(title: "Beta", dueAt: "2026-06-30", projectID: project.id))

        let answer = try XCTUnwrap(viewModel.answerProjectAssistantQuestion("What should I do next?", projectID: project.id))

        XCTAssertTrue(answer.message.contains("Resolve blocker"))
        XCTAssertEqual(answer.suggestedActionTitle, "Review unblock plan")
        XCTAssertTrue(answer.requiresReview)
        XCTAssertEqual(viewModel.projectAssistantAnswer, answer)
    }

    @MainActor
    func testProjectAssistantSuggestedActionPreparesReviewWithoutWritingTaskStatus() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Review Boundary"))
        let task = try XCTUnwrap(viewModel.createTask(title: "Blocked task", projectID: project.id, status: .blocked))
        _ = try XCTUnwrap(viewModel.answerProjectAssistantQuestion("Unblock this", projectID: project.id))

        XCTAssertTrue(viewModel.prepareProjectAssistantSuggestedActionForReview(projectID: project.id))

        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id }?.status, .blocked)
        XCTAssertEqual(viewModel.projectAssistantReviewDraft?.projectID, project.id)
        XCTAssertEqual(viewModel.projectAssistantReviewDraft?.suggestedActionTitle, "Review unblock plan")
    }

    @MainActor
    func testScheduleUnscheduledQueryExcludesDoneArchivedAndCompletedProjects() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let active = try XCTUnwrap(viewModel.createProject(title: "Active Schedule"))
        let archived = try XCTUnwrap(viewModel.createProject(title: "Archived Schedule"))
        let completed = try XCTUnwrap(viewModel.createProject(title: "Completed Schedule"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Active unscheduled", projectID: active.id, status: .planned, dueAt: nil))
        _ = try XCTUnwrap(viewModel.createTask(title: "Done unscheduled", projectID: active.id, status: .done, dueAt: nil))
        _ = try XCTUnwrap(viewModel.createTask(title: "Already scheduled", projectID: active.id, status: .planned, dueAt: "2026-06-22"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Archived unscheduled", projectID: archived.id, status: .planned, dueAt: nil))
        _ = try XCTUnwrap(viewModel.createTask(title: "Completed unscheduled", projectID: completed.id, status: .planned, dueAt: nil))
        viewModel.selectedProjectID = archived.id
        viewModel.archiveSelectedProject()
        viewModel.selectedProjectID = completed.id
        viewModel.completeSelectedProject()

        XCTAssertEqual(viewModel.unscheduledScheduleTasks().map(\.title), ["Active unscheduled"])
    }

    @MainActor
    func testScheduleDraftCombinesTodayBlocksAndUnscheduledTasksWithoutWritingStore() throws {
        var changeCount = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore(), onChange: { changeCount += 1 })
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Draft"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Today task", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Unscheduled task", projectID: project.id, status: .planned, dueAt: nil))
        changeCount = 0

        let draft = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(draft.timeBlocks.map(\.task.title), ["Today task"])
        XCTAssertEqual(draft.unscheduledTasks.map(\.title), ["Unscheduled task"])
        XCTAssertEqual(viewModel.scheduleDraft, draft)
        XCTAssertEqual(viewModel.todayScheduleDraft?.timeBlocks.map(\.task.title), ["Today task"])
    }

    @MainActor
    func testDailyWorkloadOverviewAggregatesWeekCountsProgressAndUnscheduledBuckets() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-24T09:00:00Z")
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inbox = try XCTUnwrap(viewModel.inboxProject)
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let support = try XCTUnwrap(viewModel.createProject(title: "Support"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Inbox raw capture", projectID: inbox.id, status: .planned, dueAt: nil))
        _ = try XCTUnwrap(viewModel.createTask(title: "Overdue launch follow-up", projectID: launch.id, status: .planned, dueAt: "2026-06-22T18:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Blocked support reply", projectID: support.id, status: .blocked, dueAt: "2026-06-24T15:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Done launch note", projectID: launch.id, status: .done, dueAt: "2026-06-24T12:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Tomorrow in progress", projectID: launch.id, status: .inProgress, dueAt: "2026-06-25T10:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Backlog without date", projectID: support.id, status: .planned, dueAt: nil))

        let overview = viewModel.dailyWorkloadOverview(
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: 7
        )

        XCTAssertEqual(overview.days.map(\.dateKey), [
            "2026-06-22",
            "2026-06-23",
            "2026-06-24",
            "2026-06-25",
            "2026-06-26",
            "2026-06-27",
            "2026-06-28"
        ])
        XCTAssertEqual(overview.inboxUntriagedCount, 1)
        XCTAssertEqual(overview.unscheduledTasks.map(\.title), ["Backlog without date"])

        let monday = try XCTUnwrap(overview.days.first { $0.dateKey == "2026-06-22" })
        XCTAssertEqual(monday.totalTaskCount, 1)
        XCTAssertEqual(monday.openTaskCount, 1)
        XCTAssertEqual(monday.overdueTaskCount, 1)
        XCTAssertEqual(monday.progress, 0)
        XCTAssertEqual(monday.projectContributions.map(\.projectTitle), ["Launch"])

        let wednesday = try XCTUnwrap(overview.days.first { $0.dateKey == "2026-06-24" })
        XCTAssertEqual(wednesday.totalTaskCount, 2)
        XCTAssertEqual(wednesday.openTaskCount, 1)
        XCTAssertEqual(wednesday.blockedTaskCount, 1)
        XCTAssertEqual(wednesday.doneTaskCount, 1)
        XCTAssertEqual(wednesday.overdueTaskCount, 0)
        XCTAssertEqual(wednesday.progress, 0.5)
        XCTAssertEqual(wednesday.projectContributions.map(\.projectTitle), ["Launch", "Support"])

        let thursday = try XCTUnwrap(overview.days.first { $0.dateKey == "2026-06-25" })
        XCTAssertEqual(thursday.totalTaskCount, 1)
        XCTAssertEqual(thursday.inProgressTaskCount, 1)
        XCTAssertEqual(thursday.progress, 0)
    }

    @MainActor
    func testDailyWorkloadOverviewExcludesInboxArchivedAndCompletedProjectsWithoutCalendarWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let inbox = try XCTUnwrap(viewModel.inboxProject)
        let active = try XCTUnwrap(viewModel.createProject(title: "Active Plan"))
        let archived = try XCTUnwrap(viewModel.createProject(title: "Archived Plan"))
        let completed = try XCTUnwrap(viewModel.createProject(title: "Completed Plan"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Inbox due capture", projectID: inbox.id, status: .planned, dueAt: "2026-06-24"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Active due", projectID: active.id, status: .planned, dueAt: "2026-06-24"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Archived due", projectID: archived.id, status: .planned, dueAt: "2026-06-24"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Completed due", projectID: completed.id, status: .planned, dueAt: "2026-06-24"))
        viewModel.selectedProjectID = archived.id
        viewModel.archiveSelectedProject()
        viewModel.selectedProjectID = completed.id
        viewModel.completeSelectedProject()

        let overview = viewModel.dailyWorkloadOverview(
            around: try isoDate("2026-06-24T09:00:00Z"),
            calendar: calendar,
            visibleDayCount: 7
        )

        let wednesday = try XCTUnwrap(overview.days.first { $0.dateKey == "2026-06-24" })
        XCTAssertEqual(wednesday.projectContributions.map(\.projectTitle), ["Active Plan"])
        XCTAssertEqual(wednesday.projectContributions.flatMap(\.tasks).map(\.title), ["Active due"])
        XCTAssertEqual(overview.inboxUntriagedCount, 1)
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testDailyPlanningReviewUsesTodayAndWorkloadWithoutMutatingStoreOrCalendar() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Plan"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Clear overdue blocker",
            projectID: project.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-06-29"
        ))
        let beforeSnapshot = viewModel.snapshot

        let review = viewModel.prepareDailyPlanningReview(
            transcript: "今日やることを確認して",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(review.recommendedTaskID, task.id)
        XCTAssertEqual(viewModel.dailyPlanningReview?.recommendedTaskID, task.id)
        XCTAssertEqual(viewModel.snapshot, beforeSnapshot)
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.blocked)?.tasks.map(\.id), [task.id])
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testScheduleApplyRequiresApprovalBeforeCalendarWrite() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient()
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Approval Schedule"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: nil)

        XCTAssertEqual(result, .approvalRequired)
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
        XCTAssertEqual(viewModel.scheduleApplyResult, .approvalRequired)
        XCTAssertTrue(receiptStore.receipts.isEmpty)
    }

    @MainActor
    func testScheduleApplyWithoutCalendarBackendDoesNotReturnMockSuccess() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "No Calendar"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        XCTAssertEqual(result, .calendarNotConfigured)
        XCTAssertEqual(viewModel.scheduleApplyResult, .calendarNotConfigured)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .skipped)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertTrue(receipt.approvalID?.hasPrefix("schedule-draft-apply-approval:") ?? false)
        XCTAssertEqual(receipt.references.map(\.kind), [.task, .project])
    }

    @MainActor
    func testScheduleApplyWithoutDraftPersistsSkippedReceiptAfterApproval() throws {
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore,
            scheduleCalendarClient: InMemoryCalendarClient()
        )
        viewModel.load()

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        XCTAssertEqual(result, .noDraft)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .skipped)
        XCTAssertTrue(receipt.approvalID?.hasPrefix("schedule-draft-apply-approval:") ?? false)
        XCTAssertTrue(receipt.references.isEmpty)
    }

    @MainActor
    func testScheduleApplyPersistsExecutionReceiptForCreatedCalendarEvents() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient()
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Project token=project-secret"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Calendar block token=task-secret",
            projectID: project.id,
            status: .planned,
            dueAt: "2026-06-21"
        ))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approval-token-secret")

        XCTAssertEqual(result, .applied(eventCount: 1))
        XCTAssertEqual(try calendarClient.listEvents().count, 1)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertTrue(receipt.approvalID?.hasPrefix("schedule-draft-apply-approval:") ?? false)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertEqual(receipt.references.map(\.kind), [.task, .project, .calendarEvent])
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: String(task.id), label: "Calendar block [REDACTED_SECRET]")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: String(project.id), label: "Schedule Project [REDACTED_SECRET]")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .calendarEvent, id: "calendar-event-1", label: "Calendar block [REDACTED_SECRET]")))
        XCTAssertEqual(receipt.visibleSurfaces, [.taskDetail, .projectDetail, .auditLog])
        let encodedReceipt = try XCTUnwrap(String(data: JSONEncoder().encode(receipt), encoding: .utf8))
        XCTAssertFalse(encodedReceipt.contains("approval-token-secret"))
        XCTAssertFalse(encodedReceipt.contains("task-secret"))
        XCTAssertFalse(encodedReceipt.contains("project-secret"))

        let globalRow = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot.rows.first)
        XCTAssertEqual(globalRow.status, .succeeded)
        XCTAssertEqual(globalRow.toolLabel, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertTrue(globalRow.referenceSummary.contains("Calendar Event 1"))
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.map(\.toolLabel), [ActionTool.calendarCreateWorkBlock.rawValue])
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.map(\.toolLabel), [ActionTool.calendarCreateWorkBlock.rawValue])
    }

    @MainActor
    func testScheduleApplyPersistsFailedExecutionReceiptWhenCalendarWriteFails() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient(authorizationStatus: .denied)
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Denied Calendar"))
        let task = try XCTUnwrap(viewModel.createTask(title: "Calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        guard case .failed(let message) = result else {
            return XCTFail("Expected a failed schedule apply result.")
        }
        XCTAssertTrue(message.contains("Calendar permission is denied"))
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertEqual(receipt.references.map(\.kind), [.task, .project])
        XCTAssertTrue(receipt.actions.contains { $0.status == .failed && ($0.errorSummary?.contains("Calendar permission is denied") ?? false) })
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot.rows.first?.status, .failed)
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.map(\.status), [.failed])
    }

    @MainActor
    func testScheduleApplyPersistsPartialFailureReceiptAfterCreatedCalendarEvent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = FailingAfterFirstCalendarClient()
        let receiptStore = InMemoryExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Partial Calendar"))
        let firstTask = try XCTUnwrap(viewModel.createTask(title: "First calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        let secondTask = try XCTUnwrap(viewModel.createTask(title: "Second calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        guard case .failed(let message) = result else {
            return XCTFail("Expected a failed schedule apply result.")
        }
        XCTAssertTrue(message.contains("Calendar write failed after the first event"))
        XCTAssertEqual(try calendarClient.listEvents().count, 1)
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.references.filter { $0.kind == .calendarEvent }.map(\.id), ["calendar-event-1"])
        XCTAssertEqual(receipt.actions.map(\.status), [.succeeded, .failed])
        XCTAssertTrue(receipt.references.contains { $0.kind == .task && $0.id == String(firstTask.id) })
        XCTAssertTrue(receipt.references.contains { $0.kind == .task && $0.id == String(secondTask.id) })
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.map(\.status), [.failed])
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
    func testProjectBoardViewModelRollsBackMultiTaskProjectDropWhenStoreFailsMidMove() {
        var changeCount = 0
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(
            store: store,
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let sourceProjectID = Int64(1)
        let targetProjectID = Int64(2)
        let taskIDs = store.snapshot.projects
            .first(where: { $0.id == sourceProjectID })?
            .tasks
            .map(\.id) ?? []

        let didMove = viewModel.moveDroppedTasks(ids: taskIDs, toProjectID: targetProjectID)

        XCTAssertFalse(didMove)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Project board unavailable")

        viewModel.load()

        XCTAssertEqual(
            viewModel.snapshot.projects.first(where: { $0.id == sourceProjectID })?.tasks.map(\.id),
            taskIDs
        )
        XCTAssertEqual(
            viewModel.snapshot.projects.first(where: { $0.id == targetProjectID })?.tasks,
            []
        )
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
    func testProjectBoardViewModelSelectsFirstVisibleInboxTaskWhenInboxAppears() throws {
        let bundle = try makeStoreBundle()
        let captures = SQLiteInboxCaptureStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, inboxCaptureStore: captures)
        viewModel.load()

        _ = try XCTUnwrap(viewModel.createInboxTask(title: "Older manual capture"))
        let latest = try XCTUnwrap(viewModel.createInboxTask(title: "Scheduled manual capture"))
        viewModel.selectedTaskID = nil

        viewModel.ensureSelectedInboxTaskIsVisible()

        XCTAssertEqual(viewModel.selectedTaskID, latest.id)
        XCTAssertEqual(viewModel.filteredInboxTasks.first?.id, latest.id)
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
    func testProjectBoardViewModelBuildsTodayAssistantRailContextFromSelectedTask() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Fix overdue blocker",
            detail: "Unblock the release owner",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )
        let selected = try XCTUnwrap(viewModel.createTask(
            title: "Ship today update",
            detail: "Prepare release note",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.selectedTaskID = selected.id

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .selected)
        XCTAssertEqual(context.task?.title, "Ship today update")
        XCTAssertEqual(context.projectTitle, "Launch")
        XCTAssertEqual(context.nextActionTitle, "Review selected task")
        XCTAssertEqual(context.nextActionReason, "You selected this Today task for review.")
        XCTAssertEqual(context.nextBlockLabel, "09:30-10:00")
        XCTAssertEqual(context.notes, "Prepare release note")
        XCTAssertEqual(context.subtaskSummary, "Subtask capture is staged through the Today command.")
        XCTAssertEqual(context.reminderSummary, "Reminder draft only; external writes require approval.")
    }

    @MainActor
    func testProjectBoardViewModelBuildsEmptyTodayAssistantRailContext() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .empty)
        XCTAssertNil(context.task)
        XCTAssertEqual(context.projectTitle, "No project selected")
        XCTAssertEqual(context.nextActionTitle, "Capture the next task")
        XCTAssertEqual(context.nextActionReason, "No due work is scheduled for today.")
        XCTAssertNil(context.nextBlockLabel)
    }

    @MainActor
    func testProjectBoardViewModelBuildsMissedTaskReviewWithCountsAndReviewedState() throws {
        let bundle = try makeStoreBundle()
        let reviewStore = SQLiteMissedTaskReviewStateStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, missedTaskReviewStateStore: reviewStore)
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Clear overdue blocker",
            projectID: launch.id,
            status: .planned,
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
            title: "Resolve blocked handoff",
            projectID: launch.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-06-19T14:00:00Z"
        )
        let stale = try XCTUnwrap(viewModel.createTask(
            title: "Revive stale unscheduled follow-up",
            projectID: launch.id,
            status: .backlog,
            priority: .medium
        ))
        _ = viewModel.createTask(
            title: "Unscheduled idea",
            projectID: launch.id,
            status: .backlog,
            priority: .low
        )
        try bundle.connection.execute("UPDATE tasks SET updated_at = '2026-06-01T12:00:00Z' WHERE id = \(stale.id);")
        viewModel.load()

        let summary = viewModel.missedTaskReview(
            on: try isoDate("2026-06-19T09:00:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.dueTodayCount, 2)
        XCTAssertEqual(summary.blockedCount, 1)
        XCTAssertEqual(summary.unscheduledCount, 2)
        XCTAssertEqual(summary.staleCount, 1)
        XCTAssertEqual(summary.newlyMissedCount, 4)
        XCTAssertEqual(
            summary.immediateQueue.map(\.task.title),
            [
                "Clear overdue blocker",
                "Resolve blocked handoff",
                "Revive stale unscheduled follow-up",
                "Unscheduled idea"
            ]
        )
        XCTAssertTrue(summary.immediateQueue.allSatisfy(\.isNewlyMissed))
        XCTAssertEqual(summary.immediateQueue.first?.reasons, [.overdue])
        XCTAssertEqual(summary.immediateQueue[1].reasons, [.dueToday, .blocked])
        XCTAssertEqual(summary.immediateQueue[2].reasons, [.unscheduled, .stale])
    }

    @MainActor
    func testProjectBoardViewModelSchedulesDailyMissedTaskFollowUpFromReviewSummary() throws {
        let bundle = try makeStoreBundle()
        let reviewStore = SQLiteMissedTaskReviewStateStore(connection: bundle.connection)
        let notificationClient = InMemoryNotificationClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            missedTaskReviewStateStore: reviewStore,
            missedTaskFollowUpNotificationClient: notificationClient
        )
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Sensitive customer escalation sk-secret",
            detail: "Read /Users/alice/customer.md before replying.",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Revive stale unscheduled follow-up",
            projectID: launch.id,
            status: .backlog,
            priority: .medium
        )

        let result = try XCTUnwrap(viewModel.scheduleMissedTaskDailyFollowUp(
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC"),
            dateProvider: ProjectBoardFixedDateProvider(now: try isoDate("2026-06-19T09:00:00Z")),
            calendar: utcCalendar()
        ))
        let duplicate = try XCTUnwrap(viewModel.scheduleMissedTaskDailyFollowUp(
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC"),
            dateProvider: ProjectBoardFixedDateProvider(now: try isoDate("2026-06-19T10:00:00Z")),
            calendar: utcCalendar()
        ))
        let scheduled = try notificationClient.listScheduled()

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.day, "2026-06-19")
        XCTAssertEqual(result.missedCount, 2)
        XCTAssertEqual(duplicate.status, .skippedAlreadyNotifiedToday)
        XCTAssertEqual(try reviewStore.lastNotifiedDay(), "2026-06-19")
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.id, "missed-task-review-2026-06-19")
        XCTAssertEqual(scheduled.first?.body, "2 tasks need review. Overdue: 1, due today: 0, blocked: 0, unscheduled: 1, stale: 0.")
        XCTAssertFalse((scheduled.first?.body ?? "").contains("sk-secret"))
        XCTAssertFalse((scheduled.first?.body ?? "").contains("/Users/alice/customer.md"))
        XCTAssertFalse((scheduled.first?.body ?? "").contains("Sensitive customer"))
    }

    @MainActor
    func testProjectBoardViewModelUsesConfiguredTimeZoneForMissedTaskDailyFollowUpClassification() throws {
        let bundle = try makeStoreBundle()
        let reviewStore = SQLiteMissedTaskReviewStateStore(connection: bundle.connection)
        let notificationClient = InMemoryNotificationClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            missedTaskReviewStateStore: reviewStore,
            missedTaskFollowUpNotificationClient: notificationClient
        )
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Resolve boundary-time blocker",
            projectID: launch.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-06-30T08:00:00Z"
        )

        let result = try XCTUnwrap(viewModel.scheduleMissedTaskDailyFollowUp(
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "America/Los_Angeles"),
            dateProvider: ProjectBoardFixedDateProvider(now: try isoDate("2026-07-01T06:30:00Z"))
        ))
        let scheduled = try notificationClient.listScheduled()

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.day, "2026-06-30")
        XCTAssertEqual(scheduled.first?.body, "1 tasks need review. Overdue: 0, due today: 1, blocked: 1, unscheduled: 0, stale: 0.")
    }

    @MainActor
    func testProjectBoardViewModelKeepsInboxCapturesOutOfMissedTaskReview() throws {
        let bundle = try makeStoreBundle()
        let reviewStore = SQLiteMissedTaskReviewStateStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, missedTaskReviewStateStore: reviewStore)
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Follow up with customer",
            projectID: launch.id,
            status: .backlog,
            priority: .medium
        )
        _ = try XCTUnwrap(viewModel.createInboxTask(title: "Raw voice capture"))
        _ = try XCTUnwrap(viewModel.createInboxTask(
            title: "Inbox due today",
            dueAt: "2026-06-19T12:00:00Z"
        ))

        let summary = viewModel.missedTaskReview(
            on: try isoDate("2026-06-19T09:00:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(summary.unscheduledCount, 1)
        XCTAssertEqual(summary.dueTodayCount, 0)
        XCTAssertEqual(summary.immediateQueue.map(\.task.title), ["Follow up with customer"])
        XCTAssertFalse(summary.items.contains { $0.projectTitle == "Inbox" })
    }

    @MainActor
    func testProjectBoardViewModelMissedTaskReviewFailsClosedWhenReviewStateCannotLoad() throws {
        let bundle = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            missedTaskReviewStateStore: FailingMissedTaskReviewStateStore()
        )
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Clear overdue blocker",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )

        let summary = viewModel.missedTaskReview(
            on: try isoDate("2026-06-19T09:00:00Z"),
            calendar: utcCalendar()
        )

        XCTAssertEqual(summary.overdueCount, 1)
        XCTAssertEqual(summary.newlyMissedCount, 0)
        XCTAssertEqual(summary.immediateQueue, [])
        XCTAssertEqual(summary.items.first?.isNewlyMissed, false)
        XCTAssertEqual(summary.stateErrorMessage, "Missed task review state could not be loaded.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelMissedTaskActionsUpdateLocalStateAndImmediateQueue() throws {
        let bundle = try makeStoreBundle()
        let reviewStore = SQLiteMissedTaskReviewStateStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board, missedTaskReviewStateStore: reviewStore)
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let overdue = try XCTUnwrap(viewModel.createTask(
            title: "Close overdue QA",
            projectID: launch.id,
            status: .planned,
            dueAt: "2026-06-18T09:00:00Z"
        ))
        let reschedule = try XCTUnwrap(viewModel.createTask(
            title: "Pick new time",
            projectID: launch.id,
            status: .backlog
        ))
        let deferred = try XCTUnwrap(viewModel.createTask(
            title: "Keep for later",
            projectID: launch.id,
            status: .backlog
        ))
        let referenceDate = try isoDate("2026-06-19T09:00:00Z")
        let calendar = utcCalendar()

        XCTAssertEqual(viewModel.missedTaskReview(on: referenceDate, calendar: calendar).newlyMissedCount, 3)

        viewModel.completeMissedTask(id: overdue.id, referenceDate: referenceDate)
        viewModel.rescheduleMissedTaskForToday(id: reschedule.id, referenceDate: referenceDate)
        viewModel.deferMissedTaskForLater(id: deferred.id, referenceDate: referenceDate)

        let summary = viewModel.missedTaskReview(on: referenceDate, calendar: calendar)
        let reloaded = ProjectBoardViewModel(store: bundle.board, missedTaskReviewStateStore: reviewStore)
        reloaded.load()
        let tasks = reloaded.snapshot.projects.flatMap(\.tasks)

        XCTAssertEqual(summary.immediateQueue.map(\.task.title), [])
        XCTAssertEqual(tasks.first { $0.id == overdue.id }?.status, .done)
        XCTAssertEqual(tasks.first { $0.id == reschedule.id }?.dueAt, "2026-06-19T09:00:00Z")
        XCTAssertEqual(tasks.first { $0.id == reschedule.id }?.status, .planned)
        XCTAssertEqual(try reviewStore.lastReviewedAt(taskID: deferred.id), referenceDate)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Deferred \"Keep for later\" from today's missed queue.")
    }

    func testSQLiteMissedTaskReviewStateStorePersistsReviewedTaskDates() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteMissedTaskReviewStateStore(connection: connection)
        let reviewedAt = try isoDate("2026-06-19T09:00:00Z")

        try store.markReviewed(taskID: 42, at: reviewedAt)

        let reloaded = SQLiteMissedTaskReviewStateStore(connection: connection)
        XCTAssertTrue(try connection.tableExists("missed_task_review_state"))
        XCTAssertEqual(try reloaded.lastReviewedAt(taskID: 42), reviewedAt)
    }

    func testSQLiteMissedTaskReviewStateStorePersistsNotificationDayWithoutTaskContent() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteMissedTaskReviewStateStore(connection: connection)

        try store.recordNotification(day: "2026-06-19", at: try isoDate("2026-06-19T09:00:00Z"))
        try store.recordNotification(day: "2026-06-20", at: try isoDate("2026-06-20T09:00:00Z"))

        let columns = Set(try connection.queryRows("PRAGMA table_info(missed_task_review_state);").compactMap { $0["name"] })
        let notificationRows = try connection.queryRows(
            "SELECT task_id, last_reviewed_at, last_notified_day FROM missed_task_review_state WHERE task_id = 0;"
        )

        XCTAssertEqual(try store.lastNotifiedDay(), "2026-06-20")
        XCTAssertTrue(columns.isSuperset(of: ["task_id", "last_reviewed_at", "last_reviewed_day", "last_notified_day", "updated_at"]))
        XCTAssertFalse(columns.contains("title"))
        XCTAssertFalse(columns.contains("detail"))
        XCTAssertEqual(notificationRows.count, 1)
        XCTAssertEqual(notificationRows.first?["last_reviewed_at"], "")
        XCTAssertEqual(notificationRows.first?["last_notified_day"], "2026-06-20")
    }

    @MainActor
    func testProjectBoardViewModelTodayCommandCreatesInboxItemAndNotifies() throws {
        var changeCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            onChange: { changeCount += 1 }
        )
        viewModel.load()

        let task = try XCTUnwrap(viewModel.submitTodayCommand("Capture handoff checklist"))

        XCTAssertEqual(task.title, "Capture handoff checklist")
        XCTAssertEqual(task.status, .backlog)
        XCTAssertEqual(viewModel.inboxTasks.first?.id, task.id)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Added \"Capture handoff checklist\" to Inbox.")
        XCTAssertEqual(changeCount, 1)
    }

    @MainActor
    func testProjectBoardViewModelTodayRecommendationChipsUseStableBlockerDuePriorityOrder() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Resolve release blocker",
            projectID: launch.id,
            status: .blocked,
            priority: .medium,
            dueAt: "2026-06-19T11:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Clear overdue review",
            projectID: launch.id,
            status: .planned,
            priority: .low,
            dueAt: "2026-06-18T09:00:00Z"
        )
        _ = viewModel.createTask(
            title: "Ship high priority update",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-19T12:00:00Z"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let chips = viewModel.todayRecommendationChips(
            on: try isoDate("2026-06-19T08:00:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(chips.map(\.kind), [.blocker, .overdue, .highPriority])
        XCTAssertEqual(chips.map(\.taskTitle), ["Resolve release blocker", "Clear overdue review", "Ship high priority update"])
    }

    @MainActor
    func testProjectBoardViewModelStartFocusDoesNotMutateTaskStatus() throws {
        let store = try makeStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Draft launch note",
            projectID: project.id,
            status: .planned,
            dueAt: "2026-06-19T12:00:00Z"
        ))

        viewModel.startFocus(taskID: task.id)

        let reloaded = ProjectBoardViewModel(store: store)
        reloaded.load()
        XCTAssertEqual(reloaded.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id }?.status, .planned)
        XCTAssertEqual(viewModel.todayFocusTaskID, task.id)
        XCTAssertEqual(viewModel.selectedTaskID, task.id)
    }

    @MainActor
    func testProjectBoardViewModelPreparesScheduleDraftWithoutMutatingTasks() throws {
        let store = try makeStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Prepare schedule review",
            projectID: project.id,
            status: .planned,
            dueAt: "2026-06-19T12:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let draft = viewModel.prepareTodayScheduleDraft(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        let reloaded = ProjectBoardViewModel(store: store)
        reloaded.load()
        XCTAssertEqual(draft.timeBlocks.map(\.task.id), [task.id])
        XCTAssertEqual(viewModel.todayScheduleDraft, draft)
        XCTAssertEqual(reloaded.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id }?.status, .planned)
    }

    @MainActor
    func testProjectBoardViewModelPreparesPrioritizedTodayScheduleDraftForRailTask() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        for index in 0..<5 {
            _ = viewModel.createTask(
                title: "Earlier task \(index)",
                projectID: project.id,
                status: .planned,
                dueAt: "2026-06-19T0\(index + 8):00:00Z"
            )
        }
        let railTask = try XCTUnwrap(viewModel.createTask(
            title: "Rail selected task",
            projectID: project.id,
            status: .planned,
            dueAt: "2026-06-19T15:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let draft = viewModel.prepareTodayScheduleDraft(
            prioritizing: railTask.id,
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(draft.timeBlocks.first?.task.id, railTask.id)
        XCTAssertEqual(draft.timeBlocks.first?.label, "09:00-09:30")
        XCTAssertTrue(draft.timeBlocks.contains { $0.task.title == "Earlier task 0" })
    }

    @MainActor
    func testProjectBoardViewModelBuildsProjectPortfolioSummariesWithProgressRiskAndNextDue() throws {
        let referenceDate = try isoDate("2026-06-21T09:00:00Z")
        let calendar = Calendar(identifier: .gregorian)
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Ship blocker", projectID: launch.id, status: .blocked, priority: .high, dueAt: "2026-06-20"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Draft notes", projectID: launch.id, status: .done, priority: .medium, dueAt: "2026-06-19"))
        _ = try XCTUnwrap(viewModel.createTask(title: "QA pass", projectID: launch.id, status: .planned, priority: .medium, dueAt: "2026-06-24"))
        let tidy = try XCTUnwrap(viewModel.createProject(title: "Tidy"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Close loop", projectID: tidy.id, status: .done, priority: .low, dueAt: "2026-06-18"))

        let summaries = viewModel.projectPortfolioSummaries(on: referenceDate, calendar: calendar)
        let launchSummary = try XCTUnwrap(summaries.first { $0.projectID == launch.id })
        let tidySummary = try XCTUnwrap(summaries.first { $0.projectID == tidy.id })

        XCTAssertEqual(launchSummary.progress, 1.0 / 3.0, accuracy: 0.001)
        XCTAssertEqual(launchSummary.openTaskCount, 2)
        XCTAssertEqual(launchSummary.doneTaskCount, 1)
        XCTAssertEqual(launchSummary.blockedTaskCount, 1)
        XCTAssertEqual(launchSummary.overdueTaskCount, 1)
        XCTAssertEqual(launchSummary.nextDueAt, "2026-06-20")
        XCTAssertEqual(launchSummary.health, .atRisk)
        XCTAssertEqual(launchSummary.riskReason, "1 blocked, 1 overdue")
        XCTAssertEqual(launchSummary.nextActionTitle, "Ship blocker")
        XCTAssertEqual(launchSummary.localHealthRuleDescription, "Local Health prioritizes blocked tasks, then overdue work, then open task progress.")
        XCTAssertEqual(tidySummary.health, .completed)
        XCTAssertEqual(tidySummary.progress, 1.0, accuracy: 0.001)
    }

    @MainActor
    func testDoneAnalyticsCalculatesDailyWeeklyCountsAndStreak() throws {
        let calendar = Calendar(identifier: .gregorian)
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            ProjectBoardProject(
                id: 1,
                title: "Launch",
                status: "active",
                subtitle: "0 open / 3 total",
                columns: ProjectTaskStatus.allCases.map { status in
                    ProjectBoardColumn(status: status, tasks: status == .done ? [
                        ProjectBoardTask(id: 1, projectID: 1, title: "Today", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-21T08:00:00Z"),
                        ProjectBoardTask(id: 2, projectID: 1, title: "Yesterday", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-20T08:00:00Z"),
                        ProjectBoardTask(id: 3, projectID: 1, title: "Earlier week", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-18T08:00:00Z")
                    ] : [])
                }
            )
        ])))
        viewModel.load()

        let analytics = viewModel.doneAnalytics(on: try isoDate("2026-06-21T09:00:00Z"), calendar: calendar)

        XCTAssertEqual(analytics.completedTaskCount, 3)
        XCTAssertEqual(analytics.completedTodayCount, 1)
        XCTAssertEqual(analytics.completedThisWeekCount, 3)
        XCTAssertEqual(analytics.streakDays, 2)
        XCTAssertEqual(analytics.recentTasks.map(\.title), ["Today", "Yesterday", "Earlier week"])
        XCTAssertEqual(analytics.localRuleInsight, "Done analytics uses local completed_at history; reopened tasks remain visible in completion history.")
    }

    @MainActor
    func testReopenCompletedTaskMovesToPlannedAndKeepsCompletedHistory() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.snapshot.projects.first)
        let task = try XCTUnwrap(viewModel.createTask(title: "Review closeout", projectID: project.id, status: .done))
        let completedAt = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id }?.completedAt)

        viewModel.reopenCompletedTask(id: task.id)

        let reopened = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        XCTAssertEqual(reopened.status, .planned)
        XCTAssertEqual(reopened.completedAt, completedAt)
    }

    @MainActor
    func testProjectBoardViewModelSelectsProjectFromPortfolioCardWithoutChangingTaskSelection() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let first = try XCTUnwrap(viewModel.createProject(title: "First"))
        let second = try XCTUnwrap(viewModel.createProject(title: "Second"))
        let task = try XCTUnwrap(viewModel.createTask(title: "Selected task", projectID: first.id))
        viewModel.selectedTaskID = task.id

        XCTAssertTrue(viewModel.openProjectFromPortfolioCard(projectID: second.id))

        XCTAssertEqual(viewModel.selectedProjectID, second.id)
        XCTAssertNil(viewModel.selectedTaskID)
        XCTAssertNil(viewModel.errorMessage)
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
    func testProjectBoardViewModelMovesMultipleDroppedTasksIntoTargetProject() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let targetProject = try XCTUnwrap(viewModel.createProject(title: "Batch Launch Plan"))
        let first = try XCTUnwrap(viewModel.createTask(
            title: "Classify first drag card",
            projectID: inboxID,
            status: .backlog
        ))
        let second = try XCTUnwrap(viewModel.createTask(
            title: "Classify second drag card",
            projectID: inboxID,
            status: .planned
        ))

        XCTAssertTrue(viewModel.moveDroppedTasks(ids: [String(first.id), String(second.id)], toProjectID: targetProject.id))

        let movedTasks = viewModel.snapshot.projects
            .first(where: { $0.id == targetProject.id })?
            .tasks
        XCTAssertEqual(movedTasks?.map(\.id).sorted(), [first.id, second.id].sorted())
        XCTAssertEqual(movedTasks?.first(where: { $0.id == first.id })?.status, .backlog)
        XCTAssertEqual(movedTasks?.first(where: { $0.id == second.id })?.status, .planned)
        XCTAssertEqual(viewModel.selectedProjectID, targetProject.id)
        XCTAssertEqual(viewModel.selectedTaskID, second.id)
        XCTAssertFalse(viewModel.inboxTasks.contains { [first.id, second.id].contains($0.id) })
        XCTAssertEqual(viewModel.integrationStatusMessage, "Moved 2 tasks to project.")
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

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func jsonPayload(from userInput: String) throws -> [String: Any] {
        let opening = "```json\n"
        let closing = "\n```"
        guard let start = userInput.range(of: opening)?.upperBound,
              let end = userInput[start...].range(of: closing)?.lowerBound else {
            XCTFail("Planning request did not include a fenced JSON payload.")
            return [:]
        }
        let json = String(userInput[start..<end])
        let data = Data(json.utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeStoreBundle() throws -> (
        connection: SQLiteConnection,
        board: SQLiteProjectBoardStore,
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore,
        artifacts: SQLiteArtifactStore,
        milestones: SQLiteProjectMilestoneStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            connection,
            SQLiteProjectBoardStore(connection: connection),
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteArtifactStore(connection: connection),
            SQLiteProjectMilestoneStore(connection: connection)
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

    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        throw error
    }

    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        throw error
    }

    func deleteProjectMilestone(id: Int64) throws {
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
            ),
            ProjectBoardProject(
                id: 2,
                title: "Target",
                status: "active",
                subtitle: "0 open / 0 total",
                columns: ProjectTaskStatus.allCases.map { status in
                    ProjectBoardColumn(status: status, tasks: [])
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
        let originalSnapshot = currentSnapshot
        do {
            return try ids.map { try moveTask(id: $0, toProjectID: projectID) }
        } catch {
            currentSnapshot = originalSnapshot
            throw error
        }
    }

    private func moveTask(id: Int64, toProjectID projectID: Int64) throws -> ProjectBoardTask {
        guard id == 1 else {
            throw ProjectBoardStoreTestError.unavailable
        }
        guard let sourceProjectIndex = currentSnapshot.projects.firstIndex(where: { project in
            project.tasks.contains { $0.id == id }
        }),
            let targetProjectIndex = currentSnapshot.projects.firstIndex(where: { $0.id == projectID }),
            let task = currentSnapshot.projects[sourceProjectIndex].tasks.first(where: { $0.id == id }) else {
            throw ProjectBoardStoreTestError.unavailable
        }

        let movedTask = ProjectBoardTask(
            id: task.id,
            projectID: projectID,
            title: task.title,
            detail: task.detail,
            status: task.status,
            priority: task.priority,
            dueAt: task.dueAt
        )
        for columnIndex in currentSnapshot.projects[sourceProjectIndex].columns.indices {
            currentSnapshot.projects[sourceProjectIndex].columns[columnIndex].tasks.removeAll { $0.id == id }
        }
        if let targetColumnIndex = currentSnapshot.projects[targetProjectIndex].columns.firstIndex(where: { $0.status == movedTask.status }) {
            currentSnapshot.projects[targetProjectIndex].columns[targetColumnIndex].tasks.insert(movedTask, at: 0)
        }
        return movedTask
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

    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        throw ProjectBoardStoreTestError.unavailable
    }

    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        throw ProjectBoardStoreTestError.unavailable
    }

    func deleteProjectMilestone(id: Int64) throws {
        throw ProjectBoardStoreTestError.unavailable
    }
}

private enum ProjectBoardStoreTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "Project board unavailable"
    }
}

private final class FailingAfterFirstCalendarClient: CalendarClient, @unchecked Sendable {
    private var records: [CalendarEventRecord] = []
    private let lock = NSLock()

    func createEvent(_ draft: CalendarEventDraft) throws -> CalendarEventRecord {
        lock.lock()
        defer { lock.unlock() }
        guard records.isEmpty else {
            throw ToolClientError.invalidRequest("Calendar write failed after the first event.")
        }

        let record = CalendarEventRecord(id: "calendar-event-1", draft: draft)
        records.append(record)
        return record
    }

    func listEvents() throws -> [CalendarEventRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}

private struct FailingMissedTaskReviewStateStore: MissedTaskReviewStateStore {
    func lastReviewedAt(taskID: Int64) throws -> Date? {
        throw ProjectBoardStoreTestError.unavailable
    }

    func markReviewed(taskID: Int64, at date: Date) throws {
        throw ProjectBoardStoreTestError.unavailable
    }

    func lastNotifiedDay() throws -> String? {
        throw ProjectBoardStoreTestError.unavailable
    }

    func recordNotification(day: String, at date: Date) throws {
        throw ProjectBoardStoreTestError.unavailable
    }
}

private struct ProjectBoardFixedDateProvider: DateProvider {
    let now: Date
}
