import Darwin
import Foundation

public enum CodexAppServerTransportError: Error, Equatable, Sendable {
    case localExecutionUnavailable
    case processLaunchFailed
    case streamClosed
    case malformedMessage
    case duplicateResponseID(Int64)
    case timeout(method: String)
    case remote(code: Int, message: String)
}

public struct CodexRawJSONRPCResponse: Equatable, Sendable {
    public let id: Int64
    public let result: JSONValue
}

public struct CodexJSONRPCNotification: Equatable, Sendable {
    public let id: Int64?
    public let method: String
    public let params: JSONValue?

    public var isServerRequest: Bool { id != nil }
}

public protocol CodexAppServerProcess: Sendable {
    func start() async throws
    func writeLine(_ data: Data) async throws
    func inboundLines() async -> AsyncThrowingStream<Data, Error>
    func redactedStderr() async -> String
    func stop() async
}

public protocol CodexAppServerTransport: Sendable {
    func start() async throws
    func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> CodexRawJSONRPCResponse
    func notify(method: String, params: JSONValue?) async throws
    func respond(id: Int64, result: JSONValue) async throws
    func notifications() async -> AsyncStream<CodexJSONRPCNotification>
    func shutdown() async
}

public actor CodexAppServerStdioTransport: CodexAppServerTransport {
    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<CodexRawJSONRPCResponse, Error>
    }

    private let process: any CodexAppServerProcess
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var notificationContinuations: [UUID: AsyncStream<CodexJSONRPCNotification>.Continuation] = [:]
    private var nextRequestID: Int64 = 1
    private var pending: [Int64: PendingRequest] = [:]
    private var timedOutRequestIDs: Set<Int64> = []
    private var readerTask: Task<Void, Never>?
    private var started = false
    private var stopped = false

    public init(process: any CodexAppServerProcess) {
        self.process = process
    }

    public func start() async throws {
        guard !started else { return }
        guard !stopped else { throw CodexAppServerTransportError.streamClosed }
        do {
            try await process.start()
        } catch let error as CodexAppServerRuntimeConfigurationError {
            throw error
        } catch let error as CodexAppServerTransportError {
            throw error
        } catch {
            throw CodexAppServerTransportError.processLaunchFailed
        }
        started = true
        let lines = await process.inboundLines()
        readerTask = Task { [weak self] in
            do {
                for try await line in lines {
                    guard let self else { return }
                    await self.receive(line)
                }
                guard let self else { return }
                await self.finish(with: CodexAppServerTransportError.streamClosed)
            } catch {
                guard let self else { return }
                await self.finish(with: error)
            }
        }
    }

    public func request(
        method: String,
        params: JSONValue?,
        timeout: TimeInterval
    ) async throws -> CodexRawJSONRPCResponse {
        try await start()
        let id = nextRequestID
        nextRequestID += 1
        let request = WireRequest(id: id, method: method, params: params)
        let data = try encoder.encode(request) + Data([0x0A])

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = PendingRequest(method: method, continuation: continuation)
                Task { [weak self, process] in
                    do {
                        try await process.writeLine(data)
                    } catch {
                        await self?.failRequest(id: id, error: error)
                        return
                    }
                    let nanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    await self?.timeoutRequest(id: id, method: method)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.failRequest(id: id, error: CancellationError())
            }
        }
    }

    public func notify(method: String, params: JSONValue?) async throws {
        try await start()
        let data = try encoder.encode(WireNotification(method: method, params: params)) + Data([0x0A])
        try await process.writeLine(data)
    }

    public func respond(id: Int64, result: JSONValue) async throws {
        try await start()
        let data = try encoder.encode(WireResponse(id: id, result: result)) + Data([0x0A])
        try await process.writeLine(data)
    }

    public func notifications() async -> AsyncStream<CodexJSONRPCNotification> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: CodexJSONRPCNotification.self)
        notificationContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeNotificationSubscriber(id: id) }
        }
        return stream
    }

    public func shutdown() async {
        guard !stopped else { return }
        stopped = true
        readerTask?.cancel()
        readerTask = nil
        finishNotificationStreams()
        failAll(with: CodexAppServerTransportError.streamClosed)
        await process.stop()
    }

    private func receive(_ data: Data) {
        let message: WireInbound
        do {
            message = try decoder.decode(WireInbound.self, from: data)
        } catch {
            finish(with: CodexAppServerTransportError.malformedMessage)
            return
        }

        if let method = message.method {
            let notification = CodexJSONRPCNotification(id: message.id, method: method, params: message.params)
            for continuation in notificationContinuations.values {
                continuation.yield(notification)
            }
            return
        }

        guard let id = message.id else {
            finish(with: CodexAppServerTransportError.malformedMessage)
            return
        }
        guard let request = pending.removeValue(forKey: id) else {
            if timedOutRequestIDs.remove(id) != nil {
                // A timed-out response is stale but not a protocol violation.
                // Keeping it distinct from a truly unknown/duplicate ID makes
                // future warm sessions safe without weakening correlation.
                return
            }
            finish(with: CodexAppServerTransportError.duplicateResponseID(id))
            return
        }
        if let error = message.error {
            request.continuation.resume(throwing: CodexAppServerTransportError.remote(code: error.code, message: error.message))
        } else if let result = message.result {
            request.continuation.resume(returning: CodexRawJSONRPCResponse(id: id, result: result))
        } else {
            request.continuation.resume(throwing: CodexAppServerTransportError.malformedMessage)
        }
    }

    private func timeoutRequest(id: Int64, method: String) {
        guard let request = pending.removeValue(forKey: id) else { return }
        timedOutRequestIDs.insert(id)
        request.continuation.resume(throwing: CodexAppServerTransportError.timeout(method: method))
    }

    private func failRequest(id: Int64, error: any Error) {
        pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    }

    private func finish(with error: any Error) {
        guard !stopped else { return }
        stopped = true
        finishNotificationStreams()
        failAll(with: error)
        Task { [process] in await process.stop() }
    }

    private func failAll(with error: any Error) {
        let requests = pending.values
        pending.removeAll()
        for request in requests {
            request.continuation.resume(throwing: error)
        }
    }

    private func removeNotificationSubscriber(id: UUID) {
        notificationContinuations.removeValue(forKey: id)
    }

    private func finishNotificationStreams() {
        let continuations = notificationContinuations.values
        notificationContinuations.removeAll()
        for continuation in continuations { continuation.finish() }
    }
}

public struct CodexAppServerLaunchConfiguration: Equatable, Sendable {
    public let executablePath: String
    public let arguments: [String]
    public let environment: [String: String]

    public init(executablePath: String, parentEnvironment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executablePath = executablePath
        // These stable feature gates are the primary protection against exposing
        // coding tools to ordinary voice-task prompts.
        arguments = [
            "--disable", "shell_tool",
            "--disable", "unified_exec",
            "--disable", "apps",
            "--disable", "browser_use",
            "--disable", "browser_use_external",
            "--disable", "browser_use_full_cdp_access",
            "--disable", "computer_use",
            "--disable", "image_generation",
            "--disable", "in_app_browser",
            "--disable", "multi_agent",
            "--disable", "plugins",
            "--disable", "remote_plugin",
            "--disable", "tool_call_mcp_elicitation",
            "--disable", "tool_suggest",
            "--disable", "workspace_dependencies",
            "-c", "web_search=\"disabled\"",
            "-c", "mcp_servers={}",
            "app-server", "--listen", "stdio://"
        ]
        let allowedKeys: Set<String> = ["HOME", "PATH", "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR", "USER", "LOGNAME"]
        environment = parentEnvironment.filter { allowedKeys.contains($0.key) }
    }
}

#if os(iOS) || targetEnvironment(macCatalyst)
public actor ProcessCodexAppServerProcess: CodexAppServerProcess {
    public init(
        configuration _: CodexAppServerLaunchConfiguration,
        approvedExecutable _: ApprovedCodexExecutable,
        redactor _: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {}
    public func start() async throws { throw CodexAppServerTransportError.localExecutionUnavailable }
    public func writeLine(_: Data) async throws { throw CodexAppServerTransportError.localExecutionUnavailable }
    public func inboundLines() async -> AsyncThrowingStream<Data, Error> { AsyncThrowingStream { $0.finish() } }
    public func redactedStderr() async -> String { "" }
    public func stop() async {}
}
#else
public final class ProcessCodexAppServerProcess: CodexAppServerProcess, @unchecked Sendable {
    private let configuration: CodexAppServerLaunchConfiguration
    private let approvedExecutable: ApprovedCodexExecutable
    private let redactor: DeveloperSecretRedactor
    private let lock = NSLock()
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private var outputBuffer = Data()
    private var stderrBuffer = Data()
    private static let maximumStderrBytes = 64 * 1_024
    private var isStarted = false

    public init(
        configuration: CodexAppServerLaunchConfiguration,
        approvedExecutable: ApprovedCodexExecutable,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.configuration = configuration
        self.approvedExecutable = approvedExecutable
        self.redactor = redactor
        (stream, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    }

    deinit {
        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        continuation.finish()
    }

    public func start() async throws {
        try lock.withCodexLock {
            guard !isStarted else { return }
            process.executableURL = URL(fileURLWithPath: configuration.executablePath)
            process.arguments = configuration.arguments
            process.environment = configuration.environment
            process.standardInput = input
            process.standardOutput = output
            process.standardError = errorOutput
            // Keep this check immediately adjacent to Process.run(). Earlier
            // approval and version checks do not authorize a path swapped in
            // during the intervening async account/planning setup.
            let verified = try CodexAppServerRuntimeConfiguration.preflight(
                approvedExecutable: approvedExecutable
            )
            guard verified.resolvedPath == configuration.executablePath else {
                throw CodexAppServerRuntimeConfigurationError.approvedExecutableChanged
            }
            do {
                try process.run()
                isStarted = true
                // Pipe output is buffered between exec and handler
                // installation, which keeps verification adjacent to launch
                // without losing an immediate App Server response.
                output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    self?.consumeOutput(handle.availableData)
                }
                errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    self?.consumeStderr(handle.availableData)
                }
            } catch {
                output.fileHandleForReading.readabilityHandler = nil
                errorOutput.fileHandleForReading.readabilityHandler = nil
                throw CodexAppServerTransportError.processLaunchFailed
            }
        }
    }

    public func writeLine(_ data: Data) async throws {
        try lock.withCodexLock {
            try input.fileHandleForWriting.write(contentsOf: data)
        }
    }

    public func inboundLines() async -> AsyncThrowingStream<Data, Error> { stream }

    public func redactedStderr() async -> String {
        lock.withCodexLock { String(decoding: stderrBuffer, as: UTF8.self) }
    }

    public func stop() async {
        let pid: Int32? = lock.withCodexLock {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForWriting.close()
            guard process.isRunning else {
                isStarted = false
                return nil
            }
            process.terminate()
            isStarted = false
            return process.processIdentifier
        }
        guard let pid else {
            continuation.finish()
            return
        }
        try? await Task.sleep(nanoseconds: 250_000_000)
        if process.isRunning { Darwin.kill(pid, SIGKILL) }
        continuation.finish()
    }

    private func consumeOutput(_ data: Data) {
        guard !data.isEmpty else {
            continuation.finish()
            return
        }
        let lines: [Data] = lock.withCodexLock {
            outputBuffer.append(data)
            var completed: [Data] = []
            while let newline = outputBuffer.firstIndex(of: 0x0A) {
                completed.append(outputBuffer.prefix(upTo: newline))
                outputBuffer.removeSubrange(...newline)
            }
            return completed
        }
        for line in lines where !line.isEmpty { continuation.yield(line) }
    }

    private func consumeStderr(_ data: Data) {
        guard !data.isEmpty else { return }
        let text = redactor.redact(String(decoding: data, as: UTF8.self)).text
        lock.withCodexLock {
            stderrBuffer.append(contentsOf: text.utf8)
            if stderrBuffer.count > Self.maximumStderrBytes {
                stderrBuffer.removeFirst(stderrBuffer.count - Self.maximumStderrBytes)
            }
        }
    }
}
#endif

private struct WireRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int64
    let method: String
    let params: JSONValue?
}

private struct WireNotification: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: JSONValue?
}

private struct WireResponse: Encodable {
    let jsonrpc = "2.0"
    let id: Int64
    let result: JSONValue
}

private struct WireInbound: Decodable {
    struct RemoteError: Decodable {
        let code: Int
        let message: String
    }

    let id: Int64?
    let method: String?
    let params: JSONValue?
    let result: JSONValue?
    let error: RemoteError?
}

private extension NSLock {
    func withCodexLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
