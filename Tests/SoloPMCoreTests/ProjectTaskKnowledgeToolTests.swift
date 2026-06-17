import XCTest
@testable import SoloPMCore

final class ProjectTaskKnowledgeToolTests: XCTestCase {
    func testProjectCreateToolPersistsProjectWithApproval() throws {
        let stores = try makeStores()
        let tool = ProjectTool(name: .projectCreate, store: stores.projects)

        let result = try tool.execute(
            arguments: ["title": .string("Launch alpha")],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(try stores.projects.list().first?.title, "Launch alpha")
        XCTAssertNotNil(result.rollbackMetadata["projectId"])
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
        XCTAssertEqual(try stores.tasks.listDue(onOrBefore: "9999").count, 0)
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
        let result = try search.execute(arguments: ["query": .string("notarization")], context: ToolExecutionContext(source: .test))

        XCTAssertEqual(result.output["count"], .number(1))
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
        ToolExecutionContext(approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"), source: .test)
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
