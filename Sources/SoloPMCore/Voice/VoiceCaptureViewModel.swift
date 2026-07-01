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
    @Published public private(set) var recordingState: AudioRecordingState
    @Published public private(set) var planningResponse: PlanningResponse?
    @Published public private(set) var recordedAudio: RecordedAudio?
    @Published public private(set) var auditErrorMessage: String?
    @Published public private(set) var routingResult: VoiceCommandRoutingResult?
    @Published public private(set) var clarificationSession: ClarificationSession?
    @Published public private(set) var assistantQueueItem: AssistantQueueItem?
    @Published public private(set) var dailyPlanningReviewRequest: VoiceDailyPlanningReviewRequest?
    @Published public private(set) var inboxTriageRequest: VoiceInboxTriageRequest?
    @Published public private(set) var developmentPullRequestAutomationRequest: SyncAutomationRequestPayload?

    private var audioRecorder: any AudioRecorder
    private let sttProvider: any SpeechToTextProvider
    private let llmProvider: any LLMProvider
    private let auditRecorder: PlanningAuditRecorder?
    private let runtimeValidationMessage: String?
    private let assistantQueueStore: (any AssistantQueueStore)?
    private let commandRouter: any VoiceCommandRouting
    private let inboxTriageCommandParser: InboxVoiceTriageCommandParser
    private let developmentProjectProvider: () -> ProjectRecord?
    private let developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder

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
        developmentProjectProvider: @escaping () -> ProjectRecord? = { nil },
        developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder = VoiceDevelopmentPullRequestAutomationRequestBuilder()
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
        self.developmentProjectProvider = developmentProjectProvider
        self.developmentPullRequestAutomationRequestBuilder = developmentPullRequestAutomationRequestBuilder
        self.recordingState = audioRecorder.state
        self.auditErrorMessage = nil
        self.routingResult = draft.canGeneratePlan ? commandRouter.route(transcript: draft.normalizedText) : nil
        self.clarificationSession = nil
        self.assistantQueueItem = nil
        self.dailyPlanningReviewRequest = nil
        self.inboxTriageRequest = nil
        self.developmentPullRequestAutomationRequest = nil
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
        developmentPullRequestAutomationRequest = nil
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
        developmentPullRequestAutomationRequest = nil
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
            developmentPullRequestAutomationRequest = nil
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
        let rejectsAction = containsAny(
            ["do not", "don't", "dont", "not start", "not defer", "cancel", "しない", "始めない", "開始しない", "延期しない", "やめ"],
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
        guard rejectsAction == false, asksForAdvice == false, requestsStart != requestsDefer else {
            return nil
        }
        return requestsStart ? .startRecommended : .deferRecommendedToTomorrow
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
        developmentPullRequestAutomationRequest = nil

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
        developmentPullRequestAutomationRequest = nil
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
        if isLocalProvider(response.providerID) {
            return .localOnly(model: model, observedUsage: observedUsage)
        }

        // Provider planning usage is already incurred before local execution.
        // Store it as BYOK/provider-billed telemetry so receipts can audit token
        // usage without treating it as a SoloPM-managed pre-run charge.
        return .userProviderBilled(
            provider: model.provider,
            modelName: model.name,
            observedUsage: observedUsage
        )
    }

    private func isLocalProvider(_ providerID: String) -> Bool {
        let normalized = providerID.lowercased()
        return normalized.contains("ollama") || normalized.contains("local")
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
