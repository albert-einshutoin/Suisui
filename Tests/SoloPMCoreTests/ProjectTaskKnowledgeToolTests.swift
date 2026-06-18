import XCTest
@testable import SoloPMCore

final class ProjectTaskKnowledgeToolTests: XCTestCase {
    func testProjectCreateToolPersistsProjectWithApproval() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        let result = try tool.execute(
            arguments: ["title": .string("  Launch alpha  ")],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(try stores.projects.list().first?.title, "Launch alpha")
        XCTAssertNotNil(result.rollbackMetadata["projectId"])
    }

    func testProjectCreateRejectsNonStringTagsWithoutCreatingProject() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Launch alpha"),
                    "tags": .array([.string("oss"), .number(1)])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectCreate, "Argument 'tags[1]' must be string."))
        }

        XCTAssertEqual(try stores.projects.list(), [])
    }

    func testProjectCreateRejectsBlankTagsWithoutCreatingProject() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Launch alpha"),
                    "tags": .array([.string("oss"), .string("  ")])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectCreate, "Argument 'tags[1]' cannot be blank."))
        }

        XCTAssertEqual(try stores.projects.list(), [])
    }

    func testProjectUpdateRejectsBlankTitleWithoutMutatingProject() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = ProjectTool(name: .projectUpdate, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "id": .number(Double(project.id)),
                    "title": .string("   ")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.projectUpdate, "Argument 'title' cannot be blank."))
        }

        XCTAssertEqual(try stores.projects.get(id: project.id).title, "Launch Readiness")
    }

    func testTaskBulkCreatePersistsTasksTransactionallyEnoughForMVP() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks)

        let result = try tool.execute(
            arguments: [
                "tasks": .array([
                    .object(["title": .string("Draft")]),
                    .object(["title": .string("Review")])
                ])
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.summary, "Created 2 tasks")
        XCTAssertEqual(try stores.tasks.listAll().map(\.title), ["Draft", "Review"])
    }

    func testProjectCompleteToolCompletesOpenProjectTasks() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let task = try stores.tasks.create(
            title: "Prepare release notes",
            projectID: project.id,
            status: "planned"
        )
        let tool = ProjectTool(name: .projectComplete, store: stores.projects, taskStore: stores.tasks)

        let result = try tool.execute(
            arguments: ["id": .number(Double(project.id))],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(try stores.projects.get(id: project.id).status, "completed")
        XCTAssertEqual(try stores.tasks.get(id: task.id).status, "completed")
    }

    func testProjectCompleteToolRequiresTaskStore() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = ProjectTool(name: .projectComplete, store: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: ["id": .number(Double(project.id))],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.projectComplete, "Task store is required to complete project tasks.")
            )
        }
        XCTAssertEqual(try stores.projects.get(id: project.id).status, "active")
    }

    func testTaskCreateToolReopensCompletedProjectForNewOpenWork() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        _ = try stores.projects.update(id: project.id, status: "completed")
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        _ = try tool.execute(
            arguments: [
                "title": .string("  Address release review  "),
                "projectId": .number(Double(project.id))
            ],
            context: approvedContext()
        )

        XCTAssertEqual(try stores.projects.get(id: project.id).status, "active")
        XCTAssertEqual(try stores.tasks.listAll().map(\.title), ["Address release review"])
    }

    func testTaskCreateRejectsNonStringOptionalFieldsWithoutCreatingTask() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Ship alpha"),
                    "dueAt": .number(1)
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskCreate, "Argument 'dueAt' must be string."))
        }

        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskUpdateRejectsBlankTitleWithoutMutatingTask() throws {
        let stores = try makeStores()
        let task = try stores.tasks.create(title: "Draft release notes")
        let tool = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "id": .number(Double(task.id)),
                    "title": .string("   ")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskUpdate, "Argument 'title' cannot be blank."))
        }

        XCTAssertEqual(try stores.tasks.get(id: task.id).title, "Draft release notes")
    }

    func testTaskUpdateRejectsInvalidStatusWithoutReopeningCompletedProject() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Completed Initiative")
        _ = try stores.projects.update(id: project.id, status: "completed")
        let task = try stores.tasks.create(
            title: "Already shipped",
            projectID: project.id,
            status: "completed"
        )
        let tool = TaskTool(name: .taskUpdate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "id": .number(Double(task.id)),
                    "status": .string("parked")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskUpdate, "Argument 'status' must be one of open, backlog, planned, in_progress, blocked, completed.")
            )
        }

        XCTAssertEqual(try stores.projects.get(id: project.id).status, "completed")
        XCTAssertEqual(try stores.tasks.get(id: task.id).status, "completed")
    }

    func testTaskCreateWithProjectIDRequiresProjectStore() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Launch Readiness")
        let tool = TaskTool(name: .taskCreate, store: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Unvalidated project task"),
                    "projectId": .number(Double(project.id))
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.taskCreate, "Project store is required to validate project task mutations.")
            )
        }
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskCreateToolRejectsArchivedProject() throws {
        let stores = try makeStores()
        let project = try stores.projects.create(title: "Paused Initiative")
        _ = try stores.projects.archive(id: project.id)
        let tool = TaskTool(name: .taskCreate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Hidden follow-up"),
                    "projectId": .number(Double(project.id))
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskCreate, "Restore the project before adding tasks.")
            )
        }
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreateRejectsArchivedProjectWithoutReopeningCompletedProject() throws {
        let stores = try makeStores()
        let completedProject = try stores.projects.create(title: "Completed Initiative")
        let archivedProject = try stores.projects.create(title: "Paused Initiative")
        _ = try stores.projects.update(id: completedProject.id, status: "completed")
        _ = try stores.projects.archive(id: archivedProject.id)
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks, projectStore: stores.projects)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "tasks": .array([
                        .object([
                            "title": .string("Follow-up work"),
                            "projectId": .number(Double(completedProject.id))
                        ]),
                        .object([
                            "title": .string("Hidden archived work"),
                            "projectId": .number(Double(archivedProject.id))
                        ])
                    ])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .validationFailed(.taskBulkCreate, "Restore the project before adding tasks.")
            )
        }

        XCTAssertEqual(try stores.projects.get(id: completedProject.id).status, "completed")
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreateRejectsInvalidBatchWithoutPartialRows() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "tasks": .array([
                        .object(["title": .string("Draft")]),
                        .object(["dueAt": .string("2026-06-18T09:00:00Z")])
                    ])
                ],
                context: approvedContext()
            )
        )

        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testTaskBulkCreateRejectsNonObjectItemsWithoutPartialRows() throws {
        let stores = try makeStores()
        let tool = TaskTool(name: .taskBulkCreate, store: stores.tasks)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "tasks": .array([
                        .object(["title": .string("Draft")]),
                        .string("Review")
                    ])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.taskBulkCreate, "Argument 'tasks[1]' must be object."))
        }

        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testKnowledgeFrameCreateAndSearchUseSameStore() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let search = KnowledgeFrameTool(name: .frameSearch, store: stores.knowledge)

        _ = try create.execute(
            arguments: [
                "name": .string("Release checklist"),
                "body": .string("Use notarization and checksum before alpha release.")
            ],
            context: approvedContext()
        )
        let result = try search.execute(arguments: ["query": .string("notarization")], context: ToolExecutionContext(source: .developerTool))

        XCTAssertEqual(result.output["count"], .number(1))
    }

    func testKnowledgeFrameCreateRejectsNonStringTriggersWithoutCreatingFrame() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)

        XCTAssertThrowsError(
            try create.execute(
                arguments: [
                    "name": .string("Release checklist"),
                    "body": .string("Use notarization."),
                    "triggers": .array([.string("release"), .number(1)])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameCreate, "Argument 'triggers[1]' must be string."))
        }

        XCTAssertEqual(try stores.knowledge.list(), [])
    }

    func testKnowledgeFrameUpdatePreservesTriggersWhenOmitted() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let update = KnowledgeFrameTool(name: .frameUpdate, store: stores.knowledge)

        let created = try create.execute(
            arguments: [
                "name": .string("Writing frame"),
                "body": .string("Initial"),
                "triggers": .array([.string("writing")])
            ],
            context: approvedContext()
        )
        let frameID = try XCTUnwrap(created.output["frameId"]?.int64Value)

        _ = try update.execute(
            arguments: [
                "id": .number(Double(frameID)),
                "body": .string("Updated")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(try stores.knowledge.get(id: frameID).triggers, ["writing"])
    }

    func testKnowledgeFrameUpdateRejectsBlankTriggersWithoutMutatingFrame() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let update = KnowledgeFrameTool(name: .frameUpdate, store: stores.knowledge)

        let created = try create.execute(
            arguments: [
                "name": .string("Writing frame"),
                "body": .string("Initial"),
                "triggers": .array([.string("release")])
            ],
            context: approvedContext()
        )
        let frameID = try XCTUnwrap(created.output["frameId"]?.int64Value)

        XCTAssertThrowsError(
            try update.execute(
                arguments: [
                    "id": .number(Double(frameID)),
                    "triggers": .array([.string("writing"), .string("  ")])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameUpdate, "Argument 'triggers[1]' cannot be blank."))
        }

        XCTAssertEqual(try stores.knowledge.get(id: frameID).triggers, ["release"])
    }

    func testKnowledgeFrameUpdateRejectsBlankBodyWithoutMutatingFrame() throws {
        let stores = try makeStores()
        let create = KnowledgeFrameTool(name: .frameCreate, store: stores.knowledge)
        let update = KnowledgeFrameTool(name: .frameUpdate, store: stores.knowledge)
        let created = try create.execute(
            arguments: [
                "name": .string("Release frame"),
                "body": .string("Initial content")
            ],
            context: approvedContext()
        )
        let frameID = try XCTUnwrap(created.output["frameId"]?.int64Value)

        XCTAssertThrowsError(
            try update.execute(
                arguments: [
                    "id": .number(Double(frameID)),
                    "body": .string("   ")
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.frameUpdate, "Argument 'body' cannot be blank."))
        }

        XCTAssertEqual(try stores.knowledge.get(id: frameID).body, "Initial content")
    }

    func testPhase2CoreRegistryContainsProjectTaskAndKnowledgeTools() throws {
        let stores = try makeStores()
        let registry = try ToolRegistry.phase2Core(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            knowledgeStore: stores.knowledge
        )

        XCTAssertTrue(registry.contains(.projectCreate))
        XCTAssertTrue(registry.contains(.taskCreate))
        XCTAssertTrue(registry.contains(.frameSearch))
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, knowledge: SQLiteKnowledgeFrameStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"), source: .developerTool)
    }
}

private enum TestMigrationRunner {
    static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try migration.apply(connection)
            try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(migration.id)');")
        }
    }
}

private extension JSONValue {
    var int64Value: Int64? {
        guard case .number(let value) = self else {
            return nil
        }
        return Int64(value)
    }
}
