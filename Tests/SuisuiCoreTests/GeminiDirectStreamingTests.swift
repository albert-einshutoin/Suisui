import XCTest
@testable import SuisuiCore

final class GeminiDirectStreamingTests: XCTestCase {
    private struct StubByteStreamClient: HTTPByteStreamClient {
        var lines: [String]
        var statusCode: Int = 200
        var onRequest: (@Sendable (URLRequest) -> Void)?

        func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
            onRequest?(request)
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

    private final class RequestRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: URLRequest?

        func record(_ request: URLRequest) {
            lock.lock()
            defer { lock.unlock() }
            storage = request
        }

        var request: URLRequest? {
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

    func testStreamingSendsAvailableToolsAsGeminiFunctionDeclarations() async throws {
        let requestRecorder = RequestRecorder()
        let client = StubByteStreamClient(
            lines: [
                #"data: {"candidates":[{"content":{"parts":[{"text":"{\"plan_summary\": \"Ship notes\", \"risk_level\": \"write\", \"actions\": []}"}]},"finishReason":"STOP"}]}"#
            ],
            onRequest: { requestRecorder.record($0) }
        )
        let provider = makeProvider(client: client)

        _ = try await provider.generatePlanStream(
            for: PlanningRequest(
                userInput: "Create a task to ship the release notes tomorrow.",
                availableTools: [.taskCreate]
            )
        ) { _ in }

        let body = try XCTUnwrap(requestRecorder.request?.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let generationConfig = try XCTUnwrap(object["generationConfig"] as? [String: Any])
        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        let firstTool = try XCTUnwrap(tools.first)
        let declarations = try XCTUnwrap(firstTool["functionDeclarations"] as? [[String: Any]])
        let names = declarations.compactMap { $0["name"] as? String }

        XCTAssertNil(generationConfig["responseMimeType"])
        XCTAssertEqual(names, ["task_create"])
    }

    func testStreamingMapsGeminiFunctionCallsToActionPlan() async throws {
        let client = StubByteStreamClient(lines: [
            """
            data: {"candidates":[{"content":{"parts":[{"functionCall":{"id":"call-1","name":"task_create","args":{"title":"Review MCP bridge","priority":"high"}}}]},"finishReason":"STOP"}]}
            """
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        let response = try await provider.generatePlanStream(
            for: PlanningRequest(
                userInput: "MCP bridge review taskを作って",
                availableTools: [.taskCreate]
            )
        ) { delta in
            recorder.append(delta)
        }

        // Function-call chunks synthesize exactly one progress line each so the
        // live preview shows activity; full args stay out of the stream.
        XCTAssertEqual(recorder.deltas, ["▸ task_create — \"Review MCP bridge\"\n"])
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

    func testStreamingFunctionCallChunkEmitsSingleProgressLinePerCall() async throws {
        let client = StubByteStreamClient(lines: [
            """
            data: {"candidates":[{"content":{"parts":[{"functionCall":{"id":"call-1","name":"task_create","args":{"title":"Buy milk","detail":"Also grab oat milk for the office"}}}]},"finishReason":"STOP"}]}
            """
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        _ = try await provider.generatePlanStream(
            for: PlanningRequest(
                userInput: "Buy milk",
                availableTools: [.taskCreate]
            )
        ) { delta in
            recorder.append(delta)
        }

        XCTAssertEqual(recorder.deltas.count, 1)
        let line = try XCTUnwrap(recorder.deltas.first)
        XCTAssertTrue(line.contains("task_create"))
        XCTAssertTrue(line.contains("Buy milk"))
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        // Only the title-like argument may surface, never the full payload.
        XCTAssertFalse(line.contains("oat milk"))
    }

    func testStreamingFunctionCallProgressLineTruncatesLongTitles() async throws {
        let longTitle = String(repeating: "long user content ", count: 20)
        let client = StubByteStreamClient(lines: [
            """
            data: {"candidates":[{"content":{"parts":[{"functionCall":{"id":"call-1","name":"task_create","args":{"title":"\(longTitle)"}}}]},"finishReason":"STOP"}]}
            """
        ])
        let provider = makeProvider(client: client)
        let recorder = DeltaRecorder()

        _ = try await provider.generatePlanStream(
            for: PlanningRequest(
                userInput: "Create the long task",
                availableTools: [.taskCreate]
            )
        ) { delta in
            recorder.append(delta)
        }

        XCTAssertEqual(recorder.deltas.count, 1)
        let line = try XCTUnwrap(recorder.deltas.first)
        XCTAssertTrue(line.contains("task_create"))
        XCTAssertTrue(line.contains("…"))
        XCTAssertFalse(line.contains(longTitle.trimmingCharacters(in: .whitespaces)))
        // name + separator + quoted 40-char title + ellipsis + newline stays short.
        XCTAssertLessThanOrEqual(line.count, 70)
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
