import XCTest
@testable import SoloPMCore

@MainActor
final class ReviewSessionViewModelTests: XCTestCase {
    func testApproveEditAndExecuteSession() throws {
        let logger = InMemoryAuditLogger()
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
            auditLogger: logger
        )

        viewModel.updateStringArgument(actionID: "task", key: "title", value: "Review")
        try viewModel.approve()
        try viewModel.execute()

        XCTAssertEqual(viewModel.session.items.first?.editedAction.arguments["title"], .string("Review"))
        XCTAssertEqual(viewModel.session.executionStatus, .completed)
        XCTAssertEqual(viewModel.session.items.first?.result?.rollbackMetadata["taskId"], .number(1))
        XCTAssertTrue(logger.recordedEvents.contains { $0.action == "session.approve" })
    }

    func testCancelSessionRecordsAuditEventAndDisablesExecution() throws {
        let logger = InMemoryAuditLogger()
        let registry = ToolRegistry()
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry),
            auditLogger: logger
        )

        viewModel.cancel()

        XCTAssertEqual(viewModel.session.executionStatus, .canceled)
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertTrue(logger.recordedEvents.contains { $0.action == "session.cancel" })
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

        voiceViewModel.updateDraftText("QZT article publish checklist")
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
