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

/// Next-step affordance for a `.failed` plan-generation phase, derived from
/// the typed provider error so localized message text can never flip which
/// recovery action the UI offers.
public enum VoiceCaptureFailureRecovery: Equatable, Sendable {
    /// The configured provider rejected or is missing its API key, or local
    /// execution approval is required: Settings is the fix.
    case openSettings
    /// A transient provider problem (network, rate limit): rerunning plan
    /// generation with the same transcript is a reasonable next step.
    case retryPlanGeneration
}

public enum WorkspaceAnswerState: Equatable, Sendable {
    case idle
    case retrieving
    case answering
    case answered(text: String, contextCount: Int)
    case failed(String)
}

public enum LowLatencyVoiceAgentState: Equatable, Sendable {
    case idle
    case listening
    case disabled(String)
    case unavailable(String)
    case failed(String)
}

public struct VoiceDailyPlanningReviewRequest: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var sourceTranscript: String
    public var routedIntent: VoiceCommandRoutingResult
    public var requestedActionDraftKind: DailyPlanningActionDraftKind?
    public var requestedAt: Date

    public init(
        id: UUID = UUID(),
        sourceTranscript: String,
        routedIntent: VoiceCommandRoutingResult,
        requestedActionDraftKind: DailyPlanningActionDraftKind? = nil,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.sourceTranscript = sourceTranscript
        self.routedIntent = routedIntent
        self.requestedActionDraftKind = requestedActionDraftKind
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
    @Published public private(set) var planGenerationLiveText: String = ""
    @Published public private(set) var recordingState: AudioRecordingState
    @Published public private(set) var planningResponse: PlanningResponse?
    @Published public private(set) var recordedAudio: RecordedAudio?
    @Published public private(set) var auditErrorMessage: String?
    @Published public private(set) var routingResult: VoiceCommandRoutingResult?
    @Published public private(set) var clarificationSession: ClarificationSession?
    @Published public private(set) var assistantQueueItem: AssistantQueueItem?
    @Published public private(set) var dailyPlanningReviewRequest: VoiceDailyPlanningReviewRequest?
    @Published public private(set) var inboxTriageRequest: VoiceInboxTriageRequest?
    @Published public private(set) var inboxCaptureResult: InboxVoiceCaptureResult?
    @Published public private(set) var developmentPullRequestAutomationRequest: SyncAutomationRequestPayload?
    @Published public private(set) var lowLatencyVoiceAgentState: LowLatencyVoiceAgentState
    /// Segments of the live transcript that streaming STT already finalized.
    @Published public private(set) var finalizedTranscript: String = ""
    /// Trailing partial segment that may still change before finalization.
    @Published public private(set) var pendingTranscript: String = ""
    @Published public private(set) var liveIntentPreview: VoiceCommandRoutingResult?
    /// True after the microphone level has stayed below the silence threshold
    /// for a continuous stretch while recording (see MicrophoneSilenceDetector).
    @Published public private(set) var isMicrophoneSilenceHintVisible = false
    /// Observable slice for the ~10Hz microphone level so only the meter view
    /// re-renders per sample; see `MicrophoneInputLevelMeter`.
    public let inputLevelMeter = MicrophoneInputLevelMeter()
    @Published public private(set) var workspaceAnswer: WorkspaceAnswerState = .idle
    @Published public private(set) var autoCreatedTask: AutoCreatedTaskRecord?
    /// Non-nil only while `phase` is `.failed` from plan generation and the
    /// typed error has a known next step (Open Settings / Try Again).
    @Published public private(set) var failureRecovery: VoiceCaptureFailureRecovery?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?
    private let runtimeValidationMessage: String?
    private let assistantQueueStore: (any AssistantQueueStore)?
    private let commandRouter: any VoiceCommandRouting
    private let inboxCaptureSaver: (any InboxVoiceCaptureSaving)?
    private let inboxTriageCommandParser: InboxVoiceTriageCommandParser
    private let developmentProjectProvider: () -> ProjectRecord?
    private let developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder
    private let appSettingsProvider: @Sendable () -> AppSettings
    private let managedCostRateCardProvider: @Sendable (PlanningResponse) -> AssistantQueueCostRateCard?
    private let workspaceContextRetriever: (@Sendable (String) throws -> [WorkspaceContextSnippet])?
    private let workspaceAnswerReadout: (@Sendable (String) -> Void)?
    private let taskAutomationSettingsProvider: (@Sendable () -> TaskAutoExecutionSettings)?
    private let lowRiskTaskAutoExecutor: (@Sendable (ActionPlan) async throws -> LowRiskAutoCreationOutcome)?
    private let taskDeleter: (@Sendable (Int64) throws -> Void)?
    private let lowLatencySegmentDuration: TimeInterval
    private let lowLatencySegmentOutputURLProvider: @Sendable () -> URL
    // Save-to-Inbox must be tied to the audio that produced the current
    // transcript so a failed new recording cannot reuse stale typed text.
    private var lastTranscribedAudioURL: URL?
    private var savedInboxAudioURL: URL?
    private var lowLatencyStreamTask: Task<Void, Never>?
    private var lowLatencyStreamID: UUID
    private var microphoneSilenceDetector: MicrophoneSilenceDetector
    private var inputLevelMonitorTask: Task<Void, Never>?
    /// ~10Hz keeps the meter lively without spamming the main actor.
    private let inputLevelSampleInterval: TimeInterval = 0.1

    public init(
        draft: TranscriptDraft = TranscriptDraft(),
        phase: VoiceCapturePhase = .idle,
        audioRecorder: any AudioRecorder,
        sttProvider: any SpeechToTextProvider,
        llmProvider: any LLMProvider,
        auditRecorder: PlanningAuditRecorder? = nil,
        runtimeValidationMessage: String? = nil,
        assistantQueueStore: (any AssistantQueueStore)? = nil,
        commandRouter: any VoiceCommandRouting = VoiceCommandRouter(),
        inboxCaptureSaver: (any InboxVoiceCaptureSaving)? = nil,
        developmentProjectProvider: @escaping () -> ProjectRecord? = { nil },
        developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder = VoiceDevelopmentPullRequestAutomationRequestBuilder(),
        appSettingsProvider: @escaping @Sendable () -> AppSettings = { .default },
        managedCostRateCardProvider: @escaping @Sendable (PlanningResponse) -> AssistantQueueCostRateCard? = { _ in nil },
        workspaceContextRetriever: (@Sendable (String) throws -> [WorkspaceContextSnippet])? = nil,
        workspaceAnswerReadout: (@Sendable (String) -> Void)? = nil,
        taskAutomationSettingsProvider: (@Sendable () -> TaskAutoExecutionSettings)? = nil,
        lowRiskTaskAutoExecutor: (@Sendable (ActionPlan) async throws -> LowRiskAutoCreationOutcome)? = nil,
        taskDeleter: (@Sendable (Int64) throws -> Void)? = nil,
        microphoneSilenceDetector: MicrophoneSilenceDetector = MicrophoneSilenceDetector(),
        lowLatencySegmentDuration: TimeInterval = 1.2,
        lowLatencySegmentOutputURLProvider: @escaping @Sendable () -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("suisui-low-latency-\(UUID().uuidString).m4a")
        }
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
        self.inboxCaptureSaver = inboxCaptureSaver
        self.developmentProjectProvider = developmentProjectProvider
        self.developmentPullRequestAutomationRequestBuilder = developmentPullRequestAutomationRequestBuilder
        self.appSettingsProvider = appSettingsProvider
        self.managedCostRateCardProvider = managedCostRateCardProvider
        self.workspaceContextRetriever = workspaceContextRetriever
        self.workspaceAnswerReadout = workspaceAnswerReadout
        self.taskAutomationSettingsProvider = taskAutomationSettingsProvider
        self.lowRiskTaskAutoExecutor = lowRiskTaskAutoExecutor
        self.taskDeleter = taskDeleter
        self.microphoneSilenceDetector = microphoneSilenceDetector
        self.lowLatencySegmentDuration = lowLatencySegmentDuration
        self.lowLatencySegmentOutputURLProvider = lowLatencySegmentOutputURLProvider
        self.recordingState = audioRecorder.state
        self.auditErrorMessage = nil
        self.routingResult = draft.canGeneratePlan ? commandRouter.route(transcript: draft.normalizedText) : nil
        self.clarificationSession = nil
        self.assistantQueueItem = nil
        self.dailyPlanningReviewRequest = nil
        self.inboxTriageRequest = nil
        self.inboxCaptureResult = nil
        self.developmentPullRequestAutomationRequest = nil
        self.lowLatencyVoiceAgentState = .idle
        self.liveIntentPreview = nil
        self.inboxTriageCommandParser = InboxVoiceTriageCommandParser()
        self.lastTranscribedAudioURL = nil
        self.savedInboxAudioURL = nil
        self.lowLatencyStreamID = UUID()
    }

    public var canGeneratePlan: Bool {
        runtimeValidationMessage == nil
            && draft.canGeneratePlan
            && clarificationSession == nil
            && phase != .generatingPlan
            && phase != .recording
            && phase != .transcribing
    }

    public var canSaveDraftToInbox: Bool {
        inboxCaptureSaver != nil
            && recordedAudio?.fileURL == lastTranscribedAudioURL
            && recordedAudio?.fileURL != savedInboxAudioURL
            && draft.canGeneratePlan
            && phase != .recording
            && phase != .transcribing
            && phase != .generatingPlan
    }

    public var assistantQueueExecutionHandoffItemID: String? {
        // Voice capture stops at approval so execution, receipts, and cost
        // gates stay on the centralized Assistant Queue path.
        guard let assistantQueueItem, assistantQueueItem.state == .approved else {
            return nil
        }
        return assistantQueueItem.id
    }

    public var isRecording: Bool {
        if case .recording = phase {
            return true
        }
        return false
    }

    /// Finalized and pending segments combined, for callers that only need the
    /// full live transcript text.
    public var liveTranscript: String {
        guard !finalizedTranscript.isEmpty else {
            return pendingTranscript
        }
        guard !pendingTranscript.isEmpty else {
            return finalizedTranscript
        }
        return finalizedTranscript + " " + pendingTranscript
    }

    /// Latest normalized microphone input level (0...1). Live updates are
    /// published through `inputLevelMeter` so the meter view alone re-renders.
    public var inputLevel: Double {
        inputLevelMeter.inputLevel
    }

    public var isLowLatencyVoiceAgentListening: Bool {
        lowLatencyVoiceAgentState == .listening
    }

    public var handsFreeModeProviderName: String {
        // A Voice window owns its injected provider for its lifetime. Naming
        // that exact provider prevents the privacy surface from drifting when
        // Settings changes underneath an already-open window.
        sttProvider.id.displayName
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
        inboxCaptureResult = nil
        developmentPullRequestAutomationRequest = nil
        autoCreatedTask = nil
        failureRecovery = nil
        refreshRoutingResult()
        if shouldResetPhaseAfterDraftChange, runtimeValidationMessage == nil {
            phase = .idle
        }
    }

    public func clear() {
        stopLowLatencyVoiceAgentMode()
        stopInputLevelMonitoring()
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
        inboxCaptureResult = nil
        lastTranscribedAudioURL = nil
        savedInboxAudioURL = nil
        developmentPullRequestAutomationRequest = nil
        autoCreatedTask = nil
        failureRecovery = nil
        workspaceAnswer = .idle
        recordingState = audioRecorder.state
        phase = runtimeValidationMessage.map(VoiceCapturePhase.failed) ?? .idle
    }

    public func startLowLatencyVoiceAgentMode(
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        availableTools: [ActionTool] = ActionTool.defaultPlanningTools,
        knowledgeFrameCandidates: [KnowledgeFrameCandidate] = []
    ) async {
        stopLowLatencyVoiceAgentMode()
        let settings = appSettingsProvider().normalizedForRuntime
        guard phase != .recording, phase != .transcribing, phase != .generatingPlan else {
            lowLatencyVoiceAgentState = .unavailable("Finish the current voice operation before starting low-latency voice agent mode.")
            clearLiveVoiceAgentState()
            return
        }
        guard settings.isLowLatencyVoiceAgentModeEnabled else {
            lowLatencyVoiceAgentState = .disabled("Low-latency voice agent mode is disabled in Settings.")
            clearLiveVoiceAgentState()
            return
        }
        guard sttProvider.availability.isAvailable else {
            lowLatencyVoiceAgentState = .unavailable(sttProvider.availability.reason ?? "Speech transcription is unavailable.")
            clearLiveVoiceAgentState()
            return
        }
        // Voice windows keep provider instances alive while Settings can change underneath.
        // Fail closed so a stale cloud provider cannot run under a newly selected local setting.
        guard settings.sttProvider.providerID == sttProvider.id else {
            lowLatencyVoiceAgentState = .unavailable("Restart Voice Command after changing speech-to-text provider settings.")
            clearLiveVoiceAgentState()
            return
        }
        guard canUseLowLatencySTT(settings: settings) else {
            lowLatencyVoiceAgentState = .unavailable("Select local speech-to-text, or enable visible realtime cloud cost before using low-latency voice agent mode.")
            clearLiveVoiceAgentState()
            return
        }
        guard let stream = sttProvider.streamingTranscriptionEvents() ?? segmentedLowLatencyTranscriptionEvents(settings: settings) else {
            lowLatencyVoiceAgentState = .unavailable("Selected speech-to-text provider does not support low-latency voice agent mode yet.")
            clearLiveVoiceAgentState()
            return
        }

        let streamID = UUID()
        lowLatencyStreamID = streamID
        lowLatencyVoiceAgentState = .listening
        clearLiveVoiceAgentState()
        lowLatencyStreamTask = Task { [weak self] in
            do {
                for try await event in stream {
                    let shouldContinue = await self?.handleLowLatencyStreamingEvent(
                        event,
                        streamID: streamID,
                        currentDate: currentDate,
                        timeZoneIdentifier: timeZoneIdentifier,
                        availableTools: availableTools,
                        knowledgeFrameCandidates: knowledgeFrameCandidates
                    ) ?? false
                    if !shouldContinue {
                        break
                    }
                }
                self?.finishLowLatencyStreamIfCurrent(streamID)
            } catch is CancellationError {
                return
            } catch {
                self?.handleLowLatencyStreamingError(error, streamID: streamID)
            }
        }
    }

    public func stopLowLatencyVoiceAgentMode() {
        lowLatencyStreamID = UUID()
        lowLatencyStreamTask?.cancel()
        lowLatencyStreamTask = nil
        lowLatencyVoiceAgentState = .idle
        clearLiveVoiceAgentState()
    }

    public func startRecording(at date: Date = Date()) async {
        stopLowLatencyVoiceAgentMode()
        do {
            try await audioRecorder.start(at: date)
            recordingState = audioRecorder.state
            phase = .recording
            startInputLevelMonitoring(at: date)
        } catch {
            recordingState = audioRecorder.state
            phase = .failed(userMessage(for: error))
        }
    }

    public func stopRecording(outputURL: URL, at date: Date = Date()) async {
        stopInputLevelMonitoring()
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
            inboxCaptureResult = nil
            lastTranscribedAudioURL = audio.fileURL
            savedInboxAudioURL = nil
            developmentPullRequestAutomationRequest = nil
            refreshRoutingResult()
            phase = .idle
        } catch {
            lastTranscribedAudioURL = nil
            savedInboxAudioURL = nil
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
        failureRecovery = nil
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
            developmentPullRequestAutomationRequest = nil
            beginClarification(for: routedCommand)
            return
        }

        guard routedCommand.intent != .dailyPlanningReview else {
            beginDailyPlanningReviewRequest(for: routedCommand, requestedAt: currentDate)
            return
        }

        if beginConnectorSendGateQueueItemIfNeeded(for: routedCommand) {
            return
        }

        if beginNotificationDraftQueueItemIfNeeded(for: routedCommand) {
            return
        }

        if beginDevelopmentPullRequestAutomationRequestIfPossible(for: routedCommand) {
            return
        }

        await generatePlan(
            for: routedCommand,
            plannedTranscript: plannedTranscript,
            currentDate: currentDate,
            timeZoneIdentifier: timeZoneIdentifier,
            availableTools: planningTools(
                for: routedCommand,
                requestedAvailableTools: availableTools
            ),
            knowledgeFrameCandidates: knowledgeFrameCandidates
        )
    }

    public func saveDraftToInbox(
        at date: Date = Date(),
        createdAt: String? = nil
    ) {
        guard let inboxCaptureSaver else {
            auditErrorMessage = "Voice Inbox capture is unavailable because local voice stores could not be opened."
            return
        }
        guard let recordedAudio else {
            auditErrorMessage = "Record audio before saving to Inbox."
            return
        }
        guard recordedAudio.fileURL == lastTranscribedAudioURL else {
            auditErrorMessage = "Transcribe audio before saving to Inbox."
            return
        }
        guard recordedAudio.fileURL != savedInboxAudioURL else {
            auditErrorMessage = "This voice capture is already saved to Inbox."
            return
        }
        guard draft.canGeneratePlan else {
            phase = .failed("Transcript is empty.")
            return
        }

        do {
            inboxCaptureResult = try inboxCaptureSaver.saveTranscribedCapture(
                audio: recordedAudio,
                transcript: STTTranscript(text: draft.normalizedText, duration: recordedAudio.duration),
                transcriptionErrorMessage: nil,
                at: date,
                createdAt: createdAt
            )
            savedInboxAudioURL = recordedAudio.fileURL
            auditErrorMessage = nil
        } catch {
            inboxCaptureResult = nil
            auditErrorMessage = UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: "Voice Inbox capture could not be saved."
            )
        }
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
            if beginConnectorSendGateQueueItemIfNeeded(for: result.resolvedRoute) {
                return
            }
            if beginNotificationDraftQueueItemIfNeeded(for: result.resolvedRoute) {
                return
            }
            if beginDevelopmentPullRequestAutomationRequestIfPossible(for: result.resolvedRoute) {
                return
            }
            await generatePlan(
                for: result.resolvedRoute,
                plannedTranscript: result.resolvedRoute.normalizedTranscript,
                currentDate: currentDate,
                timeZoneIdentifier: timeZoneIdentifier,
                availableTools: planningTools(
                    for: result.resolvedRoute,
                    requestedAvailableTools: availableTools
                ),
                knowledgeFrameCandidates: knowledgeFrameCandidates
            )
        }
    }

    /// Answers a free-form question about local work: retrieve workspace
    /// context, ask the configured provider for a short speakable answer,
    /// then hand the redacted answer to the readout closure for TTS.
    public func askWorkspaceQuestion(
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) async {
        let question = draft.normalizedText
        guard !question.isEmpty else {
            workspaceAnswer = .failed("Type or dictate a question first.")
            return
        }
        guard let workspaceContextRetriever else {
            workspaceAnswer = .failed("Workspace question answering is unavailable because local data stores could not be opened.")
            return
        }
        switch workspaceAnswer {
        case .retrieving, .answering:
            return
        case .idle, .answered, .failed:
            break
        }

        workspaceAnswer = .retrieving
        let snippets: [WorkspaceContextSnippet]
        do {
            snippets = try workspaceContextRetriever(question)
        } catch {
            workspaceAnswer = .failed(userMessage(for: error))
            return
        }

        guard let answeringProvider = llmProvider as? AnswerGeneratingLLMProvider else {
            workspaceAnswer = .failed("The configured AI provider does not support workspace question answering yet.")
            return
        }

        workspaceAnswer = .answering
        let settings = appSettingsProvider().normalizedForRuntime
        let request = WorkspaceAnswerRequest(
            question: question,
            contextSnippets: snippets,
            currentDate: currentDate,
            timeZoneIdentifier: timeZoneIdentifier,
            languageCode: AppSettings.normalizedTTSLanguageCode(settings.ttsLanguageCode)
        )
        do {
            let answer = try await answeringProvider.generateAnswer(for: request)
            // Defensive redaction: the provider was already given redacted
            // context, but the model could still echo secrets or paths from
            // the question itself.
            let redactedAnswer = LocalPathRedactor.redact(DeveloperSecretRedactor().redact(answer).text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            workspaceAnswer = .answered(text: redactedAnswer, contextCount: snippets.count)
            workspaceAnswerReadout?(redactedAnswer)
        } catch {
            workspaceAnswer = .failed(userMessage(for: error))
        }
    }

    public func replayWorkspaceAnswer() {
        guard case .answered(let text, _) = workspaceAnswer else {
            return
        }
        workspaceAnswerReadout?(text)
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

    private func handleLowLatencyStreamingEvent(
        _ event: STTStreamingEvent,
        streamID: UUID,
        currentDate: Date,
        timeZoneIdentifier: String,
        availableTools: [ActionTool],
        knowledgeFrameCandidates: [KnowledgeFrameCandidate]
    ) async -> Bool {
        guard streamID == lowLatencyStreamID, lowLatencyVoiceAgentState == .listening else {
            return false
        }

        switch event {
        case .partial(let transcript):
            publishLiveTranscript(transcript.text)
            return true
        case .final(let transcript):
            appendFinalizedLiveTranscript(transcript.text)
            await handleLowLatencyFinalTranscript(
                transcript.text,
                currentDate: currentDate,
                timeZoneIdentifier: timeZoneIdentifier,
                availableTools: availableTools,
                knowledgeFrameCandidates: knowledgeFrameCandidates
            )
            return streamID == lowLatencyStreamID && lowLatencyVoiceAgentState == .listening
        case .stopped:
            stopLowLatencyVoiceAgentMode()
            return false
        }
    }

    private func segmentedLowLatencyTranscriptionEvents(
        settings: AppSettings
    ) -> AsyncThrowingStream<STTStreamingEvent, Error>? {
        guard canUseSegmentedLowLatencySTT(settings: settings) else {
            return nil
        }

        return AsyncThrowingStream { continuation in
            let segmentTask = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.yield(.stopped)
                    continuation.finish()
                    return
                }
                do {
                    let startedAt = Date()
                    try await audioRecorder.start(at: startedAt)
                    recordingState = audioRecorder.state
                    if lowLatencySegmentDuration > 0 {
                        try await Task.sleep(
                            nanoseconds: UInt64(max(lowLatencySegmentDuration, 0) * 1_000_000_000)
                        )
                    }
                    let audio = try audioRecorder.stop(
                        outputURL: lowLatencySegmentOutputURLProvider(),
                        at: Date()
                    )
                    recordingState = audioRecorder.state
                    let transcript = try await sttProvider.transcribe(audio)
                    continuation.yield(.final(transcript))
                    continuation.yield(.stopped)
                    continuation.finish()
                } catch is CancellationError {
                    audioRecorder.reset()
                    recordingState = audioRecorder.state
                    continuation.finish()
                } catch {
                    audioRecorder.reset()
                    recordingState = audioRecorder.state
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                segmentTask.cancel()
            }
        }
    }

    private func canUseSegmentedLowLatencySTT(settings: AppSettings) -> Bool {
        guard canUseLowLatencySTT(settings: settings) else {
            return false
        }

        switch settings.sttProvider {
        case .localWhisperCpp:
            return true
        case .openAITranscribe:
            return true
        case .appleSpeechAnalyzer, .localWhisperKit:
            return false
        }
    }

    private func canUseLowLatencySTT(settings: AppSettings) -> Bool {
        switch settings.sttProvider {
        case .localWhisperCpp:
            return true
        case .openAITranscribe:
            return settings.isLowLatencyVoiceAgentCloudFallbackEnabled
                && settings.isLowLatencyVoiceAgentCloudFallbackCostVisible
        case .appleSpeechAnalyzer, .localWhisperKit:
            return false
        }
    }

    private func handleLowLatencyStreamingError(_ error: Error, streamID: UUID) {
        guard streamID == lowLatencyStreamID else {
            return
        }
        lowLatencyStreamTask = nil
        lowLatencyStreamID = UUID()
        lowLatencyVoiceAgentState = .failed(userMessage(for: error))
        clearLiveVoiceAgentState()
    }

    private func publishLiveTranscript(_ text: String) {
        pendingTranscript = text
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Partial transcripts are intentionally local-only previews. Calling an
        // LLM or enqueueing work on unstable audio would waste provider budget
        // and could surface review items for words the user has not finished.
        liveIntentPreview = normalized.isEmpty ? nil : commandRouter.route(transcript: normalized)
    }

    /// Moves a just-finalized transcript segment out of the pending (partial)
    /// slot so the UI can render finalized text in primary color while the
    /// next partial segment streams in as secondary.
    private func appendFinalizedLiveTranscript(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingTranscript = ""
        guard !normalized.isEmpty else {
            return
        }
        finalizedTranscript = finalizedTranscript.isEmpty
            ? normalized
            : finalizedTranscript + " " + normalized
    }

    private func handleLowLatencyFinalTranscript(
        _ text: String,
        currentDate: Date,
        timeZoneIdentifier: String,
        availableTools: [ActionTool],
        knowledgeFrameCandidates: [KnowledgeFrameCandidate]
    ) async {
        // Keep the finalized transcript visible while the command is handled;
        // only the unstable partial tail and its intent preview are stale now.
        pendingTranscript = ""
        liveIntentPreview = nil

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            phase = .failed("Transcript is empty.")
            return
        }

        if clarificationSession != nil {
            await submitClarificationAnswer(
                normalized,
                inputMode: .voice,
                currentDate: currentDate,
                timeZoneIdentifier: timeZoneIdentifier,
                availableTools: availableTools,
                knowledgeFrameCandidates: knowledgeFrameCandidates
            )
            return
        }

        updateDraftText(normalized)
        await generatePlan(
            currentDate: currentDate,
            timeZoneIdentifier: timeZoneIdentifier,
            availableTools: availableTools,
            knowledgeFrameCandidates: knowledgeFrameCandidates
        )
    }

    private func clearLiveVoiceAgentState() {
        finalizedTranscript = ""
        pendingTranscript = ""
        liveIntentPreview = nil
    }

    private func startInputLevelMonitoring(at date: Date) {
        stopInputLevelMonitoring()
        guard let levelReader = audioRecorder as? AudioInputLevelReading else {
            return
        }
        microphoneSilenceDetector.beginRecording(at: date)
        let sampleInterval = inputLevelSampleInterval
        inputLevelMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isRecording else {
                    return
                }
                let level = levelReader.currentNormalizedInputLevel ?? 0
                self.inputLevelMeter.update(level)
                let isSilent = self.microphoneSilenceDetector.recordSample(level: level, at: Date())
                if self.isMicrophoneSilenceHintVisible != isSilent {
                    self.isMicrophoneSilenceHintVisible = isSilent
                }
                try? await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))
            }
        }
    }

    private func stopInputLevelMonitoring() {
        inputLevelMonitorTask?.cancel()
        inputLevelMonitorTask = nil
        microphoneSilenceDetector.reset()
        inputLevelMeter.update(0)
        isMicrophoneSilenceHintVisible = false
    }

    private func finishLowLatencyStreamIfCurrent(_ streamID: UUID) {
        guard streamID == lowLatencyStreamID else {
            return
        }
        lowLatencyStreamTask = nil
        lowLatencyStreamID = UUID()
        lowLatencyVoiceAgentState = .idle
        clearLiveVoiceAgentState()
    }

    private func beginDailyPlanningReviewRequest(for route: VoiceCommandRoutingResult, requestedAt: Date) {
        planningResponse = nil
        assistantQueueItem = nil
        clarificationSession = nil
        inboxTriageRequest = nil
        developmentPullRequestAutomationRequest = nil
        dailyPlanningReviewRequest = VoiceDailyPlanningReviewRequest(
            sourceTranscript: route.originalTranscript,
            routedIntent: route,
            requestedActionDraftKind: Self.requestedDailyPlanningActionDraftKind(from: route),
            requestedAt: requestedAt
        )
        phase = .reviewReady
    }

    private static func requestedDailyPlanningActionDraftKind(
        from route: VoiceCommandRoutingResult
    ) -> DailyPlanningActionDraftKind? {
        let folded = route.normalizedTranscript
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let requestsStart = containsAnyExplicitPhrase(
            [
                "start recommended",
                "start the recommended",
                "begin recommended",
                "begin the recommended",
                "おすすめを開始",
                "おすすめを始め",
                "おすすめに着手",
                "推奨タスクを開始",
                "推奨タスクを始め",
                "推奨タスクに着手"
            ],
            in: folded
        )
        let requestsDefer = containsAnyExplicitPhrase(
            [
                "defer recommended to tomorrow",
                "defer recommended task",
                "defer the recommended task",
                "defer the recommended task to tomorrow",
                "move recommended to tomorrow",
                "move recommended task to tomorrow",
                "move the recommended task to tomorrow",
                "おすすめを明日に回",
                "おすすめを明日へ",
                "おすすめを延期",
                "推奨タスクを明日に回",
                "推奨タスクを明日へ",
                "推奨タスクを延期"
            ],
            in: folded
        )
        let requestsReschedule = containsAnyExplicitPhrase(
            [
                "reschedule recommended to today",
                "reschedule recommended task to today",
                "reschedule the recommended task to today",
                "move recommended to today",
                "move recommended task to today",
                "move the recommended task to today",
                "おすすめを今日にリスケ",
                "おすすめを今日へリスケ",
                "おすすめを今日に移動",
                "おすすめを今日へ移動",
                "推奨タスクを今日にリスケ",
                "推奨タスクを今日へリスケ",
                "推奨タスクを今日に移動",
                "推奨タスクを今日へ移動"
            ],
            in: folded
        )
        let requestsSplit = containsAnyExplicitPhrase(
            [
                "split recommended",
                "split recommended task",
                "split the recommended task",
                "break down recommended",
                "break down recommended task",
                "break down the recommended task",
                "おすすめを分割",
                "おすすめを分け",
                "おすすめを細分化",
                "推奨タスクを分割",
                "推奨タスクを分け",
                "推奨タスクを細分化"
            ],
            in: folded
        )
        let rejectsAction = containsAny(
            ["do not", "don't", "dont", "not start", "not defer", "not reschedule", "not split", "cancel", "しない", "始めない", "開始しない", "延期しない", "リスケしない", "分割しない", "分けない", "やめ"],
            in: folded
        )
        let asksForAdvice = containsAnyExplicitPhrase(
            ["should i", "should we", "whether", "do you think", "is it better"],
            in: folded
        ) || containsAny(
            ["すべき", "べきか", "するか", "回すか", "確認して", "相談", "どう思"],
            in: folded
        )

        // Voice Daily Planning may prefill an approval item, but ambiguous
        // phrases must stay as a read-only review so the assistant never turns
        // a vague planning prompt into a write-capable Queue action.
        let requestedKinds = [
            (requestsStart, DailyPlanningActionDraftKind.startRecommended),
            (requestsDefer, DailyPlanningActionDraftKind.deferRecommendedToTomorrow),
            (requestsReschedule, DailyPlanningActionDraftKind.moveRecommendedDueDateToToday),
            (requestsSplit, DailyPlanningActionDraftKind.splitRecommendedTask)
        ].compactMap { isRequested, kind in
            isRequested ? kind : nil
        }

        guard rejectsAction == false, asksForAdvice == false, requestedKinds.count == 1 else {
            return nil
        }
        return requestedKinds[0]
    }

    private static func containsAnyExplicitPhrase(_ phrases: [String], in foldedTranscript: String) -> Bool {
        phrases.contains { phrase in
            guard usesOnlyASCIILettersOrSpaces(phrase) else {
                return foldedTranscript.contains(phrase)
            }
            return containsLatinPhrase(phrase, in: foldedTranscript)
        }
    }

    private static func containsAny(_ needles: [String], in foldedTranscript: String) -> Bool {
        needles.contains { needle in
            foldedTranscript.contains(needle)
        }
    }

    private static func containsLatinPhrase(_ phrase: String, in foldedTranscript: String) -> Bool {
        var searchStart = foldedTranscript.startIndex
        while let range = foldedTranscript.range(of: phrase, range: searchStart..<foldedTranscript.endIndex) {
            if isLatinPhraseBoundary(before: range.lowerBound, after: range.upperBound, in: foldedTranscript) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func isLatinPhraseBoundary(
        before lowerBound: String.Index,
        after upperBound: String.Index,
        in text: String
    ) -> Bool {
        let beforeIsBoundary = lowerBound == text.startIndex
            || isLatinPhraseBoundaryCharacter(text[text.index(before: lowerBound)])
        let afterIsBoundary = upperBound == text.endIndex
            || isLatinPhraseBoundaryCharacter(text[upperBound])
        return beforeIsBoundary && afterIsBoundary
    }

    private static func isLatinPhraseBoundaryCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) == false
        }
    }

    private static func usesOnlyASCIILettersOrSpaces(_ phrase: String) -> Bool {
        phrase.unicodeScalars.allSatisfy { scalar in
            scalar.value == 32 || (scalar.value >= 97 && scalar.value <= 122)
        }
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
        developmentPullRequestAutomationRequest = nil
        routingResult = routedIntent
        inboxTriageRequest = VoiceInboxTriageRequest(
            command: command,
            sourceTranscript: command.sourceTranscript,
            routedIntent: routedIntent,
            requestedAt: requestedAt
        )
        phase = .reviewReady
    }

    private func beginDevelopmentPullRequestAutomationRequestIfPossible(
        for route: VoiceCommandRoutingResult
    ) -> Bool {
        guard route.intent == .developmentPRWorkflow,
              VoiceDevelopmentPullRequestAutomationRequestBuilder.containsPullRequestURL(in: route.normalizedTranscript) else {
            return false
        }

        guard let project = developmentProjectProvider() else {
            planningResponse = nil
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            developmentPullRequestAutomationRequest = nil
            phase = .needsClarification("Select an approved project directory before queueing a development PR automation request.")
            return true
        }

        do {
            let request = try developmentPullRequestAutomationRequestBuilder.makeRequest(
                route: route,
                project: project
            )
            let item = AssistantQueueAdapter.makeItem(automationRequest: request)
            planningResponse = nil
            assistantQueueItem = try persistAssistantQueueItemIfNeeded(item)
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            clarificationSession = nil
            developmentPullRequestAutomationRequest = request
            phase = .reviewReady
        } catch let error as VoiceDevelopmentPullRequestAutomationRequestError {
            planningResponse = nil
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            developmentPullRequestAutomationRequest = nil
            phase = .failed(error.userMessage)
        } catch {
            planningResponse = nil
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            developmentPullRequestAutomationRequest = nil
            phase = .failed(userMessage(for: error))
        }
        return true
    }

    private func beginConnectorSendGateQueueItemIfNeeded(for route: VoiceCommandRoutingResult) -> Bool {
        guard route.intent == .connectorSendGate else {
            return false
        }

        do {
            let item = makeConnectorSendGateQueueItem(for: route)
            planningResponse = nil
            assistantQueueItem = try persistAssistantQueueItemIfNeeded(item)
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            clarificationSession = nil
            developmentPullRequestAutomationRequest = nil
            phase = .reviewReady
        } catch {
            planningResponse = nil
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            developmentPullRequestAutomationRequest = nil
            phase = .failed(userMessage(for: error))
        }
        return true
    }

    private func makeConnectorSendGateQueueItem(for route: VoiceCommandRoutingResult) -> AssistantQueueItem {
        let redactor = ExecutionReceiptRedactor()
        let redactedTranscript = redactor.redact(route.originalTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let connector = Self.connectorSendDestination(from: route)
        let summary = [
            "Connector send requested for \(connector.displayName).",
            "Original voice request:",
            redactedTranscript
        ].joined(separator: "\n")
        return AssistantQueueAdapter.makeConnectorSendGateItem(
            serviceID: connector.serviceID,
            serviceDisplayName: connector.displayName,
            redactedSourceTranscript: redactedTranscript,
            redactedArgumentSummary: summary,
            routeSummary: route.interpretationSummary
        )
    }

    private func beginNotificationDraftQueueItemIfNeeded(for route: VoiceCommandRoutingResult) -> Bool {
        guard route.intent == .notificationDraft else {
            return false
        }

        do {
            let item = makeNotificationDraftQueueItem(for: route)
            planningResponse = nil
            assistantQueueItem = try persistAssistantQueueItemIfNeeded(item)
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            clarificationSession = nil
            developmentPullRequestAutomationRequest = nil
            phase = .reviewReady
        } catch {
            planningResponse = nil
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            developmentPullRequestAutomationRequest = nil
            phase = .failed(userMessage(for: error))
        }
        return true
    }

    private func makeNotificationDraftQueueItem(for route: VoiceCommandRoutingResult) -> AssistantQueueItem {
        let redactor = ExecutionReceiptRedactor()
        // Notification-style commands often mention external services. Until a
        // connector-specific send gate exists, keep them as a local mail draft
        // payload so the Assistant Queue review remains the only gate before
        // any notification, mail, Slack, LINE, or Discord side effect can exist.
        let reviewContext = makeNotificationDraftReviewContext(for: route, redactor: redactor)
        let draftBody = [
            "Original voice request:",
            reviewContext.redactedOriginalTranscript
        ]
        let clarificationBody = reviewContext.redactedClarificationLines.isEmpty
            ? []
            : [
                "",
                "Clarification answers:",
                reviewContext.redactedClarificationLines.joined(separator: "\n")
            ]
        let actionBody = (draftBody + clarificationBody).joined(separator: "\n")
        let actionPlan = ActionPlan(
            id: "notification-draft:\(UUID().uuidString)",
            userInput: reviewContext.redactedSourceTranscript,
            summary: "Prepare a text-only notification draft without sending it.",
            actions: [
                PlanAction(
                    id: "notification-draft-mail",
                    tool: .mailDraftCreateText,
                    arguments: [
                        "subject": .string("Notification draft"),
                        "body": .string(actionBody)
                    ],
                    riskLevel: .draft
                )
            ],
            riskLevel: .draft,
            requiresApproval: false
        )
        return AssistantQueueAdapter.makeItem(
            actionPlan: actionPlan,
            sourceTranscript: reviewContext.redactedSourceTranscript,
            interpretationSummary: route.interpretationSummary,
            reason: "Notification draft needs review before any external message or local notification is created.",
            costPreview: .localOnly(note: "Local text draft only. No connector send or local notification is created before review.")
        )
    }

    private func makeNotificationDraftReviewContext(
        for route: VoiceCommandRoutingResult,
        redactor: ExecutionReceiptRedactor
    ) -> (
        redactedOriginalTranscript: String,
        redactedClarificationLines: [String],
        redactedSourceTranscript: String
    ) {
        let redactedOriginalTranscript = redactor.redact(route.originalTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let redactedClarificationLines = route.clarificationTrail.map { trail in
            let redactedAnswer = redactor.redact(trail.answer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "- \(trail.slot): \(redactedAnswer)"
        }
        let sourceTranscriptParts = redactedClarificationLines.isEmpty
            ? [redactedOriginalTranscript]
            : [
                redactedOriginalTranscript,
                "Clarification answers:",
                redactedClarificationLines.joined(separator: "\n")
            ]
        return (
            redactedOriginalTranscript: redactedOriginalTranscript,
            redactedClarificationLines: redactedClarificationLines,
            redactedSourceTranscript: sourceTranscriptParts.joined(separator: "\n")
        )
    }

    private static func connectorSendDestination(
        from route: VoiceCommandRoutingResult
    ) -> (serviceID: String, displayName: String) {
        let folded = route.normalizedTranscript
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        let knownConnectors: [(serviceID: String, displayName: String, signals: [String])] = [
            ("slack", "Slack", ["slack"]),
            ("line", "LINE", ["line"]),
            ("discord", "Discord", ["discord"]),
            ("mail", "Mail", ["mail", "email", "メール"])
        ]

        for connector in knownConnectors
            where connector.signals.contains(where: { signal in containsConnectorSignal(signal, in: folded) }) {
            return (connector.serviceID, connector.displayName)
        }
        return ("external", "External")
    }

    private static func containsConnectorSignal(_ signal: String, in foldedTranscript: String) -> Bool {
        guard usesOnlyASCIILettersOrDigits(signal) else {
            return foldedTranscript.contains(signal)
        }

        var searchStart = foldedTranscript.startIndex
        while let range = foldedTranscript.range(of: signal, range: searchStart..<foldedTranscript.endIndex) {
            if isLatinWordBoundary(before: range.lowerBound, after: range.upperBound, in: foldedTranscript) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private static func usesOnlyASCIILettersOrDigits(_ signal: String) -> Bool {
        signal.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (97...122).contains(value) || (48...57).contains(value)
        }
    }

    private static func isLatinWordBoundary(
        before lowerBound: String.Index,
        after upperBound: String.Index,
        in text: String
    ) -> Bool {
        let hasLatinWordBefore = lowerBound > text.startIndex && isLatinWordCharacter(text[text.index(before: lowerBound)])
        let hasLatinWordAfter = upperBound < text.endIndex && isLatinWordCharacter(text[upperBound])
        return !hasLatinWordBefore && !hasLatinWordAfter
    }

    private static func isLatinWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            let value = scalar.value
            return (65...90).contains(value)
                || (97...122).contains(value)
                || (48...57).contains(value)
                || value == 95
        }
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

    /// Streams provider output into `planGenerationLiveText` when the
    /// configured provider supports it; otherwise falls back to the
    /// single-response path with identical results.
    private func generatePlanResponse(for request: PlanningRequest) async throws -> PlanningResponse {
        guard let streamingProvider = llmProvider as? StreamingLLMProvider else {
            return try await llmProvider.generatePlan(for: request)
        }

        return try await streamingProvider.generatePlanStream(for: request) { [weak self] delta in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .generatingPlan else {
                    return
                }
                self.planGenerationLiveText += delta
            }
        }
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
        planGenerationLiveText = ""
        workspaceAnswer = .idle
        auditErrorMessage = nil
        failureRecovery = nil
        assistantQueueItem = nil
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil
        developmentPullRequestAutomationRequest = nil
        autoCreatedTask = nil

        do {
            try auditRecorder?.recordStarted(input: request.userInput, providerID: llmProvider.providerID)
        } catch {
            phase = .failed(userMessage(for: error))
            capturePlanningAuditFailure(error)
            return
        }

        do {
            let response = try await generatePlanResponse(for: request)
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
            phase = response.validationResult.isValid ? .reviewReady : .failed("ActionPlan validation failed.")
            if phase == .reviewReady,
               await autoCreateLowRiskTaskIfEligible(from: response) {
                return
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
            failureRecovery = Self.failureRecovery(for: error)
            phase = .failed(userMessage(for: error))
        }
    }

    /// Maps a plan-generation error onto the next-step affordance shown next
    /// to the failure message. Classification is on the typed error, never on
    /// user-facing message text.
    private static func failureRecovery(for error: Error) -> VoiceCaptureFailureRecovery? {
        guard let llmError = error as? LLMProviderError else {
            return nil
        }
        switch llmError {
        case .authenticationFailed, .executionNotApproved:
            return .openSettings
        case .network, .rateLimited:
            return .retryPlanGeneration
        case .invalidResponse, .unknown:
            return nil
        }
    }

    /// Opt-in auto-creation of a single low-risk task. The plan already passed
    /// validation and reached `.reviewReady`; when the user selected the
    /// autoCreateLowRisk automation mode and the plan qualifies, run it through
    /// the injected review execution pipeline (same executor, audit trail, and
    /// receipts as a manual approval) and publish an undoable record.
    private func autoCreateLowRiskTaskIfEligible(from response: PlanningResponse) async -> Bool {
        guard let taskAutomationSettingsProvider,
              let lowRiskTaskAutoExecutor,
              let plan = response.actionPlan else {
            return false
        }
        guard LowRiskAutoCreationPolicy.qualifies(
            plan: plan,
            validation: response.validationResult,
            settings: taskAutomationSettingsProvider()
        ) else {
            return false
        }

        do {
            let outcome = try await lowRiskTaskAutoExecutor(plan)
            guard let taskID = outcome.taskID else {
                return false
            }
            autoCreatedTask = AutoCreatedTaskRecord(taskID: taskID, title: outcome.taskTitle)
            return true
        } catch {
            // Auto-create is best effort: the plan itself stays reviewReady with
            // the manual approval buttons as the fallback, so an execution
            // failure must never turn a successful plan into a failed phase.
            autoCreatedTask = nil
            return false
        }
    }

    /// Post-hoc undo for an auto-created task. Deletion failures keep the
    /// record so the user can retry, and surface through the existing
    /// audit/error message channel.
    public func undoAutoCreatedTask() {
        guard let record = autoCreatedTask else {
            return
        }
        guard let taskDeleter else {
            auditErrorMessage = "Undo is unavailable because local data stores could not be opened."
            return
        }
        do {
            try taskDeleter(record.taskID)
            autoCreatedTask = nil
            auditErrorMessage = nil
        } catch {
            auditErrorMessage = userMessage(for: error)
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
        developmentPullRequestAutomationRequest = nil
        failureRecovery = nil
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
            reason: "Voice planning draft needs review.",
            costPreview: assistantQueueCostPreview(for: response)
        )
    }

    private func planningTools(
        for routedCommand: VoiceCommandRoutingResult,
        requestedAvailableTools: [ActionTool]
    ) -> [ActionTool] {
        guard routedCommand.intent == .developmentPRWorkflow,
              requestedAvailableTools == ActionTool.defaultPlanningTools else {
            return requestedAvailableTools
        }

        // Developer tools are excluded from the default voice planner so normal
        // task capture cannot gain filesystem, Git, or GitHub write surfaces.
        // A routed development PR command is the explicit boundary where the
        // planner may draft branch, commit, push, PR, review, and merge gates.
        return ActionTool.developerModePlanningTools
    }

    private func assistantQueueCostPreview(for response: PlanningResponse) -> AssistantQueueCostPreview {
        let observedUsage = response.usage.state == .measured ? response.usage : nil
        guard response.model != nil || observedUsage != nil else {
            return .localOnly()
        }

        let model = response.model ?? ExecutionReceiptModel(provider: response.providerID, name: "unknown")
        let catalogEntry = LLMProviderCatalog.entry(forRuntimeProviderID: response.providerID)
        if catalogEntry?.id == .codexLocal {
            // Codex runs on the Mac, but its model usage is billed against the
            // user's ChatGPT/Codex allowance. Do not classify it as free local
            // inference or add it to Suisui-managed cost.
            return .userProviderBilled(
                provider: model.provider,
                modelName: model.name,
                note: "User's ChatGPT Codex allowance. No Suisui managed charge.",
                observedUsage: observedUsage
            )
        }
        if catalogEntry?.billingMode == .localOnly {
            return .localOnly(model: model, observedUsage: observedUsage)
        }
        if let rateCard = managedCostRateCardProvider(response) {
            let managedBilling = appSettingsProvider().normalizedForRuntime.managedAIBilling
            // Managed previews are the only path where Suisui can enforce a
            // local hard cap before queue approval; BYOK/provider-billed calls
            // remain audit telemetry because their billing happens upstream.
            return rateCard.preview(
                inputTokens: response.usage.inputTokens,
                outputTokens: response.usage.outputTokens,
                hardCapCents: managedBilling.hardCapCentsForPreview
            )
        }

        // Provider planning usage is already incurred before local execution.
        // Store it as BYOK/provider-billed telemetry so receipts can audit token
        // usage without treating it as a Suisui-managed pre-run charge.
        return .userProviderBilled(
            provider: model.provider,
            modelName: model.name,
            observedUsage: observedUsage
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
