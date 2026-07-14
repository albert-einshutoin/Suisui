import XCTest
@testable import SoloPMCore

/// Store-level coverage for the real palette content-search provider running
/// against a temp SQLite fixture: sanitized task LIKE fallback (tasks have no
/// FTS table) plus knowledge FTS reuse.
final class CommandPaletteContentSearchServiceTests: XCTestCase {
    func testTaskDetailHitsLeadAndKnowledgeHitsFillRemainingSlots() throws {
        let connection = try migratedConnection()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let knowledgeStore = SQLiteKnowledgeFrameStore(connection: connection)
        let service = CommandPaletteContentSearchService(taskStore: taskStore, knowledgeFrameStore: knowledgeStore)

        let project = try projectStore.create(title: "Billing")
        let task = try taskStore.create(
            title: "Prepare quarterly report",
            projectID: project.id,
            detail: "Collect every invoice from March before drafting."
        )
        _ = try knowledgeStore.create(name: "Billing rules", body: "Each invoice must reference the contract number.")

        let matches = service.search(query: "invoice")

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].source, .task(id: task.id, projectID: project.id))
        XCTAssertEqual(matches[0].title, "Prepare quarterly report")
        XCTAssertTrue(matches[0].content.contains("invoice"))
        guard case .knowledge = matches[1].source else {
            return XCTFail("Expected the knowledge hit after the task hit, got \(matches[1].source)")
        }
        XCTAssertEqual(matches[1].title, "Billing rules")
    }

    func testTaskTitleHitsMatchWithoutDetailAndInboxTasksKeepNilProjectID() throws {
        let connection = try migratedConnection()
        let taskStore = SQLiteTaskStore(connection: connection)
        let service = CommandPaletteContentSearchService(
            taskStore: taskStore,
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )

        let inboxTask = try taskStore.create(title: "Renew passport before summer")

        let matches = service.search(query: "passport")

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].source, .task(id: inboxTask.id, projectID: nil))
        XCTAssertEqual(matches[0].content, "Renew passport before summer")
    }

    func testCompletedTasksAreExcluded() throws {
        let connection = try migratedConnection()
        let taskStore = SQLiteTaskStore(connection: connection)
        let service = CommandPaletteContentSearchService(
            taskStore: taskStore,
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )

        _ = try taskStore.create(title: "Archive the beta feedback", status: "completed")
        let openTask = try taskStore.create(title: "Read the beta feedback")

        XCTAssertEqual(
            service.search(query: "beta feedback").map(\.source),
            [.task(id: openTask.id, projectID: nil)]
        )
    }

    func testTasksInArchivedProjectsAreExcludedWhileInboxAndActiveTasksRemainSearchable() throws {
        let connection = try migratedConnection()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let service = CommandPaletteContentSearchService(
            taskStore: taskStore,
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        let activeProject = try projectStore.create(title: "Active")
        let archivedProject = try projectStore.create(title: "Archived")
        _ = try projectStore.archive(id: archivedProject.id)
        let activeTask = try taskStore.create(title: "Review launch brief", projectID: activeProject.id)
        _ = try taskStore.create(title: "Review archived brief", projectID: archivedProject.id)
        let inboxTask = try taskStore.create(title: "Review inbox brief")

        XCTAssertEqual(
            service.search(query: "review").map(\.source),
            [
                .task(id: inboxTask.id, projectID: nil),
                .task(id: activeTask.id, projectID: activeProject.id),
            ]
        )
    }

    func testResultsAreCappedAtComposerLimit() throws {
        let connection = try migratedConnection()
        let taskStore = SQLiteTaskStore(connection: connection)
        let service = CommandPaletteContentSearchService(
            taskStore: taskStore,
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )

        for index in 1...7 {
            _ = try taskStore.create(title: "Rehearsal step \(index)", detail: "shared keyword rehearsal")
        }

        XCTAssertEqual(service.search(query: "rehearsal").count, CommandPaletteComposer.maxContentItemCount)
    }

    func testQuotesAsterisksAndLikeWildcardsAreSanitizedNotInterpreted() throws {
        let connection = try migratedConnection()
        let taskStore = SQLiteTaskStore(connection: connection)
        let knowledgeStore = SQLiteKnowledgeFrameStore(connection: connection)
        let service = CommandPaletteContentSearchService(taskStore: taskStore, knowledgeFrameStore: knowledgeStore)

        let progressTask = try taskStore.create(title: "Migration", detail: "Roughly 50% done as of Friday")
        _ = try taskStore.create(title: "Unrelated", detail: "Fully done as of Friday")
        _ = try knowledgeStore.create(name: "Quoting", body: "Use \"smart quotes\" sparingly.")

        // FTS control characters must not throw; the store-level sanitizer
        // (quoted phrase + escaped quotes) is reused, not reimplemented.
        XCTAssertNoThrow(_ = service.search(query: "\"smart quotes\""))
        XCTAssertNoThrow(_ = service.search(query: "quote*"))
        XCTAssertNoThrow(_ = service.search(query: "AND OR NEAR("))

        // LIKE wildcards match literally: only the task actually containing
        // "50%" comes back, not every "…done…" row.
        XCTAssertEqual(
            service.search(query: "50% done").map(\.source),
            [.task(id: progressTask.id, projectID: nil)]
        )
        XCTAssertTrue(service.search(query: "0_ done").isEmpty)
    }

    func testShortQueriesReturnNothing() throws {
        let connection = try migratedConnection()
        let taskStore = SQLiteTaskStore(connection: connection)
        let service = CommandPaletteContentSearchService(
            taskStore: taskStore,
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        _ = try taskStore.create(title: "A single letter should not query")

        XCTAssertTrue(service.search(query: "a").isEmpty)
        XCTAssertTrue(service.search(query: "  a  ").isEmpty)
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }
}
