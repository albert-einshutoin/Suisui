import XCTest
@testable import SuisuiCore

/// T-10: a failed voice plan generation must carry a typed next-step
/// affordance (Open Settings for provider readiness, Try Again for transient
/// provider problems) instead of only a message string.
@MainActor
final class VoiceFailureRecoveryTests: XCTestCase {
    func testAuthenticationFailureOffersOpenSettingsRecovery() async {
        let viewModel = makeViewModel(provider: ThrowingVoiceLLMProvider(error: .authenticationFailed))

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        guard case .failed = viewModel.phase else {
            return XCTFail("Expected failed phase, got \(viewModel.phase)")
        }
        XCTAssertEqual(viewModel.failureRecovery, .openSettings)
    }

    func testExecutionNotApprovedFailureOffersOpenSettingsRecovery() async {
        let viewModel = makeViewModel(
            provider: ThrowingVoiceLLMProvider(error: .executionNotApproved("Approve local execution in Settings."))
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.failureRecovery, .openSettings)
    }

    func testNetworkAndRateLimitFailuresOfferRetryRecovery() async {
        for error in [LLMProviderError.network("offline"), .rateLimited] {
            let viewModel = makeViewModel(provider: ThrowingVoiceLLMProvider(error: error))

            viewModel.updateDraftText("Create a task")
            await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

            guard case .failed = viewModel.phase else {
                return XCTFail("Expected failed phase for \(error), got \(viewModel.phase)")
            }
            XCTAssertEqual(viewModel.failureRecovery, .retryPlanGeneration, "for \(error)")
        }
    }

    func testInvalidResponseFailureHasNoRecoveryAffordance() async {
        let viewModel = makeViewModel(provider: ThrowingVoiceLLMProvider(error: .invalidResponse("bad JSON")))

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        guard case .failed = viewModel.phase else {
            return XCTFail("Expected failed phase, got \(viewModel.phase)")
        }
        XCTAssertNil(viewModel.failureRecovery)
    }

    func testEditingDraftClearsFailureRecovery() async {
        let viewModel = makeViewModel(provider: ThrowingVoiceLLMProvider(error: .authenticationFailed))

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertEqual(viewModel.failureRecovery, .openSettings)

        viewModel.updateDraftText("Create another task")

        XCTAssertNil(viewModel.failureRecovery)
    }

    func testClearResetsFailureRecovery() async {
        let viewModel = makeViewModel(provider: ThrowingVoiceLLMProvider(error: .network("offline")))

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertEqual(viewModel.failureRecovery, .retryPlanGeneration)

        viewModel.clear()

        XCTAssertNil(viewModel.failureRecovery)
    }

    func testRetryWithSameTranscriptSucceedsAfterTransientFailure() async {
        let provider = FlakyVoiceLLMProvider(
            failures: [.network("offline")],
            response: makePlanningResponse()
        )
        let viewModel = makeViewModel(provider: provider)

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertEqual(viewModel.failureRecovery, .retryPlanGeneration)

        // The UI retry button re-invokes generatePlan() with the unchanged draft.
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertNil(viewModel.failureRecovery)
        XCTAssertEqual(provider.requestCount, 2)
    }

    private func makeViewModel(provider: any LLMProvider) -> VoiceCaptureViewModel {
        VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )
    }

    private func makePlanningResponse() -> PlanningResponse {
        PlanningResponse(
            providerID: "flaky",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-retry-1",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
    }
}

private struct ThrowingVoiceLLMProvider: LLMProvider {
    var providerID: String = "throwing"
    var error: LLMProviderError

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        throw error
    }
}

private final class FlakyVoiceLLMProvider: LLMProvider, @unchecked Sendable {
    let providerID = "flaky"
    private let lock = NSLock()
    private var failures: [LLMProviderError]
    private let response: PlanningResponse
    private var recordedRequestCount = 0

    init(failures: [LLMProviderError], response: PlanningResponse) {
        self.failures = failures
        self.response = response
    }

    var requestCount: Int {
        lock.withLock { recordedRequestCount }
    }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        try lock.withLock {
            recordedRequestCount += 1
            guard failures.isEmpty else {
                throw failures.removeFirst()
            }
            return response
        }
    }
}
