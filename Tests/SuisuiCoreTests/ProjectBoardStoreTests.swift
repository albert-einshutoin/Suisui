import XCTest
@testable import SuisuiCore

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
        XCTAssertEqual(plannedTasks.first?.dueAt, "2026-06-20")
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
        _ = try stores.tasks.create(
            title: "Recover zero dangling task",
            projectID: 0,
            status: "planned"
        )
        _ = try stores.tasks.create(
            title: "Recover negative dangling task",
            projectID: -7,
            status: "planned"
        )

        let snapshot = try stores.board.loadSnapshot()
        let inbox = try XCTUnwrap(snapshot.projects.first { $0.title == "Inbox" })

        XCTAssertEqual(Set(inbox.column(.planned)?.tasks.map(\.title) ?? []), Set([
            "Recover dangling task",
            "Recover zero dangling task",
            "Recover negative dangling task"
        ]))
        XCTAssertEqual(inbox.subtitle, "3 open / 3 total")
        XCTAssertEqual(Set(try stores.tasks.listAll().compactMap(\.projectID)), Set([99_999, 0, -7]))
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
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/release/checklist.md",
            createdState: .expected
        )
        _ = try stores.artifacts.create(
            taskID: task.id,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/release/notes.md",
            createdState: .created,
            lastModifiedAt: try isoDate("2026-06-19T10:00:00Z")
        )
        _ = try stores.artifacts.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/unlinked.md",
            createdState: .created
        )

        let snapshot = try stores.board.loadSnapshot()
        let loadedProject = try XCTUnwrap(snapshot.projects.first { $0.id == project.id })

        XCTAssertEqual(loadedProject.artifacts.map(\.expectedPath), [
            "/tmp/suisui/release/checklist.md",
            "/tmp/suisui/release/notes.md"
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
            expectedPath: "/tmp/suisui/release-plan.md"
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
            expectedPath: "/tmp/suisui/release/notes.md"
        )

        XCTAssertEqual(artifact.projectID, project.id)
        XCTAssertNil(artifact.taskID)
        XCTAssertEqual(artifact.expectedPath, "/tmp/suisui/release/notes.md")
        XCTAssertEqual(artifact.createdState, .expected)
        XCTAssertEqual(try stores.artifacts.get(id: artifact.id).workspacePath, "/tmp/suisui/release")

        let loadedProject = try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id })
        XCTAssertEqual(loadedProject.artifacts, [artifact])
    }

    func testProjectWorkspacePathCanBeAssignedAndCleared() throws {
        let stores = try makeStoreBundle()
        let project = try stores.board.createProject(title: "Launch Readiness")
        let bookmarkData = Data("local-bookmark".utf8)

        let assigned = try stores.board.setProjectWorkspacePath(
            id: project.id,
            path: "/tmp/suisui-launch",
            bookmarkData: bookmarkData
        )

        XCTAssertTrue(assigned.hasWorkspaceDirectory)
        XCTAssertTrue(assigned.hasWorkspaceBookmark)
        XCTAssertEqual(assigned.workspaceDisplayName, "suisui-launch")
        XCTAssertEqual(try stores.projects.get(id: project.id).workspacePath, "/tmp/suisui-launch")
        XCTAssertEqual(try stores.projects.get(id: project.id).workspaceBookmarkData, bookmarkData)
        let loadedProject = try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id })
        XCTAssertTrue(loadedProject.hasWorkspaceDirectory)
        XCTAssertTrue(loadedProject.hasWorkspaceBookmark)
        XCTAssertEqual(loadedProject.workspacePath, "/tmp/suisui-launch")
        XCTAssertEqual(loadedProject.workspaceDisplayName, "suisui-launch")
        XCTAssertNotEqual(loadedProject.workspaceDisplayName, "/tmp/suisui-launch")

        let cleared = try stores.board.setProjectWorkspacePath(id: project.id, path: nil)

        XCTAssertFalse(cleared.hasWorkspaceDirectory)
        XCTAssertFalse(cleared.hasWorkspaceBookmark)
        XCTAssertNil(cleared.workspaceDisplayName)
        XCTAssertNil(try stores.projects.get(id: project.id).workspacePath)
        XCTAssertNil(try stores.projects.get(id: project.id).workspaceBookmarkData)
        XCTAssertFalse(try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id }).hasWorkspaceDirectory)
        XCTAssertFalse(try XCTUnwrap(stores.board.loadSnapshot().projects.first { $0.id == project.id }).hasWorkspaceBookmark)
    }

    @MainActor
    func testProjectBoardViewModelAssignsProjectWorkspacePathWithoutChangingTasks() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))
        let task = try XCTUnwrap(viewModel.createTask(title: "Keep task", projectID: project.id))

        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/suisui-launch",
            bookmarkData: Data("local-bookmark".utf8),
            projectID: project.id
        ))

        let loadedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        XCTAssertTrue(loadedProject.hasWorkspaceDirectory)
        XCTAssertTrue(loadedProject.hasWorkspaceBookmark)
        XCTAssertEqual(loadedProject.workspaceDisplayName, "suisui-launch")
        XCTAssertNotEqual(loadedProject.workspaceDisplayName, "/tmp/suisui-launch")
        XCTAssertEqual(loadedProject.tasks.map(\.id), [task.id])

        XCTAssertTrue(viewModel.clearProjectWorkspacePath(projectID: project.id))
        XCTAssertFalse(try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id }).hasWorkspaceDirectory)
    }

    @MainActor
    func testProjectBoardViewModelRejectsWorkspacePathWithoutBookmark() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch Readiness"))

        XCTAssertFalse(viewModel.assignProjectWorkspacePath("/tmp/suisui-launch", projectID: project.id))
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
                expectedPath: "/tmp/suisui/release/notes.md"
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
            expectedPath: "/tmp/suisui/release/notes.md"
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
        XCTAssertEqual(inProgressTasks.first?.dueAt, "2026-06-21")
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
        let subject = try makeApprovedAutomationQueueSubject(onChange: { changeCount += 1 })
        let viewModel = subject.viewModel
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

        XCTAssertEqual(changeCount, 2)
        XCTAssertEqual(viewModel.selectedTask?.status, .inProgress)
        XCTAssertNil(viewModel.taskAutomationReviewDecision)
        XCTAssertEqual(try subject.assistantQueueStore.list(filter: .all()).map(\.state), [.done])
    }

    @MainActor
    func testDevelopmentAutomationReadinessRequiresProjectWorkspaceAndOpenTask() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))

        var readiness = viewModel.developmentAutomationReadiness(for: project, task: task)

        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.blockingReason, "Choose a project directory before starting development automation.")
        XCTAssertNil(readiness.branchNamePreview)
        XCTAssertEqual(readiness.allowedFileOperations, ["create", "read", "update"])
        XCTAssertFalse(readiness.allowedFileOperations.contains("delete"))

        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        readiness = viewModel.developmentAutomationReadiness(for: assignedProject, task: currentTask)

        XCTAssertTrue(readiness.isReady)
        XCTAssertNil(readiness.blockingReason)
        XCTAssertEqual(readiness.branchNamePreview, "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback")
        XCTAssertTrue(readiness.reviewSteps.contains("Create a reviewable local branch inside the approved project directory."))
        XCTAssertTrue(readiness.reviewSteps.contains("Run verification before commit, push, or pull request creation."))
        XCTAssertTrue(readiness.reviewSteps.contains("Require explicit approval before git push and GitHub pull request creation."))
        XCTAssertEqual(readiness.lifecycleToolNames, [
            ActionTool.developmentPreparePullRequestWorkflow.rawValue,
            ActionTool.developmentRepositoryListFiles.rawValue,
            ActionTool.developmentRepositoryReadFile.rawValue,
            ActionTool.developmentRepositoryCreateFile.rawValue,
            ActionTool.developmentRepositoryUpdateFile.rawValue,
            ActionTool.developmentRunVerification.rawValue,
            ActionTool.developmentCommitChanges.rawValue,
            ActionTool.developmentPushBranch.rawValue,
            ActionTool.developmentCreatePullRequest.rawValue,
            ActionTool.developmentReviewPullRequestGate.rawValue,
            ActionTool.developmentMergePullRequest.rawValue
        ])
        XCTAssertEqual(
            readiness.approvalBoundaryLabel,
            "Branch preparation starts here; file edits, verification, commit, push, pull request, review, and merge each stay behind explicit approval gates."
        )
    }

    @MainActor
    func testDevelopmentAutomationReadinessRequiresBookmarkBackedWorkspace() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Legacy Workspace"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Prepare branch",
            projectID: project.id,
            status: .planned,
            priority: .medium
        ))
        _ = try stores.projects.updateFields(id: project.id, workspacePath: .set("/tmp/legacy-workspace"))
        viewModel.load()
        let pathOnlyProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        let readiness = viewModel.developmentAutomationReadiness(for: pathOnlyProject, task: currentTask)

        XCTAssertTrue(pathOnlyProject.hasWorkspaceDirectory)
        XCTAssertFalse(pathOnlyProject.hasWorkspaceBookmark)
        XCTAssertFalse(readiness.isReady)
        XCTAssertEqual(readiness.blockingReason, "Choose the project directory again before starting branch automation.")
        XCTAssertNil(viewModel.prepareDevelopmentAutomationReview(for: pathOnlyProject, task: currentTask))
    }

    @MainActor
    func testDevelopmentAutomationReviewPlanUsesApprovalGatedPrepareWorkflow() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        let plan = try XCTUnwrap(viewModel.prepareDevelopmentAutomationReview(for: assignedProject, task: currentTask))
        let action = try XCTUnwrap(plan.actions.first)

        XCTAssertEqual(viewModel.developmentAutomationReviewPlan, plan)
        XCTAssertEqual(plan.riskLevel, .write)
        XCTAssertTrue(plan.requiresApproval)
        XCTAssertEqual(action.tool, .developmentPreparePullRequestWorkflow)
        XCTAssertTrue(action.requiresUserConfirmation)
        XCTAssertEqual(action.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(action.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(action.arguments["branchName"], .string("feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"))
        XCTAssertFalse(plan.actions.contains { $0.tool.rawValue.localizedCaseInsensitiveContains("delete") })
        XCTAssertEqual(viewModel.integrationStatusMessage, "Development branch automation is ready for review.")
    }

    @MainActor
    func testDevelopmentAutomationQueueDraftUsesApprovalGatedPrepareWorkflow() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        XCTAssertTrue(viewModel.enqueueDevelopmentAutomationReview(for: assignedProject, task: currentTask))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(itemID.hasPrefix("action-plan:development-pr-prepare:"))
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.requiredCapabilities, [.tool(.developmentPreparePullRequestWorkflow), .providerExecutionApproval])
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(item.reviewReason, "Development branch automation is ready for Client Portal.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development automation for approval.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .developmentPreparePullRequestWorkflow)
        XCTAssertEqual(action.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(action.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(action.arguments["branchName"], .string("feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"))
        XCTAssertFalse(viewModel.snapshot.projects.first { $0.id == project.id }?.tasks.first?.status == .done)
    }

    @MainActor
    func testDevelopmentAutomationPushQueueDraftUsesSeparateApprovalGate() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"
        let headOID = String(repeating: "a", count: 40)

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-prepare",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-verification",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentRunVerification.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-commit",
            projectID: project.id,
            branchName: branchName,
            commitOID: headOID,
            toolName: ActionTool.developmentCommitChanges.rawValue
        ))

        XCTAssertTrue(viewModel.enqueueDevelopmentPushReview(for: assignedProject, task: currentTask))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(itemID.hasPrefix("action-plan:development-pr-push:"))
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.requiredCapabilities, [.tool(.developmentPushBranch), .providerExecutionApproval])
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(item.reviewReason, "Development branch push needs review for Client Portal.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development branch push review for approval.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertEqual(plan.actions.count, 1)
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .developmentPushBranch)
        XCTAssertEqual(action.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(action.arguments["branchName"], .string(branchName))
        XCTAssertEqual(action.arguments["expectedHeadOID"], .string(headOID))
        XCTAssertTrue(plan.summary.contains("Execution rechecks the current branch, reviewed commit, clean workspace, and GitHub origin before push."))
        XCTAssertTrue(plan.summary.contains("Pull request creation requires a separate approval."))
    }

    @MainActor
    func testDevelopmentAutomationPullRequestCreationQueueDraftRequiresReviewedBaseTitleAndBody() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let draft = try XCTUnwrap(viewModel.developmentPullRequestCreationDraft(for: assignedProject, task: currentTask))
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"
        let headOID = "0123456789abcdef0123456789abcdef01234567"

        XCTAssertEqual(draft.baseBranch, "main")
        XCTAssertEqual(draft.branchName, branchName)
        XCTAssertTrue(draft.title.contains("Implement OAuth callback"))
        XCTAssertTrue(draft.body.contains("Base branch: main"))
        XCTAssertTrue(draft.body.contains("Head branch: \(branchName)"))

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-prepare",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-verification",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentRunVerification.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-commit",
            projectID: project.id,
            branchName: branchName,
            commitOID: headOID,
            toolName: ActionTool.developmentCommitChanges.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-push",
            projectID: project.id,
            branchName: branchName,
            commitOID: headOID,
            toolName: ActionTool.developmentPushBranch.rawValue
        ))

        XCTAssertTrue(viewModel.enqueueDevelopmentPullRequestCreationReview(
            for: assignedProject,
            task: currentTask,
            baseBranch: "feature/phase14-product-completion",
            title: "Add OAuth callback support",
            body: "## Summary\n- Add reviewed OAuth callback support\n"
        ))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(itemID.hasPrefix("action-plan:development-pr-create:"))
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.requiredCapabilities, [.tool(.developmentCreatePullRequest), .providerExecutionApproval])
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(item.reviewReason, "Development pull request creation needs base, title, and body review for Client Portal.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development pull request creation review for approval.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertEqual(plan.actions.count, 1)
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .developmentCreatePullRequest)
        XCTAssertTrue(action.requiresUserConfirmation)
        XCTAssertEqual(action.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(action.arguments["branchName"], .string(branchName))
        XCTAssertEqual(action.arguments["expectedHeadOID"], .string(headOID))
        XCTAssertEqual(action.arguments["baseBranch"], .string("feature/phase14-product-completion"))
        XCTAssertEqual(action.arguments["title"], .string("Add OAuth callback support"))
        XCTAssertEqual(action.arguments["body"], .string("## Summary\n- Add reviewed OAuth callback support\n"))
        XCTAssertTrue(plan.summary.contains("reviewed commit \(headOID)"))
        XCTAssertTrue(plan.summary.contains("Base branch feature/phase14-product-completion"))
        XCTAssertTrue(plan.summary.contains("title and body were reviewed before queueing"))

        let approvedItem = try AssistantQueueStateMachine.approve(
            item,
            reviewerID: "runtime-smoke"
        )
        let approvedSnapshot = AssistantQueueReadModel.snapshot(from: [approvedItem])
        let approvedRow = try XCTUnwrap(approvedSnapshot.rows.first)
        XCTAssertTrue(approvedRow.canRun)

        XCTAssertTrue(viewModel.enqueueDevelopmentPullRequestCreationReview(
            for: assignedProject,
            task: currentTask,
            baseBranch: "feature/phase14-product-completion",
            title: "Add reviewed OAuth callback retry",
            body: "## Summary\n- Add reviewed OAuth callback support after review edits\n"
        ))

        let editedItemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        XCTAssertNotEqual(editedItemID, itemID)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.count, 2)
        let editedItem = try assistantQueueStore.get(id: editedItemID)
        guard case .actionPlan(let editedPlan) = editedItem.payload else {
            return XCTFail("Expected edited action plan payload")
        }
        let editedAction = try XCTUnwrap(editedPlan.actions.first)
        XCTAssertEqual(editedAction.arguments["title"], .string("Add reviewed OAuth callback retry"))
        XCTAssertEqual(
            editedAction.arguments["body"],
            .string("## Summary\n- Add reviewed OAuth callback support after review edits\n")
        )
    }

    @MainActor
    func testDevelopmentAutomationProgressQueuesReviewAndMergeFromReceipts() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let pullRequestURL = "https://github.com/albert-einshutoin/suisui/pull/116"
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"
        let baseBranch = "feature/phase14-product-completion"
        let headOID = "0123456789abcdef0123456789abcdef01234567"

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-prepare",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue
        ))

        let preparedProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertTrue(preparedProgress.canQueueRepositoryEditReview)
        XCTAssertFalse(preparedProgress.canQueueVerificationReview)
        XCTAssertFalse(preparedProgress.canQueueCommitReview)
        XCTAssertFalse(preparedProgress.canQueueBranchPushReview)
        XCTAssertFalse(preparedProgress.canQueuePullRequestCreationReview)
        XCTAssertEqual(preparedProgress.nextApproval?.id, "repository-edit")
        XCTAssertEqual(preparedProgress.nextApproval?.title, "Queue repository edit review")

        XCTAssertTrue(viewModel.enqueueDevelopmentRepositoryEditReview(
            for: assignedProject,
            task: currentTask,
            operation: .create,
            relativePath: "Sources/App/AuthCallback.swift",
            contents: "func handleOAuthCallback() {}\n",
            expectedSHA256: nil
        ))
        let repositoryEditItemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let repositoryEditItem = try assistantQueueStore.get(id: repositoryEditItemID)
        XCTAssertEqual(repositoryEditItem.state, .waitingReview)
        XCTAssertEqual(repositoryEditItem.requiredCapabilities, [
            .tool(.developmentRepositoryCreateFile),
            .providerExecutionApproval
        ])
        guard case .actionPlan(let repositoryEditPlan) = repositoryEditItem.payload else {
            return XCTFail("Expected repository edit action plan payload")
        }
        let repositoryEditAction = try XCTUnwrap(repositoryEditPlan.actions.first)
        XCTAssertEqual(repositoryEditAction.tool, .developmentRepositoryCreateFile)
        XCTAssertEqual(repositoryEditAction.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(repositoryEditAction.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(repositoryEditAction.arguments["branchName"], .string(branchName))
        XCTAssertEqual(repositoryEditAction.arguments["relativePath"], .string("Sources/App/AuthCallback.swift"))
        XCTAssertEqual(repositoryEditAction.arguments["contents"], .string("func handleOAuthCallback() {}\n"))
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development repository edit review for approval.")

        let repositoryEditRow = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == repositoryEditItemID })
        let repositoryEditQueueProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertEqual(repositoryEditQueueProgress.queueHandoff?.id, repositoryEditItemID)
        XCTAssertEqual(repositoryEditQueueProgress.queueHandoff?.state, .waitingReview)
        XCTAssertEqual(repositoryEditQueueProgress.queueHandoff?.title, repositoryEditRow.title)
        XCTAssertFalse(repositoryEditQueueProgress.queueHandoff?.reviewReason.contains("/tmp/client-portal") ?? true)

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-repository-edit",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentRepositoryCreateFile.rawValue
        ))
        try assistantQueueStore.transition(id: repositoryEditItemID) { item in
            let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "tester")
            let running = try AssistantQueueStateMachine.startRunning(approved)
            return try AssistantQueueStateMachine.markDone(running)
        }

        let editedProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertNil(editedProgress.queueHandoff)
        XCTAssertFalse(editedProgress.canQueueRepositoryEditReview)
        XCTAssertTrue(editedProgress.canQueueVerificationReview)
        XCTAssertEqual(editedProgress.nextApproval?.id, "verification-run")
        XCTAssertEqual(editedProgress.nextApproval?.title, "Queue verification review")

        XCTAssertTrue(viewModel.enqueueDevelopmentVerificationReview(for: assignedProject, task: currentTask))
        let verificationItemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let verificationItem = try assistantQueueStore.get(id: verificationItemID)
        XCTAssertEqual(verificationItem.state, .waitingReview)
        XCTAssertEqual(verificationItem.requiredCapabilities, [
            .tool(.developmentRunVerification),
            .providerExecutionApproval
        ])
        guard case .actionPlan(let verificationPlan) = verificationItem.payload else {
            return XCTFail("Expected verification action plan payload")
        }
        let verificationAction = try XCTUnwrap(verificationPlan.actions.first)
        XCTAssertEqual(verificationAction.tool, .developmentRunVerification)
        XCTAssertEqual(verificationAction.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(verificationAction.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(verificationAction.arguments["branchName"], .string(branchName))
        XCTAssertEqual(verificationAction.arguments["commandId"], .string("git.diff_check"))
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development verification review for approval.")

        let verificationRow = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == verificationItemID })
        let verificationQueueProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.id, verificationItemID)
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.state, .waitingReview)
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.stateLabel, "Waiting Review")
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.title, verificationRow.title)
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.reviewReason, verificationItem.reviewReason)
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.canApprove, true)
        XCTAssertEqual(verificationQueueProgress.queueHandoff?.canRun, false)
        XCTAssertFalse(verificationQueueProgress.queueHandoff?.reviewReason.contains("/tmp/client-portal") ?? true)

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-verification",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentRunVerification.rawValue
        ))
        try assistantQueueStore.transition(id: verificationItemID) { item in
            let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "tester")
            let running = try AssistantQueueStateMachine.startRunning(approved)
            return try AssistantQueueStateMachine.markDone(running)
        }

        let verifiedProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertNil(verifiedProgress.queueHandoff)
        XCTAssertFalse(verifiedProgress.canQueueVerificationReview)
        XCTAssertTrue(verifiedProgress.canQueueCommitReview)
        XCTAssertFalse(verifiedProgress.canQueueBranchPushReview)
        XCTAssertFalse(verifiedProgress.canQueuePullRequestCreationReview)
        XCTAssertEqual(verifiedProgress.nextApproval?.id, "commit-changes")
        XCTAssertEqual(verifiedProgress.nextApproval?.title, "Queue commit review")

        XCTAssertTrue(viewModel.enqueueDevelopmentCommitReview(
            for: assignedProject,
            task: currentTask,
            relativePathsText: "Sources/App/AuthCallback.swift\nTests/App/AuthCallbackTests.swift",
            commitMessage: "Add OAuth callback support"
        ))
        let commitItemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let commitItem = try assistantQueueStore.get(id: commitItemID)
        XCTAssertEqual(commitItem.state, .waitingReview)
        XCTAssertEqual(commitItem.requiredCapabilities, [
            .tool(.developmentCommitChanges),
            .providerExecutionApproval
        ])
        guard case .actionPlan(let commitPlan) = commitItem.payload else {
            return XCTFail("Expected commit action plan payload")
        }
        let commitAction = try XCTUnwrap(commitPlan.actions.first)
        XCTAssertEqual(commitAction.tool, .developmentCommitChanges)
        XCTAssertEqual(commitAction.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(commitAction.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(commitAction.arguments["branchName"], .string(branchName))
        XCTAssertEqual(
            commitAction.arguments["relativePaths"],
            .array([
                .string("Sources/App/AuthCallback.swift"),
                .string("Tests/App/AuthCallbackTests.swift")
            ])
        )
        XCTAssertEqual(commitAction.arguments["commitMessage"], .string("Add OAuth callback support"))
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development commit review for approval.")

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-commit",
            projectID: project.id,
            branchName: branchName,
            commitOID: headOID,
            toolName: ActionTool.developmentCommitChanges.rawValue
        ))

        let committedProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertEqual(committedProgress.latestCommitOID, headOID)
        XCTAssertEqual(committedProgress.approvalPreview?.rows.map(\.id), [
            "branch",
            "latest-commit"
        ])
        XCTAssertEqual(committedProgress.approvalPreview?.rows.first { $0.id == "latest-commit" }?.value, headOID)
        XCTAssertFalse(committedProgress.canQueueVerificationReview)
        XCTAssertFalse(committedProgress.canQueueCommitReview)
        XCTAssertTrue(committedProgress.canQueueBranchPushReview)
        XCTAssertFalse(committedProgress.canQueuePullRequestCreationReview)
        XCTAssertEqual(committedProgress.nextApproval?.id, "branch-push")
        XCTAssertEqual(committedProgress.nextApproval?.title, "Queue branch push review")

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-push",
            projectID: project.id,
            branchName: branchName,
            commitOID: headOID,
            toolName: ActionTool.developmentPushBranch.rawValue
        ))

        let pushedProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertTrue(pushedProgress.canQueuePullRequestCreationReview)
        XCTAssertEqual(pushedProgress.nextApproval?.id, "pull-request-create")
        XCTAssertEqual(pushedProgress.nextApproval?.title, "Queue pull request creation review")

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-pr-create",
            projectID: project.id,
            branchName: branchName,
            baseBranch: baseBranch,
            pullRequestURL: pullRequestURL,
            commitOID: headOID,
            toolName: ActionTool.developmentCreatePullRequest.rawValue
        ))

        let progress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)

        XCTAssertEqual(progress.branchName, branchName)
        XCTAssertEqual(progress.pullRequestURL, pullRequestURL)
        XCTAssertEqual(progress.baseBranch, baseBranch)
        XCTAssertEqual(progress.latestCommitOID, headOID)
        XCTAssertEqual(progress.approvalPreview?.rows.map(\.id), [
            "branch",
            "latest-commit",
            "pull-request",
            "base-branch"
        ])
        XCTAssertEqual(progress.approvalPreview?.rows.first { $0.id == "pull-request" }?.value, pullRequestURL)
        XCTAssertEqual(progress.approvalPreview?.rows.first { $0.id == "base-branch" }?.value, baseBranch)
        XCTAssertTrue(progress.canQueuePullRequestReviewGate)
        XCTAssertFalse(progress.canQueuePullRequestMergeGate)
        XCTAssertEqual(progress.nextApproval?.id, "pull-request-review")
        XCTAssertEqual(progress.nextApproval?.title, "Queue pull request review gate")
        XCTAssertEqual(progress.stages.map(\.id), [
            "branch-prepared",
            "repository-edited",
            "verification-run",
            "commit-created",
            "branch-pushed",
            "pull-request-created",
            "pull-request-reviewed",
            "pull-request-merged"
        ])
        XCTAssertEqual(progress.stages.map(\.status), [
            .succeeded,
            .succeeded,
            .succeeded,
            .succeeded,
            .succeeded,
            .succeeded,
            .ready,
            .waiting
        ])

        XCTAssertTrue(viewModel.enqueueDevelopmentPullRequestLifecycleReview(
            for: assignedProject,
            task: currentTask,
            operation: .reviewGate
        ))

        let reviewItemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let reviewItem = try assistantQueueStore.get(id: reviewItemID)
        XCTAssertTrue(reviewItemID.hasPrefix("automation-request:project-development-pr-review:"))
        XCTAssertEqual(reviewItem.state, .waitingReview)
        XCTAssertEqual(reviewItem.riskLevel, .write)
        XCTAssertEqual(reviewItem.requiredCapabilities, [
            .connectedMacRequired,
            .tool(.developmentReviewPullRequestGate),
            .providerExecutionApproval
        ])
        XCTAssertEqual(reviewItem.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development pull request review gate for approval.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [reviewItemID])
        guard case .automationRequest(let reviewRequest) = reviewItem.payload else {
            return XCTFail("Expected automation request payload")
        }
        XCTAssertEqual(reviewRequest.toolName, ActionTool.developmentReviewPullRequestGate.rawValue)
        XCTAssertEqual(reviewRequest.developmentPullRequest, SyncDevelopmentPullRequestPayload(
            projectID: project.id,
            taskID: task.id,
            operation: .reviewGate,
            pullRequestURL: pullRequestURL,
            branchName: branchName,
            baseBranch: baseBranch
        ))
        XCTAssertFalse(reviewItem.redactedSummary.contains("/tmp/client-portal"))

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-pr-review",
            projectID: project.id,
            branchName: branchName,
            baseBranch: baseBranch,
            pullRequestURL: pullRequestURL,
            commitOID: headOID,
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue
        ))

        let mergeProgress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertFalse(mergeProgress.canQueuePullRequestReviewGate)
        XCTAssertTrue(mergeProgress.canQueuePullRequestMergeGate)
        XCTAssertEqual(mergeProgress.nextApproval?.id, "pull-request-merge")
        XCTAssertEqual(mergeProgress.nextApproval?.title, "Queue pull request merge gate")
        XCTAssertEqual(mergeProgress.stages.first { $0.id == "pull-request-reviewed" }?.status, .succeeded)
        XCTAssertEqual(mergeProgress.stages.first { $0.id == "pull-request-merged" }?.status, .ready)

        XCTAssertTrue(viewModel.enqueueDevelopmentPullRequestLifecycleReview(
            for: assignedProject,
            task: currentTask,
            operation: .merge
        ))

        let mergeItemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let mergeItem = try assistantQueueStore.get(id: mergeItemID)
        XCTAssertTrue(mergeItemID.hasPrefix("automation-request:project-development-pr-merge:"))
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.count, 3)
        XCTAssertEqual(mergeItem.requiredCapabilities, [
            .connectedMacRequired,
            .tool(.developmentMergePullRequest),
            .providerExecutionApproval
        ])
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued development pull request merge gate for approval.")
        guard case .automationRequest(let mergeRequest) = mergeItem.payload else {
            return XCTFail("Expected automation request payload")
        }
        XCTAssertEqual(mergeRequest.toolName, ActionTool.developmentMergePullRequest.rawValue)
        XCTAssertEqual(mergeRequest.developmentPullRequest?.operation, .merge)
        XCTAssertEqual(mergeRequest.developmentPullRequest?.taskID, task.id)
        XCTAssertEqual(mergeRequest.developmentPullRequest?.pullRequestURL, pullRequestURL)
    }

    @MainActor
    func testDevelopmentRepositoryEditPreviewSummarizesReviewedInputWithoutRawContents() throws {
        let subject = try makeDevelopmentRepositoryEditPreviewSubject()

        let preview = try XCTUnwrap(subject.viewModel.developmentRepositoryEditPreview(
            for: subject.project,
            task: subject.task,
            operation: .update,
            relativePath: "Sources/App/AuthCallback.swift",
            contents: "func handleOAuthCallback() {}\n",
            expectedSHA256: String(repeating: "a", count: 64)
        ))

        XCTAssertEqual(preview.title, "Repository Edit Preview")
        XCTAssertEqual(preview.rows.first { $0.id == "operation" }?.value, "Update project file")
        XCTAssertEqual(preview.rows.first { $0.id == "relative-path" }?.value, "Sources/App/AuthCallback.swift")
        XCTAssertEqual(preview.rows.first { $0.id == "branch" }?.value, subject.branchName)
        XCTAssertEqual(preview.rows.first { $0.id == "expected-sha" }?.value, String(repeating: "a", count: 12))
        XCTAssertEqual(preview.rows.first { $0.id == "content-summary" }?.value, "1 line / 30 bytes")
        XCTAssertEqual(preview.rows.first { $0.id == "reviewed-change-scope" }?.value, "Reviewed replacement lines: 1")
        XCTAssertEqual(preview.rows.first { $0.id == "reviewed-replacement" }?.value, "Update replacement: Sources/App/AuthCallback.swift (reviewed lines: 1)")
        let digestPrefix = try XCTUnwrap(preview.rows.first { $0.id == "content-digest" }?.value)
        XCTAssertEqual(digestPrefix.count, 12)
        XCTAssertFalse(preview.rows.map(\.value).joined(separator: "\n").contains("handleOAuthCallback"))
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testDevelopmentRepositoryEditPreviewDescribesCreateReplacementWithoutPretendingDiff() throws {
        let subject = try makeDevelopmentRepositoryEditPreviewSubject()

        let preview = try XCTUnwrap(subject.viewModel.developmentRepositoryEditPreview(
            for: subject.project,
            task: subject.task,
            operation: .create,
            relativePath: "Sources/App/NewFeature.swift",
            contents: "struct NewFeature {}\nlet enabled = true\n",
            expectedSHA256: nil
        ))

        XCTAssertEqual(preview.rows.first { $0.id == "operation" }?.value, "Create project file")
        XCTAssertEqual(preview.rows.first { $0.id == "reviewed-change-scope" }?.value, "Reviewed replacement lines: 2")
        XCTAssertEqual(preview.rows.first { $0.id == "reviewed-replacement" }?.value, "Create replacement: Sources/App/NewFeature.swift (reviewed lines: 2)")
        XCTAssertNil(preview.rows.first { $0.id == "expected-sha" })
        let joinedValues = preview.rows.map(\.value).joined(separator: "\n")
        XCTAssertFalse(joinedValues.contains("struct NewFeature"))
        XCTAssertFalse(joinedValues.contains("enabled"))
        XCTAssertFalse(joinedValues.contains("+2 / -0"))
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testDevelopmentRepositoryEditPreviewCountsWhitespaceOnlyReplacementAsReviewedContent() throws {
        let subject = try makeDevelopmentRepositoryEditPreviewSubject()

        let preview = try XCTUnwrap(subject.viewModel.developmentRepositoryEditPreview(
            for: subject.project,
            task: subject.task,
            operation: .create,
            relativePath: "Sources/App/Spacing.swift",
            contents: "   \n",
            expectedSHA256: nil
        ))

        XCTAssertEqual(preview.rows.first { $0.id == "content-summary" }?.value, "1 line / 4 bytes")
        XCTAssertEqual(preview.rows.first { $0.id == "reviewed-change-scope" }?.value, "Reviewed replacement lines: 1")
        XCTAssertEqual(preview.rows.first { $0.id == "reviewed-replacement" }?.value, "Create replacement: Sources/App/Spacing.swift (reviewed lines: 1)")
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testDevelopmentRepositoryEditPreviewFailsClosedForSecretLikeContents() throws {
        let subject = try makeDevelopmentRepositoryEditPreviewSubject()

        let preview = subject.viewModel.developmentRepositoryEditPreview(
            for: subject.project,
            task: subject.task,
            operation: .create,
            relativePath: "Sources/App/AuthCallback.swift",
            contents: "let token = \"sk-proj-abcdefghijklmnopqrstuvwxyz0123456789\"\n",
            expectedSHA256: nil
        )

        XCTAssertNil(preview)
        XCTAssertNil(subject.viewModel.todayCommandFeedback)
        XCTAssertNil(subject.viewModel.errorMessage)
    }

    @MainActor
    func testDevelopmentRepositoryUpdateReviewRequiresExpectedSHA() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Update OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = "feature/suisui-\(project.id)-\(task.id)-update-oauth-callback"

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-prepare",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue
        ))

        XCTAssertTrue(viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask).canQueueRepositoryEditReview)
        XCTAssertFalse(viewModel.enqueueDevelopmentRepositoryEditReview(
            for: assignedProject,
            task: currentTask,
            operation: .update,
            relativePath: "Sources/App/AuthCallback.swift",
            contents: "func handleOAuthCallback() {}\n",
            expectedSHA256: "  "
        ))
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows, [])
        XCTAssertEqual(viewModel.todayCommandFeedback, "Review the repository edit before queueing verification.")
        XCTAssertEqual(viewModel.errorMessage, "Expected SHA is required before queueing a repository update.")

        XCTAssertFalse(viewModel.enqueueDevelopmentRepositoryEditReview(
            for: assignedProject,
            task: currentTask,
            operation: .update,
            relativePath: "Sources/App/AuthCallback.swift",
            contents: "func handleOAuthCallback() {}\n",
            expectedSHA256: "not-a-sha"
        ))
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows, [])
        XCTAssertEqual(viewModel.errorMessage, "Expected SHA must be a 64 character hex digest.")

        XCTAssertTrue(viewModel.enqueueDevelopmentRepositoryEditReview(
            for: assignedProject,
            task: currentTask,
            operation: .update,
            relativePath: "Sources/App/AuthCallback.swift",
            contents: "func handleOAuthCallback() {}\n",
            expectedSHA256: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        ))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let item = try assistantQueueStore.get(id: itemID)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected repository update action plan payload")
        }
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .developmentRepositoryUpdateFile)
        XCTAssertEqual(action.arguments["expectedSHA256"], .string("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"))
    }

    @MainActor
    func testDevelopmentAutomationQueueHandoffIgnoresSplitActionTupleMismatches() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"

        let splitPlan = ActionPlan(
            id: "development-pr-prepare:\(project.id):\(task.id):split-mismatch",
            userInput: "Mismatched queue item",
            summary: "Mismatched queue item",
            actions: [
                PlanAction(
                    id: "wrong-branch",
                    tool: .developmentPreparePullRequestWorkflow,
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string("feature/wrong-branch")
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                ),
                PlanAction(
                    id: "wrong-project",
                    tool: .developmentPreparePullRequestWorkflow,
                    arguments: [
                        "projectId": .number(Double(project.id + 100)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string(branchName)
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        try assistantQueueStore.save(AssistantQueueAdapter.makeItem(
            actionPlan: splitPlan,
            sourceTranscript: splitPlan.userInput,
            interpretationSummary: splitPlan.summary,
            reason: "Split tuple mismatch",
            costPreview: .localOnly()
        ))

        let progress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertNil(progress.queueHandoff)
    }

    @MainActor
    func testDevelopmentAutomationQueueHandoffPrefersFocusedCurrentStageItem() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-prepare",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-repository-edit",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentRepositoryCreateFile.rawValue
        ))

        let olderPlan = ActionPlan(
            id: "development-verification:\(project.id):\(task.id):old",
            userInput: "Older verification review",
            summary: "Older verification review",
            actions: [
                PlanAction(
                    id: "development-verification-old",
                    tool: .developmentRunVerification,
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string(branchName),
                        "commandId": .string("git.diff_check")
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        var olderItem = AssistantQueueAdapter.makeItem(
            actionPlan: olderPlan,
            sourceTranscript: olderPlan.userInput,
            interpretationSummary: olderPlan.summary,
            reason: "Older verification gate",
            costPreview: .localOnly()
        )
        olderItem.state = .blocked
        olderItem.blockingReason = "Older blocked review"
        try assistantQueueStore.save(olderItem)

        XCTAssertTrue(viewModel.enqueueDevelopmentVerificationReview(for: assignedProject, task: currentTask))
        let selectedID = try XCTUnwrap(viewModel.assistantQueueSelectedItemIDs.first)
        let progress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)

        XCTAssertEqual(progress.queueHandoff?.id, selectedID)
        XCTAssertNotEqual(progress.queueHandoff?.id, olderItem.id)
    }

    @MainActor
    func testDevelopmentAutomationQueueHandoffMatchesPullRequestPayloadWithoutRequestIDCoupling() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"
        let baseBranch = "feature/phase14-product-completion"
        let pullRequestURL = "https://github.com/albert-einshutoin/suisui/pull/116"

        for (id, toolName) in [
            ("receipt-prepare", ActionTool.developmentPreparePullRequestWorkflow.rawValue),
            ("receipt-repository-edit", ActionTool.developmentRepositoryCreateFile.rawValue),
            ("receipt-verification", ActionTool.developmentRunVerification.rawValue),
            ("receipt-commit", ActionTool.developmentCommitChanges.rawValue),
            ("receipt-push", ActionTool.developmentPushBranch.rawValue),
            ("receipt-pr-create", ActionTool.developmentCreatePullRequest.rawValue)
        ] {
            try receiptStore.save(developmentAutomationReceipt(
                id: id,
                projectID: project.id,
                branchName: branchName,
                baseBranch: toolName == ActionTool.developmentCreatePullRequest.rawValue ? baseBranch : nil,
                pullRequestURL: toolName == ActionTool.developmentCreatePullRequest.rawValue ? pullRequestURL : nil,
                toolName: toolName
            ))
        }

        let request = SyncAutomationRequestPayload(
            id: "voice-pr-review-request",
            source: .conversation,
            approvalState: .pendingApproval,
            sourceClientID: "voice",
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            redactedArgumentSummary: "Voice requested PR review gate",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: project.id,
                operation: .reviewGate,
                pullRequestURL: pullRequestURL,
                branchName: branchName,
                baseBranch: baseBranch
            )
        )
        let item = AssistantQueueAdapter.makeItem(automationRequest: request)
        try assistantQueueStore.save(item)

        let progress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)
        XCTAssertEqual(progress.queueHandoff?.id, item.id)
    }

    @MainActor
    func testDevelopmentAutomationProgressBlocksLifecycleQueueWithoutReceiptEvidence() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        let progress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)

        XCTAssertFalse(progress.canQueueVerificationReview)
        XCTAssertFalse(progress.canQueueCommitReview)
        XCTAssertFalse(progress.canQueueBranchPushReview)
        XCTAssertFalse(progress.canQueuePullRequestCreationReview)
        XCTAssertFalse(progress.canQueuePullRequestReviewGate)
        XCTAssertFalse(progress.canQueuePullRequestMergeGate)
        XCTAssertEqual(progress.nextApproval?.id, "branch-prepare")
        XCTAssertEqual(progress.nextApproval?.title, "Queue branch automation")
        XCTAssertEqual(
            progress.blockingReason,
            "Queue branch preparation and wait for its execution receipt before verification."
        )
        XCTAssertFalse(viewModel.enqueueDevelopmentPullRequestLifecycleReview(
            for: assignedProject,
            task: currentTask,
            operation: .reviewGate
        ))

        XCTAssertTrue(viewModel.assistantQueueSnapshot.rows.isEmpty)
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Queue branch preparation and wait for its execution receipt before verification."
        )
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testDevelopmentAutomationProgressKeepsLegacyPushedReceiptMovingToPullRequestCreation() throws {
        let stores = try makeStoreBundle()
        let receiptStore = VolatileExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            executionReceiptStore: receiptStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = "feature/suisui-\(project.id)-\(task.id)-implement-oauth-callback"

        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-prepare",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue
        ))
        try receiptStore.save(developmentAutomationReceipt(
            id: "receipt-push",
            projectID: project.id,
            branchName: branchName,
            toolName: ActionTool.developmentPushBranch.rawValue
        ))

        let progress = viewModel.developmentAutomationProgress(for: assignedProject, task: currentTask)

        XCTAssertFalse(progress.canQueueVerificationReview)
        XCTAssertFalse(progress.canQueueCommitReview)
        XCTAssertFalse(progress.canQueueBranchPushReview)
        XCTAssertTrue(progress.canQueuePullRequestCreationReview)
        XCTAssertEqual(progress.nextApproval?.id, "pull-request-create")
        XCTAssertEqual(
            progress.blockingReason,
            "Create the pull request and wait for its execution receipt before queueing review or merge."
        )
    }

    @MainActor
    func testDevelopmentAutomationQueueDraftRedactsSensitiveTaskTitleFromPersistentBranchName() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Fix /Users/alice/Secret Project notes with sk-proj-secret1234567890",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        XCTAssertTrue(viewModel.enqueueDevelopmentAutomationReview(for: assignedProject, task: currentTask))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.arguments["branchName"], .string("feature/suisui-\(project.id)-\(task.id)-task"))
        XCTAssertFalse(String(describing: item).localizedCaseInsensitiveContains("users"))
        XCTAssertFalse(String(describing: item).localizedCaseInsensitiveContains("secret"))
        XCTAssertFalse(String(describing: item).localizedCaseInsensitiveContains("sk-proj"))
    }

    @MainActor
    func testDevelopmentAutomationQueueDraftDoesNotOverwriteExistingAssistantQueueItem() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let plan = try XCTUnwrap(viewModel.prepareDevelopmentAutomationReview(for: assignedProject, task: currentTask))
        var existing = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: "existing development transcript",
            interpretationSummary: "Existing interpretation",
            reason: "Existing approved development review.",
            costPreview: .localOnly()
        )
        existing = try AssistantQueueStateMachine.approve(existing, reviewerID: "tester")
        try assistantQueueStore.save(existing)

        XCTAssertTrue(viewModel.enqueueDevelopmentAutomationReview(for: assignedProject, task: currentTask))

        let stored = try assistantQueueStore.get(id: existing.id)
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.reviewReason, "Existing approved development review.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Development automation is already in Assistant Queue.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [existing.id])
    }

    @MainActor
    func testDevelopmentAutomationQueueDraftRequiresAssistantQueueStore() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned,
            priority: .high
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        XCTAssertFalse(viewModel.enqueueDevelopmentAutomationReview(for: assignedProject, task: currentTask))

        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue is unavailable in this build.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [])
    }

    @MainActor
    func testDevelopmentAutomationReadinessBlocksArchivedCompletedAndClosedTaskStates() throws {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Readonly Project"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Draft implementation",
            projectID: project.id,
            status: .planned,
            priority: .medium
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/readonly-project",
            bookmarkData: Data([4, 5, 6]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        viewModel.selectedTaskID = task.id
        viewModel.moveSelectedTask(to: .blocked)
        let blockedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        let blockedReadiness = viewModel.developmentAutomationReadiness(for: assignedProject, task: blockedTask)

        XCTAssertFalse(blockedReadiness.isReady)
        XCTAssertEqual(blockedReadiness.blockingReason, "Select an open development task before starting branch automation.")

        viewModel.moveSelectedTask(to: .planned)
        viewModel.selectedProjectID = project.id
        viewModel.completeSelectedProject()
        let completedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let openTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        let completedReadiness = viewModel.developmentAutomationReadiness(for: completedProject, task: openTask)

        XCTAssertFalse(completedReadiness.isReady)
        XCTAssertEqual(completedReadiness.blockingReason, "Restore the project before starting development automation.")

        viewModel.restoreSelectedProject()
        viewModel.selectedTaskID = task.id
        viewModel.moveSelectedTask(to: .done)
        let activeProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let doneTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })

        XCTAssertNil(viewModel.prepareDevelopmentAutomationReview(for: activeProject, task: doneTask))
        XCTAssertNil(viewModel.developmentAutomationReviewPlan)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Select an open development task before starting branch automation.")
    }

    @MainActor
    func testProjectBoardViewModelRecordsTaskContentExecutionWhenApprovedAutomationRuns() throws {
        let subject = try makeApprovedAutomationQueueSubject()
        let viewModel = subject.viewModel
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
        XCTAssertTrue(executedTask.detail.contains("Suisui approved automation execution"))
        XCTAssertTrue(executedTask.detail.contains("Run approved plan"))
        XCTAssertEqual(viewModel.todayCommandFeedback, "Executed approved automation for \"Run release note task\".")
        XCTAssertEqual(try subject.assistantQueueStore.list(filter: .all()).map(\.state), [.done])
        XCTAssertEqual(subject.executionReceiptStore.receipts.first?.primaryToolName, ActionTool.taskUpdate.rawValue)
    }

    @MainActor
    func testApprovedAutomationResolvesDeferredCoordinatorFactoryBeforeAvailabilityGate() throws {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let executionReceiptStore = VolatileExecutionReceiptStore()
        let registry = try ToolRegistry(tools: [
            TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: executionReceiptStore
        )
        var coordinatorFactoryCallCount = 0
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinatorFactory: {
                coordinatorFactoryCallCount += 1
                return coordinator
            },
            executionReceiptStore: executionReceiptStore
        )
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Run deferred coordinator task",
            detail: "Resolve the runtime factory only after approval.",
            status: .planned,
            priority: .high
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(coordinatorFactoryCallCount, 1)
        let executedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        XCTAssertEqual(executedTask.status, .inProgress)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testApprovedAutomationRequiresExecutionReceiptStoreBeforeTaskMutation() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Run receipt-gated task",
            detail: "Do not mutate this task without durable audit evidence.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        let unchangedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        XCTAssertEqual(unchangedTask.status, .planned)
        XCTAssertFalse(unchangedTask.detail.contains("Suisui approved automation execution"))
        XCTAssertNil(viewModel.lastApprovedAutomationExecutionReceipt)
        XCTAssertTrue(viewModel.approvedAutomationExecutionReceipts.isEmpty)
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testApprovedAutomationRequiresWritableExecutionReceiptStoreBeforeTaskMutation() throws {
        let subject = try makeApprovedAutomationQueueSubject(
            executionReceiptStore: FailingProjectBoardExecutionReceiptStore()
        )
        let viewModel = subject.viewModel
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Run writable receipt-gated task",
            detail: "Do not mutate this task when receipt persistence fails.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        let unchangedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        XCTAssertEqual(unchangedTask.status, .planned)
        XCTAssertFalse(unchangedTask.detail.contains("Suisui approved automation execution"))
        XCTAssertNil(viewModel.lastApprovedAutomationExecutionReceipt)
        XCTAssertTrue(viewModel.approvedAutomationExecutionReceipts.isEmpty)
        let queueItems = try subject.assistantQueueStore.list(filter: .all())
        XCTAssertEqual(queueItems.map(\.state), [.blocked])
        XCTAssertTrue(queueItems.allSatisfy { !AssistantQueueStateMachine.hasCurrentApproval($0) })
        XCTAssertTrue(queueItems.allSatisfy { $0.blockingReason?.contains("receipt reservation") == true })
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.count, 1)
        XCTAssertTrue(viewModel.assistantQueueSnapshot.rows.allSatisfy { !$0.canApprove && !$0.canRun })
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testApprovedAutomationSurfacesQueueReceiptFailureAfterToolMutation() throws {
        let receiptStore = FailingAfterFirstProjectBoardExecutionReceiptStore()
        let subject = try makeApprovedAutomationQueueSubject(executionReceiptStore: receiptStore)
        let viewModel = subject.viewModel
        viewModel.load()
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Run final receipt failure task",
            detail: "Document the Assistant Queue failure semantics.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22"
        ))
        viewModel.prepareAutomationReviewForSelectedTask()

        viewModel.runApprovedAutomationForSelectedTask()

        XCTAssertEqual(receiptStore.receipts.map(\.status), [.running])
        XCTAssertEqual(try subject.assistantQueueStore.list(filter: .all()).map(\.state), [.failed])
        XCTAssertNil(viewModel.lastApprovedAutomationExecutionReceipt)
        XCTAssertTrue(viewModel.approvedAutomationExecutionReceipts.isEmpty)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Assistant Queue execution finished, but the execution receipt could not be saved. Fix receipt storage before retrying."
        )

        viewModel.load()
        let updatedTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        XCTAssertEqual(updatedTask.status, .inProgress)
        XCTAssertTrue(updatedTask.detail.contains("Suisui approved automation execution"))
    }

    @MainActor
    func testProjectBoardViewModelRecordsRedactedApprovedAutomationExecutionReceipt() throws {
        let subject = try makeApprovedAutomationQueueSubject()
        let viewModel = subject.viewModel
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
        let receiptStore = VolatileExecutionReceiptStore(receipts: [
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
        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()

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
    func testProjectBoardViewModelDefersScopedExecutionReceiptHistoryUntilDetailRequests() throws {
        let firstTask = ProjectBoardTask(
            id: 101,
            projectID: 7,
            title: "First launch task",
            detail: "Should not trigger scoped receipt I/O during load.",
            status: .planned,
            priority: .medium,
            dueAt: nil
        )
        let secondTask = ProjectBoardTask(
            id: 102,
            projectID: 7,
            title: "Second launch task",
            detail: "Keeps the fixture large enough to catch eager per-task loops.",
            status: .planned,
            priority: .medium,
            dueAt: nil
        )
        let project = ProjectBoardProject(
            id: 7,
            title: "Launch performance project",
            status: "active",
            subtitle: "2 open / 2 total",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: status == .planned ? [firstTask, secondTask] : [])
            }
        )
        let receiptStore = CountingProjectBoardExecutionReceiptStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [project])),
            executionReceiptStore: receiptStore
        )

        viewModel.load()

        XCTAssertTrue(receiptStore.scopedListKeys.isEmpty)
        XCTAssertEqual(receiptStore.matchingListCallCount, 0)

        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()

        XCTAssertEqual(receiptStore.matchingListCallCount, 2)

        XCTAssertTrue(viewModel.executionReceiptHistorySnapshot(forTaskID: firstTask.id).rows.isEmpty)
        XCTAssertEqual(receiptStore.scopedListKeys, ["task:101:task_detail"])

        XCTAssertTrue(viewModel.executionReceiptHistorySnapshot(forTaskID: firstTask.id).rows.isEmpty)
        XCTAssertEqual(receiptStore.scopedListKeys, ["task:101:task_detail"])

        XCTAssertTrue(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.isEmpty)
        XCTAssertEqual(receiptStore.scopedListKeys, ["task:101:task_detail", "project:7:project_detail"])
    }

    @MainActor
    func testProjectBoardViewModelLoadsIndexedLargeBoardReadModelsWithoutFullScanPlans() throws {
        let bundle = try makeStoreBundle()
        try seedLargeProjectBoardFixture(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(store: bundle.board)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try isoDate("2026-06-19T12:00:00Z")

        viewModel.load()
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)

        let tasks = viewModel.snapshot.projects.flatMap(\.tasks)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.snapshot.projects.count, 20)
        XCTAssertEqual(tasks.count, 1_000)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.projectsCount, 20)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.inboxCount, 0)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.todayCount, 400)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.scheduleCount, 100)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.doneCount, 100)
        XCTAssertGreaterThan(viewModel.derivedReadModels.sidebarMetrics.catchUpCount, 0)
        XCTAssertEqual(viewModel.derivedReadModels.doneAnalytics.completedTaskCount, 100)
        XCTAssertEqual(viewModel.derivedReadModels.schedule.unscheduledTasks.count, 100)
        XCTAssertEqual(
            viewModel.derivedReadModels.missedTaskReview,
            viewModel.missedTaskReview(on: referenceDate, calendar: calendar)
        )

        try assertQueryPlanSearchesIndex(
            "idx_projects_status",
            tableName: "projects",
            sql: "SELECT id FROM projects WHERE status IN ('active', 'completed') ORDER BY id DESC;",
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_project_id",
            tableName: "tasks",
            sql: """
            SELECT id FROM tasks
            WHERE project_id IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)
            ORDER BY project_id ASC, id ASC;
            """,
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_project_id",
            tableName: "tasks",
            sql: "SELECT id FROM tasks WHERE project_id IS NULL ORDER BY project_id ASC, id ASC;",
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_project_id",
            tableName: "tasks",
            sql: """
            SELECT id FROM tasks
            WHERE project_id IS NOT NULL
              AND project_id NOT IN (SELECT id FROM projects)
            ORDER BY project_id ASC, id ASC;
            """,
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_project_status",
            tableName: "tasks",
            sql: "SELECT id FROM tasks WHERE project_id = 12 AND status = 'planned' ORDER BY id ASC;",
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_due_at_status",
            tableName: "tasks",
            sql: """
            SELECT tasks.id FROM tasks
            LEFT JOIN projects ON tasks.project_id = projects.id
            WHERE tasks.status != 'completed'
              AND tasks.due_at IS NOT NULL
              AND tasks.due_at <= '2026-06-19T23:59:59Z'
              AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived')
            ORDER BY tasks.due_at ASC, tasks.id ASC;
            """,
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_status_due_at",
            tableName: "tasks",
            sql: "SELECT id FROM tasks WHERE status = 'planned' AND due_at <= '2026-06-19T23:59:59Z' ORDER BY due_at ASC;",
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_tasks_completed_at",
            tableName: "tasks",
            sql: "SELECT id FROM tasks WHERE completed_at >= '2026-06-01T00:00:00Z' ORDER BY completed_at DESC LIMIT 12;",
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_artifacts_project_task",
            tableName: "artifacts",
            sql: "SELECT id FROM artifacts WHERE project_id = 12 ORDER BY project_id ASC, task_id ASC, id ASC;",
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_artifacts_project_task",
            tableName: "artifacts",
            sql: """
            SELECT id FROM artifacts
            WHERE project_id IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20)
            ORDER BY project_id ASC, task_id ASC, id ASC;
            """,
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_artifacts_task_project",
            tableName: "artifacts",
            sql: """
            SELECT id FROM artifacts
            WHERE task_id IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
            ORDER BY task_id ASC, project_id ASC, id ASC;
            """,
            connection: bundle.connection
        )
        try assertQueryPlanSearchesIndex(
            "idx_project_milestones_project_due_sort",
            tableName: "project_milestones",
            sql: """
            SELECT id FROM project_milestones
            WHERE project_id IN (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
            ORDER BY project_id ASC, due_at IS NULL, due_at ASC, id ASC;
            """,
            connection: bundle.connection
        )
    }

    @MainActor
    func testProjectBoardViewModelDefersAssistantQueueExecutionCoordinatorUntilRun() throws {
        var coordinatorFactoryCallCount = 0
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            assistantQueueExecutionCoordinatorFactory: {
                coordinatorFactoryCallCount += 1
                return nil
            }
        )

        viewModel.load()

        XCTAssertEqual(coordinatorFactoryCallCount, 0)
        XCTAssertFalse(viewModel.runAssistantQueueItem(
            id: "missing-queue-item",
            expectedMutationRevision: "missing-item-revision"
        ))
        XCTAssertEqual(coordinatorFactoryCallCount, 1)
        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue execution is unavailable in this build.")
    }

    @MainActor
    func testMenuBarQuickCaptureControllerCreatesInboxTaskWithoutProjectBoardViewModelLoad() throws {
        let store = InMemoryProjectBoardStore()
        var didPostChange = false
        let controller = MenuBarQuickCaptureController(store: store) {
            didPostChange = true
        }

        let task = try XCTUnwrap(controller.createInboxTask(title: "  Capture launch follow-up  "))

        XCTAssertEqual(task.title, "Capture launch follow-up")
        XCTAssertEqual(task.status, .backlog)
        XCTAssertNil(controller.errorMessage)
        XCTAssertTrue(didPostChange)

        let snapshot = try store.loadSnapshot(includeArchived: false)
        let inboxProject = try XCTUnwrap(snapshot.projects.first { $0.title == "Inbox" })
        XCTAssertEqual(inboxProject.tasks.map(\.title), ["Capture launch follow-up"])
    }

    @MainActor
    func testMenuBarQuickCaptureControllerDefersStoreFactoryUntilSubmit() throws {
        let store = InMemoryProjectBoardStore()
        var storeFactoryCallCount = 0
        let controller = MenuBarQuickCaptureController(
            storeFactory: {
                storeFactoryCallCount += 1
                return store
            }
        )

        XCTAssertEqual(storeFactoryCallCount, 0)

        let task = try XCTUnwrap(controller.createInboxTask(title: "Deferred capture"))

        XCTAssertEqual(task.title, "Deferred capture")
        XCTAssertEqual(storeFactoryCallCount, 1)

        _ = controller.createInboxTask(title: "Second capture")

        XCTAssertEqual(storeFactoryCallCount, 1)
    }

    @MainActor
    func testMenuBarQuickCaptureControllerRejectsEmptyTitle() throws {
        let controller = MenuBarQuickCaptureController(store: InMemoryProjectBoardStore())

        XCTAssertNil(controller.createInboxTask(title: "   "))
        XCTAssertEqual(controller.errorMessage, "Task title is required.")
    }

    @MainActor
    func testProjectBoardViewModelLoadsExecutionUsageMeterFromReceiptsWithoutRawFields() throws {
        let receiptStore = VolatileExecutionReceiptStore(receipts: [
            ExecutionReceipt(
                id: "receipt-usage-estimated-token=secret",
                runID: "run-usage-estimated",
                createdAt: try isoDate("2026-06-18T08:00:00Z"),
                finishedAt: try isoDate("2026-06-18T08:02:00Z"),
                status: .succeeded,
                inputPreview: "Raw prompt sk-proj-usage-secret from /Users/alice/private.md",
                outputSummary: "Generated plan",
                primaryToolName: ActionTool.taskCreate.rawValue,
                usage: ExecutionReceiptUsage(
                    inputTokens: 1_000,
                    outputTokens: 500,
                    estimatedCostCents: 0.25,
                    currencyCode: "USD",
                    state: .estimated
                ),
                references: [
                    ExecutionReceiptReference(kind: .project, id: "7", label: "Launch token=usage-project-secret"),
                    ExecutionReceiptReference(kind: .task, id: "42", label: "Usage task")
                ],
                visibleSurfaces: [.auditLog, .projectDetail]
            ),
            ExecutionReceipt(
                id: "receipt-usage-measured",
                runID: "run-usage-measured",
                createdAt: try isoDate("2026-06-18T09:00:00Z"),
                finishedAt: try isoDate("2026-06-18T09:02:00Z"),
                status: .succeeded,
                inputPreview: "Provider prompt",
                outputSummary: "Generated follow-up",
                primaryToolName: ActionTool.taskUpdate.rawValue,
                usage: ExecutionReceiptUsage(
                    inputTokens: 300,
                    outputTokens: 100,
                    estimatedCostCents: 0.10,
                    currencyCode: "USD",
                    state: .measured
                ),
                references: [
                    ExecutionReceiptReference(kind: .project, id: "7", label: "Launch token=usage-project-secret")
                ],
                visibleSurfaces: [.auditLog, .projectDetail]
            ),
            ExecutionReceipt(
                id: "receipt-local-only",
                runID: "run-local-only",
                createdAt: try isoDate("2026-06-18T09:05:00Z"),
                status: .succeeded,
                inputPreview: "Local prompt",
                outputSummary: "Local-only action",
                primaryToolName: ActionTool.taskList.rawValue,
                usage: .unavailable,
                visibleSurfaces: [.auditLog]
            )
        ])
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: receiptStore
        )

        viewModel.load()
        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()

        let snapshot = viewModel.executionUsageMeterSnapshot
        XCTAssertNil(snapshot.unavailableMessage)
        XCTAssertTrue(snapshot.scopeLabel.contains("UTC"))
        XCTAssertTrue(snapshot.scopeLabel.contains("500"))
        XCTAssertEqual(snapshot.summary.trackedReceiptCount, 2)
        XCTAssertEqual(snapshot.summary.measuredReceiptCount, 1)
        XCTAssertEqual(snapshot.summary.estimatedReceiptCount, 1)
        XCTAssertEqual(snapshot.summary.inputTokens, 1_300)
        XCTAssertEqual(snapshot.summary.outputTokens, 600)
        XCTAssertEqual(snapshot.summary.totalTokens, 1_900)
        XCTAssertEqual(snapshot.summary.costTotals.first?.currencyCode, "USD")
        XCTAssertEqual(snapshot.summary.costTotals.first?.measuredCostCents ?? -1, 0.10, accuracy: 0.0001)
        XCTAssertEqual(snapshot.summary.costTotals.first?.estimatedCostCents ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(snapshot.dailyRows.map(\.bucketKey), ["2026-06-18"])
        XCTAssertEqual(snapshot.dailyRows.map(\.title), ["2026-06-18 UTC"])
        XCTAssertEqual(snapshot.monthlyRows.map(\.bucketKey), ["2026-06"])
        XCTAssertEqual(snapshot.monthlyRows.map(\.title), ["2026-06 UTC"])

        let projectRow = try XCTUnwrap(snapshot.projectRows.first)
        XCTAssertEqual(projectRow.bucketKey, "project:7")
        XCTAssertTrue(projectRow.title.contains("Launch"))
        XCTAssertEqual(projectRow.summary.totalTokens, 1_900)
        XCTAssertEqual(projectRow.summary.trackedReceiptCount, 2)

        let safeText = [
            snapshot.summaryLabel,
            snapshot.accessibilityValue,
            snapshot.scopeLabel,
            projectRow.title,
            projectRow.accessibilityValue
        ].joined(separator: " ")
        XCTAssertFalse(safeText.contains("receipt-usage-estimated"))
        XCTAssertFalse(safeText.contains("run-usage"))
        XCTAssertFalse(safeText.contains("usage-secret"))
        XCTAssertFalse(safeText.contains("private.md"))
        XCTAssertFalse(safeText.contains("sk-proj"))
    }

    @MainActor
    func testProjectBoardViewModelMarksExecutionUsageMeterUnavailableWithoutReceiptStore() {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())

        viewModel.load()
        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()

        XCTAssertEqual(viewModel.executionUsageMeterSnapshot.summary.trackedReceiptCount, 0)
        XCTAssertEqual(viewModel.executionUsageMeterSnapshot.unavailableMessage, "Execution usage meter is unavailable")
    }

    @MainActor
    func testProjectBoardViewModelShowsExternalMCPReceiptsOnlyInGlobalAuditHistory() throws {
        let externalMCPReceipt = ExecutionReceiptFactory.makeExternalMCPReceipt(
            serverID: "/Users/alice/private-mcp-server",
            serverName: "Private MCP token=mcp-server-secret",
            toolName: "read_status",
            permissionLevel: .read,
            redactedArgumentSummary: "project=string(\"/Users/alice/mcp-input.md\"),api_key=[REDACTED_SECRET]",
            approvalID: "approved",
            source: .developerTool,
            result: MCPToolCallResult(content: [
                MCPContentItem(type: "text", text: "status: ok secret=mcp-output-secret /Users/alice/mcp-output.md")
            ]),
            error: nil,
            runID: "run-board-mcp",
            startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 120)
        )
        let receiptStore = VolatileExecutionReceiptStore(receipts: [externalMCPReceipt])
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
        viewModel.prepareExecutionReceiptHistoryExport(exportedAt: Date(timeIntervalSince1970: 200))

        let globalRow = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot.rows.first)
        XCTAssertEqual(globalRow.toolLabel, "external_mcp.read_status")
        XCTAssertEqual(globalRow.referenceSummary, "References: External MCP 1")
        XCTAssertTrue(globalRow.outcomeSummary.contains("succeeded"))
        XCTAssertTrue(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.isEmpty)
        XCTAssertTrue(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.isEmpty)

        let exportData = try XCTUnwrap(viewModel.executionReceiptHistoryExportData)
        let exportText = String(decoding: exportData, as: UTF8.self)
        XCTAssertTrue(exportText.contains("external_mcp.read_status"))
        XCTAssertFalse(exportText.contains("private-mcp-server"))
        XCTAssertFalse(exportText.contains("mcp-server-secret"))
        XCTAssertFalse(exportText.contains("mcp-input.md"))
        XCTAssertFalse(exportText.contains("mcp-output-secret"))
        XCTAssertFalse(exportText.contains("mcp-output.md"))
        XCTAssertFalse(exportText.contains(externalMCPReceipt.id))
        XCTAssertFalse(exportText.contains(externalMCPReceipt.references.first?.id ?? "missing-reference-id"))
    }

    @MainActor
    func testProjectBoardViewModelHidesNonAuditReceiptsFromDoneHistoryAndExport() throws {
        let receiptStore = VolatileExecutionReceiptStore(receipts: [
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
        let receiptStore = VolatileExecutionReceiptStore(receipts: [
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
        let subject = try makeApprovedAutomationQueueSubject()
        let receiptStore = subject.executionReceiptStore
        let viewModel = subject.viewModel
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

        XCTAssertEqual(receiptStore.receipts.map(\.status), [.running, .succeeded, .succeeded])
        let storedReceipt = try XCTUnwrap(receiptStore.receipts.last { $0.status == .succeeded })
        XCTAssertEqual(storedReceipt.status, .succeeded)
        XCTAssertEqual(storedReceipt.primaryToolName, ActionTool.taskUpdate.rawValue)
        XCTAssertEqual(storedReceipt.visibleSurfaces, [.doneList, .taskDetail, .projectDetail, .auditLog])
        XCTAssertTrue(storedReceipt.inputPreview.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(storedReceipt.inputPreview.contains("approved-history-secret"))

        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()
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
        let receiptStore = VolatileExecutionReceiptStore()
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

        XCTAssertEqual(receiptStore.receipts.map(\.status), [.running, .succeeded])
        let storedReceipt = try XCTUnwrap(receiptStore.receipts.last { $0.status == .succeeded })
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

        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()
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
        let receiptStore = VolatileExecutionReceiptStore(receipts: [scopedReceipt] + newerUnrelatedReceipts + [
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
        let subject = try makeApprovedAutomationQueueSubject()
        let viewModel = subject.viewModel
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
        XCTAssertEqual(try subject.assistantQueueStore.list(filter: .all()).map(\.state), [.done, .done])
    }

    @MainActor
    func testProjectBoardViewModelBuildsTaskAutomationPlanningRequestWithDocumentDeliverables() throws {
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )
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
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )
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
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )
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
    func testDocumentDeliverablesRequireExecutionReceiptStoreBeforeReviewEvidenceIsPrepared() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        _ = viewModel.createTask(
            title: "High receipt-gated documentation task",
            detail: "Prepare reviewed document evidence only when receipts are durable.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        )
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Prepare release notes from selected docs.",
            documents: [
                ScopedAutomationDocument(
                    id: "release",
                    title: "Release source",
                    scope: .appDocs,
                    redactedSummary: "Release evidence.",
                    inclusionReason: "Selected for release notes."
                )
            ]
        )

        XCTAssertThrowsError(
            try viewModel.makeTaskAutomationPlanningRequest(
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
        ) { error in
            XCTAssertEqual(error as? TaskAutoExecutionPlanningRequestError, .executionReceiptStoreUnavailable)
        }
        XCTAssertTrue(viewModel.taskAutomationDocumentDeliverableReviews.isEmpty)
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testDocumentDeliverablesRequireWritableExecutionReceiptStoreBeforeReviewEvidenceIsPrepared() throws {
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: FailingProjectBoardExecutionReceiptStore()
        )
        viewModel.load()
        _ = viewModel.createTask(
            title: "High writable receipt-gated documentation task",
            detail: "Prepare reviewed document evidence only when receipts are durable.",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-21T08:00:00Z"
        )
        let drafts = DocumentAutomationArtifactPlanner().deliverableDrafts(
            userRequest: "Prepare release notes from selected docs.",
            documents: [
                ScopedAutomationDocument(
                    id: "release",
                    title: "Release source",
                    scope: .appDocs,
                    redactedSummary: "Release evidence.",
                    inclusionReason: "Selected for release notes."
                )
            ]
        )

        XCTAssertThrowsError(
            try viewModel.makeTaskAutomationPlanningRequest(
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
        ) { error in
            XCTAssertEqual(error as? TaskAutoExecutionPlanningRequestError, .executionReceiptStoreUnavailable)
        }
        XCTAssertTrue(viewModel.taskAutomationDocumentDeliverableReviews.isEmpty)
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
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
            expectedPath: "/tmp/suisui/release/notes.md",
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
            expectedPath: "/tmp/suisui/release/notes.md",
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
    func testScheduleUnscheduledTaskCanBeAddedToDraftWithoutWritingStoreOrCalendar() throws {
        var changeCount = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9, minute: 10).date)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: calendarClient,
            onChange: { changeCount += 1 }
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Draft"))
        let dueTask = try XCTUnwrap(viewModel.createTask(title: "Today task", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        let unscheduled = try XCTUnwrap(viewModel.createTask(title: "Unscheduled task", projectID: project.id, status: .planned, dueAt: nil))
        changeCount = 0

        let added = viewModel.addUnscheduledTaskToScheduleDraft(
            taskID: unscheduled.id,
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(added)
        XCTAssertEqual(changeCount, 0)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Added \"Unscheduled task\" to the local schedule draft.")
        XCTAssertEqual(viewModel.scheduleDraft?.timeBlocks.map(\.task.id), [dueTask.id, unscheduled.id])
        XCTAssertEqual(viewModel.scheduleDraft?.timeBlocks.map(\.label), ["09:30-10:00", "10:00-10:30"])
        XCTAssertEqual(viewModel.scheduleDraft?.unscheduledTasks.map(\.id), [])
        XCTAssertEqual(viewModel.unscheduledScheduleTasks().map(\.id), [])
        let cockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)
        XCTAssertEqual(cockpit.days.flatMap(\.blocks).map(\.task.id), [dueTask.id, unscheduled.id])
        XCTAssertTrue(cockpit.days.flatMap(\.blocks).allSatisfy { $0.source == .scheduleDraft })
        XCTAssertEqual(cockpit.unscheduledTasks.map(\.id), [])
        XCTAssertNil(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == unscheduled.id }?.dueAt)
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testScheduleUnscheduledTaskDraftActionDoesNotDuplicateExistingDraftBlock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9, minute: 10).date)
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Draft"))
        let unscheduled = try XCTUnwrap(viewModel.createTask(title: "Unscheduled task", projectID: project.id, status: .planned, dueAt: nil))

        XCTAssertTrue(viewModel.addUnscheduledTaskToScheduleDraft(taskID: unscheduled.id, on: referenceDate, calendar: calendar))
        XCTAssertTrue(viewModel.addUnscheduledTaskToScheduleDraft(taskID: unscheduled.id, on: referenceDate, calendar: calendar))

        XCTAssertEqual(viewModel.todayCommandFeedback, "Unscheduled task is already in the schedule draft.")
        XCTAssertEqual(viewModel.scheduleDraft?.timeBlocks.map(\.task.id), [unscheduled.id])
        XCTAssertEqual(viewModel.scheduleDraft?.unscheduledTasks.map(\.id), [])
    }

    @MainActor
    func testScheduleUnscheduledTaskDraftActionRegeneratesStaleDraftForVisibleDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oldReferenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 14, hour: 9, minute: 10).date)
        let visibleReferenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9, minute: 10).date)
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Draft"))
        let oldDueTask = try XCTUnwrap(viewModel.createTask(title: "Old due task", projectID: project.id, status: .planned, dueAt: "2026-06-14"))
        let visibleDueTask = try XCTUnwrap(viewModel.createTask(title: "Visible due task", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        let unscheduled = try XCTUnwrap(viewModel.createTask(title: "Unscheduled task", projectID: project.id, status: .planned, dueAt: nil))

        let staleDraft = viewModel.prepareScheduleDraft(on: oldReferenceDate, calendar: calendar)
        XCTAssertEqual(staleDraft.timeBlocks.map(\.task.id), [oldDueTask.id])

        XCTAssertTrue(viewModel.addUnscheduledTaskToScheduleDraft(taskID: unscheduled.id, on: visibleReferenceDate, calendar: calendar))

        XCTAssertEqual(viewModel.scheduleDraft?.timeBlocks.map(\.task.id), [oldDueTask.id, visibleDueTask.id, unscheduled.id])
        XCTAssertTrue(viewModel.scheduleDraft?.timeBlocks.allSatisfy { $0.startAt?.contains("2026-06-21") == true } ?? false)
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
        XCTAssertEqual(overview.inProgressTaskCount, 1)
        XCTAssertEqual(overview.blockedTaskCount, 1)
        XCTAssertEqual(overview.missedTaskCount, 1)
        XCTAssertEqual(overview.attentionSignalCount, 4)

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
    func testWeeklyScheduleCockpitBuildsGridForecastAndReminderProposalsWithoutCalendarWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-24T09:10:00Z")
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let support = try XCTUnwrap(viewModel.createProject(title: "Support"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Today launch review", projectID: project.id, status: .planned, priority: .high, dueAt: "2026-06-24T11:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Blocked support reply", projectID: support.id, status: .blocked, priority: .medium, dueAt: "2026-06-24T11:15:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Tomorrow implementation", projectID: project.id, status: .inProgress, priority: .medium, dueAt: "2026-06-25T10:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Later done task", projectID: project.id, status: .done, priority: .low, dueAt: "2026-06-26T09:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Unscheduled proposal", projectID: support.id, status: .planned, priority: .high, dueAt: nil))

        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)
        let cockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)

        XCTAssertEqual(cockpit.days.map(\.dateKey), [
            "2026-06-22",
            "2026-06-23",
            "2026-06-24",
            "2026-06-25",
            "2026-06-26",
            "2026-06-27",
            "2026-06-28"
        ])
        XCTAssertEqual(cockpit.unscheduledTasks.map(\.title), ["Unscheduled proposal"])
        XCTAssertEqual(cockpit.agendaDay?.dateKey, "2026-06-24")
        XCTAssertEqual(cockpit.focusForecast.overloadedDayKeys, ["2026-06-24"])

        let wednesday = try XCTUnwrap(cockpit.days.first { $0.dateKey == "2026-06-24" })
        XCTAssertEqual(wednesday.loadLevel, .overloaded)
        XCTAssertEqual(wednesday.reminderProposalCount, 2)
        XCTAssertEqual(wednesday.blocks.map(\.task.title), ["Today launch review", "Blocked support reply"])
        XCTAssertTrue(wednesday.blocks.allSatisfy { $0.source == .scheduleDraft })
        XCTAssertEqual(wednesday.blocks.map(\.overlapGroupSize), [1, 1])
        XCTAssertEqual(wednesday.blocks.map(\.overlapLane), [0, 0])
        XCTAssertEqual(wednesday.blocks.map(\.projectTitle), ["Launch", "Support"])

        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testWeeklyScheduleCockpitAssignsOverlapLanesForDueTimeBlocks() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-24T09:10:00Z")
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = try XCTUnwrap(viewModel.createTask(title: "First overlap", projectID: project.id, status: .planned, priority: .high, dueAt: "2026-06-24T11:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Second overlap", projectID: project.id, status: .planned, priority: .medium, dueAt: "2026-06-24T11:15:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Later block", projectID: project.id, status: .planned, priority: .low, dueAt: "2026-06-24T12:30:00Z"))

        let cockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)

        let wednesday = try XCTUnwrap(cockpit.days.first { $0.dateKey == "2026-06-24" })
        XCTAssertEqual(wednesday.blocks.map(\.source), [.dueTask, .dueTask, .dueTask])
        XCTAssertEqual(wednesday.blocks.map(\.overlapGroupSize), [2, 2, 1])
        XCTAssertEqual(wednesday.blocks.map(\.overlapLane), [0, 1, 0])
        XCTAssertEqual(wednesday.blocks.map(\.startHour), [11, 11, 12].map(Optional.some))
    }

    @MainActor
    func testWeeklyScheduleCockpitHandlesDateOnlyTokyoDayAndDraftDedup() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-23T15:30:00Z")
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Tokyo Launch"))
        let allDay = try XCTUnwrap(viewModel.createTask(title: "Date-only follow-up", projectID: project.id, status: .planned, priority: .medium, dueAt: "2026-06-24"))
        let afterMidnight = try XCTUnwrap(viewModel.createTask(title: "Tokyo after-midnight check", projectID: project.id, status: .planned, priority: .high, dueAt: "2026-06-24T00:15:00+09:00"))

        let dueOnlyCockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)
        let dueOnlyWednesday = try XCTUnwrap(dueOnlyCockpit.days.first { $0.dateKey == "2026-06-24" })

        XCTAssertEqual(dueOnlyCockpit.agendaDay?.dateKey, "2026-06-24")
        XCTAssertEqual(dueOnlyWednesday.blocks.map(\.task.id), [afterMidnight.id, allDay.id])
        XCTAssertEqual(dueOnlyWednesday.blocks.map(\.source), [.dueTask, .dueTask])
        XCTAssertEqual(dueOnlyWednesday.blocks.map(\.startHour), [Optional.some(0), nil])
        XCTAssertEqual(dueOnlyWednesday.blocks.last?.timeLabel, "All day")
        XCTAssertEqual(dueOnlyWednesday.loadLevel, .focused)

        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)
        let draftCockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)
        let draftWednesday = try XCTUnwrap(draftCockpit.days.first { $0.dateKey == "2026-06-24" })

        XCTAssertEqual(draftWednesday.blocks.map(\.task.id), [afterMidnight.id, allDay.id])
        XCTAssertTrue(draftWednesday.blocks.allSatisfy { $0.source == .scheduleDraft })
        XCTAssertFalse(draftWednesday.blocks.contains { $0.source == .dueTask && $0.task.id == allDay.id })
    }

    @MainActor
    func testWeeklyScheduleFocusForecastStatesUseCountsNotLocalizedStrings() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-24T09:10:00Z")
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Forecast"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Focused work", projectID: project.id, status: .planned, priority: .medium, dueAt: "2026-06-24T10:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Heavy work A", projectID: project.id, status: .planned, priority: .medium, dueAt: "2026-06-25T10:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Heavy work B", projectID: project.id, status: .planned, priority: .medium, dueAt: "2026-06-25T11:00:00Z"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Heavy work C", projectID: project.id, status: .planned, priority: .medium, dueAt: "2026-06-25T12:00:00Z"))

        let heavyCockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)

        XCTAssertEqual(heavyCockpit.focusForecast.state, .heavy)
        XCTAssertEqual(heavyCockpit.focusForecast.heavyDayKeys, ["2026-06-25"])
        XCTAssertEqual(heavyCockpit.focusForecast.overloadedDayKeys, [])

        _ = try XCTUnwrap(viewModel.createTask(title: "Overloaded blocker", projectID: project.id, status: .blocked, priority: .high, dueAt: "2026-06-25T13:00:00Z"))
        let overloadedCockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)

        XCTAssertEqual(overloadedCockpit.focusForecast.state, .overloaded)
        XCTAssertEqual(overloadedCockpit.focusForecast.overloadedDayKeys, ["2026-06-25"])
    }

    func testWeeklyScheduleFocusForecastUsesCompletionHistoryForMomentum() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-24T09:10:00Z")
        let thursdayOpenTasks = [
            ProjectBoardTask(id: 1, projectID: 1, title: "Build screen", detail: "", status: .planned, priority: .medium, dueAt: "2026-06-25T10:00:00Z"),
            ProjectBoardTask(id: 2, projectID: 1, title: "Write tests", detail: "", status: .planned, priority: .medium, dueAt: "2026-06-25T11:00:00Z"),
            ProjectBoardTask(id: 3, projectID: 1, title: "Update docs", detail: "", status: .planned, priority: .medium, dueAt: "2026-06-25T12:00:00Z")
        ]
        let completionHistoryTasks = [
            ProjectBoardTask(id: 10, projectID: 1, title: "Ship yesterday carryover", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-25T08:00:00Z"),
            ProjectBoardTask(id: 11, projectID: 1, title: "Close support loop", detail: "", status: .done, priority: .medium, dueAt: "2026-06-24", completedAt: "2026-06-25T09:00:00Z")
        ]
        let tasks = thursdayOpenTasks + completionHistoryTasks
        let project = ProjectBoardProject(
            id: 1,
            title: "Forecast Momentum",
            subtitle: "3 open / 5 total",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: tasks.filter { $0.status == status })
            }
        )
        let snapshot = ProjectBoardSnapshot(projects: [project])
        let workload = DailyWorkloadDashboardBuilder.overview(
            from: snapshot,
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: 7
        )

        let cockpit = WeeklyScheduleCockpitBuilder.cockpit(
            from: snapshot,
            workload: workload,
            scheduleDraft: nil,
            around: referenceDate,
            calendar: calendar
        )

        let thursday = try XCTUnwrap(cockpit.days.first { $0.dateKey == "2026-06-25" })
        XCTAssertEqual(thursday.workload.openTaskCount, 3)
        XCTAssertEqual(thursday.completionHistoryCount, 2)
        XCTAssertEqual(thursday.loadLevel, .heavy)
        XCTAssertEqual(cockpit.focusForecast.state, .heavy)
        XCTAssertEqual(cockpit.focusForecast.completionHistoryCount, 2)
        XCTAssertEqual(cockpit.focusForecast.completedDayKeys, ["2026-06-25"])
        XCTAssertEqual(cockpit.focusForecast.heavyDayKeys, ["2026-06-25"])
    }

    func testWeeklyScheduleCompletionHistoryUsesCalendarDayAndScopedActiveProjects() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-24T16:00:00Z")
        let activeTasks = [
            ProjectBoardTask(id: 20, projectID: 1, title: "SQLite completion", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-24 15:30:00"),
            ProjectBoardTask(id: 21, projectID: 1, title: "Reopened completion", detail: "", status: .planned, priority: .medium, dueAt: nil, completedAt: "2026-06-25T03:00:00+09:00")
        ]
        let inboxTasks = [
            ProjectBoardTask(id: 30, projectID: 2, title: "Inbox completion", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-25T04:00:00+09:00")
        ]
        let archivedTasks = [
            ProjectBoardTask(id: 40, projectID: 3, title: "Archived completion", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-25T05:00:00+09:00")
        ]
        let completedProjectTasks = [
            ProjectBoardTask(id: 50, projectID: 4, title: "Completed project history", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-25T06:00:00+09:00")
        ]
        let active = ProjectBoardProject(
            id: 1,
            title: "Active Completion",
            subtitle: "2 completed",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: activeTasks.filter { $0.status == status })
            }
        )
        let inbox = ProjectBoardProject(
            id: 2,
            title: "Inbox",
            subtitle: "1 completed",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: inboxTasks.filter { $0.status == status })
            }
        )
        let archived = ProjectBoardProject(
            id: 3,
            title: "Archived Completion",
            status: "archived",
            subtitle: "1 completed",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: archivedTasks.filter { $0.status == status })
            }
        )
        let completedProject = ProjectBoardProject(
            id: 4,
            title: "Completed Project",
            status: "completed",
            subtitle: "1 completed",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: completedProjectTasks.filter { $0.status == status })
            }
        )
        let snapshot = ProjectBoardSnapshot(projects: [active, inbox, archived, completedProject])
        let workload = DailyWorkloadDashboardBuilder.overview(
            from: snapshot,
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: 7
        )

        let cockpit = WeeklyScheduleCockpitBuilder.cockpit(
            from: snapshot,
            workload: workload,
            scheduleDraft: nil,
            around: referenceDate,
            calendar: calendar
        )

        let thursday = try XCTUnwrap(cockpit.days.first { $0.dateKey == "2026-06-25" })
        XCTAssertEqual(thursday.completionHistoryCount, 2)
        XCTAssertEqual(cockpit.focusForecast.completionHistoryCount, 2)
        XCTAssertEqual(cockpit.focusForecast.completedDayKeys, ["2026-06-25"])
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
    func testDailyPlanningReviewQueuesStartDraftWithoutMutatingStoreOrCalendar() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Clear overdue blocker",
            projectID: project.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-06-29"
        ))
        _ = viewModel.prepareDailyPlanningReview(
            transcript: "今日やることを確認して",
            on: referenceDate,
            calendar: calendar
        )

        let queued = viewModel.enqueueDailyPlanningActionDraft(
            kind: .startRecommended,
            on: referenceDate,
            calendar: calendar
        )

        let itemID = "action-plan:daily-planning:2026-06-30:startRecommended:task:\(task.id)"
        XCTAssertTrue(queued)
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued Daily Planning Review action for approval.")
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(item.reviewReason, "Daily Planning Review suggested starting Clear overdue blocker.")
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.arguments["status"], .string(ProjectTaskStatus.inProgress.rawValue))
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.blocked)?.tasks.map(\.id), [task.id])
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testDailyPlanningReviewQueuesDeferDraftForTomorrowWithoutCalendarWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Send status draft",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        ))

        let queued = viewModel.enqueueDailyPlanningActionDraft(
            kind: .deferRecommendedToTomorrow,
            transcript: "明日に回す候補を確認して",
            on: referenceDate,
            calendar: calendar
        )

        let itemID = "action-plan:daily-planning:2026-06-30:deferRecommendedToTomorrow:task:\(task.id)"
        XCTAssertTrue(queued)
        let item = try assistantQueueStore.get(id: itemID)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.arguments["dueAt"], .string("2026-07-01"))
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.planned)?.tasks.first?.dueAt, "2026-06-29")
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testDailyPlanningReviewQueuesMoveDueDateToTodayDraftWithoutCalendarWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Review launch notes",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        ))

        let queued = viewModel.enqueueDailyPlanningActionDraft(
            kind: .moveRecommendedDueDateToToday,
            transcript: "今日のレビューでおすすめを今日にリスケして token=voice-secret /Users/shutoide/Private",
            on: referenceDate,
            calendar: calendar
        )

        let itemID = "action-plan:daily-planning:2026-06-30:moveRecommendedDueDateToToday:task:\(task.id)"
        XCTAssertTrue(queued)
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.reviewReason, "Daily Planning Review suggested moving Review launch notes due date to today.")
        XCTAssertEqual(item.requiredCapabilities, [.tool(.taskUpdate), .providerExecutionApproval])
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_LOCAL_PATH]") ?? false)
        XCTAssertFalse(item.sourceTranscript?.contains("voice-secret") ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("/Users/shutoide") ?? true)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertTrue(plan.userInput.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(plan.userInput.contains("[REDACTED_LOCAL_PATH]"))
        XCTAssertFalse(plan.userInput.contains("voice-secret"))
        XCTAssertFalse(plan.userInput.contains("/Users/shutoide"))
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.arguments["dueAt"], .string("2026-06-30"))
        let payloadJSON = try XCTUnwrap(bundle.connection.queryRows(
            "SELECT payload_json FROM assistant_queue_items WHERE id = '\(itemID)' LIMIT 1;"
        ).first?["payload_json"])
        XCTAssertTrue(payloadJSON.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(payloadJSON.contains("[REDACTED_LOCAL_PATH]"))
        XCTAssertFalse(payloadJSON.contains("voice-secret"))
        XCTAssertFalse(payloadJSON.contains("/Users/shutoide"))
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.planned)?.tasks.first?.dueAt, "2026-06-29")
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testDailyPlanningReviewQueuesSplitDraftWithoutTaskMutationOrCalendarWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Prepare launch report",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        ))

        let queued = viewModel.enqueueDailyPlanningActionDraft(
            kind: .splitRecommendedTask,
            transcript: "今日のレビューでおすすめを分割して token=voice-secret file:///Users/shutoide/Private /var/tmp/build ~/vault",
            on: referenceDate,
            calendar: calendar
        )

        let itemID = "action-plan:daily-planning:2026-06-30:splitRecommendedTask:task:\(task.id)"
        XCTAssertTrue(queued)
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.reviewReason, "Daily Planning Review suggested splitting Prepare launch report into reviewable follow-up tasks.")
        XCTAssertEqual(item.requiredCapabilities, [.tool(.taskCreate), .providerExecutionApproval])
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(item.sourceTranscript?.contains("voice-secret") ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("/Users/shutoide") ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("file:///Users") ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("/var/tmp") ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("~/vault") ?? true)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertTrue(plan.actions.allSatisfy { $0.tool == .taskCreate })
        XCTAssertEqual(plan.actions.map { $0.arguments["projectId"] }, [.number(Double(project.id)), .number(Double(project.id))])
        XCTAssertEqual(plan.actions.map { $0.arguments["priority"] }, [.string(ProjectTaskPriority.high.rawValue), .string(ProjectTaskPriority.high.rawValue)])
        XCTAssertEqual(plan.actions.map { $0.arguments["dueAt"] }, [.string("2026-06-29"), .string("2026-06-29")])
        XCTAssertEqual(plan.actions.map { $0.arguments["sourceCommand"] }, [.string("Daily Planning Review split from task \(task.id)"), .string("Daily Planning Review split from task \(task.id)")])
        XCTAssertEqual(plan.actions.map { $0.arguments["title"] }, [
            .string("Prepare launch report - Define next slice"),
            .string("Prepare launch report - Complete remaining work")
        ])
        let payloadJSON = try XCTUnwrap(bundle.connection.queryRows(
            "SELECT payload_json FROM assistant_queue_items WHERE id = '\(itemID)' LIMIT 1;"
        ).first?["payload_json"])
        XCTAssertTrue(payloadJSON.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(payloadJSON.contains("voice-secret"))
        XCTAssertFalse(payloadJSON.contains("/Users/shutoide"))
        XCTAssertFalse(payloadJSON.contains("file:///Users"))
        XCTAssertFalse(payloadJSON.contains("/var/tmp"))
        XCTAssertFalse(payloadJSON.contains("~/vault"))
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.planned)?.tasks.map(\.id), [task.id])
        let taskRows = try bundle.connection.queryRows(
            "SELECT id FROM tasks WHERE project_id = \(project.id) ORDER BY id ASC;"
        )
        XCTAssertEqual(taskRows.map { $0["id"] }, ["\(task.id)"])
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testDailyPlanningReviewDoesNotOverwriteExistingAssistantQueueItem() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Clear overdue blocker",
            projectID: project.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-06-29"
        ))
        let draft = try XCTUnwrap(DailyPlanningActionDraftBuilder.makeDraft(
            kind: .startRecommended,
            review: viewModel.makeDailyPlanningReview(
                transcript: "今日やることを確認して",
                on: referenceDate,
                calendar: calendar
            ),
            task: task,
            referenceDate: referenceDate,
            calendar: calendar
        ))
        let itemID = "action-plan:\(draft.id)"
        var existing = AssistantQueueAdapter.makeItem(
            actionPlan: draft.actionPlan,
            sourceTranscript: "existing transcript",
            interpretationSummary: "Existing summary",
            reason: "Existing approved review.",
            costPreview: .localOnly()
        )
        existing = try AssistantQueueStateMachine.approve(existing, reviewerID: "tester")
        try assistantQueueStore.save(existing)

        let queued = viewModel.enqueueDailyPlanningActionDraft(
            kind: .startRecommended,
            transcript: "今日やることを確認して",
            on: referenceDate,
            calendar: calendar
        )

        let stored = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(queued)
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.reviewReason, "Existing approved review.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Daily Planning Review action is already in Assistant Queue.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
    }

    @MainActor
    func testSyncAutomationRequestIngestQueuesPendingTaskMutationForReview() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Remote Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Update remote status",
            projectID: project.id,
            status: .planned
        ))
        let request = SyncAutomationRequestPayload(
            id: "relay-status-update",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "Set task status to in progress",
            taskMutation: SyncTaskMutationPayload(
                taskID: task.id,
                operation: .update,
                status: ProjectTaskStatus.inProgress.rawValue,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        let ingested = viewModel.ingestAssistantQueueAutomationRequests([request])

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(ingested)
        XCTAssertTrue(itemID.hasPrefix("automation-request:remote-"))
        XCTAssertFalse(itemID.contains(request.id))
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued 1 remote automation request for review.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first?.state, .waitingReview)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first?.canApprove, true)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first?.canRun, false)
        let item = try assistantQueueStore.get(id: itemID)
        guard case .automationRequest(let storedRequest) = item.payload else {
            return XCTFail("Expected automation request payload")
        }
        XCTAssertEqual(storedRequest.id, itemID.replacingOccurrences(of: "automation-request:", with: ""))
        XCTAssertNotEqual(storedRequest.id, request.id)
        XCTAssertEqual(storedRequest.source, request.source)
        XCTAssertEqual(storedRequest.approvalState, request.approvalState)
        XCTAssertEqual(storedRequest.sourceClientID, request.sourceClientID)
        XCTAssertEqual(storedRequest.toolName, request.toolName)
        XCTAssertEqual(storedRequest.redactedArgumentSummary, request.redactedArgumentSummary)
        XCTAssertEqual(storedRequest.taskMutation, request.taskMutation)
    }

    @MainActor
    func testSyncAutomationRequestIngestQueuesDevelopmentPullRequestReviewForReview() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Dev Workflow"))
        let request = SyncAutomationRequestPayload(
            id: "relay-pr-review",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            redactedArgumentSummary: "Review PR before merge",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: project.id,
                operation: .reviewGate,
                pullRequestURL: "https://github.com/albert-einshutoin/suisui/pull/116",
                branchName: "feature/suisui-\(project.id)-merge-gate",
                baseBranch: "feature/phase14-product-completion"
            )
        )

        XCTAssertTrue(viewModel.ingestAssistantQueueAutomationRequests([request]))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        let row = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == itemID })
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertNil(item.blockingReason)
        XCTAssertEqual(row.state, .waitingReview)
        XCTAssertEqual(row.canApprove, true)
        guard case .automationRequest(let storedRequest) = item.payload else {
            return XCTFail("Expected automation request payload")
        }
        XCTAssertEqual(storedRequest.developmentPullRequest, request.developmentPullRequest)
        XCTAssertNil(storedRequest.taskMutation)
        XCTAssertTrue(item.redactedSummary.contains("Development PR: operation=reviewGate"))
    }

    @MainActor
    func testSyncAutomationRequestIngestRedactsExternalMetadataBeforePersistence() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let secret = "sk-meta-secret123"
        let request = SyncAutomationRequestPayload(
            id: "relay-\(secret)",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web token=\(secret)",
            toolName: "\(HostedMCPTaskToolName.taskUpdate.rawValue) token=\(secret)",
            redactedArgumentSummary: "Update remote task api_key=\(secret)",
            taskMutation: SyncTaskMutationPayload(
                taskID: 1,
                operation: .update,
                status: ProjectTaskStatus.inProgress.rawValue,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        XCTAssertTrue(viewModel.ingestAssistantQueueAutomationRequests([request]))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        guard case .automationRequest(let storedRequest) = item.payload else {
            return XCTFail("Expected automation request payload")
        }
        let payloadData = try JSONEncoder().encode(storedRequest)
        let payloadJSON = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        XCTAssertFalse(itemID.contains(secret))
        XCTAssertFalse(storedRequest.id.contains(secret))
        XCTAssertFalse(storedRequest.sourceClientID?.contains(secret) ?? true)
        XCTAssertFalse(storedRequest.toolName?.contains(secret) ?? true)
        XCTAssertFalse(storedRequest.redactedArgumentSummary.contains(secret))
        XCTAssertFalse(item.redactedSummary.contains(secret))
        XCTAssertFalse(payloadJSON.contains(secret))
    }

    @MainActor
    func testSyncAutomationRequestIngestRedactsMalformedDevelopmentPullRequestPayloadBeforePersistence() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let secret = "sk-pr-payload-secret123"
        let localPath = "/Users/shutoide/private/suisui"
        let request = SyncAutomationRequestPayload(
            id: "relay-pr-raw-secret",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            redactedArgumentSummary: "Review PR \(secret)",
            developmentPullRequest: SyncDevelopmentPullRequestPayload(
                projectID: 42,
                operation: .reviewGate,
                pullRequestURL: "https://github.com/albert-einshutoin/suisui/pull/116?token=\(secret)",
                branchName: "feature/suisui-42-\(secret)",
                baseBranch: localPath
            )
        )

        XCTAssertTrue(viewModel.ingestAssistantQueueAutomationRequests([request]))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        let payloadData = try JSONEncoder().encode(item.payload)
        let payloadJSON = try XCTUnwrap(String(data: payloadData, encoding: .utf8))
        XCTAssertEqual(item.state, .blocked)
        XCTAssertFalse(payloadJSON.contains(secret))
        XCTAssertFalse(payloadJSON.contains(localPath))
        XCTAssertFalse(item.redactedSummary.contains(secret))
        XCTAssertFalse(item.redactedSummary.contains(localPath))
    }

    @MainActor
    func testSyncAutomationRequestIngestBlocksMalformedTaskMutationBeforeApproval() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let request = SyncAutomationRequestPayload(
            id: "relay-malformed-mutation",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "Update task without a task id",
            taskMutation: SyncTaskMutationPayload(
                operation: .update,
                status: ProjectTaskStatus.inProgress.rawValue,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        XCTAssertTrue(viewModel.ingestAssistantQueueAutomationRequests([request]))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        let row = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first { $0.id == itemID })
        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.blockingReason, "Remote automation request is missing executable task or development PR details.")
        XCTAssertEqual(row.state, .blocked)
        XCTAssertEqual(row.canApprove, false)
        XCTAssertEqual(row.canRun, false)
    }

    @MainActor
    func testSyncAutomationRequestIngestDoesNotOverwriteExistingQueueReview() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let originalRequest = SyncAutomationRequestPayload(
            id: "relay-existing-review",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskComplete.rawValue,
            redactedArgumentSummary: "Complete task",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .complete,
                status: ProjectTaskStatus.done.rawValue,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )
        XCTAssertTrue(viewModel.ingestAssistantQueueAutomationRequests([originalRequest]))
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        var existing = try assistantQueueStore.get(id: itemID)
        existing.reviewReason = "Existing local review."
        existing = try AssistantQueueStateMachine.approve(existing, reviewerID: "tester")
        try assistantQueueStore.save(existing)
        let changedRemoteRequest = SyncAutomationRequestPayload(
            id: originalRequest.id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskComplete.rawValue,
            redactedArgumentSummary: "Changed remote payload",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .update,
                title: "Remote overwrite attempt",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        let ingested = viewModel.ingestAssistantQueueAutomationRequests([changedRemoteRequest])

        let stored = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(ingested)
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.reviewReason, "Existing local review.")
        XCTAssertEqual(stored.payload, existing.payload)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Remote automation request is already in Assistant Queue.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
    }

    @MainActor
    func testSyncAutomationRequestIngestRequiresAssistantQueueStore() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let request = SyncAutomationRequestPayload(
            id: "relay-without-store",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "Update task",
            taskMutation: SyncTaskMutationPayload(
                taskID: 1,
                operation: .update,
                status: ProjectTaskStatus.inProgress.rawValue,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        let ingested = viewModel.ingestAssistantQueueAutomationRequests([request])

        XCTAssertFalse(ingested)
        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue is unavailable in this build.")
        XCTAssertTrue(viewModel.assistantQueueSnapshot.rows.isEmpty)
    }

    @MainActor
    func testDailyPlanningReviewQueueDraftRequiresAssistantQueueStore() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()

        let queued = viewModel.enqueueDailyPlanningActionDraft(kind: .startRecommended)

        XCTAssertFalse(queued)
        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue is unavailable in this build.")
        XCTAssertTrue(viewModel.assistantQueueSnapshot.rows.isEmpty)
    }

    @MainActor
    func testTodayReminderDraftQueuesReminderActionForReviewWithoutReminderWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let titleSecret = "reminder-secret"
        let project = try XCTUnwrap(viewModel.createProject(title: "Today Reminder Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Renew launch checklist token=\(titleSecret)",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-01T09:00:00Z"
        ))

        let queued = viewModel.enqueueTodayReminderDraft(
            for: task.id,
            sourceTranscript: "リマインダーを作って token=voice-secret",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(queued)
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued Today reminder draft for approval.")
        XCTAssertEqual(viewModel.todayCommandFeedback, "Queued Today reminder draft for approval.")
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(itemID.hasPrefix("action-plan:today-reminder:2026-06-30:"))
        XCTAssertTrue(itemID.hasSuffix(":task:\(task.id)"))
        let idParts = itemID.split(separator: ":").map(String.init)
        XCTAssertEqual(idParts.count, 6)
        XCTAssertEqual(idParts[3].count, 16)
        XCTAssertTrue(idParts[3].allSatisfy(\.isHexDigit))
        XCTAssertFalse(itemID.contains("Renew launch checklist"))
        XCTAssertFalse(itemID.contains(titleSecret))
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.planned)?.tasks.map(\.id), [task.id])

        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.reviewReason, "Today assistant suggested a Reminders draft for 1 task.")
        XCTAssertEqual(item.requiredCapabilities, [.tool(.remindersCreate), .appPermission(.reminders), .providerExecutionApproval])
        XCTAssertFalse(item.redactedSummary.contains(titleSecret))
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(item.sourceTranscript?.contains("voice-secret") ?? true)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertEqual("action-plan:\(plan.id)", itemID)
        XCTAssertFalse(plan.id.contains("Renew launch checklist"))
        XCTAssertFalse(plan.id.contains(titleSecret))
        XCTAssertEqual(plan.requiresApproval, true)
        XCTAssertEqual(plan.riskLevel, .write)
        XCTAssertEqual(plan.actions.map(\.tool), [.remindersCreate])
        XCTAssertEqual(plan.actions.first?.arguments["title"], .string("Reminder for Renew launch checklist token=\(titleSecret)"))
        XCTAssertEqual(plan.actions.first?.arguments["dueAt"], .string("2026-07-01T09:00:00Z"))
        XCTAssertEqual(plan.actions.first?.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(plan.actions.first?.arguments["projectId"], .number(Double(project.id)))
    }

    @MainActor
    func testScheduleReminderDraftQueuesTaskLevelReminderActionForReviewWithoutReminderWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-07-01T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Reminder Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Review proposal before standup",
            projectID: project.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-07-01T10:00:00Z"
        ))

        let cockpit = viewModel.weeklyScheduleCockpit(around: referenceDate, calendar: calendar)
        XCTAssertEqual(cockpit.focusForecast.reminderProposalCount, 1)
        XCTAssertEqual(cockpit.days.first { $0.dateKey == "2026-07-01" }?.reminderProposalCount, 1)

        let queued = viewModel.enqueueScheduleReminderDraft(
            for: task.id,
            sourceTranscript: "Scheduleからリマインダー token=schedule-secret",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(queued)
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued Schedule reminder draft for approval.")
        XCTAssertEqual(viewModel.todayCommandFeedback, "Queued Schedule reminder draft for approval.")
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(itemID.hasPrefix("action-plan:schedule-reminder:2026-07-01:"))
        XCTAssertTrue(itemID.hasSuffix(":task:\(task.id)"))
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.blocked)?.tasks.map(\.id), [task.id])

        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.reviewReason, "Schedule assistant suggested a Reminders draft for 1 task.")
        XCTAssertEqual(item.requiredCapabilities, [.tool(.remindersCreate), .appPermission(.reminders), .providerExecutionApproval])
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(item.sourceTranscript?.contains("schedule-secret") ?? true)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertEqual("action-plan:\(plan.id)", itemID)
        XCTAssertEqual(plan.userInput, "Queue Schedule reminder for approval")
        XCTAssertEqual(plan.summary, "Schedule reminder draft for 1 task.")
        XCTAssertEqual(plan.requiresApproval, true)
        XCTAssertEqual(plan.riskLevel, .write)
        XCTAssertEqual(plan.actions.map(\.tool), [.remindersCreate])
        XCTAssertEqual(plan.actions.first?.id, "schedule-reminder-task-\(task.id)")
        XCTAssertEqual(plan.actions.first?.arguments["title"], .string("Reminder for Review proposal before standup"))
        XCTAssertEqual(plan.actions.first?.arguments["dueAt"], .string("2026-07-01T10:00:00Z"))
        XCTAssertEqual(plan.actions.first?.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(plan.actions.first?.arguments["projectId"], .number(Double(project.id)))
    }

    @MainActor
    func testTodayReminderDraftDoesNotOverwriteExistingQueueItem() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Today Reminder Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Renew launch checklist",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-01T09:00:00Z"
        ))
        XCTAssertTrue(viewModel.enqueueTodayReminderDraft(
            for: task.id,
            sourceTranscript: "初回のリマインダー",
            on: referenceDate,
            calendar: calendar
        ))
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        var existing = try assistantQueueStore.get(id: itemID)
        existing.reviewReason = "Existing approved reminder review."
        existing = try AssistantQueueStateMachine.approve(existing, reviewerID: "tester")
        try assistantQueueStore.save(existing)

        let queued = viewModel.enqueueTodayReminderDraft(
            for: task.id,
            sourceTranscript: "更新されたリマインダー",
            on: referenceDate,
            calendar: calendar
        )

        let stored = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(queued)
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.reviewReason, "Existing approved reminder review.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Today reminder draft is already in Assistant Queue.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
    }

    @MainActor
    func testScheduleReminderDraftDoesNotOverwriteExistingQueueItem() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-07-01T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Reminder Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Review proposal before standup",
            projectID: project.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-07-01T10:00:00Z"
        ))
        XCTAssertTrue(viewModel.enqueueScheduleReminderDraft(
            for: task.id,
            sourceTranscript: "初回のScheduleリマインダー",
            on: referenceDate,
            calendar: calendar
        ))
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(itemID.hasPrefix("action-plan:schedule-reminder:2026-07-01:"))
        var existing = try assistantQueueStore.get(id: itemID)
        existing.reviewReason = "Existing approved schedule reminder review."
        existing = try AssistantQueueStateMachine.approve(existing, reviewerID: "tester")
        try assistantQueueStore.save(existing)

        let queued = viewModel.enqueueScheduleReminderDraft(
            for: task.id,
            sourceTranscript: "更新されたScheduleリマインダー",
            on: referenceDate,
            calendar: calendar
        )

        let stored = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(queued)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.reviewReason, "Existing approved schedule reminder review.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Schedule reminder draft is already in Assistant Queue.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
    }

    @MainActor
    func testTodayReminderDraftRequiresAssistantQueueStore() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()

        let queued = viewModel.enqueueTodayReminderDraft(for: 1)

        XCTAssertFalse(queued)
        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue is unavailable in this build.")
        XCTAssertTrue(viewModel.assistantQueueSnapshot.rows.isEmpty)
    }

    @MainActor
    func testScheduleDraftQueuesCalendarWorkBlocksForReviewWithoutCalendarWrite() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let titleSecret = "calendar-secret"
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Review calendar plan token=\(titleSecret)",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-30"
        ))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let queued = viewModel.enqueueScheduleDraftCalendarApply(
            sourceTranscript: "カレンダーへ入れて",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(queued)
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued Schedule draft Calendar apply for approval.")
        XCTAssertEqual(viewModel.todayCommandFeedback, "Queued Schedule draft Calendar apply for approval.")
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(itemID.hasPrefix("action-plan:schedule-draft-calendar-apply:2026-06-30:"))
        XCTAssertTrue(itemID.hasSuffix(":task:\(task.id)"))
        let idParts = itemID.split(separator: ":").map(String.init)
        XCTAssertEqual(idParts.count, 6)
        XCTAssertEqual(idParts[3].count, 16)
        XCTAssertTrue(idParts[3].allSatisfy(\.isHexDigit))
        XCTAssertFalse(itemID.contains("Review calendar plan"))
        XCTAssertFalse(itemID.contains(titleSecret))
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)

        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.reviewReason, "Schedule draft suggested 1 Calendar work block.")
        XCTAssertEqual(item.requiredCapabilities, [.tool(.calendarCreateWorkBlock), .appPermission(.calendar), .providerExecutionApproval])
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertEqual("action-plan:\(plan.id)", itemID)
        XCTAssertFalse(plan.id.contains("Review calendar plan"))
        XCTAssertFalse(plan.id.contains(titleSecret))
        XCTAssertEqual(plan.actions.map(\.tool), [.calendarCreateWorkBlock])
        XCTAssertEqual(plan.actions.first?.arguments["taskId"], .number(Double(task.id)))
        XCTAssertEqual(plan.actions.first?.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(plan.actions.first?.arguments["title"], .string("Review calendar plan token=\(titleSecret)"))
        XCTAssertEqual(plan.actions.first?.arguments["startAt"], .string("2026-06-30T09:30:00Z"))
        XCTAssertEqual(plan.actions.first?.arguments["durationMinutes"], .number(30))
        XCTAssertEqual(plan.actions.first?.arguments["notes"], .string("Created from a reviewed Suisui schedule draft."))
    }

    @MainActor
    func testScheduleDraftCalendarQueueRequiresAssistantQueueStore() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()

        let queued = viewModel.enqueueScheduleDraftCalendarApply()

        XCTAssertFalse(queued)
        XCTAssertEqual(viewModel.errorMessage, "Assistant Queue is unavailable in this build.")
        XCTAssertTrue(viewModel.assistantQueueSnapshot.rows.isEmpty)
    }

    @MainActor
    func testScheduleDraftCalendarQueueUsesContentDigestSoUpdatedDraftDoesNotReuseStalePayload() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let firstReferenceDate = try isoDate("2026-06-30T09:10:00Z")
        let secondReferenceDate = try isoDate("2026-06-30T11:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Queue"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Review calendar plan",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-30"
        ))

        _ = viewModel.prepareScheduleDraft(on: firstReferenceDate, calendar: calendar)
        XCTAssertTrue(viewModel.enqueueScheduleDraftCalendarApply(on: firstReferenceDate, calendar: calendar))
        let firstItemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let firstItem = try assistantQueueStore.get(id: firstItemID)

        _ = viewModel.prepareScheduleDraft(on: secondReferenceDate, calendar: calendar)
        XCTAssertTrue(viewModel.enqueueScheduleDraftCalendarApply(on: secondReferenceDate, calendar: calendar))
        let ids = viewModel.assistantQueueSnapshot.rows.map(\.id).sorted()
        XCTAssertEqual(ids.count, 2)
        guard ids.count == 2 else {
            return
        }
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("action-plan:schedule-draft-calendar-apply:2026-06-30:") })
        XCTAssertTrue(ids.allSatisfy { $0.hasSuffix(":task:\(task.id)") })
        XCTAssertNotEqual(ids[0], ids[1])

        guard case .actionPlan(let firstPlan) = firstItem.payload else {
            return XCTFail("Expected first action plan payload")
        }
        let secondItemID = try XCTUnwrap(ids.first { $0 != firstItemID })
        let secondItem = try assistantQueueStore.get(id: secondItemID)
        guard case .actionPlan(let secondPlan) = secondItem.payload else {
            return XCTFail("Expected second action plan payload")
        }
        XCTAssertEqual(firstPlan.actions.first?.arguments["startAt"], .string("2026-06-30T09:30:00Z"))
        XCTAssertEqual(secondPlan.actions.first?.arguments["startAt"], .string("2026-06-30T11:30:00Z"))
    }

    @MainActor
    func testScheduleDraftCalendarQueueRedactsSourceTranscriptBeforePersistence() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Schedule Queue"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Review calendar plan",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-30"
        ))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        XCTAssertTrue(viewModel.enqueueScheduleDraftCalendarApply(
            sourceTranscript: "カレンダーに入れて token=voice-secret",
            on: referenceDate,
            calendar: calendar
        ))

        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(item.sourceTranscript?.contains("voice-secret") ?? true)
        let encodedItem = try XCTUnwrap(String(data: JSONEncoder().encode(item), encoding: .utf8))
        XCTAssertFalse(encodedItem.contains("voice-secret"))
    }

    @MainActor
    func testDailyPlanningReviewQueueDraftReportsAssistantQueueSaveFailure() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let calendarClient = InMemoryCalendarClient()
        let assistantQueueStore = SaveFailingProjectBoardAssistantQueueStore(error: AssistantQueueStoreError.saveFailed)
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Queue"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Clear overdue blocker",
            projectID: project.id,
            status: .blocked,
            priority: .high,
            dueAt: "2026-06-29"
        ))

        let queued = viewModel.enqueueDailyPlanningActionDraft(
            kind: .startRecommended,
            transcript: "今日やることを確認して",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(queued)
        XCTAssertEqual(assistantQueueStore.saveAttempts, 1)
        XCTAssertEqual(
            viewModel.errorMessage,
            "Assistant Queue could not save generated work. Confirm local data storage is available, then try again."
        )
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
    }

    @MainActor
    func testDailyPlanningReadoutPlaysReviewWithoutMutatingStoreQueueOrCalendar() async throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let calendarClient = InMemoryCalendarClient()
        let previewer = RecordingDailyPlanningTTSPreviewer()
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore,
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Readout"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Clear billing blocker",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        ))
        let beforeSnapshot = viewModel.snapshot

        let played = await viewModel.playDailyPlanningReviewReadout(
            using: previewer,
            languageCode: "ja",
            voiceID: "af_heart",
            transcript: "今日の計画を読み上げて sk-proj-secret123",
            on: referenceDate,
            calendar: calendar
        )

        let request = try XCTUnwrap(previewer.requests.first)
        XCTAssertTrue(played)
        XCTAssertEqual(previewer.requests.count, 1)
        XCTAssertEqual(request.languageCode, "ja")
        XCTAssertEqual(request.voiceID, "jf_alpha")
        XCTAssertTrue(request.text.contains("朝の計画レビューです。"))
        XCTAssertTrue(request.text.contains("期限切れは1件"))
        XCTAssertTrue(request.text.contains("Clear billing blocker"))
        XCTAssertFalse(request.text.contains("今日の計画を読み上げて"))
        XCTAssertFalse(request.text.contains("sk-proj-secret123"))
        XCTAssertEqual(viewModel.snapshot, beforeSnapshot)
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.planned)?.tasks.map(\.id), [task.id])
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
        XCTAssertTrue(try assistantQueueStore.list(filter: .all()).isEmpty)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Read daily planning review aloud.")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testDailyPlanningReadoutPassesSystemSpeechVoiceIdentifier() async throws {
        let previewer = RecordingDailyPlanningTTSPreviewer()
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()

        let played = await viewModel.playDailyPlanningReviewReadout(
            using: previewer,
            languageCode: "en",
            voiceID: "com.apple.voice.compact.en-US.Samantha",
            provider: .systemSpeech
        )

        XCTAssertTrue(played)
        XCTAssertEqual(
            previewer.requests.first?.voiceID,
            "com.apple.voice.compact.en-US.Samantha"
        )
    }

    @MainActor
    func testDailyPlanningReadoutFailureRedactsSecretsAndLocalPathsWithoutMutating() async throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-06-30T09:10:00Z")
        let calendarClient = InMemoryCalendarClient()
        let secret = "sk-proj-secret123"
        let localPath = "/Users/example/Library/Application Support/Suisui/Voice/speech.wav"
        let previewer = RecordingDailyPlanningTTSPreviewer(
            error: TTSProviderError.unavailable("Kokoro failed at \(localPath) token=\(secret)")
        )
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Daily Readout"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Clear billing blocker",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        ))
        let beforeSnapshot = viewModel.snapshot

        let played = await viewModel.playDailyPlanningReviewReadout(
            using: previewer,
            languageCode: "en",
            voiceID: "af_heart",
            transcript: "Read my day",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertFalse(played)
        XCTAssertEqual(previewer.requests.count, 1)
        XCTAssertEqual(viewModel.snapshot, beforeSnapshot)
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
        XCTAssertNil(viewModel.errorMessage)
        let message = try XCTUnwrap(viewModel.todayCommandFeedback)
        XCTAssertTrue(message.contains("Daily Planning readout failed."))
        XCTAssertTrue(message.contains("[REDACTED_PATH]"))
        XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(message.contains(localPath))
        XCTAssertFalse(message.contains("Application Support"))
        XCTAssertFalse(message.contains("speech.wav"))
        XCTAssertFalse(message.contains(secret))
    }

    @MainActor
    func testScheduleApplyRequiresApprovalBeforeCalendarWrite() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient()
        let receiptStore = VolatileExecutionReceiptStore()
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
    func testScheduleApplyRequiresExecutionReceiptStoreBeforeCalendarWrite() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Receipt Gated Schedule"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        XCTAssertEqual(
            result,
            .failed("Execution receipt storage is unavailable. Fix receipt storage before running approved AI work.")
        )
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
        XCTAssertEqual(viewModel.scheduleApplyResult, result)
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testScheduleApplyRequiresWritableExecutionReceiptStoreBeforeCalendarWrite() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: FailingProjectBoardExecutionReceiptStore(),
            scheduleCalendarClient: calendarClient
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Writable Receipt Gated Schedule"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        XCTAssertEqual(
            result,
            .failed("Execution receipt storage is unavailable. Fix receipt storage before running approved AI work.")
        )
        XCTAssertTrue(try calendarClient.listEvents().isEmpty)
        XCTAssertEqual(viewModel.scheduleApplyResult, result)
        XCTAssertEqual(
            viewModel.todayCommandFeedback,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testScheduleApplyWithoutDraftPreservesValidationResultWhenReceiptStoreIsUnavailable() throws {
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            scheduleCalendarClient: InMemoryCalendarClient()
        )
        viewModel.load()

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        XCTAssertEqual(result, .noDraft)
        XCTAssertEqual(viewModel.scheduleApplyResult, .noDraft)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Create a schedule draft before applying to Calendar.")
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testScheduleApplyWithoutCalendarPreservesValidationResultWhenReceiptStoreIsUnavailable() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "No Calendar Receipt Unavailable"))
        _ = try XCTUnwrap(viewModel.createTask(title: "Calendar block", projectID: project.id, status: .planned, dueAt: "2026-06-21"))
        _ = viewModel.prepareScheduleDraft(on: referenceDate, calendar: calendar)

        let result = viewModel.applyScheduleDraftToCalendar(approvalToken: "approved")

        XCTAssertEqual(result, .calendarNotConfigured)
        XCTAssertEqual(viewModel.scheduleApplyResult, .calendarNotConfigured)
        XCTAssertEqual(viewModel.todayCommandFeedback, "Calendar is not configured. No external write was performed.")
        XCTAssertEqual(
            viewModel.errorMessage,
            "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work."
        )
    }

    @MainActor
    func testScheduleApplyWithoutCalendarBackendDoesNotReturnMockSuccess() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let receiptStore = VolatileExecutionReceiptStore()
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
        let receiptStore = VolatileExecutionReceiptStore()
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
        let receiptStore = VolatileExecutionReceiptStore()
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
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.running, .succeeded])
        let receipt = try XCTUnwrap(receiptStore.receipts.last { $0.status == .succeeded })
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

        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()
        let globalRow = try XCTUnwrap(viewModel.executionReceiptHistorySnapshot.rows.first)
        XCTAssertEqual(globalRow.status, .succeeded)
        XCTAssertEqual(globalRow.toolLabel, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertTrue(globalRow.referenceSummary.contains("Calendar Event 1"))
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.map(\.status), [.succeeded, .running])
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.map(\.status), [.succeeded, .running])
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.map(\.toolLabel), [
            ActionTool.calendarCreateWorkBlock.rawValue,
            ActionTool.calendarCreateWorkBlock.rawValue
        ])
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.map(\.toolLabel), [
            ActionTool.calendarCreateWorkBlock.rawValue,
            ActionTool.calendarCreateWorkBlock.rawValue
        ])
    }

    @MainActor
    func testScheduleApplyPersistsFailedExecutionReceiptWhenCalendarWriteFails() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = InMemoryCalendarClient(authorizationStatus: .denied)
        let receiptStore = VolatileExecutionReceiptStore()
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
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.running, .failed])
        let receipt = try XCTUnwrap(receiptStore.receipts.last { $0.status == .failed })
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.primaryToolName, ActionTool.calendarCreateWorkBlock.rawValue)
        XCTAssertEqual(receipt.references.map(\.kind), [.task, .project])
        XCTAssertTrue(receipt.actions.contains { $0.status == .failed && ($0.errorSummary?.contains("Calendar permission is denied") ?? false) })
        viewModel.refreshExecutionReceiptAuditSnapshotsIfNeeded()
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot.rows.first?.status, .failed)
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forTaskID: task.id).rows.map(\.status), [.failed, .running])
    }

    @MainActor
    func testScheduleApplyPersistsPartialFailureReceiptAfterCreatedCalendarEvent() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try XCTUnwrap(DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 6, day: 21, hour: 9).date)
        let calendarClient = FailingAfterFirstCalendarClient()
        let receiptStore = VolatileExecutionReceiptStore()
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
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.running, .failed])
        let receipt = try XCTUnwrap(receiptStore.receipts.last { $0.status == .failed })
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.references.filter { $0.kind == .calendarEvent }.map(\.id), ["calendar-event-1"])
        XCTAssertEqual(receipt.actions.map(\.status), [.succeeded, .failed])
        XCTAssertTrue(receipt.references.contains { $0.kind == .task && $0.id == String(firstTask.id) })
        XCTAssertTrue(receipt.references.contains { $0.kind == .task && $0.id == String(secondTask.id) })
        XCTAssertEqual(viewModel.executionReceiptHistorySnapshot(forProjectID: project.id).rows.map(\.status), [.failed, .running])
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
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/voice-filter.m4a",
            durationSeconds: 5,
            transcript: "Call supplier",
            interpretationSummary: nil,
            memo: nil,
            transcriptionStatus: .succeeded
        ))
        let suggested = try XCTUnwrap(viewModel.createInboxTask(title: "AI suggested capture"))
        _ = try captures.createVoiceCapture(InboxVoiceCaptureDraft(
            taskID: suggested.id,
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/ai-filter.m4a",
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
    func testInboxTriageCountUsesCachedCapturesWithoutRefreshingStore() throws {
        let captureStore = CountingInboxCaptureStore()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            inboxCaptureStore: captureStore
        )
        viewModel.load()
        let manual = try XCTUnwrap(viewModel.createInboxTask(title: "Manual capture"))
        let voice = try XCTUnwrap(viewModel.createInboxTask(title: "Voice capture"))
        captureStore.recordsByTaskID[voice.id] = [
            InboxCaptureRecord(
                id: 1,
                taskID: voice.id,
                sourceKind: .voiceMemo,
                audioFilePath: "/tmp/suisui-inbox-voice.m4a",
                durationSeconds: 4,
                transcript: "Follow up",
                interpretationSummary: "Likely task: follow up",
                memo: nil,
                classificationStatus: .unclassified,
                transcriptionStatus: .succeeded,
                createdAt: "2026-07-05T00:00:00Z"
            )
        ]
        viewModel.load()
        let batchListCallCountAfterLoad = captureStore.batchListCallCount
        let singleListCallCountAfterLoad = captureStore.singleListCallCount

        XCTAssertEqual(viewModel.inboxTriageCount(for: .all), 2)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .voice), 1)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .aiSuggested), 1)
        XCTAssertEqual(viewModel.inboxTriageCount(for: .manual), 1)
        XCTAssertEqual(viewModel.filteredInboxTasks.map(\.id), [voice.id, manual.id])
        XCTAssertEqual(captureStore.batchListCallCount, batchListCallCountAfterLoad)
        XCTAssertEqual(captureStore.singleListCallCount, singleListCallCountAfterLoad)
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
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/selection-filter.m4a",
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
            audioFilePath: "/Users/example/Library/Application Support/Suisui/InboxAudio/no-ai-suggestion.m4a",
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
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
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
        let completedToday = try XCTUnwrap(viewModel.createTask(
            title: "Publish shipped update",
            projectID: launch.id,
            status: .done,
            priority: .low,
            dueAt: "2026-06-19T13:00:00Z"
        ))
        let legacyDoneWithoutCompletedAt = try XCTUnwrap(viewModel.createTask(
            title: "Legacy done due today",
            projectID: launch.id,
            status: .done,
            priority: .low,
            dueAt: "2026-06-19T14:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        try bundle.connection.execute("UPDATE tasks SET completed_at = '2026-06-19T13:05:00Z' WHERE id = \(completedToday.id);")
        try bundle.connection.execute("UPDATE tasks SET completed_at = NULL WHERE id = \(legacyDoneWithoutCompletedAt.id);")
        viewModel.load()
        XCTAssertTrue(viewModel.enqueueTodayReminderDraft(
            for: selected.id,
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        ))
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
        XCTAssertEqual(context.subtaskSummary, "2 open Today tasks, 1 done today.")
        XCTAssertEqual(context.reminderSummary, "Reminder draft is waiting for approval.")
    }

    @MainActor
    func testProjectBoardViewModelUsesCurrentTodayReminderDraftStateForRailContext() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
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

        XCTAssertTrue(viewModel.enqueueTodayReminderDraft(
            for: selected.id,
            on: try isoDate("2026-06-18T08:37:00Z"),
            calendar: calendar
        ))
        var context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )
        XCTAssertEqual(context.reminderSummary, "No Today reminder draft queued.")

        XCTAssertTrue(viewModel.enqueueTodayReminderDraft(
            for: selected.id,
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        ))
        let currentItemID = try XCTUnwrap(try assistantQueueStore.list(filter: .all(limit: 500)).map(\.id).first { id in
            id.hasPrefix("action-plan:today-reminder:2026-06-19:")
                && id.hasSuffix(":task:\(selected.id)")
        })
        try assistantQueueStore.save(
            AssistantQueueStateMachine.deferItem(
                try assistantQueueStore.get(id: currentItemID)
            )
        )

        context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.reminderSummary, "Reminder draft is deferred.")
    }

    @MainActor
    func testProjectBoardViewModelBuildsTodayAssistantRailContextFromRecommendedTask() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Ship today update",
            detail: "Prepare release note",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.selectedTaskID = nil

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .recommended)
        XCTAssertEqual(context.task?.title, "Ship today update")
        XCTAssertEqual(context.projectTitle, "Launch")
        XCTAssertEqual(context.nextActionTitle, "Start recommended task")
        XCTAssertEqual(context.nextActionReason, "Earliest due task keeps today on track.")
        XCTAssertEqual(context.nextBlockLabel, "09:00-09:30")
        XCTAssertEqual(context.notes, "Prepare release note")
    }

    @MainActor
    func testProjectBoardViewModelBuildsTodayWorkflowSnapshotFromOneReferenceDateAndCalendar() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let localToday = try XCTUnwrap(viewModel.createTask(
            title: "Close June report",
            detail: "Date-only task should stay in the same snapshot as Today rail.",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-30"
        ))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "July follow-up",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-01T09:00:00Z"
        ))
        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        let snapshot = viewModel.todayWorkflowSnapshot(
            on: try isoDate("2026-07-01T06:30:00Z"),
            calendar: pacificCalendar
        )

        XCTAssertEqual(snapshot.plan.tasks.map(\.id), [localToday.id])
        XCTAssertEqual(snapshot.plan.dueTodayCount, 1)
        XCTAssertEqual(snapshot.plan.overdueCount, 0)
        XCTAssertEqual(snapshot.plan.recommendedTask?.id, localToday.id)
        XCTAssertEqual(snapshot.assistantContext.source, .recommended)
        XCTAssertEqual(snapshot.assistantContext.task?.id, localToday.id)
        XCTAssertEqual(snapshot.assistantContext.nextBlockLabel, "23:30-00:00")
        XCTAssertTrue(snapshot.recommendationChips.allSatisfy { chip in
            snapshot.plan.tasks.contains { $0.id == chip.taskID }
        })
    }

    @MainActor
    func testDerivedTodayWorkflowPrecomputesDailyReviewAndReusesItForSelectionRefresh() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Review launch plan",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-10"
        ))
        let referenceDate = try isoDate("2026-07-10T09:00:00Z")
        let calendar = utcCalendar()

        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        let firstPreview = try XCTUnwrap(viewModel.derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview)
        let firstPlan = viewModel.derivedReadModels.todayWorkflowSnapshot.plan
        let firstChips = viewModel.derivedReadModels.todayWorkflowSnapshot.recommendationChips

        viewModel.selectedTaskID = nil
        viewModel.selectedTaskID = task.id

        XCTAssertEqual(
            viewModel.derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview,
            firstPreview
        )
        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.plan, firstPlan)
        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.recommendationChips, firstChips)
        XCTAssertEqual(
            viewModel.derivedReadModels.todayWorkflowSnapshot.planningDayKey,
            PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        )
    }

    @MainActor
    func testRepeatedLoadOfTheSameSnapshotDoesNotAdvanceTodayPreviewRevision() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let firstRevision = viewModel.todaySnapshotSourceRevision

        viewModel.load()

        XCTAssertEqual(viewModel.todaySnapshotSourceRevision, firstRevision)
    }

    @MainActor
    func testPublicTodayWorkflowSnapshotUsesItsRealPlanningDayKey() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        let referenceDate = try isoDate("2026-07-10T12:01:00Z")
        let calendar = utcCalendar()

        let snapshot = viewModel.todayWorkflowSnapshot(on: referenceDate, calendar: calendar)

        XCTAssertEqual(
            snapshot.planningDayKey,
            PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        )
        XCTAssertNotEqual(snapshot.planningDayKey, .empty)
    }

    @MainActor
    func testDailyReviewPreviewInvalidatesAfterTaskMutationAndCompletedVisibilityChange() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Ship launch",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-10"
        ))
        let referenceDate = try isoDate("2026-07-10T09:00:00Z")
        let calendar = utcCalendar()
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        XCTAssertEqual(
            viewModel.derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview?.recommendedTaskID,
            task.id
        )

        viewModel.moveTask(id: task.id, to: .done)
        XCTAssertNil(viewModel.derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview?.recommendedTaskID)

        viewModel.setShowsCompletedWorkflowTasks(true)
        XCTAssertEqual(
            viewModel.derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview?.recommendedTaskID,
            task.id
        )
    }

    @MainActor
    func testDailyReviewPreviewInvalidatesAcrossLocalDayDSTAndTimezoneBoundaries() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Observe day boundary",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-03-08"
        ))
        var newYorkCalendar = Calendar(identifier: .gregorian)
        newYorkCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let beforeDSTBoundary = try isoDate("2026-03-08T06:30:00Z")
        let afterDSTBoundary = try isoDate("2026-03-09T05:30:00Z")

        viewModel.refreshDerivedReadModels(on: beforeDSTBoundary, calendar: newYorkCalendar)
        let beforeKey = viewModel.derivedReadModels.todayWorkflowSnapshot.planningDayKey
        viewModel.refreshDerivedReadModels(on: afterDSTBoundary, calendar: newYorkCalendar)
        let afterKey = viewModel.derivedReadModels.todayWorkflowSnapshot.planningDayKey

        XCTAssertNotEqual(beforeKey, afterKey)
        XCTAssertEqual(afterKey.timeZoneIdentifier, "America/New_York")

        var tokyoCalendar = Calendar(identifier: .gregorian)
        tokyoCalendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        viewModel.refreshDerivedReadModels(on: afterDSTBoundary, calendar: tokyoCalendar)
        let tokyoKey = viewModel.derivedReadModels.todayWorkflowSnapshot.planningDayKey
        XCTAssertNotEqual(afterKey, tokyoKey)
        XCTAssertEqual(tokyoKey.timeZoneIdentifier, "Asia/Tokyo")
    }

    @MainActor
    func testExplicitDailyPlanningReviewAlwaysWinsOverDerivedPreview() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Prepare readout",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-10"
        ))
        let referenceDate = try isoDate("2026-07-10T09:00:00Z")
        let calendar = utcCalendar()
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        let preview = try XCTUnwrap(viewModel.derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview)

        let explicit = viewModel.prepareDailyPlanningReview(
            transcript: "explicit voice review",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertNotEqual(explicit, preview)
        XCTAssertEqual(viewModel.currentDailyPlanningReview, explicit)
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        XCTAssertEqual(viewModel.currentDailyPlanningReview, explicit)
    }

    @MainActor
    func testProjectBoardViewModelBuildsTodayAssistantRailContextFromFocusedTask() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let focused = try XCTUnwrap(viewModel.createTask(
            title: "Write launch memo",
            detail: "Keep the current focus visible",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T11:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.startFocus(taskID: focused.id)
        viewModel.selectedTaskID = nil

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .focused)
        XCTAssertEqual(context.task?.title, "Write launch memo")
        XCTAssertEqual(context.projectTitle, "Launch")
        XCTAssertEqual(context.nextActionTitle, "Resume focused task")
        XCTAssertEqual(context.nextActionReason, "This task is already in focus.")
        XCTAssertEqual(context.notes, "Keep the current focus visible")
    }

    @MainActor
    func testProjectBoardDerivedTodayReadModelRefreshesWhenFocusChanges() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let recommended = try XCTUnwrap(viewModel.createTask(
            title: "Fix launch blocker",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-19T09:00:00Z"
        ))
        let focused = try XCTUnwrap(viewModel.createTask(
            title: "Write launch memo",
            detail: "Keep the current focus visible",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T11:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.selectedTaskID = nil
        viewModel.refreshDerivedReadModels(on: try isoDate("2026-06-19T08:37:00Z"), calendar: calendar)

        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.assistantContext.source, .recommended)
        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.assistantContext.task?.id, recommended.id)

        viewModel.startFocus(taskID: focused.id)

        let context = viewModel.derivedReadModels.todayWorkflowSnapshot.assistantContext
        XCTAssertEqual(context.source, .focused)
        XCTAssertEqual(context.task?.id, focused.id)
        XCTAssertEqual(context.nextActionTitle, "Resume focused task")
    }

    @MainActor
    func testProjectBoardScheduleReadModelRefreshKeepsTodaySnapshotAnchored() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let todayTask = try XCTUnwrap(viewModel.createTask(
            title: "Today launch check",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-19T09:00:00Z"
        ))
        let nextWeekTask = try XCTUnwrap(viewModel.createTask(
            title: "Next week launch check",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-26T09:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try isoDate("2026-06-19T08:37:00Z")
        let nextWeek = try isoDate("2026-06-26T08:37:00Z")
        viewModel.selectedTaskID = nil
        viewModel.refreshDerivedReadModels(on: today, calendar: calendar)

        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.plan.tasks.map(\.id), [todayTask.id])
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.todayCount, 1)

        viewModel.refreshScheduleReadModel(around: nextWeek, calendar: calendar)

        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.plan.tasks.map(\.id), [todayTask.id])
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.todayCount, 1)
        XCTAssertTrue(viewModel.derivedReadModels.schedule.workloadOverview.days.contains { day in
            calendar.isDate(day.date, inSameDayAs: nextWeek)
                && day.projectContributions.contains { contribution in
                    contribution.tasks.contains { $0.id == nextWeekTask.id }
                }
        })
    }

    @MainActor
    func testProjectBoardInitialLoadAndImplicitRefreshUseInjectedReadModelClock() throws {
        let store = InMemoryProjectBoardStore()
        let seedingViewModel = ProjectBoardViewModel(store: store)
        seedingViewModel.load()
        let project = try XCTUnwrap(seedingViewModel.createProject(title: "Deterministic capture"))
        let task = try XCTUnwrap(seedingViewModel.createTask(
            title: "Pinned Today task",
            projectID: project.id,
            status: .planned,
            dueAt: "2026-07-10T09:00:00Z"
        ))
        let referenceInstant = try isoDate("2026-07-10T12:00:00Z")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        var calendarRequestCount = 0
        let viewModel = ProjectBoardViewModel(
            store: store,
            readModelNow: { referenceInstant },
            readModelCalendar: {
                calendarRequestCount += 1
                return calendar
            }
        )

        viewModel.load()

        XCTAssertEqual(viewModel.derivedReadModels.builtAt, referenceInstant)
        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.plan.tasks.map(\.id), [task.id])
        let captureDay = viewModel.derivedReadModels.schedule.workloadOverview.days.first {
            $0.dateKey == "2026-07-10"
        }
        let captureDayTaskIDs = try XCTUnwrap(captureDay).projectContributions
            .flatMap(\.tasks)
            .map(\.id)
        XCTAssertTrue(captureDayTaskIDs.contains(task.id))

        let calendarRequestCountBeforeRefresh = calendarRequestCount
        viewModel.refreshDerivedReadModels()

        XCTAssertEqual(viewModel.derivedReadModels.builtAt, referenceInstant)
        XCTAssertEqual(viewModel.derivedReadModels.todayWorkflowSnapshot.plan.tasks.map(\.id), [task.id])
        XCTAssertGreaterThan(calendarRequestCount, calendarRequestCountBeforeRefresh)
    }

    @MainActor
    func testProjectBoardViewModelPrefersFocusedTaskWhenBuildingTodayAssistantRailContext() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let selected = try XCTUnwrap(viewModel.createTask(
            title: "Selected due item",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-19T09:00:00Z"
        ))
        let focused = try XCTUnwrap(viewModel.createTask(
            title: "Focused due item",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.startFocus(taskID: focused.id)
        viewModel.selectedTaskID = selected.id

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .focused)
        XCTAssertEqual(context.task?.title, "Focused due item")
    }

    @MainActor
    func testProjectBoardViewModelIgnoresCompletedFocusedTaskWhenBuildingTodayAssistantRailContext() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        let selected = try XCTUnwrap(viewModel.createTask(
            title: "Selected open item",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-19T09:00:00Z"
        ))
        let completedFocus = try XCTUnwrap(viewModel.createTask(
            title: "Completed focus item",
            projectID: launch.id,
            status: .done,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.setShowsCompletedWorkflowTasks(true)
        viewModel.startFocus(taskID: completedFocus.id)
        viewModel.selectedTaskID = selected.id

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .selected)
        XCTAssertEqual(context.task?.title, "Selected open item")
    }

    @MainActor
    func testProjectBoardViewModelFallsBackFromFutureFocusedTaskWhenBuildingTodayAssistantRailContext() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Recommended today item",
            projectID: launch.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-19T09:00:00Z"
        ))
        let futureFocus = try XCTUnwrap(viewModel.createTask(
            title: "Future focused item",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-25T12:00:00Z"
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        viewModel.startFocus(taskID: futureFocus.id)

        let context = viewModel.todayAssistantRailContext(
            on: try isoDate("2026-06-19T08:37:00Z"),
            calendar: calendar
        )

        XCTAssertEqual(context.source, .recommended)
        XCTAssertEqual(context.task?.title, "Recommended today item")
    }

    @MainActor
    func testTodayDueDisplayLabelFormatsOverdueTodayAndDateOnlyValues() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try isoDate("2026-06-19T08:37:00Z")
        let overdue = ProjectBoardTask(
            id: 1,
            projectID: 1,
            title: "Overdue",
            detail: "",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )
        let today = ProjectBoardTask(
            id: 2,
            projectID: 1,
            title: "Today",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        )
        let dateOnlyToday = ProjectBoardTask(
            id: 3,
            projectID: 1,
            title: "Date only today",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19"
        )
        let dateOnly = ProjectBoardTask(
            id: 4,
            projectID: 1,
            title: "Date only",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-20"
        )
        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var buddhistPacificCalendar = Calendar(identifier: .buddhist)
        buddhistPacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let pacificDateOnlyToday = ProjectBoardTask(
            id: 5,
            projectID: 1,
            title: "Pacific date only",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-30"
        )

        XCTAssertEqual(
            overdue.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Overdue Jun 18 at 09:00"
        )
        XCTAssertTrue(overdue.isOverdueForToday(on: referenceDate, calendar: calendar))
        XCTAssertEqual(
            today.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Today 12:00"
        )
        XCTAssertFalse(today.isOverdueForToday(on: referenceDate, calendar: calendar))
        XCTAssertEqual(
            dateOnlyToday.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Today"
        )
        XCTAssertEqual(
            dateOnly.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Due Jun 20"
        )
        XCTAssertEqual(
            pacificDateOnlyToday.todayDueDisplayLabel(
                on: try isoDate("2026-07-01T06:30:00Z"),
                calendar: pacificCalendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Today"
        )
        XCTAssertEqual(
            pacificDateOnlyToday.todayDueDisplayLabel(
                on: try isoDate("2026-07-01T06:30:00Z"),
                calendar: buddhistPacificCalendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Today"
        )
        XCTAssertFalse(
            pacificDateOnlyToday.isOverdueForToday(
                on: try isoDate("2026-07-01T06:30:00Z"),
                calendar: pacificCalendar
            )
        )
    }

    @MainActor
    func testTodayPlanUsesCalendarTimeZoneForDateOnlyDueDates() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let launch = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = viewModel.createTask(
            title: "Close June report",
            projectID: launch.id,
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-30"
        )
        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var buddhistPacificCalendar = Calendar(identifier: .buddhist)
        buddhistPacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

        let plan = viewModel.todayPlan(
            on: try isoDate("2026-07-01T06:30:00Z"),
            calendar: pacificCalendar
        )
        let nonGregorianPlan = viewModel.todayPlan(
            on: try isoDate("2026-07-01T06:30:00Z"),
            calendar: buddhistPacificCalendar
        )

        XCTAssertEqual(plan.overdueCount, 0)
        XCTAssertEqual(plan.dueTodayCount, 1)
        XCTAssertEqual(plan.recommendedTask?.title, "Close June report")
        XCTAssertEqual(plan.recommendationReason, "Earliest due task keeps today on track.")
        XCTAssertEqual(nonGregorianPlan.overdueCount, 0)
        XCTAssertEqual(nonGregorianPlan.dueTodayCount, 1)
        XCTAssertEqual(nonGregorianPlan.recommendedTask?.title, "Close June report")
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
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: calendar)
        XCTAssertEqual(viewModel.derivedReadModels.missedTaskReview.newlyMissedCount, 3)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.catchUpCount, 3)

        viewModel.completeMissedTask(id: overdue.id, referenceDate: referenceDate)
        viewModel.rescheduleMissedTaskForToday(id: reschedule.id, referenceDate: referenceDate)
        viewModel.deferMissedTaskForLater(id: deferred.id, referenceDate: referenceDate)

        let summary = viewModel.missedTaskReview(on: referenceDate, calendar: calendar)
        let reloaded = ProjectBoardViewModel(store: bundle.board, missedTaskReviewStateStore: reviewStore)
        reloaded.load()
        let tasks = reloaded.snapshot.projects.flatMap(\.tasks)

        XCTAssertEqual(summary.immediateQueue.map(\.task.title), [])
        XCTAssertEqual(viewModel.derivedReadModels.missedTaskReview, summary)
        XCTAssertEqual(viewModel.derivedReadModels.sidebarMetrics.catchUpCount, 0)
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
        XCTAssertNil(notificationRows.first?["last_reviewed_at"])
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
    func testUnrelatedAutomationAndReceiptStateDoesNotRepublishTodayDerivedModels() throws {
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Launch"))
        _ = try XCTUnwrap(viewModel.createTask(
            title: "Ship release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-06-22T18:00:00Z"
        ))
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        viewModel.refreshDerivedReadModels(on: referenceDate, calendar: utcCalendar())
        let initialModels = viewModel.derivedReadModels
        let initialPreviewBuildCount = viewModel.dailyPlanningReviewPreviewBuildCount

        _ = viewModel.prepareTaskAutomationReview(
            settings: TaskAutoExecutionSettings(isEnabled: true, mode: .reviewOnly, cadence: .manual),
            trigger: .manual,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )
        viewModel.setExecutionReceiptHistorySearchText("reviewed")

        XCTAssertEqual(viewModel.derivedReadModels, initialModels)
        XCTAssertEqual(viewModel.dailyPlanningReviewPreviewBuildCount, initialPreviewBuildCount)
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
    func testDoneAnalyticsCalculatesCountsHeatmapBestSummariesAndKeepsReopenedHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            ProjectBoardProject(
                id: 1,
                title: "Launch",
                status: "completed",
                subtitle: "0 open / 4 total",
                columns: ProjectTaskStatus.allCases.map { status in
                    ProjectBoardColumn(status: status, tasks: status == .done ? [
                        ProjectBoardTask(id: 1, projectID: 1, title: "Today", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-21T01:30:00Z"),
                        ProjectBoardTask(id: 2, projectID: 1, title: "Yesterday", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-20T00:15:00Z"),
                        ProjectBoardTask(id: 3, projectID: 1, title: "Earlier week", detail: "", status: .done, priority: .medium, dueAt: nil, completedAt: "2026-06-18T14:00:00Z")
                    ] : status == .planned ? [
                        ProjectBoardTask(id: 4, projectID: 1, title: "Reopened", detail: "", status: .planned, priority: .medium, dueAt: nil, completedAt: "2026-06-20T01:15:00Z")
                    ] : [])
                }
            )
        ])))
        viewModel.load()

        let analytics = viewModel.doneAnalytics(on: try isoDate("2026-06-21T12:00:00Z"), calendar: calendar)

        XCTAssertEqual(analytics.completedTaskCount, 4)
        XCTAssertEqual(analytics.completedProjectCount, 1)
        XCTAssertEqual(analytics.completedTodayCount, 1)
        XCTAssertEqual(analytics.completedThisWeekCount, 4)
        XCTAssertEqual(analytics.streakDays, 2)
        XCTAssertEqual(analytics.completionHeatmapBuckets.count, 28)
        XCTAssertEqual(analytics.completionHeatmapBuckets.first?.dayKey, "2026-05-25")
        XCTAssertEqual(analytics.completionHeatmapBuckets.last?.dayKey, "2026-06-21")
        XCTAssertEqual(analytics.completionHeatmapBuckets.first { $0.dayKey == "2026-06-20" }?.completedCount, 2)
        XCTAssertEqual(analytics.completionHeatmapBuckets.first { $0.dayKey == "2026-06-19" }?.completedCount, 0)
        XCTAssertEqual(analytics.bestWeekdaySummary, DoneAnalyticsBestWeekdaySummary(weekday: 7, completedCount: 2))
        XCTAssertEqual(analytics.bestHourSummary, DoneAnalyticsBestHourSummary(hour: 10, timeOfDay: .morning, completedCount: 2))
        XCTAssertEqual(analytics.recentTasks.map(\.title), ["Today", "Reopened", "Yesterday", "Earlier week"])
        XCTAssertEqual(analytics.localRuleInsight, "Done analytics uses local completed_at history; reopened tasks remain visible in completion history.")
    }

    @MainActor
    func testDoneAnalyticsReturnsEmptyBestSummariesWithoutCompletionHistory() throws {
        let calendar = utcCalendar()
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore(snapshot: ProjectBoardSnapshot(projects: [
            ProjectBoardProject(
                id: 1,
                title: "Inbox",
                status: "active",
                subtitle: "2 open / 2 total",
                columns: ProjectTaskStatus.allCases.map { status in
                    let tasks: [ProjectBoardTask]
                    switch status {
                    case .planned:
                        tasks = [
                            ProjectBoardTask(id: 1, projectID: 1, title: "Plan", detail: "", status: .planned, priority: .medium, dueAt: nil)
                        ]
                    case .backlog:
                        tasks = [
                            ProjectBoardTask(id: 2, projectID: 1, title: "Draft", detail: "", status: .backlog, priority: .medium, dueAt: nil)
                        ]
                    default:
                        tasks = []
                    }
                    return ProjectBoardColumn(status: status, tasks: tasks)
                }
            )
        ])))
        viewModel.load()

        let analytics = viewModel.doneAnalytics(on: try isoDate("2026-06-21T12:00:00Z"), calendar: calendar)

        XCTAssertEqual(analytics.completedTaskCount, 0)
        XCTAssertEqual(analytics.completedTodayCount, 0)
        XCTAssertEqual(analytics.completedThisWeekCount, 0)
        XCTAssertEqual(analytics.streakDays, 0)
        XCTAssertEqual(analytics.completionHeatmapBuckets.count, 28)
        XCTAssertTrue(analytics.completionHeatmapBuckets.allSatisfy { $0.completedCount == 0 })
        XCTAssertEqual(analytics.bestWeekdaySummary, DoneAnalyticsBestWeekdaySummary.empty)
        XCTAssertEqual(analytics.bestHourSummary, DoneAnalyticsBestHourSummary.empty)
        XCTAssertTrue(analytics.recentTasks.isEmpty)
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
    func testDoneFollowUpDraftQueuesTaskCreateProposalWithoutMutatingTasks() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-07-02T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let secret = "done-secret"
        let project = try XCTUnwrap(viewModel.createProject(title: "Done Follow Up"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Ship recap token=\(secret) /Users/shutoide/Private",
            detail: "Original detail api_key=\(secret) file:///Users/shutoide/Private/report.md",
            projectID: project.id,
            status: .done,
            priority: .high
        ))
        let completedAt = try XCTUnwrap(
            viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id }?.completedAt
        )

        let queued = viewModel.enqueueDoneFollowUpDraft(
            for: task.id,
            sourceTranscript: "Doneから次の作業を作る token=\(secret) ~/vault /var/tmp/work",
            on: referenceDate,
            calendar: calendar
        )

        XCTAssertTrue(queued)
        XCTAssertEqual(viewModel.errorMessage, nil)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Queued Done follow-up draft for approval.")
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(itemID.hasPrefix("action-plan:done-follow-up:2026-07-02:"))
        XCTAssertTrue(itemID.hasSuffix(":task:\(task.id)"))
        XCTAssertFalse(itemID.contains(secret))
        XCTAssertFalse(itemID.contains("/Users/shutoide"))
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        let item = try assistantQueueStore.get(id: itemID)
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(item.requiredCapabilities, [.tool(.taskCreate), .providerExecutionApproval])
        XCTAssertTrue(item.sourceTranscript?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(item.sourceTranscript?.contains(secret) ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("/Users/shutoide") ?? true)
        XCTAssertFalse(item.sourceTranscript?.contains("~/vault") ?? true)
        guard case .actionPlan(let plan) = item.payload else {
            return XCTFail("Expected action plan payload")
        }
        XCTAssertTrue(plan.requiresApproval)
        XCTAssertEqual(plan.riskLevel, .write)
        XCTAssertEqual(plan.actions.map(\.tool), [.taskCreate])
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.arguments["projectId"], .number(Double(project.id)))
        XCTAssertEqual(action.arguments["priority"], .string(ProjectTaskPriority.high.rawValue))
        XCTAssertEqual(action.arguments["sourceCommand"], .string("Done follow-up from task \(task.id)"))
        XCTAssertTrue(String(describing: action.arguments["title"]).contains("Follow up: Ship recap"))
        XCTAssertTrue(String(describing: action.arguments["detail"]).contains("Source task ID: \(task.id)"))
        XCTAssertTrue(String(describing: action.arguments["detail"]).contains("Source completed at: \(completedAt)"))
        let payloadJSON = try XCTUnwrap(bundle.connection.queryRows(
            "SELECT payload_json FROM assistant_queue_items WHERE id = '\(itemID)' LIMIT 1;"
        ).first?["payload_json"])
        XCTAssertFalse(payloadJSON.contains(secret))
        XCTAssertFalse(payloadJSON.contains("/Users/shutoide"))
        XCTAssertFalse(payloadJSON.contains("file:///Users"))
        XCTAssertFalse(payloadJSON.contains("/var/tmp"))
        XCTAssertFalse(payloadJSON.contains("~/vault"))
        XCTAssertEqual(viewModel.snapshot.projects.first { $0.id == project.id }?.column(.done)?.tasks.map(\.id), [task.id])
        let taskRows = try bundle.connection.queryRows(
            "SELECT id, status FROM tasks WHERE project_id = \(project.id) ORDER BY id ASC;"
        )
        XCTAssertEqual(taskRows.map { $0["id"] }, ["\(task.id)"])
        XCTAssertEqual(taskRows.map { $0["status"] }, [ProjectTaskStatus.done.rawValue])
    }

    @MainActor
    func testDoneFollowUpDraftDoesNotOverwriteExistingQueueItem() throws {
        var calendar = utcCalendar()
        calendar.firstWeekday = 2
        let referenceDate = try isoDate("2026-07-02T09:10:00Z")
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Done Follow Up"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Ship recap",
            projectID: project.id,
            status: .done,
            priority: .high
        ))
        XCTAssertTrue(viewModel.enqueueDoneFollowUpDraft(
            for: task.id,
            sourceTranscript: "first follow-up",
            on: referenceDate,
            calendar: calendar
        ))
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        var existing = try assistantQueueStore.get(id: itemID)
        existing.reviewReason = "Existing approved Done follow-up review."
        existing = try AssistantQueueStateMachine.approve(existing, reviewerID: "tester")
        try assistantQueueStore.save(existing)

        let queued = viewModel.enqueueDoneFollowUpDraft(
            for: task.id,
            sourceTranscript: "changed follow-up",
            on: referenceDate,
            calendar: calendar
        )

        let stored = try assistantQueueStore.get(id: itemID)
        XCTAssertTrue(queued)
        XCTAssertEqual(stored.state, .approved)
        XCTAssertEqual(stored.reviewReason, "Existing approved Done follow-up review.")
        XCTAssertEqual(viewModel.integrationStatusMessage, "Done follow-up draft is already in Assistant Queue.")
        XCTAssertEqual(viewModel.assistantQueueSelectedItemIDs, [itemID])
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
    }

    @MainActor
    func testDoneFollowUpDraftAcceptsReopenedHistoryAndRejectsOpenTasks() throws {
        let bundle = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: bundle.connection)
        let viewModel = ProjectBoardViewModel(
            store: bundle.board,
            assistantQueueStore: assistantQueueStore
        )
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Done Follow Up"))
        let completedTask = try XCTUnwrap(viewModel.createTask(
            title: "Close launch loop",
            projectID: project.id,
            status: .done
        ))
        viewModel.reopenCompletedTask(id: completedTask.id)
        let reopenedTask = try XCTUnwrap(
            viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == completedTask.id }
        )
        let openTask = try XCTUnwrap(viewModel.createTask(
            title: "Still open",
            projectID: project.id,
            status: .planned
        ))

        XCTAssertTrue(viewModel.enqueueDoneFollowUpDraft(for: reopenedTask.id))
        let itemID = try XCTUnwrap(viewModel.assistantQueueSnapshot.rows.first?.id)
        XCTAssertTrue(itemID.hasSuffix(":task:\(reopenedTask.id)"))
        XCTAssertFalse(viewModel.enqueueDoneFollowUpDraft(for: openTask.id))
        XCTAssertEqual(viewModel.errorMessage, "Select a completed task before queuing a Done follow-up.")
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.map(\.id), [itemID])
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
    func testProjectBoardViewModelAppliesInboxVoiceTriageCommandsToSelectedInboxTask() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let first = try XCTUnwrap(viewModel.createTask(title: "First capture", projectID: inboxID))
        let second = try XCTUnwrap(viewModel.createTask(title: "Second capture", projectID: inboxID))

        viewModel.selectedTaskID = second.id

        XCTAssertTrue(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .scheduleToday, sourceTranscript: "today"),
            referenceDate: try isoDate("2026-06-19T09:00:00Z")
        ))
        XCTAssertEqual(viewModel.selectedTaskID, first.id)
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == second.id }?.dueAt, "2026-06-19T09:00:00Z")

        XCTAssertTrue(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .undo, sourceTranscript: "undo")
        ))
        XCTAssertEqual(viewModel.selectedTaskID, second.id)
        XCTAssertNil(viewModel.selectedTask?.dueAt)

        XCTAssertTrue(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .setPriority(.high), sourceTranscript: "優先度高")
        ))
        XCTAssertEqual(viewModel.selectedTaskID, first.id)
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == second.id }?.priority, .high)

        viewModel.selectedTaskID = second.id
        XCTAssertTrue(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .complete, sourceTranscript: "完了")
        ))
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == second.id }?.status, .done)
        XCTAssertFalse(viewModel.inboxTasks.contains { $0.id == second.id })
    }

    @MainActor
    func testProjectBoardViewModelInboxVoiceTriageCanSelectNextVisibleInboxTask() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let inboxID = try XCTUnwrap(viewModel.inboxProject?.id)
        let first = try XCTUnwrap(viewModel.createTask(title: "First capture", projectID: inboxID))
        let second = try XCTUnwrap(viewModel.createTask(title: "Second capture", projectID: inboxID))

        viewModel.selectedTaskID = second.id

        XCTAssertTrue(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .selectNext, sourceTranscript: "次")
        ))
        XCTAssertEqual(viewModel.selectedTaskID, first.id)
        XCTAssertEqual(viewModel.inboxClassificationFeedback?.canUndo, false)
    }

    @MainActor
    func testProjectBoardViewModelInboxVoiceTriageFailsClosedWithoutSelectedInboxItem() throws {
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Work"))
        let projectTask = try XCTUnwrap(viewModel.createTask(title: "Project task", projectID: project.id))

        viewModel.selectedTaskID = nil
        XCTAssertFalse(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .scheduleToday, sourceTranscript: "today")
        ))
        XCTAssertEqual(viewModel.errorMessage, "Select an Inbox item before using voice triage.")

        viewModel.selectedTaskID = projectTask.id
        XCTAssertFalse(viewModel.applyInboxVoiceTriageCommand(
            InboxVoiceTriageCommand(action: .complete, sourceTranscript: "done")
        ))
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == projectTask.id }?.status, .backlog)
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
        XCTAssertEqual(viewModel.fatalFailure, .initialLoadFailed("Project board unavailable"))
        XCTAssertEqual(
            viewModel.errorPresentation,
            .fatal(message: "Project board unavailable", canRetry: true)
        )
        XCTAssertFalse(viewModel.isEmptyProjectStateVisible)
    }

    @MainActor
    func testTaskSaveFailureRemainsInlineAndPreservesBoardContextForRetry() throws {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedProjectID = 1
        viewModel.selectedTaskID = 1
        let selectedTask = try XCTUnwrap(viewModel.selectedTask)

        viewModel.updateSelectedTask(
            title: "Edited title",
            detail: selectedTask.detail,
            status: selectedTask.status,
            priority: selectedTask.priority,
            dueDate: nil
        )

        XCTAssertEqual(viewModel.snapshot, store.snapshot)
        XCTAssertEqual(viewModel.selectedTaskID, selectedTask.id)
        XCTAssertNil(viewModel.fatalFailure)
        XCTAssertEqual(viewModel.taskSaveFailure(taskID: selectedTask.id), .saveFailed("Project board unavailable"))
        XCTAssertEqual(
            viewModel.errorPresentation,
            .inline(message: "Project board unavailable", canRetry: true)
        )
        XCTAssertEqual(viewModel.taskSaveFailure(taskID: selectedTask.id)?.message, "Project board unavailable")
        XCTAssertEqual(
            viewModel.rootErrorPresentation,
            .inline(message: "Project board unavailable", canRetry: true)
        )
    }

    @MainActor
    func testReadinessFailureIsRedactedInlineAndRetryRechecksProvider() {
        let sync = RecoveringReadinessGoogleCalendarSync()
        let viewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: sync
        )
        viewModel.load()
        sync.shouldFail = true

        viewModel.refreshGoogleCalendarSyncStatus()

        XCTAssertEqual(sync.statusCallCount, 2)
        XCTAssertEqual(
            viewModel.failure,
            .readinessCheckFailed("calendar readiness failed token=[REDACTED_SECRET]")
        )
        XCTAssertEqual(
            viewModel.errorPresentation,
            .inline(message: "calendar readiness failed token=[REDACTED_SECRET]", canRetry: true)
        )

        sync.shouldFail = false
        viewModel.retryCurrentFailure()

        XCTAssertEqual(sync.statusCallCount, 3)
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testReadinessFailureRemainsVisibleWhenRetryStillFails() {
        let sync = RecoveringReadinessGoogleCalendarSync()
        let viewModel = ProjectBoardViewModel(store: InMemoryProjectBoardStore(), googleCalendarSync: sync)
        viewModel.load()
        sync.shouldFail = true
        viewModel.refreshGoogleCalendarSyncStatus()

        viewModel.retryCurrentFailure()

        XCTAssertEqual(sync.statusCallCount, 3)
        XCTAssertEqual(
            viewModel.errorPresentation,
            .inline(message: "calendar readiness failed token=[REDACTED_SECRET]", canRetry: true)
        )
    }

    @MainActor
    func testTaskSaveRetryReplaysCapturedDraftInsteadOfReloadingOnly() throws {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedProjectID = 1
        viewModel.selectedTaskID = 1

        viewModel.updateSelectedTask(
            title: "Retried title",
            detail: "Retried detail",
            status: .planned,
            priority: .high,
            dueDate: nil
        )
        store.shouldFailUpdates = false

        viewModel.retryCurrentFailure()

        XCTAssertEqual(viewModel.selectedTask?.title, "Retried title")
        XCTAssertEqual(viewModel.selectedTask?.detail, "Retried detail")
        XCTAssertEqual(viewModel.selectedTask?.priority, .high)
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testTaskSaveFailureMovesToRootAndExactRetryRestoresCapturedSelectionAfterNavigation() {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedProjectID = 1
        viewModel.selectedTaskID = 1
        viewModel.updateSelectedTask(
            title: "Captured retry title",
            detail: "Captured retry detail",
            status: .planned,
            priority: .high,
            dueDate: nil
        )

        viewModel.selectedTaskID = 2

        XCTAssertNotNil(viewModel.rootErrorPresentation)
        XCTAssertNil(viewModel.taskSaveFailure(taskID: 2))

        store.shouldFailUpdates = false
        viewModel.retryCurrentFailure()

        XCTAssertEqual(viewModel.selectedTaskID, 1)
        XCTAssertEqual(viewModel.selectedTask?.title, "Captured retry title")
        XCTAssertEqual(viewModel.selectedTask?.detail, "Captured retry detail")
        XCTAssertEqual(viewModel.selectedTask?.priority, .high)
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testTaskSaveRetryBecomesUnavailableWhenCapturedTaskDisappears() {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedTaskID = 1
        viewModel.updateSelectedTask(
            title: "Unavailable retry target",
            detail: "",
            status: .planned,
            priority: .medium,
            dueDate: nil
        )
        store.removeTaskForTest(id: 1)
        viewModel.load()

        XCTAssertEqual(
            viewModel.errorPresentation,
            .inline(message: "Project board unavailable", canRetry: false)
        )
        XCTAssertNil(viewModel.failureActionLabel)
        viewModel.retryCurrentFailure()
        XCTAssertNotNil(viewModel.failure)
    }

    @MainActor
    func testSQLiteTriggerFailurePublishesTaskRetryContextBeforeFailureAndSurvivesReload() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-project-board-retry-\(UUID().uuidString).sqlite")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: databaseURL)
        }
        let connection = try SQLiteConnection(path: databaseURL.path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteProjectBoardStore(connection: connection)
        let projectID = try XCTUnwrap(try store.loadSnapshot().projects.first?.id)
        let task = try store.createTask(ProjectBoardTaskDraft(
            projectID: projectID,
            title: "Persisted title",
            status: .planned
        ))
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedProjectID = projectID
        viewModel.selectedTaskID = task.id
        try connection.execute(
            "CREATE TRIGGER fail_task_update BEFORE UPDATE ON tasks "
                + "WHEN OLD.id = \(task.id) BEGIN SELECT RAISE(FAIL, 'injected recoverable task save failure'); END;"
        )

        viewModel.updateSelectedTask(
            title: "Rejected title",
            detail: "",
            status: .planned,
            priority: .medium,
            dueDate: nil
        )
        // Runtime store notifications can reload immediately after SQLite
        // reports a write failure; the retry context must survive that load.
        viewModel.load()

        XCTAssertEqual(
            try connection.queryRows("SELECT title FROM tasks WHERE id = \(task.id);").first?["title"],
            "Persisted title"
        )
        XCTAssertEqual(
            viewModel.failure,
            .saveFailed("injected recoverable task save failure")
        )
        XCTAssertEqual(
            viewModel.errorPresentation,
            .inline(message: "injected recoverable task save failure", canRetry: true)
        )
        XCTAssertEqual(
            viewModel.taskSaveFailure(taskID: task.id),
            .saveFailed("injected recoverable task save failure")
        )
        XCTAssertEqual(viewModel.failureActionLabel, "Retry")

        try connection.execute("DROP TRIGGER fail_task_update;")
        viewModel.retryCurrentFailure()
        XCTAssertEqual(
            try connection.queryRows("SELECT title FROM tasks WHERE id = \(task.id);").first?["title"],
            "Rejected title"
        )
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testCorrectedTaskSaveClearsPreviousFailureWithoutUsingRetryButton() {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedProjectID = 1
        viewModel.selectedTaskID = 1
        viewModel.updateSelectedTask(
            title: "First failed title",
            detail: "",
            status: .planned,
            priority: .medium,
            dueDate: nil
        )
        store.shouldFailUpdates = false

        viewModel.updateSelectedTask(
            title: "Corrected title",
            detail: "",
            status: .planned,
            priority: .medium,
            dueDate: nil
        )

        XCTAssertEqual(viewModel.selectedTask?.title, "Corrected title")
        XCTAssertNil(viewModel.failure)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectUpdateRetryReplaysCapturedTitleInsteadOfReloadingOnly() {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedProjectID = 1

        viewModel.updateSelectedProject(title: "Retried project title")
        store.shouldFailUpdates = false
        viewModel.retryCurrentFailure()

        XCTAssertEqual(viewModel.selectedProject?.title, "Retried project title")
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testTaskDeleteRetryDeletesOnlyTheCapturedTaskID() {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()
        viewModel.selectedTaskID = 1

        viewModel.deleteSelectedTask()
        XCTAssertNotNil(viewModel.rootErrorPresentation)
        XCTAssertNil(viewModel.taskSaveFailure(taskID: 1))
        viewModel.selectedTaskID = 2
        store.shouldFailDeletes = false
        viewModel.retryCurrentFailure()

        XCTAssertEqual(store.deleteTaskAttempts, [1, 1])
        XCTAssertFalse(viewModel.snapshot.projects.flatMap(\.tasks).contains { $0.id == 1 })
        XCTAssertTrue(viewModel.snapshot.projects.flatMap(\.tasks).contains { $0.id == 2 })
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testTaskMoveRetryPreservesCapturedTaskIDAndDestinationStatus() {
        let store = PartiallyFailingBulkMoveProjectBoardStore()
        store.shouldFailMoves = true
        let viewModel = ProjectBoardViewModel(store: store)
        viewModel.load()

        viewModel.moveTask(id: 1, to: .blocked)
        XCTAssertNotNil(viewModel.rootErrorPresentation)
        XCTAssertNil(viewModel.taskSaveFailure(taskID: 1))
        viewModel.selectedTaskID = 2
        store.shouldFailMoves = false
        viewModel.retryCurrentFailure()

        XCTAssertEqual(store.moveTaskAttempts.map(\.id), [1, 1])
        XCTAssertEqual(store.moveTaskAttempts.map(\.status), [.blocked, .blocked])
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == 1 }?.status, .blocked)
        XCTAssertEqual(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == 2 }?.status, .planned)
        XCTAssertNil(viewModel.failure)
    }

    @MainActor
    func testGoogleCalendarRetryPreservesApprovalTokenAndApprovalRequiredCannotRetry() {
        let retryingSync = RetryingGoogleCalendarSync(behavior: .fail)
        let retryingViewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: retryingSync
        )
        retryingViewModel.load()

        XCTAssertNil(retryingViewModel.syncDueTasksToGoogleCalendar(approvalToken: "approval-123"))
        retryingSync.behavior = .succeed
        retryingViewModel.retryCurrentFailure()

        XCTAssertEqual(retryingSync.approvalTokenIDs, ["approval-123", "approval-123"])
        XCTAssertNil(retryingViewModel.failure)

        let approvalRequiredSync = RetryingGoogleCalendarSync(behavior: .approvalRequired)
        let approvalRequiredViewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: approvalRequiredSync
        )
        approvalRequiredViewModel.load()
        XCTAssertNil(approvalRequiredViewModel.syncDueTasksToGoogleCalendar(approvalToken: "rejected-token"))

        XCTAssertNil(approvalRequiredViewModel.failureActionLabel)
        XCTAssertEqual(
            approvalRequiredViewModel.errorPresentation,
            .inline(
                message: "Google Calendar sync requires approval before writing events.",
                canRetry: false
            )
        )
        approvalRequiredViewModel.retryCurrentFailure()
        XCTAssertEqual(approvalRequiredSync.approvalTokenIDs, ["rejected-token"])

        let missingApprovalViewModel = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: RetryingGoogleCalendarSync(behavior: .succeed)
        )
        missingApprovalViewModel.load()
        XCTAssertNil(missingApprovalViewModel.syncDueTasksToGoogleCalendar(approvalToken: nil))
        XCTAssertNil(missingApprovalViewModel.failureActionLabel)
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
            "Local board data needs repair: projects.tags_json contains invalid list JSON. Restore from backup or repair the local database, then reopen Suisui."
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
            "Local board data needs repair: projects.status contains unsupported value \"parked\". Restore from backup or repair the local database, then reopen Suisui."
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
            "Local board data needs repair: tasks.due_at contains invalid date value \"\(String(repeating: "x", count: 80))...\". Restore from backup or repair the local database, then reopen Suisui."
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

    private func seedLargeProjectBoardFixture(connection: SQLiteConnection) throws {
        try connection.execute(
            """
            WITH RECURSIVE project_numbers(n) AS (
                SELECT 1
                UNION ALL
                SELECT n + 1 FROM project_numbers WHERE n < 20
            )
            INSERT INTO projects (id, title, status, tags_json, created_at, updated_at)
            SELECT
                n,
                printf('Large Project %03d', n),
                'active',
                '[]',
                '2026-06-01T00:00:00Z',
                '2026-06-01T00:00:00Z'
            FROM project_numbers;

            WITH RECURSIVE task_numbers(n) AS (
                SELECT 1
                UNION ALL
                SELECT n + 1 FROM task_numbers WHERE n < 1000
            )
            INSERT INTO tasks (
                id,
                project_id,
                title,
                status,
                detail,
                due_at,
                completed_at,
                priority,
                source_command,
                created_at,
                updated_at
            )
            SELECT
                n,
                ((n - 1) % 20) + 1,
                printf('Large board task %05d', n),
                CASE
                    WHEN n % 10 = 0 THEN 'completed'
                    WHEN n % 7 = 0 THEN 'blocked'
                    WHEN n % 3 = 0 THEN 'planned'
                    ELSE 'backlog'
                END,
                printf('Large board detail %05d', n),
                CASE
                    WHEN n % 5 = 0 THEN NULL
                    WHEN n % 2 = 0 THEN '2026-06-19T09:00:00Z'
                    ELSE '2026-06-25T09:00:00Z'
                END,
                CASE
                    WHEN n % 10 = 0 THEN '2026-06-18T17:00:00Z'
                    ELSE NULL
                END,
                CASE
                    WHEN n % 11 = 0 THEN 'high'
                    WHEN n % 13 = 0 THEN 'low'
                    ELSE 'medium'
                END,
                'large-board-fixture',
                '2026-06-01T00:00:00Z',
                CASE
                    WHEN n % 17 = 0 THEN '2026-06-01T00:00:00Z'
                    ELSE '2026-06-18T12:00:00Z'
                END
            FROM task_numbers;

            WITH RECURSIVE artifact_numbers(n) AS (
                SELECT 1
                UNION ALL
                SELECT n + 1 FROM artifact_numbers WHERE n < 100
            )
            INSERT INTO artifacts (
                id,
                project_id,
                task_id,
                workspace_path,
                expected_path,
                created_state,
                last_modified_at,
                created_at,
                updated_at
            )
            SELECT
                n,
                ((n - 1) % 20) + 1,
                n,
                printf('/tmp/suisui/large-%03d', ((n - 1) % 20) + 1),
                printf('/tmp/suisui/large-%03d/artifact-%04d.md', ((n - 1) % 20) + 1, n),
                'created',
                '2026-06-18T12:00:00Z',
                '2026-06-01T00:00:00Z',
                '2026-06-18T12:00:00Z'
            FROM artifact_numbers;

            WITH RECURSIVE milestone_numbers(n) AS (
                SELECT 1
                UNION ALL
                SELECT n + 1 FROM milestone_numbers WHERE n < 100
            )
            INSERT INTO project_milestones (
                id,
                project_id,
                title,
                due_at,
                is_completed,
                created_at,
                updated_at
            )
            SELECT
                n,
                ((n - 1) % 20) + 1,
                printf('Large milestone %04d', n),
                '2026-06-24T09:00:00Z',
                CASE WHEN n % 8 = 0 THEN 1 ELSE 0 END,
                '2026-06-01T00:00:00Z',
                '2026-06-18T12:00:00Z'
            FROM milestone_numbers;
            """
        )
    }

    private func assertQueryPlanSearchesIndex(
        _ indexName: String,
        tableName: String,
        sql: String,
        connection: SQLiteConnection,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let planDetails = try connection.queryRows("EXPLAIN QUERY PLAN \(sql)").compactMap { $0["detail"] }

        XCTAssertTrue(
            planDetails.contains { $0.contains("SEARCH \(tableName)") && $0.contains(indexName) },
            "Expected query plan to SEARCH \(tableName) with \(indexName), got \(planDetails)",
            file: file,
            line: line
        )
        XCTAssertFalse(
            planDetails.contains { $0.contains("SCAN \(tableName)") },
            "Expected query plan to avoid scanning \(tableName), got \(planDetails)",
            file: file,
            line: line
        )
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

    @MainActor
    private func makeApprovedAutomationQueueSubject() throws -> (
        viewModel: ProjectBoardViewModel,
        assistantQueueStore: SQLiteAssistantQueueStore,
        executionReceiptStore: VolatileExecutionReceiptStore
    ) {
        try makeApprovedAutomationQueueSubject(onChange: {})
    }

    @MainActor
    private func makeApprovedAutomationQueueSubject(
        onChange: @escaping () -> Void
    ) throws -> (
        viewModel: ProjectBoardViewModel,
        assistantQueueStore: SQLiteAssistantQueueStore,
        executionReceiptStore: VolatileExecutionReceiptStore
    ) {
        let executionReceiptStore = VolatileExecutionReceiptStore()
        let subject = try makeApprovedAutomationQueueSubject(
            executionReceiptStore: executionReceiptStore,
            onChange: onChange
        )
        return (subject.viewModel, subject.assistantQueueStore, executionReceiptStore)
    }

    @MainActor
    private func makeApprovedAutomationQueueSubject(
        executionReceiptStore: any ExecutionReceiptStore,
        onChange: @escaping () -> Void = {}
    ) throws -> (
        viewModel: ProjectBoardViewModel,
        assistantQueueStore: SQLiteAssistantQueueStore
    ) {
        let stores = try makeStoreBundle()
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: stores.connection)
        let registry = try ToolRegistry(tools: [
            TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: executionReceiptStore
        )
        let viewModel = ProjectBoardViewModel(
            store: stores.board,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator,
            executionReceiptStore: executionReceiptStore,
            onChange: onChange
        )
        return (viewModel, assistantQueueStore)
    }

    @MainActor
    private func makeDevelopmentRepositoryEditPreviewSubject() throws -> (
        viewModel: ProjectBoardViewModel,
        project: ProjectBoardProject,
        task: ProjectBoardTask,
        branchName: String
    ) {
        let stores = try makeStoreBundle()
        let viewModel = ProjectBoardViewModel(store: stores.board)
        viewModel.load()
        let project = try XCTUnwrap(viewModel.createProject(title: "Client Portal"))
        let task = try XCTUnwrap(viewModel.createTask(
            title: "Implement OAuth callback",
            projectID: project.id,
            status: .planned
        ))
        XCTAssertTrue(viewModel.assignProjectWorkspacePath(
            "/tmp/client-portal",
            bookmarkData: Data([1, 2, 3]),
            projectID: project.id
        ))
        let assignedProject = try XCTUnwrap(viewModel.snapshot.projects.first { $0.id == project.id })
        let currentTask = try XCTUnwrap(viewModel.snapshot.projects.flatMap(\.tasks).first { $0.id == task.id })
        let branchName = try XCTUnwrap(viewModel.developmentAutomationReadiness(
            for: assignedProject,
            task: currentTask
        ).branchNamePreview)
        return (viewModel, assignedProject, currentTask, branchName)
    }

    private func developmentAutomationReceipt(
        id: String,
        projectID: Int64,
        branchName: String,
        baseBranch: String? = nil,
        pullRequestURL: String? = nil,
        commitOID: String? = nil,
        toolName: String,
        status: ExecutionReceiptStatus = .succeeded
    ) -> ExecutionReceipt {
        var references = [
            ExecutionReceiptReference(kind: .project, id: String(projectID)),
            ExecutionReceiptReference(kind: .developmentBranch, id: branchName)
        ]
        if let baseBranch {
            references.append(ExecutionReceiptReference(kind: .developmentBaseBranch, id: baseBranch))
        }
        if let pullRequestURL {
            references.append(ExecutionReceiptReference(kind: .pullRequest, id: pullRequestURL))
        }
        if let commitOID {
            references.append(ExecutionReceiptReference(kind: .developmentCommit, id: commitOID))
        }
        return ExecutionReceipt(
            id: id,
            runID: "run-\(id)",
            createdAt: Date(timeIntervalSince1970: 1),
            status: status,
            inputPreview: "Project development automation receipt",
            outputSummary: "Project development automation \(toolName) \(status.rawValue).",
            primaryToolName: toolName,
            references: references,
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-\(id)",
                    toolName: toolName,
                    status: status,
                    inputPreview: "Receipt-backed project development automation."
                )
            ],
            visibleSurfaces: [.projectDetail, .auditLog]
        )
    }
}

private extension ProjectBoardProject {
    func column(_ status: ProjectTaskStatus) -> ProjectBoardColumn? {
        columns.first { $0.status == status }
    }
}

private final class SaveFailingProjectBoardAssistantQueueStore: AssistantQueueStore, @unchecked Sendable {
    let error: Error
    private(set) var saveAttempts: Int

    init(error: Error) {
        self.error = error
        self.saveAttempts = 0
    }

    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        saveAttempts += 1
        throw error
    }

    func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? {
        try save(item)
    }

    func get(id: String) throws -> AssistantQueueItem {
        throw AssistantQueueStoreError.notFound(id)
    }

    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] {
        []
    }

    func stateCounts() throws -> AssistantQueueStateCounts {
        .empty
    }

    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        throw AssistantQueueStoreError.notFound(id)
    }
}

private final class RecordingDailyPlanningTTSPreviewer: TextToSpeechPreviewing, @unchecked Sendable {
    private(set) var requests: [TextToSpeechRequest]
    private let error: Error?

    init(error: Error? = nil) {
        self.requests = []
        self.error = error
    }

    func playPreview(_ request: TextToSpeechRequest) async throws {
        requests.append(request)
        if let error {
            throw error
        }
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
    var shouldFailUpdates = true
    var shouldFailMoves = false
    var shouldFailDeletes = true
    private(set) var moveTaskAttempts: [(id: Int64, status: ProjectTaskStatus)] = []
    private(set) var deleteTaskAttempts: [Int64] = []

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

    func removeTaskForTest(id: Int64) {
        for projectIndex in currentSnapshot.projects.indices {
            for columnIndex in currentSnapshot.projects[projectIndex].columns.indices {
                currentSnapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll { $0.id == id }
            }
        }
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
        guard !shouldFailUpdates,
              let index = currentSnapshot.projects.firstIndex(where: { $0.id == id }) else {
            throw ProjectBoardStoreTestError.unavailable
        }
        let current = currentSnapshot.projects[index]
        let updated = ProjectBoardProject(
            id: current.id,
            title: title,
            status: current.status,
            subtitle: current.subtitle,
            columns: current.columns
        )
        currentSnapshot.projects[index] = updated
        return updated
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
        guard !shouldFailUpdates,
              let projectIndex = currentSnapshot.projects.firstIndex(where: { $0.id == draft.projectID }),
              let original = currentSnapshot.projects[projectIndex].tasks.first(where: { $0.id == id }) else {
            throw ProjectBoardStoreTestError.unavailable
        }
        let updated = ProjectBoardTask(
            id: original.id,
            projectID: draft.projectID,
            title: draft.title,
            detail: draft.detail,
            status: draft.status,
            priority: draft.priority,
            dueAt: draft.dueAt,
            recurrence: draft.recurrence
        )
        for columnIndex in currentSnapshot.projects[projectIndex].columns.indices {
            currentSnapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll { $0.id == id }
        }
        let columnIndex = currentSnapshot.projects[projectIndex].columns.firstIndex { $0.status == draft.status }!
        currentSnapshot.projects[projectIndex].columns[columnIndex].tasks.insert(updated, at: 0)
        return updated
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        moveTaskAttempts.append((id: id, status: status))
        guard !shouldFailMoves, id == 1 else {
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
        deleteTaskAttempts.append(id)
        guard !shouldFailDeletes,
              currentSnapshot.projects.contains(where: { project in project.tasks.contains { $0.id == id } }) else {
            throw ProjectBoardStoreTestError.unavailable
        }
        for projectIndex in currentSnapshot.projects.indices {
            for columnIndex in currentSnapshot.projects[projectIndex].columns.indices {
                currentSnapshot.projects[projectIndex].columns[columnIndex].tasks.removeAll { $0.id == id }
            }
        }
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

private final class RecoveringReadinessGoogleCalendarSync: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    var shouldFail = false
    private(set) var statusCallCount = 0

    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        statusCallCount += 1
        if shouldFail {
            throw ProjectBoardSecretError(message: "calendar readiness failed token=sk-readinessSecret123")
        }
        return .runtimeNotConfigured
    }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        throw GoogleCalendarRuntimeSyncError.notReady(.runtimeNotConfigured)
    }
}

private final class RetryingGoogleCalendarSync: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    enum Behavior {
        case fail
        case succeed
        case approvalRequired
    }

    var behavior: Behavior
    private(set) var approvalTokenIDs: [String] = []

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)
    }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        approvalTokenIDs.append(context.approvalToken?.id ?? "")
        switch behavior {
        case .fail:
            throw ProjectBoardStoreTestError.unavailable
        case .succeed:
            return GoogleCalendarTaskSyncResult(createdEventCount: 1)
        case .approvalRequired:
            throw GoogleCalendarRuntimeSyncError.approvalRequired
        }
    }
}

private final class CountingInboxCaptureStore: InboxCaptureStore, @unchecked Sendable {
    var recordsByTaskID: [Int64: [InboxCaptureRecord]]
    private(set) var singleListCallCount: Int
    private(set) var batchListCallCount: Int

    init(recordsByTaskID: [Int64: [InboxCaptureRecord]] = [:]) {
        self.recordsByTaskID = recordsByTaskID
        self.singleListCallCount = 0
        self.batchListCallCount = 0
    }

    func createVoiceCapture(_ draft: InboxVoiceCaptureDraft) throws -> InboxCaptureRecord {
        let nextID = (recordsByTaskID.values.flatMap { $0 }.map(\.id).max() ?? 0) + 1
        let record = InboxCaptureRecord(
            id: nextID,
            taskID: draft.taskID,
            sourceKind: .voiceMemo,
            audioFilePath: draft.audioFilePath,
            durationSeconds: draft.durationSeconds,
            transcript: draft.transcript,
            interpretationSummary: draft.interpretationSummary,
            memo: draft.memo,
            classificationStatus: draft.classificationStatus,
            transcriptionStatus: draft.transcriptionStatus,
            createdAt: draft.createdAt ?? "2026-07-05T00:00:00Z"
        )
        recordsByTaskID[draft.taskID, default: []].insert(record, at: 0)
        return record
    }

    func get(id: Int64) throws -> InboxCaptureRecord {
        guard let record = recordsByTaskID.values.flatMap({ $0 }).first(where: { $0.id == id }) else {
            throw InboxCaptureStoreError.notFound(id)
        }
        return record
    }

    func list(taskID: Int64) throws -> [InboxCaptureRecord] {
        singleListCallCount += 1
        return recordsByTaskID[taskID] ?? []
    }

    func list(taskIDs: Set<Int64>) throws -> [Int64: [InboxCaptureRecord]] {
        batchListCallCount += 1
        return Dictionary(uniqueKeysWithValues: taskIDs.map { taskID in
            (taskID, recordsByTaskID[taskID] ?? [])
        })
    }

    func updateMemo(id: Int64, memo: String?) throws -> InboxCaptureRecord {
        for taskID in recordsByTaskID.keys {
            guard let index = recordsByTaskID[taskID]?.firstIndex(where: { $0.id == id }) else {
                continue
            }
            recordsByTaskID[taskID]?[index].memo = memo
            return recordsByTaskID[taskID]![index]
        }
        throw InboxCaptureStoreError.notFound(id)
    }

    func relinkCaptures(fromTaskID: Int64, toTaskID: Int64) throws -> Int {
        let records = recordsByTaskID.removeValue(forKey: fromTaskID) ?? []
        recordsByTaskID[toTaskID, default: []].append(contentsOf: records.map { record in
            var updated = record
            updated.taskID = toTaskID
            return updated
        })
        return records.count
    }

    func delete(id: Int64) throws {
        for taskID in recordsByTaskID.keys {
            recordsByTaskID[taskID]?.removeAll { $0.id == id }
        }
    }
}

private final class FailingProjectBoardExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    func save(_ receipt: ExecutionReceipt) throws {
        throw ProjectBoardStoreTestError.unavailable
    }

    func list(limit: Int) throws -> [ExecutionReceipt] {
        []
    }

    func list(matching filter: ExecutionReceiptSearchFilter, limit: Int) throws -> [ExecutionReceipt] {
        []
    }

    func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int
    ) throws -> [ExecutionReceipt] {
        []
    }
}

private final class CountingProjectBoardExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var scopedListKeys: [String] = []
    private(set) var matchingListCallCount = 0

    func save(_ receipt: ExecutionReceipt) throws {}

    func list(limit: Int) throws -> [ExecutionReceipt] {
        []
    }

    func list(matching filter: ExecutionReceiptSearchFilter, limit: Int) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        matchingListCallCount += 1
        return []
    }

    func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int
    ) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        scopedListKeys.append("\(referenceKind.rawValue):\(referenceID):\(visibleSurface.rawValue)")
        return []
    }
}

private final class FailingAfterFirstProjectBoardExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ExecutionReceipt] = []

    var receipts: [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func save(_ receipt: ExecutionReceipt) throws {
        lock.lock()
        defer { lock.unlock() }
        guard storage.isEmpty else {
            throw ProjectBoardStoreTestError.unavailable
        }
        storage.append(receipt)
    }

    func list(limit: Int) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.suffix(max(1, min(limit, 500))).reversed())
    }

    func list(matching filter: ExecutionReceiptSearchFilter, limit: Int) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.reversed())
            .filter { filter.matches($0) }
            .prefix(max(1, min(limit, 500)))
            .map { $0 }
    }

    func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int
    ) throws -> [ExecutionReceipt] {
        lock.lock()
        defer { lock.unlock() }
        return Array(storage.reversed())
            .filter { receipt in
                receipt.visibleSurfaces.contains(visibleSurface)
                    && receipt.references.contains { reference in
                        reference.kind == referenceKind && reference.id == referenceID
                    }
            }
            .prefix(max(1, min(limit, 500)))
            .map { $0 }
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
