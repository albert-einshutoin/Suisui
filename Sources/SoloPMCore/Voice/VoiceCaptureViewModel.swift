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
    @Published public private(set) var auditErrorMessage: String?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?
    private let runtimeValidationMessage: String?

    public init(
        draft: TranscriptDraft = TranscriptDraft(),
        phase: VoiceCapturePhase = .idle,
        audioRecorder: any AudioRecorder,
        sttProvider: any SpeechToTextProvider,
        llmProvider: any LLMProvider,
        auditRecorder: PlanningAuditRecorder? = nil,
        runtimeValidationMessage: String? = nil
    ) {
        self.draft = draft
        self.phase = phase
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.llmProvider = llmProvider
        self.auditRecorder = auditRecorder
        self.runtimeValidationMessage = runtimeValidationMessage
        self.recordingState = audioRecorder.state
        self.auditErrorMessage = nil
    }

    public var canGeneratePlan: Bool {
        runtimeValidationMessage == nil
            && draft.canGeneratePlan
            && phase != .generatingPlan
            && phase != .recording
            && phase != .transcribing
    }

    public var isRecording: Bool {
        if case .recording = phase {
            return true
        }
        return false
    }

    public func updateDraftText(_ text: String) {
        draft.text = text
        if case .failed = phase, runtimeValidationMessage == nil {
            phase = .idle
        }
    }

    public func clear() {
        audioRecorder.reset()
        draft = TranscriptDraft()
        planningResponse = nil
        recordedAudio = nil
        auditErrorMessage = nil
        recordingState = audioRecorder.state
        phase = runtimeValidationMessage.map(VoiceCapturePhase.failed) ?? .idle
    }

    public func startRecording(at date: Date = Date()) {
        do {
            try audioRecorder.start(at: date)
            recordingState = audioRecorder.state
            phase = .recording
        } catch {
            recordingState = audioRecorder.state
            phase = .failed(userMessage(for: error))
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
            phase = .failed(userMessage(for: error))
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

        if let runtimeValidationMessage {
            phase = .failed(runtimeValidationMessage)
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
        auditErrorMessage = nil

        do {
            try auditRecorder?.recordStarted(input: request.userInput, providerID: llmProvider.providerID)
        } catch {
            phase = .failed(userMessage(for: error))
            capturePlanningAuditFailure(error)
            return
        }

        do {
            let response = try await llmProvider.generatePlan(for: request)
            planningResponse = response
            recordPlanningAudit {
                try auditRecorder?.recordCompleted(response: response)
            }
            phase = response.validationResult.isValid ? .reviewReady : .failed("ActionPlan validation failed.")
        } catch {
            recordPlanningAudit {
                try auditRecorder?.recordFailed(input: request.userInput, providerID: llmProvider.providerID, error: error)
            }
            phase = .failed(userMessage(for: error))
        }
    }

    private func recordPlanningAudit(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            capturePlanningAuditFailure(error)
        }
    }

    private func capturePlanningAuditFailure(_ error: Error) {
        auditErrorMessage = "Planning audit log failed: \(String(describing: error))"
    }

    private func userMessage(for error: Error) -> String {
        if let audioError = error as? AudioRecorderError {
            switch audioError {
            case .microphonePermissionDenied:
                return "Microphone permission is required to record."
            case .alreadyRecording:
                return "Recording is already in progress."
            case .notRecording:
                return "Recording has not started."
            case .failed(let message):
                return message
            }
        }

        if let sttError = error as? STTProviderError {
            switch sttError {
            case .unavailable(let message):
                return message
            case .permissionDenied:
                return "Speech transcription permission is required."
            case .modelMissing(let message), .transcriptionFailed(let message):
                return message
            }
        }

        return String(describing: error)
    }
}
