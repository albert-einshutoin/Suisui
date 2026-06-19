import XCTest
@testable import SoloPMCore

final class DatabaseMigrationTests: XCTestCase {
    func testDatabaseLocationCanUseAbsoluteEnvironmentOverrideForRuntimeSmokeIsolation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-db-location-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("nested/SoloPM-runtime-smoke.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let resolvedURL = try SoloPMAppDatabaseLocation.defaultDatabaseURL(
            createDirectory: true,
            environment: [SoloPMAppDatabaseLocation.databasePathOverrideEnvironmentKey: databaseURL.path]
        )

        XCTAssertEqual(resolvedURL, databaseURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testDatabaseLocationRejectsRelativeEnvironmentOverride() throws {
        XCTAssertThrowsError(
            try SoloPMAppDatabaseLocation.defaultDatabaseURL(
                createDirectory: false,
                environment: [SoloPMAppDatabaseLocation.databasePathOverrideEnvironmentKey: "relative/SoloPM.sqlite"]
            )
        ) { error in
            guard case let DatabaseError.openFailed(message) = error else {
                XCTFail("Expected DatabaseError.openFailed, got \(error).")
                return
            }
            XCTAssertTrue(message.contains(SoloPMAppDatabaseLocation.databasePathOverrideEnvironmentKey))
            XCTAssertTrue(message.contains("absolute"))
        }
    }

    func testSQLiteConnectionEnforcesForeignKeyConstraints() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute(
            """
            CREATE TABLE parent_records (
                id INTEGER PRIMARY KEY NOT NULL
            );
            CREATE TABLE child_records (
                id INTEGER PRIMARY KEY NOT NULL,
                parent_id INTEGER NOT NULL,
                FOREIGN KEY(parent_id) REFERENCES parent_records(id)
            );
            """
        )

        XCTAssertThrowsError(
            try connection.execute("INSERT INTO child_records (id, parent_id) VALUES (1, 404);")
        ) { error in
            guard case let DatabaseError.executeFailed(message) = error else {
                XCTFail("Expected SQLite foreign key enforcement, got \(error).")
                return
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("foreign key"))
        }
    }

    func testPhase0MigrationsAreIdempotent() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.phase0)
        try database.migrate(CoreMigrations.phase0)

        XCTAssertEqual(
            try database.appliedMigrationIDs(),
            ["0001_create_settings_and_audit_logs"]
        )
        XCTAssertTrue(try database.tableExists("settings"))
        XCTAssertTrue(try database.tableExists("audit_logs"))
    }

    func testPhase2MigrationsCreateSystemToolTrackingTables() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.phase2)

        XCTAssertTrue(try database.tableExists("notification_requests"))
        XCTAssertTrue(try database.tableExists("calendar_links"))
        XCTAssertTrue(try database.tableExists("reminder_links"))
        XCTAssertTrue(try database.appliedMigrationIDs().contains("0002b_create_system_tool_state"))
    }

    func testCurrentMigrationsUpgradeExistingTaskTableWithDetailColumn() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let taskColumns = try connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
        let appliedMigrationIDs = try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;")

        XCTAssertTrue(taskColumns.contains("detail"))
        XCTAssertTrue(appliedMigrationIDs.contains("0007_add_task_detail"))
    }

    func testCurrentMigrationsCreateMCPRegistrationTable() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.current)

        XCTAssertTrue(try database.tableExists("mcp_server_registrations"))
        XCTAssertTrue(try database.appliedMigrationIDs().contains("0008_create_mcp_server_registrations"))
    }
}
