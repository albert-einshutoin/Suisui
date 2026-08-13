import XCTest
@testable import SuisuiCore

final class ArtifactMonitoringTests: XCTestCase {
    func testArtifactStorePersistsExpectedPathCreatedStateAndLastModifiedAt() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let lastModifiedAt = try Date.iso8601("2026-06-10T09:30:00Z")

        let artifact = try store.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md",
            createdState: .created,
            lastModifiedAt: lastModifiedAt
        )

        XCTAssertTrue(try connection.tableExists("artifacts"))
        XCTAssertEqual(artifact.workspacePath, "/tmp/suisui")
        XCTAssertEqual(artifact.expectedPath, "/tmp/suisui/reports/status.md")
        XCTAssertEqual(artifact.createdState, .created)
        XCTAssertEqual(artifact.lastModifiedAt, lastModifiedAt)
    }

    func testArtifactStoreUpdatesOnlyMatchingProjectArtifactFromFileEvent() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let projectArtifact = try store.create(
            projectID: 10,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        let otherProjectArtifact = try store.create(
            projectID: 20,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/other.md"
        )
        let modifiedAt = try Date.iso8601("2026-06-10T10:00:00Z")

        let updated = try store.updateProjectArtifactFromFileEvent(
            projectID: 10,
            workspacePath: "/tmp/suisui",
            path: "/tmp/suisui/reports/status.md",
            modifiedAt: modifiedAt
        )

        XCTAssertEqual(updated.map(\.id), [projectArtifact.id])
        let records = try store.list()
        XCTAssertEqual(records.first { $0.id == projectArtifact.id }?.createdState, .created)
        XCTAssertEqual(records.first { $0.id == projectArtifact.id }?.lastModifiedAt, modifiedAt)
        XCTAssertEqual(records.first { $0.id == otherProjectArtifact.id }?.createdState, .expected)
        XCTAssertNil(records.first { $0.id == otherProjectArtifact.id }?.lastModifiedAt)
    }

    func testArtifactStoreProjectFileEventDoesNotUpdateTaskArtifactWithSameExpectedPath() throws {
        let connection = try makeCurrentConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let projectArtifact = try store.create(
            projectID: 10,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        let taskArtifact = try store.create(
            projectID: 10,
            taskID: 99,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        let modifiedAt = try Date.iso8601("2026-06-10T10:00:00Z")

        let updated = try store.updateProjectArtifactFromFileEvent(
            projectID: 10,
            workspacePath: "/tmp/suisui",
            path: "/tmp/suisui/reports/status.md",
            modifiedAt: modifiedAt
        )

        XCTAssertEqual(updated.map(\.id), [projectArtifact.id])
        let records = try store.list()
        XCTAssertEqual(records.first { $0.id == projectArtifact.id }?.createdState, .created)
        XCTAssertEqual(records.first { $0.id == taskArtifact.id }?.createdState, .expected)
        XCTAssertNil(records.first { $0.id == taskArtifact.id }?.lastModifiedAt)
    }

    func testArtifactStoreAllowsSameExpectedPathForDifferentProjects() throws {
        let connection = try makeCurrentConnection()
        let store = SQLiteArtifactStore(connection: connection)

        let first = try store.create(
            projectID: 10,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        let second = try store.create(
            projectID: 20,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(try store.list().map(\.projectID), [10, 20])
    }

    func testCurrentMigrationScopesArtifactUniquenessAndKeepsCreatedDuplicate() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        try connection.execute(
            """
            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state, last_modified_at)
            VALUES (
                10,
                NULL,
                '/tmp/suisui/reports',
                '/tmp/suisui/reports/status.md',
                'expected',
                NULL
            );

            INSERT INTO artifacts (project_id, task_id, workspace_path, expected_path, created_state, last_modified_at)
            VALUES (
                10,
                NULL,
                '/tmp/suisui',
                '/tmp/suisui/reports/status.md',
                'created',
                '2026-06-10T10:00:00Z'
            );
            """
        )

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let store = SQLiteArtifactStore(connection: connection)
        let artifacts = try store.list()
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.workspacePath, "/tmp/suisui")
        XCTAssertEqual(artifacts.first?.createdState, .created)
        XCTAssertEqual(artifacts.first?.lastModifiedAt, try Date.iso8601("2026-06-10T10:00:00Z"))
    }

    func testArtifactStoreDeletesArtifactAndReportsMissingOnSecondDelete() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let artifact = try store.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )

        try store.delete(id: artifact.id)

        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertThrowsError(try store.delete(id: artifact.id)) { error in
            XCTAssertEqual(error as? ArtifactStoreError, .notFound(artifact.id))
        }
    }

    func testArtifactStoreRejectsCorruptedTaskIDInsteadOfDroppingLink() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let artifact = try store.create(taskID: 42, workspacePath: "/tmp/suisui", expectedPath: "/tmp/suisui/reports/status.md")

        try connection.execute("UPDATE artifacts SET task_id = 'not-int' WHERE id = \(artifact.id);")

        XCTAssertThrowsError(try store.get(id: artifact.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidInt64(column: "artifacts.task_id", value: "not-int"))
        }
    }

    func testArtifactStoreRejectsCorruptedExpectedPathInsteadOfReturningEmptyPath() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let artifact = try store.create(workspacePath: "/tmp/suisui", expectedPath: "/tmp/suisui/reports/status.md")

        try connection.execute("UPDATE artifacts SET expected_path = '' WHERE id = \(artifact.id);")

        XCTAssertThrowsError(try store.get(id: artifact.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .missingRequiredColumn(column: "artifacts.expected_path"))
        }
    }

    func testArtifactStoreRejectsCorruptedLastModifiedAtInsteadOfDroppingTimestamp() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let artifact = try store.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-10T09:30:00Z")
        )

        try connection.execute("UPDATE artifacts SET last_modified_at = 'not-a-date' WHERE id = \(artifact.id);")

        XCTAssertThrowsError(try store.get(id: artifact.id)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidDate(column: "artifacts.last_modified_at", value: "not-a-date"))
        }
    }

    func testFakeFileMonitorUpdatesArtifactInsideWorkspace() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        _ = try store.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        let modifiedAt = try Date.iso8601("2026-06-17T12:00:00Z")
        let monitor = FakeFileMonitorClient(
            events: [
                FileMonitorEvent(
                    path: "/tmp/suisui/reports/status.md",
                    kind: .modified,
                    modifiedAt: modifiedAt
                )
            ]
        )
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: monitor,
            workspacePath: "/tmp/suisui",
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
            workspacePath: "/tmp/suisui",
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
            workspacePath: "/tmp/suisui",
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
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        _ = try store.create(
            workspacePath: "/tmp/other",
            expectedPath: "/tmp/suisui/reports/status.md"
        )
        let now = try Date.iso8601("2026-06-17T12:00:00Z")
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: FakeFileMonitorClient(
                events: [
                    FileMonitorEvent(
                        path: "/tmp/suisui/reports/status.md",
                        kind: .modified,
                        modifiedAt: now
                    )
                ]
            ),
            workspacePath: "/tmp/suisui",
            dateProvider: FixedDateProvider(now: now)
        )

        let result = try service.applyNextEvent()
        let records = try store.list()

        XCTAssertEqual(result.updatedArtifacts.map(\.workspacePath), ["/tmp/suisui"])
        XCTAssertEqual(records[0].createdState, .created)
        XCTAssertEqual(records[1].createdState, .expected)
    }

    func testArtifactMonitorDetectsStaleArtifacts() throws {
        let connection = try makeConnection()
        let store = SQLiteArtifactStore(connection: connection)
        let now = try Date.iso8601("2026-06-17T12:00:00Z")
        _ = try store.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/old.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-01T12:00:00Z")
        )
        _ = try store.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/recent.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-16T12:00:00Z")
        )
        let service = ArtifactMonitoringService(
            artifactStore: store,
            fileMonitorClient: FakeFileMonitorClient(),
            workspacePath: "/tmp/suisui",
            dateProvider: FixedDateProvider(now: now)
        )

        let stale = try service.staleArtifacts(olderThan: 7 * 24 * 60 * 60)

        XCTAssertEqual(stale.map(\.expectedPath), ["/tmp/suisui/reports/old.md"])
    }

    func testWorkspacePathPolicyHandlesTrailingSlashAndSiblingPrefix() {
        XCTAssertTrue(WorkspacePathPolicy.isPath("/tmp/suisui/reports/status.md", inside: "/tmp/suisui/"))
        XCTAssertFalse(WorkspacePathPolicy.isPath("/tmp/suisui-other/status.md", inside: "/tmp/suisui"))
    }

    func testArtifactProgressDetectorReportsMissingFileWithDeadlineRuleTarget() throws {
        let connection = try makeConnection()
        let stores = makeStores(connection: connection)
        let task = try stores.tasks.create(title: "Draft status", dueAt: "2026-06-30T12:00:00Z")
        _ = try stores.artifacts.create(
            taskID: task.id,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/status.md",
            createdState: .missing
        )
        let detector = ArtifactProgressDetector(
            artifactStore: stores.artifacts,
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z"))
        )

        let issues = try detector.detectIssues(staleAfter: 7 * 24 * 60 * 60, deadlineLeadTime: 24 * 60 * 60)

        XCTAssertEqual(issues.map(\.kind), [.missingFile])
        XCTAssertEqual(issues.first?.deadlineRuleTarget, .task(task.id))
    }

    func testArtifactProgressDetectorReportsStaleFile() throws {
        let connection = try makeConnection()
        let stores = makeStores(connection: connection)
        _ = try stores.artifacts.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/old.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-01T12:00:00Z")
        )
        let detector = ArtifactProgressDetector(
            artifactStore: stores.artifacts,
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z"))
        )

        let issues = try detector.detectIssues(staleAfter: 7 * 24 * 60 * 60, deadlineLeadTime: 24 * 60 * 60)

        XCTAssertEqual(issues.map(\.kind), [.staleFile])
        XCTAssertEqual(issues.first?.artifact.expectedPath, "/tmp/suisui/reports/old.md")
    }

    func testArtifactProgressDetectorIgnoresRecentlyUpdatedFile() throws {
        let connection = try makeConnection()
        let stores = makeStores(connection: connection)
        _ = try stores.artifacts.create(
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/recent.md",
            createdState: .created,
            lastModifiedAt: try Date.iso8601("2026-06-16T12:00:00Z")
        )
        let detector = ArtifactProgressDetector(
            artifactStore: stores.artifacts,
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z"))
        )

        let issues = try detector.detectIssues(staleAfter: 7 * 24 * 60 * 60, deadlineLeadTime: 24 * 60 * 60)

        XCTAssertEqual(issues, [])
    }

    func testArtifactProgressDetectorReportsIncompleteArtifactBeforeDeadline() throws {
        let connection = try makeConnection()
        let stores = makeStores(connection: connection)
        let project = try stores.projects.create(title: "Launch", deadline: "2026-06-18T12:00:00Z")
        _ = try stores.artifacts.create(
            projectID: project.id,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/launch.md"
        )
        let detector = ArtifactProgressDetector(
            artifactStore: stores.artifacts,
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z"))
        )

        let issues = try detector.detectIssues(staleAfter: 7 * 24 * 60 * 60, deadlineLeadTime: 2 * 24 * 60 * 60)

        XCTAssertEqual(issues.map(\.kind), [.missingFile, .incompleteBeforeDeadline])
        XCTAssertEqual(issues.last?.deadlineRuleTarget, .project(project.id))
    }

    func testArtifactProgressDetectorUsesDateOnlyTaskDueDateForIncompleteDeadline() throws {
        let connection = try makeConnection()
        let stores = makeStores(connection: connection)
        let task = try stores.tasks.create(title: "Write launch memo", dueAt: "2026-06-18")
        _ = try stores.artifacts.create(
            taskID: task.id,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/launch-memo.md"
        )
        let detector = ArtifactProgressDetector(
            artifactStore: stores.artifacts,
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            timeZoneIdentifier: "UTC"
        )

        let issues = try detector.detectIssues(staleAfter: 7 * 24 * 60 * 60, deadlineLeadTime: 2 * 24 * 60 * 60)

        XCTAssertEqual(issues.map(\.kind), [.missingFile, .incompleteBeforeDeadline])
        XCTAssertEqual(issues.last?.deadlineRuleTarget, .task(task.id))
    }

    func testArtifactProgressDetectorThrowsOnInvalidTaskDueDate() throws {
        let connection = try makeConnection()
        let stores = makeStores(connection: connection)
        let task = try stores.tasks.create(title: "Write launch memo", dueAt: "not-a-date")
        _ = try stores.artifacts.create(
            taskID: task.id,
            workspacePath: "/tmp/suisui",
            expectedPath: "/tmp/suisui/reports/launch-memo.md"
        )
        let detector = ArtifactProgressDetector(
            artifactStore: stores.artifacts,
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T00:00:00Z")),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertThrowsError(try detector.detectIssues(staleAfter: 7 * 24 * 60 * 60, deadlineLeadTime: 2 * 24 * 60 * 60)) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidDate(column: "tasks.due_at", value: "not-a-date"))
        }
    }

    private func makeConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        return connection
    }

    private func makeCurrentConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private func makeStores(
        connection: SQLiteConnection
    ) -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, artifacts: SQLiteArtifactStore) {
        (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteArtifactStore(connection: connection)
        )
    }
}

private struct FixedDateProvider: DateProvider {
    let now: Date
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
