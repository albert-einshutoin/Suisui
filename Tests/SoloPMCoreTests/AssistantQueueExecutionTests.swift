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

    func testCoordinatorRunsApprovedAutomationRequestTaskMutationThroughActionExecutor() throws {
        let queueStore = try makeQueueStore()
        let receiptStore = InMemoryExecutionReceiptStore()
        let approved = try AssistantQueueStateMachine.approve(makeTaskMutationItem(), reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskUpdate,
                description: "update task",
                inputSchema: ToolInputSchema(required: ["id"], properties: ["id": "number", "dueAt": "string"]),
                permissionLevel: .writeWithApproval
            ) { arguments, context in
                XCTAssertNotNil(context.approvalToken)
                XCTAssertEqual(context.source, .reviewUI)
                XCTAssertEqual(arguments["id"], .number(42))
                XCTAssertEqual(arguments["dueAt"], .string("2026-07-01T09:00:00Z"))
                return ToolResult(
                    tool: .taskUpdate,
                    status: .succeeded,
                    summary: "Updated due date",
                    output: ["taskId": .number(42)]
                )
            }
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-automation-task-mutation" },
            now: { Date(timeIntervalSince1970: 150) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(result.session.originalPlan.id, "automation-request:automation-task-due")
        XCTAssertEqual(result.session.originalPlan.actions.map(\.tool), [.taskUpdate])
        XCTAssertEqual(try queueStore.get(id: approved.id).state, .done)

        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertEqual(receipt.assistantQueueItemID, approved.id)
        let queueReference = try XCTUnwrap(receipt.references.first)
        XCTAssertEqual(queueReference.kind, .assistantQueue)
        XCTAssertEqual(queueReference.id, approved.id)
        XCTAssertTrue(queueReference.label?.contains("taskID=42, dueAt=2026-07-01T09:00:00Z") ?? false)
        XCTAssertTrue(queueReference.label?.contains("Mutation: operation=updateDueDate") ?? false)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: "42")))
        XCTAssertEqual(receipt.actions.first?.toolName, ActionTool.taskUpdate.rawValue)
    }

    func testCoordinatorRunsApprovedAutomationRequestTaskMutationAgainstSQLiteTaskTool() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = SQLiteAssistantQueueStore(connection: connection)
        let receiptStore = InMemoryExecutionReceiptStore()
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let task = try taskStore.create(title: "Existing remote task")
        let item = AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: "automation-real-task-due",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            redactedArgumentSummary: "taskID=\(task.id), dueAt=2026-07-03T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: task.id,
                operation: .updateDueDate,
                dueAt: "2026-07-03T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        try queueStore.save(approved)
        let registry = try ToolRegistry(tools: [
            TaskTool(name: .taskUpdate, store: taskStore, projectStore: projectStore)
        ])
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore,
            runIDProvider: { "run-automation-real-task-mutation" },
            now: { Date(timeIntervalSince1970: 175) }
        )

        let result = try coordinator.execute(id: approved.id)

        XCTAssertEqual(result.item.state, .done)
        XCTAssertEqual(try taskStore.get(id: task.id).dueAt, "2026-07-03T09:00:00Z")
        let receipt = try XCTUnwrap(receiptStore.receipts.first)
        XCTAssertEqual(receipt.status, .succeeded)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: String(task.id))))
    }

    func testCoordinatorRejectsMalformedAutomationRequestBeforeRunning() throws {
        let queueStore = try makeQueueStore()
        let missingTaskID = try AssistantQueueStateMachine.approve(
            makeMalformedTaskMutationItem(id: "automation-missing-task-id"),
            reviewerID: "local-user"
        )
        let noOpUpdate = try AssistantQueueStateMachine.approve(
            makeNoOpUpdateTaskMutationItem(id: "automation-no-op-update"),
            reviewerID: "local-user"
        )
        let mismatchedTool = try AssistantQueueStateMachine.approve(
            makeTaskMutationItem(id: "automation-mismatched-tool", toolName: HostedMCPTaskToolName.taskCreate.rawValue),
            reviewerID: "local-user"
        )
        try queueStore.save(missingTaskID)
        try queueStore.save(noOpUpdate)
        try queueStore.save(mismatchedTool)
        let coordinator = AssistantQueueExecutionCoordinator(
            queueStore: queueStore,
            executor: ActionExecutor(registry: ToolRegistry()),
            executionReceiptStore: InMemoryExecutionReceiptStore()
        )

        for item in [missingTaskID, noOpUpdate, mismatchedTool] {
            XCTAssertThrowsError(try coordinator.execute(id: item.id)) { error in
                XCTAssertEqual(error as? AssistantQueueExecutionError, .unsupportedPayload)
            }
            XCTAssertEqual(try queueStore.get(id: item.id).state, .approved)
        }
    }

    func testExecutableFactoryMapsTaskMutationOperationsToLocalTaskTools() throws {
        let cases: [(SyncTaskMutationPayload, ActionTool, [String: JSONValue])] = [
            (
                SyncTaskMutationPayload(
                    operation: .create,
                    title: "Remote task",
                    detail: "Details",
                    projectID: 7,
                    dueAt: "2026-07-01",
                    priority: "high",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskCreate,
                [
                    "title": .string("Remote task"),
                    "detail": .string("Details"),
                    "projectId": .number(7),
                    "dueAt": .string("2026-07-01"),
                    "priority": .string("high")
                ]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .update,
                    title: "Renamed",
                    status: "in_progress",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskUpdate,
                [
                    "id": .number(42),
                    "title": .string("Renamed"),
                    "status": .string("in_progress")
                ]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .complete,
                    status: "completed",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskComplete,
                ["id": .number(42)]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .moveProject,
                    projectID: 8,
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskUpdate,
                ["id": .number(42), "projectId": .number(8)]
            ),
            (
                SyncTaskMutationPayload(
                    taskID: 42,
                    operation: .updateDueDate,
                    dueAt: "2026-07-02",
                    source: .cloudRelay,
                    approvalState: .pendingApproval
                ),
                .taskUpdate,
                ["id": .number(42), "dueAt": .string("2026-07-02")]
            )
        ]

        for (index, testCase) in cases.enumerated() {
            let request = SyncAutomationRequestPayload(
                id: "automation-\(index)",
                source: .cloudRelay,
                approvalState: .pendingApproval,
                toolName: hostedToolName(for: testCase.0.operation),
                redactedArgumentSummary: "case-\(index)",
                taskMutation: testCase.0
            )
            let plan = try XCTUnwrap(AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(request)))

            XCTAssertEqual(plan.id, "automation-request:automation-\(index)")
            XCTAssertEqual(plan.requiresApproval, true)
            XCTAssertEqual(plan.actions.first?.tool, testCase.1)
            XCTAssertEqual(plan.actions.first?.arguments, testCase.2)
        }
    }

    func testExecutableFactoryIncludesRedactedMutationDetailInReviewSummary() throws {
        let request = SyncAutomationRequestPayload(
            id: "automation-redacted-detail",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .update,
                detail: "Use token=detail-secret before launch",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        )

        let summary = AssistantQueueExecutableActionPlanFactory.reviewSummary(for: request)
        let plan = try XCTUnwrap(AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(request)))

        XCTAssertTrue(summary.contains("detail=Use [REDACTED_SECRET] before launch"))
        XCTAssertFalse(summary.contains("detail-secret"))
        XCTAssertEqual(plan.summary, summary)
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

    private func makeTaskMutationItem(
        id: String = "automation-task-due",
        toolName: String = HostedMCPTaskToolName.taskDueDateUpdate.rawValue
    ) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: toolName,
            redactedArgumentSummary: "taskID=42, dueAt=2026-07-01T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .updateDueDate,
                dueAt: "2026-07-01T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
    }

    private func makeMalformedTaskMutationItem(id: String) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskComplete.rawValue,
            redactedArgumentSummary: "Complete remote task without taskID",
            taskMutation: SyncTaskMutationPayload(
                operation: .complete,
                status: "completed",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
    }

    private func makeNoOpUpdateTaskMutationItem(id: String) -> AssistantQueueItem {
        AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: id,
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskUpdate.rawValue,
            redactedArgumentSummary: "Update remote task without changed fields",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .update,
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
    }

    private func hostedToolName(for operation: SyncTaskMutationOperation) -> String {
        switch operation {
        case .create:
            return HostedMCPTaskToolName.taskCreate.rawValue
        case .update:
            return HostedMCPTaskToolName.taskUpdate.rawValue
        case .complete:
            return HostedMCPTaskToolName.taskComplete.rawValue
        case .moveProject:
            return HostedMCPTaskToolName.taskProjectMove.rawValue
        case .updateDueDate:
            return HostedMCPTaskToolName.taskDueDateUpdate.rawValue
        }
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
