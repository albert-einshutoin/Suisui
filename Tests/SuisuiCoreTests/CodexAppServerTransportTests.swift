import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerTransportTests: XCTestCase {
    func testConcurrentRequestsAreCorrelatedByIDWhileNotificationsStream() async throws {
        let process = ScriptedCodexProcess()
        let transport = CodexAppServerStdioTransport(process: process)
        let notificationStream = await transport.notifications()
        let notificationTask = Task { try await notificationStream.firstValue() }

        async let account = transport.request(method: CodexAppServerMethod.accountRead, params: .object([:]), timeout: 1)
        async let models = transport.request(method: CodexAppServerMethod.modelList, params: .object([:]), timeout: 1)

        let accountResponse = try await account
        let modelResponse = try await models
        XCTAssertEqual(Set([accountResponse.id, modelResponse.id]), Set([1, 2]))
        XCTAssertNotEqual(accountResponse.id, modelResponse.id)
        XCTAssertEqual(accountResponse.result, .object(["source": .string("account")]))
        XCTAssertEqual(modelResponse.result, .object(["source": .string("models")]))
        let notification = try await notificationTask.value
        XCTAssertEqual(notification.method, "account/updated")
        await transport.shutdown()
    }

    func testRequestTimesOutAndDoesNotAcceptLateResponse() async throws {
        let process = SilentCodexProcess()
        let transport = CodexAppServerStdioTransport(process: process)

        await XCTAssertThrowsErrorAsync(
            try await transport.request(method: CodexAppServerMethod.accountRead, params: nil, timeout: 0.01)
        ) { error in
            XCTAssertEqual(error as? CodexAppServerTransportError, .timeout(method: CodexAppServerMethod.accountRead))
        }
        await transport.shutdown()
    }

    func testMalformedJSONFailsPendingRequestClosed() async throws {
        let process = MalformedCodexProcess()
        let transport = CodexAppServerStdioTransport(process: process)

        await XCTAssertThrowsErrorAsync(
            try await transport.request(method: CodexAppServerMethod.accountRead, params: nil, timeout: 1)
        ) { error in
            XCTAssertEqual(error as? CodexAppServerTransportError, .malformedMessage)
        }
        await transport.shutdown()
    }

    func testProductionLaunchDisablesExecutionToolsAndFiltersSecretsFromEnvironment() {
        let launch = CodexAppServerLaunchConfiguration(
            executablePath: "/opt/homebrew/bin/codex",
            parentEnvironment: [
                "HOME": "/Users/example",
                "PATH": "/usr/bin:/bin",
                "LANG": "ja_JP.UTF-8",
                "OPENAI_API_KEY": "secret",
                "CODEX_ACCESS_TOKEN": "secret",
                "SUISUI_INTERNAL_TOKEN": "secret"
            ]
        )

        XCTAssertEqual(
            launch.arguments,
            ["--disable", "shell_tool", "--disable", "unified_exec", "app-server", "--listen", "stdio://"]
        )
        XCTAssertEqual(launch.environment, [
            "HOME": "/Users/example",
            "PATH": "/usr/bin:/bin",
            "LANG": "ja_JP.UTF-8"
        ])
    }
}

private actor ScriptedCodexProcess: CodexAppServerProcess {
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    func start() async throws {}

    func writeLine(_ data: Data) async throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let id = try XCTUnwrap((object["id"] as? NSNumber)?.int64Value)
        let method = try XCTUnwrap(object["method"] as? String)
        let source = method == CodexAppServerMethod.accountRead ? "account" : "models"
        let delay: UInt64 = method == CodexAppServerMethod.accountRead ? 20_000_000 : 1_000_000
        let continuation = continuation
        Task {
            try? await Task.sleep(nanoseconds: delay)
            if method == CodexAppServerMethod.modelList {
                continuation.yield(Data(#"{"jsonrpc":"2.0","method":"account/updated","params":{}}"#.utf8))
            }
            continuation.yield(Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{\"source\":\"\(source)\"}}".utf8))
        }
    }

    func inboundLines() async -> AsyncThrowingStream<Data, Error> { stream }
    func redactedStderr() async -> String { "" }
    func stop() async { continuation.finish() }
}

private actor SilentCodexProcess: CodexAppServerProcess {
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    func start() async throws {}
    func writeLine(_: Data) async throws {}
    func inboundLines() async -> AsyncThrowingStream<Data, Error> { stream }
    func redactedStderr() async -> String { "" }
    func stop() async { continuation.finish() }
}

private actor MalformedCodexProcess: CodexAppServerProcess {
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    func start() async throws {}
    func writeLine(_: Data) async throws { continuation.yield(Data("not-json".utf8)) }
    func inboundLines() async -> AsyncThrowingStream<Data, Error> { stream }
    func redactedStderr() async -> String { "" }
    func stop() async { continuation.finish() }
}

private extension AsyncStream where Element == CodexJSONRPCNotification {
    func firstValue() async throws -> Element {
        for await value in self { return value }
        throw CodexAppServerTransportError.streamClosed
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (any Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
