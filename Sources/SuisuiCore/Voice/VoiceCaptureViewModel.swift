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
    @Published public private(set) var conversationWorkspaceScope =
        VoiceTaskConversationWorkspacePresentation.Scope()
    @Published public private(set) var conversationWorkspaceTurns:
        [VoiceTaskConversationWorkspacePresentation.Turn] = []
    @Published public private(set) var conversationWorkspaceTurnListState:
        VoiceTaskConversationWorkspacePresentation.TurnListState = .empty
    @Published public private(set) var conversationWorkspaceLocalAnswerItems:
        [VoiceTaskConversationAnswerItem] = []
    @Published public private(set) var conversationWorkspaceSessionState:
        VoiceTaskConversationWorkspacePresentation.SessionState?
    @Published public private(set) var conversationWorkspaceCloseout =
        VoiceTaskConversationWorkspacePresentation.Closeout()
    @Published public private(set) var conversationWorkspaceResolvedTarget:
        VoiceTaskConversationWorkspacePresentation.ResolvedTarget?
    @Published public private(set) var conversationWorkspaceFactCandidates:
        [VoiceTaskConversationWorkspacePresentation.FactCandidate] = []
    @Published private var orchestratedClarificationQuestion: ClarificationQuestion?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?
    private let runtimeValidationMessage: String?
    private let assistantQueueStore: (any AssistantQueueStore)?
    private let commandRouter: any VoiceCommandRouting
    private let conversationOrchestrator: (any VoiceTaskConversationOrchestrating)?
    private let conversationCommandPreparer:
        (any VoiceTaskConversationCommandPreparing)?
    private let conversationSessionID: UUID
    private let inboxCaptureSaver: (any InboxVoiceCaptureSaving)?
    private let inboxTriageCommandParser: InboxVoiceTriageCommandParser
    private let developmentProjectProvider: () -> ProjectRecord?
    private let developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder
    private let appSettingsProvider: @Sendable () -> AppSettings
    private let managedCostRateCardProvider: @Sendable (PlanningResponse) -> AssistantQueueCostRateCard?
    private let workspaceContextRetriever: (@Sendable (String) throws -> [WorkspaceContextSnippet])?
    private let workspaceAnswerReadout: (@Sendable (String) -> Void)?
    /// Quick Capture can opt into a bounded clarification loop. nil keeps
    /// the legacy Conversation workspace contract, which may ask more than
    /// one scoped question.
    private let maximumQuickCaptureClarificationTurns: Int?
    private let taskAutomationSettingsProvider: (@Sendable () -> TaskAutoExecutionSettings)?
    private let lowRiskTaskAutoExecutor: (@Sendable (ActionPlan) async throws -> LowRiskAutoCreationOutcome)?
    private let taskDeleter: (@Sendable (Int64) throws -> Void)?
    private let lowLatencySegmentDuration: TimeInterval
    private let lowLatencySegmentOutputURLProvider: @Sendable () -> URL
    private var temporaryRecordingRemover: @Sendable (URL) throws -> Void = {
        try FileManager.default.removeItem(at: $0)
    }
    // Save-to-Inbox must be tied to the audio that produced the current
    // transcript so a failed new recording cannot reuse stale typed text.
    private var lastTranscribedAudioURL: URL?
    // Identifies the source take already persisted to Inbox so repeated Save
    // cannot duplicate its task. Deletion ownership is tracked separately:
    // a copied temporary source can be both saved and pending cleanup.
    private var savedInboxSourceAudioURL: URL?
    private var pendingTemporaryRecordingDeletionURLs: Set<URL> = []
    private var lowLatencyStreamTask: Task<Void, Never>?
    private var lowLatencyStreamID: UUID
    private var microphoneSilenceDetector: MicrophoneSilenceDetector
    private var inputLevelMonitorTask: Task<Void, Never>?
    private var activeConversationSourceTurnID: UUID?
    private var clarificationQuestionCount = 0
    private var conversationCancellationTask: Task<VoiceTaskConversationOutcome, Never>?
    private var conversationWorkspaceStore: (any VoiceTaskConversationStore)?
    private var conversationWorkspaceTurnCursor:
        VoiceTaskConversationTurnCursor?
    private var conversationWorkspaceSession:
        VoiceTaskConversationSession?
    /// ~10Hz keeps the meter lively without spamming the main actor.
    private let inputLevelSampleInterval: TimeInterval = 0.1
    private static let pendingConversationEvidenceBlockingReason =
        "Conversation evidence is being linked before review."
    private static let failedConversationEvidenceBlockingReason =
        "Conversation evidence could not be persisted. Create a new reviewed plan."

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
        conversationOrchestrator: (any VoiceTaskConversationOrchestrating)?,
        conversationCommandPreparer:
            (any VoiceTaskConversationCommandPreparing)? = nil,
        conversationSessionID: UUID,
        inboxCaptureSaver: (any InboxVoiceCaptureSaving)? = nil,
        developmentProjectProvider: @escaping () -> ProjectRecord? = { nil },
        developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder = VoiceDevelopmentPullRequestAutomationRequestBuilder(),
        appSettingsProvider: @escaping @Sendable () -> AppSettings = { .default },
        managedCostRateCardProvider: @escaping @Sendable (PlanningResponse) -> AssistantQueueCostRateCard? = { _ in nil },
        workspaceContextRetriever: (@Sendable (String) throws -> [WorkspaceContextSnippet])? = nil,
        workspaceAnswerReadout: (@Sendable (String) -> Void)? = nil,
        maximumQuickCaptureClarificationTurns: Int? = nil,
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
        let staleRecordingCleanupFailures =
            Self.removeStaleTemporaryVoiceRecordings(
                in: FileManager.default.temporaryDirectory,
                now: Date()
            )
        self.draft = draft
        self.phase = phase
        self.audioRecorder = audioRecorder
        self.sttProvider = sttProvider
        self.llmProvider = llmProvider
        self.auditRecorder = auditRecorder
        self.runtimeValidationMessage = runtimeValidationMessage
        self.assistantQueueStore = assistantQueueStore
        self.commandRouter = commandRouter
        self.conversationOrchestrator = conversationOrchestrator
        self.conversationCommandPreparer = conversationCommandPreparer
        self.conversationSessionID = conversationSessionID
        self.inboxCaptureSaver = inboxCaptureSaver
        self.developmentProjectProvider = developmentProjectProvider
        self.developmentPullRequestAutomationRequestBuilder = developmentPullRequestAutomationRequestBuilder
        self.appSettingsProvider = appSettingsProvider
        self.managedCostRateCardProvider = managedCostRateCardProvider
        self.workspaceContextRetriever = workspaceContextRetriever
        self.workspaceAnswerReadout = workspaceAnswerReadout
        self.maximumQuickCaptureClarificationTurns = maximumQuickCaptureClarificationTurns.map { max(1, $0) }
        self.taskAutomationSettingsProvider = taskAutomationSettingsProvider
        self.lowRiskTaskAutoExecutor = lowRiskTaskAutoExecutor
        self.taskDeleter = taskDeleter
        self.microphoneSilenceDetector = microphoneSilenceDetector
        self.lowLatencySegmentDuration = lowLatencySegmentDuration
        self.lowLatencySegmentOutputURLProvider = lowLatencySegmentOutputURLProvider
        self.recordingState = audioRecorder.state
        self.auditErrorMessage = staleRecordingCleanupFailures == 0
            ? nil
            : "Some expired temporary voice recordings could not be removed."
        self.routingResult = draft.canGeneratePlan ? commandRouter.route(transcript: draft.normalizedText) : nil
        self.clarificationSession = nil
        self.assistantQueueItem = nil
        self.dailyPlanningReviewRequest = nil
        self.inboxTriageRequest = nil
        self.inboxCaptureResult = nil
        self.developmentPullRequestAutomationRequest = nil
        self.lowLatencyVoiceAgentState = .idle
        self.orchestratedClarificationQuestion = nil
        self.liveIntentPreview = nil
        self.inboxTriageCommandParser = InboxVoiceTriageCommandParser()
        self.lastTranscribedAudioURL = nil
        self.savedInboxSourceAudioURL = nil
        self.lowLatencyStreamID = UUID()
        self.activeConversationSourceTurnID = nil
        self.clarificationQuestionCount = 0
        self.conversationCancellationTask = nil
    }

    public convenience init(
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
        maximumQuickCaptureClarificationTurns: Int? = nil,
        taskAutomationSettingsProvider: (@Sendable () -> TaskAutoExecutionSettings)? = nil,
        lowRiskTaskAutoExecutor: (@Sendable (ActionPlan) async throws -> LowRiskAutoCreationOutcome)? = nil,
        taskDeleter: (@Sendable (Int64) throws -> Void)? = nil,
        microphoneSilenceDetector: MicrophoneSilenceDetector = MicrophoneSilenceDetector(),
        lowLatencySegmentDuration: TimeInterval = 1.2,
        lowLatencySegmentOutputURLProvider: @escaping @Sendable () -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "suisui-low-latency-\(UUID().uuidString).m4a"
                )
        }
    ) {
        self.init(
            draft: draft,
            phase: phase,
            audioRecorder: audioRecorder,
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            auditRecorder: auditRecorder,
            runtimeValidationMessage: runtimeValidationMessage,
            assistantQueueStore: assistantQueueStore,
            commandRouter: commandRouter,
            conversationOrchestrator: nil,
            conversationCommandPreparer: nil,
            conversationSessionID: UUID(),
            inboxCaptureSaver: inboxCaptureSaver,
            developmentProjectProvider: developmentProjectProvider,
            developmentPullRequestAutomationRequestBuilder: developmentPullRequestAutomationRequestBuilder,
            appSettingsProvider: appSettingsProvider,
            managedCostRateCardProvider: managedCostRateCardProvider,
            workspaceContextRetriever: workspaceContextRetriever,
            workspaceAnswerReadout: workspaceAnswerReadout,
            maximumQuickCaptureClarificationTurns: maximumQuickCaptureClarificationTurns,
            taskAutomationSettingsProvider: taskAutomationSettingsProvider,
            lowRiskTaskAutoExecutor: lowRiskTaskAutoExecutor,
            taskDeleter: taskDeleter,
            microphoneSilenceDetector: microphoneSilenceDetector,
            lowLatencySegmentDuration: lowLatencySegmentDuration,
            lowLatencySegmentOutputURLProvider: lowLatencySegmentOutputURLProvider
        )
    }

    /// Keeps deletion-failure tests deterministic without changing the public
    /// initializer surface used by OSS clients.
    convenience init(
        audioRecorder: any AudioRecorder,
        sttProvider: any SpeechToTextProvider,
        llmProvider: any LLMProvider,
        inboxCaptureSaver: (any InboxVoiceCaptureSaving)? = nil,
        temporaryRecordingRemover: @escaping @Sendable (URL) throws -> Void
    ) {
        self.init(
            audioRecorder: audioRecorder,
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            inboxCaptureSaver: inboxCaptureSaver
        )
        self.temporaryRecordingRemover = temporaryRecordingRemover
    }

    public var canGeneratePlan: Bool {
        runtimeValidationMessage == nil
            && draft.canGeneratePlan
            && clarificationSession == nil
            && conversationWorkspaceSessionState != .paused
            && conversationWorkspaceSessionState != .archived
            && phase != .generatingPlan
            && phase != .recording
            && phase != .transcribing
    }

    /// Connects the workspace to the same durable SQLite store used by the
    /// orchestrator. Production composition calls this only after migrations
    /// succeed; there is intentionally no in-memory success fallback.
    public func configureConversationWorkspace(
        store: any VoiceTaskConversationStore,
        scope: VoiceTaskConversationWorkspacePresentation.Scope,
        activeProjectID: Int64? = nil,
        activeTaskID: Int64? = nil,
        entryPoint: VoiceTaskConversationEntryPoint = .voiceCommand
    ) {
        conversationWorkspaceStore = store
        conversationWorkspaceScope = scope
        // Scope is shown separately in the workspace header. Calling it a
        // resolved reference would mislead reviewers when speech resolves to
        // a different Task or Project.
        conversationWorkspaceResolvedTarget = nil
        conversationWorkspaceFactCandidates = []
        do {
            let session: VoiceTaskConversationSession
            if var existing = try store.loadSession(id: conversationSessionID) {
                if existing.activeProjectID != activeProjectID
                    || existing.activeTaskID != activeTaskID
                    || existing.title != scope.sessionTitle
                {
                    let expectedUpdatedAt = existing.updatedAt
                    let nextUpdateValue = max(
                        Date().timeIntervalSinceReferenceDate,
                        expectedUpdatedAt.timeIntervalSinceReferenceDate.nextUp
                    )
                    let updatedAt = Date(
                        timeIntervalSinceReferenceDate: nextUpdateValue
                    )
                    try existing.setActiveContext(
                        projectID: activeProjectID,
                        taskID: activeTaskID,
                        resumeSummary: scope.accessibilityValue,
                        at: updatedAt
                    )
                    try existing.updateTitle(
                        scope.sessionTitle,
                        at: updatedAt
                    )
                    try store.updateSession(
                        existing,
                        expectedUpdatedAt: expectedUpdatedAt
                    )
                }
                session = existing
            } else {
                let created = VoiceTaskConversationSession(
                    id: conversationSessionID,
                    title: scope.sessionTitle,
                    entryPoint: entryPoint,
                    activeProjectID: activeProjectID,
                    activeTaskID: activeTaskID,
                    resumeSummary: scope.accessibilityValue
                )
                try store.createSession(created)
                session = created
            }
            conversationWorkspaceSession = session
            conversationWorkspaceSessionState = Self.workspaceState(
                for: session.state
            )
            try reloadConversationWorkspaceTurns()
        } catch {
            conversationWorkspaceTurnListState = .failed(
                message: "Conversation history is unavailable."
            )
            phase = .failed(
                "Voice conversation storage is unavailable."
            )
        }
    }

    public func loadEarlierConversationTurns() {
        guard conversationWorkspaceTurnCursor != nil else { return }
        conversationWorkspaceTurnListState = .loadingMore
        do {
            try reloadConversationWorkspaceTurns(append: true)
        } catch {
            conversationWorkspaceTurnListState = .failed(
                message: "Earlier conversation turns could not be loaded."
            )
        }
    }

    public func updateConversationWorkspaceScope(
        _ scope: VoiceTaskConversationWorkspacePresentation.Scope,
        activeProjectID: Int64?,
        activeTaskID: Int64?
    ) {
        conversationWorkspaceScope = scope
        conversationWorkspaceResolvedTarget = nil
        conversationWorkspaceFactCandidates = []
        mutateConversationWorkspaceSession { session, date in
            try session.updateTitle(scope.sessionTitle, at: date)
            try session.setActiveContext(
                projectID: activeProjectID,
                taskID: activeTaskID,
                resumeSummary: scope.accessibilityValue,
                at: date
            )
        }
    }

    /// Re-reads the Queue source of truth before showing a closeout. A past
    /// conversation message is never treated as proof that execution finished.
    public func refreshConversationWorkspaceCloseout() {
        guard let itemID = assistantQueueItem?.id,
              let assistantQueueStore
        else {
            conversationWorkspaceCloseout = .init()
            return
        }
        do {
            let current = try assistantQueueStore.get(id: itemID)
            assistantQueueItem = current
            switch current.state {
            case .done:
                let actions: [PlanAction]
                if case .actionPlan(let plan) = current.payload {
                    actions = plan.actions
                } else {
                    actions = []
                }
                conversationWorkspaceCloseout = .init(
                    createdCount: actions.filter {
                        $0.tool == .taskCreate
                    }.count,
                    changedCount: actions.filter {
                        $0.tool != .taskCreate
                    }.count
                )
            case .blocked, .failed, .rejected:
                conversationWorkspaceCloseout = .init(
                    unresolvedCount: 1
                )
            case .captured, .interpreted, .drafted, .waitingReview,
                 .approved, .running, .deferred:
                conversationWorkspaceCloseout = .init(
                    pendingCount: 1
                )
            }
        } catch {
            conversationWorkspaceCloseout = .init(unresolvedCount: 1)
        }
    }

    public func pauseConversationWorkspace() {
        mutateConversationWorkspaceSession { session, date in
            try session.pause(at: date)
        }
    }

    public func resumeConversationWorkspace() {
        mutateConversationWorkspaceSession { session, date in
            try session.resume(at: date)
        }
    }

    public func archiveConversationWorkspace() {
        mutateConversationWorkspaceSession { session, date in
            if session.state == .active {
                try session.pause(at: date)
                let nextDate = Date(
                    timeIntervalSinceReferenceDate:
                        session.updatedAt.timeIntervalSinceReferenceDate.nextUp
                )
                try session.archive(at: nextDate)
            } else {
                try session.archive(at: date)
            }
        }
    }

    private func reloadConversationWorkspaceTurns(
        append: Bool = false
    ) throws {
        guard let store = conversationWorkspaceStore else {
            conversationWorkspaceTurnListState = .failed(
                message: "Conversation history is unavailable."
            )
            return
        }
        let page = try store.listTurnPage(
            sessionID: conversationSessionID,
            before: append ? conversationWorkspaceTurnCursor : nil,
            limit: 20
        )
        let rows = page.turns.compactMap(Self.workspaceTurn)
        if append {
            conversationWorkspaceTurns.append(contentsOf: rows)
        } else {
            conversationWorkspaceTurns = rows
        }
        conversationWorkspaceTurns.sort { $0.createdAt < $1.createdAt }
        conversationWorkspaceTurnCursor = page.nextCursor
        conversationWorkspaceTurnListState =
            conversationWorkspaceTurns.isEmpty
            ? .empty
            : .loaded(hasMore: page.nextCursor != nil)
    }

    private func mutateConversationWorkspaceSession(
        _ mutation: (inout VoiceTaskConversationSession, Date) throws -> Void
    ) {
        guard let store = conversationWorkspaceStore,
              var session = conversationWorkspaceSession
        else {
            phase = .failed(
                "Voice conversation storage is unavailable."
            )
            return
        }
        let expectedUpdatedAt = session.updatedAt
        do {
            let now = Date(
                timeIntervalSinceReferenceDate: max(
                    Date().timeIntervalSinceReferenceDate,
                    expectedUpdatedAt.timeIntervalSinceReferenceDate.nextUp
                )
            )
            try mutation(&session, now)
            try store.updateSession(
                session,
                expectedUpdatedAt: expectedUpdatedAt
            )
            conversationWorkspaceSession = session
            conversationWorkspaceSessionState = Self.workspaceState(
                for: session.state
            )
        } catch {
            phase = .failed(
                "Conversation session state could not be saved."
            )
        }
    }

    private static func workspaceState(
        for state: VoiceTaskConversationSessionState
    ) -> VoiceTaskConversationWorkspacePresentation.SessionState? {
        switch state {
        case .active:
            nil
        case .paused:
            .paused
        case .archived:
            .archived
        }
    }

    private static func workspaceTurn(
        _ turn: VoiceTaskConversationTurn
    ) -> VoiceTaskConversationWorkspacePresentation.Turn? {
        let author: VoiceTaskConversationWorkspacePresentation.Turn.Author
        let text: String
        switch turn.author {
        case .user:
            guard let displayText =
                turn.userConfirmedText ?? turn.rawTranscript
            else {
                return nil
            }
            author = .user
            text = displayText
        case .assistant:
            author = .assistant
            text = String(localized: "Structured response recorded.")
        case .system:
            author = .system
            text = String(localized: "Conversation state updated.")
        }
        return .init(
            id: turn.id,
            author: author,
            text: text,
            createdAt: turn.createdAt
        )
    }

    public var canSaveDraftToInbox: Bool {
        inboxCaptureSaver != nil
            && recordedAudio?.fileURL == lastTranscribedAudioURL
            && recordedAudio?.fileURL != savedInboxSourceAudioURL
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
        orchestratedClarificationQuestion ?? clarificationSession?.currentQuestion
    }

    public func restoreConversationIfNeeded() async {
        guard let conversationOrchestrator,
              orchestratedClarificationQuestion == nil,
              clarificationSession == nil
        else {
            return
        }
        await waitForPendingConversationCancellation()
        let sourceTurnID = UUID()
        activeConversationSourceTurnID = sourceTurnID
        let outcome = await conversationOrchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: conversationSessionID,
                sourceTurnID: sourceTurnID,
                event: .restore
            )
        )
        if case .canceled = outcome {
            return
        }
        await applyConversationOutcome(outcome, sourceTurnID: sourceTurnID)
    }

    public func updateDraftText(_ text: String) {
        guard draft.text != text else {
            return
        }
        draft.text = text
        conversationWorkspaceLocalAnswerItems = []
        conversationWorkspaceResolvedTarget = nil
        conversationWorkspaceFactCandidates = []
        planningResponse = nil
        clarificationSession = nil
        cancelOrchestratedClarificationIfNeeded()
        activeConversationSourceTurnID = nil
        clarificationQuestionCount = 0
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
        retryPendingTemporaryRecordingDeletions()
        removeUnsavedTemporaryRecording()
        audioRecorder.reset()
        draft = TranscriptDraft()
        conversationWorkspaceLocalAnswerItems = []
        conversationWorkspaceResolvedTarget = nil
        conversationWorkspaceFactCandidates = []
        planningResponse = nil
        recordedAudio = nil
        auditErrorMessage = nil
        routingResult = nil
        clarificationSession = nil
        cancelOrchestratedClarificationIfNeeded()
        activeConversationSourceTurnID = nil
        clarificationQuestionCount = 0
        assistantQueueItem = nil
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil
        inboxCaptureResult = nil
        lastTranscribedAudioURL = nil
        savedInboxSourceAudioURL = nil
        developmentPullRequestAutomationRequest = nil
        autoCreatedTask = nil
        failureRecovery = nil
        workspaceAnswer = .idle
        recordingState = audioRecorder.state
        phase = runtimeValidationMessage.map(VoiceCapturePhase.failed) ?? .idle
    }

    /// Releases workspace-owned recording resources when its window closes.
    ///
    /// Saved Inbox audio is owned by the Inbox store and is deliberately left
    /// intact; only an unsaved file under the system temporary directory is
    /// eligible for deletion.
    public func releaseTemporaryRecordingResources() {
        stopLowLatencyVoiceAgentMode()
        stopInputLevelMonitoring()
        retryPendingTemporaryRecordingDeletions()
        removeUnsavedTemporaryRecording()
        audioRecorder.reset()
        recordedAudio = nil
        lastTranscribedAudioURL = nil
        recordingState = audioRecorder.state
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
        retryPendingTemporaryRecordingDeletions()
        // Starting another take transfers ownership away from the previous
        // unsaved temporary file. Delete it before the recorder can replace
        // our in-memory reference, while preserving Inbox-owned recordings.
        removeUnsavedTemporaryRecording()
        recordedAudio = nil
        lastTranscribedAudioURL = nil
        if clarificationQuestion == nil {
            clarificationQuestionCount = 0
        }
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
            if clarificationQuestion != nil {
                await submitClarificationAnswer(transcript.text, inputMode: .voice)
                return
            }
            draft = TranscriptDraft(text: transcript.text)
            planningResponse = nil
            clarificationSession = nil
            clarificationQuestionCount = 0
            assistantQueueItem = nil
            dailyPlanningReviewRequest = nil
            inboxTriageRequest = nil
            inboxCaptureResult = nil
            lastTranscribedAudioURL = audio.fileURL
            savedInboxSourceAudioURL = nil
            developmentPullRequestAutomationRequest = nil
            refreshRoutingResult()
            phase = .idle
        } catch {
            removeUnsavedTemporaryRecording()
            lastTranscribedAudioURL = nil
            savedInboxSourceAudioURL = nil
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

        await waitForPendingConversationCancellation()
        let routedCommand = commandRouter.route(transcript: draft.normalizedText)
        let plannedTranscript = routedCommand.normalizedTranscript
        routingResult = routedCommand
        let sourceTurnID = UUID()
        activeConversationSourceTurnID = sourceTurnID

        if let conversationOrchestrator,
           let conversationCommandPreparer
        {
            do {
                if let prepared = try conversationCommandPreparer.prepare(
                    transcript: draft.normalizedText,
                    sessionID: conversationSessionID,
                    sourceTurnID: sourceTurnID,
                    selectedProjectID:
                        conversationWorkspaceSession?.activeProjectID,
                    selectedTaskID:
                        conversationWorkspaceSession?.activeTaskID,
                    at: currentDate
                ) {
                    conversationWorkspaceFactCandidates =
                        prepared.referenceRequest?.confirmedFacts.map {
                            VoiceTaskConversationWorkspacePresentation
                                .FactCandidate(
                                    id: $0.id,
                                    preview: $0.value,
                                    stateLabel: $0.state.rawValue,
                                    sourceLabel: $0.author.rawValue
                                )
                        } ?? []
                    let outcome = await conversationOrchestrator.handle(
                        VoiceTaskConversationInput(
                            sessionID: conversationSessionID,
                            sourceTurnID: sourceTurnID,
                            event: .begin(
                                route: routedCommand,
                                requiredSlots: prepared.requiredSlots,
                                intents: prepared.intents,
                                referenceRequest:
                                    prepared.referenceRequest,
                                localAnswerItems:
                                    prepared.localAnswerItems
                            ),
                            currentDate: currentDate,
                            timeZoneIdentifier: timeZoneIdentifier,
                            availableTools: planningTools(
                                for: routedCommand,
                                requestedAvailableTools: availableTools
                            )
                        )
                    )
                    await applyConversationOutcome(outcome, sourceTurnID: sourceTurnID)
                    return
                }
            } catch {
                phase = .failed(
                    "Voice conversation context could not be prepared safely."
                )
                auditErrorMessage = userMessage(for: error)
                return
            }
        }

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
            if let conversationOrchestrator {
                let outcome = await conversationOrchestrator.handle(
                    VoiceTaskConversationInput(
                        sessionID: conversationSessionID,
                        sourceTurnID: sourceTurnID,
                        event: .begin(
                            route: routedCommand,
                            requiredSlots: [],
                            intents: [],
                            referenceRequest: nil,
                            localAnswerItems: []
                        ),
                        currentDate: currentDate,
                        timeZoneIdentifier: timeZoneIdentifier,
                        availableTools: planningTools(
                            for: routedCommand,
                            requestedAvailableTools: availableTools
                        )
                    )
                )
                await applyConversationOutcome(outcome, sourceTurnID: sourceTurnID)
            } else {
                beginClarification(for: routedCommand)
            }
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
        guard recordedAudio.fileURL != savedInboxSourceAudioURL else {
            auditErrorMessage = "This voice capture is already saved to Inbox."
            return
        }
        guard draft.canGeneratePlan else {
            phase = .failed("Transcript is empty.")
            return
        }

        do {
            let result = try inboxCaptureSaver.saveTranscribedCapture(
                audio: recordedAudio,
                transcript: STTTranscript(text: draft.normalizedText, duration: recordedAudio.duration),
                transcriptionErrorMessage: nil,
                at: date,
                createdAt: createdAt
            )
            if result.capture.audioFilePath != recordedAudio.fileURL.path {
                // The Inbox service has copied the recording into its managed
                // store. The temporary source is no longer needed and must
                // not remain on disk after a successful save.
                removeOwnedTemporaryRecording(at: recordedAudio.fileURL)
            }
            inboxCaptureResult = result
            savedInboxSourceAudioURL = recordedAudio.fileURL
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
        if let conversationOrchestrator,
           orchestratedClarificationQuestion != nil
        {
            guard let sourceTurnID = activeConversationSourceTurnID else { return }
            let outcome = await conversationOrchestrator.handle(
                VoiceTaskConversationInput(
                    sessionID: conversationSessionID,
                    sourceTurnID: UUID(),
                    event: .clarificationAnswer(answer, inputMode: inputMode),
                    currentDate: currentDate,
                    timeZoneIdentifier: timeZoneIdentifier,
                    availableTools: availableTools
                )
            )
            await applyConversationOutcome(outcome, sourceTurnID: sourceTurnID)
            return
        }
        guard var session = clarificationSession else {
            phase = .failed("No clarification is active.")
            return
        }

        switch session.answer(answer, inputMode: inputMode) {
        case .needsClarification:
            let acceptedTurnCount = session.turns.count
            if let maximum = maximumQuickCaptureClarificationTurns,
               acceptedTurnCount >= maximum
            {
                clarificationSession = session
                finishUnresolvedQuickCapture()
                return
            }
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
        clarificationQuestionCount = 0
        cancelOrchestratedClarificationIfNeeded()
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
            self.assistantQueueItem = try transitionAssistantQueueItemIfNeeded(
                expected: assistantQueueItem
            ) { current in
                try AssistantQueueStateMachine.approve(current, reviewerID: reviewerID)
            }
            return true
        } catch {
            refreshAssistantQueueItemAfterMutationFailure(id: assistantQueueItem.id)
            auditErrorMessage = userMessage(for: error)
            return false
        }
    }

    public func deferAssistantQueueItem() {
        guard let assistantQueueItem else {
            return
        }
        do {
            self.assistantQueueItem = try transitionAssistantQueueItemIfNeeded(
                expected: assistantQueueItem,
                AssistantQueueStateMachine.deferForReview
            )
        } catch {
            refreshAssistantQueueItemAfterMutationFailure(id: assistantQueueItem.id)
            auditErrorMessage = userMessage(for: error)
        }
    }

    public func rejectAssistantQueueItem() {
        guard let assistantQueueItem else {
            return
        }
        do {
            self.assistantQueueItem = try transitionAssistantQueueItemIfNeeded(
                expected: assistantQueueItem,
                AssistantQueueStateMachine.rejectForReview
            )
        } catch {
            refreshAssistantQueueItemAfterMutationFailure(id: assistantQueueItem.id)
            auditErrorMessage = userMessage(for: error)
        }
    }

    private func beginClarification(for route: VoiceCommandRoutingResult) {
        let session = ClarificationSession(route: route)
        clarificationSession = session
        clarificationQuestionCount = 1
        phase = .needsClarification(session.currentQuestion?.prompt ?? route.clarificationReason ?? "Voice command needs clarification.")
    }

    private func finishUnresolvedQuickCapture() {
        clarificationSession = nil
        orchestratedClarificationQuestion = nil
        activeConversationSourceTurnID = nil
        planningResponse = nil
        assistantQueueItem = nil
        dailyPlanningReviewRequest = nil
        inboxTriageRequest = nil
        developmentPullRequestAutomationRequest = nil
        if canSaveDraftToInbox {
            saveDraftToInbox()
            if inboxCaptureResult != nil {
                phase = .reviewReady
                auditErrorMessage = "Clarification limit reached; the capture was saved to Inbox for later triage."
                return
            }
        }
        phase = runtimeValidationMessage.map(VoiceCapturePhase.failed) ?? .idle
        auditErrorMessage = "One clarification is allowed. Edit the capture or save it to Inbox."
    }

    private func applyConversationOutcome(
        _ outcome: VoiceTaskConversationOutcome,
        sourceTurnID: UUID
    ) async {
        guard activeConversationSourceTurnID == sourceTurnID else { return }
        let reporter = conversationOrchestrator as? any VoiceTaskConversationResolutionReporting
        let resolved = await reporter?.resolvedReference(sessionID: conversationSessionID)
        guard activeConversationSourceTurnID == sourceTurnID else { return }
        if let resolved {
            conversationWorkspaceResolvedTarget = .init(
                title: resolved.candidate.title,
                reason: resolved.reason
            )
        } else {
            conversationWorkspaceResolvedTarget = nil
        }
        switch outcome {
        case .clarification(let question):
            if let maximum = maximumQuickCaptureClarificationTurns,
               clarificationQuestionCount >= maximum
            {
                // Cancel the persisted checkpoint before claiming that this capture
                // has finished; reopening the window must not restore another question.
                orchestratedClarificationQuestion = question
                cancelOrchestratedClarificationIfNeeded()
                let cancellation = await waitForPendingConversationCancellation()
                guard activeConversationSourceTurnID == sourceTurnID else { return }
                guard cancellation == .canceled else {
                    phase = .failed("Voice conversation could not be canceled safely. Please try again.")
                    return
                }
                finishUnresolvedQuickCapture()
                return
            }
            conversationWorkspaceLocalAnswerItems = []
            clarificationSession = nil
            orchestratedClarificationQuestion = question
            clarificationQuestionCount += 1
            phase = .needsClarification(question.prompt)
        case .review(let plan):
            clarificationQuestionCount = 0
            conversationWorkspaceLocalAnswerItems = []
            orchestratedClarificationQuestion = nil
            let validation = ActionPlanValidator().validate(plan)
            let response = PlanningResponse(
                providerID: "voice-conversation-orchestrator",
                rawContent: "",
                actionPlan: plan,
                validationResult: validation
            )
            planningResponse = response
            guard validation.isValid else {
                phase = .failed("ActionPlan validation failed.")
                return
            }
            do {
                let routedCommand = routingResult
                    ?? commandRouter.route(transcript: plan.userInput)
                guard let queueItem = makeAssistantQueueItem(
                    from: response,
                    routedCommand: routedCommand
                ) else {
                    phase = .failed(
                        "Voice conversation did not produce a reviewable queue item."
                    )
                    return
                }
                let persisted =
                    try await persistConversationQueueItemWithLink(
                    plan: plan,
                    sourceTurnID: sourceTurnID,
                    queueItem: queueItem,
                    at: Date()
                )
                guard activeConversationSourceTurnID == sourceTurnID else { return }
                assistantQueueItem = persisted
                phase = .reviewReady
            } catch {
                guard activeConversationSourceTurnID == sourceTurnID else { return }
                blockConversationQueueItemAfterLinkFailure()
                phase = .failed(
                    "Voice review could not be linked to durable execution evidence."
                )
                auditErrorMessage = userMessage(for: error)
            }
        case .answer(let answer):
            orchestratedClarificationQuestion = nil
            conversationWorkspaceLocalAnswerItems =
                answer.source == .localDeterministic
                ? answer.items
                : []
            workspaceAnswer = .answered(
                text: answer.text,
                contextCount: answer.items.count
            )
            if conversationWorkspaceStore != nil {
                try? reloadConversationWorkspaceTurns()
            }
            phase = .idle
        case .canceled:
            conversationWorkspaceLocalAnswerItems = []
            orchestratedClarificationQuestion = nil
            phase = .idle
        case .blocked:
            conversationWorkspaceLocalAnswerItems = []
            orchestratedClarificationQuestion = nil
            phase = .failed(
                "Voice conversation could not continue safely. Please try again."
            )
        }
    }

    private func cancelOrchestratedClarificationIfNeeded() {
        guard orchestratedClarificationQuestion != nil || activeConversationSourceTurnID != nil,
              let conversationOrchestrator
        else {
            orchestratedClarificationQuestion = nil
            return
        }
        orchestratedClarificationQuestion = nil
        let sessionID = conversationSessionID
        let precedingCancellation = conversationCancellationTask
        conversationCancellationTask = Task {
            _ = await precedingCancellation?.value
            return await conversationOrchestrator.handle(
                VoiceTaskConversationInput(
                    sessionID: sessionID,
                    sourceTurnID: UUID(),
                    event: .cancel
                )
            )
        }
    }

    @discardableResult
    private func waitForPendingConversationCancellation() async -> VoiceTaskConversationOutcome? {
        // Editing stays synchronous for responsive typing, while a replacement
        // command must wait here so an older unstructured cancel cannot erase
        // the replacement checkpoint after it has been persisted.
        return await conversationCancellationTask?.value
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
                var ownedSegmentURL: URL?
                defer {
                    if let ownedSegmentURL {
                        removeOwnedTemporaryRecording(
                            at: ownedSegmentURL
                        )
                    }
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
                    let outputURL =
                        lowLatencySegmentOutputURLProvider()
                    ownedSegmentURL = outputURL
                    let audio = try audioRecorder.stop(
                        outputURL: outputURL,
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

    private func removeUnsavedTemporaryRecording() {
        guard let url = recordedAudio?.fileURL,
              url != savedInboxSourceAudioURL
        else {
            return
        }
        removeOwnedTemporaryRecording(at: url)
    }

    private func removeOwnedTemporaryRecording(at url: URL) {
        let temporaryRoot =
            FileManager.default.temporaryDirectory.standardizedFileURL.path
        let candidate = url.standardizedFileURL
        guard candidate.path.hasPrefix(temporaryRoot + "/") else {
            // Injected recorders may return caller-owned paths. Only production
            // temporary recordings are owned by this workspace.
            return
        }
        do {
            try temporaryRecordingRemover(candidate)
            pendingTemporaryRecordingDeletionURLs.remove(candidate)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            pendingTemporaryRecordingDeletionURLs.remove(candidate)
        } catch {
            // Keep ownership after a transient deletion failure. A later
            // lifecycle boundary retries it, while the startup sweep covers a
            // process crash before that retry can run.
            pendingTemporaryRecordingDeletionURLs.insert(candidate)
        }
    }

    private func retryPendingTemporaryRecordingDeletions() {
        for candidate in pendingTemporaryRecordingDeletionURLs {
            removeOwnedTemporaryRecording(at: candidate)
        }
    }

    /// Sweeps only UUID-named files owned by Suisui and old enough that no
    /// active recording window should still reference them. This bounds raw
    /// audio lifetime after a crash, while avoiding caller-owned temp files.
    @discardableResult
    static func removeStaleTemporaryVoiceRecordings(
        in directory: URL,
        now: Date,
        minimumAge: TimeInterval = 24 * 60 * 60,
        fileManager: FileManager = .default
    ) -> Int {
        let prefixes = [
            "suisui-recording-",
            "suisui-conversation-",
            "suisui-low-latency-",
        ]
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey,
        ]
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 1
        }
        let cutoff = now.addingTimeInterval(-max(0, minimumAge))
        var failures = 0
        for candidate in candidates {
            let name = candidate.lastPathComponent
            guard name.hasSuffix(".m4a"),
                  let prefix = prefixes.first(where: name.hasPrefix)
            else {
                continue
            }
            let identifier = String(
                name.dropFirst(prefix.count).dropLast(".m4a".count)
            )
            guard UUID(uuidString: identifier) != nil,
                  let values = try? candidate.resourceValues(
                      forKeys: keys
                  ),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt <= cutoff
            else {
                continue
            }
            do {
                try fileManager.removeItem(at: candidate)
            } catch let error as CocoaError
                where error.code == .fileNoSuchFile
            {
                // Another window may have completed the same bounded sweep.
            } catch {
                failures += 1
            }
        }
        return failures
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
            requestedActionDraftKind: VoiceDailyPlanningActionDraftClassifier.requestedKind(from: route),
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
            assistantQueueItem = try persistNewAssistantQueueItemIfNeeded(item)
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
            assistantQueueItem = try persistNewAssistantQueueItemIfNeeded(item)
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
            assistantQueueItem = try persistNewAssistantQueueItemIfNeeded(item)
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
        VoiceCommandRouter.matchesSignal(signal, in: foldedTranscript)
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
        let sourceTurnID = activeConversationSourceTurnID
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
                if let plan = response.actionPlan,
                   let queueItem = makeAssistantQueueItem(
                       from: response,
                       routedCommand: routedCommand
                   )
                {
                    let persisted =
                        try await persistConversationQueueItemWithLink(
                        plan: plan,
                        sourceTurnID: sourceTurnID,
                        queueItem: queueItem,
                        at: currentDate
                    )
                    assistantQueueItem = persisted
                }
            } catch {
                blockConversationQueueItemAfterLinkFailure()
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

        if error is AssistantQueueReviewActionUnavailableError {
            return "This Assistant Queue item cannot be changed by that review action in its current state."
        }
        if error is AssistantQueueStaleReviewError {
            return AssistantQueueMutationFailure.staleUserMessage
        }

        return UserFacingErrorMessageSanitizer.message(from: error)
    }

    private func persistNewAssistantQueueItemIfNeeded(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard let assistantQueueStore else {
            return item
        }
        do {
            if let inserted = try assistantQueueStore.insertIfAbsent(item) {
                return inserted
            }
            return try assistantQueueStore.get(id: item.id)
        } catch {
            // Queue persistence is fail-closed because review approval must not
            // happen against work that disappears after a restart.
            throw AssistantQueueStoreError.saveFailed
        }
    }

    private func persistConversationReviewLink(
        plan: ActionPlan,
        sourceTurnID: UUID,
        queueItem: AssistantQueueItem,
        at date: Date
    ) async throws {
        guard let persister = conversationOrchestrator
            as? any VoiceTaskConversationReviewLinkPersisting
        else {
            return
        }
        guard activeConversationSourceTurnID == sourceTurnID else { throw CancellationError() }
        try await persister.persistReviewLink(
            sessionID: conversationSessionID,
            fallbackSourceTurnID: sourceTurnID,
            confirmedText: plan.userInput,
            plan: plan,
            queueItem: queueItem,
            at: date
        )
        guard activeConversationSourceTurnID == sourceTurnID else { throw CancellationError() }
        if conversationWorkspaceStore != nil {
            do {
                try reloadConversationWorkspaceTurns()
            } catch {
                conversationWorkspaceTurnListState = .failed(
                    message: "Conversation history could not be refreshed."
                )
            }
        }
    }

    private func persistConversationQueueItemWithLink(
        plan: ActionPlan,
        sourceTurnID: UUID?,
        queueItem: AssistantQueueItem,
        at date: Date
    ) async throws -> AssistantQueueItem {
        // A configured conversation orchestrator establishes the durable-link
        // contract. Without one, preserve the established single-row queue
        // publication used by legacy/non-conversation planning.
        guard conversationOrchestrator != nil else {
            return try persistNewAssistantQueueItemIfNeeded(queueItem)
        }
        guard let sourceTurnID, activeConversationSourceTurnID == sourceTurnID else {
            throw CancellationError()
        }
        // Conversation Turns are the retention-controlled source of raw STT.
        // The durable Queue keeps the reviewed semantics but must not become a
        // second, indefinitely retained copy of speech the user never confirmed.
        let conversationQueueItem =
            queueItem.minimizingUnapprovedConversationTranscript()
        guard let assistantQueueStore else {
            try await persistConversationReviewLink(
                plan: plan,
                sourceTurnID: sourceTurnID,
                queueItem: conversationQueueItem,
                at: date
            )
            return conversationQueueItem
        }
        guard conversationOrchestrator
                is any VoiceTaskConversationReviewLinkPersisting
        else {
            throw AssistantQueueStoreError.saveFailed
        }

        // These stores cannot share one transaction. Keep the provisional
        // queue row blocked until its causal Action Link is durable, so another
        // window cannot approve unaudited work in the publication gap.
        var provisional = conversationQueueItem
        provisional.state = .blocked
        provisional.approval = nil
        provisional.blockingReason =
            Self.pendingConversationEvidenceBlockingReason
        let persistence = try persistConversationProvisionalIfSafe(
            provisional,
            published: conversationQueueItem
        )
        let persistedItem = persistence.item
        assistantQueueItem = persistedItem
        do {
            if persistence.isAlreadyPublished {
                guard try await hasMatchingPublishedConversationReview(
                    plan: plan,
                    queueItem: persistedItem
                ) else {
                    throw AssistantQueueStaleReviewError()
                }
                guard activeConversationSourceTurnID == sourceTurnID else { throw CancellationError() }
                try await acknowledgeConversationReviewPublication()
                return persistedItem
            }
            try await persistConversationReviewLink(
                plan: plan,
                sourceTurnID: sourceTurnID,
                queueItem: persistedItem,
                at: date
            )
            guard activeConversationSourceTurnID == sourceTurnID else { throw CancellationError() }
            guard let expectedRevision =
                persistedItem.mutationRevision
            else {
                throw AssistantQueueStaleReviewError()
            }
            let published = try assistantQueueStore.transition(
                id: persistedItem.id
            ) { current in
                guard current.mutationRevision == expectedRevision,
                      current.state == .blocked,
                      current.approval == nil,
                      current.blockingReason ==
                        Self.pendingConversationEvidenceBlockingReason,
                      current.contentFingerprint ==
                        persistedItem.contentFingerprint
                else {
                    throw AssistantQueueStaleReviewError()
                }
                var published = current
                published.state = conversationQueueItem.state
                published.blockingReason =
                    conversationQueueItem.blockingReason
                published.approval = nil
                return published
            }
            try await acknowledgeConversationReviewPublication()
            return published
        } catch {
            if activeConversationSourceTurnID != sourceTurnID {
                if !persistence.isAlreadyPublished {
                    // Only this request's still-blocked provisional row can be
                    // rejected. Never mutate a concurrently approved/replaced row.
                    _ = try assistantQueueStore.transition(id: persistedItem.id) { current in
                        guard current.mutationRevision == persistedItem.mutationRevision,
                              current.state == .blocked,
                              current.approval == nil,
                              current.blockingReason == Self.pendingConversationEvidenceBlockingReason,
                              current.contentFingerprint == persistedItem.contentFingerprint else {
                            throw AssistantQueueStaleReviewError()
                        }
                        var canceled = current
                        canceled.state = .rejected
                        canceled.blockingReason = nil
                        return canceled
                    }
                }
            } else {
                blockConversationQueueItemAfterLinkFailure()
            }
            throw error
        }
    }

    private struct ConversationQueuePersistence {
        let item: AssistantQueueItem
        let isAlreadyPublished: Bool
    }

    private func persistConversationProvisionalIfSafe(
        _ provisional: AssistantQueueItem,
        published: AssistantQueueItem
    ) throws -> ConversationQueuePersistence {
        guard let assistantQueueStore else {
            return ConversationQueuePersistence(
                item: provisional,
                isAlreadyPublished: false
            )
        }
        if let inserted = try assistantQueueStore.insertIfAbsent(provisional) {
            return ConversationQueuePersistence(
                item: inserted,
                isAlreadyPublished: false
            )
        }
        let existing = try assistantQueueStore.get(id: provisional.id)
        if existing.state == published.state,
           existing.approval == nil,
           existing.blockingReason == published.blockingReason,
           existing.contentFingerprint == published.contentFingerprint,
           existing.requiresConversationActionLink,
           existing.mutationRevision == published.mutationRevision
        {
            // The link bundle may have committed before the process exited
            // between Queue publication and checkpoint acknowledgement.
            // Revalidate the same review link before acknowledging recovery.
            return ConversationQueuePersistence(
                item: existing,
                isAlreadyPublished: true
            )
        }
        // An ID collision is only a retry when it is exactly the provisional
        // row this flow previously published. Content, state, reason, approval,
        // and revision all participate so approved/running/terminal or foreign
        // work can never be repurposed by a repeated voice request.
        guard existing.state == .blocked,
              existing.approval == nil,
              existing.blockingReason ==
                Self.pendingConversationEvidenceBlockingReason,
              existing.contentFingerprint == provisional.contentFingerprint,
              existing.mutationRevision == provisional.mutationRevision
        else {
            throw AssistantQueueStaleReviewError()
        }
        return ConversationQueuePersistence(
            item: existing,
            isAlreadyPublished: false
        )
    }

    private func acknowledgeConversationReviewPublication() async throws {
        guard let acknowledger = conversationOrchestrator
            as? any VoiceTaskConversationReviewPublicationAcknowledging
        else {
            return
        }
        try await acknowledger.acknowledgeReviewPublication(
            sessionID: conversationSessionID
        )
    }

    private func hasMatchingPublishedConversationReview(
        plan: ActionPlan,
        queueItem: AssistantQueueItem
    ) async throws -> Bool {
        guard let reconciler = conversationOrchestrator
            as? any VoiceTaskConversationReviewPublicationReconciling
        else {
            return false
        }
        return try await reconciler.hasMatchingPublishedReview(
            sessionID: conversationSessionID,
            plan: plan,
            queueItem: queueItem
        )
    }

    private func blockConversationQueueItemAfterLinkFailure() {
        guard let queueItem = assistantQueueItem else {
            return
        }
        // A Voice-created queue item without its causal ActionLink must never
        // become executable. Persist a visible blocked state so reopening the
        // app cannot turn a transient linkage failure into unaudited work.
        guard let assistantQueueStore,
              let expectedRevision = queueItem.mutationRevision
        else {
            var blocked = queueItem
            blocked.state = .blocked
            blocked.approval = nil
            blocked.blockingReason =
                Self.failedConversationEvidenceBlockingReason
            assistantQueueItem = blocked
            return
        }
        let blocked: AssistantQueueItem
        do {
            blocked = try assistantQueueStore.transition(
                id: queueItem.id
            ) { current in
                guard current.mutationRevision == expectedRevision,
                      current.state == .blocked,
                      current.approval == nil,
                      current.blockingReason ==
                        Self.pendingConversationEvidenceBlockingReason,
                      current.contentFingerprint ==
                        queueItem.contentFingerprint
                else {
                    throw AssistantQueueStaleReviewError()
                }
                var failed = current
                failed.blockingReason =
                    Self.failedConversationEvidenceBlockingReason
                return failed
            }
        } catch {
            refreshAssistantQueueItemAfterMutationFailure(id: queueItem.id)
            return
        }
        assistantQueueItem = blocked
    }

    private func transitionAssistantQueueItemIfNeeded(
        expected item: AssistantQueueItem,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        guard let assistantQueueStore else {
            return try transform(item)
        }
        guard let expectedRevision = item.mutationRevision else {
            throw AssistantQueueStaleReviewError()
        }
        return try assistantQueueStore.transition(id: item.id) { current in
            guard current.mutationRevision == expectedRevision else {
                throw AssistantQueueStaleReviewError()
            }
            return try transform(current)
        }
    }

    private func refreshAssistantQueueItemAfterMutationFailure(id: String) {
        guard let assistantQueueStore,
              let latest = try? assistantQueueStore.get(id: id) else {
            return
        }
        // A failed optimistic mutation must show the durable item that caused
        // the conflict; otherwise the recovery message points at stale UI.
        assistantQueueItem = latest
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
