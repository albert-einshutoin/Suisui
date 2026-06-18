import XCTest
@testable import SoloPMCore

final class SoloPMCLIReadOnlyReporterTests: XCTestCase {
    func testStatusReadsPersistentProjectTaskAndKnowledgeCounts() throws {
        let databaseURL = try makeSeededDatabase()
        let reporter = SoloPMCLIReadOnlyReporter(databaseURL: databaseURL, now: fixedNow())

        let lines = try reporter.statusLines()

        XCTAssertEqual(
            lines,
            [
                "SoloPM CLI status",
                "database: \(databaseURL.path)",
                "projects active: 1",
                "projects archived: 1",
                "tasks open: 1",
                "tasks due: 1",
                "knowledge frames: 1"
            ]
        )
    }

    func testTasksDueReadsDueTasksAndExcludesCompletedArchivedOrCompletedProjectTasks() throws {
        let databaseURL = try makeSeededDatabase()
        let reporter = SoloPMCLIReadOnlyReporter(databaseURL: databaseURL, now: fixedNow())

        let lines = try reporter.tasksDueLines()

        XCTAssertEqual(lines.first, "SoloPM tasks due")
        XCTAssertTrue(lines.contains("database: \(databaseURL.path)"))
        XCTAssertTrue(lines.contains("count: 1"))
        XCTAssertTrue(lines.contains("- Due Task | due: 2026-06-18T00:00:00Z | priority: high"))
        XCTAssertFalse(lines.joined(separator: "\n").contains("Completed Task"))
        XCTAssertFalse(lines.joined(separator: "\n").contains("Archived Task"))
        XCTAssertFalse(lines.joined(separator: "\n").contains("Completed Project Task"))
    }

    func testFramesSearchReadsKnowledgeFrameFTS() throws {
        let databaseURL = try makeSeededDatabase()
        let reporter = SoloPMCLIReadOnlyReporter(databaseURL: databaseURL, now: fixedNow())

        let lines = try reporter.framesSearchLines(query: "release readiness")

        XCTAssertEqual(lines.first, "SoloPM frames search")
        XCTAssertTrue(lines.contains("query: release readiness"))
        XCTAssertTrue(lines.contains("count: 1"))
        XCTAssertTrue(lines.contains("- Release readiness frame"))
    }

    func testMissingDatabaseDoesNotCreateFile() throws {
        let databaseURL = temporaryDirectory().appendingPathComponent("missing.sqlite")
        let reporter = SoloPMCLIReadOnlyReporter(databaseURL: databaseURL, now: fixedNow())

        let lines = try reporter.statusLines()

        XCTAssertEqual(
            lines,
            [
                "SoloPM CLI status",
                "database: missing \(databaseURL.path)"
            ]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testCountValueDecodeDoesNotDefaultInvalidCountsToZero() throws {
        XCTAssertEqual(try SoloPMCLIReadOnlyReporter.parseCountValue("3"), 3)

        XCTAssertThrowsError(try SoloPMCLIReadOnlyReporter.parseCountValue(nil)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .missingRequiredColumn(column: "count"))
        }

        XCTAssertThrowsError(try SoloPMCLIReadOnlyReporter.parseCountValue("not-a-count")) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidInt64(column: "count", value: "not-a-count"))
        }
    }

    private func makeSeededDatabase() throws -> URL {
        let databaseURL = temporaryDirectory().appendingPathComponent("SoloPM.sqlite")
        let connection = try SQLiteConnection(path: databaseURL.path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let frameStore = SQLiteKnowledgeFrameStore(connection: connection)

        let activeProject = try projectStore.create(title: "Active Project")
        let archivedProject = try projectStore.create(title: "Archived Project")
        let completedProject = try projectStore.create(title: "Completed Project")
        _ = try projectStore.archive(id: archivedProject.id)
        _ = try projectStore.update(id: completedProject.id, status: "completed")

        _ = try taskStore.create(
            title: "Due Task",
            projectID: activeProject.id,
            dueAt: "2026-06-18T00:00:00Z",
            priority: "high"
        )
        _ = try taskStore.create(
            title: "Completed Task",
            projectID: activeProject.id,
            dueAt: "2026-06-18T00:00:00Z",
            priority: "medium",
            status: "completed"
        )
        _ = try taskStore.create(
            title: "Archived Task",
            projectID: archivedProject.id,
            dueAt: "2026-06-18T00:00:00Z",
            priority: "low"
        )
        _ = try taskStore.create(
            title: "Completed Project Task",
            projectID: completedProject.id,
            dueAt: "2026-06-18T00:00:00Z",
            priority: "high"
        )
        _ = try frameStore.create(
            name: "Release readiness frame",
            body: "release readiness checklist",
            triggers: ["release"]
        )

        return databaseURL
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    private func fixedNow() -> Date {
        ISO8601DateFormatter().date(from: "2026-06-18T00:00:00Z") ?? Date(timeIntervalSince1970: 0)
    }
}
