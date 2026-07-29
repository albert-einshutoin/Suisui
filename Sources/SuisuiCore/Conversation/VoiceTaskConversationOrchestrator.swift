import Foundation

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

    public init(
        sessionID: UUID,
        originalSourceTurnID: UUID,
        route: VoiceCommandRoutingResult,
        intents: [ConversationTaskIntent],
        clarification: ClarificationSession
    ) {
        self.sessionID = sessionID
        self.originalSourceTurnID = originalSourceTurnID
        self.route = route
        self.intents = intents
        self.clarification = clarification
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
    VoiceTaskConversationReviewLinkPersisting
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
            if !requiredSlots.isEmpty || route.needsClarification {
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
                    intents: intents,
                    clarification: clarification
                )
                do {
                    try stateStore.save(state)
                    return .clarification(question)
                } catch {
                    return .blocked(.persistenceUnavailable)
                }
            }

            let resolvedIntents: [ConversationTaskIntent]
            if let referenceRequest {
                switch referenceResolver.resolve(referenceRequest) {
                case let .resolved(target, _):
                    resolvedIntents = applying(target: target, to: intents)
                case .needsClarification:
                    return .clarification(
                        ClarificationQuestion(
                            slot: .taskTitle,
                            prompt: "Which task or project did you mean?"
                        )
                    )
                case .unavailable:
                    return .blocked(.referenceUnavailable)
                }
            } else {
                resolvedIntents = intents
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
                rememberReviewSource(
                    outcome,
                    sessionID: input.sessionID,
                    sourceTurnID: input.sourceTurnID
                )
                return outcome
            }

            let outcome = await providerOutcome(input: input, route: route)
            rememberReviewSource(
                outcome,
                sessionID: input.sessionID,
                sourceTurnID: input.sourceTurnID
            )
            return outcome
        }
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
        let sourceTurnID = pendingReviewSourceTurnIDs
            .removeValue(forKey: sessionID)
            ?? fallbackSourceTurnID
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
        try conversationStore.saveTurn(
            VoiceTaskConversationTurn(
                id: sourceTurnID,
                sessionID: sessionID,
                author: .user,
                rawTranscript: nil,
                userConfirmedText: confirmedText,
                createdAt: date
            )
        )
        try conversationStore.saveActionLink(
            ConversationActionLinkCoordinator().makeReviewLink(
                sessionID: sessionID,
                sourceTurnID: sourceTurnID,
                plan: plan,
                queueItem: queueItem,
                taskSnapshotFingerprintProvider:
                    taskSnapshotFingerprintProvider
            )
        )
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
        switch state.clarification.answer(answer, inputMode: inputMode) {
        case .needsClarification:
            do {
                try stateStore.save(state)
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
            do {
                try stateStore.remove(sessionID: input.sessionID)
            } catch {
                return .blocked(.persistenceUnavailable)
            }
            let intents = applying(
                clarificationAnswers: result.answers,
                to: state.intents
            )
            guard !intents.isEmpty else {
                let outcome = await providerOutcome(
                    input: input,
                    route: result.resolvedRoute
                )
                rememberReviewSource(
                    outcome,
                    sessionID: input.sessionID,
                    sourceTurnID: state.originalSourceTurnID
                )
                return outcome
            }
            let outcome = reviewOutcome(
                intents: intents,
                originalTranscript: result.originalTranscript
            )
            rememberReviewSource(
                outcome,
                sessionID: input.sessionID,
                sourceTurnID: state.originalSourceTurnID
            )
            return outcome
        }
    }

    private func rememberReviewSource(
        _ outcome: VoiceTaskConversationOutcome,
        sessionID: UUID,
        sourceTurnID: UUID
    ) {
        guard case .review = outcome else {
            return
        }
        pendingReviewSourceTurnIDs[sessionID] = sourceTurnID
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
