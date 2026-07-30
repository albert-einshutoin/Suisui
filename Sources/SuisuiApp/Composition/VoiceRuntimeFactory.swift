import Foundation
import SuisuiCore

extension AppRuntimeFactory {
    @MainActor
    static func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel {
        let secretStore = makeSecretStore()
        let settingsResult = loadRuntimeSettings()
        let audioRecorder = AVFoundationAudioRecorder()
        let sttProvider = makeSpeechToTextProvider(settings: settingsResult.settings, secretStore: secretStore)
        let llmProvider = makeLLMProvider(settings: settingsResult.settings, secretStore: secretStore)
        let managedCostRateCardResolver = ManagedAICostRateCardResolver()
        var auditLogger: (any AuditLogger)?
        var assistantQueueStore: (any AssistantQueueStore)?
        var conversationOrchestrator: (any VoiceTaskConversationOrchestrating)?
        var conversationCommandPreparer:
            (any VoiceTaskConversationCommandPreparing)?
        var conversationStore: (any VoiceTaskConversationStore)?
        var conversationSessionID = voiceConversationSessionID()
        let scopeRequest = SuisuiVoiceConversationScopeBridge.consume()
        var inboxCaptureService: InboxVoiceCaptureService?
        var developmentProjectProvider: () -> ProjectRecord? = { nil }
        var workspaceContextRetriever: (@Sendable (String) throws -> [WorkspaceContextSnippet])?
        var taskDeleter: (@Sendable (Int64) throws -> Void)?
        var runtimeValidationMessage: String?
        var initialFailureMessage: String?
        do {
            auditLogger = try makeAuditLogger()
            let connection = try migratedConnection()
            assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
            let sqliteConversationStore = SQLiteVoiceTaskConversationStore(
                connection: connection
            )
            if try sqliteConversationStore.loadSession(
                id: conversationSessionID
            )?.state == .archived {
                conversationSessionID = resetVoiceConversationSessionID()
            }
            conversationStore = sqliteConversationStore
            let taskStore = SQLiteTaskStore(connection: connection)
            let projectStore = SQLiteProjectStore(connection: connection)
            conversationCommandPreparer =
                SQLiteVoiceTaskConversationCommandPreparer(
                    taskStore: taskStore,
                    projectStore: projectStore,
                    conversationStore: sqliteConversationStore
                )
            conversationOrchestrator = VoiceTaskConversationOrchestrator(
                stateStore: SQLiteVoiceTaskConversationOrchestrationStateStore(
                    connection: connection
                ),
                conversationStore: sqliteConversationStore,
                taskSnapshotFingerprintProvider: { taskID in
                    ConversationTaskSnapshotFingerprint.make(
                        try taskStore.get(id: taskID)
                    )
                },
                provider: llmProvider
            )
            let projectBoardStore = SQLiteProjectBoardStore(connection: connection)
            let inboxCaptureStore = SQLiteInboxCaptureStore(connection: connection)
            inboxCaptureService = InboxVoiceCaptureService(
                audioRecorder: audioRecorder,
                sttProvider: sttProvider,
                projectBoardStore: projectBoardStore,
                inboxCaptureStore: inboxCaptureStore
            )
            developmentProjectProvider = {
                approvedDevelopmentProject(from: projectStore)
            }
            let questionRetriever = WorkspaceQuestionRetriever(
                projectStore: projectStore,
                taskStore: taskStore,
                knowledgeFrameStore: SQLiteKnowledgeFrameStore(connection: connection),
                settings: settingsResult.settings
            )
            workspaceContextRetriever = { question in
                try questionRetriever.retrieve(question: question)
            }
            let undoTaskStore = SQLiteTaskStore(connection: connection)
            taskDeleter = { taskID in
                _ = try undoTaskStore.delete(id: taskID)
                NotificationCenter.default.post(name: .suisuiProjectBoardDidChange, object: nil)
            }
            runtimeValidationMessage = nil
            initialFailureMessage = settingsResult.errorMessage
        } catch {
            auditLogger = nil
            assistantQueueStore = nil
            runtimeValidationMessage = "Voice planning is unavailable because audit logging or local data stores could not be opened."
            initialFailureMessage = runtimeValidationMessage
        }
        let viewModel = VoiceCaptureViewModel(
            phase: initialFailureMessage.map(VoiceCapturePhase.failed) ?? .idle,
            audioRecorder: audioRecorder,
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            auditRecorder: auditLogger.map { PlanningAuditRecorder(logger: $0) },
            runtimeValidationMessage: runtimeValidationMessage,
            assistantQueueStore: assistantQueueStore,
            conversationOrchestrator: conversationOrchestrator,
            conversationCommandPreparer: conversationCommandPreparer,
            conversationSessionID: conversationSessionID,
            inboxCaptureSaver: inboxCaptureService,
            developmentProjectProvider: developmentProjectProvider,
            appSettingsProvider: { loadRuntimeSettings().settings },
            managedCostRateCardProvider: { managedCostRateCardResolver.rateCard(for: $0) },
            workspaceContextRetriever: workspaceContextRetriever,
            workspaceAnswerReadout: { answer in
                speakWorkspaceAnswer(answer)
            },
            taskAutomationSettingsProvider: { loadRuntimeSettings().settings.taskAutoExecution },
            lowRiskTaskAutoExecutor: { plan in
                try await executeLowRiskAutoCreation(plan: plan)
            },
            taskDeleter: taskDeleter
        )
        if let conversationStore {
            viewModel.configureConversationWorkspace(
                store: conversationStore,
                scope: scopeRequest?.presentationScope ?? .init(),
                activeProjectID: scopeRequest?.projectID,
                activeTaskID: scopeRequest?.taskID,
                entryPoint: scopeRequest?.taskID == nil
                    ? .voiceCommand
                    : .taskInspector
            )
        }
        return viewModel
    }

    private static func voiceConversationSessionID() -> UUID {
        let key = "suisui.voiceConversationSessionID"
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: key),
           let id = UUID(uuidString: value)
        {
            return id
        }
        // The stable ID lets the SQLite checkpoint reconnect the Voice window
        // to an unfinished clarification after an app relaunch.
        let id = UUID()
        defaults.set(id.uuidString, forKey: key)
        return id
    }

    private static func resetVoiceConversationSessionID() -> UUID {
        let id = UUID()
        UserDefaults.standard.set(
            id.uuidString,
            forKey: "suisui.voiceConversationSessionID"
        )
        return id
    }

    /// Runs an opt-in auto-create plan through the exact ReviewSession pipeline
    /// used by manual review (`makeReviewSessionViewModel`): the same
    /// ActionExecutor, tool registry, audit logging, and execution receipts.
    /// The only difference is that the approval token is granted
    /// programmatically because the low-risk auto-create policy already gated
    /// the plan to a single validated `task.create` action.
    @MainActor
    private static func executeLowRiskAutoCreation(plan: ActionPlan) throws -> LowRiskAutoCreationOutcome {
        let reviewViewModel = makeReviewSessionViewModel(plan: plan)
        if reviewViewModel.session.canApprove {
            try reviewViewModel.approve()
        }
        try reviewViewModel.execute()
        let session = reviewViewModel.session
        guard session.executionStatus == .completed else {
            throw LowRiskAutoCreationError.executionFailed(
                reviewViewModel.errorMessage ?? "Low-risk task auto-creation did not complete."
            )
        }

        let executedItem = session.enabledItems.first
        var taskID: Int64?
        if case .number(let value)? = executedItem?.result?.output["taskId"] {
            taskID = Int64(value)
        }
        let taskTitle: String
        if case .string(let title)? = executedItem?.editedAction.arguments["title"] {
            taskTitle = title
        } else {
            taskTitle = plan.summary
        }
        NotificationCenter.default.post(name: .suisuiProjectBoardDidChange, object: nil)
        return LowRiskAutoCreationOutcome(
            taskID: taskID,
            taskTitle: taskTitle,
            summaryMessage: executedItem?.result?.summary ?? "Task created"
        )
    }

    /// Speaks a workspace answer with the same local TTS preview machinery as
    /// the Settings "Test Play" button. Speech is best effort: a missing or
    /// misconfigured Kokoro runtime must never turn a successful written
    /// answer into an error.
    private static func speakWorkspaceAnswer(_ answer: String) {
        let settings = loadRuntimeSettings().settings
        let languageCode = AppSettings.normalizedTTSLanguageCode(settings.ttsLanguageCode)
        let request = TextToSpeechRequest(
            text: limitedWorkspaceAnswerReadoutText(answer),
            languageCode: languageCode,
            voiceID: AppSettings.normalizedTTSVoiceID(settings.ttsVoiceID, languageCode: languageCode)
        )
        let previewer = makeTextToSpeechPreviewer(settings: settings)
        Task {
            try? await previewer.playPreview(request)
        }
    }

    private static func limitedWorkspaceAnswerReadoutText(_ text: String) -> String {
        let maxPromptLength = 280
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > maxPromptLength else {
            return flattened
        }
        return "\(flattened.prefix(maxPromptLength - 3))..."
    }

    private static func approvedDevelopmentProject(from projectStore: SQLiteProjectStore) -> ProjectRecord? {
        guard let projects = try? projectStore.list() else {
            return nil
        }
        return VoiceDevelopmentProjectSelection.uniqueApprovedActiveProject(from: projects)
    }

    static func loadRuntimeSettings() -> RuntimeSettingsLoadResult {
        do {
            return RuntimeSettingsLoadResult(settings: try UserDefaultsAppSettingsStore().load().normalizedForRuntime)
        } catch {
            return RuntimeSettingsLoadResult(
                settings: .default,
                errorMessage: "Runtime app settings could not be loaded. Defaults are shown until settings are saved again."
            )
        }
    }

    private static func makeLLMProvider(settings: AppSettings, secretStore: any SecretStore) -> any LLMProvider {
        switch settings.normalizedForRuntime.aiProvider {
        case .codexLocal:
            return CodexAppServerRuntimeFactory.makeProvider(settings: settings)
        case .openaiResponses:
            let entry = LLMProviderCatalog.entry(for: .openaiResponses)
            let configuration = OpenAIResponsesConfiguration(model: entry.defaultModelID)
            return OpenAIResponsesProvider(secretStore: secretStore, configuration: configuration)
        case .geminiDirect:
            let entry = LLMProviderCatalog.entry(for: .geminiDirect)
            let configuration = GeminiDirectConfiguration(model: settings.normalizedForRuntime.geminiModelID ?? entry.defaultModelID)
            return GeminiDirectProvider(secretStore: secretStore, configuration: configuration)
        case .claudeMessages:
            let entry = LLMProviderCatalog.entry(for: .claudeMessages)
            let configuration = ClaudeMessagesConfiguration(model: entry.defaultModelID)
            return ClaudeMessagesProvider(secretStore: secretStore, configuration: configuration)
        case .openRouterCompatible:
            let entry = LLMProviderCatalog.entry(for: .openRouterCompatible)
            return ChatCompletionsCompatibleProvider(
                configuration: .openRouter(model: entry.defaultModelID),
                secretStore: secretStore
            )
        case .groqOpenAICompatible:
            let entry = LLMProviderCatalog.entry(for: .groqOpenAICompatible)
            let defaultBaseURL = entry.baseURL
                ?? ChatCompletionsCompatibleConfiguration.groq(model: entry.defaultModelID).baseURL
            return ChatCompletionsCompatibleProvider(
                configuration: .groq(
                    model: entry.defaultModelID,
                    baseURL: settings.normalizedForRuntime.resolvedGroqBaseURL(defaultBaseURL: defaultBaseURL)
                ),
                secretStore: secretStore
            )
        case .ollamaCompatible:
            let entry = LLMProviderCatalog.entry(for: .ollamaCompatible)
            return ChatCompletionsCompatibleProvider(
                configuration: .ollama(model: entry.defaultModelID),
                secretStore: secretStore
            )
        case .opencodeLocal:
            let entry = LLMProviderCatalog.entry(for: .opencodeLocal)
            let normalizedSettings = settings.normalizedForRuntime
            let configuration = OpenCodeLocalConfiguration(
                executablePath: normalizedSettings.openCodeExecutablePath,
                workspacePath: normalizedSettings.openCodeWorkspacePath,
                modelID: normalizedSettings.openCodeModelID ?? entry.defaultModelID,
                isExecutionApproved: normalizedSettings.isOpenCodeLocalExecutionApproved
            )
            return OpenCodeLocalProvider(configuration: configuration)
        case .geminiOpenAICompatible:
            let entry = LLMProviderCatalog.entry(for: .geminiOpenAICompatible)
            return UnavailableLLMProvider(
                providerID: .geminiOpenAICompatible,
                reason: entry.unavailableReason ?? LLMProviderCatalog.unavailableReason
            )
        }
    }

    private static func makeSpeechToTextProvider(
        settings: AppSettings,
        secretStore: any SecretStore
    ) -> any SpeechToTextProvider {
        let normalizedSettings = settings.normalizedForRuntime
        switch normalizedSettings.sttProvider {
        case .appleSpeechAnalyzer:
            return AppleSpeechRecognitionProvider()
        case .openAITranscribe, .localWhisperKit:
            return OpenAITranscribeProvider(secretStore: secretStore)
        case .localWhisperCpp:
            let configuration = WhisperCppLocalSTTConfiguration(
                executablePath: normalizedSettings.whisperCppExecutablePath ?? ""
            )
            return WhisperCppLocalSTTProvider(configuration: configuration)
        }
    }

    static func makeTextToSpeechPreviewer(settings: AppSettings) -> any TextToSpeechPreviewing {
        AppTextToSpeechRuntimeFactory.makePreviewer(settings: settings)
    }
}

enum AppTextToSpeechRuntimeFactory {
    static func makeProvider(settings: AppSettings, outputURL: URL? = nil) -> any TextToSpeechProvider {
        let normalizedSettings = settings.normalizedForRuntime
        switch normalizedSettings.ttsProvider {
        case .systemSpeech:
            return AppleSystemSpeechProvider(outputURL: outputURL)
        case .localKokoro:
            let configuration = KokoroLocalTTSConfiguration(
                executablePath: normalizedSettings.kokoroExecutablePath ?? "",
                languageCode: normalizedSettings.ttsLanguageCode,
                voiceID: normalizedSettings.ttsVoiceID,
                outputURL: outputURL
            )
            return KokoroLocalTTSProvider(configuration: configuration)
        }
    }

    static func makePreviewer(
        settings: AppSettings,
        temporaryDirectoryPrefix: String = "suisui-tts-preview",
        outputFilename: String? = nil
    ) -> any TextToSpeechPreviewing {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(temporaryDirectoryPrefix)-\(UUID().uuidString)", isDirectory: true)
        let resolvedOutputFilename = outputFilename
            ?? (settings.normalizedForRuntime.ttsProvider == .systemSpeech ? "preview.caf" : "preview.wav")
        let outputURL = temporaryDirectory.appendingPathComponent(resolvedOutputFilename, isDirectory: false)
        return TemporaryDirectoryTextToSpeechPreviewer(
            previewer: TextToSpeechPreviewService(
                provider: makeProvider(settings: settings, outputURL: outputURL),
                audioPlayer: AVFoundationSpeechAudioPlayer()
            ),
            temporaryDirectory: temporaryDirectory
        )
    }
}
