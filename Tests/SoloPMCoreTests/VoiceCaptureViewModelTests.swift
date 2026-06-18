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
