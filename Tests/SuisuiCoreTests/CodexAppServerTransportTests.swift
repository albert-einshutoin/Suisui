import Foundation
import XCTest
@testable import SuisuiCore

final class CodexAppServerTransportTests: XCTestCase {
    func testConcurrentRequestsAreCorrelatedByIDWhileNotificationsStream() async throws {
        let process = ScriptedCodexProcess()
        let transport = CodexAppServerStdioTransport(process: process)
        let notificationStream = await transport.notifications()
        let secondNotificationStream = await transport.notifications()
        let notificationTask = Task { try await notificationStream.firstValue() }
        let secondNotificationTask = Task { try await secondNotificationStream.firstValue() }

        async let account = transport.request(method: CodexAppServerMethod.accountRead, params: .object([:]), timeout: 1)
        async let models = transport.request(method: CodexAppServerMethod.modelList, params: .object([:]), timeout: 1)

        let accountResponse = try await account
        let modelResponse = try await models
        XCTAssertEqual(Set([accountResponse.id, modelResponse.id]), Set([1, 2]))
        XCTAssertNotEqual(accountResponse.id, modelResponse.id)
        XCTAssertEqual(accountResponse.result, .object(["source": .string("account")]))
        XCTAssertEqual(modelResponse.result, .object(["source": .string("models")]))
        let notification = try await notificationTask.value
        let secondNotification = try await secondNotificationTask.value
        XCTAssertEqual(notification.method, "account/updated")
        XCTAssertEqual(secondNotification, notification)
        await transport.shutdown()
    }

    func testRequestTimesOutAndDoesNotAcceptLateResponse() async throws {
        let process = LateThenResponsiveCodexProcess()
        let transport = CodexAppServerStdioTransport(process: process)

        await XCTAssertThrowsErrorAsync(
            try await transport.request(method: CodexAppServerMethod.accountRead, params: nil, timeout: 0.01)
        ) { error in
            XCTAssertEqual(error as? CodexAppServerTransportError, .timeout(method: CodexAppServerMethod.accountRead))
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        let response = try await transport.request(
            method: CodexAppServerMethod.modelList,
            params: nil,
            timeout: 1
        )
        XCTAssertEqual(response.id, 2)
        XCTAssertEqual(response.result, .object(["accepted": .bool(true)]))
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
            Array(launch.arguments.suffix(7)),
            ["-c", "web_search=\"disabled\"", "-c", "mcp_servers={}", "app-server", "--listen", "stdio://"]
        )
        XCTAssertTrue(launch.arguments.containsSubsequence(["--disable", "shell_tool"]))
        XCTAssertTrue(launch.arguments.containsSubsequence(["--disable", "unified_exec"]))
        XCTAssertTrue(launch.arguments.containsSubsequence(["--disable", "browser_use"]))
        XCTAssertTrue(launch.arguments.containsSubsequence(["--disable", "plugins"]))
        XCTAssertEqual(launch.environment, [
            "HOME": "/Users/example",
            "PATH": "/usr/bin:/bin",
            "LANG": "ja_JP.UTF-8"
        ])
    }

    func testExecutableSwapAfterVersionCheckFailsBeforeAppServerLaunch() async throws {
        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-launch-integrity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex")
        let marker = directory.appendingPathComponent("launched")
        try Data("#!/bin/sh\ntouch \"$1\"\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: executable.path,
            trustPolicy: .developerUnsignedAllowed
        )

        try Data("#!/bin/sh\ntouch '\(marker.path)'\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let process = ProcessCodexAppServerProcess(
            configuration: CodexAppServerLaunchConfiguration(executablePath: executable.path),
            approvedExecutable: approved
        )

        await XCTAssertThrowsErrorAsync(try await process.start()) { error in
            XCTAssertEqual(
                error as? CodexAppServerRuntimeConfigurationError,
                .approvedExecutableChanged
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        #endif
    }

    func testApprovedSymlinkLaunchesItsVerifiedResolvedTarget() async throws {
        #if os(macOS)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-codex-symlink-launch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("codex-target")
        let selected = directory.appendingPathComponent("codex")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        try FileManager.default.createSymbolicLink(at: selected, withDestinationURL: executable)
        let approved = try CodexAppServerRuntimeConfiguration.approve(
            executablePath: selected.path,
            trustPolicy: .developerUnsignedAllowed
        )
        let process = ProcessCodexAppServerProcess(
            configuration: CodexAppServerLaunchConfiguration(executablePath: selected.path),
            approvedExecutable: approved
        )

        try await process.start()
        await process.stop()
        #endif
    }
}

private extension Array where Element: Equatable {
    func containsSubsequence(_ subsequence: [Element]) -> Bool {
        guard !subsequence.isEmpty, subsequence.count <= count else { return false }
        return indices.dropLast(subsequence.count - 1).contains { index in
            Array(self[index..<(index + subsequence.count)]) == subsequence
        }
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

private actor LateThenResponsiveCodexProcess: CodexAppServerProcess {
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation

    init() {
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    func start() async throws {}
    func writeLine(_ data: Data) async throws {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let id = try XCTUnwrap((object["id"] as? NSNumber)?.int64Value)
        let continuation = continuation
        if id == 1 {
            Task {
                try? await Task.sleep(nanoseconds: 25_000_000)
                continuation.yield(Data(#"{"jsonrpc":"2.0","id":1,"result":{"late":true}}"#.utf8))
            }
        } else {
            continuation.yield(Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{\"accepted\":true}}".utf8))
        }
    }
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
