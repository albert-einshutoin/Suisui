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

public struct VoiceDailyPlanningReviewRequest: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sourceTranscript: String
    public var routedIntent: VoiceCommandRoutingResult
    public var requestedAt: Date

    public init(
        id: UUID = UUID(),
        sourceTranscript: String,
        routedIntent: VoiceCommandRoutingResult,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.sourceTranscript = sourceTranscript
        self.routedIntent = routedIntent
        self.requestedAt = requestedAt
    }
}

public struct VoiceInboxTriageRequest: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var command: InboxVoiceTriageCommand
    public var sourceTranscript: String
    public var routedIntent: VoiceCommandRoutingResult
    public var requestedAt: Date

    public init(
        id: UUID = UUID(),
        command: InboxVoiceTriageCommand,
        sourceTranscript: String,
        routedIntent: VoiceCommandRoutingResult,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.command = command
        self.sourceTranscript = sourceTranscript
        self.routedIntent = routedIntent
        self.requestedAt = requestedAt
    }
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
    @Published public private(set) var dailyPlanningReviewRequest: VoiceDailyPlanningReviewRequest?
    @Published public private(set) var inboxTriageRequest: VoiceInboxTriageRequest?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?
    private let runtimeValidationMessage: String?
    private let assistantQueueStore: (any AssistantQueueStore)?
    private let commandRouter: any VoiceCommandRouting
    private let inboxTriageCommandParser: InboxVoiceTriageCommandParser

    public init(
        draft: TranscriptDraft = TranscriptDraft(),
        phase: VoiceCapturePhase = .idle,
        audioRecorder: any AudioRecorder,
        sttProvider: any SpeechToTextProvider,
        llmProvider: any LLMProvider,
        auditRecorder: PlanningAuditRecorder? = nil,
        runtimeValidationMessage: String? = nil,
        assistantQueueStore: (any AssistantQueueStore)? = nil,
        commandRouter: any VoiceCommandRouting = VoiceCommandRouter()
    ) {
        self.draft = draft
        self.phase = phase
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.llmProvider = llmProvider
        self.auditRecorder = auditRecorder
        self.runtimeValidationMessage = runtimeValidationMessage
        self.assistantQueueStore = assistantQueueStore
        self.commandRouter = commandRouter
        self.recordingState = audioRecorder.state
        self.auditErrorMessage = nil
        self.routingResult = draft.canGeneratePlan ? commandRouter.route(transcript: draft.normalizedText) : nil
        self.clarificationSession = nil
        self.assistantQueueItem = nil
        self.dailyPlanningReviewRequest = nil
        self.inboxTriageRequest = nil
        self.inboxTriageCommandParser = InboxVoiceTriageCommandParser()
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
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil
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
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil
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
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
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
        availableTools: [ActionTool] = ActionTool.defaultPlanningTools,
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

        if let inboxTriageCommand = inboxTriageCommandParser.parseVoiceCommand(draft.normalizedText) {
            beginInboxTriageRequest(
                command: inboxTriageCommand,
                routedIntent: makeInboxTriageRoute(for: inboxTriageCommand, fallbackRoute: routedCommand),
                requestedAt: currentDate
            )
            return
        }

        guard !routedCommand.needsClarification else {
            planningResponse = nil
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            beginClarification(for: routedCommand)
            return
        }

        guard routedCommand.intent != .dailyPlanningReview else {
            beginDailyPlanningReviewRequest(for: routedCommand, requestedAt: currentDate)
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
        availableTools: [ActionTool] = ActionTool.defaultPlanningTools,
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
            if let inboxTriageCommand = inboxTriageCommandParser.parseVoiceCommand(result.resolvedRoute.normalizedTranscript) {
                beginInboxTriageRequest(
                    command: inboxTriageCommand,
                    routedIntent: makeInboxTriageRoute(for: inboxTriageCommand, fallbackRoute: result.resolvedRoute),
                    requestedAt: currentDate
                )
                return
            }
            guard result.resolvedRoute.intent != .dailyPlanningReview else {
                beginDailyPlanningReviewRequest(for: result.resolvedRoute, requestedAt: currentDate)
                return
            }
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
            let approved = try AssistantQueueStateMachine.approve(assistantQueueItem, reviewerID: reviewerID)
            self.assistantQueueItem = try persistAssistantQueueItemIfNeeded(approved)
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
        let deferred = AssistantQueueStateMachine.deferItem(assistantQueueItem)
        do {
            self.assistantQueueItem = try persistAssistantQueueItemIfNeeded(deferred)
        } catch {
            auditErrorMessage = userMessage(for: error)
        }
    }

    public func rejectAssistantQueueItem() {
        guard let assistantQueueItem else {
            return
        }
        let rejected = AssistantQueueStateMachine.reject(assistantQueueItem)
        do {
            self.assistantQueueItem = try persistAssistantQueueItemIfNeeded(rejected)
        } catch {
            auditErrorMessage = userMessage(for: error)
        }
    }

    private func beginClarification(for route: VoiceCommandRoutingResult) {
        let session = ClarificationSession(route: route)
        clarificationSession = session
        phase = .needsClarification(session.currentQuestion?.prompt ?? route.clarificationReason ?? "Voice command needs clarification.")
    }

    private func beginDailyPlanningReviewRequest(for route: VoiceCommandRoutingResult, requestedAt: Date) {
        planningResponse = nil
        assistantQueueItem = nil
        clarificationSession = nil
        inboxTriageRequest = nil
        dailyPlanningReviewRequest = VoiceDailyPlanningReviewRequest(
            sourceTranscript: route.originalTranscript,
            routedIntent: route,
            requestedAt: requestedAt
        )
        phase = .reviewReady
    }

    private func beginInboxTriageRequest(
        command: InboxVoiceTriageCommand,
        routedIntent: VoiceCommandRoutingResult,
        requestedAt: Date
    ) {
        planningResponse = nil
        assistantQueueItem = nil
        clarificationSession = nil
        dailyPlanningReviewRequest = nil
        routingResult = routedIntent
        inboxTriageRequest = VoiceInboxTriageRequest(
            command: command,
            sourceTranscript: command.sourceTranscript,
            routedIntent: routedIntent,
            requestedAt: requestedAt
        )
        phase = .reviewReady
    }

    private func makeInboxTriageRoute(
        for command: InboxVoiceTriageCommand,
        fallbackRoute: VoiceCommandRoutingResult
    ) -> VoiceCommandRoutingResult {
        // The deterministic Inbox path gets its own local route because
        // explicitly scoped commands like "inbox today" are local UI commands,
        // not provider planning prompts.
        VoiceCommandRoutingResult(
            originalTranscript: fallbackRoute.originalTranscript,
            normalizedTranscript: fallbackRoute.normalizedTranscript,
            intent: .taskTriage,
            interpretationSummary: "Route as local Inbox voice triage command: \(command.action.accessibilityLabel).",
            confidence: 0.94,
            decision: .reviewOnly,
            reviewOnly: true,
            matchedSignals: [command.action.accessibilityLabel]
        )
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
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil

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
            recordPlanningAudit {
                try auditRecorder?.recordCompleted(response: response)
            }
            do {
                if let queueItem = makeAssistantQueueItem(from: response, routedCommand: routedCommand) {
                    assistantQueueItem = try persistAssistantQueueItemIfNeeded(queueItem)
                }
            } catch {
                assistantQueueItem = nil
                phase = .failed(userMessage(for: error))
                return
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

        if error is AssistantQueueStoreError {
            return AssistantQueueStoreError.userMessage(for: error)
        }

        return UserFacingErrorMessageSanitizer.message(from: error)
    }

    private func persistAssistantQueueItemIfNeeded(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard let assistantQueueStore else {
            return item
        }
        do {
            return try assistantQueueStore.save(item)
        } catch {
            // Queue persistence is fail-closed because review approval must not
            // happen against work that disappears after a restart.
            throw AssistantQueueStoreError.saveFailed
        }
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
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil
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
