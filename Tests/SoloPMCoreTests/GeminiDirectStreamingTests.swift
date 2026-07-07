import XCTest
@testable import SoloPMCore

final class GeminiDirectStreamingTests: XCTestCase {
    private struct StubByteStreamClient: HTTPByteStreamClient {
        var lines: [String]
        var statusCode: Int = 200

        func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
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

    private func makeProvider(client: StubByteStreamClient) -> GeminiDirectProvider {
        GeminiDirectProvider(
            secretStore: InMemorySecretStore(values: [.geminiAPIKey: "gemini-test-key"]),
            byteStreamClient: client
        )
    }

    private func makeRequest() -> PlanningRequest {
        PlanningRequest(userInput: "Create a task to ship the release notes tomorrow.")
    }

    func testStreamingAccumulatesDeltasAndParsesFinalResponse() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"candidates":[{"content":{"parts":[{"text":"{\"plan_summary\": \"Ship notes\", "}]}}]}"#,
            "",
            #"data: {"candidates":[{"content":{"parts":[{"text":"\"risk_level\": \"write\", \"actions\": []}"}]},"finishReason":"STOP"}]}"#
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
        XCTAssertEqual(response.providerID, "gemini.direct")
        XCTAssertEqual(response.rawContent, recorder.deltas.joined())
    }

    func testStreamingIgnoresPromptFeedbackAndEmptyCandidateChunks() async throws {
        let client = StubByteStreamClient(lines: [
            #"data: {"promptFeedback":{"safetyRatings":[]}}"#,
            #"data: {"candidates":[]}"#,
            #"data: {"candidates":[{"content":{"parts":[{"text":"hello plan"}]}}]}"#,
            #"data: {"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}"#
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
            #"data: {"error":{"code":503,"message":"The model is overloaded.","status":"UNAVAILABLE"}}"#
        ])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected an invalidResponse error.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("The model is overloaded."))
        }
    }

    func testStreamingMapsHTTPStatusErrors() async throws {
        let client = StubByteStreamClient(
            lines: [#"{"error":{"message":"Request had invalid authentication credentials."}}"#],
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
        let client = StubByteStreamClient(lines: [#"data: {"candidates":[]}"#])
        let provider = makeProvider(client: client)

        do {
            _ = try await provider.generatePlanStream(for: makeRequest()) { _ in }
            XCTFail("Expected invalidResponse for an empty stream.")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse("Gemini Direct stream did not contain text content."))
        }
    }

    func testRequestBuilderSwitchesToStreamGenerateContentEndpoint() throws {
        let builder = GeminiDirectRequestBuilder()
        let prompt = PlanningPrompt(system: "system", user: "user")

        let request = try builder.makeRequest(apiKey: "gemini-test-key", prompt: prompt, stream: true)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:streamGenerateContent?alt=sse"
        )

        let nonStreaming = try builder.makeRequest(apiKey: "gemini-test-key", prompt: prompt)
        XCTAssertEqual(
            nonStreaming.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent"
        )
    }
}
