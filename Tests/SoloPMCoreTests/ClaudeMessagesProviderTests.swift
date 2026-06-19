import XCTest
@testable import SoloPMCore

final class ClaudeMessagesProviderTests: XCTestCase {
    func testConfigurationUsesAnthropicDefaults() {
        let configuration = ClaudeMessagesConfiguration()

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.anthropic.com/v1")
        XCTAssertEqual(configuration.model, "claude-fable-5")
        XCTAssertEqual(configuration.maxTokens, 16_000)
        XCTAssertEqual(configuration.anthropicVersion, "2023-06-01")
    }

    func testRequestBuilderUsesMessagesEndpointAndAnthropicHeaders() throws {
        let request = try ClaudeMessagesRequestBuilder(
            configuration: ClaudeMessagesConfiguration(
                baseURL: URL(string: "https://api.anthropic.com/v1")!,
                model: "claude-test",
                maxTokens: 4_096,
                timeoutInterval: 12,
                anthropicVersion: "2023-06-01"
            )
        ).makeRequest(
            apiKey: "sk-ant-test",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testRequestBodyContainsSystemUserMaxTokensModelAndNoTools() throws {
        let request = try ClaudeMessagesRequestBuilder(
            configuration: ClaudeMessagesConfiguration(model: "claude-test", maxTokens: 4_096)
        ).makeRequest(
            apiKey: "sk-ant-test",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])

        XCTAssertEqual(object["model"] as? String, "claude-test")
        XCTAssertEqual(object["max_tokens"] as? Int, 4_096)
        XCTAssertEqual(object["system"] as? String, "system prompt")
        XCTAssertEqual(object["stream"] as? Bool, false)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"] as? String, "user")
        XCTAssertEqual(messages.first?["content"] as? String, "user prompt")
        XCTAssertNil(object["tools"])
        XCTAssertNil(object["tool_choice"])
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains("sk-ant-test") ?? true)
    }

    func testOutputTextExtractorReadsTextContentBlocks() throws {
        let data = Data(
            """
            {
              "id": "msg_1",
              "content": [
                {
                  "type": "text",
                  "text": "{\\"id\\":\\"plan-1\\"}"
                }
              ]
            }
            """.utf8
        )

        let text = try ClaudeMessagesOutputTextExtractor().extractText(from: data)

        XCTAssertEqual(text, #"{"id":"plan-1"}"#)
    }

    func testOutputTextExtractorRejectsBlankTextContentInsteadOfDroppingIt() throws {
        let data = Data(
            """
            {
              "id": "msg_1",
              "content": [
                {
                  "type": "text",
                  "text": "   "
                },
                {
                  "type": "text",
                  "text": "{\\"id\\":\\"plan-1\\"}"
                }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try ClaudeMessagesOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Claude Messages text content block was empty.")
            )
        }
    }

    func testOutputTextExtractorRejectsToolUseOnlyContent() throws {
        let data = Data(
            """
            {
              "id": "msg_1",
              "content": [
                {
                  "type": "tool_use",
                  "id": "toolu_1",
                  "name": "create_task",
                  "input": {"title": "Create task"}
                }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try ClaudeMessagesOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Claude Messages response did not contain text content.")
            )
        }
    }

    func testOutputTextExtractorMapsDecodeFailureToInvalidResponse() throws {
        let data = Data(
            """
            {
              "content": "not-an-array"
            }
            """.utf8
        )

        XCTAssertThrowsError(try ClaudeMessagesOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Claude Messages payload could not be decoded.")
            )
        }
    }

    func testProviderRejectsMissingAPIKeyBeforeHTTP() async throws {
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(),
            httpClient: ClaudeStubHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected missing API key to fail.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    func testProviderMapsHTTPErrorWithProviderNameAndRedaction() async throws {
        let secret = "sk-ant-serverSecret123"
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(values: [.anthropicAPIKey: "sk-ant-test"]),
            httpClient: ClaudeStubHTTPDataClient(
                data: Data(
                    """
                    {"error":{"message":"Claude failed api_key=\(secret) request-id=claude-500"}}
                    """.utf8
                ),
                statusCode: 500
            )
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected HTTP error to fail.")
        } catch {
            guard case .network(let message) = error as? LLMProviderError else {
                return XCTFail("Expected network error, got \(error)")
            }
            XCTAssertTrue(message.contains("Claude Messages HTTP 500"))
            XCTAssertTrue(message.contains("request-id=claude-500"))
            XCTAssertFalse(message.contains(secret))
            XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        }
    }

    func testProviderParsesSuccessfulResponse() async throws {
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(values: [.anthropicAPIKey: "sk-ant-test"]),
            httpClient: ClaudeStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "content": [
                        {
                          "type": "text",
                          "text": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "claude.messages")
        XCTAssertEqual(response.actionPlan?.id, "plan-1")
        XCTAssertTrue(response.validationResult.isValid)
    }

    func testProviderReturnsBlockingValidationForActionPlanSchemaMismatch() async throws {
        let provider = ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(values: [.anthropicAPIKey: "sk-ant-test"]),
            httpClient: ClaudeStubHTTPDataClient(
                data: Data(
                    """
                    {
                      "content": [
                        {
                          "type": "text",
                          "text": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"unexpected\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "claude.messages")
        XCTAssertNil(response.actionPlan)
        XCTAssertFalse(response.validationResult.isValid)
        XCTAssertEqual(response.validationResult.issues.first?.path, "unexpected")
    }
}

private struct ClaudeStubHTTPDataClient: HTTPDataClient {
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
