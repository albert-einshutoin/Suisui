import XCTest
@testable import SuisuiCore

final class AuditedTaskCreationTests: XCTestCase {
    func testSharedSessionPreservesUnknownAcrossEditingAndReapproval() throws {
        let connection = try connection()
        try connection.execute("""
            CREATE TRIGGER fail_creation_result BEFORE UPDATE ON external_side_effect_journal
            WHEN NEW.state = 'succeeded'
            BEGIN SELECT RAISE(ABORT, 'fixture'); END;
            """)
        let executor = try executor(connection)
        var session = try executor.execute(approvedSession())
        try connection.execute("DROP TRIGGER fail_creation_result;")
        session.requestFreshApproval()
        let original = session
        session.updateStringArgument(id: "create", key: "title", value: "private fixture text ")
        XCTAssertEqual(session, original)
        session.editActionArguments(id: "create", arguments: ["title": .string("changed")])
        XCTAssertEqual(session, original)
        session.resetAction(id: "create")
        XCTAssertEqual(session, original)
        session.setActionEnabled(id: "create", false)
        XCTAssertEqual(session, original)
        XCTAssertFalse(session.canApprove)
        XCTAssertFalse(session.canExecute)
        XCTAssertThrowsError(try session.approve())
        XCTAssertThrowsError(try executor.execute(session)) { error in
            guard case ActionExecutorError.approvalBlocked = error else {
                return XCTFail("Expected reconciliation rejection, got \(error)")
            }
        }
        XCTAssertTrue(session.requiresReconciliation)
        XCTAssertEqual(try SQLiteTaskStore(connection: connection).listAll().count, 1)
    }

    @MainActor
    func testReviewUnknownCannotBeReapprovedOrClearedByEditing() throws {
        let connection = try connection()
        try connection.execute("""
            CREATE TRIGGER fail_creation_result BEFORE UPDATE ON external_side_effect_journal
            WHEN NEW.state = 'succeeded'
            BEGIN SELECT RAISE(ABORT, 'fixture'); END;
            """)
        let viewModel = ReviewSessionViewModel(
            plan: try approvedSession().originalPlan,
            executor: try executor(connection)
        )
        try viewModel.approve()
        try viewModel.execute()
        XCTAssertTrue(viewModel.session.requiresReconciliation)
        XCTAssertFalse(viewModel.canApprove)
        XCTAssertFalse(viewModel.canExecute)
        let beforeEdit = viewModel.session
        viewModel.updateStringArgument(actionID: "create", key: "title", value: "changed")
        viewModel.resetAction(actionID: "create")
        viewModel.setActionEnabled(actionID: "create", isEnabled: false)
        XCTAssertEqual(viewModel.session, beforeEdit)
        XCTAssertTrue(viewModel.lastExecutionReceipt?.actions.first?.errorSummary?.contains("unknown") == true)
        XCTAssertEqual(try SQLiteTaskStore(connection: connection).listAll().count, 1)
    }

    func testAuditFailureBeforeCreationDoesNotCreateOrSucceed() throws {
        let connection = try connection()
        let session = try approvedSession()
        let result = try executor(connection, logger: FailingTaskAuditLogger(failOnStart: true)).execute(session)

        XCTAssertEqual(result.executionStatus, .failed)
        XCTAssertNil(result.items.first?.result)
        XCTAssertTrue(try SQLiteTaskStore(connection: connection).listAll().isEmpty)
        XCTAssertTrue(try SQLiteExternalSideEffectJournal(connection: connection).records(
            executionID: XCTUnwrap(session.approvalToken?.nonce.uuidString)
        ).isEmpty)
    }

    func testSucceededCreationAndReplayFinishFailureSurviveReopeningDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("tasks.sqlite").path
        var session = try approvedSession()
        let nonce = try XCTUnwrap(session.approvalToken?.nonce)
        do {
            let connection = try connection(path)
            try connection.execute("""
                CREATE TRIGGER fail_nonce_finish BEFORE UPDATE ON approval_execution_nonces
                BEGIN SELECT RAISE(ABORT, 'private fixture text'); END;
                """)
            session = try executor(connection).execute(session)
            XCTAssertEqual(session.executionStatus, .completed)
            XCTAssertEqual(session.items.first?.result?.output["taskId"], .number(1))
            XCTAssertEqual(session.auditErrorMessage, "Execution state could not be saved. Do not repeat completed actions.")
            XCTAssertEqual(try SQLiteApprovalReplayStore(connection: connection).state(for: nonce), .started)
            try connection.execute("DROP TRIGGER fail_nonce_finish;")
        }
        let reopened = try SQLiteConnection(path: path)
        XCTAssertThrowsError(try executor(reopened).execute(session))
        session.requestFreshApproval()
        try session.approve()
        let retried = try executor(reopened).execute(session)
        XCTAssertEqual(retried.items.first?.result?.output["taskId"], .number(1))
        XCTAssertEqual(try SQLiteTaskStore(connection: reopened).listAll().count, 1)
    }

    func testUnknownCreationBlocksRetryAcrossRestartEvenWhenUnknownSaveAlsoFails() throws {
        for failUnknownSave in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.appendingPathComponent("tasks.sqlite").path
            var session = try approvedSession()
            let executionID = try XCTUnwrap(session.approvalToken?.nonce.uuidString)
            do {
                let connection = try connection(path)
                let states = failUnknownSave ? "'succeeded', 'unknown'" : "'succeeded'"
                try connection.execute("""
                    CREATE TRIGGER fail_journal_finish BEFORE UPDATE ON external_side_effect_journal
                    WHEN NEW.state IN (\(states))
                    BEGIN SELECT RAISE(ABORT, 'private fixture text'); END;
                    """)
                // Failure auditing also fails: it must not replace unknown evidence.
                session = try executor(connection, logger: FailingTaskAuditLogger()).execute(session)
                XCTAssertEqual(session.executionStatus, .failed)
                XCTAssertEqual(session.items.first?.failureRecovery, .notRetryable)
                XCTAssertEqual(session.items.first?.result?.output["journalState"], .string("unknown"))
                XCTAssertEqual(try SQLiteTaskStore(connection: connection).listAll().count, 1)
                let record = try XCTUnwrap(SQLiteExternalSideEffectJournal(connection: connection)
                    .records(executionID: executionID).first)
                XCTAssertEqual(record.state, failUnknownSave ? .started : .unknown)
                XCTAssertFalse((session.items.first?.errorMessage ?? "").contains("private fixture text"))
                try connection.execute("DROP TRIGGER fail_journal_finish;")
            }
            let reopened = try SQLiteConnection(path: path)
            let journal = SQLiteExternalSideEffectJournal(connection: reopened)
            _ = try journal.recoverStartedAsUnknown(at: Date())
            XCTAssertEqual(try journal.records(executionID: executionID).first?.state, .unknown)
            session.requestFreshApproval()
            XCTAssertThrowsError(try session.approve())
            XCTAssertThrowsError(try executor(reopened).execute(session))
            // Reconstructed sessions must still be stopped by durable journal evidence.
            session = ReviewSession(id: session.id, plan: session.originalPlan)
            try session.approve()
            let retried = try executor(reopened).execute(session)
            XCTAssertEqual(retried.items.first?.result?.output["journalState"], .string("unknown"))
            XCTAssertEqual(retried.items.first?.failureRecovery, .notRetryable)
            XCTAssertEqual(try SQLiteTaskStore(connection: reopened).listAll().count, 1)
        }
    }

    func testBulkCreationAuditFailureReusesIDsAndJournalContainsNoTaskText() throws {
        let connection = try connection()
        var session = try approvedSession(tool: .taskBulkCreate, arguments: [
            "tasks": .array([
                .object(["title": .string("private title"), "detail": .string("private body")]),
                .object(["title": .string("second private title")])
            ])
        ])
        let executionID = try XCTUnwrap(session.approvalToken?.nonce.uuidString)
        session = try executor(connection, logger: FailingTaskAuditLogger(), tool: .taskBulkCreate).execute(session)
        XCTAssertEqual(session.executionStatus, .completed)
        let ids = session.items.first?.result?.output["taskIds"]
        XCTAssertEqual(ids, .array([.number(1), .number(2)]))
        let journal = SQLiteExternalSideEffectJournal(connection: connection)
        let evidence = try XCTUnwrap(journal.records(executionID: executionID).first)
        XCTAssertFalse(String(describing: evidence).contains("private title"))
        XCTAssertFalse(String(describing: evidence).contains("private body"))
        session.requestFreshApproval()
        try session.approve()
        session = try executor(connection, tool: .taskBulkCreate).execute(session)
        XCTAssertEqual(session.items.first?.result?.output["taskIds"], ids)
        XCTAssertEqual(try SQLiteTaskStore(connection: connection).listAll().count, 2)
    }

    private func connection(_ path: String = ":memory:") throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private func approvedSession(
        tool: ActionTool = .taskCreate,
        arguments: [String: JSONValue] = ["title": .string("private fixture text")]
    ) throws -> ReviewSession {
        var session = ReviewSession(plan: ActionPlan(
            id: "audited-task-plan", userInput: "fixture", summary: "fixture",
            actions: [PlanAction(id: "create", tool: tool, arguments: arguments)],
            riskLevel: .write, requiresApproval: true
        ))
        try session.approve()
        return session
    }

    private func executor(
        _ connection: SQLiteConnection,
        logger: any AuditLogger = InMemoryAuditLogger(),
        tool: ActionTool = .taskCreate
    ) throws -> ActionExecutor {
        let registry = try ToolRegistry(tools: [AuditedTool(
            base: TaskTool(name: tool, store: SQLiteTaskStore(connection: connection)), logger: logger
        )])
        return ActionExecutor(registry: registry, replayStore: SQLiteApprovalReplayStore(connection: connection))
    }
}

struct FailingTaskAuditLogger: AuditLogger {
    var failOnStart = false

    func record(_ event: AuditEvent) throws {
        if failOnStart || event.status != .started {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
