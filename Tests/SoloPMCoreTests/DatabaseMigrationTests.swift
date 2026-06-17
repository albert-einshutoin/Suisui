import XCTest
@testable import SoloPMCore

final class DatabaseMigrationTests: XCTestCase {
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
}

