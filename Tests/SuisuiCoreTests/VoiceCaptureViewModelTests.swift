import XCTest
@testable import SuisuiCore

@MainActor
final class VoiceCaptureViewModelTests: XCTestCase {
    func testConversationWorkspaceCreatesScopedSessionAndPersistsLifecycle()
        throws
    {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        try connection.execute(
            """
            INSERT INTO projects (id, title, status)
            VALUES (7, 'Launch', 'active');
            INSERT INTO tasks (id, project_id, title, status)
            VALUES (11, 7, 'Ship alpha', 'todo');
            """
        )
        let store = SQLiteVoiceTaskConversationStore(connection: connection)
        let sessionID = UUID()
        let viewModel = makeConversationWorkspaceViewModel(
            sessionID: sessionID
        )
        let scope = VoiceTaskConversationWorkspacePresentation.Scope(
            projectName: "Launch",
            taskName: "Ship alpha",
            sessionTitle: "Ship alpha"
        )

        viewModel.configureConversationWorkspace(
            store: store,
            scope: scope,
            activeProjectID: 7,
            activeTaskID: 11,
            entryPoint: .taskInspector
        )

        let created = try XCTUnwrap(store.loadSession(id: sessionID))
        XCTAssertEqual(created.activeProjectID, 7)
        XCTAssertEqual(created.activeTaskID, 11)
        XCTAssertEqual(created.entryPoint, .taskInspector)
        XCTAssertEqual(viewModel.conversationWorkspaceScope, scope)

        viewModel.pauseConversationWorkspace()
        XCTAssertEqual(viewModel.conversationWorkspaceSessionState, .paused)
        viewModel.resumeConversationWorkspace()
        XCTAssertNil(viewModel.conversationWorkspaceSessionState)
        viewModel.archiveConversationWorkspace()
        XCTAssertEqual(viewModel.conversationWorkspaceSessionState, .archived)
        XCTAssertEqual(
            try store.loadSession(id: sessionID)?.state,
            .archived
        )
    }

    func testConversationWorkspaceLoadsConfirmedTurnsWithStablePagination()
        throws
    {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let store = SQLiteVoiceTaskConversationStore(connection: connection)
        let sessionID = UUID()
        let viewModel = makeConversationWorkspaceViewModel(
            sessionID: sessionID
        )
        viewModel.configureConversationWorkspace(
            store: store,
            scope: .init()
        )
        let base = Date().addingTimeInterval(1)
        for index in 0..<21 {
            try store.saveTurn(
                VoiceTaskConversationTurn(
                    sessionID: sessionID,
                    author: .user,
                    rawTranscript: "raw \(index)",
                    userConfirmedText: "confirmed \(index)",
                    createdAt: base.addingTimeInterval(Double(index))
                )
            )
        }

        viewModel.configureConversationWorkspace(
            store: store,
            scope: .init()
        )

        XCTAssertEqual(viewModel.conversationWorkspaceTurns.count, 20)
        XCTAssertEqual(
            viewModel.conversationWorkspaceTurnListState,
            .loaded(hasMore: true)
        )
        XCTAssertFalse(
            viewModel.conversationWorkspaceTurns.contains {
                $0.text.hasPrefix("raw ")
            }
        )

        viewModel.loadEarlierConversationTurns()

        XCTAssertEqual(viewModel.conversationWorkspaceTurns.count, 21)
        XCTAssertEqual(
            viewModel.conversationWorkspaceTurnListState,
            .loaded(hasMore: false)
        )
        XCTAssertEqual(
            viewModel.conversationWorkspaceTurns.first?.text,
            "confirmed 0"
        )
    }

    func testConversationWorkspaceDisplaysRawTranscriptUntilRetentionRemovesIt()
        throws
    {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        let store = SQLiteVoiceTaskConversationStore(connection: connection)
        let sessionID = UUID()
        let viewModel = makeConversationWorkspaceViewModel(
            sessionID: sessionID
        )
        viewModel.configureConversationWorkspace(store: store, scope: .init())
        try store.saveTurn(
            VoiceTaskConversationTurn(
                sessionID: sessionID,
                author: .user,
                rawTranscript: "Original speech",
                userConfirmedText: nil,
                createdAt: Date()
            )
        )

        viewModel.configureConversationWorkspace(store: store, scope: .init())
        XCTAssertEqual(
            viewModel.conversationWorkspaceTurns.map(\.text),
            ["Original speech"]
        )

        let turn = try XCTUnwrap(
            store.listTurnPage(
                sessionID: sessionID,
                before: nil,
                limit: 20
            ).turns.first
        )
        _ = try store.deleteSession(
            id: sessionID,
            scope: .rawTranscripts
        )
        viewModel.configureConversationWorkspace(store: store, scope: .init())

        XCTAssertFalse(turn.rawTranscript?.isEmpty ?? true)
        XCTAssertTrue(viewModel.conversationWorkspaceTurns.isEmpty)
    }

    func testExistingVoiceViewModelCannotUseCodexAfterApprovalIsRevoked() async throws {
        let approval = MutableCodexApprovalForVoice(
            try CodexAppServerRuntimeConfiguration.approve(
                executablePath: "/usr/bin/true",
                trustPolicy: .developerUnsignedAllowed
            )
        )
        let reporter = VoiceRecordingVersionReporter()
        let provider = CodexLocalRuntimeProvider(
            approvedExecutableProvider: { approval.value },
            modelID: nil,
            clientVersion: "voice-test",
            versionReporter: reporter
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider
        )
        viewModel.updateDraftText("明日のタスクを追加")

        approval.value = nil
        await viewModel.generatePlan()

        guard case .failed = viewModel.phase else {
            return XCTFail("Expected revoked approval to fail the existing Voice runtime")
        }
        let callCount = await reporter.callCount
        XCTAssertEqual(callCount, 0)
    }

    private func makeConversationWorkspaceViewModel(
        sessionID: UUID
    ) -> VoiceCaptureViewModel {
        VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "fake",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            ),
            conversationOrchestrator: nil,
            conversationSessionID: sessionID
        )
    }

    func testGeneratePlanRequiresAValidDraftInEveryIdleState() {
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

        viewModel.updateDraftText("   \n")
        XCTAssertFalse(viewModel.canGeneratePlan)

        viewModel.updateDraftText("Plan the release")
        XCTAssertTrue(viewModel.canGeneratePlan)
    }

    func testHandsFreeProviderIdentityDoesNotDriftWhenSettingsChange() {
        let settings = MutableVoiceSettings(AppSettings(sttProvider: .openAITranscribe))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                id: .openAITranscribe,
                transcript: STTTranscript(text: "")
            ),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            appSettingsProvider: { settings.value }
        )

        XCTAssertEqual(viewModel.handsFreeModeProviderName, "OpenAI Transcribe")

        settings.value = AppSettings(sttProvider: .localWhisperCpp)

        XCTAssertEqual(viewModel.handsFreeModeProviderName, "OpenAI Transcribe")
    }

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
        let store = RecordingAssistantQueueStore()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            auditRecorder: PlanningAuditRecorder(logger: logger),
            assistantQueueStore: store
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
        XCTAssertEqual(store.savedItems.map(\.state), [.waitingReview])
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
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryListFiles) ?? true)
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryReadFile) ?? true)
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryCreateFile) ?? true)
        XCTAssertFalse(provider.requests.first?.availableTools.contains(.developmentRepositoryUpdateFile) ?? true)
    }

    func testGeneratePlanUsesDeveloperPlanningToolsForDevelopmentPRIntent() async {
        let response = PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-development-pr-workflow",
                userInput: "Prepare a development PR workflow",
                summary: "Prepare branch, verification, PR review, and merge gates.",
                actions: [
                    PlanAction(
                        id: "action-development-prepare",
                        tool: .developmentPreparePullRequestWorkflow,
                        arguments: ["projectId": .number(7)],
                        riskLevel: .write
                    )
                ],
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

        viewModel.updateDraftText("このプロジェクトでブランチを作ってPRレビューとマージまで進めて")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(provider.requests.first?.availableTools, ActionTool.developerModePlanningTools)
        XCTAssertEqual(viewModel.assistantQueueItem?.requiredCapabilities, [
            .tool(.developmentPreparePullRequestWorkflow),
            .providerExecutionApproval
        ])
    }

    func testNotificationDraftCommandCreatesMailDraftQueueItemWithoutProviderCall() async throws {
        let response = PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "unexpected-provider-plan",
                userInput: "Should not be called",
                summary: "Should not be used",
                actions: [PlanAction(id: "unexpected", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )
        let provider = RecordingVoiceLLMProvider(response: response)
        let store = RecordingAssistantQueueStore()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: store
        )

        viewModel.updateDraftText("Slack notification draft for release delay token=sk-notification-secret at /Users/shutoide/private.txt")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertTrue(provider.requests.isEmpty)
        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(store.savedItems.map(\.id), [item.id])
        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .draft)
        XCTAssertEqual(item.requiredCapabilities, [.tool(.mailDraftCreateText)])
        XCTAssertEqual(item.reviewReason, "Notification draft needs review before any external message or local notification is created.")
        XCTAssertEqual(item.sourceTranscript, "Slack notification draft for release delay token=[REDACTED_SECRET] at [REDACTED_LOCAL_PATH]")
        XCTAssertFalse(item.redactedSummary.contains("sk-notification-secret"))
        XCTAssertFalse(item.sourceTranscript?.contains("/Users/shutoide") == true)

        guard case .actionPlan(let actionPlan) = item.payload else {
            return XCTFail("Expected notification draft to enter Assistant Queue as an action plan.")
        }
        XCTAssertTrue(actionPlan.id.hasPrefix("notification-draft:"))
        XCTAssertEqual(actionPlan.riskLevel, .draft)
        XCTAssertFalse(actionPlan.requiresApproval)
        XCTAssertEqual(actionPlan.actions.map(\.tool), [.mailDraftCreateText])
        XCTAssertEqual(actionPlan.actions.first?.arguments["subject"]?.stringValue, "Notification draft")
        XCTAssertTrue(actionPlan.actions.first?.arguments["body"]?.stringValue?.contains("[REDACTED_SECRET]") == true)
        XCTAssertFalse(actionPlan.actions.first?.arguments["body"]?.stringValue?.contains("/Users/shutoide") == true)
        XCTAssertFalse(actionPlan.userInput.contains("sk-notification-secret"))
        XCTAssertFalse(actionPlan.summary.contains("sk-notification-secret"))
    }

    func testClarifiedNotificationDraftIncludesDestinationAnswerInQueueReviewPayload() async throws {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: RecordingAssistantQueueStore()
        )

        viewModel.updateDraftText("通知して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .clarify)
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .destination)

        await viewModel.submitClarificationAnswer(
            "Slack release channel token=sk-destination-secret",
            currentDate: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC"
        )

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertTrue(provider.requests.isEmpty)
        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(item.sourceTranscript, "通知して\nClarification answers:\n- destination: Slack release channel token=[REDACTED_SECRET]")
        XCTAssertFalse(item.sourceTranscript?.contains("sk-destination-secret") == true)

        guard case .actionPlan(let actionPlan) = item.payload else {
            return XCTFail("Expected clarified notification draft to enter Assistant Queue as an action plan.")
        }
        let body = try XCTUnwrap(actionPlan.actions.first?.arguments["body"]?.stringValue)
        XCTAssertTrue(body.contains("Original voice request:\n通知して"))
        XCTAssertTrue(body.contains("Clarification answers:\n- destination: Slack release channel token=[REDACTED_SECRET]"))
        XCTAssertFalse(body.contains("sk-destination-secret"))
    }

    func testExplicitExternalSendDoesNotCreateMailDraftQueueOrProviderCall() async throws {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: RecordingAssistantQueueStore()
        )

        viewModel.updateDraftText("Slackに今すぐ送信して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .connectorSendGate)
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertTrue(provider.requests.isEmpty)
        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.requiredCapabilities, [
            .externalConnector(serviceID: "slack", action: "message.send"),
            .providerExecutionApproval
        ])
        guard case .automationRequest(let request) = item.payload else {
            return XCTFail("Expected direct external send to become a non-executable automation request.")
        }
        XCTAssertEqual(request.toolName, "connector.send")
        XCTAssertNil(request.taskMutation)
        XCTAssertNil(request.developmentPullRequest)
    }

    func testExplicitConnectorSendCreatesBlockedQueueGateWithoutProviderOrMailDraftPlan() async throws {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let store = RecordingAssistantQueueStore()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: store
        )

        viewModel.updateDraftText("Slackに今すぐ送信して token=sk-connector-secret at /Users/shutoide/private.txt")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertTrue(provider.requests.isEmpty)
        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(store.savedItems.map(\.id), [item.id])
        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.requiredCapabilities, [
            .externalConnector(serviceID: "slack", action: "message.send"),
            .providerExecutionApproval
        ])
        XCTAssertEqual(
            item.blockingReason,
            "Slack connector send is not configured. Create a reviewed draft instead; no external message was sent."
        )
        XCTAssertEqual(
            item.sourceTranscript,
            "Slackに今すぐ送信して token=[REDACTED_SECRET] at [REDACTED_LOCAL_PATH]"
        )
        XCTAssertFalse(item.redactedSummary.contains("sk-connector-secret"))
        XCTAssertFalse(item.sourceTranscript?.contains("/Users/shutoide") == true)
        XCTAssertFalse(viewModel.approveAssistantQueueItem())

        guard case .automationRequest(let request) = item.payload else {
            return XCTFail("Expected connector send gate to enter Assistant Queue as a non-executable automation request.")
        }
        XCTAssertEqual(request.source, .conversation)
        XCTAssertEqual(request.approvalState, .pendingApproval)
        XCTAssertEqual(request.sourceClientID, "voice")
        XCTAssertEqual(request.toolName, "connector.send")
        XCTAssertNil(request.taskMutation)
        XCTAssertNil(request.developmentPullRequest)
        XCTAssertFalse(request.redactedArgumentSummary.contains("sk-connector-secret"))
        XCTAssertFalse(request.redactedArgumentSummary.contains("/Users/shutoide"))
    }

    func testExplicitConnectorSendGateDetectsLineAndDiscordDestinations() async throws {
        let cases: [(transcript: String, serviceID: String, displayName: String)] = [
            ("LINEに今すぐ送って", "line", "LINE"),
            ("Discordに今すぐ投稿して", "discord", "Discord")
        ]

        for testCase in cases {
            let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
                providerID: "recording",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
            let viewModel = VoiceCaptureViewModel(
                audioRecorder: FakeAudioRecorder(),
                sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
                llmProvider: provider,
                assistantQueueStore: RecordingAssistantQueueStore()
            )

            viewModel.updateDraftText(testCase.transcript)
            await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

            let item = try XCTUnwrap(viewModel.assistantQueueItem, testCase.transcript)
            XCTAssertEqual(item.state, .blocked, testCase.transcript)
            XCTAssertEqual(item.requiredCapabilities.first, .externalConnector(serviceID: testCase.serviceID, action: "message.send"), testCase.transcript)
            XCTAssertTrue(item.blockingReason?.contains("\(testCase.displayName) connector send is not configured") == true, testCase.transcript)
            XCTAssertTrue(provider.requests.isEmpty, testCase.transcript)
        }
    }

    func testConnectorSendGateDoesNotTreatOnlineAsLineDestination() async throws {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: RecordingAssistantQueueStore()
        )

        viewModel.updateDraftText("online meeting mail send now")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.requiredCapabilities.first, .externalConnector(serviceID: "mail", action: "message.send"))
        XCTAssertFalse(item.blockingReason?.contains("LINE connector") == true)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testGeneratePlanQueuesDevelopmentPullRequestReviewGateFromExplicitVoiceCommand() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let bookmarkData = Data("voice-pr-workspace-bookmark".utf8)
        let project = ProjectRecord(
            id: 7,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let store = RecordingAssistantQueueStore()
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: store,
            developmentProjectProvider: { project },
            developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder(
                bookmarkResolver: StaticProjectWorkspaceBookmarkResolver(url: workspace),
                requestIDProvider: { "voice-pr-review-request" }
            )
        )

        viewModel.updateDraftText("""
        Review PR https://github.com/albert-einshutoin/suisui/pull/116 branch feature/suisui-7-merge-gate base feature/phase14-product-completion
        """)
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(store.savedItems.map(\.id), ["automation-request:voice-pr-review-request"])
        XCTAssertEqual(viewModel.assistantQueueItem?.requiredCapabilities, [
            .connectedMacRequired,
            .tool(.developmentReviewPullRequestGate),
            .providerExecutionApproval
        ])
        guard case .automationRequest(let request) = viewModel.assistantQueueItem?.payload else {
            return XCTFail("Expected a development PR automation request")
        }
        XCTAssertEqual(request.source, .conversation)
        XCTAssertEqual(request.toolName, ActionTool.developmentReviewPullRequestGate.rawValue)
        XCTAssertEqual(request.developmentPullRequest, SyncDevelopmentPullRequestPayload(
            projectID: 7,
            operation: .reviewGate,
            pullRequestURL: "https://github.com/albert-einshutoin/suisui/pull/116",
            branchName: "feature/suisui-7-merge-gate",
            baseBranch: "feature/phase14-product-completion"
        ))
    }

    func testGeneratePlanQueuesDevelopmentPullRequestMergeFromExplicitVoiceCommand() async throws {
        let workspace = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let bookmarkData = Data("voice-pr-workspace-bookmark".utf8)
        let project = ProjectRecord(
            id: 7,
            title: "Suisui",
            status: "active",
            workspacePath: workspace.path,
            workspaceBookmarkData: bookmarkData
        )
        let store = RecordingAssistantQueueStore()
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: store,
            developmentProjectProvider: { project },
            developmentPullRequestAutomationRequestBuilder: VoiceDevelopmentPullRequestAutomationRequestBuilder(
                bookmarkResolver: StaticProjectWorkspaceBookmarkResolver(url: workspace),
                requestIDProvider: { "voice-pr-merge-request" }
            )
        )

        viewModel.updateDraftText("""
        Merge PR https://github.com/albert-einshutoin/suisui/pull/116 branch feature/suisui-7-merge-gate base feature/phase14-product-completion
        """)
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(store.savedItems.map(\.id), ["automation-request:voice-pr-merge-request"])
        XCTAssertEqual(viewModel.assistantQueueItem?.requiredCapabilities, [
            .connectedMacRequired,
            .tool(.developmentMergePullRequest),
            .providerExecutionApproval
        ])
        guard case .automationRequest(let request) = viewModel.assistantQueueItem?.payload else {
            return XCTFail("Expected a development PR automation request")
        }
        XCTAssertEqual(request.source, .conversation)
        XCTAssertEqual(request.toolName, ActionTool.developmentMergePullRequest.rawValue)
        XCTAssertEqual(request.developmentPullRequest, SyncDevelopmentPullRequestPayload(
            projectID: 7,
            operation: .merge,
            pullRequestURL: "https://github.com/albert-einshutoin/suisui/pull/116",
            branchName: "feature/suisui-7-merge-gate",
            baseBranch: "feature/phase14-product-completion"
        ))
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

    func testGeneratePlanPreservesMeasuredProviderUsageForAssistantQueueReceipt() async {
        let response = PlanningResponse(
            providerID: "openai.chat_completions",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-measured-usage",
                userInput: "Create a measured task",
                summary: "Create measured task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: []),
            model: ExecutionReceiptModel(provider: "openai.chat_completions", name: "gpt-5.5"),
            usage: ExecutionReceiptUsage(inputTokens: 900, outputTokens: 120, isEstimated: false)
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response)
        )

        viewModel.updateDraftText("Create a measured task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        let preview = viewModel.assistantQueueItem?.costPreview
        XCTAssertEqual(preview?.billingMode, .userProviderBilled)
        XCTAssertEqual(preview?.model, ExecutionReceiptModel(provider: "openai.chat_completions", name: "gpt-5.5"))
        XCTAssertEqual(preview?.executionReceiptUsage.state, .measured)
        XCTAssertEqual(preview?.executionReceiptUsage.inputTokens, 900)
        XCTAssertEqual(preview?.executionReceiptUsage.outputTokens, 120)
        XCTAssertTrue(preview?.allowsApprovalAndRun ?? false)
    }

    func testCodexLocalSubscriptionIsProviderBilledNotLocalOnly() async {
        let response = PlanningResponse(
            providerID: "codex.local",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-codex-subscription",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: []),
            model: ExecutionReceiptModel(provider: "codex.local", name: "gpt-5.4")
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response)
        )

        viewModel.updateDraftText("Create a task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        let preview = viewModel.assistantQueueItem?.costPreview
        XCTAssertEqual(preview?.billingMode, .userProviderBilled)
        XCTAssertNil(preview?.estimatedCostCents)
        XCTAssertEqual(preview?.model?.provider, "codex.local")
    }

    func testGeneratePlanAppliesManagedAIBillingPerRunCapToManagedCostPreview() async {
        let response = PlanningResponse(
            providerID: "suisui.managed",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-managed-preview-cap",
                userInput: "Create a managed task",
                summary: "Create managed task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: []),
            model: ExecutionReceiptModel(provider: "suisui.managed", name: "managed-small"),
            usage: ExecutionReceiptUsage(
                inputTokens: 1_000,
                outputTokens: 1_000,
                estimatedCostCents: nil,
                currencyCode: "USD",
                state: .estimated
            )
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response),
            appSettingsProvider: {
                AppSettings(
                    managedAIBilling: ManagedAIBillingSettings(
                        isEnabled: true,
                        perRunCapCents: 10
                    )
                )
            },
            managedCostRateCardProvider: { response in
                guard response.providerID == "suisui.managed" else {
                    return nil
                }
                return AssistantQueueCostRateCard(
                    provider: "suisui.managed",
                    modelName: "managed-small",
                    currencyCode: "USD",
                    inputTokenCentsPerMillion: 10_000,
                    outputTokenCentsPerMillion: 10_000
                )
            }
        )

        viewModel.updateDraftText("Create a managed task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        let preview = viewModel.assistantQueueItem?.costPreview
        XCTAssertEqual(preview?.billingMode, .suisuiManaged)
        XCTAssertEqual(preview?.estimatedCostCents ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(preview?.capStatus, .wouldExceedLimit)
        XCTAssertFalse(preview?.allowsApprovalAndRun ?? true)
        XCTAssertFalse(viewModel.approveAssistantQueueItem(reviewerID: "local-user"))
    }

    func testGeneratePlanRedactsProviderModelPathBeforeQueuePersistence() async {
        let response = PlanningResponse(
            providerID: "openai.chat_completions",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-redacted-model",
                userInput: "Create a measured task",
                summary: "Create measured task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: []),
            model: ExecutionReceiptModel(
                provider: "openai.chat_completions",
                name: "/Users/alice/private/sk-modelSecret1234567890/model.gguf"
            ),
            usage: ExecutionReceiptUsage(inputTokens: 12, outputTokens: 8, isEstimated: false)
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(response: response)
        )

        viewModel.updateDraftText("Create a measured task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        let modelName = viewModel.assistantQueueItem?.costPreview?.model?.name ?? ""
        XCTAssertFalse(modelName.contains("/Users/alice"))
        XCTAssertFalse(modelName.contains("modelSecret"))
        XCTAssertTrue(modelName.contains("[REDACTED"))
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

    func testAssistantQueueStaleVoiceActionCannotRewindDurableCompletedState() async throws {
        let store = RecordingAssistantQueueStore()
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-stale-voice-transition",
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
        await viewModel.generatePlan(
            currentDate: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC"
        )

        let itemID = "action-plan:plan-stale-voice-transition"
        let waiting = try store.get(id: itemID)
        let approved = try AssistantQueueStateMachine.approve(waiting, reviewerID: "other-window")
        let running = try AssistantQueueStateMachine.startRunning(approved)
        let done = try AssistantQueueStateMachine.markDone(running)
        try store.save(done)

        viewModel.rejectAssistantQueueItem()

        XCTAssertEqual(try store.get(id: itemID).state, .done)
        XCTAssertEqual(viewModel.assistantQueueItem?.state, .done)
        XCTAssertEqual(
            viewModel.auditErrorMessage,
            "This Assistant Queue item changed elsewhere. Review the latest version before acting."
        )
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

    func testUnsafeExternalSendCommandCreatesBlockedGateWithoutProviderCall() async throws {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: provider,
            assistantQueueStore: RecordingAssistantQueueStore()
        )

        viewModel.updateDraftText("Slackに今すぐ送信して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .connectorSendGate)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(viewModel.phase, .reviewReady)
        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.blockingReason, "Slack connector send is not configured. Create a reviewed draft instead; no external message was sent.")
        XCTAssertFalse(viewModel.approveAssistantQueueItem())
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
        XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewStartCommandCreatesActionDraftRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "Open Today Review and start the recommended task",
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

        viewModel.updateDraftText("Open Today Review and start the recommended task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.sourceTranscript, "Open Today Review and start the recommended task")
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, .startRecommended)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewDeferCommandCreatesActionDraftRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "今日のレビューでおすすめを明日に回して",
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

        viewModel.updateDraftText("今日のレビューでおすすめを明日に回して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.sourceTranscript, "今日のレビューでおすすめを明日に回して")
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, .deferRecommendedToTomorrow)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewRescheduleCommandCreatesActionDraftRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "今日のレビューでおすすめを今日にリスケして",
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

        viewModel.updateDraftText("今日のレビューでおすすめを今日にリスケして")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.sourceTranscript, "今日のレビューでおすすめを今日にリスケして")
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, .moveRecommendedDueDateToToday)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewEnglishMoveToTodayCommandCreatesActionDraftRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "Open Today Review and move the recommended task to today",
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

        viewModel.updateDraftText("Open Today Review and move the recommended task to today")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, .moveRecommendedDueDateToToday)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewSplitCommandCreatesActionDraftRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "今日のレビューでおすすめを分割して",
                summary: "Should not call provider",
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

        viewModel.updateDraftText("今日のレビューでおすすめを分割して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.sourceTranscript, "今日のレビューでおすすめを分割して")
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, .splitRecommendedTask)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewEnglishSplitCommandCreatesActionDraftRequestWithoutProviderCall() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "Open Today Review and split the recommended task",
                summary: "Should not call provider",
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

        viewModel.updateDraftText("Open Today Review and split the recommended task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.planningResponse)
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, .splitRecommendedTask)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewAmbiguousMoveToTodayPhrasesStayReviewOnly() async {
        for transcript in [
            "Today review should I reschedule the recommended task to today?",
            "Open Today Review but do not reschedule the recommended task to today",
            "Open Today Review and start the recommended task, then move the recommended task to today",
            "Today review should I split the recommended task?",
            "Open Today Review but do not split the recommended task",
            "Open Today Review and split the recommended task, then move the recommended task to today"
        ] {
            let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: ActionPlan(
                    id: "plan-should-not-run",
                    userInput: transcript,
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

            viewModel.updateDraftText(transcript)
            await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

            XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview, transcript)
            XCTAssertEqual(provider.requests.count, 0, transcript)
            XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind, transcript)
            XCTAssertEqual(viewModel.phase, .reviewReady, transcript)
        }
    }

    func testDailyPlanningReviewNegativeActionPhraseStaysReviewOnly() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "Open Today Review but do not start the recommended task",
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

        viewModel.updateDraftText("Open Today Review but do not start the recommended task")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewTomorrowContextWithoutDeferPhraseStaysReviewOnly() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "今日のレビューでおすすめを確認して、明日の予定も見せて",
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

        viewModel.updateDraftText("今日のレビューでおすすめを確認して、明日の予定も見せて")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewQuestionAboutDeferStaysReviewOnly() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "今日のレビューでおすすめを明日に回すか確認して",
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

        viewModel.updateDraftText("今日のレビューでおすすめを明日に回すか確認して")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind)
        XCTAssertEqual(viewModel.phase, .reviewReady)
    }

    func testDailyPlanningReviewEnglishQuestionAboutStartStaysReviewOnly() async {
        let provider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-should-not-run",
                userInput: "Today review should I start the recommended task?",
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

        viewModel.updateDraftText("Today review should I start the recommended task?")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")

        XCTAssertEqual(viewModel.routingResult?.intent, .dailyPlanningReview)
        XCTAssertEqual(provider.requests.count, 0)
        XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind)
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
        XCTAssertNil(viewModel.dailyPlanningReviewRequest?.requestedActionDraftKind)
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
            "Suisui",
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
        XCTAssertTrue(provider.requests[0].userInput.contains("project: Suisui"))
    }

    func testInjectedConversationOrchestratorOwnsClarificationAndReviewTransition() async {
        let plan = ActionPlan(
            id: "orchestrated-plan",
            userInput: "これ明日やって",
            summary: "Create clarified task",
            actions: [PlanAction(id: "action-1", tool: .taskCreate)],
            riskLevel: .write,
            requiresApproval: true
        )
        let orchestrator = RecordingVoiceConversationOrchestrator(
            outcomes: [
                .clarification(
                    ClarificationQuestion(
                        slot: .taskTitle,
                        prompt: "What should the task be called?"
                    )
                ),
                .review(plan),
            ]
        )
        let sessionID = UUID()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: ActionPlanValidationResult(issues: [])
                )
            ),
            conversationOrchestrator: orchestrator,
            conversationSessionID: sessionID
        )

        viewModel.updateDraftText("これ明日やって")
        await viewModel.generatePlan()
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .taskTitle)

        await viewModel.submitClarificationAnswer("リリースメモを書く")

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(
            viewModel.planningResponse?.actionPlan?.id,
            "orchestrated-plan"
        )
        let events = await orchestrator.recordedEvents
        XCTAssertEqual(events, [
            .begin(sessionID: sessionID),
            .answer(sessionID: sessionID, value: "リリースメモを書く"),
        ])
    }

    func testDeterministicConversationAnswerPublishesStructuredTaskItems() async {
        let items = [
            VoiceTaskConversationAnswerItem(
                id: "task:11",
                label: "Prepare review"
            ),
            VoiceTaskConversationAnswerItem(
                id: "task:22",
                label: "Submit summary"
            ),
        ]
        let orchestrator = RecordingVoiceConversationOrchestrator(
            outcomes: [
                .answer(
                    VoiceTaskConversationAnswer(
                        text: "Prepare review\nSubmit summary",
                        items: items,
                        source: .localDeterministic
                    )
                ),
            ]
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: ActionPlanValidationResult(issues: [])
                )
            ),
            conversationOrchestrator: orchestrator,
            conversationSessionID: UUID()
        )

        viewModel.updateDraftText("List tasks")
        await viewModel.generatePlan()

        XCTAssertEqual(
            viewModel.conversationWorkspaceLocalAnswerItems,
            items
        )
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testOrchestratedReviewPersistsQueueBoundConversationLink() async throws {
        let plan = ActionPlan(
            id: "orchestrated-linked-plan",
            userInput: "これ明日やって",
            summary: "Create clarified task",
            actions: [
                PlanAction(
                    id: "action-create",
                    tool: .taskCreate,
                    arguments: ["title": .string("リリースメモを書く")]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let orchestrator = RecordingReviewPersistingConversationOrchestrator(
            outcomes: [
                .clarification(
                    ClarificationQuestion(
                        slot: .taskTitle,
                        prompt: "What should the task be called?"
                    )
                ),
                .review(plan),
            ]
        )
        let queueStore = RecordingAssistantQueueStore()
        let sessionID = UUID()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: ActionPlanValidationResult(issues: [])
                )
            ),
            assistantQueueStore: queueStore,
            conversationOrchestrator: orchestrator,
            conversationSessionID: sessionID
        )

        viewModel.updateDraftText("これ明日やって")
        await viewModel.generatePlan()
        await viewModel.submitClarificationAnswer("リリースメモを書く")

        let queueItem = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(queueStore.savedItems.last?.id, queueItem.id)
        XCTAssertEqual(
            queueStore.savedItems.map(\.state),
            [.blocked, .waitingReview]
        )
        XCTAssertNotNil(queueStore.savedItems.first?.blockingReason)
        XCTAssertNil(queueStore.savedItems.last?.blockingReason)
        let reviews = await orchestrator.persistedReviews
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews.first?.sessionID, sessionID)
        XCTAssertEqual(reviews.first?.plan, plan)
        XCTAssertEqual(reviews.first?.queueItem.id, queueItem.id)
        XCTAssertEqual(reviews.first?.confirmedText, plan.userInput)
    }

    func testOrchestratedReviewWithoutReviewLinkPersisterDoesNotPublishQueueItem() async {
        let plan = ActionPlan(
            id: "orchestrated-unlinked-plan",
            userInput: "これ明日やって",
            summary: "Create release task",
            actions: [
                PlanAction(
                    id: "action-create",
                    tool: .taskCreate,
                    arguments: ["title": .string("Write release notes")]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let queueStore = RecordingAssistantQueueStore()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            ),
            assistantQueueStore: queueStore,
            conversationOrchestrator: RecordingVoiceConversationOrchestrator(
                outcomes: [.review(plan)]
            ),
            conversationSessionID: UUID()
        )

        viewModel.updateDraftText(plan.userInput)
        await viewModel.generatePlan()

        XCTAssertTrue(queueStore.savedItems.isEmpty)
        XCTAssertNil(viewModel.assistantQueueItem)
        guard case .failed = viewModel.phase else {
            return XCTFail("Unlinked conversation review must fail closed")
        }
    }

    func testOrchestratedReviewQueueIDCollisionDoesNotMutateExistingItem() async throws {
        let plan = ActionPlan(
            id: "orchestrated-collision-plan",
            userInput: "これ明日やって",
            summary: "Create release task",
            actions: [
                PlanAction(
                    id: "action-create",
                    tool: .taskCreate,
                    arguments: ["title": .string("Write release notes")]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let collisionStates: [AssistantQueueState] = [
            .captured, .interpreted, .drafted, .waitingReview,
            .approved, .running, .blocked, .done, .failed, .rejected,
            .deferred,
        ]

        for collisionState in collisionStates {
            let queueStore = RecordingAssistantQueueStore { proposed in
                var existing = proposed
                existing.state = collisionState
                existing.blockingReason = nil
                return existing
            }
            let orchestrator = RecordingReviewPersistingConversationOrchestrator(
                outcomes: [.review(plan)]
            )
            let viewModel = VoiceCaptureViewModel(
                audioRecorder: FakeAudioRecorder(),
                sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
                llmProvider: FakeLLMProvider(
                    response: PlanningResponse(
                        providerID: "unused",
                        rawContent: "{}",
                        actionPlan: nil,
                        validationResult: .init(issues: [])
                    )
                ),
                assistantQueueStore: queueStore,
                conversationOrchestrator: orchestrator,
                conversationSessionID: UUID()
            )

            viewModel.updateDraftText(plan.userInput)
            await viewModel.generatePlan()

            XCTAssertEqual(queueStore.collidedItem?.state, collisionState)
            XCTAssertTrue(
                queueStore.savedItems.isEmpty,
                "Collision in \(collisionState) must not be overwritten"
            )
            let reviews = await orchestrator.persistedReviews
            XCTAssertTrue(reviews.isEmpty)
        }
    }

    func testOrchestratedReviewQueueIDCollisionWithDifferentContentFailsClosed() async {
        let plan = ActionPlan(
            id: "orchestrated-content-collision-plan",
            userInput: "これ明日やって",
            summary: "Create release task",
            actions: [
                PlanAction(
                    id: "action-create",
                    tool: .taskCreate,
                    arguments: ["title": .string("Write release notes")]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let queueStore = RecordingAssistantQueueStore { proposed in
            var existing = proposed
            existing.redactedSummary = "Different queued work"
            return existing
        }
        let orchestrator = RecordingReviewPersistingConversationOrchestrator(
            outcomes: [.review(plan)]
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            ),
            assistantQueueStore: queueStore,
            conversationOrchestrator: orchestrator,
            conversationSessionID: UUID()
        )

        viewModel.updateDraftText(plan.userInput)
        await viewModel.generatePlan()

        XCTAssertEqual(
            queueStore.collidedItem?.redactedSummary,
            "Different queued work"
        )
        XCTAssertTrue(queueStore.savedItems.isEmpty)
        let reviews = await orchestrator.persistedReviews
        XCTAssertTrue(reviews.isEmpty)
    }

    func testOrchestratedReviewRetriesMatchingBlockedProvisionalWithCAS() async throws {
        let plan = ActionPlan(
            id: "orchestrated-provisional-retry-plan",
            userInput: "これ明日やって",
            summary: "Create release task",
            actions: [
                PlanAction(
                    id: "action-create",
                    tool: .taskCreate,
                    arguments: ["title": .string("Write release notes")]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let queueStore = RecordingAssistantQueueStore { $0 }
        let orchestrator = RecordingReviewPersistingConversationOrchestrator(
            outcomes: [.review(plan)]
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            ),
            assistantQueueStore: queueStore,
            conversationOrchestrator: orchestrator,
            conversationSessionID: UUID()
        )

        viewModel.updateDraftText(plan.userInput)
        await viewModel.generatePlan()

        XCTAssertEqual(viewModel.assistantQueueItem?.state, .waitingReview)
        XCTAssertEqual(queueStore.savedItems.map(\.state), [.waitingReview])
        let reviews = await orchestrator.persistedReviews
        XCTAssertEqual(reviews.count, 1)
    }

    func testRestoreConversationPublishesPersistedClarificationQuestion() async {
        let sessionID = UUID()
        let orchestrator = RecordingVoiceConversationOrchestrator(
            outcomes: [
                .clarification(
                    ClarificationQuestion(
                        slot: .dueDate,
                        prompt: "When is the due date?"
                    )
                ),
            ]
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "")),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: ActionPlanValidationResult(issues: [])
                )
            ),
            conversationOrchestrator: orchestrator,
            conversationSessionID: sessionID
        )

        await viewModel.restoreConversationIfNeeded()

        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .dueDate)
        XCTAssertEqual(viewModel.phase, .needsClarification("When is the due date?"))
        let events = await orchestrator.recordedEvents
        XCTAssertEqual(
            events,
            [.restore(sessionID: sessionID)]
        )
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
            outputURL: URL(filePath: "/tmp/suisui-clarification-answer.m4a"),
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
            outputURL: URL(filePath: "/tmp/suisui-test.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(viewModel.draft.text, "Create a task")
        XCTAssertEqual(viewModel.recordedAudio?.duration, 2)
    }

    func testClearDeletesUnsavedTemporaryVoiceRecording() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "suisui-clear-unsaved-\(UUID().uuidString).m4a"
            )
        try Data("audio".utf8).write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "Create a task")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            )
        )

        await viewModel.startRecording()
        await viewModel.stopRecording(outputURL: outputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        viewModel.clear()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outputURL.path)
        )
    }

    func testStartingNewRecordingDeletesPreviousUnsavedTemporaryRecording() async throws {
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-replaced-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: firstURL)
        defer { try? FileManager.default.removeItem(at: firstURL) }
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "First recording")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            )
        )

        await viewModel.startRecording()
        await viewModel.stopRecording(outputURL: firstURL)
        await viewModel.startRecording()

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
    }

    func testStartingNewRecordingKeepsPreviousInboxSavedRecording() async throws {
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-saved-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: firstURL)
        defer { try? FileManager.default.removeItem(at: firstURL) }
        let task = ProjectBoardTask(
            id: 42,
            projectID: 1,
            title: "First recording",
            detail: "",
            status: .backlog,
            priority: .medium,
            dueAt: nil
        )
        let capture = InboxCaptureRecord(
            id: 7,
            taskID: task.id,
            sourceKind: .voiceMemo,
            audioFilePath: firstURL.path,
            durationSeconds: 1,
            transcript: "First recording",
            interpretationSummary: "Saved",
            memo: "",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-07-30T00:00:00Z"
        )
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "First recording")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            ),
            inboxCaptureSaver: RecordingInboxVoiceCaptureSaver(
                result: .init(task: task, capture: capture)
            )
        )

        await viewModel.startRecording()
        await viewModel.stopRecording(outputURL: firstURL)
        viewModel.saveDraftToInbox()
        await viewModel.startRecording()

        XCTAssertTrue(FileManager.default.fileExists(atPath: firstURL.path))
    }

    func testReleaseTemporaryRecordingResourcesDeletesUnsavedRecording() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-teardown-\(UUID().uuidString).m4a")
        try Data("audio".utf8).write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                transcript: STTTranscript(text: "Temporary recording")
            ),
            llmProvider: FakeLLMProvider(
                response: PlanningResponse(
                    providerID: "unused",
                    rawContent: "{}",
                    actionPlan: nil,
                    validationResult: .init(issues: [])
                )
            )
        )

        await viewModel.startRecording()
        await viewModel.stopRecording(outputURL: outputURL)
        viewModel.releaseTemporaryRecordingResources()

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testSaveDraftToInboxPersistsRecordedTranscriptAfterTranscription() async {
        let task = ProjectBoardTask(
            id: 42,
            projectID: 1,
            title: "Create a task",
            detail: "",
            status: .backlog,
            priority: .medium,
            dueAt: nil
        )
        let capture = InboxCaptureRecord(
            id: 7,
            taskID: task.id,
            sourceKind: .voiceMemo,
            audioFilePath: "/tmp/suisui-test.m4a",
            durationSeconds: 2,
            transcript: "Create a task",
            interpretationSummary: "Route as task.create for a reviewable local task draft.",
            memo: "Confidence: 0.91",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:27:00Z"
        )
        let saver = RecordingInboxVoiceCaptureSaver(result: InboxVoiceCaptureResult(task: task, capture: capture))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            inboxCaptureSaver: saver
        )

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/suisui-test.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertTrue(viewModel.canSaveDraftToInbox)
        viewModel.saveDraftToInbox(
            at: Date(timeIntervalSince1970: 13),
            createdAt: "2026-06-21T10:27:00Z"
        )

        XCTAssertEqual(saver.requests.map(\.transcript?.text), ["Create a task"])
        XCTAssertEqual(saver.requests.first?.audio.fileURL.path, "/tmp/suisui-test.m4a")
        XCTAssertEqual(viewModel.inboxCaptureResult, InboxVoiceCaptureResult(task: task, capture: capture))
        XCTAssertNil(viewModel.auditErrorMessage)
    }

    func testSaveDraftToInboxRequiresRecordedAudioAndSaver() {
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

        viewModel.updateDraftText("Create a task")
        viewModel.saveDraftToInbox()

        XCTAssertFalse(viewModel.canSaveDraftToInbox)
        XCTAssertNil(viewModel.inboxCaptureResult)
        XCTAssertEqual(viewModel.auditErrorMessage, "Voice Inbox capture is unavailable because local voice stores could not be opened.")
    }

    func testSaveDraftToInboxIsDisabledAfterSuccessfulSaveForSameAudio() async {
        let task = ProjectBoardTask(
            id: 42,
            projectID: 1,
            title: "Create a task",
            detail: "",
            status: .backlog,
            priority: .medium,
            dueAt: nil
        )
        let capture = InboxCaptureRecord(
            id: 7,
            taskID: task.id,
            sourceKind: .voiceMemo,
            audioFilePath: "/tmp/suisui-test.m4a",
            durationSeconds: 2,
            transcript: "Create a task",
            interpretationSummary: "Route as task.create for a reviewable local task draft.",
            memo: "Confidence: 0.91",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:27:00Z"
        )
        let saver = RecordingInboxVoiceCaptureSaver(result: InboxVoiceCaptureResult(task: task, capture: capture))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            inboxCaptureSaver: saver
        )

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/suisui-test.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )

        viewModel.saveDraftToInbox()
        viewModel.saveDraftToInbox()

        XCTAssertFalse(viewModel.canSaveDraftToInbox)
        XCTAssertEqual(saver.requests.count, 1)
    }

    func testSaveDraftToInboxDoesNotUseStaleDraftAfterTranscriptionFailure() async {
        let task = ProjectBoardTask(
            id: 42,
            projectID: 1,
            title: "Create a task",
            detail: "",
            status: .backlog,
            priority: .medium,
            dueAt: nil
        )
        let capture = InboxCaptureRecord(
            id: 7,
            taskID: task.id,
            sourceKind: .voiceMemo,
            audioFilePath: "/tmp/suisui-test.m4a",
            durationSeconds: 2,
            transcript: "Create a task",
            interpretationSummary: "Route as task.create for a reviewable local task draft.",
            memo: "Confidence: 0.91",
            classificationStatus: .unclassified,
            transcriptionStatus: .succeeded,
            createdAt: "2026-06-21T10:27:00Z"
        )
        let saver = RecordingInboxVoiceCaptureSaver(result: InboxVoiceCaptureResult(task: task, capture: capture))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(
                availability: STTProviderAvailability(providerID: .whisperKit, isAvailable: false, reason: "Model missing"),
                transcript: STTTranscript(text: "")
            ),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            inboxCaptureSaver: saver
        )

        viewModel.updateDraftText("Create a stale task")
        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))
        await viewModel.stopRecording(
            outputURL: URL(filePath: "/tmp/suisui-failed.m4a"),
            at: Date(timeIntervalSince1970: 12)
        )
        viewModel.saveDraftToInbox()

        XCTAssertFalse(viewModel.canSaveDraftToInbox)
        XCTAssertEqual(saver.requests.count, 0)
        XCTAssertNil(viewModel.inboxCaptureResult)
        XCTAssertEqual(viewModel.auditErrorMessage, "Transcribe audio before saving to Inbox.")
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
            outputURL: URL(filePath: "/tmp/suisui-test-first.m4a"),
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

    func testLowLatencyAgentModeDoesNotStartRecordingAutomatically() {
        let provider = StreamingSTTProviderFixture()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: provider,
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .idle)
        XCTAssertFalse(viewModel.isLowLatencyVoiceAgentListening)
        XCTAssertFalse(provider.didStartStreaming)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testLowLatencyAgentModePublishesPartialTranscriptAndIntentWithoutProviderPlanning() async {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "unexpected-provider-plan",
                userInput: "Should not be called for partials",
                summary: "Should not be used",
                actions: [PlanAction(id: "unexpected", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        sttProvider.yield(.partial(STTTranscript(text: "Slackに今すぐ送信して")))
        let didPublishPreview = await waitForVoiceCondition { viewModel.liveIntentPreview != nil }
        XCTAssertTrue(didPublishPreview)

        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)
        XCTAssertEqual(viewModel.liveTranscript, "Slackに今すぐ送信して")
        XCTAssertEqual(viewModel.liveIntentPreview?.intent, .connectorSendGate)
        XCTAssertEqual(viewModel.draft.text, "")
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertTrue(llmProvider.requests.isEmpty)
    }

    func testLowLatencyAgentModeStopCancelsStreamAndClearsInFlightPartialState() async {
        let sttProvider = StreamingSTTProviderFixture()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        sttProvider.yield(.partial(STTTranscript(text: "Create")))
        let didPublishTranscript = await waitForVoiceCondition { viewModel.liveTranscript == "Create" }
        XCTAssertTrue(didPublishTranscript)
        viewModel.stopLowLatencyVoiceAgentMode()
        let didCancelStream = await waitForVoiceCondition { sttProvider.didCancelStream }
        XCTAssertTrue(didCancelStream)

        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .idle)
        XCTAssertFalse(viewModel.isLowLatencyVoiceAgentListening)
        XCTAssertEqual(viewModel.liveTranscript, "")
        XCTAssertNil(viewModel.liveIntentPreview)
    }

    func testLowLatencyAgentModeUsesSegmentedLocalBatchTranscriptionWhenProviderDoesNotStream() async throws {
        let sttProvider = FakeSTTProvider(id: .whisperCpp, transcript: STTTranscript(text: "Slackに今すぐ送信して"))
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            appSettingsProvider: {
                AppSettings(
                    sttProvider: .localWhisperCpp,
                    isLowLatencyVoiceAgentModeEnabled: true
                )
            },
            lowLatencySegmentDuration: 0,
            lowLatencySegmentOutputURLProvider: { URL(filePath: "/tmp/suisui-low-latency-segment.m4a") }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        let didQueueSegmentedItem = await waitForVoiceCondition { viewModel.assistantQueueItem != nil }
        XCTAssertTrue(didQueueSegmentedItem)

        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .idle)
        XCTAssertEqual(viewModel.recordingState, .completed(RecordedAudio(
            fileURL: URL(filePath: "/tmp/suisui-low-latency-segment.m4a"),
            format: .m4a,
            duration: viewModel.recordingState.completedAudioDuration
        )))
        XCTAssertEqual(item.state, .blocked)
        XCTAssertTrue(llmProvider.requests.isEmpty)
    }

    func testLowLatencyAgentModeRejectsCloudBatchSTTWithoutVisibleFallback() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(id: .openAITranscribe, transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            appSettingsProvider: {
                AppSettings(
                    sttProvider: .openAITranscribe,
                    isLowLatencyVoiceAgentModeEnabled: true,
                    isLowLatencyVoiceAgentCloudFallbackEnabled: false,
                    isLowLatencyVoiceAgentCloudFallbackCostVisible: false
                )
            },
            lowLatencySegmentDuration: 0
        )

        await viewModel.startLowLatencyVoiceAgentMode()

        XCTAssertEqual(
            viewModel.lowLatencyVoiceAgentState,
            .unavailable("Select local speech-to-text, or enable visible realtime cloud cost before using low-latency voice agent mode.")
        )
        XCTAssertEqual(viewModel.draft.text, "")
    }

    func testLowLatencyAgentModeRejectsProviderSettingsMismatchBeforeTranscription() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(id: .openAITranscribe, transcript: STTTranscript(text: "Create a task")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() },
            lowLatencySegmentDuration: 0
        )

        await viewModel.startLowLatencyVoiceAgentMode()

        XCTAssertEqual(
            viewModel.lowLatencyVoiceAgentState,
            .unavailable("Restart Voice Command after changing speech-to-text provider settings.")
        )
        XCTAssertEqual(viewModel.recordingState, .idle)
        XCTAssertEqual(viewModel.draft.text, "")
    }

    func testLowLatencyAgentModeRejectsCloudStreamingSTTWithoutVisibleFallback() async {
        let sttProvider = StreamingSTTProviderFixture(id: .openAITranscribe)
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            appSettingsProvider: {
                AppSettings(
                    sttProvider: .openAITranscribe,
                    isLowLatencyVoiceAgentModeEnabled: true,
                    isLowLatencyVoiceAgentCloudFallbackEnabled: false,
                    isLowLatencyVoiceAgentCloudFallbackCostVisible: false
                )
            }
        )

        await viewModel.startLowLatencyVoiceAgentMode()

        XCTAssertEqual(
            viewModel.lowLatencyVoiceAgentState,
            .unavailable("Select local speech-to-text, or enable visible realtime cloud cost before using low-latency voice agent mode.")
        )
        XCTAssertFalse(sttProvider.didStartStreaming)
    }

    func testStartingRecordingStopsLowLatencyAgentModeBeforeRecorderUse() async {
        let sttProvider = StreamingSTTProviderFixture()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)

        await viewModel.startRecording(at: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(viewModel.phase, .recording)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .idle)
        let didCancelStream = await waitForVoiceCondition { sttProvider.didCancelStream }
        XCTAssertTrue(didCancelStream)
    }

    func testLowLatencyAgentModeStopIgnoresLateFinalTranscript() async {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "late-plan",
                userInput: "Late transcript",
                summary: "Should not be queued",
                actions: [PlanAction(id: "late-action", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        viewModel.stopLowLatencyVoiceAgentMode()
        sttProvider.yield(.final(STTTranscript(text: "Create a late task")))
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .idle)
        XCTAssertEqual(viewModel.draft.text, "")
        XCTAssertNil(viewModel.assistantQueueItem)
        XCTAssertTrue(llmProvider.requests.isEmpty)
    }

    func testLowLatencyAgentModeFinalPlanningCommandDoesNotCancelProviderRequest() async throws {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = CancellationAwareVoiceLLMProvider(response: PlanningResponse(
            providerID: "cancellation-aware",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-low-latency-final",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-create", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            assistantQueueStore: RecordingAssistantQueueStore(),
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        sttProvider.yield(.final(STTTranscript(text: "Create a task")))
        let didQueuePlanningItem = await waitForVoiceCondition { viewModel.assistantQueueItem != nil }
        XCTAssertTrue(didQueuePlanningItem)

        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(item.sourceTranscript, "Create a task")
        XCTAssertEqual(llmProvider.requests.count, 1)
        XCTAssertFalse(llmProvider.didObserveCancellation)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)
        viewModel.stopLowLatencyVoiceAgentMode()
    }

    func testLowLatencyAgentModeFinalCommandCreatesAssistantQueueItemBeforeExecution() async throws {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let store = RecordingAssistantQueueStore()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            assistantQueueStore: store,
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        sttProvider.yield(.final(STTTranscript(text: "Slackに今すぐ送信して token=sk-low-latency-secret")))
        let didQueueConnectorItem = await waitForVoiceCondition { viewModel.assistantQueueItem != nil }
        XCTAssertTrue(didQueueConnectorItem)

        XCTAssertEqual(viewModel.phase, .reviewReady)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)
        XCTAssertTrue(llmProvider.requests.isEmpty)
        let item = try XCTUnwrap(viewModel.assistantQueueItem)
        XCTAssertEqual(store.savedItems.map(\.id), [item.id])
        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.requiredCapabilities, [
            .externalConnector(serviceID: "slack", action: "message.send"),
            .providerExecutionApproval
        ])
        XCTAssertFalse(item.redactedSummary.contains("sk-low-latency-secret"))
        viewModel.stopLowLatencyVoiceAgentMode()
    }

    func testLowLatencyAgentModeNativeStreamHandlesMultipleFinalCommandsUntilStop() async throws {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let store = RecordingAssistantQueueStore()
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            assistantQueueStore: store,
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        sttProvider.yield(.final(STTTranscript(text: "Slackに今すぐ送信して 最初の連絡")))
        let didQueueFirstItem = await waitForVoiceCondition { store.savedItems.count == 1 }
        XCTAssertTrue(didQueueFirstItem)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)

        sttProvider.yield(.final(STTTranscript(text: "Slackに今すぐ送信して 次の連絡")))
        let didQueueSecondItem = await waitForVoiceCondition { store.savedItems.count == 2 }
        XCTAssertTrue(didQueueSecondItem)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)

        sttProvider.yield(.stopped)
        let didStop = await waitForVoiceCondition { viewModel.lowLatencyVoiceAgentState == .idle }
        XCTAssertTrue(didStop)
        XCTAssertTrue(llmProvider.requests.isEmpty)
    }

    func testLowLatencyAgentModeClarificationUsesStreamingFinalTranscriptAsVoiceAnswer() async {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        viewModel.updateDraftText("これ明日やって")
        await viewModel.generatePlan(currentDate: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC")
        XCTAssertEqual(viewModel.clarificationQuestion?.slot, .taskTitle)

        await viewModel.startLowLatencyVoiceAgentMode(currentDate: Date(timeIntervalSince1970: 1), timeZoneIdentifier: "UTC")
        sttProvider.yield(.final(STTTranscript(text: "リリースメモを書く")))
        let didCaptureVoiceAnswer = await waitForVoiceCondition { viewModel.clarificationSession?.turns.first?.inputMode == .voice }
        XCTAssertTrue(didCaptureVoiceAnswer)

        XCTAssertEqual(viewModel.draft.text, "これ明日やって")
        XCTAssertEqual(viewModel.clarificationSession?.turns.first?.answer, .text("リリースメモを書く"))
        XCTAssertEqual(viewModel.clarificationSession?.turns.first?.inputMode, .voice)
        XCTAssertEqual(viewModel.lowLatencyVoiceAgentState, .listening)
        XCTAssertTrue(llmProvider.requests.isEmpty)
        viewModel.stopLowLatencyVoiceAgentMode()
    }

    func testLowLatencyAgentModeSplitsFinalizedAndPendingTranscriptSegments() async {
        let sttProvider = StreamingSTTProviderFixture()
        let llmProvider = RecordingVoiceLLMProvider(response: PlanningResponse(
            providerID: "recording",
            rawContent: "{}",
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: [])
        ))
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            appSettingsProvider: { Self.lowLatencyLocalVoiceAgentSettings() }
        )

        await viewModel.startLowLatencyVoiceAgentMode()
        sttProvider.yield(.partial(STTTranscript(text: "Create a")))
        let didPublishPending = await waitForVoiceCondition { viewModel.pendingTranscript == "Create a" }
        XCTAssertTrue(didPublishPending)
        XCTAssertEqual(viewModel.finalizedTranscript, "")
        XCTAssertEqual(viewModel.liveTranscript, "Create a")

        sttProvider.yield(.final(STTTranscript(text: "Create a release notes task")))
        let didFinalize = await waitForVoiceCondition { viewModel.finalizedTranscript == "Create a release notes task" }
        XCTAssertTrue(didFinalize)
        XCTAssertEqual(viewModel.pendingTranscript, "")
        XCTAssertEqual(viewModel.liveTranscript, "Create a release notes task")

        viewModel.stopLowLatencyVoiceAgentMode()
        XCTAssertEqual(viewModel.finalizedTranscript, "")
        XCTAssertEqual(viewModel.pendingTranscript, "")
        XCTAssertEqual(viewModel.liveTranscript, "")
    }

    func testRecordingPublishesNormalizedInputLevelFromMeteringRecorder() async {
        let recorder = MeteringFakeAudioRecorder()
        recorder.levelToReturn = 0.75
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: recorder,
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "hello")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.startRecording()
        let didPublishLevel = await waitForVoiceCondition { viewModel.inputLevel == 0.75 }
        XCTAssertTrue(didPublishLevel)
        XCTAssertEqual(viewModel.inputLevelMeter.inputLevel, 0.75)

        await viewModel.stopRecording(
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("suisui-metering-test-\(UUID().uuidString).m4a")
        )
        XCTAssertEqual(viewModel.inputLevel, 0)
    }

    func testSilenceHintAppearsAfterContinuousSilenceAndClearsWhenLevelRecovers() async {
        let recorder = MeteringFakeAudioRecorder()
        recorder.levelToReturn = 0.0
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: recorder,
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "hello")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            )),
            microphoneSilenceDetector: MicrophoneSilenceDetector(threshold: 0.05, requiredSilenceDuration: 0.2)
        )

        await viewModel.startRecording()
        XCTAssertFalse(viewModel.isMicrophoneSilenceHintVisible)
        let didShowHint = await waitForVoiceCondition(timeout: 2) { viewModel.isMicrophoneSilenceHintVisible }
        XCTAssertTrue(didShowHint)

        recorder.levelToReturn = 0.6
        let didClearHint = await waitForVoiceCondition { !viewModel.isMicrophoneSilenceHintVisible }
        XCTAssertTrue(didClearHint)

        viewModel.clear()
        XCTAssertFalse(viewModel.isMicrophoneSilenceHintVisible)
        XCTAssertEqual(viewModel.inputLevel, 0)
    }

    func testRecordingWithoutMeteringCapableRecorderKeepsLevelIdle() async {
        let viewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "hello")),
            llmProvider: FakeLLMProvider(response: PlanningResponse(
                providerID: "fake",
                rawContent: "{}",
                actionPlan: nil,
                validationResult: ActionPlanValidationResult(issues: [])
            ))
        )

        await viewModel.startRecording()
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(viewModel.inputLevel, 0)
        XCTAssertFalse(viewModel.isMicrophoneSilenceHintVisible)
        viewModel.clear()
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

    private func waitForVoiceCondition(
        timeout: TimeInterval = 1,
        condition: @MainActor @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    nonisolated private static func lowLatencyLocalVoiceAgentSettings() -> AppSettings {
        AppSettings(
            sttProvider: .localWhisperCpp,
            isLowLatencyVoiceAgentModeEnabled: true
        )
    }
}

private final class MutableCodexApprovalForVoice: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: ApprovedCodexExecutable?

    init(_ value: ApprovedCodexExecutable?) {
        storedValue = value
    }

    var value: ApprovedCodexExecutable? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedValue
        }
        set {
            lock.lock()
            storedValue = newValue
            lock.unlock()
        }
    }
}

private actor VoiceRecordingVersionReporter: CodexVersionReporting {
    private(set) var callCount = 0

    func versionOutput(approvedExecutable _: ApprovedCodexExecutable) async throws -> String {
        callCount += 1
        return "codex-cli 0.144.1"
    }
}

private extension AudioRecordingState {
    var completedAudioDuration: TimeInterval? {
        guard case .completed(let audio) = self else {
            return nil
        }
        return audio.duration
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
    private let queue = DispatchQueue(label: "dev.suisui.tests.recording-voice-llm-provider")
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

private final class CancellationAwareVoiceLLMProvider: LLMProvider, @unchecked Sendable {
    let providerID: String = "cancellation-aware"
    private let response: PlanningResponse
    private let queue = DispatchQueue(label: "dev.suisui.tests.cancellation-aware-voice-llm-provider")
    private var recordedRequests: [PlanningRequest] = []
    private var observedCancellation = false

    init(response: PlanningResponse) {
        self.response = response
    }

    var requests: [PlanningRequest] {
        queue.sync { recordedRequests }
    }

    var didObserveCancellation: Bool {
        queue.sync { observedCancellation }
    }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        queue.sync {
            recordedRequests.append(request)
            observedCancellation = Task.isCancelled
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        return response
    }
}

private final class DelayedRecordingVoiceLLMProvider: LLMProvider, @unchecked Sendable {
    let providerID: String = "delayed-recording"
    private let gate: VoicePlanningGate
    private let response: PlanningResponse
    private let queue = DispatchQueue(label: "dev.suisui.tests.delayed-recording-voice-llm-provider")
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

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SuisuiVoiceCaptureViewModelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private struct StaticProjectWorkspaceBookmarkResolver: ProjectWorkspaceBookmarkResolving {
    var url: URL

    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        ProjectWorkspaceBookmarkResolution(
            url: url,
            isStale: false,
            didStartAccessing: true,
            stopAccessing: {}
        )
    }
}

@MainActor
private final class RecordingInboxVoiceCaptureSaver: InboxVoiceCaptureSaving {
    struct Request: Equatable {
        var audio: RecordedAudio
        var transcript: STTTranscript?
        var transcriptionErrorMessage: String?
        var date: Date
        var createdAt: String?
    }

    private let result: InboxVoiceCaptureResult
    private(set) var requests: [Request] = []

    init(result: InboxVoiceCaptureResult) {
        self.result = result
    }

    func saveTranscribedCapture(
        audio: RecordedAudio,
        transcript: STTTranscript?,
        transcriptionErrorMessage: String?,
        at date: Date,
        createdAt: String?
    ) throws -> InboxVoiceCaptureResult {
        requests.append(Request(
            audio: audio,
            transcript: transcript,
            transcriptionErrorMessage: transcriptionErrorMessage,
            date: date,
            createdAt: createdAt
        ))
        return result
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
    private(set) var collidedItem: AssistantQueueItem?
    private var items: [String: AssistantQueueItem] = [:]
    private let saveError: Error?
    private let collisionTransform:
        ((AssistantQueueItem) -> AssistantQueueItem)?

    init(
        saveError: Error? = nil,
        collisionTransform:
            ((AssistantQueueItem) -> AssistantQueueItem)? = nil
    ) {
        self.saveError = saveError
        self.collisionTransform = collisionTransform
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

    func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? {
        if let collisionTransform, items[item.id] == nil {
            let collision = collisionTransform(item)
            items[item.id] = collision
            collidedItem = collision
            return nil
        }
        guard items[item.id] == nil else {
            return nil
        }
        return try save(item)
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

/// Class-based fake so the view model's `any AudioRecorder` storage and the
/// test share one instance, letting tests steer the reported input level while
/// the ~10Hz monitor task is polling.
@MainActor
private final class MeteringFakeAudioRecorder: AudioRecorder, AudioInputLevelReading {
    private(set) var state: AudioRecordingState = .idle
    var levelToReturn: Double?

    func start(at date: Date) async throws {
        state = .recording(startedAt: date)
    }

    func stop(outputURL: URL, at date: Date) throws -> RecordedAudio {
        guard case .recording(let startedAt) = state else {
            throw AudioRecorderError.notRecording
        }
        let audio = RecordedAudio(
            fileURL: outputURL,
            format: .m4a,
            duration: max(0, date.timeIntervalSince(startedAt))
        )
        state = .completed(audio)
        return audio
    }

    func reset() {
        state = .idle
    }

    var currentNormalizedInputLevel: Double? {
        levelToReturn
    }
}

private final class MutableVoiceSettings: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AppSettings

    init(_ settings: AppSettings) {
        self.settings = settings
    }

    var value: AppSettings {
        get {
            lock.lock()
            defer { lock.unlock() }
            return settings
        }
        set {
            lock.lock()
            settings = newValue
            lock.unlock()
        }
    }
}

private actor RecordingVoiceConversationOrchestrator:
    VoiceTaskConversationOrchestrating
{
    enum RecordedEvent: Equatable {
        case restore(sessionID: UUID)
        case begin(sessionID: UUID)
        case answer(sessionID: UUID, value: String)
        case cancel(sessionID: UUID)
    }

    private var outcomes: [VoiceTaskConversationOutcome]
    private(set) var recordedEvents: [RecordedEvent] = []

    init(outcomes: [VoiceTaskConversationOutcome]) {
        self.outcomes = outcomes
    }

    func handle(
        _ input: VoiceTaskConversationInput
    ) async -> VoiceTaskConversationOutcome {
        switch input.event {
        case .restore:
            recordedEvents.append(.restore(sessionID: input.sessionID))
        case .begin:
            recordedEvents.append(.begin(sessionID: input.sessionID))
        case .clarificationAnswer(let value, _):
            recordedEvents.append(
                .answer(sessionID: input.sessionID, value: value)
            )
        case .cancel:
            recordedEvents.append(.cancel(sessionID: input.sessionID))
        }
        guard !outcomes.isEmpty else {
            return .blocked(.missingClarificationState)
        }
        return outcomes.removeFirst()
    }
}

private actor RecordingReviewPersistingConversationOrchestrator:
    VoiceTaskConversationOrchestrating,
    VoiceTaskConversationReviewLinkPersisting
{
    struct PersistedReview: Equatable {
        let sessionID: UUID
        let fallbackSourceTurnID: UUID
        let confirmedText: String
        let plan: ActionPlan
        let queueItem: AssistantQueueItem
    }

    private var outcomes: [VoiceTaskConversationOutcome]
    private(set) var persistedReviews: [PersistedReview] = []

    init(outcomes: [VoiceTaskConversationOutcome]) {
        self.outcomes = outcomes
    }

    func handle(
        _ input: VoiceTaskConversationInput
    ) async -> VoiceTaskConversationOutcome {
        guard !outcomes.isEmpty else {
            return .blocked(.missingClarificationState)
        }
        return outcomes.removeFirst()
    }

    func persistReviewLink(
        sessionID: UUID,
        fallbackSourceTurnID: UUID,
        confirmedText: String,
        plan: ActionPlan,
        queueItem: AssistantQueueItem,
        at _: Date
    ) throws {
        persistedReviews.append(
            PersistedReview(
                sessionID: sessionID,
                fallbackSourceTurnID: fallbackSourceTurnID,
                confirmedText: confirmedText,
                plan: plan,
                queueItem: queueItem
            )
        )
    }
}
