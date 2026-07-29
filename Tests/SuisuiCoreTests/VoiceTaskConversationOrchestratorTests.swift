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
        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: TestConversationOrchestrationStateStore()
        ).handle(
            makeInput(
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
        )

        guard case .answer(let answer) = outcome else {
            return XCTFail("Expected deterministic local answer, got \(outcome)")
        }
        XCTAssertEqual(answer.items.map(\.label), ["Release", "Docs"])
        XCTAssertEqual(answer.source, .localDeterministic)
    }

    func testGivenProviderUnavailableAndFreeformPlanningWhenHandleThenReturnsBlockedReason() async {
        let outcome = await VoiceTaskConversationOrchestrator(
            stateStore: TestConversationOrchestrationStateStore()
        ).handle(
            makeInput(
                route: makeRoute(transcript: "来週の進め方を考えて"),
                intents: []
            )
        )

        XCTAssertEqual(outcome, .blocked(.providerUnavailable))
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
        XCTAssertNil(try? store.load(sessionID: initial.sessionID))
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
