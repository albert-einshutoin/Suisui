import XCTest
@testable import SuisuiCore

final class OpenAIResponsesProviderTests: XCTestCase {
    func testConfigurationUsesOpenAIDefaults() {
        let configuration = OpenAIResponsesConfiguration()

        XCTAssertEqual(configuration.baseURL.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(configuration.model, "gpt-5.5")
        XCTAssertEqual(configuration.timeoutInterval, 60)
    }

    func testRequestBuilderUsesResponsesEndpointAndAuthorizationHeader() throws {
        let request = try OpenAIResponsesRequestBuilder(
            configuration: OpenAIResponsesConfiguration(
                baseURL: URL(string: "https://api.openai.com/v1")!,
                model: "gpt-test",
                timeoutInterval: 12
            )
        ).makeRequest(
            apiKey: "sk-test",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
    }

    func testRequestBuilderBodyContainsModelInputMessagesAndNoToolChoice() throws {
        let request = try OpenAIResponsesRequestBuilder(
            configuration: OpenAIResponsesConfiguration(model: "gpt-test")
        ).makeRequest(
            apiKey: "sk-test",
            prompt: PlanningPrompt(system: "system prompt", user: "user prompt")
        )

        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let input = try XCTUnwrap(object["input"] as? [[String: Any]])

        XCTAssertEqual(object["model"] as? String, "gpt-test")
        XCTAssertEqual(object["tool_choice"] as? String, "none")
        XCTAssertEqual(input.first?["role"] as? String, "system")
        XCTAssertEqual(input.last?["role"] as? String, "user")
        XCTAssertFalse(String(data: body, encoding: .utf8)?.contains("sk-test") ?? true)
    }

    func testOutputTextExtractorReadsOutputTextShortcut() throws {
        let data = Data(
            """
            {
              "id": "resp_1",
              "output_text": "{\\"id\\":\\"plan-1\\"}"
            }
            """.utf8
        )

        let text = try OpenAIResponsesOutputTextExtractor().extractText(from: data)

        XCTAssertEqual(text, #"{"id":"plan-1"}"#)
    }

    func testOutputTextExtractorReadsMessageContentText() throws {
        let data = Data(
            """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"id\\":\\"plan-1\\"}"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        let text = try OpenAIResponsesOutputTextExtractor().extractText(from: data)

        XCTAssertEqual(text, #"{"id":"plan-1"}"#)
    }

    func testOutputTextExtractorIgnoresNonMessageOutputItems() throws {
        let data = Data(
            """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "reasoning",
                  "summary": []
                },
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"id\\":\\"plan-1\\"}"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        let text = try OpenAIResponsesOutputTextExtractor().extractText(from: data)

        XCTAssertEqual(text, #"{"id":"plan-1"}"#)
    }

    func testOutputTextExtractorRejectsOutputTextWithoutTextInsteadOfDroppingIt() throws {
        let data = Data(
            """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text"
                    },
                    {
                      "type": "output_text",
                      "text": "{\\"id\\":\\"plan-1\\"}"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try OpenAIResponsesOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Response output_text item did not contain text.")
            )
        }
    }

    func testOutputTextExtractorRejectsMessageItemWithoutContentInsteadOfDroppingIt() throws {
        let data = Data(
            """
            {
              "id": "resp_1",
              "output": [
                {
                  "type": "message"
                },
                {
                  "type": "message",
                  "content": [
                    {
                      "type": "output_text",
                      "text": "{\\"id\\":\\"plan-1\\"}"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try OpenAIResponsesOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("Response message item did not contain content.")
            )
        }
    }

    func testOutputTextExtractorMapsDecodeFailureToInvalidResponse() throws {
        let data = Data(
            """
            {
              "output": "not-an-array"
            }
            """.utf8
        )

        XCTAssertThrowsError(try OpenAIResponsesOutputTextExtractor().extractText(from: data)) { error in
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("OpenAI Responses payload could not be decoded.")
            )
        }
    }

    func testProviderRejectsMissingAPIKeyBeforeHTTP() async throws {
        let provider = OpenAIResponsesProvider(
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

    func testProviderRejectsAPIKeyWithInternalWhitespaceBeforeHTTP() async throws {
        let provider = OpenAIResponsesProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test invalid"]),
            httpClient: StubHTTPDataClient(data: Data(), statusCode: 200)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected malformed API key to fail before HTTP.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
        }
    }

    func testProviderMapsRateLimitStatus() async throws {
        let store = InMemorySecretStore(values: [.openAIAPIKey: "sk-test"])
        let provider = OpenAIResponsesProvider(
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

    func testProviderIncludesRedactedMalformedHTTPErrorBodyPreview() async throws {
        let store = InMemorySecretStore(values: [.openAIAPIKey: "sk-test"])
        let secret = "sk-" + "serverSecret123"
        let provider = OpenAIResponsesProvider(
            secretStore: store,
            httpClient: StubHTTPDataClient(
                data: Data("upstream failed api_key=\(secret) request-id=resp-500".utf8),
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
            XCTAssertTrue(message.contains("request-id=resp-500"))
            XCTAssertFalse(message.contains("No error message"))
            XCTAssertFalse(message.contains(secret))
            XCTAssertTrue(message.contains("[REDACTED_SECRET]"))
        }
    }

    func testProviderMapsSuccessfulEnvelopeSchemaMismatchToInvalidResponse() async throws {
        let provider = OpenAIResponsesProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            httpClient: StubHTTPDataClient(data: Data(#"{"output":"not-an-array"}"#.utf8), statusCode: 200)
        )

        do {
            _ = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))
            XCTFail("Expected success envelope mismatch to fail.")
        } catch {
            XCTAssertEqual(
                error as? LLMProviderError,
                .invalidResponse("OpenAI Responses payload could not be decoded.")
            )
        }
    }

    func testProviderParsesSuccessfulResponse() async throws {
        let store = InMemorySecretStore(values: [.openAIAPIKey: "sk-test"])
        let provider = OpenAIResponsesProvider(
            secretStore: store,
            httpClient: StubHTTPDataClient(
                data: Data(
                    """
                    {
                      "output": [
                        {
                          "type": "message",
                          "content": [
                            {
                              "type": "output_text",
                              "text": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                            }
                          ]
                        }
                      ]
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "openai.responses")
        XCTAssertEqual(response.actionPlan?.id, "plan-1")
        XCTAssertTrue(response.validationResult.isValid)
    }

    func testProviderCarriesMeasuredUsageAndResponseModelIntoPlanningResponse() async throws {
        let store = InMemorySecretStore(values: [.openAIAPIKey: "sk-test"])
        let provider = OpenAIResponsesProvider(
            secretStore: store,
            httpClient: StubHTTPDataClient(
                data: Data(
                    """
                    {
                      "id": "resp_usage",
                      "model": "gpt-5.5",
                      "output_text": "{\\"id\\":\\"plan-usage\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}",
                      "usage": {
                        "input_tokens": 700,
                        "output_tokens": 90,
                        "total_tokens": 790
                      }
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.model, ExecutionReceiptModel(provider: "openai.responses", name: "gpt-5.5"))
        XCTAssertEqual(response.usage.state, .measured)
        XCTAssertEqual(response.usage.inputTokens, 700)
        XCTAssertEqual(response.usage.outputTokens, 90)
        XCTAssertNil(response.usage.estimatedCostCents)
    }

    func testProviderReturnsBlockingValidationForActionPlanSchemaMismatch() async throws {
        let provider = OpenAIResponsesProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            httpClient: StubHTTPDataClient(
                data: Data(
                    """
                    {
                      "output_text": "{\\"id\\":\\"plan-1\\",\\"userInput\\":\\"Create a task\\",\\"summary\\":\\"Create task\\",\\"riskLevel\\":\\"write\\",\\"requiresApproval\\":true,\\"unexpected\\":true,\\"actions\\":[{\\"id\\":\\"action-1\\",\\"tool\\":\\"task.create\\"}]}"
                    }
                    """.utf8
                ),
                statusCode: 200
            )
        )

        let response = try await provider.generatePlan(for: PlanningRequest(userInput: "Create a task"))

        XCTAssertEqual(response.providerID, "openai.responses")
        XCTAssertNil(response.actionPlan)
        XCTAssertFalse(response.validationResult.isValid)
        XCTAssertEqual(response.validationResult.issues.first?.path, "unexpected")
    }
}

private struct StubHTTPDataClient: HTTPDataClient {
    var data: Data
    var statusCode: Int

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://api.openai.com/v1/responses")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }
}
