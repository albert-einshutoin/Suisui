import XCTest
@testable import SoloPMCore

final class OpenAIResponsesStreamingTests: XCTestCase {
    private struct StubByteStreamClient: HTTPByteStreamClient {
        var lines: [String]
        var statusCode: Int = 200

        func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.openai.com/v1/responses")!,
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

    private func makeProvider(client: StubByteStreamClient) -> OpenAIResponsesProvider {
        OpenAIResponsesProvider(
            secretStore: InMemorySecretStore(values: [.openAIAPIKey: "sk-test"]),
            byteStreamClient: client
        )
    }

    private func makeRequest() -> PlanningRequest {
        PlanningRequest(userInput: "Create a task to ship the release notes tomorrow.")
    }

    func testStreamingAccumulatesDeltasAndParsesFinalResponse() async throws {
        let client = StubByteStreamClient(lines: [
            "event: response.created",
            #"data: {"type":"response.created","response":{"id":"resp_1"}}"#,
            "event: response.output_text.delta",
            #"data: {"type":"response.output_text.delta","delta":"{\"plan_summary\": \"Ship notes\", "}"#,
            "",
            #"data: {"type":"response.output_text.delta","delta":"\"risk_level\": \"write\", \"actions\": []}"}"#,
            #"data: {"type":"response.completed","response":{"id":"resp_1"}}"#
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
        XCTAssertEqual(response.providerID, "openai.responses")
        XCTAssertEqual(response.rawContent, recorder.deltas.joined())
    }

    func testStreamingIgnoresNonDeltaEventTypes() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"type":"response.created","response":{"id":"resp_1"}}"#,
            #"data: {"type":"response.output_item.added","output_index":0}"#,
            #"data: {"type":"response.output_text.delta","delta":"hello plan"}"#,
            #"data: {"type":"response.output_text.done","text":"hello plan"}"#,
            #"data: {"type":"response.completed","response":{"id":"resp_1"}}"#
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        let response = try await provider.generatePlanStream(for: makeRequest()) { delta in
            recorder.append(delta)
        }

        XCTAssertEqual(recorder.deltas, ["hello plan"])
        XCTAssertEqual(response.rawContent, "hello plan")
    }

    func testStreamingSurfacesErrorEvent() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"type":"error","code":"server_error","message":"The server had an error."}"#
        ])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected an invalidResponse error.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("The server had an error."))
        }
    }

    func testStreamingSurfacesResponseFailedEvent() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"type":"response.failed","response":{"id":"resp_1","error":{"code":"server_error","message":"Generation failed."}}}"#
        ])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected an invalidResponse error.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("Generation failed."))
        }
    }

    func testStreamingMapsHTTPStatusErrors() async throws {
        let client = StubByteStreamClient(
            lines: [#"{"error":{"message":"Incorrect API key provided."}}"#],
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
        let client = StubByteStreamClient(lines: [
            #"data: {"type":"response.completed","response":{"id":"resp_1"}}"#
        ])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected invalidResponse for an empty stream.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("OpenAI Responses stream did not contain text content."))
        }
    }

    func testRequestBuilderMarksStreamingRequests() throws {
        let builder = OpenAIResponsesRequestBuilder()
        let prompt = PlanningPrompt(system: "system", user: "user")

        let request = try builder.makeRequest(apiKey: "sk-test", prompt: prompt, stream: true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)

        let nonStreaming = try builder.makeRequest(apiKey: "sk-test", prompt: prompt)
        let defaultBody = try XCTUnwrap(nonStreaming.httpBody)
        let defaultJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: defaultBody) as? [String: Any])
        XCTAssertEqual(defaultJSON["stream"] as? Bool, false)
    }
}
