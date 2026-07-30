import Foundation

private struct VoiceTaskConversationReviewStateMismatchError: Error {}

public struct VoiceTaskConversationAnswerItem: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public enum VoiceTaskConversationAnswerSource: String, Codable, Equatable, Sendable {
    case localDeterministic = "local_deterministic"
    case provider
}

public struct VoiceTaskConversationAnswer: Codable, Equatable, Sendable {
    public let text: String
    public let items: [VoiceTaskConversationAnswerItem]
    public let source: VoiceTaskConversationAnswerSource

    public init(
        text: String,
        items: [VoiceTaskConversationAnswerItem] = [],
        source: VoiceTaskConversationAnswerSource
    ) {
        self.text = text
        self.items = items
        self.source = source
    }
}

public enum VoiceTaskConversationBlockReason: Equatable, Sendable {
    case providerUnavailable
    case persistenceUnavailable
    case contextUnavailable
    case referenceUnavailable
    case invalidPlan
    case missingClarificationState
}

public enum VoiceTaskConversationOutcome: Equatable, Sendable {
    case answer(VoiceTaskConversationAnswer)
    case clarification(ClarificationQuestion)
    case review(ActionPlan)
    case canceled
    case blocked(VoiceTaskConversationBlockReason)
}

public struct VoiceTaskConversationOrchestrationState: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let originalSourceTurnID: UUID
    public let route: VoiceCommandRoutingResult
    public let intents: [ConversationTaskIntent]
    public var clarification: ClarificationSession
    public var referenceCandidates: [ConversationReferenceCandidate]?
    public var referenceClarificationTurns: [ClarificationTurn]
    public var resolvedReferenceCandidate: ConversationReferenceCandidate?
    public var resolvedReferenceReason: String?
    public var pendingReviewPlan: ActionPlan?

    public init(
        sessionID: UUID,
        originalSourceTurnID: UUID,
        route: VoiceCommandRoutingResult,
        intents: [ConversationTaskIntent],
        clarification: ClarificationSession,
        referenceCandidates: [ConversationReferenceCandidate]? = nil,
        referenceClarificationTurns: [ClarificationTurn] = [],
        resolvedReferenceCandidate: ConversationReferenceCandidate? = nil,
        resolvedReferenceReason: String? = nil,
        pendingReviewPlan: ActionPlan? = nil
    ) {
        self.sessionID = sessionID
        self.originalSourceTurnID = originalSourceTurnID
        self.route = route
        self.intents = intents
        self.clarification = clarification
        self.referenceCandidates = referenceCandidates
        self.referenceClarificationTurns = referenceClarificationTurns
        self.resolvedReferenceCandidate = resolvedReferenceCandidate
        self.resolvedReferenceReason = resolvedReferenceReason
        self.pendingReviewPlan = pendingReviewPlan
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case originalSourceTurnID
        case route
        case intents
        case clarification
        case referenceCandidates
        case referenceClarificationTurns
        case resolvedReferenceCandidate
        case resolvedReferenceReason
        case pendingReviewPlan
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try values.decode(UUID.self, forKey: .sessionID),
            originalSourceTurnID: try values.decode(
                UUID.self,
                forKey: .originalSourceTurnID
            ),
            route: try values.decode(
                VoiceCommandRoutingResult.self,
                forKey: .route
            ),
            intents: try values.decode(
                [ConversationTaskIntent].self,
                forKey: .intents
            ),
            clarification: try values.decode(
                ClarificationSession.self,
                forKey: .clarification
            ),
            referenceCandidates: try values.decodeIfPresent(
                [ConversationReferenceCandidate].self,
                forKey: .referenceCandidates
            ),
            referenceClarificationTurns: try values.decodeIfPresent(
                [ClarificationTurn].self,
                forKey: .referenceClarificationTurns
            ) ?? [],
            resolvedReferenceCandidate: try values.decodeIfPresent(
                ConversationReferenceCandidate.self,
                forKey: .resolvedReferenceCandidate
            ),
            resolvedReferenceReason: try values.decodeIfPresent(
                String.self,
                forKey: .resolvedReferenceReason
            ),
            pendingReviewPlan: try values.decodeIfPresent(
                ActionPlan.self,
                forKey: .pendingReviewPlan
            )
        )
    }
}

public protocol VoiceTaskConversationOrchestrationStateStore: Sendable {
    func load(sessionID: UUID) throws -> VoiceTaskConversationOrchestrationState?
    func save(_ state: VoiceTaskConversationOrchestrationState) throws
    func remove(sessionID: UUID) throws
}

public enum VoiceTaskConversationEvent: Sendable {
    case restore
    case begin(
        route: VoiceCommandRoutingResult,
        requiredSlots: [ClarificationSlot],
        intents: [ConversationTaskIntent],
        referenceRequest: VoiceTaskReferenceRequest?,
        localAnswerItems: [VoiceTaskConversationAnswerItem]
    )
    case clarificationAnswer(String, inputMode: ClarificationInputMode = .typed)
    case cancel
}

public struct VoiceTaskConversationInput: Sendable {
    public let sessionID: UUID
    public let sourceTurnID: UUID
    public let event: VoiceTaskConversationEvent
    public let contextInput: VoiceTaskContextInput?
    public let contextBudget: VoiceTaskContextBudget
    public let currentDate: Date
    public let timeZoneIdentifier: String
    public let availableTools: [ActionTool]

    public init(
        sessionID: UUID,
        sourceTurnID: UUID,
        event: VoiceTaskConversationEvent,
        contextInput: VoiceTaskContextInput? = nil,
        contextBudget: VoiceTaskContextBudget = .init(
            maximumTurns: 12,
            maximumCharacters: 8_000
        ),
        currentDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        availableTools: [ActionTool] = ActionTool.defaultPlanningTools
    ) {
        self.sessionID = sessionID
        self.sourceTurnID = sourceTurnID
        self.event = event
        self.contextInput = contextInput
        self.contextBudget = contextBudget
        self.currentDate = currentDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.availableTools = availableTools
    }
}

public protocol VoiceTaskConversationOrchestrating: Sendable {
    func handle(_ input: VoiceTaskConversationInput) async -> VoiceTaskConversationOutcome
}

public struct VoiceTaskConversationResolvedReference:
    Equatable,
    Sendable
{
    public let candidate: ConversationReferenceCandidate
    public let reason: String

    public init(
        candidate: ConversationReferenceCandidate,
        reason: String
    ) {
        self.candidate = candidate
        self.reason = reason
    }
}

public protocol VoiceTaskConversationResolutionReporting: Sendable {
    func resolvedReference(
        sessionID: UUID
    ) async -> VoiceTaskConversationResolvedReference?
}

public protocol VoiceTaskConversationReviewLinkPersisting: Sendable {
    func persistReviewLink(
        sessionID: UUID,
        fallbackSourceTurnID: UUID,
        confirmedText: String,
        plan: ActionPlan,
        queueItem: AssistantQueueItem,
        at date: Date
    ) async throws
}

public protocol VoiceTaskConversationReviewPublicationAcknowledging: Sendable {
    func acknowledgeReviewPublication(sessionID: UUID) async throws
}

public protocol VoiceTaskConversationReviewPublicationReconciling: Sendable {
    func hasMatchingPublishedReview(
        sessionID: UUID,
        plan: ActionPlan,
        queueItem: AssistantQueueItem
    ) async throws -> Bool
}

public protocol VoiceTaskReferenceResolving: Sendable {
    func resolve(_ request: VoiceTaskReferenceRequest) -> VoiceTaskReferenceResolution
}

extension VoiceTaskReferenceResolver: VoiceTaskReferenceResolving {}

public protocol VoiceTaskContextAssembling: Sendable {
    func assemble(
        _ input: VoiceTaskContextInput,
        budget: VoiceTaskContextBudget
    ) throws -> VoiceTaskContextAssembly
}

extension VoiceTaskContextAssembler: VoiceTaskContextAssembling {}

public actor VoiceTaskConversationOrchestrator:
    VoiceTaskConversationOrchestrating,
    VoiceTaskConversationResolutionReporting,
    VoiceTaskConversationReviewLinkPersisting,
    VoiceTaskConversationReviewPublicationAcknowledging,
    VoiceTaskConversationReviewPublicationReconciling
{
    private let stateStore: any VoiceTaskConversationOrchestrationStateStore
    private let referenceResolver: any VoiceTaskReferenceResolving
    private let contextAssembler: any VoiceTaskContextAssembling
    private let provider: (any LLMProvider)?
    private let validator: ActionPlanValidator
    private let conversationStore:
        (any VoiceTaskConversationStore & ConversationActionLinkStore)?
    private let taskSnapshotFingerprintProvider:
        @Sendable (Int64) throws -> String?
    private var pendingReviewSourceTurnIDs: [UUID: UUID] = [:]
    private var pendingReviewClarificationTurns:
        [UUID: [ClarificationTurn]] = [:]

    public init(
        stateStore: any VoiceTaskConversationOrchestrationStateStore,
        referenceResolver: any VoiceTaskReferenceResolving = VoiceTaskReferenceResolver(),
        contextAssembler: any VoiceTaskContextAssembling = VoiceTaskContextAssembler(),
        provider: (any LLMProvider)? = nil,
        validator: ActionPlanValidator = ActionPlanValidator()
    ) {
        self.stateStore = stateStore
        self.referenceResolver = referenceResolver
        self.contextAssembler = contextAssembler
        self.provider = provider
        self.validator = validator
        conversationStore = nil
        taskSnapshotFingerprintProvider = { _ in nil }
    }

    public init(
        stateStore: any VoiceTaskConversationOrchestrationStateStore,
        conversationStore:
            any VoiceTaskConversationStore & ConversationActionLinkStore,
        taskSnapshotFingerprintProvider:
            @escaping @Sendable (Int64) throws -> String? = { _ in nil },
        referenceResolver: any VoiceTaskReferenceResolving =
            VoiceTaskReferenceResolver(),
        contextAssembler: any VoiceTaskContextAssembling =
            VoiceTaskContextAssembler(),
        provider: (any LLMProvider)? = nil,
        validator: ActionPlanValidator = ActionPlanValidator()
    ) {
        self.stateStore = stateStore
        self.referenceResolver = referenceResolver
        self.contextAssembler = contextAssembler
        self.provider = provider
        self.validator = validator
        self.conversationStore = conversationStore
        self.taskSnapshotFingerprintProvider =
            taskSnapshotFingerprintProvider
    }

    public func handle(_ input: VoiceTaskConversationInput) async -> VoiceTaskConversationOutcome {
        switch input.event {
        case .restore:
            do {
                guard let state = try stateStore.load(
                    sessionID: input.sessionID
                ) else {
                    return .canceled
                }
                if let plan = state.pendingReviewPlan {
                    let outcome = VoiceTaskConversationOutcome.review(plan)
                    rememberReviewSource(
                        outcome,
                        sessionID: input.sessionID,
                        sourceTurnID: state.originalSourceTurnID,
                        clarificationTurns:
                            clarificationTurns(in: state)
                    )
                    return outcome
                }
                if state.referenceCandidates != nil {
                    return .clarification(
                        referenceClarificationQuestion
                    )
                }
                guard let question = state.clarification.currentQuestion else {
                    return .blocked(.invalidPlan)
                }
                return .clarification(question)
            } catch {
                return .blocked(.persistenceUnavailable)
            }

        case .cancel:
            do {
                try stateStore.remove(sessionID: input.sessionID)
                return .canceled
            } catch {
                return .blocked(.persistenceUnavailable)
            }

        case let .clarificationAnswer(answer, inputMode):
            return await resumeClarification(
                input: input,
                answer: answer,
                inputMode: inputMode
            )

        case let .begin(route, requiredSlots, intents, referenceRequest, localAnswerItems):
            let resolvedIntents: [ConversationTaskIntent]
            var resolvedReferenceCandidate:
                ConversationReferenceCandidate? = nil
            var resolvedReferenceReason: String? = nil
            if let referenceRequest {
                switch referenceResolver.resolve(referenceRequest) {
                case let .resolved(target, reason):
                    resolvedIntents = applying(
                        target: target,
                        to: intents
                    )
                    resolvedReferenceCandidate =
                        referenceRequest.candidates.first {
                            $0.target == target
                        }
                    resolvedReferenceReason =
                        Self.resolutionReasonLabel(reason)
                case let .needsClarification(candidates):
                    guard !candidates.isEmpty else {
                        return .blocked(.referenceUnavailable)
                    }
                    let clarification = ClarificationSession(
                        route: route,
                        requiredSlots: [.taskTitle]
                    )
                    guard let question = clarification.currentQuestion else {
                        return .blocked(.invalidPlan)
                    }
                    let state = VoiceTaskConversationOrchestrationState(
                        sessionID: input.sessionID,
                        originalSourceTurnID: input.sourceTurnID,
                        route: route,
                        intents: intents,
                        clarification: clarification,
                        referenceCandidates: candidates
                    )
                    do {
                        try saveOrchestrationState(state)
                        return .clarification(
                            ClarificationQuestion(
                                slot: question.slot,
                                prompt:
                                    referenceClarificationQuestion.prompt
                            )
                        )
                    } catch {
                        return .blocked(.persistenceUnavailable)
                    }
                case .unavailable:
                    return .blocked(.referenceUnavailable)
                }
            } else {
                resolvedIntents = intents
            }

            // A deterministic preparer has already converted the utterance
            // into typed intents. In that case the generic router's low
            // confidence must not invent an unrelated clarification (for
            // example, asking for a project after a scoped "List tasks").
            // Explicit missing slots still win and are asked one at a time.
            if !requiredSlots.isEmpty
                || (resolvedIntents.isEmpty && route.needsClarification)
            {
                let clarification = ClarificationSession(
                    route: route,
                    requiredSlots: requiredSlots.isEmpty ? nil : requiredSlots
                )
                guard let question = clarification.currentQuestion else {
                    return .blocked(.invalidPlan)
                }
                let state = VoiceTaskConversationOrchestrationState(
                    sessionID: input.sessionID,
                    originalSourceTurnID: input.sourceTurnID,
                    route: route,
                    intents: resolvedIntents,
                    clarification: clarification
                )
                do {
                    try saveOrchestrationState(state)
                    return .clarification(question)
                } catch {
                    return .blocked(.persistenceUnavailable)
                }
            }

            if !resolvedIntents.isEmpty,
               resolvedIntents.allSatisfy({ $0.operation == .list })
            {
                let text = localAnswerItems.isEmpty
                    ? "No matching tasks were found."
                    : localAnswerItems.map(\.label).joined(separator: "\n")
                return .answer(
                    VoiceTaskConversationAnswer(
                        text: text,
                        items: localAnswerItems,
                        source: .localDeterministic
                    )
                )
            }

            if !resolvedIntents.isEmpty {
                let outcome = reviewOutcome(
                    intents: resolvedIntents,
                    originalTranscript: route.originalTranscript
                )
                let state = VoiceTaskConversationOrchestrationState(
                    sessionID: input.sessionID,
                    originalSourceTurnID: input.sourceTurnID,
                    route: route,
                    intents: resolvedIntents,
                    clarification: ClarificationSession(
                        route: route,
                        requiredSlots: []
                    ),
                    resolvedReferenceCandidate:
                        resolvedReferenceCandidate,
                    resolvedReferenceReason: resolvedReferenceReason
                )
                return persistPendingReviewOutcome(
                    outcome,
                    state: state,
                    sessionID: input.sessionID,
                    clarificationTurns: []
                )
            }

            let outcome = await providerOutcome(input: input, route: route)
            let state = VoiceTaskConversationOrchestrationState(
                sessionID: input.sessionID,
                originalSourceTurnID: input.sourceTurnID,
                route: route,
                intents: [],
                clarification: ClarificationSession(
                    route: route,
                    requiredSlots: []
                ),
                resolvedReferenceCandidate:
                    resolvedReferenceCandidate,
                resolvedReferenceReason: resolvedReferenceReason
            )
            return persistPendingReviewOutcome(
                outcome,
                state: state,
                sessionID: input.sessionID,
                clarificationTurns: []
            )
        }
    }

    public func resolvedReference(
        sessionID: UUID
    ) -> VoiceTaskConversationResolvedReference? {
        guard let state = try? stateStore.load(sessionID: sessionID),
              let candidate = state.resolvedReferenceCandidate
        else {
            return nil
        }
        return VoiceTaskConversationResolvedReference(
            candidate: candidate,
            reason: state.resolvedReferenceReason
                ?? "Resolved from the current conversation."
        )
    }

    public func persistReviewLink(
        sessionID: UUID,
        fallbackSourceTurnID: UUID,
        confirmedText: String,
        plan: ActionPlan,
        queueItem: AssistantQueueItem,
        at date: Date
    ) async throws {
        guard let conversationStore else {
            // The original initializer remains source-compatible for Core-only
            // clients. Production uses the persistence-enabled initializer;
            // callers that deliberately construct the legacy variant keep the
            // pre-link behavior instead of failing an otherwise valid review.
            return
        }
        let durableState = try stateStore.load(sessionID: sessionID)
        guard durableState?.pendingReviewPlan == plan else {
            throw VoiceTaskConversationReviewStateMismatchError()
        }
        let sourceTurnID = durableState?.originalSourceTurnID
            ?? pendingReviewSourceTurnIDs[sessionID]
            ?? fallbackSourceTurnID
        let clarificationTurns = durableState.map(
            clarificationTurns(in:)
        ) ?? pendingReviewClarificationTurns[sessionID] ?? []
        if try conversationStore.loadSession(id: sessionID) == nil {
            try conversationStore.createSession(
                VoiceTaskConversationSession(
                    id: sessionID,
                    title: "Voice task conversation",
                    entryPoint: .voiceCommand,
                    createdAt: date
                )
            )
        }
        var turns = try [
            VoiceTaskConversationTurn(
                id: sourceTurnID,
                sessionID: sessionID,
                author: .user,
                // Planning does not itself prove the user confirmed the STT
                // wording. Keep it in the transcript retention class instead
                // of promoting it to indefinitely retained confirmed text.
                // The durable route is the captured user input; a provider's
                // ActionPlan.userInput is not trusted as transcript evidence.
                rawTranscript: durableState?.route.originalTranscript,
                userConfirmedText: nil,
                createdAt: date
            ),
        ]
        for (index, turn) in clarificationTurns.enumerated() {
            let offset = Double(index * 2 + 1) / 1_000_000
            turns.append(
                try VoiceTaskConversationTurn(
                    sessionID: sessionID,
                    author: .assistant,
                    rawTranscript: turn.question.prompt,
                    userConfirmedText: nil,
                    createdAt: date.addingTimeInterval(offset)
                )
            )
            turns.append(
                try VoiceTaskConversationTurn(
                    sessionID: sessionID,
                    author: .user,
                    // A typed answer is explicit text confirmation. A voice
                    // answer is still unconfirmed STT and must remain under
                    // the shorter raw-transcript retention policy.
                    rawTranscript: turn.inputMode == .voice
                        ? turn.answer.planningValue : nil,
                    userConfirmedText: turn.inputMode == .typed
                        ? turn.answer.planningValue : nil,
                    createdAt: date.addingTimeInterval(
                        offset + 1 / 1_000_000
                    )
                )
            )
        }
        let actionLink =
            try ConversationActionLinkCoordinator().makeReviewLink(
                sessionID: sessionID,
                sourceTurnID: sourceTurnID,
                plan: plan,
                queueItem: queueItem,
                taskSnapshotFingerprintProvider:
                    taskSnapshotFingerprintProvider
            )
        // SQLite commits the complete review trail and its causal link in one
        // transaction. Custom stores retain ordered compatibility behavior,
        // while production cannot expose a partial review after a crash.
        try conversationStore.saveReviewBundle(
            turns: turns,
            actionLink: actionLink
        )
    }

    public func acknowledgeReviewPublication(
        sessionID: UUID
    ) async throws {
        try stateStore.remove(sessionID: sessionID)
        pendingReviewSourceTurnIDs.removeValue(forKey: sessionID)
        pendingReviewClarificationTurns.removeValue(forKey: sessionID)
    }

    public func hasMatchingPublishedReview(
        sessionID: UUID,
        plan: ActionPlan,
        queueItem: AssistantQueueItem
    ) async throws -> Bool {
        guard let conversationStore,
              let link = try conversationStore.latestActionLink(
                  assistantQueueItemID: queueItem.id
              )
        else {
            return false
        }
        return link.sessionID == sessionID
            && link.actionPlanID == plan.id
            && link.assistantQueueItemID == queueItem.id
            && link.reviewedFingerprint == queueItem.contentFingerprint
    }

    private func resumeClarification(
        input: VoiceTaskConversationInput,
        answer: String,
        inputMode: ClarificationInputMode
    ) async -> VoiceTaskConversationOutcome {
        let loadedState: VoiceTaskConversationOrchestrationState
        do {
            guard let state = try stateStore.load(sessionID: input.sessionID) else {
                return .blocked(.missingClarificationState)
            }
            loadedState = state
        } catch {
            return .blocked(.persistenceUnavailable)
        }

        var state = loadedState
        if let plan = state.pendingReviewPlan {
            let outcome = VoiceTaskConversationOutcome.review(plan)
            rememberReviewSource(
                outcome,
                sessionID: input.sessionID,
                sourceTurnID: state.originalSourceTurnID,
                clarificationTurns: clarificationTurns(in: state)
            )
            return outcome
        }
        if let referenceCandidates = state.referenceCandidates {
            return resumeReferenceClarification(
                input: input,
                answer: answer,
                inputMode: inputMode,
                state: state,
                candidates: referenceCandidates
            )
        }
        switch state.clarification.answer(answer, inputMode: inputMode) {
        case .needsClarification:
            do {
                try saveOrchestrationState(state)
                guard let question = state.clarification.currentQuestion else {
                    return .blocked(.invalidPlan)
                }
                return .clarification(question)
            } catch {
                return .blocked(.persistenceUnavailable)
            }

        case .resolved:
            guard let result = state.clarification.result else {
                return .blocked(.invalidPlan)
            }
            let intents = applying(
                clarificationAnswers: result.answers,
                to: state.intents
            )
            let outcome: VoiceTaskConversationOutcome
            guard !intents.isEmpty else {
                outcome = await providerOutcome(
                    input: input,
                    route: result.resolvedRoute
                )
                return persistPendingReviewOutcome(
                    outcome,
                    state: state,
                    sessionID: input.sessionID,
                    clarificationTurns: result.turns
                )
            }
            outcome = reviewOutcome(
                intents: intents,
                originalTranscript: result.originalTranscript
            )
            return persistPendingReviewOutcome(
                outcome,
                state: state,
                sessionID: input.sessionID,
                clarificationTurns: result.turns
            )
        }
    }

    private func resumeReferenceClarification(
        input: VoiceTaskConversationInput,
        answer: String,
        inputMode: ClarificationInputMode,
        state: VoiceTaskConversationOrchestrationState,
        candidates: [ConversationReferenceCandidate]
    ) -> VoiceTaskConversationOutcome {
        let clarificationTurn = ClarificationTurn(
            slot: .taskTitle,
            question: referenceClarificationQuestion,
            response: answer,
            answer: .text(answer),
            inputMode: inputMode
        )
        let request = VoiceTaskReferenceRequest(
            sessionID: input.sessionID,
            utterance: answer,
            candidateOrderingFingerprint:
                VoiceTaskReferenceResolver.orderingFingerprint(
                    for: candidates
                ),
            candidates: candidates
        )
        switch referenceResolver.resolve(request) {
        case let .resolved(target, reason):
            let outcome = reviewOutcome(
                intents: applying(target: target, to: state.intents),
                originalTranscript: state.route.originalTranscript
            )
            var pendingState = state
            pendingState.referenceClarificationTurns.append(
                clarificationTurn
            )
            pendingState.resolvedReferenceCandidate =
                candidates.first { $0.target == target }
            pendingState.resolvedReferenceReason =
                Self.resolutionReasonLabel(reason)
            return persistPendingReviewOutcome(
                outcome,
                state: pendingState,
                sessionID: input.sessionID,
                clarificationTurns:
                    pendingState.referenceClarificationTurns
            )
        case let .needsClarification(narrowedCandidates):
            guard !narrowedCandidates.isEmpty else {
                return .blocked(.referenceUnavailable)
            }
            var narrowedState = state
            narrowedState.referenceCandidates = narrowedCandidates
            narrowedState.referenceClarificationTurns.append(
                clarificationTurn
            )
            do {
                try saveOrchestrationState(narrowedState)
                return .clarification(
                    referenceClarificationQuestion
                )
            } catch {
                return .blocked(.persistenceUnavailable)
            }
        case .unavailable:
            return .blocked(.referenceUnavailable)
        }
    }

    private func rememberReviewSource(
        _ outcome: VoiceTaskConversationOutcome,
        sessionID: UUID,
        sourceTurnID: UUID,
        clarificationTurns: [ClarificationTurn] = []
    ) {
        guard case .review = outcome else {
            return
        }
        pendingReviewSourceTurnIDs[sessionID] = sourceTurnID
        pendingReviewClarificationTurns[sessionID] = clarificationTurns
    }

    private var referenceClarificationQuestion: ClarificationQuestion {
        ClarificationQuestion(
            slot: .taskTitle,
            prompt: "Which task or project did you mean?"
        )
    }

    private static func resolutionReasonLabel(
        _ reason: VoiceTaskReferenceResolutionReason
    ) -> String {
        switch reason {
        case .explicitIdentifier:
            "Matched an explicit identifier."
        case .selectedTask:
            "Matched the selected Task."
        case .selectedProject:
            "Matched the selected Project."
        case .previousActionLink:
            "Matched the previous reviewed action."
        case .stableOrdinal:
            "Matched the reviewed list position."
        case .uniqueCandidate:
            "Matched a unique name."
        case .confirmedFact:
            "Matched a user-confirmed fact."
        }
    }

    private func clarificationTurns(
        in state: VoiceTaskConversationOrchestrationState
    ) -> [ClarificationTurn] {
        if !state.referenceClarificationTurns.isEmpty {
            return state.referenceClarificationTurns
        }
        return state.clarification.result?.turns
            ?? state.clarification.turns
    }

    private func persistPendingReviewOutcome(
        _ outcome: VoiceTaskConversationOutcome,
        state: VoiceTaskConversationOrchestrationState,
        sessionID: UUID,
        clarificationTurns: [ClarificationTurn]
    ) -> VoiceTaskConversationOutcome {
        guard case .review(let plan) = outcome else {
            do {
                // Terminal non-review outcomes must not retain the raw route in
                // a checkpoint that cannot be resumed into useful work.
                try stateStore.remove(sessionID: sessionID)
                pendingReviewSourceTurnIDs.removeValue(forKey: sessionID)
                pendingReviewClarificationTurns.removeValue(forKey: sessionID)
                return outcome
            } catch {
                return .blocked(.persistenceUnavailable)
            }
        }
        var durableState = state
        durableState.pendingReviewPlan = plan
        do {
            // Keep the completed clarification checkpoint until the causal
            // Action Link is durable. A process exit between review rendering
            // and Queue publication can then restore the exact reviewed plan.
            try saveOrchestrationState(durableState)
        } catch {
            return .blocked(.persistenceUnavailable)
        }
        rememberReviewSource(
            outcome,
            sessionID: sessionID,
            sourceTurnID: durableState.originalSourceTurnID,
            clarificationTurns: clarificationTurns
        )
        return outcome
    }

    private func saveOrchestrationState(
        _ state: VoiceTaskConversationOrchestrationState
    ) throws {
        if let conversationStore,
           try conversationStore.loadSession(id: state.sessionID) == nil
        {
            // SQLite checkpoints are children of a Session so retention can
            // remove sensitive paused state with one cascade. Direct Core
            // callers may begin orchestration before a UI workspace creates
            // that parent, so establish the durable boundary here as well.
            try conversationStore.createSession(
                VoiceTaskConversationSession(
                    id: state.sessionID,
                    title: "Voice task conversation",
                    entryPoint: .voiceCommand
                )
            )
        }
        try stateStore.save(state)
    }

    private func providerOutcome(
        input: VoiceTaskConversationInput,
        route: VoiceCommandRoutingResult
    ) async -> VoiceTaskConversationOutcome {
        guard let provider else {
            return .blocked(.providerUnavailable)
        }

        let providerContext: VoiceTaskProviderContext?
        if let contextInput = input.contextInput {
            do {
                providerContext = try contextAssembler
                    .assemble(contextInput, budget: input.contextBudget)
                    .providerContext
            } catch {
                return .blocked(.contextUnavailable)
            }
        } else {
            providerContext = nil
        }

        do {
            let response = try await provider.generatePlan(
                for: PlanningRequest(
                    userInput: route.planningInput,
                    currentDate: input.currentDate,
                    timeZoneIdentifier: input.timeZoneIdentifier,
                    availableTools: input.availableTools,
                    voiceTaskContext: providerContext
                )
            )
            guard let plan = response.actionPlan,
                  validator.validate(plan).isValid else {
                return .blocked(.invalidPlan)
            }
            if plan.actions.allSatisfy({ $0.riskLevel == .read }) {
                return .answer(
                    VoiceTaskConversationAnswer(
                        text: plan.summary,
                        source: .provider
                    )
                )
            }
            // Provider raw content is intentionally discarded. Only the typed,
            // validated plan crosses into the approval surface.
            return .review(plan)
        } catch {
            return .blocked(.providerUnavailable)
        }
    }

    private func reviewOutcome(
        intents: [ConversationTaskIntent],
        originalTranscript: String
    ) -> VoiceTaskConversationOutcome {
        guard !intents.isEmpty else {
            return .blocked(.invalidPlan)
        }
        let actions = intents.enumerated().map { index, intent in
            PlanAction(
                id: "voice-action-\(index + 1)",
                tool: intent.tool,
                arguments: intent.arguments,
                riskLevel: intent.riskLevel
            )
        }
        let riskLevel = intents.map(\.riskLevel).max() ?? .read
        let plan = ActionPlan(
            id: "voice-plan-\(UUID().uuidString.lowercased())",
            userInput: originalTranscript,
            summary: intents.map(\.summary).joined(separator: "; "),
            actions: actions,
            riskLevel: riskLevel,
            requiresApproval: actions.contains { $0.riskLevel >= .write }
        )
        guard validator.validate(plan).isValid else {
            return .blocked(.invalidPlan)
        }
        if actions.allSatisfy({ $0.riskLevel == .read }) {
            return .answer(
                VoiceTaskConversationAnswer(
                    text: plan.summary,
                    source: .localDeterministic
                )
            )
        }
        return .review(plan)
    }

    private func applying(
        target: ConversationResolvedTarget,
        to intents: [ConversationTaskIntent]
    ) -> [ConversationTaskIntent] {
        intents.map { intent in
            var updated = intent
            switch target {
            case .task(let id, _):
                updated.arguments["id"] = .number(Double(id))
            case .project(let id):
                updated.arguments["projectId"] = .number(Double(id))
            }
            return updated
        }
    }

    private func applying(
        clarificationAnswers: [ClarificationSlot: ClarificationValue],
        to intents: [ConversationTaskIntent]
    ) -> [ConversationTaskIntent] {
        intents.map { intent in
            var updated = intent
            for (slot, answer) in clarificationAnswers {
                let key: String
                switch slot {
                case .project:
                    key = "project"
                case .dueDate:
                    key = "dueAt"
                default:
                    key = slot.rawValue
                }
                switch answer {
                case .text(let value):
                    updated.arguments[key] = .string(value)
                case .approval(let approved):
                    updated.arguments[key] = .bool(approved)
                }
            }
            return updated
        }
    }
}
