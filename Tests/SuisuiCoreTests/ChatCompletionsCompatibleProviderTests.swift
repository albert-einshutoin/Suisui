import XCTest
@testable import SuisuiCore

final class ChatCompletionsCompatibleProviderTests: XCTestCase {
    func testOpenRouterConfigurationRequiresAPIKey() {
        let configuration = ChatCompletionsCompatibleConfiguration.openRouter(model: "openai/gpt-latest")

        XCTAssertEqual(configuration.providerID, "openrouter.chat")
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://openrouter.ai/api/v1")
        XCTAssertEqual(configuration.apiKeySecretKey, .openRouterAPIKey)
        XCTAssertTrue(configuration.requiresAPIKey)
    }

    func testOpenAICompatibleConfigurationUsesOpenAIKey() {
        let configuration = ChatCompletionsCompatibleConfiguration.openAICompatible(model: "gpt-5.5")

        XCTAssertEqual(configuration.providerID, "openai.chat_completions")
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(configuration.apiKeySecretKey, .openAIAPIKey)
        XCTAssertTrue(configuration.requiresAPIKey)
    }

    func testGroqConfigurationUsesGroqDefaultsWithoutMixingOpenAISecrets() {
        let configuration = ChatCompletionsCompatibleConfiguration.groq(model: "llama-3.3-70b-versatile")

        XCTAssertEqual(configuration.providerID, "groq.chat")
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.groq.com/openai/v1")
        XCTAssertEqual(configuration.model, "llama-3.3-70b-versatile")
        XCTAssertEqual(configuration.apiKeySecretKey, .groqAPIKey)
        XCTAssertTrue(configuration.requiresAPIKey)
        XCTAssertNotEqual(configuration.apiKeySecretKey, .openAIAPIKey)
        XCTAssertNotEqual(configuration.apiKeySecretKey, .openRouterAPIKey)
    }

    func testOllamaConfigurationDoesNotRequireAPIKey() {
        let configuration = ChatCompletionsCompatibleConfiguration.ollama(model: "llama3.2")

        XCTAssertEqual(configuration.providerID, "ollama.chat")
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://localhost:11434/v1")
        XCTAssertNil(configuration.apiKeySecretKey)
        XCTAssertFalse(configuration.requiresAPIKey)
    }

    func testRequestBuilderUsesChatCompletionsEndpointAndAuthorizationWhenPresent() throws {
        let request = try ChatCompletionsCompatibleRequestBuilder(
            configuration: .openRouter(model: "openai/gpt-latest", timeoutInterval: 15)
        ).makeRequest(
            apiKey: "sk-router",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-router")
    }

    func testGroqRequestBuilderUsesExplicitOpenAICompatibleChatCompletionsPath() throws {
        let request = try ChatCompletionsCompatibleRequestBuilder(
            configuration: .groq(model: "llama-3.3-70b-versatile")
        ).makeRequest(
            apiKey: "gsk-test",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk-test")
    }

    func testRequestBuilderOmitsAuthorizationForLocalProvider() throws {
        let request = try ChatCompletionsCompatibleRequestBuilder(
            configuration: .ollama(model: "llama3.2")
        ).makeRequest(
            apiKey: nil,
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testRequestBodyContainsModelMessagesAndNoSecret() throws {
        let request = try ChatCompletionsCompatibleRequestBuilder(
            configuration: .openRouter(model: "openai/gpt-latest")
        ).makeRequest(
            apiKey: "sk-router",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])

        XCTAssertEqual(object["model"] as? String, "openai/gpt-latest")
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "system prompt")
        XCTAssertEqual(messages.last?["role"] as? String, "user")
        XCTAssertEqual(messages.last?["content"] as? String, "user prompt")
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains("sk-router") ?? true)
    }

    func testOutputTextExtractorReadsFirstMessageContent() throws {
        let data = Data(
            """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "{\\"id\\":\\"plan-1\\"}"
                  }
                }
              ]
            }
            """.utf8
        )

        let text = try ChatCompletionsOutputTextExtractor().extractText(from: data)

        XCTAssertEqual(text, #"{"id":"plan-1"}"#)
    }

    func testOutputTextExtractorRejectsBlankChoiceContentInsteadOfDroppingIt() throws {
        let data = Data(
            """
            {
              "choices": [
                {
                  "message": {
                    "role": "assistant",
                    "content": "   "
                  }
                },
                {
                  "message": {
                    "role": "assistant",
                    "content": "{\\"id\\":\\"plan-1\\"}"
                  }
                }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try ChatCompletionsOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Chat completion choice did not contain message content.")
            )
        }
    }

    func testOutputTextExtractorMapsDecodeFailureToInvalidResponse() throws {
        let data = Data(
            """
            {
              "choices": "not-an-array"
            }
            """.utf8
        )

        XCTAssertThrowsError(try ChatCompletionsOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Chat completion response could not be decoded.")
            )
        }
    }

    func testOpenRouterProviderRejectsMissingAPIKeyBeforeHTTP() async throws {
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .openRouter(model: "openai/gpt-latest"),
            secretStore: InMemorySecretStore(),
            httpClient: StubHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected missing API key to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    func testOpenRouterProviderRejectsAPIKeyWithInternalWhitespaceBeforeHTTP() async throws {
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .openRouter(model: "openai/gpt-latest"),
            secretStore: InMemorySecretStore(values: [.openRouterAPIKey: "sk-router\ninvalid"]),
            httpClient: StubHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected malformed API key to fail before HTTP.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    func testOllamaProviderParsesSuccessfulResponseWithoutAPIKey() async throws {
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .ollama(model: "llama3.2"),
            secretStore: InMemorySecretStore(),
            httpClient: StubHTTPDataClient(
                data: Data(
                    """
                    {
                      "choices": [
                        {
                          "message": {
                            "role": "assistant",
                            "content": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                          }
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "ollama.chat")
        XCTAssertEqual(response.actionPlan?.id, "plan-1")
        XCTAssertTrue(response.validationResult.isValid)
    }

    func testProviderCarriesMeasuredUsageAndResponseModelIntoPlanningResponse() async throws {
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .groq(model: "llama-3.3-70b-versatile"),
            secretStore: InMemorySecretStore(values: [.groqAPIKey: "gsk-test"]),
            httpClient: StubHTTPDataClient(
                data: Data(
                    """
                    {
                      "id": "chatcmpl-usage",
                      "object": "chat.completion",
                      "created": 0,
                      "model": "llama-3.3-70b-versatile",
                      "choices": [
                        {
                          "index": 0,
                          "message": {
                            "role": "assistant",
                            "content": "{\\"id\\":\\"plan-usage\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                          },
                          "finish_reason": "stop"
                        }
                      ],
                      "usage": {
                        "prompt_tokens": 321,
                        "completion_tokens": 123,
                        "total_tokens": 444
                      }
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.model, ExecutionReceiptModel(provider: "groq.chat", name: "llama-3.3-70b-versatile"))
        XCTAssertEqual(response.usage.state, .measured)
        XCTAssertEqual(response.usage.inputTokens, 321)
        XCTAssertEqual(response.usage.outputTokens, 123)
        XCTAssertNil(response.usage.estimatedCostCents)
    }

    func testProviderRedactsSecretsAndLocalPathsFromResponseModelMetadata() async throws {
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .ollama(model: "/Users/alice/private/fallback.gguf"),
            secretStore: InMemorySecretStore(),
            httpClient: StubHTTPDataClient(
                data: Data(
                    """
                    {
                      "model": "/Users/alice/private/sk-modelSecret1234567890/model.gguf",
                      "choices": [
                        {
                          "message": {
                            "role": "assistant",
                            "content": "{\\"id\\":\\"plan-redacted\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                          }
                        }
                      ],
                      "usage": {
                        "prompt_tokens": 5,
                        "completion_tokens": 7
                      }
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        let modelName = try XCTUnwrap(response.model?.name)
        XCTAssertFalse(modelName.contains("/Users/alice"))
        XCTAssertFalse(modelName.contains("modelSecret"))
        XCTAssertTrue(modelName.contains("[REDACTED"))
    }

    func testProviderMapsRateLimitStatus() async throws {
        let store = InMemorySecretStore(values: [.openRouterAPIKey: "sk-router"])
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .openRouter(model: "openai/gpt-latest"),
            secretStore: store,
            httpClient: StubHTTPDataClient(data: Data(#"{"error":{"message":"Slow down"}}"#.utf8), statusCode: 429)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected rate limit to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .rateLimited)
        }
    }

    func testGroqProviderMapsRateLimitStatusWithGroqKey() async throws {
        let store = InMemorySecretStore(values: [.groqAPIKey: "gsk-test"])
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .groq(model: "llama-3.3-70b-versatile"),
            secretStore: store,
            httpClient: StubHTTPDataClient(data: Data(#"{"error":{"message":"Rate limit reached"}}"#.utf8), statusCode: 429)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected Groq rate limit to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .rateLimited)
        }
    }

    func testGroqProviderRejectsSchemaMismatchAsInvalidResponse() async throws {
        let store = InMemorySecretStore(values: [.groqAPIKey: "gsk-test"])
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .groq(model: "llama-3.3-70b-versatile"),
            secretStore: store,
            httpClient: StubHTTPDataClient(
                data: Data(#"{"id":"chatcmpl-1","choices":{"message":{"content":"{}"}}}"#.utf8),
                statusCode: 200
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected Groq schema mismatch to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Chat completion response could not be decoded.")
            )
        }
    }

    func testProviderIncludesRedactedMalformedHTTPErrorBodyPreview() async throws {
        let store = InMemorySecretStore(values: [.openRouterAPIKey: "sk-router"])
        let secret = "sk-" + "routerSecret123"
        let provider = ChatCompletionsCompatibleProvider(
            configuration: .openRouter(model: "openai/gpt-latest"),
            secretStore: store,
            httpClient: StubHTTPDataClient(
                data: Data("provider exploded token=\(secret) request-id=chat-500".utf8),
                statusCode: 500
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected malformed HTTP error body to fail.")
        } catch {
            guard case .network(let message) = error as? LLMProviderError else {
                return XCTFail("Expected network error, got \(error)")
            }
            XCTAssertTrue(message.contains("HTTP 500"))
            XCTAssertTrue(message.contains("Unexpected error body"))
            XCTAssertTrue(message.contains("request-id=chat-500"))
            XCTAssertFalse(message.contains("No error message"))
            XCTAssertFalse(message.contains(secret))
            XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        }
    }
}

private struct StubHTTPDataClient: HTTPDataClient {
    var data: Data
    var statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "http://localhost:11434/v1/chat/completions")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
