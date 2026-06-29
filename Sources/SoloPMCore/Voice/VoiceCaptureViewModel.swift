import Combine
import Foundation

public enum VoiceCapturePhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case needsClarification(String)
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
    @Published public private(set) var routingResult: VoiceCommandRoutingResult?
    @Published public private(set) var clarificationSession: ClarificationSession?
    @Published public private(set) var assistantQueueItem: AssistantQueueItem?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?
    private let runtimeValidationMessage: String?
    private let commandRouter: any VoiceCommandRouting

    public init(
        draft: TranscriptDraft = TranscriptDraft(),
        phase: VoiceCapturePhase = .idle,
        audioRecorder: any AudioRecorder,
        sttProvider: any SpeechToTextProvider,
        llmProvider: any LLMProvider,
        auditRecorder: PlanningAuditRecorder? = nil,
        runtimeValidationMessage: String? = nil,
        commandRouter: any VoiceCommandRouting = VoiceCommandRouter()
    ) {
        self.draft = draft
        self.phase = phase
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.llmProvider = llmProvider
        self.auditRecorder = auditRecorder
        self.runtimeValidationMessage = runtimeValidationMessage
        self.commandRouter = commandRouter
        self.recordingState = audioRecorder.state
        self.auditErrorMessage = nil
        self.routingResult = draft.canGeneratePlan ? commandRouter.route(transcript: draft.normalizedText) : nil
        self.clarificationSession = nil
        self.assistantQueueItem = nil
    }

    public var canGeneratePlan: Bool {
        runtimeValidationMessage == nil
            && draft.canGeneratePlan
            && clarificationSession == nil
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

    public var clarificationQuestion: ClarificationQuestion? {
        clarificationSession?.currentQuestion
    }

    public func updateDraftText(_ text: String) {
        guard draft.text != text else {
            return
        }
        draft.text = text
        planningResponse = nil
        clarificationSession = nil
        assistantQueueItem = nil
        refreshRoutingResult()
        if shouldResetPhaseAfterDraftChange, runtimeValidationMessage == nil {
            phase = .idle
        }
    }

    public func clear() {
        audioRecorder.reset()
        draft = TranscriptDraft()
        planningResponse = nil
        recordedAudio = nil
        auditErrorMessage = nil
        routingResult = nil
        clarificationSession = nil
        assistantQueueItem = nil
        recordingState = audioRecorder.state
        phase = runtimeValidationMessage.map(VoiceCapturePhase.failed) ?? .idle
    }

    public func startRecording(at date: Date = Date()) async {
        do {
            try await audioRecorder.start(at: date)
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
            if clarificationSession != nil {
                await submitClarificationAnswer(transcript.text, inputMode: .voice)
                return
            }
            draft = TranscriptDraft(text: transcript.text)
            planningResponse = nil
            clarificationSession = nil
            assistantQueueItem = nil
            refreshRoutingResult()
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

        let routedCommand = commandRouter.route(transcript: draft.normalizedText)
        let plannedTranscript = routedCommand.normalizedTranscript
        routingResult = routedCommand
        guard !routedCommand.needsClarification else {
            planningResponse = nil
            assistantQueueItem = nil
            beginClarification(for: routedCommand)
            return
        }

        await generatePlan(
            for: routedCommand,
            plannedTranscript: plannedTranscript,
            currentDate: currentDate,
            timeZoneIdentifier: timeZoneIdentifier,
            availableTools: availableTools,
            knowledgeFrameCandidates: knowledgeFrameCandidates
        )
    }

    public func submitClarificationAnswer(
        _ answer: String,
        inputMode: ClarificationInputMode = .typed,
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        availableTools: [ActionTool] = ActionTool.allCases,
        knowledgeFrameCandidates: [KnowledgeFrameCandidate] = []
    ) async {
        guard var session = clarificationSession else {
            phase = .failed("No clarification is active.")
            return
        }

        switch session.answer(answer, inputMode: inputMode) {
        case .needsClarification:
            clarificationSession = session
            phase = .needsClarification(session.currentQuestion?.prompt ?? "Voice command needs clarification.")
        case .resolved:
            clarificationSession = nil
            guard let result = session.result else {
                phase = .failed("Clarification could not be resolved.")
                return
            }
            routingResult = result.resolvedRoute
            await generatePlan(
                for: result.resolvedRoute,
                plannedTranscript: result.resolvedRoute.normalizedTranscript,
                currentDate: currentDate,
                timeZoneIdentifier: timeZoneIdentifier,
                availableTools: availableTools,
                knowledgeFrameCandidates: knowledgeFrameCandidates
            )
        }
    }

    public func cancelClarification() {
        clarificationSession = nil
        if case .needsClarification = phase {
            phase = runtimeValidationMessage.map(VoiceCapturePhase.failed) ?? .idle
        }
    }

    @discardableResult
    public func approveAssistantQueueItem(reviewerID: String = "local-user") -> Bool {
        guard let assistantQueueItem else {
            return false
        }

        do {
            self.assistantQueueItem = try AssistantQueueStateMachine.approve(assistantQueueItem, reviewerID: reviewerID)
            return true
        } catch {
            auditErrorMessage = userMessage(for: error)
            return false
        }
    }

    public func deferAssistantQueueItem() {
        guard let assistantQueueItem else {
            return
        }
        self.assistantQueueItem = AssistantQueueStateMachine.deferItem(assistantQueueItem)
    }

    public func rejectAssistantQueueItem() {
        guard let assistantQueueItem else {
            return
        }
        self.assistantQueueItem = AssistantQueueStateMachine.reject(assistantQueueItem)
    }

    private func beginClarification(for route: VoiceCommandRoutingResult) {
        let session = ClarificationSession(route: route)
        clarificationSession = session
        phase = .needsClarification(session.currentQuestion?.prompt ?? route.clarificationReason ?? "Voice command needs clarification.")
    }

    private func generatePlan(
        for routedCommand: VoiceCommandRoutingResult,
        plannedTranscript: String,
        currentDate: Date,
        timeZoneIdentifier: String,
        availableTools: [ActionTool],
        knowledgeFrameCandidates: [KnowledgeFrameCandidate]
    ) async {
        let request = PlanningRequest(
            userInput: routedCommand.planningInput,
            currentDate: currentDate,
            timeZoneIdentifier: timeZoneIdentifier,
            availableTools: availableTools,
            knowledgeFrameCandidates: knowledgeFrameCandidates
        )

        phase = .generatingPlan
        auditErrorMessage = nil
        assistantQueueItem = nil

        do {
            try auditRecorder?.recordStarted(input: request.userInput, providerID: llmProvider.providerID)
        } catch {
            phase = .failed(userMessage(for: error))
            capturePlanningAuditFailure(error)
            return
        }

        do {
            let response = try await llmProvider.generatePlan(for: request)
            guard isCurrentTranscript(plannedTranscript) else {
                recordPlanningAudit {
                    try auditRecorder?.recordFailed(
                        input: request.userInput,
                        providerID: llmProvider.providerID,
                        error: VoicePlanningLifecycleError.transcriptChangedBeforeReview
                    )
                }
                applyStalePlanningState()
                return
            }
            planningResponse = response
            assistantQueueItem = makeAssistantQueueItem(from: response, routedCommand: routedCommand)
            recordPlanningAudit {
                try auditRecorder?.recordCompleted(response: response)
            }
            phase = response.validationResult.isValid ? .reviewReady : .failed("ActionPlan validation failed.")
        } catch {
            guard isCurrentTranscript(plannedTranscript) else {
                recordPlanningAudit {
                    try auditRecorder?.recordFailed(
                        input: request.userInput,
                        providerID: llmProvider.providerID,
                        error: VoicePlanningLifecycleError.transcriptChangedBeforeReview
                    )
                }
                applyStalePlanningState()
                return
            }
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
        auditErrorMessage = "Planning audit log failed: \(UserFacingErrorMessageSanitizer.message(from: error))"
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
                return UserFacingErrorMessageSanitizer.message(from: message)
            }
        }

        if let sttError = error as? STTProviderError {
            switch sttError {
            case .unavailable(let message):
                return UserFacingErrorMessageSanitizer.message(from: message)
            case .permissionDenied:
                return "Speech transcription permission is required."
            case .modelMissing(let message), .transcriptionFailed(let message):
                return UserFacingErrorMessageSanitizer.message(from: message)
            }
        }

        if let llmError = error as? LLMProviderError {
            return UserFacingErrorMessageSanitizer.message(from: llmError.userMessage)
        }

        return UserFacingErrorMessageSanitizer.message(from: error)
    }

    private var shouldResetPhaseAfterDraftChange: Bool {
        switch phase {
        case .failed, .needsClarification, .reviewReady:
            return true
        case .idle, .recording, .transcribing, .generatingPlan:
            return false
        }
    }

    private func refreshRoutingResult() {
        routingResult = draft.canGeneratePlan ? commandRouter.route(transcript: draft.normalizedText) : nil
    }

    private func isCurrentTranscript(_ plannedTranscript: String) -> Bool {
        draft.normalizedText == plannedTranscript
    }

    private func applyStalePlanningState() {
        // Review approval must stay tied to the transcript that produced it.
        // If the user edits speech text during provider generation, discard the
        // stale response instead of leaving an executable panel for old input.
        planningResponse = nil
        clarificationSession = nil
        assistantQueueItem = nil
        refreshRoutingResult()
        if let routingResult, routingResult.needsClarification {
            beginClarification(for: routingResult)
        } else if runtimeValidationMessage == nil {
            phase = .idle
        } else {
            phase = .failed(runtimeValidationMessage ?? "Voice planning is unavailable.")
        }
    }

    private func makeAssistantQueueItem(
        from response: PlanningResponse,
        routedCommand: VoiceCommandRoutingResult
    ) -> AssistantQueueItem? {
        guard let actionPlan = response.actionPlan else {
            return nil
        }
        return AssistantQueueAdapter.makeItem(
            actionPlan: actionPlan,
            sourceTranscript: routedCommand.originalTranscript,
            interpretationSummary: routedCommand.interpretationSummary,
            reason: "Voice planning draft needs review."
        )
    }
}

private enum VoicePlanningLifecycleError: Error, CustomStringConvertible {
    case transcriptChangedBeforeReview

    var description: String {
        switch self {
        case .transcriptChangedBeforeReview:
            "Planning response ignored because the transcript changed before review."
        }
    }
}
