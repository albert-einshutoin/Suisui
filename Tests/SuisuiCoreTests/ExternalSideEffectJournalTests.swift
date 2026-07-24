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

    func testRecoveryMakesPreparedRecordRetryableAcrossRestart() throws {
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
        }

        let reopened = try makeStore(path: databaseURL.path)
        XCTAssertEqual(try reopened.recoverStartedAsUnknown(at: now), 1)
        let recovered = try XCTUnwrap(reopened.record(id: recordID))
        XCTAssertEqual(recovered.state, .failedBeforeSideEffect)
        XCTAssertEqual(recovered.failureCategory, "process_interrupted_before_start")

        guard case .execute(let retry) = try reopened.claim(request, at: now) else {
            return XCTFail("A prepared claim interrupted before start must be retryable.")
        }
        XCTAssertEqual(retry.id, recordID)
        XCTAssertEqual(retry.attempt, 2)
    }

    func testStartupRecoveryRunsOnceAndDoesNotRewriteLaterLiveRecords() throws {
        let store = try makeStore()
        let recovery = ExternalSideEffectStartupRecovery()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let interruptedRequest = makeRequest(idempotencyKey: "interrupted-key")

        guard case .execute(let interrupted) = try store.claim(interruptedRequest, at: now) else {
            return XCTFail("Interrupted request must be executable.")
        }
        try store.markStarted(id: interrupted.id, at: now)

        XCTAssertEqual(try recovery.recoverOnce(journal: store, at: now), 1)
        XCTAssertEqual(try store.record(id: interrupted.id)?.state, .unknown)

        let liveRequest = makeRequest(idempotencyKey: "live-key")
        guard case .execute(let live) = try store.claim(liveRequest, at: now) else {
            return XCTFail("Live request must be executable.")
        }
        try store.markStarted(id: live.id, at: now)

        XCTAssertEqual(try recovery.recoverOnce(journal: store, at: now), 0)
        XCTAssertEqual(try store.record(id: live.id)?.state, .started)
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

    func testConcurrentClaimsAcrossJournalInstancesAreIdempotent() throws {
        let root = temporaryDirectory()
        let databaseURL = root.appendingPathComponent("journal.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = try makeStore(path: databaseURL.path)
        let secondStore = try makeStore(path: databaseURL.path)
        let queue = DispatchQueue(label: "cross-instance-journal-claim", attributes: .concurrent)

        for index in 0..<50 {
            let request = makeRequest(idempotencyKey: "cross-instance-key-\(index)")
            let group = DispatchGroup()
            let outcomes = LockedClaimOutcomes()

            for store in [firstStore, secondStore] {
                group.enter()
                queue.async {
                    defer { group.leave() }
                    do {
                        outcomes.append(try store.claim(request, at: Date()))
                    } catch {
                        outcomes.append(error)
                    }
                }
            }
            group.wait()

            XCTAssertTrue(outcomes.errors.isEmpty, "Unexpected claim errors: \(outcomes.errors)")
            XCTAssertEqual(
                outcomes.claims.filter {
                    if case .execute = $0 { return true }
                    return false
                }.count,
                1
            )
            XCTAssertEqual(
                outcomes.claims.filter {
                    if case .inProgress = $0 { return true }
                    return false
                }.count,
                1
            )
        }
    }

    func testConcurrentSafeRetriesAcrossJournalInstancesHaveOneWinner() throws {
        let root = temporaryDirectory()
        let databaseURL = root.appendingPathComponent("journal.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        let firstStore = try makeStore(path: databaseURL.path)
        let secondStore = try makeStore(path: databaseURL.path)
        let request = makeRequest(idempotencyKey: "safe-retry-key")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .execute(let firstAttempt) = try firstStore.claim(request, at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try firstStore.markStarted(id: firstAttempt.id, at: now)
        try firstStore.markFailedBeforeSideEffect(
            id: firstAttempt.id,
            failureCategory: "permission_denied",
            at: now
        )

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "cross-instance-safe-retry", attributes: .concurrent)
        let outcomes = LockedClaimOutcomes()
        for store in [firstStore, secondStore] {
            group.enter()
            queue.async {
                defer { group.leave() }
                do {
                    outcomes.append(try store.claim(request, at: now))
                } catch {
                    outcomes.append(error)
                }
            }
        }
        group.wait()

        XCTAssertTrue(outcomes.errors.isEmpty, "Unexpected claim errors: \(outcomes.errors)")
        XCTAssertEqual(
            outcomes.claims.filter {
                if case .execute = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(
            outcomes.claims.filter {
                if case .inProgress = $0 { return true }
                return false
            }.count,
            1
        )
        XCTAssertEqual(try firstStore.record(id: firstAttempt.id)?.attempt, 2)
    }

    func testJournalTransitionRetriesBriefSQLiteWriterContention() throws {
        let root = temporaryDirectory()
        let databaseURL = root.appendingPathComponent("journal.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        let journalConnection = try migratedConnection(path: databaseURL.path)
        let lockingConnection = try SQLiteConnection(path: databaseURL.path)
        let store = SQLiteExternalSideEffectJournal(connection: journalConnection)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        guard case .execute(let prepared) = try store.claim(makeRequest(), at: now) else {
            return XCTFail("First claim must be executable.")
        }
        try lockingConnection.execute("BEGIN IMMEDIATE;")

        let transitionStarted = DispatchSemaphore(value: 0)
        let transitionFinished = expectation(description: "journal transition finished")
        let errors = LockedErrors()
        DispatchQueue.global().async {
            transitionStarted.signal()
            do {
                try store.markStarted(id: prepared.id, at: now)
            } catch {
                errors.append(error)
            }
            transitionFinished.fulfill()
        }

        transitionStarted.wait()
        Thread.sleep(forTimeInterval: 0.01)
        try lockingConnection.execute("COMMIT;")
        wait(for: [transitionFinished], timeout: 1)

        XCTAssertTrue(errors.values.isEmpty, "Unexpected transition errors: \(errors.values)")
        XCTAssertEqual(try store.record(id: prepared.id)?.state, .started)
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

    func testActionExecutorReceiptPreservesUnknownSideEffectEvidence() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let client = InMemoryCalendarClient()
        let registry = try ToolRegistry(tools: [
            CalendarTool(
                name: .calendarCreateEvent,
                client: client,
                linkStore: SQLiteCalendarLinkStore(connection: connection),
                sideEffectJournal: journal
            )
        ])
        try connection.execute(
            """
            CREATE TRIGGER block_calendar_link_for_receipt
            BEFORE INSERT ON calendar_links
            BEGIN
                SELECT RAISE(FAIL, 'calendar link blocked');
            END;
            """
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var session = ReviewSession(
            id: "review-calendar-unknown",
            plan: ActionPlan(
                id: "plan-calendar-unknown",
                userInput: "Create deep work event",
                summary: "Create event",
                actions: [
                    PlanAction(
                        id: "calendar-action-unknown",
                        tool: .calendarCreateEvent,
                        arguments: [
                            "title": .string("Deep work"),
                            "startAt": .string("2026-06-18T09:00:00Z"),
                            "endAt": .string("2026-06-18T10:00:00Z"),
                            "taskId": .number(20)
                        ]
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        )
        let approval = try session.approve(issuedAt: now)

        let executed = try ActionExecutor(registry: registry).execute(session, now: now)
        XCTAssertEqual(executed.executionStatus, .failed)
        let record = try XCTUnwrap(
            journal.records(executionID: approval.nonce.uuidString).first
        )
        XCTAssertEqual(record.state, .unknown)

        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: executed,
            runID: "run-calendar-unknown",
            model: nil,
            usage: .unavailable,
            startedAt: now,
            finishedAt: now
        )
        let evidence = try XCTUnwrap(receipt.actions.first?.externalSideEffectEvidence)
        XCTAssertEqual(evidence.idempotencyKeys, [record.idempotencyKey])
        XCTAssertEqual(evidence.externalResourceIDs, [try XCTUnwrap(record.externalResourceID)])
        XCTAssertEqual(evidence.journalRecordIDs, [record.id])
        XCTAssertEqual(evidence.journalState, .unknown)
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

    func testNotificationJournalPreservesExplicitCallerIdentifier() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let requestStore = SQLiteNotificationRequestStore(connection: connection)
        let tool = NotificationTool(
            name: .notificationSchedule,
            client: InMemoryNotificationClient(),
            requestStore: requestStore,
            sideEffectJournal: journal
        )

        let result = try tool.execute(
            arguments: [
                "title": .string("Standup"),
                "id": .string("standup-reminder"),
                "scheduledAt": .string("2026-06-18T09:00:00Z")
            ],
            context: approvedSideEffectContext(idempotencyKey: "notification-journal-key")
        )

        XCTAssertEqual(result.output["notificationId"], .string("standup-reminder"))
        XCTAssertEqual(try requestStore.list().first?.requestID, "standup-reminder")
        XCTAssertEqual(
            try journal.records(executionID: "execution-1").first?.idempotencyKey,
            "notification-journal-key"
        )
    }

    func testNotificationJournalRetriesKnownPreWriteClientFailure() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let requestStore = SQLiteNotificationRequestStore(connection: connection)
        let client = FailOnceNotificationClient()
        let tool = NotificationTool(
            name: .notificationSchedule,
            client: client,
            requestStore: requestStore,
            sideEffectJournal: journal
        )
        let arguments: [String: JSONValue] = [
            "title": .string("Standup"),
            "id": .string("standup-reminder"),
            "scheduledAt": .string("2026-06-18T09:00:00Z")
        ]
        let context = approvedSideEffectContext(idempotencyKey: "notification-retry-key")

        XCTAssertThrowsError(try tool.execute(arguments: arguments, context: context))
        XCTAssertEqual(try requestStore.list().first?.status, "failed")
        XCTAssertEqual(
            try journal.records(executionID: "execution-1").first?.state,
            .failedBeforeSideEffect
        )

        let result = try tool.execute(arguments: arguments, context: context)

        XCTAssertEqual(result.output["notificationId"], .string("standup-reminder"))
        XCTAssertEqual(try client.listScheduled().count, 1)
        XCTAssertEqual(try requestStore.list().first?.status, "scheduled")
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

    func testReminderBulkSuccessIncludesExternalResourceIDsForReceiptEvidence() throws {
        let connection = try migratedConnection()
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let tool = ReminderTool(
            name: .remindersBulkCreate,
            client: InMemoryReminderClient(),
            sideEffectJournal: journal
        )

        let result = try tool.execute(
            arguments: [
                "reminders": .array([
                    .object(["title": .string("Draft")]),
                    .object(["title": .string("Review")])
                ])
            ],
            context: approvedSideEffectContext(idempotencyKey: "reminder-bulk-success")
        )

        XCTAssertEqual(
            result.output["externalResourceIds"],
            .array([.string("reminder-1"), .string("reminder-2")])
        )
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

private final class LockedClaimOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var claimStorage: [ExternalSideEffectClaim] = []
    private var errorStorage: [Error] = []

    var claims: [ExternalSideEffectClaim] {
        lock.lock()
        defer { lock.unlock() }
        return claimStorage
    }

    var errors: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return errorStorage
    }

    func append(_ claim: ExternalSideEffectClaim) {
        lock.lock()
        claimStorage.append(claim)
        lock.unlock()
    }

    func append(_ error: Error) {
        lock.lock()
        errorStorage.append(error)
        lock.unlock()
    }
}

private final class LockedErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}

private final class FailOnceNotificationClient: NotificationClient, @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true
    private var records: [NotificationRecord] = []

    func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
        lock.lock()
        defer { lock.unlock() }
        if shouldFail {
            shouldFail = false
            throw ToolClientError.invalidRequest("Notification schedule is invalid.")
        }
        let record = NotificationRecord(
            id: draft.identifierHint ?? "notification-1",
            title: draft.title,
            body: draft.body,
            scheduledAt: draft.scheduledAt
        )
        records.append(record)
        return record
    }

    func cancel(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            throw ToolClientError.notFound("Notification \(id) was not found.")
        }
        records.remove(at: index)
    }

    func listScheduled() throws -> [NotificationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }
}
