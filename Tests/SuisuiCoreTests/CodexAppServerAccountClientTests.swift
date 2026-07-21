import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerAccountClientTests: XCTestCase {
    func testBrowserLoginReturnsOnlyAllowedURLAndCompletesFromMatchingNotification() async throws {
        let transport = RecordingCodexTransport(responses: [
            CodexAppServerMethod.accountLoginStart: [
                .object([
                    "type": .string("chatgpt"),
                    "loginId": .string("login-1"),
                    "authUrl": .string("https://auth.openai.com/oauth/authorize?client_id=example")
                ])
            ],
            CodexAppServerMethod.accountRead: [
                .object([
                    "account": .object([
                        "type": .string("chatgpt"),
                        "email": .string("private@example.com"),
                        "planType": .string("plus")
                    ]),
                    "requiresOpenaiAuth": .bool(true)
                ])
            ]
        ])
        let client = CodexAppServerAccountClient(transport: transport)

        let attempt = try await client.startLogin(.chatGPTBrowser)
        XCTAssertEqual(attempt.authorizationURL.host, "auth.openai.com")
        let completion = Task { try await client.awaitLogin(id: attempt.id, timeout: 1) }
        await transport.emit(
            CodexJSONRPCNotification(
                id: nil,
                method: "account/login/completed",
                params: .object(["loginId": .string("login-1"), "success": .bool(true)])
            )
        )

        let readiness = try await completion.value
        XCTAssertEqual(readiness, .ready(plan: .plus))
        let traffic = await transport.encodedTraffic
        XCTAssertFalse(traffic.contains("accessToken"))
        XCTAssertFalse(traffic.contains("refreshToken"))
        XCTAssertFalse(traffic.contains("private@example.com"))
    }

    func testInitializeUsesSuisuiClientIdentityWithoutExperimentalCapabilities() async throws {
        let transport = RecordingCodexTransport(responses: [
            CodexAppServerMethod.initialize: [.object(["userAgent": .string("codex-app-server")])]
        ])
        let client = CodexAppServerAccountClient(transport: transport)

        try await client.initialize(clientVersion: "1.2.3")

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, CodexAppServerMethod.initialize)
        XCTAssertEqual(request.params?["clientInfo"]?["name"], .string("suisui"))
        XCTAssertEqual(request.params?["clientInfo"]?["title"], .string("Suisui"))
        XCTAssertEqual(request.params?["clientInfo"]?["version"], .string("1.2.3"))
        XCTAssertNil(request.params?["capabilities"])
        XCTAssertNil(request.params?["experimentalApi"])
    }

    func testLoginRejectsUntrustedAuthenticationURL() async throws {
        let transport = RecordingCodexTransport(responses: [
            CodexAppServerMethod.accountLoginStart: [
                .object([
                    "type": .string("chatgpt"),
                    "loginId": .string("login-1"),
                    "authUrl": .string("https://phishing.example/authorize")
                ])
            ]
        ])
        let client = CodexAppServerAccountClient(transport: transport)

        await XCTAssertThrowsCodexAccountError(try await client.startLogin(.chatGPTBrowser)) { error in
            XCTAssertEqual(error, .unsafeAuthenticationURL)
        }
    }

    func testStaleLoginCompletionDoesNotCompleteCurrentAttempt() async throws {
        let transport = RecordingCodexTransport(responses: [
            CodexAppServerMethod.accountLoginStart: [
                .object([
                    "type": .string("chatgpt"),
                    "loginId": .string("login-current"),
                    "authUrl": .string("https://chatgpt.com/auth")
                ])
            ]
        ])
        let client = CodexAppServerAccountClient(transport: transport)
        let attempt = try await client.startLogin(.chatGPTBrowser)
        let completion = Task { try await client.awaitLogin(id: attempt.id, timeout: 0.02) }

        await transport.emit(
            CodexJSONRPCNotification(
                id: nil,
                method: "account/login/completed",
                params: .object(["loginId": .string("stale"), "success": .bool(true)])
            )
        )

        await XCTAssertThrowsCodexAccountError(try await completion.value) { error in
            XCTAssertEqual(error, .loginTimedOut)
        }
    }

    func testAccountReadMapsWorkspacePolicyFailureWithoutStartingLoginLoop() async throws {
        let transport = RecordingCodexTransport(
            responses: [:],
            failures: [
                CodexAppServerMethod.accountRead: [
                    .remote(code: -32_000, message: "Codex is disabled by your workspace administrator policy.")
                ]
            ]
        )
        let client = CodexAppServerAccountClient(transport: transport)

        let snapshot = try await client.readAccount(refresh: false)

        XCTAssertEqual(snapshot.readiness, .workspaceDisabled)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.method), [CodexAppServerMethod.accountRead])
    }
}

private actor RecordingCodexTransport: CodexAppServerTransport {
    struct Request: Sendable {
        let method: String
        let params: JSONValue?
    }

    private var responses: [String: [JSONValue]]
    private var failures: [String: [CodexAppServerTransportError]]
    private let stream: AsyncStream<CodexJSONRPCNotification>
    private let continuation: AsyncStream<CodexJSONRPCNotification>.Continuation
    private(set) var requests: [Request] = []
    private(set) var encodedTraffic = ""

    init(
        responses: [String: [JSONValue]],
        failures: [String: [CodexAppServerTransportError]] = [:]
    ) {
        self.responses = responses
        self.failures = failures
        (stream, continuation) = AsyncStream.makeStream(of: CodexJSONRPCNotification.self)
    }

    func start() async throws {}

    func request(method: String, params: JSONValue?, timeout _: TimeInterval) async throws -> CodexRawJSONRPCResponse {
        requests.append(Request(method: method, params: params))
        encodedTraffic += method + String(describing: params)
        if var queuedFailures = failures[method], !queuedFailures.isEmpty {
            let error = queuedFailures.removeFirst()
            failures[method] = queuedFailures
            throw error
        }
        guard var queued = responses[method], !queued.isEmpty else {
            throw CodexAppServerTransportError.streamClosed
        }
        let result = queued.removeFirst()
        responses[method] = queued
        return CodexRawJSONRPCResponse(id: Int64(requests.count), result: result)
    }

    func notify(method _: String, params _: JSONValue?) async throws {}
    func respond(id _: Int64, result _: JSONValue) async throws {}
    func notifications() async -> AsyncStream<CodexJSONRPCNotification> { stream }
    func shutdown() async { continuation.finish() }
    func emit(_ notification: CodexJSONRPCNotification) { continuation.yield(notification) }
}

private extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case let .object(values) = self else { return nil }
        return values[key]
    }
}

private func XCTAssertThrowsCodexAccountError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (CodexAccountClientError) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch let error as CodexAccountClientError {
        errorHandler(error)
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
