import XCTest
@testable import SoloPMCore

@MainActor
final class LowRiskAutoCreationTests: XCTestCase {
    // MARK: - Policy matrix

    func testQualifiesForSingleValidTaskCreateAtWriteRiskWithModeOn() {
        XCTAssertTrue(
            LowRiskAutoCreationPolicy.qualifies(
                plan: makeQualifyingPlan(),
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings()
            )
        )
    }

    func testDoesNotQualifyWhenAutomationDisabled() {
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: makeQualifyingPlan(),
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings(isEnabled: false)
            )
        )
    }

    func testDoesNotQualifyInReviewOnlyMode() {
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: makeQualifyingPlan(),
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings(mode: .reviewOnly)
            )
        )
    }

    func testDoesNotQualifyWithTwoActions() {
        let plan = makePlan(actions: [
            PlanAction(id: "a1", tool: .taskCreate, arguments: ["title": .string("One")]),
            PlanAction(id: "a2", tool: .taskCreate, arguments: ["title": .string("Two")])
        ])
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: plan,
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings()
            )
        )
    }

    func testDoesNotQualifyForNonTaskCreateAction() {
        let plan = makePlan(actions: [
            PlanAction(id: "a1", tool: .taskUpdate, arguments: ["id": .number(1), "status": .string("open")])
        ])
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: plan,
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings()
            )
        )
    }

    func testDoesNotQualifyAtDangerRisk() {
        let dangerAction = makePlan(
            actions: [
                PlanAction(id: "a1", tool: .taskCreate, arguments: ["title": .string("One")], riskLevel: .danger)
            ],
            riskLevel: .danger
        )
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: dangerAction,
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings()
            )
        )

        let dangerPlan = makePlan(
            actions: [
                PlanAction(id: "a1", tool: .taskCreate, arguments: ["title": .string("One")])
            ],
            riskLevel: .danger
        )
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: dangerPlan,
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings()
            )
        )
    }

    func testDoesNotQualifyWhenActionRequiresUserConfirmation() {
        let plan = makePlan(actions: [
            PlanAction(
                id: "a1",
                tool: .taskCreate,
                arguments: ["title": .string("One")],
                requiresUserConfirmation: true
            )
        ])
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: plan,
                validation: ActionPlanValidationResult(issues: []),
                settings: autoCreateSettings()
            )
        )
    }

    func testDoesNotQualifyWhenValidationHasBlockingIssue() {
        XCTAssertFalse(
            LowRiskAutoCreationPolicy.qualifies(
                plan: makeQualifyingPlan(),
                validation: ActionPlanValidationResult(issues: [
                    .blocking(path: "actions[0].arguments.title", message: "title is required.")
                ]),
                settings: autoCreateSettings()
            )
        )
    }

    func testQualifiesDespiteValidationWarnings() {
        XCTAssertTrue(
            LowRiskAutoCreationPolicy.qualifies(
                plan: makeQualifyingPlan(),
                validation: ActionPlanValidationResult(issues: [
                    .warning(path: "actions[0]", message: "Ambiguous date.")
                ]),
                settings: autoCreateSettings()
            )
        )
    }

    // MARK: - View model integration

    func testQualifyingPlanAutoCreatesTaskAndKeepsReviewReadyPhase() async {
        let recorder = AutoCreateExecutionRecorder()
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(),
            executor: { plan in
                recorder.recordExecution(plan)
                return LowRiskAutoCreationOutcome(
                    taskID: 42,
                    taskTitle: "Buy stamps",
                    summaryMessage: "Created task Buy stamps"
                )
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(recorder.executedPlans.map(\.id), ["plan-auto"])
        XCTAssertEqual(viewModel.autoCreatedTask, AutoCreatedTaskRecord(taskID: 42, title: "Buy stamps"))
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-auto")
    }

    func testReviewOnlyModeNeverCallsExecutor() async {
        let recorder = AutoCreateExecutionRecorder()
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(mode: .reviewOnly),
            executor: { plan in
                recorder.recordExecution(plan)
                return LowRiskAutoCreationOutcome(taskID: 42, taskTitle: "Buy stamps", summaryMessage: "Created")
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertTrue(recorder.executedPlans.isEmpty)
        XCTAssertNil(viewModel.autoCreatedTask)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testExecutorFailureFallsBackToManualReviewWithoutFailingPlan() async {
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(),
            executor: { _ in
                throw LowRiskAutoCreationError.executionFailed("Registry unavailable.")
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertNil(viewModel.autoCreatedTask)
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-auto")
    }

    func testOutcomeWithoutTaskIDDoesNotPublishUndoableRecord() async {
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(),
            executor: { _ in
                LowRiskAutoCreationOutcome(taskID: nil, taskTitle: "Buy stamps", summaryMessage: "Created")
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertNil(viewModel.autoCreatedTask)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testUndoAutoCreatedTaskCallsDeleterAndClearsRecord() async {
        let recorder = AutoCreateExecutionRecorder()
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(),
            executor: { _ in
                LowRiskAutoCreationOutcome(taskID: 7, taskTitle: "Buy stamps", summaryMessage: "Created")
            },
            taskDeleter: { taskID in
                recorder.recordDeletion(taskID)
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertNotNil(viewModel.autoCreatedTask)

        viewModel.undoAutoCreatedTask()

        XCTAssertEqual(recorder.deletedTaskIDs, [7])
        XCTAssertNil(viewModel.autoCreatedTask)
        XCTAssertNil(viewModel.auditErrorMessage)
    }

    func testUndoFailureKeepsRecordAndSurfacesErrorMessage() async {
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(),
            executor: { _ in
                LowRiskAutoCreationOutcome(taskID: 7, taskTitle: "Buy stamps", summaryMessage: "Created")
            },
            taskDeleter: { _ in
                throw ToolExecutionError.executionFailed(.taskDelete, "Task not found.")
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertNotNil(viewModel.autoCreatedTask)

        viewModel.undoAutoCreatedTask()

        XCTAssertEqual(viewModel.autoCreatedTask, AutoCreatedTaskRecord(taskID: 7, title: "Buy stamps"))
        XCTAssertNotNil(viewModel.auditErrorMessage)
    }

    func testUpdatingDraftTextClearsAutoCreatedBanner() async {
        let viewModel = makeViewModel(
            response: makeResponse(plan: makeQualifyingPlan()),
            settings: autoCreateSettings(),
            executor: { _ in
                LowRiskAutoCreationOutcome(taskID: 7, taskTitle: "Buy stamps", summaryMessage: "Created")
            }
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertNotNil(viewModel.autoCreatedTask)

        viewModel.updateDraftText("Something new")

        XCTAssertNil(viewModel.autoCreatedTask)
    }

    // MARK: - Settings round trip

    func testTaskAutoExecutionSettingsRoundTripWithAutoCreateMode() throws {
        let settings = TaskAutoExecutionSettings(
            isEnabled: true,
            mode: .autoCreateLowRisk,
            cadence: .daily,
            maxTasksPerRun: 4,
            dailyLLMCallLimit: 8,
            lookaheadHours: 24,
            urgentReviewCooldownMinutes: 30
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.mode, .autoCreateLowRisk)
    }

    func testLegacyReviewOnlySettingsStillDecode() throws {
        let legacyJSON = """
        {"isEnabled":true,"mode":"reviewOnly","cadence":"manual","maxTasksPerRun":3,"dailyLLMCallLimit":6,"lookaheadHours":48}
        """
        let decoded = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.mode, .reviewOnly)
        XCTAssertEqual(decoded.urgentReviewCooldownMinutes, 60)
    }

    func testModeLabels() {
        XCTAssertEqual(TaskAutoExecutionMode.reviewOnly.label, "Review before execution")
        XCTAssertEqual(TaskAutoExecutionMode.autoCreateLowRisk.label, "Auto-create low-risk tasks")
        XCTAssertEqual(TaskAutoExecutionMode.allCases, [.reviewOnly, .autoCreateLowRisk])
    }

    // MARK: - Fixtures

    private func makeQualifyingPlan() -> ActionPlan {
        makePlan(actions: [
            PlanAction(id: "a1", tool: .taskCreate, arguments: ["title": .string("Buy stamps")])
        ])
    }

    private func makePlan(actions: [PlanAction], riskLevel: RiskLevel = .write) -> ActionPlan {
        ActionPlan(
            id: "plan-auto",
            userInput: "Buy stamps tomorrow",
            summary: "Create one task",
            actions: actions,
            riskLevel: riskLevel,
            requiresApproval: true
        )
    }

    private func autoCreateSettings(
        isEnabled: Bool = true,
        mode: TaskAutoExecutionMode = .autoCreateLowRisk
    ) -> TaskAutoExecutionSettings {
        TaskAutoExecutionSettings(isEnabled: isEnabled, mode: mode)
    }

    private func makeResponse(plan: ActionPlan) -> PlanningResponse {
        PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: plan,
            validationResult: ActionPlanValidationResult(issues: [])
        )
    }

    private func makeViewModel(
        response: PlanningResponse,
        settings: TaskAutoExecutionSettings,
        executor: @escaping @Sendable (ActionPlan) async throws -> LowRiskAutoCreationOutcome,
        taskDeleter: (@Sendable (Int64) throws -> Void)? = nil
    ) -> VoiceCaptureViewModel {
        VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            taskAutomationSettingsProvider: { settings },
            lowRiskTaskAutoExecutor: executor,
            taskDeleter: taskDeleter
        )
    }
}

private final class AutoCreateExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [ActionPlan] = []
    private var deletions: [Int64] = []

    func recordExecution(_ plan: ActionPlan) {
        lock.lock()
        defer { lock.unlock() }
        plans.append(plan)
    }

    func recordDeletion(_ taskID: Int64) {
        lock.lock()
        defer { lock.unlock() }
        deletions.append(taskID)
    }

    var executedPlans: [ActionPlan] {
        lock.lock()
        defer { lock.unlock() }
        return plans
    }

    var deletedTaskIDs: [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return deletions
    }
}
