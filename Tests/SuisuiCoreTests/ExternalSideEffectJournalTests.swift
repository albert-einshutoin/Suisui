import Foundation
import XCTest
@testable import SuisuiCore

final class ExternalSideEffectJournalTests: XCTestCase {
    func testDerivedIdempotencyKeyIsStableAndGoogleCalendarCompatible() throws {
        let arguments: [String: JSONValue] = ["title": .string("Deep work")]
        let first = try ToolExecutionContext.externalSideEffectIdempotencyKey(
            reviewSessionID: "session-1",
            actionID: "action-1",
            tool: .calendarCreateEvent,
            arguments: arguments
        )
        let second = try ToolExecutionContext.externalSideEffectIdempotencyKey(
            reviewSessionID: "session-1",
            actionID: "action-1",
            tool: .calendarCreateEvent,
            arguments: arguments
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 70)
        XCTAssertTrue(first.hasPrefix("suisui"))
        XCTAssertTrue(first.allSatisfy { "0123456789abcdefghijklmnopqrstuv".contains($0) })
    }

    func testSucceededClaimReturnsPersistedResultWithoutReexecution() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let expected = ToolResult(
            tool: .calendarCreateEvent,
            status: .succeeded,
            summary: "Created calendar event",
            output: ["eventId": .string("event-1")]
        )

        guard case .execute(let prepared) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: prepared.id, at: now)
        try store.markSucceeded(
            id: prepared.id,
            externalResourceID: "event-1",
            result: expected,
            at: now
        )

        XCTAssertEqual(try store.claim(request, at: now), .returnSucceeded(expected))
    }

    func testUnknownClaimBlocksBlindRetry() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .execute(let prepared) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: prepared.id, at: now)
        try store.markUnknown(
            id: prepared.id,
            externalResourceID: nil,
            failureCategory: "external_result_uncertain",
            at: now
        )

        XCTAssertEqual(
            try store.claim(request, at: now),
            .requiresReconciliation(try XCTUnwrap(store.record(id: prepared.id)))
        )
    }

    func testUnknownRecordIsExposedByReadModelAndCompensationIsAuditable() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        guard case .execute(let prepared) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: prepared.id, at: now)
        try store.markUnknown(
            id: prepared.id,
            externalResourceID: "event-1",
            failureCategory: "local_persistence_failed_after_external_success",
            at: now
        )

        let row = try XCTUnwrap(
            ExternalSideEffectReconciliationReadModel(journal: store).load().first
        )
        XCTAssertEqual(row.tool, .calendarCreateEvent)
        XCTAssertEqual(row.externalResourceID, "event-1")
        XCTAssertTrue(row.guidance.contains("Verify external resource"))

        try store.markCompensated(
            id: prepared.id,
            reconciliationResult: "Deleted event after user confirmation.",
            at: now
        )
        let compensated = try XCTUnwrap(store.record(id: prepared.id))
        XCTAssertEqual(compensated.state, .compensated)
        XCTAssertEqual(
            compensated.reconciliationResult,
            "Deleted event after user confirmation."
        )
        XCTAssertTrue(try ExternalSideEffectReconciliationReadModel(journal: store).load().isEmpty)
    }

    func testReviewReceiptCarriesJournalAndExternalResourceEvidence() throws {
        var session = ReviewSession(
            id: "session-1",
            plan: ActionPlan(
                id: "plan-1",
                userInput: "Create event",
                summary: "Create event",
                actions: [
                    PlanAction(
                        id: "action-1",
                        tool: .calendarCreateEvent,
                        arguments: ["title": .string("Deep work")]
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        session.executionStatus = .completed
        session.markAction(
            id: "action-1",
            status: .succeeded,
            result: ToolResult(
                tool: .calendarCreateEvent,
                status: .succeeded,
                summary: "Created calendar event",
                output: [
                    "idempotencyKey": .string("calendar-key"),
                    "externalResourceId": .string("event-1"),
                    "journalRecordId": .string("journal-1"),
                    "journalState": .string("succeeded")
                ]
            )
        )

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "run-1",
            model: nil,
            usage: .unavailable,
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )

        let evidence = try XCTUnwrap(receipt.actions.first?.externalSideEffectEvidence)
        XCTAssertEqual(evidence.idempotencyKeys, ["calendar-key"])
        XCTAssertEqual(evidence.externalResourceIDs, ["event-1"])
        XCTAssertEqual(evidence.journalRecordIDs, ["journal-1"])
        XCTAssertEqual(evidence.journalState, .succeeded)
    }

    func testFailedBeforeSideEffectCanRetryWithIncrementedAttempt() throws {
        let store = try makeStore()
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .execute(let first) = try store.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try store.markStarted(id: first.id, at: now)
        try store.markFailedBeforeSideEffect(
            id: first.id,
            failureCategory: "permission_denied",
            at: now
        )

        guard case .execute(let retry) = try store.claim(request, at: now) else {
            return XCTFail("A known-safe failure must be retryable.")
        }
        XCTAssertEqual(retry.id, first.id)
        XCTAssertEqual(retry.attempt, 2)
        XCTAssertEqual(retry.state, .prepared)
    }

    func testRecoveryMovesStartedRecordsToUnknownAcrossRestart() throws {
        let root = temporaryDirectory()
        let databaseURL = root.appendingPathComponent("journal.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        let request = makeRequest()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recordID: String

        do {
            let store = try makeStore(path: databaseURL.path)
            guard case .execute(let prepared) = try store.claim(request, at: now) else {
                return XCTFail("First claim must be executable.")
            }
            recordID = prepared.id
            try store.markStarted(id: prepared.id, at: now)
        }

        let reopened = try makeStore(path: databaseURL.path)
        XCTAssertEqual(try reopened.recoverStartedAsUnknown(at: now), 1)
        XCTAssertEqual(try reopened.record(id: recordID)?.state, .unknown)
        guard case .requiresReconciliation = try reopened.claim(request, at: now) else {
            return XCTFail("Recovered uncertain work must not be retried.")
        }
    }

    func testConcurrentClaimsAllowOneExternalExecution() throws {
        let store = try makeStore()
        let request = makeRequest()
        let queue = DispatchQueue(label: "journal-claim", attributes: .concurrent)
        let group = DispatchGroup()
        let executableCount = LockedCounter()

        for _ in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                if case .execute = try? store.claim(request, at: Date()) {
                    executableCount.increment()
                }
            }
        }
        group.wait()

        XCTAssertEqual(executableCount.value, 1)
    }

    func testBulkItemsRoundTripIndependently() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstRequest = makeRequest(itemIndex: 0, idempotencyKey: "bulk-key:0")
        let secondRequest = makeRequest(itemIndex: 1, idempotencyKey: "bulk-key:1")

        guard case .execute(let first) = try store.claim(firstRequest, at: now),
              case .execute(let second) = try store.claim(secondRequest, at: now) else {
            return XCTFail("Each bulk item must have an independent claim.")
        }
        try store.markStarted(id: first.id, at: now)
        try store.markSucceeded(
            id: first.id,
            externalResourceID: "reminder-1",
            result: ToolResult(tool: .remindersBulkCreate, status: .succeeded, summary: "Created reminder"),
            at: now
        )
        try store.markStarted(id: second.id, at: now)
        try store.markUnknown(
            id: second.id,
            externalResourceID: nil,
            failureCategory: "external_result_uncertain",
            at: now
        )

        let records = try store.records(executionID: "execution-1")
        XCTAssertEqual(records.map(\.itemIndex), [0, 1])
        XCTAssertEqual(records.map(\.state), [.succeeded, .unknown])
    }

    func testCalendarLocalPersistenceFailureBecomesUnknownAndRetryDoesNotDuplicate() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let client = InMemoryCalendarClient()
        let tool = CalendarTool(
            name: .calendarCreateEvent,
            client: client,
            linkStore: SQLiteCalendarLinkStore(connection: connection),
            sideEffectJournal: journal
        )
        try connection.execute(
            """
            CREATE TRIGGER block_calendar_link
            BEFORE INSERT ON calendar_links
            BEGIN
                SELECT RAISE(FAIL, 'calendar link blocked');
            END;
            """
        )
        let arguments: [String: JSONValue] = [
            "title": .string("Deep work"),
            "startAt": .string("2026-06-18T09:00:00Z"),
            "endAt": .string("2026-06-18T10:00:00Z"),
            "taskId": .number(20)
        ]
        let context = approvedSideEffectContext(idempotencyKey: "calendar-key")

        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context))
        XCTAssertEqual(try client.listEvents().count, 1)
        XCTAssertEqual(try journal.records(executionID: "execution-1").first?.state, .unknown)

        try connection.execute("DROP TRIGGER block_calendar_link;")
        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context)) { error in
            guard case ToolExecutionError.externalSideEffectRequiresReconciliation = error else {
                return XCTFail("Expected reconciliation-required error, got \(error).")
            }
        }
        XCTAssertEqual(try client.listEvents().count, 1)
    }

    func testActionExecutorSuppliesStableIdentityToProductionJournalPath() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let client = InMemoryCalendarClient()
        let registry = try ToolRegistry(tools: [
            CalendarTool(
                name: .calendarCreateEvent,
                client: client,
                sideEffectJournal: journal
            )
        ])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(
            id: "review-calendar",
            plan: ActionPlan(
                id: "plan-calendar",
                userInput: "Create deep work event",
                summary: "Create event",
                actions: [
                    PlanAction(
                        id: "calendar-action",
                        tool: .calendarCreateEvent,
                        arguments: [
                            "title": .string("Deep work"),
                            "startAt": .string("2026-06-18T09:00:00Z"),
                            "endAt": .string("2026-06-18T10:00:00Z")
                        ]
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        let approval = try session.approve(issuedAt: now)

        let executed = try ActionExecutor(registry: registry).execute(session, now: now)

        XCTAssertEqual(executed.executionStatus, .completed)
        let record = try XCTUnwrap(
            journal.records(executionID: approval.nonce.uuidString).first
        )
        XCTAssertEqual(record.state, .succeeded)
        XCTAssertEqual(record.actionID, "calendar-action")
        XCTAssertEqual(try client.listEvents().first?.draft.idempotencyKey, record.idempotencyKey)
    }

    func testNotificationLocalPersistenceFailureBecomesUnknown() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let client = InMemoryNotificationClient()
        let tool = NotificationTool(
            name: .notificationSchedule,
            client: client,
            requestStore: SQLiteNotificationRequestStore(connection: connection),
            sideEffectJournal: journal
        )
        try connection.execute(
            """
            CREATE TRIGGER block_notification_scheduled
            BEFORE UPDATE ON notification_requests
            WHEN NEW.status = 'scheduled'
            BEGIN
                SELECT RAISE(FAIL, 'notification scheduled state blocked');
            END;
            """
        )

        XCTAssertThrowsError(
            try tool.execute(
                arguments: [
                    "title": .string("Standup"),
                    "scheduledAt": .string("2026-06-18T09:00:00Z")
                ],
                context: approvedSideEffectContext(idempotencyKey: "notification-key")
            )
        )

        XCTAssertEqual(try client.listScheduled().count, 1)
        let record = try XCTUnwrap(journal.records(executionID: "execution-1").first)
        XCTAssertEqual(record.state, .unknown)
        XCTAssertEqual(record.externalResourceID, "notification-key")
    }

    func testReminderBulkPartialFailureDoesNotRecreateSucceededItems() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let client = InMemoryReminderClient()
        let tool = ReminderTool(
            name: .remindersBulkCreate,
            client: client,
            linkStore: SQLiteReminderLinkStore(connection: connection),
            sideEffectJournal: journal
        )
        try connection.execute(
            """
            CREATE TRIGGER block_second_reminder_link
            BEFORE INSERT ON reminder_links
            WHEN NEW.task_id = 2
            BEGIN
                SELECT RAISE(FAIL, 'second reminder link blocked');
            END;
            """
        )
        let arguments: [String: JSONValue] = [
            "reminders": .array([
                .object(["title": .string("Draft"), "taskId": .number(1)]),
                .object(["title": .string("Review"), "taskId": .number(2)])
            ])
        ]
        let context = approvedSideEffectContext(idempotencyKey: "reminder-bulk")

        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context))
        XCTAssertEqual(try client.list().count, 2)
        XCTAssertEqual(
            try journal.records(executionID: "execution-1").map(\.state),
            [.succeeded, .unknown]
        )

        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context))
        XCTAssertEqual(try client.list().count, 2)
    }

    func testFileArtifactPersistenceFailureDoesNotOverwriteCreatedFile() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = FileSystemTool(
            name: .filesystemCreateMarkdownFile,
            client: LocalFileAccessClient(workspaceRoot: root),
            artifactStore: SQLiteArtifactStore(connection: connection),
            sideEffectJournal: journal
        )
        try connection.execute(
            """
            CREATE TRIGGER block_artifact
            BEFORE INSERT ON artifacts
            BEGIN
                SELECT RAISE(FAIL, 'artifact insert blocked');
            END;
            """
        )
        let arguments: [String: JSONValue] = [
            "relativePath": .string("docs/plan.md"),
            "contents": .string("# Original"),
            "taskId": .number(1)
        ]
        let context = approvedSideEffectContext(idempotencyKey: "file-key")

        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context))
        let fileURL = root.appendingPathComponent("docs/plan.md")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Original")
        XCTAssertEqual(try journal.records(executionID: "execution-1").first?.state, .unknown)

        try connection.execute("DROP TRIGGER block_artifact;")
        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Original")
    }

    func testLocalFileCreationIsExclusiveUnderConcurrency() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let client = LocalFileAccessClient(workspaceRoot: root)
        let queue = DispatchQueue(label: "exclusive-file-create", attributes: .concurrent)
        let group = DispatchGroup()
        let successCount = LockedCounter()

        for index in 0..<20 {
            group.enter()
            queue.async {
                defer { group.leave() }
                if (try? client.createMarkdownFile(
                    relativePath: "docs/plan.md",
                    contents: "# Candidate \(index)"
                )) != nil {
                    successCount.increment()
                }
            }
        }
        group.wait()

        XCTAssertEqual(successCount.value, 1)
        let contents = try String(
            contentsOf: root.appendingPathComponent("docs/plan.md"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.hasPrefix("# Candidate "))
    }

    private func makeStore(path: String = ":memory:") throws -> SQLiteExternalSideEffectJournal {
        let connection = try migratedConnection(path: path)
        return SQLiteExternalSideEffectJournal(connection: connection)
    }

    private func migratedConnection(path: String = ":memory:") throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private func makeRequest(
        itemIndex: Int? = nil,
        idempotencyKey: String = "calendar-key"
    ) -> ExternalSideEffectRequest {
        ExternalSideEffectRequest(
            executionID: "execution-1",
            reviewSessionID: "session-1",
            actionID: "action-1",
            itemIndex: itemIndex,
            tool: .calendarCreateEvent,
            canonicalArgumentsDigest: Data(repeating: 7, count: 32),
            idempotencyKey: idempotencyKey
        )
    }

    private func approvedSideEffectContext(idempotencyKey: String) -> ToolExecutionContext {
        ToolExecutionContext(
            approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"),
            source: .reviewUI,
            executionID: "execution-1",
            reviewSessionID: "session-1",
            actionID: "action-1",
            idempotencyKey: idempotencyKey
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SuisuiJournalTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}
