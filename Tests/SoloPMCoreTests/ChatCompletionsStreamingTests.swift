import XCTest
@testable import SoloPMCore

final class ChatCompletionsStreamingTests: XCTestCase {
    private struct StubByteStreamClient: HTTPByteStreamClient {
        var lines: [String]
        var statusCode: Int = 200

        func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            let captured = lines
            let stream = AsyncThrowingStream<String, Error> { continuation in
                for line in captured {
                    continuation.yield(line)
                }
                continuation.finish()
            }
            return (stream, response)
        }
    }

    private final class DeltaRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ delta: String) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(delta)
        }

        var deltas: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private func makeProvider(client: StubByteStreamClient) -> ChatCompletionsCompatibleProvider {
        ChatCompletionsCompatibleProvider(
            configuration: .groq(model: "llama-3.3-70b-versatile"),
            secretStore: InMemorySecretStore(values: [.groqAPIKey: "gsk-test"]),
            byteStreamClient: client
        )
    }

    private func makeRequest() -> PlanningRequest {
        PlanningRequest(userInput: "Create a task to ship the release notes tomorrow.")
    }

    func testStreamingAccumulatesDeltasAndParsesFinalResponse() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{"content":"{\"plan_summary\": \"Ship notes\", "}}]}"#,
            "",
            #"data: {"choices":[{"delta":{"content":"\"risk_level\": \"write\", \"actions\": []}"}}]}"#,
            "data: [DONE]"
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        let response = try await provider.generatePlanStream(for: makeRequest()) { delta in
            recorder.append(delta)
        }

        XCTAssertEqual(recorder.deltas.count, 2)
        XCTAssertEqual(
            recorder.deltas.joined(),
            "{\"plan_summary\": \"Ship notes\", \"risk_level\": \"write\", \"actions\": []}"
        )
        XCTAssertEqual(response.providerID, "groq.chat")
        XCTAssertEqual(response.rawContent, recorder.deltas.joined())
    }

    func testStreamingIgnoresContentlessChunksAndDoneMarker() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#,
            #"data: {"choices":[{"delta":{}}]}"#,
            #"data: {"choices":[{"delta":{"content":"hello plan"}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":0}]}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "data: [DONE]"
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        let response = try await provider.generatePlanStream(for: makeRequest()) { delta in
            recorder.append(delta)
        }

        XCTAssertEqual(recorder.deltas, ["hello plan"])
        XCTAssertEqual(response.rawContent, "hello plan")
    }

    func testStreamingSurfacesServerErrorPayload() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"error":{"message":"Model overloaded","type":"server_error"}}"#
        ])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected an invalidResponse error.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("Model overloaded"))
        }
    }

    func testStreamingMapsHTTPStatusErrors() async throws {
        let client = StubByteStreamClient(
            lines: [#"{"error":{"message":"Invalid API key"}}"#],
            statusCode: 401
        )
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected authenticationFailed.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .authenticationFailed)
        }
    }

    func testStreamingRejectsEmptyStreams() async throws {
        let client = StubByteStreamClient(lines: ["data: [DONE]"])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected invalidResponse for an empty stream.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("Chat completion stream did not contain text content."))
        }
    }

    func testRequestBuilderMarksStreamingRequests() throws {
        let builder = ChatCompletionsCompatibleRequestBuilder(
            configuration: .groq(model: "llama-3.3-70b-versatile")
        )
        let prompt = PlanningPrompt(system: "system", user: "user")

        let request = try builder.makeRequest(apiKey: "gsk-test", prompt: prompt, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)

        let nonStreaming = try builder.makeRequest(apiKey: "gsk-test", prompt: prompt)
        let defaultBody = try XCTUnwrap(nonStreaming.httpBody)
        let defaultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: defaultBody) as? [String: Any])
        XCTAssertEqual(defaultJSON["stream"] as? Bool, false)
    }
}
