import XCTest
@testable import SoloPMCore

final class AssistantQueueStoreTests: XCTestCase {
    func testSQLiteStorePersistsQueueItemsAndLoadsByState() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let waiting = makeItem(id: "queue-waiting", state: .waitingReview, summary: "Create launch task")
        let blocked = makeItem(id: "queue-blocked", state: .blocked, summary: "Blocked filesystem write")

        try store.save(waiting)
        try store.save(blocked)

        XCTAssertEqual(try store.get(id: waiting.id), waiting)
        XCTAssertEqual(try store.get(id: blocked.id), blocked)
        XCTAssertEqual(
            Set(try store.list(filter: .states([.waitingReview], limit: 10)).map(\.id)),
            Set([waiting.id])
        )
        XCTAssertEqual(
            Set(try store.list(filter: .states([.waitingReview, .blocked], limit: 10)).map(\.id)),
            Set([waiting.id, blocked.id])
        )
    }

    func testSQLiteStorePersistsApprovalWithoutExecutionToken() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(id: "queue-approval")

        try store.save(item)
        let approved = try store.transition(id: item.id) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
        let reloaded = try store.get(id: item.id)

        XCTAssertEqual(reloaded, approved)
        XCTAssertEqual(reloaded.state, .approved)
        XCTAssertEqual(reloaded.approval?.reviewerID, "local-user")
        XCTAssertNil(reloaded.approval?.executionTokenID)
    }

    func testSQLiteStoreRejectsInvalidStoredState() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(id: "queue-invalid")

        try store.save(item)
        try connection.execute("UPDATE assistant_queue_items SET state = 'not_real' WHERE id = 'queue-invalid';")

        XCTAssertThrowsError(try store.get(id: item.id)) { error in
            XCTAssertEqual(
                error as? AssistantQueueStoreError,
                .invalidStoredValue(column: "assistant_queue_items.state", value: "not_real")
            )
        }
    }

    func testReadModelCountsReviewableItemsAndRedactsSourcePreview() throws {
        let secretSource = "Create task with token=sk-assistantQueueStoreSecret"
        let waiting = makeItem(
            id: "queue-read-model-waiting",
            state: .waitingReview,
            sourceTranscript: secretSource,
            summary: secretSource
        )
        let blocked = makeItem(id: "queue-read-model-blocked", state: .blocked, summary: "Blocked task")
        let done = makeItem(id: "queue-read-model-done", state: .done, summary: "Done task")
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-read-model-approved", state: .waitingReview, summary: "Approved task"),
            reviewerID: "local-user"
        )
        let failed = makeItem(id: "queue-read-model-failed", state: .failed, summary: "Failed task")

        let snapshot = AssistantQueueReadModel.snapshot(from: [done, blocked, waiting, approved, failed])

        XCTAssertEqual(snapshot.waitingReviewCount, 1)
        XCTAssertEqual(snapshot.blockedCount, 1)
        XCTAssertEqual(snapshot.reviewableCount, 2)
        XCTAssertEqual(snapshot.rows.map(\.id), [blocked.id, waiting.id, approved.id, failed.id, done.id])
        let waitingRow = try XCTUnwrap(snapshot.rows.first { $0.id == waiting.id })
        XCTAssertFalse(waitingRow.title.contains("sk-assistantQueueStoreSecret"))
        XCTAssertFalse(waitingRow.sourcePreview?.contains("sk-assistantQueueStoreSecret") ?? true)
        XCTAssertTrue(waitingRow.canApprove)
        XCTAssertFalse(waitingRow.canRun)
        XCTAssertTrue(waitingRow.canDefer)
        XCTAssertTrue(waitingRow.canReject)
        let approvedRow = try XCTUnwrap(snapshot.rows.first { $0.id == approved.id })
        XCTAssertFalse(approvedRow.canApprove)
        XCTAssertTrue(approvedRow.canRun)
        let blockedRow = try XCTUnwrap(snapshot.rows.first { $0.id == blocked.id })
        XCTAssertFalse(blockedRow.canApprove)
        XCTAssertFalse(blockedRow.canRun)
        XCTAssertTrue(blockedRow.canReject)
        let failedRow = try XCTUnwrap(snapshot.rows.first { $0.id == failed.id })
        XCTAssertEqual(failedRow.stateLabel, "Failed")
        XCTAssertFalse(failedRow.canRun)
        XCTAssertFalse(failedRow.canReject)
    }

    @MainActor
    func testProjectBoardViewModelLoadsAssistantQueueSnapshotFromStore() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let item = makeItem(id: "queue-project-board", state: .waitingReview, summary: "Create board-visible task")
        try assistantQueueStore.save(item)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        XCTAssertEqual(viewModel.assistantQueueSnapshot.reviewableCount, 1)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first?.id, item.id)
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testProjectBoardViewModelTransitionsAssistantQueueRowsFromVisibleInboxActions() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let waiting = makeItem(id: "queue-visible-approve", state: .waitingReview, summary: "Create visible inbox task")
        let deferred = makeItem(id: "queue-visible-defer", state: .waitingReview, summary: "Review later")
        let blocked = makeItem(id: "queue-visible-blocked", state: .blocked, summary: "Blocked destructive plan")
        try assistantQueueStore.save(waiting)
        try assistantQueueStore.save(deferred)
        try assistantQueueStore.save(blocked)
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore
        )

        viewModel.load()

        XCTAssertTrue(viewModel.approveAssistantQueueItem(id: waiting.id))
        XCTAssertEqual(try assistantQueueStore.get(id: waiting.id).state, .approved)
        XCTAssertNil(try assistantQueueStore.get(id: waiting.id).approval?.executionTokenID)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == waiting.id }?.state, .approved)

        XCTAssertTrue(viewModel.deferAssistantQueueItem(id: deferred.id))
        XCTAssertEqual(try assistantQueueStore.get(id: deferred.id).state, .deferred)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == deferred.id }?.state, .deferred)

        XCTAssertFalse(viewModel.approveAssistantQueueItem(id: blocked.id))
        XCTAssertEqual(try assistantQueueStore.get(id: blocked.id).state, .blocked)
        XCTAssertEqual(viewModel.errorMessage, "Blocked Assistant Queue items cannot be approved.")

        XCTAssertTrue(viewModel.rejectAssistantQueueItem(id: blocked.id))
        XCTAssertEqual(try assistantQueueStore.get(id: blocked.id).state, .rejected)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == blocked.id }?.state, .rejected)
    }

    @MainActor
    func testProjectBoardViewModelRunsApprovedAssistantQueueItemThroughExecutionCoordinator() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = InMemoryExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(
            makeItem(id: "queue-visible-run", state: .waitingReview, summary: "Create runnable task"),
            reviewerID: "local-user"
        )
        try assistantQueueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created runnable task")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: assistantQueueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-board-queue" },
            now: { Date(timeIntervalSince1970: 500) }
        )
        let viewModel = ProjectBoardViewModel(
            store: boardStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: coordinator
        )

        viewModel.load()

        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.canRun, true)
        XCTAssertTrue(viewModel.runAssistantQueueItem(id: approved.id))
        XCTAssertEqual(try assistantQueueStore.get(id: approved.id).state, .done)
        XCTAssertEqual(viewModel.assistantQueueSnapshot.rows.first { $0.id == approved.id }?.state, .done)
        XCTAssertEqual(receiptStore.receipts.first?.assistantQueueItemID, approved.id)
        XCTAssertEqual(viewModel.integrationStatusMessage, "Executed Assistant Queue item.")
        XCTAssertNil(viewModel.errorMessage)
    }

    private func makeItem(
        id: String = "queue-item",
        state: AssistantQueueState = .waitingReview,
        sourceTranscript: String = "Create a task",
        summary: String = "Create task"
    ) -> AssistantQueueItem {
        AssistantQueueItem(
            id: id,
            state: state,
            payload: .actionPlan(ActionPlan(
                id: "\(id)-plan",
                userInput: sourceTranscript,
                summary: summary,
                actions: [
                    PlanAction(
                        id: "\(id)-action",
                        tool: .taskCreate,
                        arguments: ["title": .string(summary)],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )),
            riskLevel: .write,
            sourceTranscript: sourceTranscript,
            interpretationSummary: "Routed as task intent.",
            reviewReason: "Voice planning draft needs review.",
            redactedSummary: summary,
            requiredCapabilities: [.tool(.taskCreate), .providerExecutionApproval],
            blockingReason: state == .blocked ? "Dangerous action plans cannot be approved from Assistant Queue." : nil
        )
    }
}
