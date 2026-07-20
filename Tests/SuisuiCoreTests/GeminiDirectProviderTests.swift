import XCTest
@testable import SuisuiCore

final class GeminiDirectProviderTests: XCTestCase {
    @MainActor
    func testLiveGeminiVoiceOverTaskListRunsReadOnlyReviewExecutionWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SUISUI_LIVE_GEMINI_TASK_LIST_SMOKE"] == "1" else {
            throw XCTSkip("Set SUISUI_LIVE_GEMINI_TASK_LIST_SMOKE=1 to run the live Gemini VoiceOver task-list smoke.")
        }

        let title = "VoiceOver task list smoke \(UUID().uuidString.prefix(8))"
        let completedTitle = "Completed VoiceOver hidden smoke \(UUID().uuidString.prefix(8))"
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let knowledgeStore = SQLiteKnowledgeFrameStore(connection: connection)
        _ = try taskStore.create(title: title, priority: "high", detail: "Validate VoiceOver task listing through Gemini.")
        _ = try taskStore.create(title: completedTitle, status: "completed")
        let registry = try ToolRegistry.phase2Core(
            projectStore: projectStore,
            taskStore: taskStore,
            knowledgeStore: knowledgeStore
        )
        let voiceViewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "VoiceOverで未完了タスクを列挙して。新規作成、更新、完了はしないで。")),
            llmProvider: GeminiDirectProvider(
                secretStore: try Self.liveGeminiSecretStore(environment: environment),
                configuration: Self.liveGeminiConfiguration(environment: environment)
            )
        )

        voiceViewModel.updateDraftText("VoiceOverで未完了タスクを列挙して。新規作成、更新、完了はしないで。")
        await voiceViewModel.generatePlan(
            currentDate: Date(timeIntervalSince1970: 1_782_000_000),
            timeZoneIdentifier: "Asia/Tokyo",
            availableTools: [.taskList]
        )

        try Self.skipLiveGeminiTransientFailureIfNeeded(phase: voiceViewModel.phase, smokeName: "task-list")
        XCTAssertEqual(voiceViewModel.phase, .reviewReady)
        let plan = try XCTUnwrap(voiceViewModel.planningResponse?.actionPlan)
        XCTAssertFalse(plan.requiresApproval)
        XCTAssertEqual(plan.actions.map(\.tool), [.taskList])

        let reviewViewModel = ReviewSessionViewModel(
            plan: plan,
            executor: ActionExecutor(registry: registry)
        )
        XCTAssertTrue(reviewViewModel.executeOrReportError())

        let result = try XCTUnwrap(reviewViewModel.session.items.first?.result)
        XCTAssertEqual(reviewViewModel.session.executionStatus, .completed)
        XCTAssertEqual(result.output["count"], .number(1))
        XCTAssertTrue(String(describing: result.output["tasks"]).contains(title))
        XCTAssertFalse(String(describing: result.output["tasks"]).contains(completedTitle))
    }

    @MainActor
    func testLiveGeminiVoiceTextTaskCreationRunsThroughReviewIntoLocalTaskStoreWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        let shouldWriteRealDatabase = environment["SUISUI_LIVE_GEMINI_TASK_CREATE_REAL_DB"] == "1"
        guard environment["SUISUI_LIVE_GEMINI_TASK_CREATE_SMOKE"] == "1" || shouldWriteRealDatabase else {
            throw XCTSkip("Set SUISUI_LIVE_GEMINI_TASK_CREATE_SMOKE=1 to run the live Gemini task creation smoke.")
        }

        let title = shouldWriteRealDatabase
            ? "Gemini VoiceOver real DB smoke \(UUID().uuidString.prefix(8))"
            : "Gemini VoiceOver smoke \(UUID().uuidString.prefix(8))"
        let databasePath = try Self.databasePath(shouldWriteRealDatabase: shouldWriteRealDatabase)
        let connection = try SQLiteConnection(path: databasePath)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let taskStore = SQLiteTaskStore(connection: connection)
        let registry = try ToolRegistry.phase2Core(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: taskStore,
            knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection)
        )
        let voiceViewModel = VoiceCaptureViewModel(
            audioRecorder: FakeAudioRecorder(),
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "\(title)のタスクを作成したい")),
            llmProvider: GeminiDirectProvider(
                secretStore: try Self.liveGeminiSecretStore(environment: environment),
                configuration: Self.liveGeminiConfiguration(environment: environment)
            )
        )

        voiceViewModel.updateDraftText("\(title)のタスクを作成したい")
        await voiceViewModel.generatePlan(
            currentDate: Date(timeIntervalSince1970: 1_782_000_000),
            timeZoneIdentifier: "Asia/Tokyo",
            availableTools: [.taskCreate]
        )

        try Self.skipLiveGeminiTransientFailureIfNeeded(phase: voiceViewModel.phase, smokeName: "task-create")
        XCTAssertEqual(voiceViewModel.phase, .reviewReady)
        let plan = try XCTUnwrap(voiceViewModel.planningResponse?.actionPlan)
        XCTAssertEqual(plan.actions.first?.tool, .taskCreate)
        XCTAssertEqual(plan.requiresApproval, true)

        let reviewViewModel = ReviewSessionViewModel(
            plan: plan,
            executor: ActionExecutor(registry: registry)
        )
        XCTAssertTrue(reviewViewModel.approveOrReportError())
        XCTAssertTrue(reviewViewModel.executeOrReportError())

        let tasks = try taskStore.listAll()
        let matchingTasks = tasks.filter { $0.title == title }
        XCTAssertEqual(matchingTasks.count, 1)
        XCTAssertEqual(reviewViewModel.session.executionStatus, .completed)
    }

    private static func databasePath(shouldWriteRealDatabase: Bool) throws -> String {
        guard shouldWriteRealDatabase else {
            return ":memory:"
        }
        return try SuisuiAppDatabaseLocation.defaultDatabaseURL(createDirectory: true).path
    }

    private static func liveGeminiSecretStore(environment: [String: String]) throws -> any SecretStore {
        let apiKey = try liveGeminiAPIKey(environment: environment)
        return InMemorySecretStore(values: [.geminiAPIKey: apiKey])
    }

    private static func liveGeminiAPIKey(environment: [String: String]) throws -> String {
        for name in ["SUISUI_GEMINI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY"] {
            if let apiKey = try? APIKeyValidator.normalize(environment[name]) {
                return apiKey
            }
        }

        #if canImport(Security)
        do {
            if let apiKey = try KeychainSecretStore().read(.geminiAPIKey) {
                return try APIKeyValidator.normalize(apiKey)
            }
        } catch APIKeyValidationError.empty, APIKeyValidationError.containsWhitespace {
            throw XCTSkip("Gemini API key is present but invalid; re-enter it in Settings or set SUISUI_GEMINI_API_KEY.")
        } catch {
            throw XCTSkip("Gemini API key is unavailable from env or Keychain; live Gemini smoke skipped.")
        }
        #endif

        throw XCTSkip("Set SUISUI_GEMINI_API_KEY, GEMINI_API_KEY, GOOGLE_API_KEY, or save Gemini API key in Keychain to run live Gemini smoke.")
    }

    private static func liveGeminiConfiguration(environment: [String: String]) -> GeminiDirectConfiguration {
        let modelOverride = environment["SUISUI_LIVE_GEMINI_MODEL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let model: String
        if let modelOverride, !modelOverride.isEmpty {
            model = modelOverride
        } else {
            model = GeminiDirectConfiguration().model
        }
        return GeminiDirectConfiguration(
            model: model,
            maxOutputTokens: 2_048,
            timeoutInterval: 60
        )
    }

    private static func skipLiveGeminiTransientFailureIfNeeded(
        phase: VoiceCapturePhase,
        smokeName: String
    ) throws {
        guard case .failed(let message) = phase else {
            return
        }

        let lowercasedMessage = message.lowercased()
        if lowercasedMessage.contains("rate limit")
            || lowercasedMessage.contains("quota")
            || lowercasedMessage.contains("503")
            || lowercasedMessage.contains("high demand")
            || lowercasedMessage.contains("try again later") {
            throw XCTSkip("Gemini free-tier or transient capacity limit reached; live \(smokeName) smoke skipped.")
        }
    }

    func testConfigurationUsesGeminiDefaults() {
        let configuration = GeminiDirectConfiguration()

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertEqual(configuration.model, "gemini-3.5-flash")
        XCTAssertEqual(configuration.maxOutputTokens, 16_000)
    }

    func testRequestBuilderUsesGenerateContentEndpointAndGoogleAPIKeyHeader() throws {
        let request = try GeminiDirectRequestBuilder(
            configuration: GeminiDirectConfiguration(
                baseURL: URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
                model: "gemini-test",
                maxOutputTokens: 4_096,
                timeoutInterval: 12
            )
        ).makeRequest(
            apiKey: "gemini-test-key",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "gemini-test-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testRequestBodyContainsSystemInstructionUserContentJSONResponseFormatAndNoOpenAIFields() throws {
        let request = try GeminiDirectRequestBuilder(
            configuration: GeminiDirectConfiguration(model: "gemini-test", maxOutputTokens: 4_096)
        ).makeRequest(
            apiKey: "gemini-test-key",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let systemInstruction = try XCTUnwrap(object["system_instruction"] as? [String: Any])
        let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
        let contents = try XCTUnwrap(object["contents"] as? [[String: Any]])
        let firstContent = try XCTUnwrap(contents.first)
        let userParts = try XCTUnwrap(firstContent["parts"] as? [[String: Any]])
        let generationConfig = try XCTUnwrap(object["generationConfig"] as? [String: Any])

        XCTAssertEqual(systemParts.first?["text"] as? String, "system prompt")
        XCTAssertEqual(firstContent["role"] as? String, "user")
        XCTAssertEqual(userParts.first?["text"] as? String, "user prompt")
        XCTAssertEqual(generationConfig["maxOutputTokens"] as? Int, 4_096)
        XCTAssertEqual(generationConfig["responseMimeType"] as? String, "application/json")
        XCTAssertNil(object["messages"])
        XCTAssertNil(object["tools"])
        XCTAssertNil(object["tool_choice"])
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains("gemini-test-key") ?? true)
    }

    func testRequestBodyExposesTaskMutationAsGeminiFunctionDeclarations() throws {
        let request = try GeminiDirectRequestBuilder(
            configuration: GeminiDirectConfiguration(model: "gemini-test", maxOutputTokens: 4_096)
        ).makeRequest(
            apiKey: "gemini-test-key",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt"),
            availableTools: [.taskList, .taskCreate, .taskBulkCreate, .taskUpdate, .taskComplete, .gitStatus]
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try XCTUnwrap(object["generationConfig"] as? [String: Any])
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        let toolConfig = try XCTUnwrap(object["toolConfig"] as? [String: Any])
        let functionCallingConfig = try XCTUnwrap(toolConfig["functionCallingConfig"] as? [String: Any])
        let firstTool = try XCTUnwrap(tools.first)
        let declarations = try XCTUnwrap(firstTool["functionDeclarations"] as? [[String: Any]])
        let names = declarations.compactMap { $0["name"] as? String }

        XCTAssertNil(generationConfig["responseMimeType"])
        XCTAssertEqual(names, ["task_list", "task_create", "task_bulk_create", "task_update", "task_complete"])
        XCTAssertEqual(functionCallingConfig["mode"] as? String, "ANY")
        XCTAssertEqual(functionCallingConfig["allowedFunctionNames"] as? [String], ["task_list", "task_create", "task_bulk_create", "task_update", "task_complete"])
        XCTAssertFalse(names.contains("git_status"))

        let taskCreate = try XCTUnwrap(declarations.first { $0["name"] as? String == "task_create" })
        let parameters = try XCTUnwrap(taskCreate["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["title"])
        XCTAssertNotNil(properties["title"])
        XCTAssertNotNil(properties["projectId"])

        let taskUpdate = try XCTUnwrap(declarations.first { $0["name"] as? String == "task_update" })
        let updateParameters = try XCTUnwrap(taskUpdate["parameters"] as? [String: Any])
        let updateProperties = try XCTUnwrap(updateParameters["properties"] as? [String: Any])
        XCTAssertEqual(updateParameters["required"] as? [String], ["id"])
        XCTAssertNotNil(updateProperties["id"])
        XCTAssertNotNil(updateProperties["status"])
        XCTAssertNotNil(updateProperties["projectId"])
        XCTAssertNotNil(updateProperties["dueAt"])

        let taskList = try XCTUnwrap(declarations.first { $0["name"] as? String == "task_list" })
        let listParameters = try XCTUnwrap(taskList["parameters"] as? [String: Any])
        XCTAssertEqual(listParameters["required"] as? [String], [])

        let taskComplete = try XCTUnwrap(declarations.first { $0["name"] as? String == "task_complete" })
        let completeParameters = try XCTUnwrap(taskComplete["parameters"] as? [String: Any])
        let completeProperties = try XCTUnwrap(completeParameters["properties"] as? [String: Any])
        XCTAssertEqual(completeParameters["required"] as? [String], ["id"])
        XCTAssertNotNil(completeProperties["id"])
    }

    func testOutputTextExtractorReadsCandidateTextParts() throws {
        let data = Data(
            """
            {
              "candidates": [
                {
                  "content": {
                    "parts": [
                      { "text": "{\\"id\\":\\"plan-1\\"}" }
                    ]
                  },
                  "finishReason": "STOP"
                }
              ]
            }
            """.utf8
        )

        let text = try GeminiDirectOutputTextExtractor().extractText(from: data)

        XCTAssertEqual(text, #"{"id":"plan-1"}"#)
    }

    func testOutputTextExtractorRejectsPromptSafetyBlock() throws {
        let data = Data(
            """
            {
              "promptFeedback": {
                "blockReason": "SAFETY"
              },
              "candidates": []
            }
            """.utf8
        )

        XCTAssertThrowsError(try GeminiDirectOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Gemini Direct blocked the prompt: SAFETY.")
            )
        }
    }

    func testOutputTextExtractorRejectsSafetyFinishReasonWithoutDroppingIt() throws {
        let data = Data(
            """
            {
              "candidates": [
                {
                  "content": {
                    "parts": []
                  },
                  "finishReason": "SAFETY"
                }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try GeminiDirectOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Gemini Direct blocked the response for safety.")
            )
        }
    }

    func testOutputTextExtractorMapsDecodeFailureToInvalidResponse() throws {
        let data = Data(
            """
            {
              "candidates": "not-an-array"
            }
            """.utf8
        )

        XCTAssertThrowsError(try GeminiDirectOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Gemini Direct payload could not be decoded.")
            )
        }
    }

    func testProviderRejectsMissingAPIKeyBeforeHTTP() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(),
            httpClient: GeminiStubHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected missing API key to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    func testProviderMapsInvalidAPIKeyHTTPBodyToAuthenticationFailure() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(#"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#.utf8),
                statusCode: 400
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected invalid key to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    func testProviderMapsQuotaHTTPStatusToRateLimited() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(#"{"error":{"message":"Quota exceeded."}}"#.utf8),
                statusCode: 429
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected quota to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .rateLimited)
        }
    }

    func testProviderParsesSuccessfulResponse() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              { "text": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}" }
                            ]
                          },
                          "finishReason": "STOP"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "gemini.direct")
        XCTAssertEqual(response.actionPlan?.id, "plan-1")
        XCTAssertTrue(response.validationResult.isValid)
    }

    func testProviderMapsGeminiFunctionCallToApprovalBackedActionPlanWithoutExecuting() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              {
                                "functionCall": {
                                  "id": "call-1",
                                  "name": "task_create",
                                  "args": {
                                    "title": "Review MCP bridge",
                                    "priority": "high"
                                  }
                                }
                              }
                            ]
                          },
                          "finishReason": "STOP"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(
            for: PlanningRequest(
                userInput: "MCP bridge review taskを作って",
                availableTools: [.taskCreate]
            )
        )

        XCTAssertEqual(response.providerID, "gemini.direct")
        XCTAssertTrue(response.validationResult.isValid)
        XCTAssertEqual(response.actionPlan?.id, "gemini-function-plan")
        XCTAssertEqual(response.actionPlan?.requiresApproval, true)
        XCTAssertEqual(response.actionPlan?.riskLevel, .write)
        XCTAssertEqual(response.actionPlan?.summary, "Create task: Review MCP bridge")
        XCTAssertEqual(response.actionPlan?.actions, [
            PlanAction(
                id: "call-1",
                tool: .taskCreate,
                arguments: [
                    "title": .string("Review MCP bridge"),
                    "priority": .string("high")
                ],
                riskLevel: .write,
                requiresUserConfirmation: false
            )
        ])
    }

    func testProviderMapsGeminiTaskMutationFunctionCallsToApprovalBackedActionPlan() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              {
                                "functionCall": {
                                  "id": "call-update",
                                  "name": "task_update",
                                  "args": {
                                    "id": 42,
                                    "status": "in_progress",
                                    "projectId": 7,
                                    "dueAt": "2026-06-22T09:00:00Z"
                                  }
                                }
                              },
                              {
                                "functionCall": {
                                  "id": "call-complete",
                                  "name": "task_complete",
                                  "args": {
                                    "id": 43
                                  }
                                }
                              }
                            ]
                          },
                          "finishReason": "STOP"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(
            for: PlanningRequest(
                userInput: "42を進行中にして、43は完了にして",
                availableTools: [.taskUpdate, .taskComplete]
            )
        )

        XCTAssertEqual(response.providerID, "gemini.direct")
        XCTAssertTrue(response.validationResult.isValid)
        XCTAssertEqual(response.actionPlan?.id, "gemini-function-plan")
        XCTAssertEqual(response.actionPlan?.requiresApproval, true)
        XCTAssertEqual(response.actionPlan?.riskLevel, .write)
        XCTAssertEqual(response.actionPlan?.actions, [
            PlanAction(
                id: "call-update",
                tool: .taskUpdate,
                arguments: [
                    "id": .number(42),
                    "status": .string("in_progress"),
                    "projectId": .number(7),
                    "dueAt": .string("2026-06-22T09:00:00Z")
                ],
                riskLevel: .write,
                requiresUserConfirmation: false
            ),
            PlanAction(
                id: "call-complete",
                tool: .taskComplete,
                arguments: [
                    "id": .number(43)
                ],
                riskLevel: .write,
                requiresUserConfirmation: false
            )
        ])
    }

    func testProviderMapsGeminiTaskListFunctionCallToReadOnlyActionPlan() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              {
                                "functionCall": {
                                  "id": "call-list",
                                  "name": "task_list",
                                  "args": {}
                                }
                              }
                            ]
                          },
                          "finishReason": "STOP"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(
            for: PlanningRequest(
                userInput: "タスクを列挙して",
                availableTools: [.taskList]
            )
        )

        let plan = try XCTUnwrap(response.actionPlan)
        XCTAssertTrue(response.validationResult.isValid)
        XCTAssertFalse(plan.requiresApproval)
        XCTAssertEqual(plan.approvalRequirement, .none)
        XCTAssertEqual(plan.summary, "List current Suisui tasks.")
        XCTAssertEqual(plan.actions.first?.tool, .taskList)
    }

    func testProviderRejectsUnavailableGeminiFunctionCallBeforeLocalExecution() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              {
                                "functionCall": {
                                  "name": "git_status",
                                  "args": {}
                                }
                              }
                            ]
                          },
                          "finishReason": "STOP"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        do {
            _ = try await provider.generatePlan(
                for: PlanningRequest(
                    userInput: "git statusを見て",
                    availableTools: [.taskCreate]
                )
            )
            XCTFail("Expected unsupported function call to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Gemini Direct requested unsupported function 'git_status'.")
            )
        }
    }

    func testProviderReturnsBlockingValidationForActionPlanSchemaMismatch() async throws {
        let provider = GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            httpClient: GeminiStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "candidates": [
                        {
                          "content": {
                            "parts": [
                              { "text": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"unexpected\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}" }
                            ]
                          },
                          "finishReason": "STOP"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "gemini.direct")
        XCTAssertNil(response.actionPlan)
        XCTAssertFalse(response.validationResult.isValid)
        XCTAssertEqual(response.validationResult.issues.first?.path, "unexpected")
    }
}

private struct GeminiStubHTTPDataClient: HTTPDataClient {
    var data: Data
    var statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-test:generateContent")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
