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

private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, knowledge: SQLiteKnowledgeFrameStore) {
    let connection = try SQLiteConnection(path: ":memory:")
    try ReviewTestMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
    return (
        SQLiteProjectStore(connection: connection),
        SQLiteTaskStore(connection: connection),
        SQLiteKnowledgeFrameStore(connection: connection)
    )
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

private enum ReviewTestMigrationRunner {
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
