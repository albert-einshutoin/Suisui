import XCTest
@testable import SuisuiCore

final class WorkspaceBackupTests: XCTestCase {
    private struct Stores {
        let projectStore: SQLiteProjectStore
        let taskStore: SQLiteTaskStore
        let knowledgeFrameStore: SQLiteKnowledgeFrameStore
    }

    private func makeStores() throws -> Stores {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return Stores(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    private func makeExporter(_ stores: Stores) -> WorkspaceBackupExporter {
        WorkspaceBackupExporter(
            projectStore: stores.projectStore,
            taskStore: stores.taskStore,
            knowledgeFrameStore: stores.knowledgeFrameStore
        )
    }

    private func makeImporter(_ stores: Stores) -> WorkspaceBackupImporter {
        WorkspaceBackupImporter(
            projectStore: stores.projectStore,
            taskStore: stores.taskStore,
            knowledgeFrameStore: stores.knowledgeFrameStore
        )
    }

    func testExportIncludesArchivedProjectsCompletedTasksAndRecurrence() throws {
        let stores = try makeStores()
        let activeProject = try stores.projectStore.create(title: "Active Project", tags: ["launch"])
        let archivedProject = try stores.projectStore.create(title: "Archived Project")
        _ = try stores.projectStore.archive(id: archivedProject.id)
        let completedProject = try stores.projectStore.create(title: "Completed Project")
        _ = try stores.projectStore.complete(id: completedProject.id, taskStore: stores.taskStore)

        let openTask = try stores.taskStore.create(
            title: "Open recurring task",
            projectID: activeProject.id,
            dueAt: "2026-07-08T09:00:00Z",
            priority: "high",
            detail: "Weekly release check",
            recurrence: "weekly"
        )
        let completedTask = try stores.taskStore.create(
            title: "Completed task",
            projectID: archivedProject.id,
            status: "completed"
        )
        _ = try stores.knowledgeFrameStore.create(name: "Release ritual", body: "Check evidence first", triggers: ["release"])

        let document = try makeExporter(stores).export(now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(document.formatVersion, 1)
        XCTAssertEqual(Set(document.projects.map(\.title)), ["Active Project", "Archived Project", "Completed Project"])
        XCTAssertEqual(document.projects.first { $0.title == "Archived Project" }?.status, "archived")
        XCTAssertEqual(document.projects.first { $0.title == "Completed Project" }?.status, "completed")
        XCTAssertEqual(document.projects.first { $0.title == "Active Project" }?.tags, ["launch"])

        XCTAssertEqual(Set(document.tasks.map(\.title)), ["Open recurring task", "Completed task"])
        let exportedOpenTask = try XCTUnwrap(document.tasks.first { $0.id == openTask.id })
        XCTAssertEqual(exportedOpenTask.recurrence, "weekly")
        XCTAssertEqual(exportedOpenTask.detail, "Weekly release check")
        XCTAssertEqual(exportedOpenTask.dueAt, "2026-07-08T09:00:00Z")
        XCTAssertEqual(exportedOpenTask.projectID, activeProject.id)
        let exportedCompletedTask = try XCTUnwrap(document.tasks.first { $0.id == completedTask.id })
        XCTAssertEqual(exportedCompletedTask.status, "completed")
        XCTAssertNotNil(exportedCompletedTask.completedAt)

        XCTAssertEqual(document.knowledgeFrames.count, 1)
        XCTAssertEqual(document.knowledgeFrames.first?.triggers, ["release"])
    }

    func testJSONEncodingRoundTripsAndUsesStableFormat() throws {
        let document = WorkspaceBackupDocument(
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            projects: [
                .init(id: 3, title: "P", status: "active", priority: "high", deadline: "2026-08-01", tags: ["a", "b"])
            ],
            tasks: [
                .init(
                    id: 9,
                    projectID: 3,
                    title: "T",
                    status: "completed",
                    dueAt: "2026-07-10T09:00:00Z",
                    completedAt: "2026-07-06T10:00:00Z",
                    priority: "low",
                    detail: "d",
                    recurrence: "daily"
                )
            ],
            knowledgeFrames: [.init(id: 4, name: "K", body: "B", triggers: ["t"])]
        )

        let data = try WorkspaceBackupCoding.encode(document)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"formatVersion\" : 1"))
        XCTAssertTrue(json.contains("2023-11-14T22:13:20Z"), "exportedAt must serialize as ISO 8601")

        let decoded = try WorkspaceBackupCoding.decode(data)
        XCTAssertEqual(decoded, document)

        // Sorted keys keep the wire format deterministic across encodes.
        XCTAssertEqual(try WorkspaceBackupCoding.encode(decoded), data)
    }

    func testMergeRestoreRemapsProjectIDsAndPreservesFields() throws {
        let source = try makeStores()
        let sourceProject = try source.projectStore.create(title: "Ported Project", priority: "high", deadline: "2026-08-01")
        let archived = try source.projectStore.create(title: "Ported Archived")
        _ = try source.projectStore.archive(id: archived.id)
        _ = try source.taskStore.create(
            title: "Ported open task",
            projectID: sourceProject.id,
            dueAt: "2026-07-09T09:00:00Z",
            priority: "medium",
            detail: "carry detail",
            recurrence: "monthly"
        )
        _ = try source.taskStore.create(title: "Ported unassigned task")
        let document = try makeExporter(source).export()

        let target = try makeStores()
        // Occupy low row IDs so restored project IDs cannot collide with the
        // backup's original IDs by coincidence.
        _ = try target.projectStore.create(title: "Existing A")
        _ = try target.projectStore.create(title: "Existing B")
        _ = try target.projectStore.create(title: "Existing C")

        let summary = try makeImporter(target).restore(document, mode: .merge)

        XCTAssertEqual(summary.projectsCreated, 2)
        XCTAssertEqual(summary.tasksCreated, 2)
        XCTAssertEqual(summary.framesCreated, 0)
        XCTAssertEqual(summary.framesSkipped, 0)

        let restoredProjects = try target.projectStore.list(includeArchived: true)
        XCTAssertEqual(restoredProjects.count, 5)
        let restoredProject = try XCTUnwrap(restoredProjects.first { $0.title == "Ported Project" })
        XCTAssertNotEqual(restoredProject.id, sourceProject.id)
        XCTAssertEqual(restoredProject.priority, "high")
        XCTAssertEqual(restoredProject.deadline, "2026-08-01")
        let restoredArchived = try XCTUnwrap(restoredProjects.first { $0.title == "Ported Archived" })
        XCTAssertEqual(restoredArchived.status, "archived")

        let restoredTasks = try target.taskStore.listAll()
        XCTAssertEqual(restoredTasks.count, 2)
        let restoredTask = try XCTUnwrap(restoredTasks.first { $0.title == "Ported open task" })
        XCTAssertEqual(restoredTask.projectID, restoredProject.id, "task projectID must be remapped to the new project row")
        XCTAssertEqual(restoredTask.recurrence, "monthly")
        XCTAssertEqual(restoredTask.detail, "carry detail")
        XCTAssertEqual(restoredTask.dueAt, "2026-07-09T09:00:00Z")
        let unassigned = try XCTUnwrap(restoredTasks.first { $0.title == "Ported unassigned task" })
        XCTAssertNil(unassigned.projectID)
    }

    func testMergeRestorePreservesCompletedAtAndDedupesFrames() throws {
        let target = try makeStores()
        _ = try target.knowledgeFrameStore.create(name: "Shared frame", body: "Same body", triggers: ["old"])

        let document = WorkspaceBackupDocument(
            exportedAt: Date(),
            projects: [],
            tasks: [
                .init(
                    id: 1,
                    projectID: nil,
                    title: "Done long ago",
                    status: "completed",
                    completedAt: "2025-12-31T09:30:00Z"
                )
            ],
            knowledgeFrames: [
                .init(id: 1, name: "Shared frame", body: "Same body", triggers: ["new"]),
                .init(id: 2, name: "Shared frame", body: "Different body"),
                .init(id: 3, name: "Fresh frame", body: "Fresh body", triggers: ["fresh"])
            ]
        )

        let summary = try makeImporter(target).restore(document, mode: .merge)

        XCTAssertEqual(summary.projectsCreated, 0)
        XCTAssertEqual(summary.tasksCreated, 1)
        XCTAssertEqual(summary.framesCreated, 2)
        XCTAssertEqual(summary.framesSkipped, 1)

        let restoredTask = try XCTUnwrap(target.taskStore.listAll().first)
        XCTAssertEqual(restoredTask.status, "completed")
        XCTAssertEqual(restoredTask.completedAt, "2025-12-31T09:30:00Z", "restore must keep the original completion timestamp")

        let frames = try target.knowledgeFrameStore.list()
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.filter { $0.name == "Shared frame" }.count, 2)
        XCTAssertEqual(frames.filter { $0.name == "Fresh frame" }.count, 1)
    }

    func testRestoreIsAdditiveAndRepeatableWithoutTouchingExistingRows() throws {
        let target = try makeStores()
        let existing = try target.projectStore.create(title: "Existing project")
        _ = try target.taskStore.create(title: "Existing task", projectID: existing.id)

        let document = WorkspaceBackupDocument(
            exportedAt: Date(),
            projects: [.init(id: 42, title: "Backup project", status: "active")],
            tasks: [.init(id: 7, projectID: 42, title: "Backup task", status: "open")],
            knowledgeFrames: []
        )

        let importer = makeImporter(target)
        _ = try importer.restore(document, mode: .merge)
        _ = try importer.restore(document, mode: .merge)

        let projects = try target.projectStore.list(includeArchived: true)
        XCTAssertEqual(projects.filter { $0.title == "Backup project" }.count, 2, "merge restore is additive by design")
        XCTAssertEqual(projects.filter { $0.title == "Existing project" }.count, 1)
        XCTAssertEqual(try target.taskStore.listAll().filter { $0.title == "Existing task" }.count, 1)
    }

    func testRestoreRejectsUnsupportedFormatVersion() throws {
        let target = try makeStores()
        let document = WorkspaceBackupDocument(
            formatVersion: 2,
            exportedAt: Date(),
            projects: [],
            tasks: [],
            knowledgeFrames: []
        )

        XCTAssertThrowsError(try makeImporter(target).restore(document, mode: .merge)) { error in
            XCTAssertEqual(error as? WorkspaceBackupError, .unsupportedFormatVersion(2))
        }
    }
}
