import XCTest
@testable import SoloPMCore

final class OpenAIResponsesProviderTests: XCTestCase {
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
