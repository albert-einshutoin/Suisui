import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationOrchestratorTests: XCTestCase {
    func testGivenMissingProjectWhenHandleThenAsksOneProjectQuestion() async {
        let store = TestConversationOrchestrationStateStore()
        let orchestrator = VoiceTaskConversationOrchestrator(stateStore: store)
        let input = makeInput(
            route: makeRoute(transcript: "リリースタスクを作成して"),
            requiredSlots: [.project],
            intents: [makeCreateIntent()]
        )

        let outcome = await orchestrator.handle(input)

        guard case .clarification(let question) = outcome else {
            return XCTFail("Expected one clarification question, got \(outcome)")
        }
        XCTAssertEqual(question.slot, .project)
        XCTAssertNotNil(try? store.load(sessionID: input.sessionID))
    }

    func testGivenClarificationAnswerWhenResumeThenReturnsOriginalIntentPlan() async {
        let store = TestConversationOrchestrationStateStore()
        let orchestrator = VoiceTaskConversationOrchestrator(stateStore: store)
        let initial = makeInput(
            route: makeRoute(transcript: "リリースタスクを作成して"),
            requiredSlots: [.project],
            intents: [makeCreateIntent()]
        )
        _ = await orchestrator.handle(initial)

        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Launch", inputMode: .typed)
            )
        )

        guard case .review(let plan) = outcome else {
            return XCTFail("Expected a reviewable plan, got \(outcome)")
        }
        XCTAssertEqual(plan.userInput, "リリースタスクを作成して")
        XCTAssertEqual(plan.actions.first?.arguments["project"], .string("Launch"))
        XCTAssertTrue(plan.requiresApproval)
    }

    func testGivenCompletedClarificationWhenProcessRestartsThenRestoresExactPendingReview()
        async
    {
        let store = TestConversationOrchestrationStateStore()
        let initial = makeInput(
            route: makeRoute(transcript: "リリースタスクを作成して"),
            requiredSlots: [.project],
            intents: [makeCreateIntent()]
        )
        let first = VoiceTaskConversationOrchestrator(stateStore: store)
        _ = await first.handle(initial)
        let reviewed = await first.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Launch")
            )
        )

        let restored = await VoiceTaskConversationOrchestrator(
            stateStore: store
        ).handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .restore
            )
        )

        XCTAssertEqual(restored, reviewed)
        XCTAssertNotNil(try? store.load(sessionID: initial.sessionID))
    }

    func testGivenResolvedAmbiguousReferenceWhenProcessRestartsThenRestoresReviewAndTrail()
        async
    {
        let store = TestConversationOrchestrationStateStore()
        let candidates = [
            ConversationReferenceCandidate(
                target: .task(id: 11, projectID: 3),
                title: "Release notes",
                stableSortKey: "01"
            ),
            ConversationReferenceCandidate(
                target: .task(id: 22, projectID: 3),
                title: "Release build",
                stableSortKey: "02"
            ),
        ]
        let sessionID = UUID()
        let initial = makeInput(
            sessionID: sessionID,
            route: makeRoute(
                transcript: "Releaseを完了にして"
            ),
            intents: [
                ConversationTaskIntent(
                    utterance: "Releaseを完了にして",
                    operation: .complete,
                    tool: .taskComplete,
                    arguments: [:],
                    summary: "Complete selected task"
                ),
            ],
            referenceRequest: VoiceTaskReferenceRequest(
                sessionID: sessionID,
                utterance: "Releaseを完了にして",
                candidateOrderingFingerprint:
                    VoiceTaskReferenceResolver.orderingFingerprint(
                        for: candidates
                    ),
                candidates: candidates
            )
        )
        let first = VoiceTaskConversationOrchestrator(stateStore: store)
        _ = await first.handle(initial)
        let reviewed = await first.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Release build")
            )
        )

        let restored = await VoiceTaskConversationOrchestrator(
            stateStore: store
        ).handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .restore
            )
        )
        let state = try? store.load(sessionID: initial.sessionID)

        XCTAssertEqual(restored, reviewed)
        XCTAssertEqual(
            state?.resolvedReferenceCandidate?.target,
            .task(id: 22, projectID: 3)
        )
        XCTAssertEqual(
            state?.referenceClarificationTurns.map {
                $0.question.prompt
            },
            ["Which task or project did you mean?"]
        )
    }

    func testGivenCancelDuringClarificationWhenHandleThenCreatesNoPlan() async {
        let store = TestConversationOrchestrationStateStore()
        let provider = RecordingConversationProvider()
        let orchestrator = VoiceTaskConversationOrchestrator(
            stateStore: store,
            provider: provider
        )
        let initial = makeInput(
            route: makeRoute(transcript: "タスクを作成して"),
            requiredSlots: [.project],
            intents: [makeCreateIntent()]
        )
        _ = await orchestrator.handle(initial)

        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .cancel
            )
        )

        XCTAssertEqual(outcome, .canceled)
        XCTAssertNil(try? store.load(sessionID: initial.sessionID))
        XCTAssertEqual(provider.requestCount, 0)
    }

    func testGivenCorrectionOfOrdinalWhenHandleThenUsesCorrectedReference() async throws {
        let candidates = [
            ConversationReferenceCandidate(
                target: .task(id: 11, projectID: 3),
                title: "First",
                stableSortKey: "01"
            ),
            ConversationReferenceCandidate(
                target: .task(id: 22, projectID: 3),
                title: "Second",
                stableSortKey: "02"
            )
        ]
        let fingerprint = VoiceTaskReferenceResolver.orderingFingerprint(for: candidates)
        let ordinalReference = try ConversationReference(
            id: UUID(),
            sessionID: UUID(),
            target: .task(22),
            sourceTurnID: UUID(),
            ordinal: 1,
            orderingFingerprint: fingerprint,
            expiresAt: Date().addingTimeInterval(60),
            createdAt: Date()
        )
        let request = VoiceTaskReferenceRequest(
            sessionID: ordinalReference.sessionID,
            utterance: "違う、2つ目を完了にして",
            ordinalReference: ordinalReference,
            candidateOrderingFingerprint: fingerprint,
            candidates: candidates
        )
        let input = makeInput(
            sessionID: request.sessionID,
            route: makeRoute(transcript: request.utterance),
            intents: [
                ConversationTaskIntent(
                    utterance: request.utterance,
                    operation: .complete,
                    tool: .taskComplete,
                    arguments: [:],
                    summary: "Complete corrected task"
                )
            ],
            referenceRequest: request
        )

        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: TestConversationOrchestrationStateStore()
        ).handle(input)

        guard case .review(let plan) = outcome else {
            return XCTFail("Expected corrected review plan, got \(outcome)")
        }
        XCTAssertEqual(plan.actions.first?.arguments["id"], .number(22))
    }

    func testGivenAmbiguousReferenceWhenAnswerThenResumesOriginalIntentWithSelectedTarget()
        async
    {
        let store = TestConversationOrchestrationStateStore()
        let orchestrator = VoiceTaskConversationOrchestrator(
            stateStore: store
        )
        let sessionID = UUID()
        let candidates = [
            ConversationReferenceCandidate(
                target: .task(id: 11, projectID: 3),
                title: "Prepare review",
                stableSortKey: "01"
            ),
            ConversationReferenceCandidate(
                target: .task(id: 22, projectID: 3),
                title: "Submit summary",
                stableSortKey: "02"
            ),
        ]
        let initial = makeInput(
            sessionID: sessionID,
            route: makeRoute(transcript: "Complete that task"),
            intents: [
                ConversationTaskIntent(
                    utterance: "Complete that task",
                    operation: .complete,
                    tool: .taskComplete,
                    arguments: [:],
                    summary: "Complete selected task"
                ),
            ],
            referenceRequest: VoiceTaskReferenceRequest(
                sessionID: sessionID,
                utterance: "Complete that task",
                candidates: candidates
            )
        )

        guard case .clarification = await orchestrator.handle(initial) else {
            return XCTFail("Expected reference clarification")
        }
        XCTAssertNotNil(try? store.load(sessionID: sessionID))

        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer(
                    "Submit summary",
                    inputMode: .typed
                )
            )
        )

        guard case .review(let plan) = outcome else {
            return XCTFail("Expected resumed review, got \(outcome)")
        }
        XCTAssertEqual(plan.userInput, "Complete that task")
        XCTAssertEqual(plan.actions.first?.arguments["id"], .number(22))
        XCTAssertEqual(
            try? store.load(sessionID: sessionID)?.pendingReviewPlan,
            plan
        )
    }

    func testGivenTwoTaskChangesWhenHandleThenCreatesTwoPlanActions() async {
        let intents = [
            ConversationTaskIntent(
                utterance: "2件を更新して",
                operation: .updateStatus,
                tool: .taskUpdate,
                arguments: ["id": .number(1), "status": .string("planned")],
                summary: "Plan first task"
            ),
            ConversationTaskIntent(
                utterance: "2件を更新して",
                operation: .updateDueDate,
                tool: .taskUpdate,
                arguments: ["id": .number(2), "dueAt": .string("2026-08-01")],
                summary: "Date second task"
            )
        ]

        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: TestConversationOrchestrationStateStore()
        ).handle(
            makeInput(
                route: makeRoute(transcript: "2件を更新して"),
                intents: intents
            )
        )

        guard case .review(let plan) = outcome else {
            return XCTFail("Expected review, got \(outcome)")
        }
        XCTAssertEqual(plan.actions.count, 2)
        XCTAssertTrue(plan.requiresApproval)
    }

    func testGivenProviderUnavailableAndTaskListWhenHandleThenReturnsLocalAnswer() async {
        let store = TestConversationOrchestrationStateStore()
        let input = makeInput(
            route: makeRoute(transcript: "タスク一覧"),
            intents: [
                ConversationTaskIntent(
                    utterance: "タスク一覧",
                    operation: .list,
                    tool: .taskList,
                    arguments: [:],
                    summary: "List tasks"
                )
            ],
            localAnswerItems: [
                VoiceTaskConversationAnswerItem(id: "task:1", label: "Release"),
                VoiceTaskConversationAnswerItem(id: "task:2", label: "Docs")
            ]
        )
        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: store
        ).handle(input)

        guard case .answer(let answer) = outcome else {
            return XCTFail("Expected deterministic local answer, got \(outcome)")
        }
        XCTAssertEqual(answer.items.map(\.label), ["Release", "Docs"])
        XCTAssertEqual(answer.source, .localDeterministic)
        XCTAssertNil(try? store.load(sessionID: input.sessionID))
    }

    func testGivenDeterministicTaskListWhenGenericRouterNeedsClarificationThenReturnsLocalAnswer() async {
        let route = VoiceCommandRouter().route(transcript: "List tasks")
        XCTAssertTrue(route.needsClarification)

        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: TestConversationOrchestrationStateStore()
        ).handle(
            makeInput(
                route: route,
                intents: [
                    ConversationTaskIntent(
                        utterance: "List tasks",
                        operation: .list,
                        tool: .taskList,
                        arguments: ["projectId": .number(7)],
                        summary: "List current tasks"
                    )
                ],
                localAnswerItems: [
                    VoiceTaskConversationAnswerItem(
                        id: "task:11",
                        label: "Prepare review"
                    ),
                    VoiceTaskConversationAnswerItem(
                        id: "task:22",
                        label: "Submit summary"
                    )
                ]
            )
        )

        guard case .answer(let answer) = outcome else {
            return XCTFail("Expected deterministic local answer, got \(outcome)")
        }
        XCTAssertEqual(answer.items.map(\.id), ["task:11", "task:22"])
        XCTAssertEqual(answer.source, .localDeterministic)
    }

    func testGivenProviderUnavailableAndFreeformPlanningWhenHandleThenReturnsBlockedReason() async {
        let store = TestConversationOrchestrationStateStore()
        let input = makeInput(
            route: makeRoute(transcript: "来週の進め方を考えて"),
            intents: []
        )
        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: store
        ).handle(input)

        XCTAssertEqual(outcome, .blocked(.providerUnavailable))
        XCTAssertNil(try store.load(sessionID: input.sessionID))
    }

    func testGivenPersistedPausedSessionWhenResumeThenRestoresClarificationTrail() async {
        let store = TestConversationOrchestrationStateStore()
        let initial = makeInput(
            route: makeRoute(transcript: "金曜までにタスクを作成して"),
            requiredSlots: [.project, .dueDate],
            intents: [makeCreateIntent()]
        )
        let first = VoiceTaskConversationOrchestrator(stateStore: store)
        _ = await first.handle(initial)
        let secondQuestion = await first.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Launch")
            )
        )
        guard case .clarification(let question) = secondQuestion else {
            return XCTFail("Expected second clarification")
        }
        XCTAssertEqual(question.slot, .dueDate)

        let restored = VoiceTaskConversationOrchestrator(stateStore: store)
        let outcome = await restored.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("月曜")
            )
        )

        guard case .review(let plan) = outcome else {
            return XCTFail("Expected restored review plan, got \(outcome)")
        }
        XCTAssertEqual(plan.userInput, "金曜までにタスクを作成して")
        XCTAssertEqual(plan.actions.first?.arguments["project"], .string("Launch"))
        XCTAssertEqual(plan.actions.first?.arguments["dueAt"], .string("月曜"))
    }

    func testGivenClarifiedReviewWhenPersistLinkThenUsesOriginalTurnAndDurableQueue() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let conversationStore = SQLiteVoiceTaskConversationStore(
            connection: connection
        )
        let stateStore =
            SQLiteVoiceTaskConversationOrchestrationStateStore(
                connection: connection
            )
        let orchestrator = VoiceTaskConversationOrchestrator(
            stateStore: stateStore,
            conversationStore: conversationStore
        )
        let originalTurnID = UUID()
        let initial = VoiceTaskConversationInput(
            sessionID: UUID(),
            sourceTurnID: originalTurnID,
            event: .begin(
                route: makeRoute(
                    transcript: "リリースタスクを作成して"
                ),
                requiredSlots: [.project],
                intents: [makeCreateIntent()],
                referenceRequest: nil,
                localAnswerItems: []
            )
        )
        _ = await orchestrator.handle(initial)
        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Launch")
            )
        )
        guard case .review(let plan) = outcome else {
            return XCTFail("Expected review, got \(outcome)")
        }
        let queueItem = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: "Review",
            costPreview: .localOnly()
        )

        try await orchestrator.persistReviewLink(
            sessionID: initial.sessionID,
            fallbackSourceTurnID: UUID(),
            confirmedText: plan.userInput,
            plan: plan,
            queueItem: queueItem,
            at: Date().addingTimeInterval(1)
        )

        XCTAssertNotNil(
            try conversationStore.loadSession(id: initial.sessionID)
        )
        let turns = try conversationStore.listTurns(
            sessionID: initial.sessionID,
            before: nil,
            limit: 10
        )
        XCTAssertEqual(turns.map(\.author), [.user, .assistant, .user])
        XCTAssertEqual(
            turns.map(\.userConfirmedText),
            ["Launch", nil, nil]
        )
        XCTAssertEqual(turns[1].rawTranscript, "Which project should this belong to?")
        XCTAssertEqual(turns.last?.rawTranscript, "リリースタスクを作成して")
        XCTAssertEqual(turns.last?.id, originalTurnID)
        let link = try XCTUnwrap(
            conversationStore.latestActionLink(
                assistantQueueItemID: queueItem.id
            )
        )
        XCTAssertEqual(link.sourceTurnID, originalTurnID)
        XCTAssertEqual(link.actionPlanID, plan.id)
        XCTAssertEqual(link.assistantQueueItemID, queueItem.id)
        XCTAssertNotNil(
            try stateStore.load(sessionID: initial.sessionID)
        )
        try await orchestrator.acknowledgeReviewPublication(
            sessionID: initial.sessionID
        )
        XCTAssertNil(try stateStore.load(sessionID: initial.sessionID))
    }

    func testGivenVoiceClarificationWhenPersistLinkThenKeepsAnswerUnderRawRetention()
        async throws
    {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let conversationStore = SQLiteVoiceTaskConversationStore(
            connection: connection
        )
        let stateStore =
            SQLiteVoiceTaskConversationOrchestrationStateStore(
                connection: connection
            )
        let orchestrator = VoiceTaskConversationOrchestrator(
            stateStore: stateStore,
            conversationStore: conversationStore
        )
        let initial = makeInput(
            route: makeRoute(transcript: "リリースタスクを作成して"),
            requiredSlots: [.project],
            intents: [makeCreateIntent()]
        )
        _ = await orchestrator.handle(initial)
        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer(
                    "Launch",
                    inputMode: .voice
                )
            )
        )
        guard case .review(let plan) = outcome else {
            return XCTFail("Expected review, got \(outcome)")
        }
        let queueItem = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: "Review",
            costPreview: .localOnly()
        )
        try await orchestrator.persistReviewLink(
            sessionID: initial.sessionID,
            fallbackSourceTurnID: UUID(),
            confirmedText: plan.userInput,
            plan: plan,
            queueItem: queueItem,
            at: Date()
        )

        var turns = try conversationStore.listTurns(
            sessionID: initial.sessionID,
            before: nil,
            limit: 10
        )
        let voiceAnswer = try XCTUnwrap(
            turns.first { $0.rawTranscript == "Launch" }
        )
        XCTAssertNil(voiceAnswer.userConfirmedText)

        _ = try conversationStore.deleteSession(
            id: initial.sessionID,
            scope: .rawTranscripts
        )
        turns = try conversationStore.listTurns(
            sessionID: initial.sessionID,
            before: nil,
            limit: 10
        )
        XCTAssertTrue(turns.allSatisfy { $0.rawTranscript == nil })
        XCTAssertFalse(
            turns.contains { $0.userConfirmedText == "Launch" }
        )
    }

    func testGivenPersistedPausedSessionWhenRestoreThenReturnsCurrentQuestion() async {
        let store = TestConversationOrchestrationStateStore()
        let initial = makeInput(
            route: makeRoute(transcript: "金曜までにタスクを作成して"),
            requiredSlots: [.project, .dueDate],
            intents: [makeCreateIntent()]
        )
        let first = VoiceTaskConversationOrchestrator(stateStore: store)
        _ = await first.handle(initial)
        _ = await first.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Launch")
            )
        )

        let restored = VoiceTaskConversationOrchestrator(stateStore: store)
        let outcome = await restored.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .restore
            )
        )

        guard case .clarification(let question) = outcome else {
            return XCTFail("Expected restored clarification, got \(outcome)")
        }
        XCTAssertEqual(question.slot, .dueDate)
    }

    func testGivenProviderPlanningAfterClarificationThenPreservesOriginalTranscriptAndTrail() async {
        let expectedPlan = ActionPlan(
            id: "provider-plan",
            userInput: "リリース計画を作って",
            summary: "Prepare release work",
            actions: [PlanAction(id: "action-1", tool: .taskCreate)],
            riskLevel: .write,
            requiresApproval: true
        )
        let provider = RecordingConversationProvider(
            response: PlanningResponse(
                providerID: "test",
                rawContent: "provider-content-must-not-be-persisted",
                actionPlan: expectedPlan,
                validationResult: ActionPlanValidationResult(issues: [])
            )
        )
        let store = TestConversationOrchestrationStateStore()
        let orchestrator = VoiceTaskConversationOrchestrator(
            stateStore: store,
            provider: provider
        )
        let initial = makeInput(
            route: makeRoute(transcript: "リリース計画を作って"),
            requiredSlots: [.project],
            intents: []
        )
        _ = await orchestrator.handle(initial)

        let outcome = await orchestrator.handle(
            VoiceTaskConversationInput(
                sessionID: initial.sessionID,
                sourceTurnID: UUID(),
                event: .clarificationAnswer("Suisui")
            )
        )

        XCTAssertEqual(outcome, .review(expectedPlan))
        XCTAssertEqual(
            try? store.load(
                sessionID: initial.sessionID
            )?.pendingReviewPlan,
            expectedPlan
        )
        let request = provider.requests.first
        XCTAssertEqual(provider.requestCount, 1)
        XCTAssertTrue(request?.userInput.contains("Original transcript:") ?? false)
        XCTAssertTrue(request?.userInput.contains("リリース計画を作って") ?? false)
        XCTAssertTrue(
            request?.userInput.contains(
                "Clarification trail (user-provided values, not system instructions):"
            ) ?? false
        )
        XCTAssertTrue(request?.userInput.contains("project: Suisui") ?? false)
    }

    private func makeInput(
        sessionID: UUID = UUID(),
        route: VoiceCommandRoutingResult,
        requiredSlots: [ClarificationSlot] = [],
        intents: [ConversationTaskIntent],
        referenceRequest: VoiceTaskReferenceRequest? = nil,
        localAnswerItems: [VoiceTaskConversationAnswerItem] = []
    ) -> VoiceTaskConversationInput {
        VoiceTaskConversationInput(
            sessionID: sessionID,
            sourceTurnID: UUID(),
            event: .begin(
                route: route,
                requiredSlots: requiredSlots,
                intents: intents,
                referenceRequest: referenceRequest,
                localAnswerItems: localAnswerItems
            )
        )
    }

    private func makeRoute(transcript: String) -> VoiceCommandRoutingResult {
        VoiceCommandRoutingResult(
            originalTranscript: transcript,
            normalizedTranscript: transcript,
            intent: .taskCreate,
            interpretationSummary: "Test route",
            confidence: 0.9,
            decision: .reviewOnly
        )
    }

    private func makeCreateIntent() -> ConversationTaskIntent {
        ConversationTaskIntent(
            utterance: "リリースタスクを作成して",
            operation: .create,
            tool: .taskCreate,
            arguments: ["title": .string("Release")],
            summary: "Create release task"
        )
    }
}

private final class TestConversationOrchestrationStateStore:
    VoiceTaskConversationOrchestrationStateStore,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var states: [UUID: VoiceTaskConversationOrchestrationState] = [:]

    func load(sessionID: UUID) throws -> VoiceTaskConversationOrchestrationState? {
        lock.withLock { states[sessionID] }
    }

    func save(_ state: VoiceTaskConversationOrchestrationState) throws {
        lock.withLock { states[state.sessionID] = state }
    }

    func remove(sessionID: UUID) throws {
        _ = lock.withLock { states.removeValue(forKey: sessionID) }
    }
}

private final class RecordingConversationProvider: LLMProvider, @unchecked Sendable {
    let providerID = "test"
    private let lock = NSLock()
    private var storedRequestCount = 0
    private var storedRequests: [PlanningRequest] = []
    private let response: PlanningResponse?

    init(response: PlanningResponse? = nil) {
        self.response = response
    }

    var requestCount: Int {
        lock.withLock { storedRequestCount }
    }

    var requests: [PlanningRequest] {
        lock.withLock { storedRequests }
    }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        lock.withLock {
            storedRequestCount += 1
            storedRequests.append(request)
        }
        if let response {
            return response
        }
        throw LLMProviderError.network("offline")
    }
}
