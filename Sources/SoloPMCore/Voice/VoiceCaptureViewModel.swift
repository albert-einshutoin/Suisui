import Combine
import Foundation

public enum VoiceCapturePhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case generatingPlan
    case reviewReady
    case failed(String)
}

@MainActor
public final class VoiceCaptureViewModel: ObservableObject {
    @Published public private(set) var draft: TranscriptDraft
    @Published public private(set) var phase: VoiceCapturePhase
    @Published public private(set) var recordingState: AudioRecordingState
    @Published public private(set) var planningResponse: PlanningResponse?
    @Published public private(set) var recordedAudio: RecordedAudio?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?

    public init(
        draft: TranscriptDraft = TranscriptDraft(),
        phase: VoiceCapturePhase = .idle,
        audioRecorder: any AudioRecorder = FakeAudioRecorder(),
        sttProvider: any SpeechToTextProvider = FakeSTTProvider(transcript: STTTranscript(text: "")),
        llmProvider: any LLMProvider,
        auditRecorder: PlanningAuditRecorder? = nil
    ) {
        self.draft = draft
        self.phase = phase
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.llmProvider = llmProvider
        self.auditRecorder = auditRecorder
        self.recordingState = audioRecorder.state
    }

    public var canGeneratePlan: Bool {
        draft.canGeneratePlan && phase != .generatingPlan && phase != .recording && phase != .transcribing
    }

    public var isRecording: Bool {
        if case .recording = phase {
            return true
        }
        return false
    }

    public func updateDraftText(_ text: String) {
        draft.text = text
        if case .failed = phase {
            phase = .idle
        }
    }

    public func clear() {
        draft = TranscriptDraft()
        planningResponse = nil
        recordedAudio = nil
        phase = .idle
    }

    public func startRecording(at date: Date = Date()) {
        do {
            try audioRecorder.start(at: date)
            recordingState = audioRecorder.state
            phase = .recording
        } catch {
            recordingState = audioRecorder.state
            phase = .failed(String(describing: error))
        }
    }

    public func stopRecording(outputURL: URL, at date: Date = Date()) async {
        do {
            phase = .transcribing
            let audio = try audioRecorder.stop(outputURL: outputURL, at: date)
            recordingState = audioRecorder.state
            recordedAudio = audio
            let transcript = try await sttProvider.transcribe(audio)
            draft = TranscriptDraft(text: transcript.text)
            phase = .idle
        } catch {
            recordingState = audioRecorder.state
            phase = .failed(String(describing: error))
        }
    }

    public func generatePlan(
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        availableTools: [ActionTool] = ActionTool.allCases,
        knowledgeFrameCandidates: [KnowledgeFrameCandidate] = []
    ) async {
        guard draft.canGeneratePlan else {
            phase = .failed("Transcript is empty.")
            return
        }

        let request = PlanningRequest(
            userInput: draft.normalizedText,
            currentDate: currentDate,
            timeZoneIdentifier: timeZoneIdentifier,
            availableTools: availableTools,
            knowledgeFrameCandidates: knowledgeFrameCandidates
        )

        phase = .generatingPlan

        do {
            try auditRecorder?.recordStarted(input: request.userInput, providerID: llmProvider.providerID)
            let response = try await llmProvider.generatePlan(for: request)
            planningResponse = response
            try auditRecorder?.recordCompleted(response: response)
            phase = response.validationResult.isValid ? .reviewReady : .failed("ActionPlan validation failed.")
        } catch {
            try? auditRecorder?.recordFailed(input: request.userInput, providerID: llmProvider.providerID, error: error)
            phase = .failed(String(describing: error))
        }
    }
}
