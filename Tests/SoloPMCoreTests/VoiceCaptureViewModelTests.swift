import XCTest
@testable import SoloPMCore

@MainActor
final class VoiceCaptureViewModelTests: XCTestCase {
    func testGeneratePlanUsesDraftTextAndMovesToReviewReady() async {
        let logger = InMemoryAuditLogger()
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-1",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            auditRecorder: PlanningAuditRecorder(logger: logger)
        )

        viewModel.updateDraftText(" Create a task ")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-1")
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
    }

    func testGeneratePlanSurfacesCompletionAuditFailureWithoutLosingPlan() async {
        let logger = SequencedVoiceAuditLogger(failOnCall: 2)
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-1",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            auditRecorder: PlanningAuditRecorder(logger: logger)
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-1")
        XCTAssertEqual(viewModel.auditErrorMessage, "Planning audit log failed: unavailable")
    }

    func testPlanningAuditFailureRedactsSecretContext() async {
        let secret = "sk-" + "voiceAuditSecret123"
        let logger = ThrowingVoiceAuditLogger(
            error: SecretVoiceTestError(message: "audit failed token=\(secret)&request_id=voice-audit-1")
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            auditRecorder: PlanningAuditRecorder(logger: logger)
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(
            viewModel.auditErrorMessage,
            "Planning audit log failed: audit failed token=[REDACTED_SECRET]&request_id=voice-audit-1"
        )
        XCTAssertFalse(viewModel.auditErrorMessage?.contains(secret) ?? true)
    }

    func testGeneratePlanRedactsUnexpectedProviderErrorMessage() async {
        let secret = "sk-" + "voiceProviderSecret123"
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: ThrowingVoiceLLMProvider(
                error: SecretVoiceTestError(message: "planner failed token=\(secret)&request_id=voice-provider-1")
            )
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(
            viewModel.phase,
            .failed("planner failed token=[REDACTED_SECRET]&request_id=voice-provider-1")
        )
        if case .failed(let message) = viewModel.phase {
            XCTAssertFalse(message.contains(secret))
        } else {
            XCTFail("Expected failed phase.")
        }
    }

    func testRuntimeValidationMessageBlocksPlanGenerationUntilRuntimeIsFixed() async {
        let message = "Voice planning is unavailable because audit logging or local data stores could not be opened."
        let viewModel = VoiceCaptureViewModel(
            phase: .failed(message),
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            runtimeValidationMessage: message
        )

        viewModel.updateDraftText("Create a task")

        XCTAssertFalse(viewModel.canGeneratePlan)
        XCTAssertEqual(viewModel.phase, .failed(message))

        await viewModel.generatePlan()

        XCTAssertNil(viewModel.planningResponse)
        XCTAssertEqual(viewModel.phase, .failed(message))

        viewModel.clear()

        XCTAssertEqual(viewModel.phase, .failed(message))
    }

    func testRecordingFlowTranscribesIntoDraft() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(viewModel.phase, .recording)

        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/solopm-test.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.draft.text, "Create a task")
        XCTAssertEqual(viewModel.recordedAudio?.duration, 2)
    }

    func testCanRecordAgainAfterSuccessfulTranscription() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/solopm-test-first.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        viewModel.startRecording(at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(viewModel.phase, .recording)
        XCTAssertEqual(viewModel.recordingState, .recording(startedAt: Date(timeIntervalSince1970: 20)))
    }

    func testClearResetsActiveRecordingState() {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        viewModel.clear()
        viewModel.startRecording(at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(viewModel.phase, .recording)
        XCTAssertEqual(viewModel.recordingState, .recording(startedAt: Date(timeIntervalSince1970: 20)))
    }

    func testGeneratePlanRejectsEmptyDraft() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.generatePlan()

        XCTAssertEqual(viewModel.phase, .failed("Transcript is empty."))
    }
}

private enum VoiceAuditTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "unavailable"
    }
}

private struct SecretVoiceTestError: Error, CustomStringConvertible {
    var message: String

    var description: String {
        message
    }
}

private struct ThrowingVoiceLLMProvider: LLMProvider {
    var providerID: String = "throwing"
    var error: Error

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        throw error
    }
}

private final class ThrowingVoiceAuditLogger: AuditLogger, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func record(_ event: AuditEvent) throws {
        throw error
    }
}

private final class SequencedVoiceAuditLogger: AuditLogger, @unchecked Sendable {
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
            throw VoiceAuditTestError.unavailable
        }
    }
}
