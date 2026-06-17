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

    func testTaskStoreCreatesAndQueriesDueTasks() throws {
        let connection = try migratedConnection()
        let store = SQLiteTaskStore(connection: connection)

        _ = try store.create(title: "Soon", dueAt: "2026-06-17T00:00:00Z")
        _ = try store.create(title: "Later", dueAt: "2026-06-20T00:00:00Z")

        let due = try store.listDue(onOrBefore: "2026-06-18T00:00:00Z")

        XCTAssertEqual(due.map(\.title), ["Soon"])
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
