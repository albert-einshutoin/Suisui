import XCTest
@testable import SoloPMCore

final class ChatCompletionsCompatibleProviderTests: XCTestCase {
    func testOpenRouterConfigurationRequiresAPIKey() {
        let configuration = ChatCompletionsCompatibleConfiguration.openRouter(model: "openai/gpt-latest")

        XCTAssertEqual(configuration.providerID, "openrouter.chat")
        XCTAssertEqual(configuration.baseURL.absoluteString, "https://openrouter.ai/api/v1")
        XCTAssertEqual(configuration.apiKeySecretKey, .openRouterAPIKey)
        XCTAssertTrue(configuration.requiresAPIKey)
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
