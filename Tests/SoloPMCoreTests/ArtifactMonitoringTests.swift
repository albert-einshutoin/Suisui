import XCTest
@testable import SoloPMCore

final class ArtifactMonitoringTests: XCTestCase {
    func testArtifactStorePersistsExpectedPathCreatedStateAndLastModifiedAt() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let lastModifiedAt = try Date.iso8601("2026-06-10T09:30:00Z")

        let artifact = try store.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/reports/status.md",
            createdState: .created,
            lastModifiedAt: lastModifiedAt
        )

        XCTAssertTrue(try connection.tableExists("artifacts"))
        XCTAssertEqual(artifact.workspacePath, "/tmp/solopm")
        XCTAssertEqual(artifact.expectedPath, "/tmp/solopm/reports/status.md")
        XCTAssertEqual(artifact.createdState, .created)
        XCTAssertEqual(artifact.lastModifiedAt, lastModifiedAt)
    }

    func testFakeFileMonitorUpdatesArtifactInsideWorkspace() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        _ = try store.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/reports/status.md"
        )
        let modifiedAt = try Date.iso8601("2026-06-17T12:00:00Z")
        let monitor = FakeFileMonitorClient(
            events: [
                FileMonitorEvent(
                    path: "/tmp/solopm/reports/status.md",
                    kind: .modified,
                    modifiedAt: modifiedAt
                )
            ]
        )
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: monitor,
            workspacePath: "/tmp/solopm",
            dateProvider: FixedDateProvider(now: modifiedAt)
        )

        let result = try service.applyNextEvent()

        XCTAssertEqual(result.updatedArtifacts.count, 1)
        XCTAssertEqual(result.updatedArtifacts.first?.createdState, .created)
        XCTAssertEqual(result.updatedArtifacts.first?.lastModifiedAt, modifiedAt)
        XCTAssertNil(result.skippedReason)
    }

    func testArtifactMonitorSkipsEventsOutsideWorkspace() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        _ = try store.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/elsewhere/status.md"
        )
        let now = try Date.iso8601("2026-06-17T12:00:00Z")
        let monitor = FakeFileMonitorClient(
            events: [
                FileMonitorEvent(
                    path: "/tmp/elsewhere/status.md",
                    kind: .modified,
                    modifiedAt: now
                )
            ]
        )
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: monitor,
            workspacePath: "/tmp/solopm",
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try service.applyNextEvent()

        XCTAssertEqual(result.updatedArtifacts, [])
        XCTAssertEqual(result.skippedReason, "outside_workspace")
        XCTAssertEqual(try store.list().first?.createdState, .expected)
    }

    func testArtifactMonitorUpdatesOnlyMatchingWorkspaceRecord() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        _ = try store.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/reports/status.md"
        )
        _ = try store.create(
            workspacePath: "/tmp/other",
            expectedPath: "/tmp/solopm/reports/status.md"
        )
        let now = try Date.iso8601("2026-06-17T12:00:00Z")
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: FakeFileMonitorClient(
                events: [
                    FileMonitorEvent(
                        path: "/tmp/solopm/reports/status.md",
                        kind: .modified,
                        modifiedAt: now
                    )
                ]
            ),
            workspacePath: "/tmp/solopm",
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try service.applyNextEvent()
        let records = try store.list()

        XCTAssertEqual(result.updatedArtifacts.map(\.workspacePath), ["/tmp/solopm"])
        XCTAssertEqual(records[0].createdState, .created)
        XCTAssertEqual(records[1].createdState, .expected)
    }

    func testArtifactMonitorDetectsStaleArtifacts() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let now = try Date.iso8601("2026-06-17T12:00:00Z")
        _ = try store.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/reports/old.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-01T12:00:00Z")
        )
        _ = try store.create(
            workspacePath: "/tmp/solopm",
            expectedPath: "/tmp/solopm/reports/recent.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-16T12:00:00Z")
        )
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: FakeFileMonitorClient(),
            workspacePath: "/tmp/solopm",
            dateProvider: FixedDateProvider(now: now)
        )

        let stale = try service.staleArtifacts(olderThan: 7 * 24 * 60 * 60)

        XCTAssertEqual(stale.map(\.expectedPath), ["/tmp/solopm/reports/old.md"])
    }

    func testWorkspacePathPolicyHandlesTrailingSlashAndSiblingPrefix() {
        XCTAssertTrue(WorkspacePathPolicy.isPath("/tmp/solopm/reports/status.md", inside: "/tmp/solopm/"))
        XCTAssertFalse(WorkspacePathPolicy.isPath("/tmp/solopm-other/status.md", inside: "/tmp/solopm"))
    }

    private func makeConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        return connection
    }
}

private struct FixedDateProvider: DateProvider {
    let now: Date
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

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
