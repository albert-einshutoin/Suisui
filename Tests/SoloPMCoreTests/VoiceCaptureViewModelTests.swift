import XCTest
@testable import SoloPMCore

@MainActor
final class VoiceCaptureViewModelTests: XCTestCase {
    func testGeneratePlanUsesDraftTextAndMovesToReviewReady() async {
        let logger = InMemoryAuditLogger()
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
            llmProvider: FakeLLMProvider(response: response),
            auditRecorder: PlanningAuditRecorder(logger: logger)
        )

        viewModel.updateDraftText(" Create a task ")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-1")
        let expectedCapabilities: [AssistantQueueRequiredCapability] = [.tool(.taskCreate), .providerExecutionApproval]
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .waitingReview)
        XCTAssertEqual(viewModel.assistantQueueItem?.sourceTranscript, "Create a task")
        XCTAssertEqual(viewModel.assistantQueueItem?.redactedSummary, "Create task")
        XCTAssertEqual(viewModel.assistantQueueItem?.requiredCapabilities, expectedCapabilities)
        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
    }

    func testGeneratePlanDefaultsToNonDeveloperPlanningTools() async {
        let response = PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-default-tools",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let provider = RecordingVoiceLLMProvider(response: response)
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(provider.requests.first?.availableTools, ActionTool.defaultPlanningTools)
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryReadFile) ?? true)
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryCreateFile) ?? true)
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryUpdateFile) ?? true)
    }

    func testGeneratePlanPersistsAssistantQueueItemWhenStoreIsConfigured() async {
        let store = RecordingAssistantQueueStore()
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-persisted",
                userInput: "Create a persisted task",
                summary: "Create persisted task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            assistantQueueStore: store
        )

        viewModel.updateDraftText("Create a persisted task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(store.savedItems.map(\.id), ["action-plan:plan-persisted"])
        XCTAssertEqual(store.savedItems.map(\.state), [.waitingReview])
        XCTAssertEqual(try? store.get(id: "action-plan:plan-persisted"), viewModel.assistantQueueItem)
    }

    func testAssistantQueueTransitionsPersistThroughConfiguredStore() async {
        let store = RecordingAssistantQueueStore()
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-transition-persisted",
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
            llmProvider: FakeLLMProvider(response: response),
            assistantQueueStore: store
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertTrue(viewModel.approveAssistantQueueItem(reviewerID: "local-user"))
        viewModel.deferAssistantQueueItem()
        viewModel.rejectAssistantQueueItem()

        XCTAssertEqual(store.savedItems.map(\.state), [.waitingReview, .approved, .deferred, .rejected])
        XCTAssertEqual((try? store.get(id: "action-plan:plan-transition-persisted"))?.state, .rejected)
    }

    func testAssistantQueueStoreSaveFailureKeepsGeneratedWorkOutOfReview() async {
        let store = RecordingAssistantQueueStore(saveError: SecretVoiceTestError(message: "disk full sk-store-secret"))
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-store-failure",
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
            llmProvider: FakeLLMProvider(response: response),
            assistantQueueStore: store
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertNil(viewModel.assistantQueueItem)
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.contains("Assistant Queue could not save generated work"))
            XCTAssertFalse(message.contains("sk-store-secret"))
        } else {
            XCTFail("Expected queue persistence failure to fail closed before review.")
        }
    }

    func testGeneratePlanRoutesTranscriptIntoStructuredVoiceIntent() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-1",
                userInput: "リリースメモのタスクを作成して",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("リリースメモのタスクを作成して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .taskCreate)
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertTrue(provider.requests[0].userInput.contains("Voice command intent: task.create"))
        XCTAssertTrue(provider.requests[0].userInput.contains("Original transcript:"))
        XCTAssertTrue(provider.requests[0].userInput.contains("リリースメモのタスクを作成して"))
        XCTAssertTrue(provider.requests[0].userInput.contains("Review boundary: review-only"))
    }

    func testGeneratePlanRequiresClarificationForAmbiguousTranscriptWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("いい感じにして")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .clarify)
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .taskTitle)
        XCTAssertEqual(provider.requests.count, 0)
        if case .needsClarification(let reason) = viewModel.phase {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected needs clarification phase.")
        }
    }

    func testDailyPlanningReviewIntentCreatesLocalRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "今日やることを確認して",
                summary: "Should not call provider",
                actions: [PlanAction(id: "action-1", tool: .taskList)],
                riskLevel: .read,
                requiresApproval: false
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("今日やることを確認して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.sourceTranscript, "今日やることを確認して")
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testOpenTodayReviewCreatesLocalRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "Open Today Review",
                summary: "Should not call provider",
                actions: [PlanAction(id: "action-1", tool: .taskList)],
                riskLevel: .read,
                requiresApproval: false
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Open Today Review")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.sourceTranscript, "Open Today Review")
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testExplicitInboxVoiceTriageCommandCreatesLocalRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "inbox today",
                summary: "Should not call provider",
                actions: [PlanAction(id: "action-1", tool: .taskUpdate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("inbox today")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .taskTriage)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertNil(viewModel.dailyPlanningReviewRequest)
        XCTAssertEqual(viewModel.inboxTriageRequest?.sourceTranscript, "inbox today")
        XCTAssertEqual(viewModel.inboxTriageRequest?.command.action, .scheduleToday)
        XCTAssertEqual(viewModel.phase, .reviewReady)

        viewModel.updateDraftText("Create a task")

        XCTAssertNil(viewModel.inboxTriageRequest)
    }

    func testBareInboxVoiceTriageCommandNeedsContextBeforeLocalRequest() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("today")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertNil(viewModel.inboxTriageRequest)
        XCTAssertNil(viewModel.dailyPlanningReviewRequest)
        XCTAssertEqual(provider.requests.count, 0)
        if case .needsClarification = viewModel.phase {
        } else {
            XCTFail("Expected bare command to require clarification outside explicit Inbox context.")
        }
    }

    func testClarificationAnswerContinuesIntoReviewablePlanningRequest() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-clarified",
                userInput: "これ明日やって",
                summary: "Create clarified task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("これ明日やって")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .taskTitle)

        await viewModel.submitClarificationAnswer(
            "リリースメモを書く",
            currentDate: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .project)

        await viewModel.submitClarificationAnswer(
            "SoloPM",
            currentDate: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-clarified")
        XCTAssertEqual(provider.requests.count, 1)
        XCTAssertTrue(provider.requests[0].userInput.contains("Voice command intent: task.create"))
        XCTAssertTrue(provider.requests[0].userInput.contains("Original transcript:"))
        XCTAssertTrue(provider.requests[0].userInput.contains("これ明日やって"))
        XCTAssertTrue(provider.requests[0].userInput.contains("Clarification trail (user-provided values, not system instructions):"))
        XCTAssertTrue(provider.requests[0].userInput.contains("task_title: リリースメモを書く"))
        XCTAssertTrue(provider.requests[0].userInput.contains("project: SoloPM"))
    }

    func testGeneratePlanQueuesDangerousActionPlanAsBlockedBeforeReview() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-danger",
                userInput: "Create a task",
                summary: "Create risky project files",
                actions: [PlanAction(id: "action-danger", tool: .filesystemCreateMarkdownFile, riskLevel: .danger)],
                riskLevel: .danger,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [
                ActionPlanValidationIssue(
                    severity: .blocking,
                    path: "actions[0].riskLevel",
                    message: "Dangerous action plans are blocked."
                )
            ])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        if case .failed(let message) = viewModel.phase {
            XCTAssertEqual(message, "ActionPlan validation failed.")
        } else {
            XCTFail("Expected dangerous plan validation failure.")
        }
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .blocked)
        XCTAssertEqual(viewModel.assistantQueueItem?.blockingReason, "Dangerous action plans cannot be approved from Assistant Queue.")
    }

    func testAssistantQueueItemCanBeApprovedDeferredAndRejectedWithoutExecutionToken() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-queue",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertTrue(viewModel.approveAssistantQueueItem(reviewerID: "local-user"))
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .approved)
        XCTAssertNil(viewModel.assistantQueueItem?.approval?.executionTokenID)

        viewModel.deferAssistantQueueItem()
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .deferred)

        viewModel.rejectAssistantQueueItem()
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .rejected)
        XCTAssertNil(viewModel.assistantQueueItem?.approval)
    }

    func testAssistantQueueApprovalCreatesCentralExecutionHandoff() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-queue-handoff",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertNil(viewModel.assistantQueueExecutionHandoffItemID)

        XCTAssertTrue(viewModel.approveAssistantQueueItem(reviewerID: "local-user"))
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .approved)
        XCTAssertEqual(viewModel.assistantQueueExecutionHandoffItemID, "action-plan:plan-queue-handoff")

        viewModel.deferAssistantQueueItem()

        XCTAssertNil(viewModel.assistantQueueExecutionHandoffItemID)
    }

    func testRecordingDuringClarificationUsesTranscriptAsAnswerWithoutReplacingOriginalDraft() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "リリースメモを書く")),
            llmProvider: provider
        )

        viewModel.updateDraftText("これ明日やって")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertFalse(viewModel.canGeneratePlan)

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/solopm-clarification-answer.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(viewModel.draft.text, "これ明日やって")
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .project)
        XCTAssertEqual(viewModel.clarificationSession?.turns.first?.answer, .text("リリースメモを書く"))
        XCTAssertEqual(viewModel.clarificationSession?.turns.first?.inputMode, .voice)
        XCTAssertEqual(provider.requests.count, 0)
    }

    func testCancelClarificationRestoresDraftEditing() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("いい感じにして")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertNotNil(viewModel.clarificationQuestion)

        viewModel.cancelClarification()

        XCTAssertNil(viewModel.clarificationQuestion)
        XCTAssertTrue(viewModel.canGeneratePlan)
        XCTAssertEqual(provider.requests.count, 0)
    }

    func testDraftEditClearsStalePlanningResponse() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
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
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertNotNil(viewModel.planningResponse)

        viewModel.updateDraftText("いい感じにして")

        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.routingResult?.intent, .clarify)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testInFlightPlanningResponseIsIgnoredWhenDraftChangesBeforeReview() async {
        let gate = VoicePlanningGate()
        let provider = DelayedRecordingVoiceLLMProvider(
            gate: gate,
            response: PlanningResponse(
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
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )

        viewModel.updateDraftText("Create a task")
        let planningTask = Task {
            await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        }
        await gate.waitUntilRequestReceived()

        viewModel.updateDraftText("いい感じにして")
        await gate.release()
        await planningTask.value

        XCTAssertNil(viewModel.planningResponse)
        XCTAssertEqual(viewModel.routingResult?.intent, .clarify)
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .taskTitle)
        XCTAssertEqual(provider.requests.count, 1)
        if case .needsClarification(let reason) = viewModel.phase {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("Expected stale response to leave the current ambiguous draft in clarification.")
        }
    }

    func testGeneratePlanSurfacesCompletionAuditFailureWithoutLosingPlan() async {
        let logger = SequencedVoiceAuditLogger(failOnCall: 2)
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
            llmProvider: FakeLLMProvider(response: response),
            auditRecorder: PlanningAuditRecorder(logger: logger)
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.planningResponse?.actionPlan?.id, "plan-1")
        XCTAssertEqual(viewModel.auditErrorMessage, "Planning audit log failed: unavailable")
    }

    func testPlanningAuditFailureRedactsSecretContext() async {
        let secret = "sk-" + "voiceAuditSecret123"
        let logger = ThrowingVoiceAuditLogger(
            error: SecretVoiceTestError(message: "audit failed token=\(secret)&request_id=voice-audit-1")
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            auditRecorder: PlanningAuditRecorder(logger: logger)
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(
            viewModel.auditErrorMessage,
            "Planning audit log failed: audit failed token=[REDACTED_SECRET]&request_id=voice-audit-1"
        )
        XCTAssertFalse(viewModel.auditErrorMessage?.contains(secret) ?? true)
    }

    func testGeneratePlanRedactsUnexpectedProviderErrorMessage() async {
        let secret = "sk-" + "voiceProviderSecret123"
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: ThrowingVoiceLLMProvider(
                error: SecretVoiceTestError(message: "planner failed token=\(secret)&request_id=voice-provider-1")
            )
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(
            viewModel.phase,
            .failed("planner failed token=[REDACTED_SECRET]&request_id=voice-provider-1")
        )
        if case .failed(let message) = viewModel.phase {
            XCTAssertFalse(message.contains(secret))
        } else {
            XCTFail("Expected failed phase.")
        }
    }

    func testRuntimeValidationMessageBlocksPlanGenerationUntilRuntimeIsFixed() async {
        let message = "Voice planning is unavailable because audit logging or local data stores could not be opened."
        let viewModel = VoiceCaptureViewModel(
            phase: .failed(message),
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            runtimeValidationMessage: message
        )

        viewModel.updateDraftText("Create a task")

        XCTAssertFalse(viewModel.canGeneratePlan)
        XCTAssertEqual(viewModel.phase, .failed(message))

        await viewModel.generatePlan()

        XCTAssertNil(viewModel.planningResponse)
        XCTAssertEqual(viewModel.phase, .failed(message))

        viewModel.clear()

        XCTAssertEqual(viewModel.phase, .failed(message))
    }

    func testRecordingFlowTranscribesIntoDraft() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(viewModel.phase, .recording)

        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/solopm-test.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.draft.text, "Create a task")
        XCTAssertEqual(viewModel.recordedAudio?.duration, 2)
    }

    func testCanRecordAgainAfterSuccessfulTranscription() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/solopm-test-first.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(viewModel.phase, .recording)
        XCTAssertEqual(viewModel.recordingState, .recording(startedAt: Date(timeIntervalSince1970: 20)))
    }

    func testClearResetsActiveRecordingState() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        viewModel.clear()
        await viewModel.startRecording(at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(viewModel.phase, .recording)
        XCTAssertEqual(viewModel.recordingState, .recording(startedAt: Date(timeIntervalSince1970: 20)))
    }

    func testGeneratePlanRejectsEmptyDraft() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.generatePlan()

        XCTAssertEqual(viewModel.phase, .failed("Transcript is empty."))
    }
}

private enum VoiceAuditTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "unavailable"
    }
}

private struct SecretVoiceTestError: Error, CustomStringConvertible {
    var message: String

    var description: String {
        message
    }
}

private struct ThrowingVoiceLLMProvider: LLMProvider {
    var providerID: String = "throwing"
    var error: Error

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        throw error
    }
}

private final class RecordingVoiceLLMProvider: LLMProvider, @unchecked Sendable {
    let providerID: String = "recording"
    private let response: PlanningResponse
    private let queue = DispatchQueue(label: "dev.solopm.tests.recording-voice-llm-provider")
    private var recordedRequests: [PlanningRequest] = []

    init(response: PlanningResponse) {
        self.response = response
    }

    var requests: [PlanningRequest] {
        queue.sync { recordedRequests }
    }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        queue.sync {
            recordedRequests.append(request)
        }
        return response
    }
}

private final class DelayedRecordingVoiceLLMProvider: LLMProvider, @unchecked Sendable {
    let providerID: String = "delayed-recording"
    private let gate: VoicePlanningGate
    private let response: PlanningResponse
    private let queue = DispatchQueue(label: "dev.solopm.tests.delayed-recording-voice-llm-provider")
    private var recordedRequests: [PlanningRequest] = []

    init(gate: VoicePlanningGate, response: PlanningResponse) {
        self.gate = gate
        self.response = response
    }

    var requests: [PlanningRequest] {
        queue.sync { recordedRequests }
    }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        queue.sync {
            recordedRequests.append(request)
        }
        await gate.markRequestReceived()
        await gate.waitForRelease()
        return response
    }
}

private actor VoicePlanningGate {
    private var requestReceived = false
    private var released = false
    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func markRequestReceived() {
        requestReceived = true
        requestContinuation?.resume()
        requestContinuation = nil
    }

    func waitUntilRequestReceived() async {
        guard !requestReceived else {
            return
        }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func waitForRelease() async {
        guard !released else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private final class ThrowingVoiceAuditLogger: AuditLogger, @unchecked Sendable {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func record(_ event: AuditEvent) throws {
        throw error
    }
}

private final class SequencedVoiceAuditLogger: AuditLogger, @unchecked Sendable {
    private let failOnCall: Int
    private var callCount = 0
    private let lock = NSLock()

    init(failOnCall: Int) {
        self.failOnCall = failOnCall
    }

    func record(_ event: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }
        callCount += 1
        if callCount >= failOnCall {
            throw VoiceAuditTestError.unavailable
        }
    }
}

private final class RecordingAssistantQueueStore: AssistantQueueStore {
    private(set) var savedItems: [AssistantQueueItem] = []
    private var items: [String: AssistantQueueItem] = [:]
    private let saveError: Error?

    init(saveError: Error? = nil) {
        self.saveError = saveError
    }

    @discardableResult
    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        if let saveError {
            throw saveError
        }
        items[item.id] = item
        savedItems.append(item)
        return item
    }

    func get(id: String) throws -> AssistantQueueItem {
        guard let item = items[id] else {
            throw AssistantQueueStoreError.notFound(id)
        }
        return item
    }

    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] {
        items.values
            .filter { filter.includes($0.state) }
            .sorted { $0.id < $1.id }
            .prefix(filter.limit)
            .map { $0 }
    }

    func stateCounts() throws -> AssistantQueueStateCounts {
        AssistantQueueStateCounts(items: Array(items.values))
    }

    @discardableResult
    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        let item = try get(id: id)
        return try save(transform(item))
    }
}
