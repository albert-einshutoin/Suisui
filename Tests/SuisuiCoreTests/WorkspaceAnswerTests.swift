import XCTest
@testable import SuisuiCore

@MainActor
final class WorkspaceAnswerTests: XCTestCase {
    // MARK: - Prompt builder

    func testPromptBuilderNumbersSnippetsAndCarriesQuestionLanguageAndLengthLimit() {
        let request = WorkspaceAnswerRequest(
            question: "What is overdue right now?",
            contextSnippets: [
                WorkspaceContextSnippet(kind: "task", title: "Ship beta build", detail: "overdue, due 2026-07-01"),
                WorkspaceContextSnippet(kind: "project", title: "Website relaunch"),
                WorkspaceContextSnippet(kind: "knowledge", title: "Release checklist", detail: "Verify signing before upload")
            ],
            currentDate: Date(timeIntervalSince1970: 1_783_418_400),
            timeZoneIdentifier: "Asia/Tokyo",
            languageCode: "ja"
        )

        let prompt = WorkspaceAnswerPromptBuilder.buildPrompt(for: request)

        XCTAssertTrue(prompt.system.contains("You are Suisui's local work assistant."))
        XCTAssertTrue(prompt.system.contains("Answer ONLY from the provided workspace context"))
        XCTAssertTrue(prompt.system.contains("at most 280 characters"))
        XCTAssertTrue(prompt.system.contains("in language 'ja'"))
        XCTAssertTrue(prompt.system.contains("Never invent tasks, projects, or dates."))

        XCTAssertTrue(prompt.user.contains("Time zone: Asia/Tokyo"))
        XCTAssertTrue(prompt.user.contains("Current date: 2026-07-07T10:00:00Z"))
        XCTAssertTrue(prompt.user.contains("[1] (task) Ship beta build — overdue, due 2026-07-01"))
        XCTAssertTrue(prompt.user.contains("[2] (project) Website relaunch"))
        XCTAssertFalse(prompt.user.contains("[2] (project) Website relaunch —"))
        XCTAssertTrue(prompt.user.contains("[3] (knowledge) Release checklist — Verify signing before upload"))
        XCTAssertTrue(prompt.user.contains("Question: What is overdue right now?"))
    }

    func testPromptBuilderRedactsSecretsAndLocalPathsFromSnippets() {
        let request = WorkspaceAnswerRequest(
            question: "What should I rotate?",
            contextSnippets: [
                WorkspaceContextSnippet(
                    kind: "task",
                    title: "Rotate token=sk-secret1234 for staging",
                    detail: "Notes stored in /Users/alice/Client Contracts/notes.md"
                )
            ]
        )

        let prompt = WorkspaceAnswerPromptBuilder.buildPrompt(for: request)

        XCTAssertFalse(prompt.user.contains("sk-secret1234"))
        XCTAssertTrue(prompt.user.contains("[REDACTED_SECRET]"))
        XCTAssertFalse(prompt.user.contains("/Users/alice"))
        XCTAssertTrue(prompt.user.contains("[REDACTED_PATH]"))
    }

    func testPromptBuilderExplainsMissingContextInsteadOfInventingIt() {
        let prompt = WorkspaceAnswerPromptBuilder.buildPrompt(
            for: WorkspaceAnswerRequest(question: "Anything urgent?")
        )

        XCTAssertTrue(prompt.user.contains("No workspace context was found."))
    }

    // MARK: - Retriever

    func testRetrieveListsOverdueBeforeDueTodayThenKeywordMatches() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Overdue invoice", dueAt: "2026-06-15T00:00:00Z")
        _ = try stores.tasks.create(title: "Demo rehearsal", dueAt: "2026-06-17T06:00:00Z")
        _ = try stores.tasks.create(title: "Prepare launch review checklist")
        _ = try stores.projects.create(title: "Launch website")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "How is the launch going?")

        XCTAssertEqual(snippets.first?.kind, "task")
        XCTAssertEqual(snippets.first?.title, "Overdue invoice")
        XCTAssertEqual(snippets.first?.detail, "overdue, due 2026-06-15")
        XCTAssertEqual(snippets[1].title, "Demo rehearsal")
        XCTAssertEqual(snippets[1].detail, "due today")
        XCTAssertTrue(snippets.contains(WorkspaceContextSnippet(kind: "task", title: "Prepare launch review checklist")))
        XCTAssertTrue(snippets.contains { $0.kind == "project" && $0.title == "Launch website" })
    }

    func testRetrieveMatchesTaskDetailKeywords() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Follow up", detail: "Ask the printing vendor about quotes")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "What about the vendor?")

        XCTAssertEqual(snippets.map(\.title), ["Follow up"])
        XCTAssertEqual(snippets.first?.detail, "Ask the printing vendor about quotes")
    }

    func testRetrieveFindsUnicodeInternalTaskSubstringBeyondNewerRows() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "VorÜbergabe handoff")
        for index in 0..<129 {
            _ = try stores.tasks.create(title: "Unrelated newer task \(index)")
        }

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "übe", limit: 1).map(\.title),
            ["VorÜbergabe handoff"]
        )
    }

    func testRetrieveFindsCanonicalUnicodeTaskSubstringAcrossNFCAndNFD() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "VorU\u{0308}bergabe handoff")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "über", limit: 1).map(\.title),
            ["VorU\u{0308}bergabe handoff"]
        )
    }

    func testRetrievePagesShortUnicodeInternalTaskSubstringBeyondNewerRows() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "VorÜbergabe handoff")
        for index in 0..<129 {
            _ = try stores.tasks.create(title: "Unrelated newer task \(index)")
        }

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "üb", limit: 1).map(\.title),
            ["VorÜbergabe handoff"]
        )
    }

    func testRetrieveCompletesLiteralTaskSubstringsAlongsideFTSHits() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Prepare invoice report")
        _ = try stores.tasks.create(title: "Record voice memo")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "What about voice?", limit: 2)

        XCTAssertEqual(Set(snippets.filter { $0.kind == "task" }.map(\.title)), ["Prepare invoice report", "Record voice memo"])
    }

    func testRetrieveMatchesJapaneseTaskTitleWithoutSpaceSeparation() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "リリース準備タスク")
        _ = try stores.tasks.create(title: "Unrelated cleanup")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "リリースの進捗は？")

        XCTAssertEqual(snippets.map(\.title), ["リリース準備タスク"])
    }

    func testRetrieveMatchesJapaneseTaskTitleWhenPhraseStartsAfterOtherText() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "請求書リリース確認")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "リリースの進捗は？")

        XCTAssertEqual(snippets.map(\.title), ["請求書リリース確認"])
    }

    func testRetrieveIncludesKnowledgeFrameFTSHitsWithBodyPreview() throws {
        let stores = try makeStores()
        let longBody = "Verify signing certificates before every release upload. "
            + String(repeating: "Repeat the notarization checklist steps carefully. ", count: 6)
        _ = try stores.frames.create(name: "Deployment notes", body: longBody)

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "Where are the deployment notes?")

        let knowledge = try XCTUnwrap(snippets.first { $0.kind == "knowledge" })
        XCTAssertEqual(knowledge.title, "Deployment notes")
        let detail = try XCTUnwrap(knowledge.detail)
        XCTAssertTrue(detail.hasPrefix("Verify signing certificates"))
        XCTAssertTrue(detail.hasSuffix("..."))
        XCTAssertLessThanOrEqual(detail.count, 163)
    }

    func testRetrieveMatchesJapaneseKnowledgeTextInTheMiddleOfATitle() throws {
        let stores = try makeStores()
        _ = try stores.frames.create(
            name: "請求書リリース手順",
            body: "承認後に公開する"
        )

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")
        let snippets = try retriever.retrieve(question: "リリースの手順は？")

        XCTAssertEqual(snippets.filter { $0.kind == "knowledge" }.map(\.title), ["請求書リリース手順"])
    }

    func testRetrieveUsesSingleJapaneseCharacterAsKnowledgeLiteralFallback() throws {
        let stores = try makeStores()
        _ = try stores.frames.create(name: "税務メモ", body: "税金の確認")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "税?").map(\.title),
            ["税務メモ"]
        )
    }

    func testRetrieveUsesSingleASCIICharacterAsKnowledgeLiteralFallback() throws {
        let stores = try makeStores()
        _ = try stores.frames.create(name: "C compiler notes", body: "Compile the local helper")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "C?").map(\.title),
            ["C compiler notes"]
        )
    }

    func testRetrieveNormalizesSentenceTerminatorsForSingleCharacterKnowledgeFallback() throws {
        let stores = try makeStores()
        _ = try stores.frames.create(name: "C compiler notes", body: "Compile the local helper")
        _ = try stores.frames.create(name: "税務メモ", body: "税金の確認")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "C.").map(\.title),
            ["C compiler notes"]
        )
        XCTAssertEqual(
            try retriever.retrieve(question: "税.").map(\.title),
            ["税務メモ"]
        )
    }

    func testRetrievePunctuatedSingleCharacterKnowledgeFallbackPreservesDeadlineLimit() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Due today", dueAt: "2026-06-17T06:00:00Z")
        _ = try stores.tasks.create(title: "C task should not be scanned")
        _ = try stores.frames.create(name: "C compiler notes", body: "Compile the local helper")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "C.", limit: 2).map(\.title),
            ["Due today", "C compiler notes"]
        )
        XCTAssertEqual(
            try retriever.retrieve(question: "C.", limit: 1).map(\.title),
            ["Due today"]
        )
    }

    func testRetrieveSingleCharacterKnowledgeFallbackPreservesDeadlineOrderAndLimit() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Due today", dueAt: "2026-06-17T06:00:00Z")
        _ = try stores.tasks.create(title: "税 task should not be scanned")
        _ = try stores.frames.create(name: "税務メモ", body: "税金の確認")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "税?", limit: 2).map(\.title),
            ["Due today", "税務メモ"]
        )
        XCTAssertEqual(
            try retriever.retrieve(question: "税?", limit: 1).map(\.title),
            ["Due today"]
        )
    }

    func testRetrieveDedupesByKindAndTitleAndCapsAtLimit() throws {
        let stores = try makeStores()
        // Overdue AND keyword-matched: must appear exactly once.
        _ = try stores.tasks.create(title: "Launch review", dueAt: "2026-06-10T00:00:00Z")
        for index in 1...10 {
            _ = try stores.tasks.create(title: "Launch follow-up \(index)")
        }

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        let capped = try retriever.retrieve(question: "launch review", limit: 3)
        XCTAssertEqual(capped.count, 3)

        let all = try retriever.retrieve(question: "launch review", limit: 50)
        XCTAssertEqual(all.filter { $0.kind == "task" && $0.title == "Launch review" }.count, 1)
    }

    func testRetrieveOverfetchesTaskCandidatesBeforeDedupingTitles() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Launch review")
        _ = try stores.tasks.create(title: "Launch review")
        _ = try stores.tasks.create(title: "Launch retrospective")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "launch", limit: 2).map(\.title),
            ["Launch review", "Launch retrospective"]
        )
    }

    func testRetrieveOverfetchesKnowledgeCandidatesBeforeDedupingTitles() throws {
        let stores = try makeStores()
        _ = try stores.frames.create(name: "Launch notes", body: "first")
        _ = try stores.frames.create(name: "Launch notes", body: "second")
        _ = try stores.frames.create(name: "Launch retrospective", body: "third")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "launch", limit: 2).map(\.title),
            ["Launch notes", "Launch retrospective"]
        )
    }

    func testRetrievePagesPastEightDuplicateTaskTitlesBeforeDeduping() throws {
        let stores = try makeStores()
        for _ in 0..<8 {
            _ = try stores.tasks.create(title: "Launch review")
        }
        _ = try stores.tasks.create(title: "Prelaunch retrospective")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "launch review", limit: 2).map(\.title),
            ["Launch review", "Prelaunch retrospective"]
        )
    }

    func testRetrievePagesPastEightDuplicateKnowledgeTitlesBeforeDeduping() throws {
        let stores = try makeStores()
        for index in 0..<8 {
            _ = try stores.frames.create(name: "Launch review notes", body: "duplicate \(index)")
        }
        _ = try stores.frames.create(name: "Prelaunch retrospective", body: "unique")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "launch review", limit: 2).map(\.title),
            ["Launch review notes", "Prelaunch retrospective"]
        )
    }

    func testRetrieveUsesExactTaskMatchBeforeOlderSubstringAfterDeadlineConsumesSlot() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Send daily summary", dueAt: "2026-06-17T06:00:00Z")
        _ = try stores.tasks.create(title: "Prepare invoice report")
        _ = try stores.tasks.create(title: "Record voice memo")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(
            try retriever.retrieve(question: "What about voice?", limit: 2).map(\.title),
            ["Send daily summary", "Record voice memo"]
        )
    }

    func testRetrieveReturnsNothingForBlankQuestion() throws {
        let stores = try makeStores()
        _ = try stores.tasks.create(title: "Overdue invoice", dueAt: "2026-06-15T00:00:00Z")

        let retriever = makeRetriever(stores: stores, now: "2026-06-17T00:00:00Z")

        XCTAssertEqual(try retriever.retrieve(question: "   "), [])
    }

    // MARK: - Claude generateAnswer

    func testClaudeGenerateAnswerReturnsTrimmedPlainText() async throws {
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(values: [.anthropicAPIKey: "sk-ant-test"]),
            httpClient: WorkspaceAnswerStubHTTPDataClient(
                data: Data(
                    """
                    {"content":[{"type":"text","text":"  You have two overdue tasks. Start with the invoice.  "}]}
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let answer = try await provider.generateAnswer(
            for: WorkspaceAnswerRequest(question: "What is overdue?")
        )

        XCTAssertEqual(answer, "You have two overdue tasks. Start with the invoice.")
    }

    func testClaudeGenerateAnswerMapsMissingTextContentToInvalidResponse() async {
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(values: [.anthropicAPIKey: "sk-ant-test"]),
            httpClient: WorkspaceAnswerStubHTTPDataClient(
                data: Data(#"{"content":[]}"#.utf8),
                statusCode: 200
            )
        )

        do {
            _ = try await provider.generateAnswer(for: WorkspaceAnswerRequest(question: "What is overdue?"))
            XCTFail("Expected empty content to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Claude Messages response did not contain text content.")
            )
        }
    }

    func testClaudeGenerateAnswerRequiresAPIKeyBeforeHTTP() async {
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(),
            httpClient: WorkspaceAnswerStubHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.generateAnswer(for: WorkspaceAnswerRequest(question: "What is overdue?"))
            XCTFail("Expected missing API key to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    // MARK: - View model

    func testAskWorkspaceQuestionAnswersWithRedactionAndSpeaksOnce() async {
        let recorder = ReadoutRecorder()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeAnswerGeneratingProvider(answer: "Check /Users/alice/plan.md, then rest."),
            workspaceContextRetriever: { _ in
                [WorkspaceContextSnippet(kind: "task", title: "Plan tomorrow")]
            },
            workspaceAnswerReadout: { text in
                recorder.record(text)
            }
        )

        viewModel.updateDraftText("What should I do next?")
        await viewModel.askWorkspaceQuestion()

        XCTAssertEqual(
            viewModel.workspaceAnswer,
            .answered(text: "Check [REDACTED_PATH], then rest.", contextCount: 1)
        )
        XCTAssertEqual(recorder.texts, ["Check [REDACTED_PATH], then rest."])

        viewModel.replayWorkspaceAnswer()

        XCTAssertEqual(recorder.texts, [
            "Check [REDACTED_PATH], then rest.",
            "Check [REDACTED_PATH], then rest."
        ])
    }

    func testAskWorkspaceQuestionFailsWhenProviderCannotAnswerQuestions() async {
        let recorder = ReadoutRecorder()
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            workspaceContextRetriever: { _ in [] },
            workspaceAnswerReadout: { text in
                recorder.record(text)
            }
        )

        viewModel.updateDraftText("What should I do next?")
        await viewModel.askWorkspaceQuestion()

        guard case .failed(let message) = viewModel.workspaceAnswer else {
            return XCTFail("Expected failed state, got \(viewModel.workspaceAnswer)")
        }
        XCTAssertTrue(message.contains("does not support workspace question answering"))
        XCTAssertTrue(recorder.texts.isEmpty)
    }

    func testAskWorkspaceQuestionFailsWhenRetrieverThrows() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeAnswerGeneratingProvider(answer: "unused"),
            workspaceContextRetriever: { _ in
                throw LLMProviderError.unknown("retrieval store closed")
            }
        )

        viewModel.updateDraftText("What should I do next?")
        await viewModel.askWorkspaceQuestion()

        guard case .failed(let message) = viewModel.workspaceAnswer else {
            return XCTFail("Expected failed state, got \(viewModel.workspaceAnswer)")
        }
        XCTAssertTrue(message.contains("retrieval store closed"))
    }

    func testAskWorkspaceQuestionFailsWhenProviderThrows() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeAnswerGeneratingProvider(error: LLMProviderError.rateLimited),
            workspaceContextRetriever: { _ in [] }
        )

        viewModel.updateDraftText("What should I do next?")
        await viewModel.askWorkspaceQuestion()

        guard case .failed(let message) = viewModel.workspaceAnswer else {
            return XCTFail("Expected failed state, got \(viewModel.workspaceAnswer)")
        }
        XCTAssertTrue(message.contains("rate limit"))
    }

    func testAskWorkspaceQuestionRequiresDraftTextAndRetriever() async {
        let withoutRetriever = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeAnswerGeneratingProvider(answer: "unused")
        )
        withoutRetriever.updateDraftText("What should I do next?")
        await withoutRetriever.askWorkspaceQuestion()
        guard case .failed(let message) = withoutRetriever.workspaceAnswer else {
            return XCTFail("Expected failed state, got \(withoutRetriever.workspaceAnswer)")
        }
        XCTAssertTrue(message.contains("unavailable"))

        let withoutText = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeAnswerGeneratingProvider(answer: "unused"),
            workspaceContextRetriever: { _ in [] }
        )
        await withoutText.askWorkspaceQuestion()
        XCTAssertEqual(withoutText.workspaceAnswer, .failed("Type or dictate a question first."))
    }

    func testGeneratePlanResetsWorkspaceAnswerState() async {
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-1",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: AnsweringFakeLLMProvider(response: response, answer: "Do the beta task first."),
            workspaceContextRetriever: { _ in [] }
        )

        viewModel.updateDraftText("What should I do next?")
        await viewModel.askWorkspaceQuestion()
        XCTAssertEqual(viewModel.workspaceAnswer, .answered(text: "Do the beta task first.", contextCount: 0))

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.workspaceAnswer, .idle)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    // MARK: - Fixtures

    private struct FixedDateProvider: DateProvider {
        let now: Date
    }

    private func makeStores() throws -> (
        projects: SQLiteProjectStore,
        tasks: SQLiteTaskStore,
        frames: SQLiteKnowledgeFrameStore
    ) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteKnowledgeFrameStore(connection: connection)
        )
    }

    private func makeRetriever(
        stores: (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, frames: SQLiteKnowledgeFrameStore),
        now: String
    ) -> WorkspaceQuestionRetriever {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return WorkspaceQuestionRetriever(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            knowledgeFrameStore: stores.frames,
            dateProvider: FixedDateProvider(now: formatter.date(from: now) ?? Date()),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )
    }
}

private final class ReadoutRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(text)
    }

    var texts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct WorkspaceAnswerStubHTTPDataClient: HTTPDataClient {
    var data: Data
    var statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.anthropic.com/v1/messages")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}

private struct FakeAnswerGeneratingProvider: AnswerGeneratingLLMProvider {
    var providerID = "fake.answering"
    var answer: String = ""
    var error: LLMProviderError?

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        PlanningResponse(
            providerID: providerID,
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        )
    }

    func generateAnswer(for request: WorkspaceAnswerRequest) async throws -> String {
        if let error {
            throw error
        }
        return answer
    }
}

/// Answers questions AND returns a fixed plan, for tests that exercise the
/// plan flow after a workspace answer.
private struct AnsweringFakeLLMProvider: AnswerGeneratingLLMProvider {
    var providerID = "fake.answering.planning"
    var response: PlanningResponse
    var answer: String

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        response
    }

    func generateAnswer(for request: WorkspaceAnswerRequest) async throws -> String {
        answer
    }
}
