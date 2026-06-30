import XCTest
@testable import SoloPMCore

final class AssistantQueueExecutionTests: XCTestCase {
    func testCoordinatorRunsApprovedActionPlanAndPersistsQueueReceipt() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = InMemoryExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                XCTAssertEqual(context.source, .reviewUI)
                return ToolResult(
                    tool: .taskCreate,
                    status: .succeeded,
                    summary: "Created Launch checklist",
                    output: ["taskId": .number(42), "projectId": .number(7)]
                )
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-success" },
            now: { Date(timeIntervalSince1970: 100) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        XCTAssertNil(try queueStore.get(id: approved.id).blockingReason)
        XCTAssertNil(try queueStore.get(id: approved.id).approval?.executionTokenID)

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertEqual(receipt.queueApproval?.reviewerID, "local-user")
        XCTAssertEqual(receipt.queueApproval?.reviewedContentDigest, approved.approval?.reviewedContentFingerprint)
        XCTAssertEqual(receipt.approvalID, result.session.approvalToken?.id)
        XCTAssertEqual(receipt.references.first, ExecutionReceiptReference(kind: .assistantQueue, id: approved.id, label: "Create Launch checklist"))
        XCTAssertEqual(receipt.actions.first?.status, .succeeded)
        XCTAssertEqual(receipt.visibleSurfaces, [.assistantQueue])
    }

    func testCoordinatorRequiresQueueApprovalBeforeRunning() throws {
        let queueStore = try makeQueueStore()
        let item = makeActionPlanItem()
        try queueStore.save(item)
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: ToolRegistry()),
            executionReceiptStore: InMemoryExecutionReceiptStore()
        )

        XCTAssertThrowsError(try coordinator.execute(id: item.id)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .approvalRequiredBeforeRunning)
        }
        XCTAssertEqual(try queueStore.get(id: item.id).state, .waitingReview)
    }

    func testCoordinatorMarksQueueFailedAndPersistsFailedReceiptWhenToolFails() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = InMemoryExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                throw ToolExecutionError.executionFailed(.taskCreate, "provider failed token=queue-secret")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-failure" },
            now: { Date(timeIntervalSince1970: 200) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .failed)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .failed)
        XCTAssertEqual(try queueStore.get(id: approved.id).blockingReason, "Execution failed. Review the receipt before retrying.")

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        XCTAssertEqual(receipt.queueApproval?.reviewerID, "local-user")
        XCTAssertTrue(receipt.outputSummary.contains("failed"))
        XCTAssertTrue(receipt.actions.first?.errorSummary?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(receipt.actions.first?.errorSummary?.contains("queue-secret") ?? true)
    }

    func testCoordinatorCanRunReapprovedFailedItemAfterRetryReviewAndKeepsSeparateReceipts() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = InMemoryExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let failingRegistry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                throw ToolExecutionError.executionFailed(.taskCreate, "provider failed")
            }
        ])
        let failingCoordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: failingRegistry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-retry-failure" },
            now: { Date(timeIntervalSince1970: 200) }
        )

        _ = try failingCoordinator.execute(id: approved.id)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .failed)

        let reopened = try queueStore.transition(id: approved.id) { item in
            try AssistantQueueStateMachine.reopenFailedForReview(item)
        }
        XCTAssertEqual(reopened.state, .waitingReview)
        XCTAssertNil(reopened.approval)
        let reapproved = try queueStore.transition(id: approved.id) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
        let successRegistry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created after retry")
            }
        ])
        let successCoordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: successRegistry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-queue-retry-success" },
            now: { Date(timeIntervalSince1970: 300) }
        )

        let result = try successCoordinator.execute(id: reapproved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)
        XCTAssertEqual(receiptStore.receipts.map(\.assistantQueueItemID), [approved.id, approved.id])
        XCTAssertEqual(receiptStore.receipts.map(\.status), [.failed, .succeeded])
        XCTAssertEqual(receiptStore.receipts.map(\.runID), ["run-queue-retry-failure", "run-queue-retry-success"])
        XCTAssertEqual(receiptStore.receipts[0].queueApproval?.reviewedContentDigest, receiptStore.receipts[1].queueApproval?.reviewedContentDigest)
        XCTAssertNotEqual(receiptStore.receipts[0].queueApproval?.approvalID, receiptStore.receipts[1].queueApproval?.approvalID)
    }

    func testCoordinatorDoesNotMarkDoneWhenReceiptCannotBePersisted() throws {
        let queueStore = try makeQueueStore()
        let approved = try AssistantQueueStateMachine.approve(makeActionPlanItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create task",
                inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "Created")
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: FailingExecutionReceiptStore(),
            runIDProvider: { "run-queue-receipt-failure" },
            now: { Date(timeIntervalSince1970: 300) }
        )

        XCTAssertThrowsError(try coordinator.execute(id: approved.id)) { error in
            XCTAssertEqual(error as? FailingExecutionReceiptStore.Error, .saveFailed)
        }
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .running)
    }

    private func makeQueueStore() throws -> SQLiteAssistantQueueStore {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return SQLiteAssistantQueueStore(connection: connection)
    }

    private func makeActionPlanItem() -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "plan-queue-execution",
                userInput: "Create Launch checklist",
                summary: "Create Launch checklist",
                actions: [
                    PlanAction(
                        id: "action-create",
                        tool: .taskCreate,
                        arguments: ["title": .string("Launch checklist")],
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Create Launch checklist",
            interpretationSummary: "Task creation",
            reason: "Needs review before execution."
        )
    }
}

private final class FailingExecutionReceiptStore: ExecutionReceiptStore, @unchecked Sendable {
    enum Error: Swift.Error, Equatable {
        case saveFailed
    }

    func save(_ receipt: ExecutionReceipt) throws {
        throw Error.saveFailed
    }

    func list(limit: Int) throws -> [ExecutionReceipt] {
        []
    }

    func list(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int
    ) throws -> [ExecutionReceipt] {
        []
    }
}
