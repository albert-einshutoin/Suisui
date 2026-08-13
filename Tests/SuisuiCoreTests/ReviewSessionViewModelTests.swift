import XCTest
@testable import SuisuiCore

@MainActor
final class ReviewSessionViewModelTests: XCTestCase {
    func testApproveEditAndExecuteSession() throws {
        let logger = InMemoryAuditLogger()
        let receiptStore = VolatileExecutionReceiptStore()
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"]), permissionLevel: .writeWithApproval) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created", rollbackMetadata: ["taskId": .number(1)])
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry, auditLogger: logger),
            auditLogger: logger,
            executionReceiptStore: receiptStore
        )

        viewModel.updateStringArgument(actionID: "task", key: "title", value: "Review")
        try viewModel.approve()
        let approvalID = try XCTUnwrap(viewModel.session.approvalToken?.approvalID.uuidString)
        try viewModel.execute()

        XCTAssertEqual(viewModel.session.items.first?.editedAction.arguments["title"], .string("Review"))
        XCTAssertEqual(viewModel.session.executionStatus, .completed)
        XCTAssertEqual(viewModel.session.items.first?.result?.rollbackMetadata["taskId"], .number(1))
        XCTAssertTrue(logger.recordedEvents.contains { $0.action == "session.approve" })
        XCTAssertEqual(viewModel.lastExecutionReceipt?.status, .succeeded)
        XCTAssertEqual(viewModel.lastExecutionReceipt?.actions.first?.status, .succeeded)
        XCTAssertEqual(viewModel.lastExecutionReceipt?.approvalID, approvalID)
        XCTAssertNil(viewModel.session.approvalToken)
        XCTAssertEqual(viewModel.executionReceipts.map(\.id), receiptStore.receipts.map(\.id))
        let receipt = try XCTUnwrap(viewModel.lastExecutionReceipt)
        let receiptAudit = try XCTUnwrap(logger.recordedEvents.last { $0.category == "receipt" && $0.action == "execution.receipt.create" })
        XCTAssertEqual(receiptAudit.metadata["receipt_id"], receipt.id)
        XCTAssertEqual(receiptAudit.metadata["run_id"], receipt.runID)
        XCTAssertEqual(receiptAudit.metadata["receipt_status"], ExecutionReceiptStatus.succeeded.rawValue)
        XCTAssertEqual(receiptAudit.metadata["session_id"], viewModel.session.id)
    }

    func testCompletedExecutionRequestsFreshApprovalWithoutNoOpEdit() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .taskCreate,
                description: "create",
                inputSchema: ToolInputSchema(required: ["title"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry)
        )

        try viewModel.approve()
        let consumedNonce = try XCTUnwrap(viewModel.session.approvalToken?.nonce)
        try viewModel.execute()

        XCTAssertTrue(viewModel.canApprove)
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertNil(viewModel.session.approvalToken)

        try viewModel.approve()
        XCTAssertNotEqual(viewModel.session.approvalToken?.nonce, consumedNonce)
        XCTAssertTrue(viewModel.canExecute)
    }

    func testNotificationExecutionReceiptIncludesScheduledNotificationReference() throws {
        let receiptStore = VolatileExecutionReceiptStore()
        let registry = try ToolRegistry(tools: [
            NotificationTool(name: .notificationSchedule, client: InMemoryNotificationClient())
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(
                    id: "notify",
                    tool: .notificationSchedule,
                    arguments: [
                        "id": .string("notification-standup"),
                        "title": .string("Standup"),
                        "scheduledAt": .string("2026-07-01T09:00:00Z")
                    ],
                    riskLevel: .write
                )
            ]),
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore
        )

        try viewModel.approve()
        try viewModel.execute()

        let receipt = try XCTUnwrap(viewModel.lastExecutionReceipt)
        XCTAssertEqual(receiptStore.receipts, [receipt])
        XCTAssertEqual(receipt.actions.first?.toolName, ActionTool.notificationSchedule.rawValue)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .notification, id: "notification-standup")))
    }

    func testReminderExecutionReceiptIncludesCreatedReminderReference() throws {
        let receiptStore = VolatileExecutionReceiptStore()
        let registry = try ToolRegistry(tools: [
            ReminderTool(name: .remindersCreate, client: InMemoryReminderClient())
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(
                    id: "reminder",
                    tool: .remindersCreate,
                    arguments: [
                        "title": .string("Send launch notes"),
                        "dueAt": .string("2026-07-01T09:00:00Z")
                    ],
                    riskLevel: .write
                )
            ]),
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore
        )

        try viewModel.approve()
        try viewModel.execute()

        let receipt = try XCTUnwrap(viewModel.lastExecutionReceipt)
        XCTAssertEqual(receiptStore.receipts, [receipt])
        XCTAssertEqual(receipt.actions.first?.toolName, ActionTool.remindersCreate.rawValue)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .reminder, id: "reminder-1")))
    }

    func testDevelopmentPRWorkflowExecutionReceiptIncludesBranchEvidenceAndScopedVisibility() throws {
        let branchName = "feature/suisui-7-42-fix-calendar-sync"
        let receiptStore = VolatileExecutionReceiptStore()
        let registry = try ToolRegistry(tools: [
            StaticTool(
                name: .developmentPreparePullRequestWorkflow,
                description: "prepare PR",
                inputSchema: ToolInputSchema(
                    required: ["projectId"],
                    properties: [
                        "projectId": "integer",
                        "taskId": "integer",
                        "branchName": "string"
                    ],
                    nonBlank: ["branchName"]
                ),
                permissionLevel: .writeWithApproval
            ) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(
                    tool: .developmentPreparePullRequestWorkflow,
                    status: .succeeded,
                    summary: "Prepared local development branch \(branchName). Push and PR creation require a separate approval gate.",
                    output: [
                        "projectId": .number(7),
                        "taskId": .number(42),
                        "branchName": .string(branchName),
                        "status": .string("## \(branchName)\n"),
                        "diffStat": .string("README.md | 1 +"),
                        "requiresPushApproval": .bool(true),
                        "requiresPullRequestApproval": .bool(true)
                    ]
                )
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(
                    id: "development-pr",
                    tool: .developmentPreparePullRequestWorkflow,
                    arguments: [
                        "projectId": .number(7),
                        "taskId": .number(42),
                        "branchName": .string(branchName)
                    ],
                    riskLevel: .write
                )
            ]),
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore
        )

        try viewModel.approve()
        try viewModel.execute()

        let receipt = try XCTUnwrap(viewModel.lastExecutionReceipt)
        XCTAssertEqual(receiptStore.receipts, [receipt])
        XCTAssertEqual(receipt.actions.first?.toolName, ActionTool.developmentPreparePullRequestWorkflow.rawValue)
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .developmentBranch, id: branchName)))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .task, id: "42")))
        XCTAssertTrue(receipt.references.contains(ExecutionReceiptReference(kind: .project, id: "7")))
        XCTAssertEqual(receipt.visibleSurfaces, [.taskDetail, .projectDetail, .auditLog])
    }

    func testApproveOrReportErrorSurfacesDisabledApprovalFailure() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "read", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry)
        )

        XCTAssertFalse(viewModel.canApprove)

        XCTAssertFalse(viewModel.approveOrReportError())
        XCTAssertEqual(viewModel.errorMessage, "This action plan does not require approval.")
    }

    func testExecuteOrReportErrorSurfacesApprovalPreflightFailure() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"]), permissionLevel: .writeWithApproval) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry)
        )

        XCTAssertFalse(viewModel.executeOrReportError())
        XCTAssertEqual(viewModel.errorMessage, "Approve this action plan before executing it.")
        XCTAssertEqual(viewModel.session.executionStatus, .notStarted)
    }

    func testExecuteOrReportErrorClearsStaleActionErrorOnSuccess() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "read", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry)
        )

        XCTAssertFalse(viewModel.approveOrReportError())
        XCTAssertEqual(viewModel.errorMessage, "This action plan does not require approval.")

        XCTAssertTrue(viewModel.executeOrReportError())
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.session.executionStatus, .completed)
    }

    func testFailedToolExecutionCreatesRedactedExecutionReceipt() throws {
        let receiptStore = VolatileExecutionReceiptStore()
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"]), permissionLevel: .writeWithApproval) { _, _ in
                throw ToolExecutionError.executionFailed(.taskCreate, "provider failed \("token" + "=" + "tool-secret")")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry),
            executionReceiptStore: receiptStore
        )

        try viewModel.approve()
        try viewModel.execute()

        let receipt = try XCTUnwrap(viewModel.lastExecutionReceipt)
        XCTAssertEqual(receipt.status, .failed)
        XCTAssertEqual(receipt.actions.first?.status, .failed)
        XCTAssertTrue(receipt.actions.first?.errorSummary?.contains("[REDACTED_SECRET]") ?? false)
        XCTAssertFalse(receipt.actions.first?.errorSummary?.contains("tool-secret") ?? true)
        XCTAssertEqual(receiptStore.receipts, [receipt])
    }

    func testCancelSessionRecordsAuditEventAndDisablesExecution() throws {
        let logger = InMemoryAuditLogger()
        let receiptStore = VolatileExecutionReceiptStore()
        let registry = ToolRegistry()
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry),
            auditLogger: logger,
            executionReceiptStore: receiptStore
        )

        viewModel.cancel()

        XCTAssertEqual(viewModel.session.executionStatus, .canceled)
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertTrue(logger.recordedEvents.contains { $0.action == "session.cancel" })
        XCTAssertEqual(viewModel.lastExecutionReceipt?.status, .canceled)
        XCTAssertEqual(receiptStore.receipts, viewModel.executionReceipts)
    }

    func testInvalidEditDisablesExecutionAndReportsValidationIssue() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]), permissionLevel: .writeWithApproval) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry)
        )

        viewModel.updateStringArgument(actionID: "task", key: "title", value: "   ")
        try viewModel.approve()

        XCTAssertFalse(viewModel.canExecute)
        XCTAssertEqual(viewModel.validationIssues(for: "task").first?.field, "title")
        XCTAssertThrowsError(try viewModel.execute())
    }

    func testPermissionDeniedActionIsDisabledWithSettingsGuidance() throws {
        var permissions = PermissionSnapshot.empty
        permissions.setStatus(.denied, for: .notifications)
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .notificationSchedule, description: "notify", inputSchema: ToolInputSchema(required: ["title", "scheduledAt"], properties: ["title": "string", "scheduledAt": "string"]), permissionLevel: .writeWithApproval) { _, _ in
                ToolResult(tool: .notificationSchedule, status: .succeeded, summary: "scheduled")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(
                    id: "notify",
                    tool: .notificationSchedule,
                    arguments: [
                        "title": .string("Standup"),
                        "scheduledAt": .string("2026-06-18T09:00:00Z")
                    ]
                )
            ]),
            executor: ActionExecutor(registry: registry),
            permissionGate: ReviewPermissionGate(permissionSnapshot: permissions)
        )

        try viewModel.approve()

        XCTAssertFalse(viewModel.canExecute)
        XCTAssertEqual(viewModel.validationIssues(for: "notify").first?.field, "permission")
        XCTAssertTrue(viewModel.validationIssues(for: "notify").first?.message.contains("Open Settings") == true)
    }

    func testRuntimeValidationMessageDisablesExecutionBeforeUnknownToolFailure() throws {
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]), permissionLevel: .writeWithApproval) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry),
            runtimeValidationMessage: "Review execution tools are unavailable."
        )

        try viewModel.approve()

        XCTAssertEqual(viewModel.errorMessage, "Review execution tools are unavailable.")
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertEqual(viewModel.validationIssues(for: "task").first?.field, "runtime")
        XCTAssertEqual(viewModel.validationIssues(for: "task").first?.message, "Review execution tools are unavailable.")
        XCTAssertThrowsError(try viewModel.execute())
    }

    func testAuditFailureDuringEditIsSurfacedInsteadOfDropped() throws {
        let auditLogger = SequencedFailingAuditLogger(failOnCall: 2)
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"], properties: ["title": "string"]), permissionLevel: .writeWithApproval) { _, _ in
                ToolResult(tool: .taskCreate, status: .succeeded, summary: "created")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry),
            auditLogger: auditLogger
        )

        XCTAssertNil(viewModel.auditErrorMessage)

        viewModel.updateStringArgument(actionID: "task", key: "title", value: "Review")

        XCTAssertEqual(viewModel.auditErrorMessage, "Review audit log could not be saved.")
    }

    func testAuditFailureDuringExecuteFailureIsSurfacedWithExecutorError() throws {
        let viewAuditLogger = SequencedFailingAuditLogger(failOnCall: 2)
        let executorAuditLogger = SequencedFailingAuditLogger(failOnCall: 1)
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "read", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry, auditLogger: executorAuditLogger),
            auditLogger: viewAuditLogger
        )

        XCTAssertThrowsError(try viewModel.execute())

        XCTAssertEqual(viewModel.errorMessage, "Review execution could not be completed.")
        XCTAssertEqual(viewModel.auditErrorMessage, "Review audit log could not be saved.")
    }

    func testExecutorAuditFailureAfterToolSuccessIsSurfacedWithoutLosingSessionResult() throws {
        let executorAuditLogger = SequencedFailingAuditLogger(failOnCall: 2)
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .projectList, description: "read", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .projectList, status: .succeeded, summary: "ok")
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry, auditLogger: executorAuditLogger),
            auditLogger: InMemoryAuditLogger()
        )

        try viewModel.execute()

        XCTAssertEqual(viewModel.session.executionStatus, .completed)
        XCTAssertEqual(viewModel.session.items.first?.executionStatus, .succeeded)
        XCTAssertEqual(viewModel.session.items.first?.result?.summary, "ok")
        XCTAssertEqual(viewModel.auditErrorMessage, "Action audit log could not be saved.")
    }

    func testBlankOptionalCRUDFieldDisablesExecutionBeforeApproval() throws {
        let stores = try makeStores()
        let task = try stores.tasks.create(title: "Draft release notes")
        let registry = try ToolRegistry.phase2Core(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            knowledgeStore: stores.knowledge
        )
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(
                    id: "task",
                    tool: .taskUpdate,
                    arguments: [
                        "id": .number(Double(task.id)),
                        "title": .string("   ")
                    ]
                )
            ]),
            executor: ActionExecutor(registry: registry)
        )

        XCTAssertEqual(viewModel.validationIssues(for: "task").first?.field, "title")
        XCTAssertEqual(
            viewModel.validationIssues(for: "task").first?.message,
            "Argument 'title' cannot be blank for task.update."
        )
        try viewModel.approve()
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertThrowsError(try viewModel.execute())
    }

    func testBlankBulkTaskTitleDisablesExecutionBeforeApproval() throws {
        let stores = try makeStores()
        let registry = try ToolRegistry.phase2Core(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            knowledgeStore: stores.knowledge
        )
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(
                    id: "bulk",
                    tool: .taskBulkCreate,
                    arguments: [
                        "tasks": .array([
                            .object(["title": .string("Draft release notes")]),
                            .object(["title": .string("   ")])
                        ])
                    ]
                )
            ]),
            executor: ActionExecutor(registry: registry)
        )

        XCTAssertEqual(viewModel.validationIssues(for: "bulk").first?.field, "tasks[1].title")
        XCTAssertEqual(
            viewModel.validationIssues(for: "bulk").first?.message,
            "Missing required argument 'tasks[1].title' for task.bulk_create."
        )
        try viewModel.approve()
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertThrowsError(try viewModel.execute())
        XCTAssertEqual(try stores.tasks.listAll(), [])
    }

    func testFakeVoiceToReviewToExecuteFlow() async throws {
        let plan = ActionPlan.reviewViewModelFixture(actions: [
            PlanAction(id: "project", tool: .projectCreate, arguments: ["title": .string("QZT Article")]),
            PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Publish draft")])
        ])
        let voiceViewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: plan,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        voiceViewModel.updateDraftText("Create a task for QZT article publish checklist")
        await voiceViewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        let generatedPlan = try XCTUnwrap(voiceViewModel.planningResponse?.actionPlan)
        let auditLogger = InMemoryAuditLogger()
        let registry = try ToolRegistryTestFactory.inMemoryPhase2MVP(
            workspaceRoot: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true),
            auditLogger: auditLogger
        )
        let reviewViewModel = ReviewSessionViewModel(
            plan: generatedPlan,
            executor: ActionExecutor(registry: registry, auditLogger: auditLogger),
            auditLogger: auditLogger
        )

        try reviewViewModel.approve()
        try reviewViewModel.execute()

        XCTAssertEqual(voiceViewModel.phase, .reviewReady)
        XCTAssertEqual(reviewViewModel.session.executionStatus, .completed)
        XCTAssertEqual(reviewViewModel.session.items.map(\.executionStatus), [.succeeded, .succeeded])
    }
}

private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, knowledge: SQLiteKnowledgeFrameStore) {
    let connection = try SQLiteConnection(path: ":memory:")
    try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
    return (
        SQLiteProjectStore(connection: connection),
        SQLiteTaskStore(connection: connection),
        SQLiteKnowledgeFrameStore(connection: connection)
    )
}

private enum ReviewAuditTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "unavailable"
    }
}

private final class SequencedFailingAuditLogger: AuditLogger, @unchecked Sendable {
    private let failOnCall: Int
    private var callCount = 0
    private let lock = NSLock()

    init(failOnCall: Int) {
        self.failOnCall = failOnCall
    }

    func record(_ event: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        if callCount >= failOnCall {
            throw ReviewAuditTestError.unavailable
        }
    }
}

private extension ActionPlan {
    static func reviewViewModelFixture(actions: [PlanAction]) -> ActionPlan {
        ActionPlan(
            id: "plan-review-vm",
            userInput: "Review fixture",
            summary: "Review fixture",
            actions: actions,
            riskLevel: actions.map(\.riskLevel).max() ?? .read,
            requiresApproval: actions.contains { $0.riskLevel >= .write }
        )
    }
}
