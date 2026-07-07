import XCTest
@testable import SoloPMCore

final class ClaudeMessagesStreamingTests: XCTestCase {
    private struct StubByteStreamClient: HTTPByteStreamClient {
        var lines: [String]
        var statusCode: Int = 200

        func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.anthropic.com/v1/messages")!,
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

    private func makeProvider(client: StubByteStreamClient) -> ClaudeMessagesProvider {
        ClaudeMessagesProvider(
            secretStore: InMemorySecretStore(values: [.anthropicAPIKey: "sk-ant-test"]),
            byteStreamClient: client
        )
    }

    private func makeRequest() -> PlanningRequest {
        PlanningRequest(userInput: "Create a task to ship the release notes tomorrow.")
    }

    func testStreamingAccumulatesDeltasAndParsesFinalResponse() async throws {
        let client = StubByteStreamClient(lines: [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"msg_1"}}"#,
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"{\"plan_summary\": \"Ship notes\", "}}"#,
            "",
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"\"risk_level\": \"write\", \"actions\": []}"}}"#,
            #"data: {"type":"message_stop"}"#
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
        XCTAssertEqual(response.providerID, "claude.messages")
        XCTAssertEqual(response.rawContent, recorder.deltas.joined())
    }

    func testStreamingIgnoresNonTextEventsAndPings() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"type":"ping"}"#,
            #"data: {"type":"content_block_start","content_block":{"type":"text"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"hello plan"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{}"}}"#,
            #"data: {"type":"message_stop"}"#
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        let response = try await provider.generatePlanStream(for: makeRequest()) { delta in
            recorder.append(delta)
        }

        XCTAssertEqual(recorder.deltas, ["hello plan"])
        XCTAssertEqual(response.rawContent, "hello plan")
    }

    func testStreamingSurfacesServerErrorEvent() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        ])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected an invalidResponse error.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("Overloaded"))
        }
    }

    func testStreamingMapsHTTPStatusErrors() async throws {
        let client = StubByteStreamClient(
            lines: [#"{"type":"error","error":{"type":"authentication_error","message":"bad key"}}"#],
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
        let client = StubByteStreamClient(lines: [#"data: {"type":"message_stop"}"#])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected invalidResponse for an empty stream.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("Claude Messages stream did not contain text content."))
        }
    }

    func testRequestBuilderMarksStreamingRequests() throws {
        let builder = ClaudeMessagesRequestBuilder()
        let prompt = PlanningPrompt(system: "system", user: "user")

        let request = try builder.makeRequest(apiKey: "sk-ant-test-key", prompt: prompt, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)

        let nonStreaming = try builder.makeRequest(apiKey: "sk-ant-test-key", prompt: prompt)
        let defaultBody = try XCTUnwrap(nonStreaming.httpBody)
        let defaultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: defaultBody) as? [String: Any])
        XCTAssertEqual(defaultJSON["stream"] as? Bool, false)
    }
}
