import XCTest
@testable import SoloPMCore

final class SystemToolTests: XCTestCase {
    func testNotificationToolSchedulesWithFakeClient() throws {
        let client = InMemoryNotificationClient()
        let tool = NotificationTool(name: .notificationSchedule, client: client)

        let result = try tool.execute(
            arguments: [
                "title": .string("Standup"),
                "body": .string("Share blockers"),
                "scheduledAt": .string("2026-06-18T09:00:00Z")
            ],
            context: approvedContext()
        )

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.output["notificationId"]?.stringValue, "notification-1")
        XCTAssertEqual(try client.listScheduled().map(\.title), ["Standup"])
    }

    func testNotificationToolReportsPermissionDenied() throws {
        let connection = try migratedConnection()
        let requestStore = SQLiteNotificationRequestStore(connection: connection)
        let client = InMemoryNotificationClient(authorizationStatus: .denied)
        let tool = NotificationTool(name: .notificationSchedule, client: client, requestStore: requestStore)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Standup"),
                    "id": .string("standup-reminder"),
                    "scheduledAt": .string("2026-06-18T09:00:00Z")
                ],
                context: approvedContext()
            )
        )

        let request = try XCTUnwrap(requestStore.list().first)
        XCTAssertEqual(request.requestID, "standup-reminder")
        XCTAssertEqual(request.status, "failed")
        XCTAssertEqual(request.failureReason, "Notification permission is denied.")
    }

    func testNotificationToolSurfacesFailedRequestPersistenceError() throws {
        let connection = try migratedConnection()
        let requestStore = SQLiteNotificationRequestStore(connection: connection)
        try connection.execute(
            """
            CREATE TRIGGER block_notification_request_update
            BEFORE UPDATE ON notification_requests
            BEGIN
                SELECT RAISE(FAIL, 'notification update blocked');
            END;
            """
        )
        let client = InMemoryNotificationClient(authorizationStatus: .denied)
        let tool = NotificationTool(name: .notificationSchedule, client: client, requestStore: requestStore)

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Standup"),
                    "id": .string("standup-reminder"),
                    "scheduledAt": .string("2026-06-18T09:00:00Z")
                ],
                context: approvedContext()
            )
        ) { error in
            guard case let ToolExecutionError.executionFailed(tool, message) = error else {
                return XCTFail("Expected executionFailed, got \(error)")
            }
            XCTAssertEqual(tool, .notificationSchedule)
            XCTAssertTrue(message.contains("Notification permission is denied."))
            XCTAssertTrue(message.contains("Failed to persist notification failure state"))
            XCTAssertTrue(message.contains("notification update blocked"))
        }

        let request = try XCTUnwrap(requestStore.list().first)
        XCTAssertEqual(request.status, "pending")
    }

    func testNotificationToolPersistsPendingThenScheduledState() throws {
        let connection = try migratedConnection()
        let requestStore = SQLiteNotificationRequestStore(connection: connection)
        let tool = NotificationTool(name: .notificationSchedule, client: InMemoryNotificationClient(), requestStore: requestStore)

        _ = try tool.execute(
            arguments: [
                "title": .string("Standup"),
                "id": .string("standup-reminder"),
                "scheduledAt": .string("2026-06-18T09:00:00Z")
            ],
            context: approvedContext()
        )

        let request = try XCTUnwrap(requestStore.list().first)
        XCTAssertEqual(request.status, "scheduled")
        XCTAssertEqual(request.externalNotificationID, "standup-reminder")
    }

    func testNotificationRequestStoreRejectsCorruptedTitleInsteadOfReturningEmptyRequest() throws {
        let connection = try migratedConnection()
        let requestStore = SQLiteNotificationRequestStore(connection: connection)
        _ = try requestStore.createPending(requestID: "standup-reminder", title: "Standup", scheduledAt: "2026-06-18T09:00:00Z")

        try connection.execute("UPDATE notification_requests SET title = '' WHERE request_id = 'standup-reminder';")

        XCTAssertThrowsError(try requestStore.list()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .missingRequiredColumn(column: "notification_requests.title"))
        }
    }

    func testNotificationRelativeScheduleRejectsNonPositiveOffset() throws {
        let tool = NotificationTool(name: .notificationScheduleRelative, client: InMemoryNotificationClient())

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Break"),
                    "offsetSeconds": .number(0)
                ],
                context: approvedContext()
            )
        )
    }

    func testCalendarToolRejectsInvalidDateRange() throws {
        let tool = CalendarTool(name: .calendarCreateEvent, client: InMemoryCalendarClient())

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Deep work"),
                    "startAt": .string("2026-06-18T10:00:00Z"),
                    "endAt": .string("2026-06-18T09:00:00Z")
                ],
                context: approvedContext()
            )
        )
    }

    func testCalendarToolPersistsProjectAndTaskLink() throws {
        let connection = try migratedConnection()
        let linkStore = SQLiteCalendarLinkStore(connection: connection)
        let tool = CalendarTool(name: .calendarCreateEvent, client: InMemoryCalendarClient(), linkStore: linkStore)

        _ = try tool.execute(
            arguments: [
                "title": .string("Deep work"),
                "startAt": .string("2026-06-18T09:00:00Z"),
                "endAt": .string("2026-06-18T10:00:00Z"),
                "projectId": .number(10),
                "taskId": .number(20)
            ],
            context: approvedContext()
        )

        let link = try XCTUnwrap(linkStore.list().first)
        XCTAssertEqual(link.eventID, "calendar-event-1")
        XCTAssertEqual(link.projectID, 10)
        XCTAssertEqual(link.taskID, 20)
    }

    func testCalendarLinkStoreRejectsCorruptedTaskIDInsteadOfDroppingLink() throws {
        let connection = try migratedConnection()
        let linkStore = SQLiteCalendarLinkStore(connection: connection)
        _ = try linkStore.link(eventID: "event-1", projectID: 10, taskID: 20, title: "Deep work")

        try connection.execute("UPDATE calendar_links SET task_id = 'not-int' WHERE event_id = 'event-1';")

        XCTAssertThrowsError(try linkStore.list()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidInt64(column: "calendar_links.task_id", value: "not-int"))
        }
    }

    func testCalendarWorkBlockRejectsNonPositiveDuration() throws {
        let tool = CalendarTool(name: .calendarCreateWorkBlock, client: InMemoryCalendarClient())

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Deep work"),
                    "startAt": .string("2026-06-18T10:00:00Z"),
                    "durationMinutes": .number(0)
                ],
                context: approvedContext()
            )
        )
    }

    func testReminderToolBulkCreateAndMarkComplete() throws {
        let client = InMemoryReminderClient()
        let create = ReminderTool(name: .remindersBulkCreate, client: client)
        let complete = ReminderTool(name: .remindersMarkComplete, client: client)

        let result = try create.execute(
            arguments: [
                "reminders": .array([
                    .object(["title": .string("Draft spec")]),
                    .object(["title": .string("Review spec")])
                ])
            ],
            context: approvedContext()
        )
        let firstID = try XCTUnwrap(result.output["reminderIds"]?.stringArrayValue.first)

        _ = try complete.execute(arguments: ["id": .string(firstID)], context: approvedContext())

        XCTAssertEqual(try client.list().first?.isCompleted, true)
    }

    func testReminderBulkCreateRejectsNonObjectItemsWithoutPartialRecords() throws {
        let client = InMemoryReminderClient()
        let create = ReminderTool(name: .remindersBulkCreate, client: client)

        XCTAssertThrowsError(
            try create.execute(
                arguments: [
                    "reminders": .array([
                        .object(["title": .string("Draft spec")]),
                        .string("Review spec")
                    ])
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(error as? ToolExecutionError, .validationFailed(.remindersBulkCreate, "Argument 'reminders[1]' must be object."))
        }

        XCTAssertEqual(try client.list(), [])
    }

    func testReminderToolPersistsLocalTaskLink() throws {
        let connection = try migratedConnection()
        let linkStore = SQLiteReminderLinkStore(connection: connection)
        let tool = ReminderTool(name: .remindersCreate, client: InMemoryReminderClient(), linkStore: linkStore)

        _ = try tool.execute(
            arguments: [
                "title": .string("Draft spec"),
                "taskId": .number(42)
            ],
            context: approvedContext()
        )

        let link = try XCTUnwrap(linkStore.list().first)
        XCTAssertEqual(link.reminderID, "reminder-1")
        XCTAssertEqual(link.taskID, 42)
        XCTAssertEqual(link.title, "Draft spec")
    }

    func testReminderLinkStoreRejectsCorruptedProjectIDInsteadOfDroppingLink() throws {
        let connection = try migratedConnection()
        let linkStore = SQLiteReminderLinkStore(connection: connection)
        _ = try linkStore.link(reminderID: "reminder-1", projectID: 10, taskID: 20, title: "Draft spec")

        try connection.execute("UPDATE reminder_links SET project_id = 'not-int' WHERE reminder_id = 'reminder-1';")

        XCTAssertThrowsError(try linkStore.list()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidInt64(column: "reminder_links.project_id", value: "not-int"))
        }
    }

    func testFileSystemToolRejectsOverwriteAndTraversal() throws {
        let root = temporaryDirectory()
        let client = LocalFileAccessClient(workspaceRoot: root)
        let tool = FileSystemTool(name: .filesystemCreateMarkdownFile, client: client)

        _ = try tool.execute(
            arguments: [
                "relativePath": .string("docs/plan.md"),
                "contents": .string("# Plan")
            ],
            context: approvedContext()
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/plan.md").path))
        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("# Overwrite")
                ],
                context: approvedContext()
            )
        )
        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "relativePath": .string("../escape.md"),
                    "contents": .string("# Escape")
                ],
                context: approvedContext()
            )
        )
    }

    func testFileSystemToolPersistsCreatedArtifactLinkWhenProjectIDIsProvided() throws {
        let root = temporaryDirectory()
        let connection = try currentMigratedConnection()
        let projects = SQLiteProjectStore(connection: connection)
        let artifactStore = SQLiteArtifactStore(connection: connection)
        let project = try projects.create(title: "Launch Readiness")
        let tool = FileSystemTool(
            name: .filesystemCreateArtifactsFromFrame,
            client: LocalFileAccessClient(workspaceRoot: root),
            artifactStore: artifactStore
        )

        let arguments: [String: JSONValue] = [
            "frameName": .string("Release Notes"),
            "body": .string("# Release Notes"),
            "directory": .string("docs/release"),
            "projectId": .number(Double(project.id))
        ]
        let result = try tool.execute(
            arguments: arguments,
            context: approvedContext()
        )

        let artifactURL = root.appendingPathComponent("docs/release/release-notes.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertEqual(result.output["relativePath"], JSONValue.string("docs/release/release-notes.md"))
        XCTAssertEqual(result.output["artifactId"], JSONValue.number(1))
        XCTAssertEqual(result.rollbackMetadata["artifactId"], JSONValue.number(1))

        let artifacts = try artifactStore.list()
        XCTAssertEqual(artifacts.count, 1)
        XCTAssertEqual(artifacts.first?.projectID, project.id)
        XCTAssertNil(artifacts.first?.taskID)
        XCTAssertEqual(artifacts.first?.workspacePath, root.standardizedFileURL.path)
        XCTAssertEqual(artifacts.first?.expectedPath, artifactURL.standardizedFileURL.path)
        XCTAssertEqual(artifacts.first?.createdState, .created)
    }

    func testFileSystemToolRejectsArtifactLinkRequestBeforeWritingWhenStoreIsMissing() throws {
        let root = temporaryDirectory()
        let tool = FileSystemTool(
            name: .filesystemCreateMarkdownFile,
            client: LocalFileAccessClient(workspaceRoot: root)
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "relativePath": .string("docs/plan.md"),
                    "contents": .string("# Plan"),
                    "projectId": .number(1)
                ],
                context: approvedContext()
            )
        ) { error in
            XCTAssertEqual(
                error as? ToolExecutionError,
                .executionFailed(.filesystemCreateMarkdownFile, "Artifact store is required to link created artifacts.")
            )
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("docs/plan.md").path))
    }

    func testFileSystemDirectoryToolDoesNotExposeArtifactLinkFields() throws {
        let tool = FileSystemTool(
            name: .filesystemCreateDirectory,
            client: LocalFileAccessClient(workspaceRoot: temporaryDirectory())
        )

        XCTAssertEqual(tool.inputSchema.properties["relativePath"], "string")
        XCTAssertNil(tool.inputSchema.properties["projectId"])
        XCTAssertNil(tool.inputSchema.properties["taskId"])
    }

    func testMailDraftToolCreatesTextOnlyDraftWithoutSendTool() throws {
        let client = InMemoryMailDraftClient()
        let tool = MailDraftTool(client: client)

        let result = try tool.execute(
            arguments: [
                "to": .string("team@example.com"),
                "subject": .string("Status"),
                "body": .string("Draft only")
            ],
            context: ToolExecutionContext(source: .developerTool)
        )

        XCTAssertEqual(result.output["draftId"]?.stringValue, "mail-draft-1")
        XCTAssertEqual(try client.listDrafts().first?.body, "Draft only")
        XCTAssertFalse(ActionTool.allCases.contains { $0.rawValue == "maildraft.send" })
    }

    func testAuditedToolLogsApprovalMissingAndRedactsArguments() throws {
        let logger = InMemoryAuditLogger()
        let base = StaticTool(
            name: .taskCreate,
            description: "Create task",
            inputSchema: ToolInputSchema(required: ["title"]),
            permissionLevel: .writeWithApproval
        ) { _, _ in
            ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created")
        }
        let audited = AuditedTool(base: base, logger: RedactingAuditLogger(base: logger))

        XCTAssertThrowsError(
            try audited.execute(
                arguments: [
                    "title": .string("Secret task"),
                    "apiKey": .string("redacted-test-key")
                ],
                context: ToolExecutionContext(source: .developerTool)
            )
        )

        let events = logger.recordedEvents
        XCTAssertEqual(events.map(\.status), [.started, .failed])
        XCTAssertEqual(events.last?.metadata["approval_state"], "missing")
        let arguments = try XCTUnwrap(events.last?.metadata["arguments"])
        XCTAssertFalse(arguments.contains("redacted-test-key"))
        XCTAssertEqual(arguments, "[REDACTED]")
    }

    func testAuditedToolRedactsArgumentsWithoutRedactingLogger() throws {
        let logger = InMemoryAuditLogger()
        let base = StaticTool(
            name: .taskCreate,
            description: "Create task",
            inputSchema: ToolInputSchema(required: ["title"]),
            permissionLevel: .writeWithApproval
        ) { _, _ in
            ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created")
        }
        let audited = AuditedTool(base: base, logger: logger)
        let apiKey = "sk-" + "sampleSecret"

        XCTAssertThrowsError(
            try audited.execute(
                arguments: [
                    "title": .string("Secret task"),
                    "apiKey": .string(apiKey)
                ],
                context: ToolExecutionContext(source: .developerTool)
            )
        )

        let arguments = try XCTUnwrap(logger.recordedEvents.last?.metadata["arguments"])
        XCTAssertFalse(arguments.contains(apiKey))
        XCTAssertTrue(arguments.contains("[REDACTED_SECRET]"))
    }

    func testAuditedToolRedactsSensitiveArgumentKeyEvenWhenValueHasSpaces() throws {
        let logger = InMemoryAuditLogger()
        let base = StaticTool(
            name: .taskCreate,
            description: "Create task",
            inputSchema: ToolInputSchema(required: ["title"]),
            permissionLevel: .writeWithApproval
        ) { _, _ in
            ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created")
        }
        let audited = AuditedTool(base: base, logger: logger)
        let malformedSecret = "alpha beta gamma"

        XCTAssertThrowsError(
            try audited.execute(
                arguments: [
                    "title": .string("Secret task"),
                    "apiKey": .string(malformedSecret)
                ],
                context: ToolExecutionContext(source: .developerTool)
            )
        )

        let arguments = try XCTUnwrap(logger.recordedEvents.last?.metadata["arguments"])
        XCTAssertFalse(arguments.contains("alpha"))
        XCTAssertFalse(arguments.contains("beta gamma"))
        XCTAssertTrue(arguments.contains("apiKey=[REDACTED_SECRET]"))
        XCTAssertTrue(arguments.contains("title=string(\"Secret task\")"))
    }

    func testPhase2MVPRegistryContainsSystemTools() throws {
        let stores = try makeStores()
        let registry = try ToolRegistry.phase2MVP(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            knowledgeStore: stores.knowledge,
            notificationClient: InMemoryNotificationClient(),
            calendarClient: InMemoryCalendarClient(),
            reminderClient: InMemoryReminderClient(),
            fileAccessClient: LocalFileAccessClient(workspaceRoot: temporaryDirectory()),
            mailDraftClient: InMemoryMailDraftClient()
        )

        XCTAssertTrue(registry.contains(.notificationSchedule))
        XCTAssertTrue(registry.contains(.calendarCreateEvent))
        XCTAssertTrue(registry.contains(.remindersBulkCreate))
        XCTAssertTrue(registry.contains(.filesystemCreateMarkdownFile))
        XCTAssertTrue(registry.contains(.mailDraftCreateText))
    }

    func testInMemoryPhase2MVPFactoryBuildsExecutableRegistry() throws {
        let registry = try ToolRegistryTestFactory.inMemoryPhase2MVP(
            workspaceRoot: temporaryDirectory(),
            auditLogger: InMemoryAuditLogger()
        )

        XCTAssertTrue(registry.contains(.projectCreate))
        XCTAssertTrue(registry.contains(.taskCreate))
        XCTAssertTrue(registry.contains(.notificationSchedule))
        XCTAssertTrue(registry.contains(.mailDraftCreateText))
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, knowledge: SQLiteKnowledgeFrameStore) {
        let connection = try migratedConnection()
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        return connection
    }

    private func currentMigratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try TestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private func approvedContext() -> ToolExecutionContext {
        ToolExecutionContext(approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"), source: .developerTool)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SoloPMTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
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
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var stringArrayValue: [String] {
        guard case .array(let values) = self else {
            return []
        }
        return values.compactMap { value in
            guard case .string(let string) = value else {
                return nil
            }
            return string
        }
    }
}
