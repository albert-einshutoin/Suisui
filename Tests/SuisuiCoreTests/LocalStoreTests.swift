import XCTest
@testable import SuisuiCore

final class LocalStoreTests: XCTestCase {
    func testPhase2MigrationsCreateProjectTaskAndKnowledgeTables() throws {
        let connection = try migratedConnection()

        XCTAssertTrue(try connection.tableExists("projects"))
        XCTAssertTrue(try connection.tableExists("tasks"))
        XCTAssertTrue(try connection.tableExists("knowledge_frames"))
    }

    func testProjectStoreCreatesAndListsProjects() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)

        _ = try store.create(title: "First")
        let second = try store.create(title: "Second", tags: ["oss"], sourceCommand: "voice")

        let projects = try store.list()

        XCTAssertEqual(projects.map(\.title), ["Second", "First"])
        XCTAssertEqual(projects.first?.id, second.id)
        XCTAssertEqual(projects.first?.tags, ["oss"])
    }

    func testProjectStoreRejectsCorruptedTagsJSONInsteadOfDroppingTags() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)
        let project = try store.create(title: "Tagged", tags: ["oss", "alpha"])

        try connection.execute("UPDATE projects SET tags_json = 'not-json' WHERE id = \(project.id);")

        XCTAssertThrowsError(try store.get(id: project.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidStringArray(column: "projects.tags_json"))
        }
    }

    func testProjectStoreRejectsCorruptedStatusInsteadOfReturningUnknownState() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)
        let project = try store.create(title: "Launch alpha")

        try connection.execute("UPDATE projects SET status = 'parked' WHERE id = \(project.id);")

        XCTAssertThrowsError(try store.get(id: project.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidEnum(column: "projects.status", value: "parked"))
        }
    }

    func testProjectStoreNormalizesAndRejectsBlankTitles() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)

        let project = try store.create(title: "  Launch alpha  ")

        XCTAssertEqual(project.title, "Launch alpha")

        do {
            _ = try store.create(title: " \n\t ")
            XCTFail("Blank project title should not be persisted.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectCreate, "Argument 'title' cannot be blank."))
        }

        let updated = try store.update(id: project.id, title: "  Investor demo  ")

        XCTAssertEqual(updated.title, "Investor demo")

        do {
            _ = try store.update(id: project.id, title: " \n ")
            XCTFail("Blank project title should not replace an existing title.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectUpdate, "Argument 'title' cannot be blank."))
        }
        XCTAssertEqual(try store.get(id: project.id).title, "Investor demo")
        XCTAssertEqual(try store.list(includeArchived: true).map(\.title), ["Investor demo"])
    }

    func testProjectStoreNormalizesAndRejectsInvalidStatus() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)
        let project = try store.create(title: "Launch alpha")

        let completed = try store.update(id: project.id, status: " completed ")

        XCTAssertEqual(completed.status, "completed")

        do {
            _ = try store.update(id: project.id, status: "paused")
            XCTFail("Invalid project status should not replace an existing status.")
        } catch {
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.projectUpdate, "Argument 'status' must be one of active, completed, archived.")
            )
        }

        XCTAssertEqual(try store.get(id: project.id).status, "completed")
    }

    func testProjectStoreArchivesProjectsWithoutDeletingRows() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)
        let project = try store.create(title: "Stale")

        _ = try store.archive(id: project.id)

        XCTAssertEqual(try store.list().map(\.title), [])
        XCTAssertEqual(try store.list(includeArchived: true).map(\.title), ["Stale"])
        XCTAssertEqual(try store.get(id: project.id).status, "archived")
    }

    func testProjectStoreRestoresArchivedProjectsToActiveList() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)
        let project = try store.create(title: "Paused Launch")
        _ = try store.archive(id: project.id)

        let restored = try store.restore(id: project.id)

        XCTAssertEqual(restored.status, "active")
        XCTAssertEqual(try store.list().map(\.title), ["Paused Launch"])
    }

    func testProjectStoreDeletesProjectTasksAndLinkedLocalState() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let calendarLinks = SQLiteCalendarLinkStore(connection: connection)
        let reminderLinks = SQLiteReminderLinkStore(connection: connection)
        let project = try projects.create(title: "Stale Initiative")
        let task = try tasks.create(title: "Remove stale project task", projectID: project.id)
        let otherProject = try projects.create(title: "Keep Initiative")
        let otherTask = try tasks.create(title: "Keep task", projectID: otherProject.id)

        _ = try calendarLinks.link(eventID: "project-event", projectID: project.id, title: "Project event")
        _ = try calendarLinks.link(eventID: "task-event", taskID: task.id, title: "Task event")
        _ = try calendarLinks.link(eventID: "keep-event", projectID: otherProject.id, taskID: otherTask.id, title: "Keep event")
        _ = try reminderLinks.link(reminderID: "project-reminder", projectID: project.id, title: "Project reminder")
        _ = try reminderLinks.link(reminderID: "task-reminder", taskID: task.id, title: "Task reminder")
        _ = try reminderLinks.link(reminderID: "keep-reminder", projectID: otherProject.id, taskID: otherTask.id, title: "Keep reminder")
        try connection.execute("INSERT INTO deadline_rules (target_type, target_id, kind) VALUES ('project', \(project.id), 'overdue');")
        try connection.execute("INSERT INTO deadline_rules (target_type, target_id, kind) VALUES ('task', \(task.id), 'overdue');")
        try connection.execute("INSERT INTO deadline_rules (target_type, target_id, kind) VALUES ('task', \(otherTask.id), 'overdue');")
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state)
            VALUES (\(project.id), NULL, '/tmp/suisui', 'project.md', 'expected');
            """
        )
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state)
            VALUES (NULL, \(task.id), '/tmp/suisui', 'task.md', 'expected');
            """
        )
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state)
            VALUES (\(otherProject.id), \(otherTask.id), '/tmp/suisui', 'keep.md', 'expected');
            """
        )

        let deletion = try projects.delete(id: project.id)

        XCTAssertEqual(deletion.project.id, project.id)
        XCTAssertEqual(deletion.deletedTaskCount, 1)
        XCTAssertEqual(deletion.deletedCalendarLinkCount, 2)
        XCTAssertEqual(deletion.deletedReminderLinkCount, 2)
        XCTAssertEqual(deletion.deletedDeadlineRuleCount, 2)
        XCTAssertEqual(deletion.deletedArtifactCount, 2)
        XCTAssertThrowsError(try projects.get(id: project.id))
        XCTAssertThrowsError(try tasks.get(id: task.id))
        XCTAssertEqual(try tasks.get(id: otherTask.id).title, "Keep task")
        XCTAssertEqual(try rowCount("projects", connection: connection), 1)
        XCTAssertEqual(try rowCount("tasks", connection: connection), 1)
        XCTAssertEqual(try rowCount("calendar_links", connection: connection), 1)
        XCTAssertEqual(try rowCount("reminder_links", connection: connection), 1)
        XCTAssertEqual(try rowCount("deadline_rules", connection: connection), 1)
        XCTAssertEqual(try rowCount("artifacts", connection: connection), 1)
    }

    func testProjectStoreDeleteWorksOnPhase2SchemaWithoutLaterTables() throws {
        let connection = try migratedConnection()
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let calendarLinks = SQLiteCalendarLinkStore(connection: connection)
        let reminderLinks = SQLiteReminderLinkStore(connection: connection)
        let project = try projects.create(title: "Phase 2 Project")
        let task = try tasks.create(title: "Phase 2 Task", projectID: project.id)
        _ = try calendarLinks.link(eventID: "phase2-event", projectID: project.id, taskID: task.id)
        _ = try reminderLinks.link(reminderID: "phase2-reminder", projectID: project.id, taskID: task.id)

        let deletion = try projects.delete(id: project.id)

        XCTAssertEqual(deletion.deletedTaskCount, 1)
        XCTAssertThrowsError(try projects.get(id: project.id))
        XCTAssertThrowsError(try tasks.get(id: task.id))
        XCTAssertEqual(try rowCount("calendar_links", connection: connection), 0)
        XCTAssertEqual(try rowCount("reminder_links", connection: connection), 0)
    }

    func testTaskStoreDeletesLinkedLocalStateWithoutDeletingProjectState() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let calendarLinks = SQLiteCalendarLinkStore(connection: connection)
        let reminderLinks = SQLiteReminderLinkStore(connection: connection)
        let project = try projects.create(title: "Launch Initiative")
        let deletedTask = try tasks.create(title: "Remove stale task", projectID: project.id)
        let keptTask = try tasks.create(title: "Keep task", projectID: project.id)

        _ = try calendarLinks.link(eventID: "deleted-task-event", taskID: deletedTask.id, title: "Deleted task event")
        _ = try calendarLinks.link(eventID: "kept-task-event", taskID: keptTask.id, title: "Kept task event")
        _ = try calendarLinks.link(eventID: "project-event", projectID: project.id, title: "Project event")
        _ = try reminderLinks.link(reminderID: "deleted-task-reminder", taskID: deletedTask.id, title: "Deleted task reminder")
        _ = try reminderLinks.link(reminderID: "kept-task-reminder", taskID: keptTask.id, title: "Kept task reminder")
        _ = try reminderLinks.link(reminderID: "project-reminder", projectID: project.id, title: "Project reminder")
        try connection.execute("INSERT INTO deadline_rules (target_type, target_id, kind) VALUES ('task', \(deletedTask.id), 'overdue');")
        try connection.execute("INSERT INTO deadline_rules (target_type, target_id, kind) VALUES ('task', \(keptTask.id), 'overdue');")
        try connection.execute("INSERT INTO deadline_rules (target_type, target_id, kind) VALUES ('project', \(project.id), 'overdue');")
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state)
            VALUES (NULL, \(deletedTask.id), '/tmp/suisui', 'deleted-task.md', 'expected');
            """
        )
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state)
            VALUES (NULL, \(keptTask.id), '/tmp/suisui', 'kept-task.md', 'expected');
            """
        )
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state)
            VALUES (\(project.id), NULL, '/tmp/suisui', 'project.md', 'expected');
            """
        )

        let deletion = try tasks.delete(id: deletedTask.id)

        XCTAssertEqual(deletion.task.id, deletedTask.id)
        XCTAssertEqual(deletion.deletedCalendarLinkCount, 1)
        XCTAssertEqual(deletion.deletedReminderLinkCount, 1)
        XCTAssertEqual(deletion.deletedDeadlineRuleCount, 1)
        XCTAssertEqual(deletion.deletedArtifactCount, 1)
        XCTAssertThrowsError(try tasks.get(id: deletedTask.id))
        XCTAssertEqual(try tasks.get(id: keptTask.id).title, "Keep task")
        XCTAssertEqual(try projects.get(id: project.id).title, "Launch Initiative")
        XCTAssertEqual(try rowCount("calendar_links", connection: connection), 2)
        XCTAssertEqual(try rowCount("reminder_links", connection: connection), 2)
        XCTAssertEqual(try rowCount("deadline_rules", connection: connection), 2)
        XCTAssertEqual(try rowCount("artifacts", connection: connection), 2)
    }

    func testProjectStoreUpdatesAndClearsEditableMetadata() throws {
        let connection = try migratedConnection()
        let store = SQLiteProjectStore(connection: connection)
        let project = try store.create(title: "Launch alpha")

        let updated = try store.updateFields(
            id: project.id,
            priority: .set("high"),
            deadline: .set("2026-06-30"),
            workspacePath: .set("/tmp/suisui-launch"),
            tags: .set(["release", "alpha"])
        )

        XCTAssertEqual(updated.priority, "high")
        XCTAssertEqual(updated.deadline, "2026-06-30")
        XCTAssertEqual(updated.workspacePath, "/tmp/suisui-launch")
        XCTAssertEqual(updated.tags, ["release", "alpha"])

        let cleared = try store.updateFields(
            id: project.id,
            priority: .clear,
            deadline: .clear,
            workspacePath: .clear,
            tags: .clear
        )

        XCTAssertNil(cleared.priority)
        XCTAssertNil(cleared.deadline)
        XCTAssertNil(cleared.workspacePath)
        XCTAssertEqual(cleared.tags, [])
    }

    func testTaskStoreCreatesAndQueriesDueTasks() throws {
        let connection = try migratedConnection()
        let store = SQLiteTaskStore(connection: connection)

        _ = try store.create(title: "Soon", dueAt: "2026-06-17T00:00:00Z")
        _ = try store.create(title: "Later", dueAt: "2026-06-20T00:00:00Z")
        let completed = try store.create(title: "Completed", dueAt: "2026-06-17T00:00:00Z")
        _ = try store.update(id: completed.id, status: "completed")

        let due = try store.listDue(onOrBefore: "2026-06-18T00:00:00Z")

        XCTAssertEqual(due.map(\.title), ["Soon"])
    }

    func testTaskContentSearchFTSIndexTracksCreateUpdateAndDelete() throws {
        let connection = try currentConnection()
        let store = SQLiteTaskStore(connection: connection)

        XCTAssertTrue(try connection.tableExists("tasks_fts"))

        let task = try store.create(
            title: "Release checklist",
            detail: "Verify signing before upload"
        )
        XCTAssertEqual(
            try store.searchOpenTasksByContent(text: "signing", limit: 10).map(\.id),
            [task.id]
        )

        _ = try store.update(
            id: task.id,
            title: "Sprint checklist",
            detail: "Run the deployment dry run"
        )
        XCTAssertTrue(try store.searchOpenTasksByContent(text: "release", limit: 10).isEmpty)
        XCTAssertTrue(try store.searchOpenTasksByContent(text: "signing", limit: 10).isEmpty)
        XCTAssertEqual(
            try store.searchOpenTasksByContent(text: "sprint", limit: 10).map(\.id),
            [task.id]
        )
        XCTAssertEqual(
            try store.searchOpenTasksByContent(text: "dry run", limit: 10).map(\.id),
            [task.id]
        )

        _ = try store.delete(id: task.id)
        XCTAssertTrue(try store.searchOpenTasksByContent(text: "sprint", limit: 10).isEmpty)
    }

    func testContentSearchMigrationBackfillsExistingTasksAndKnowledgeTriggers() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeTaskSearch = CoreMigrations.current.filter {
            $0.id != "0036_create_task_and_knowledge_content_search"
        }
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrationsBeforeTaskSearch)
        let taskStore = SQLiteTaskStore(connection: connection)
        let knowledgeStore = SQLiteKnowledgeFrameStore(connection: connection)
        let task = try taskStore.create(title: "Restore search index")
        let frame = try knowledgeStore.create(
            name: "Release guide",
            body: "Verify signing",
            triggers: ["shiproom"]
        )

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertEqual(
            try taskStore.searchOpenTasksByContent(text: "restore", limit: 10).map(\.id),
            [task.id]
        )
        XCTAssertEqual(try knowledgeStore.search(query: "shiproom").map(\.id), [frame.id])
    }

    func testTaskContentSearchBoundsTokensBeforeBuildingQuery() {
        let longToken = String(repeating: "a", count: 129)
        let tokens = [" ", longToken] + (0..<40).map { "token-\($0)" }

        let bounded = SQLiteTaskStore.boundedSearchTokens(tokens)

        XCTAssertEqual(bounded.count, 32)
        XCTAssertEqual(bounded.first, String(repeating: "a", count: 128))
        XCTAssertTrue(bounded.allSatisfy { $0.count <= 128 })
    }

    func testKnowledgeSearchCompletesLiteralSubstringsAlongsideFTSHits() throws {
        let connection = try currentConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let substringFrame = try store.create(name: "Billing", body: "Prepare invoice report")
        let ftsFrame = try store.create(name: "Notes", body: "Record voice memo")

        XCTAssertEqual(
            try store.search(matching: ["voice"], limit: 2).map(\.id),
            [ftsFrame.id, substringFrame.id]
        )
    }

    func testKnowledgeSearchExcludesEarlierFTSHitBeforeCompletingAnotherTokenSubstring() throws {
        let connection = try currentConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let ftsFrame = try store.create(name: "Voice notes", body: "Record the voice memo")
        let substringFrame = try store.create(name: "Meetings", body: "Prepare the premeeting checklist")

        XCTAssertEqual(
            try store.search(matching: ["voice", "meet"], limit: 2).map(\.id),
            [ftsFrame.id, substringFrame.id]
        )
    }

    func testKnowledgeSearchFiltersTokenizedFTSCandidatesToLiteralQuery() throws {
        let connection = try currentConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let literalFrame = try store.create(
            name: "Migration",
            body: "Roughly 50% done as of Friday"
        )
        _ = try store.create(name: "Shortcut", body: "Roughly 50 done as of Friday")

        XCTAssertEqual(try store.search(query: "50% done").map(\.id), [literalFrame.id])
    }

    func testTaskStoreRejectsCorruptedProjectIDInsteadOfDetachingTask() throws {
        let connection = try migratedConnection()
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let project = try projects.create(title: "Launch alpha")
        let task = try tasks.create(title: "Ship alpha", projectID: project.id)

        try connection.execute("UPDATE tasks SET project_id = 'not-int' WHERE id = \(task.id);")

        XCTAssertThrowsError(try tasks.get(id: task.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidInt64(column: "tasks.project_id", value: "not-int"))
        }
    }

    func testTaskStoreCanExplicitlyClearNullableMetadataFields() throws {
        let connection = try migratedConnection()
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let project = try projects.create(title: "Launch alpha")
        let task = try tasks.create(
            title: "Ship alpha",
            projectID: project.id,
            dueAt: "2026-06-21",
            priority: "high",
            detail: "Initial detail"
        )

        let updated = try tasks.updateFields(
            id: task.id,
            detail: .clear,
            dueAt: .clear,
            priority: .clear,
            projectID: .clear
        )

        XCTAssertNil(updated.projectID)
        XCTAssertNil(updated.detail)
        XCTAssertNil(updated.dueAt)
        XCTAssertNil(updated.priority)
    }

    func testTaskStoreNormalizesAndRejectsBlankTitles() throws {
        let connection = try migratedConnection()
        let store = SQLiteTaskStore(connection: connection)

        let task = try store.create(title: "  Ship alpha  ")

        XCTAssertEqual(task.title, "Ship alpha")

        do {
            _ = try store.create(title: " \n\t ")
            XCTFail("Blank task title should not be persisted.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskCreate, "Argument 'title' cannot be blank."))
        }

        let updated = try store.update(id: task.id, title: "  Fix onboarding  ")

        XCTAssertEqual(updated.title, "Fix onboarding")

        do {
            _ = try store.update(id: task.id, title: " \n ")
            XCTFail("Blank task title should not replace an existing title.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskUpdate, "Argument 'title' cannot be blank."))
        }

        do {
            _ = try store.createMany([
                TaskCreateDraft(title: "Keep me out of rollback"),
                TaskCreateDraft(title: " \n ")
            ])
            XCTFail("Bulk create should reject blank task titles.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskBulkCreate, "Argument 'title' cannot be blank."))
        }

        XCTAssertEqual(try store.get(id: task.id).title, "Fix onboarding")
        XCTAssertEqual(try store.listAll().map(\.title), ["Fix onboarding"])
    }

    func testTaskStoreNormalizesAndRejectsInvalidStatus() throws {
        let connection = try migratedConnection()
        let store = SQLiteTaskStore(connection: connection)

        let completed = try store.create(title: "Ship alpha", status: " done ")

        XCTAssertEqual(completed.status, "completed")

        let inProgress = try store.update(id: completed.id, status: "doing")

        XCTAssertEqual(inProgress.status, "in_progress")

        do {
            _ = try store.create(title: "Invalid status task", status: "parked")
            XCTFail("Invalid task status should not be persisted.")
        } catch {
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskCreate, "Argument 'status' must be one of open, backlog, planned, in_progress, blocked, completed.")
            )
        }

        do {
            _ = try store.update(id: completed.id, status: "parked")
            XCTFail("Invalid task status should not replace an existing status.")
        } catch {
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskUpdate, "Argument 'status' must be one of open, backlog, planned, in_progress, blocked, completed.")
            )
        }

        XCTAssertEqual(try store.get(id: completed.id).status, "in_progress")
        XCTAssertEqual(try store.listAll().map(\.title), ["Ship alpha"])
    }

    func testTaskStoreDueQueriesExcludeArchivedProjectTasks() throws {
        let connection = try migratedConnection()
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let archived = try projects.create(title: "Archived")
        _ = try projects.archive(id: archived.id)

        _ = try tasks.create(title: "Archived task", projectID: archived.id, dueAt: "2026-06-17T00:00:00Z")
        _ = try tasks.create(title: "Visible task", dueAt: "2026-06-17T00:00:00Z")

        let due = try tasks.listDue(onOrBefore: "2026-06-18T00:00:00Z")

        XCTAssertEqual(due.map(\.title), ["Visible task"])
    }

    func testTaskStoreDeadlineQueriesExcludeCompletedProjectTasks() throws {
        let connection = try migratedConnection()
        let projects = SQLiteProjectStore(connection: connection)
        let tasks = SQLiteTaskStore(connection: connection)
        let completedProject = try projects.create(title: "Completed Project")
        _ = try projects.update(id: completedProject.id, status: "completed")

        _ = try tasks.create(
            title: "Completed project task",
            projectID: completedProject.id,
            dueAt: "2026-06-17T00:00:00Z"
        )
        _ = try tasks.create(title: "Visible task", dueAt: "2026-06-17T00:00:00Z")

        let due = try tasks.listDue(onOrBefore: "2026-06-18T00:00:00Z")
        let deadlineCandidates = try tasks.listDeadlineCandidates()

        XCTAssertEqual(due.map(\.title), ["Visible task"])
        XCTAssertEqual(deadlineCandidates.map(\.title), ["Visible task"])
    }

    func testKnowledgeFrameStoreNormalizesNamesAndRejectsBlankCoreFields() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)

        let frame = try store.create(name: "  Runbook  ", body: "  Use release checklist  ")

        XCTAssertEqual(frame.name, "Runbook")
        XCTAssertEqual(frame.body, "  Use release checklist  ")

        do {
            _ = try store.create(name: " \n ", body: "Body")
            XCTFail("Blank knowledge frame name should not be persisted.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameCreate, "Argument 'name' cannot be blank."))
        }

        do {
            _ = try store.create(name: "Frame", body: " \n ")
            XCTFail("Blank knowledge frame body should not be persisted.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameCreate, "Argument 'body' cannot be blank."))
        }

        let updated = try store.update(id: frame.id, name: "  Investor memo  ", body: "  Updated body  ")

        XCTAssertEqual(updated.name, "Investor memo")
        XCTAssertEqual(updated.body, "  Updated body  ")

        do {
            _ = try store.update(id: frame.id, name: " \n ")
            XCTFail("Blank knowledge frame name should not replace an existing name.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameUpdate, "Argument 'name' cannot be blank."))
        }

        do {
            _ = try store.update(id: frame.id, body: " \n ")
            XCTFail("Blank knowledge frame body should not replace an existing body.")
        } catch {
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameUpdate, "Argument 'body' cannot be blank."))
        }

        XCTAssertEqual(try store.get(id: frame.id).name, "Investor memo")
        XCTAssertEqual(try store.get(id: frame.id).body, "  Updated body  ")
        XCTAssertEqual(try store.list().map(\.name), ["Investor memo"])
    }

    func testKnowledgeFrameStoreRejectsCorruptedTriggersJSONInsteadOfDroppingTriggers() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let frame = try store.create(name: "Runbook", body: "Use release checklist", triggers: ["release", "alpha"])

        try connection.execute("UPDATE knowledge_frames SET triggers_json = 'not-json' WHERE id = \(frame.id);")

        XCTAssertThrowsError(try store.get(id: frame.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidStringArray(column: "knowledge_frames.triggers_json"))
        }
    }

    func testKnowledgeFrameStoreRejectsCorruptedRequiredFieldsInsteadOfReturningEmptyFrame() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let frame = try store.create(name: "Runbook", body: "Use release checklist")

        try connection.execute("UPDATE knowledge_frames SET name = '' WHERE id = \(frame.id);")

        XCTAssertThrowsError(try store.get(id: frame.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .missingRequiredColumn(column: "knowledge_frames.name"))
        }
    }

    func testKnowledgeFrameStoreSearchesWithFTS5() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)

        _ = try store.create(name: "QZT article", body: "Publish the QZT article checklist", triggers: ["qzt"])

        let results = try store.search(query: "QZT")

        XCTAssertEqual(results.map(\.name), ["QZT article"])
    }

    func testKnowledgeFrameFTSIndexesTriggersAndTracksTheirUpdates() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let frame = try store.create(
            name: "Release checklist",
            body: "Verify signing before upload",
            triggers: ["shiproom"]
        )

        XCTAssertEqual(try store.search(query: "shiproom").map(\.id), [frame.id])

        _ = try store.update(id: frame.id, triggers: ["launchpad"])

        XCTAssertTrue(try store.search(query: "shiproom").isEmpty)
        XCTAssertEqual(try store.search(query: "launchpad").map(\.id), [frame.id])
    }

    func testKnowledgeFrameCreateRollsBackBaseRowWhenFTSWriteFails() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        try connection.execute("DROP TABLE knowledge_frames_fts;")

        XCTAssertThrowsError(
            try store.create(name: "Atomic frame", body: "Should not leave a base row")
        )

        XCTAssertEqual(try connection.queryRows("SELECT * FROM knowledge_frames;").count, 0)
    }

    func testKnowledgeFrameUpdateKeepsFTSIndexWhenBaseUpdateFails() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let frame = try store.create(name: "Release notes", body: "Indexed before failure")
        XCTAssertEqual(try store.search(query: "Release").map(\.id), [frame.id])
        try connection.execute(
            """
            CREATE TRIGGER reject_knowledge_frame_updates
            BEFORE UPDATE ON knowledge_frames
            BEGIN
                SELECT RAISE(ABORT, 'blocked knowledge frame update');
            END;
            """
        )

        XCTAssertThrowsError(
            try store.update(id: frame.id, name: "Mutated", body: "Should not apply")
        )

        XCTAssertEqual(try store.get(id: frame.id).name, "Release notes")
        XCTAssertEqual(try store.search(query: "Release").map(\.id), [frame.id])
    }

    func testKnowledgeFrameDeleteKeepsFTSIndexWhenBaseDeleteFails() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)
        let frame = try store.create(name: "Protected frame", body: "Delete should roll back")
        XCTAssertEqual(try store.search(query: "Protected").map(\.id), [frame.id])
        try connection.execute(
            """
            CREATE TABLE guarded_knowledge_frame_refs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                frame_id INTEGER NOT NULL,
                FOREIGN KEY(frame_id) REFERENCES knowledge_frames(id) ON DELETE RESTRICT
            );
            INSERT INTO guarded_knowledge_frame_refs (frame_id) VALUES (\(frame.id));
            """
        )

        XCTAssertThrowsError(try store.delete(id: frame.id))

        XCTAssertEqual(try store.get(id: frame.id).name, "Protected frame")
        XCTAssertEqual(try store.search(query: "Protected").map(\.id), [frame.id])
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        let database = TestDatabaseClient(connection: connection)
        try database.migrate(CoreMigrations.phase2)
        return connection
    }

    private func currentConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private func rowCount(_ table: String, connection: SQLiteConnection) throws -> Int {
        let rawCount = try XCTUnwrap(connection.queryStrings("SELECT COUNT(*) FROM \(table);").first)
        return try XCTUnwrap(Int(rawCount))
    }
}

private final class TestDatabaseClient: DatabaseClient {
    private let connection: SQLiteConnection

    init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func migrate(_ migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try appliedMigrationIDs())
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }

    func appliedMigrationIDs() throws -> [String] {
        try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;")
    }

    func tableExists(_ tableName: String) throws -> Bool {
        try connection.tableExists(tableName)
    }
}
