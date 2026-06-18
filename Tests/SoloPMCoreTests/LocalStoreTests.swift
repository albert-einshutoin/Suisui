import XCTest
@testable import SoloPMCore

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

    func testKnowledgeFrameStoreSearchesWithFTS5() throws {
        let connection = try migratedConnection()
        let store = SQLiteKnowledgeFrameStore(connection: connection)

        _ = try store.create(name: "QZT article", body: "Publish the QZT article checklist", triggers: ["qzt"])

        let results = try store.search(query: "QZT")

        XCTAssertEqual(results.map(\.name), ["QZT article"])
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        let database = TestDatabaseClient(connection: connection)
        try database.migrate(CoreMigrations.phase2)
        return connection
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
