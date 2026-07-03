import Darwin
import Foundation

#if os(iOS) || targetEnvironment(macCatalyst)
public final class MCPStdioTransport: MCPClientTransport, MCPServerProcess, MCPProcessController, @unchecked Sendable {
    private let registration: MCPServerRegistration

    public init(
        registration: MCPServerRegistration,
        resolvedEnvironment: [String: String] = [:],
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.registration = registration
    }

    public var redactedStderr: String {
        ""
    }

    public func start() async throws {
        // Stdio MCP launches local processes, which mobile platforms cannot do;
        // iOS uses Hosted MCP / Cloud Relay pending actions instead.
        throw MCPClientError.transportFailed(
            serverID: registration.id,
            method: "initialize",
            message: "MCP stdio transport is available only on macOS."
        )
    }

    public func healthCheck() async -> Bool {
        false
    }

    public func shutdown() async {}

    public func kill() async {}

    public func kill(serverID: String, reason: MCPProcessKillReason) async {}

    public func send(_ request: MCPJSONRPCRequest, timeout: TimeInterval) async throws -> MCPJSONRPCResponse {
        throw MCPClientError.transportFailed(
            serverID: registration.id,
            method: request.method,
            message: "MCP stdio transport is available only on macOS."
        )
    }

    public func notify(_ notification: MCPJSONRPCNotification) async throws {
        throw MCPClientError.transportFailed(
            serverID: registration.id,
            method: notification.method,
            message: "MCP stdio transport is available only on macOS."
        )
    }
}
#else
public final class MCPStdioTransport: MCPClientTransport, MCPServerProcess, MCPProcessController, @unchecked Sendable {
    private let registration: MCPServerRegistration
    private let resolvedEnvironment: [String: String]
    private let redactor: DeveloperSecretRedactor
    private let lock = NSLock()
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var isStarted = false
    private var stderrBuffer = ""

    public init(
        registration: MCPServerRegistration,
        resolvedEnvironment: [String: String] = [:],
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.registration = registration
        self.resolvedEnvironment = resolvedEnvironment
        self.redactor = redactor
    }

    deinit {
        shutdownSync()
    }

    public var redactedStderr: String {
        lock.withLock {
            stderrBuffer
        }
    }

    public func start() async throws {
        try startSync()
    }

    public func healthCheck() async -> Bool {
        healthCheckSync()
    }

    public func shutdown() async {
        shutdownSync()
    }

    public func kill() async {
        killSync()
    }

    public func kill(serverID: String, reason: MCPProcessKillReason) async {
        guard serverID == registration.id else {
            return
        }
        killSync()
    }

    public func send(_ request: MCPJSONRPCRequest, timeout: TimeInterval) async throws -> MCPJSONRPCResponse {
        try await start()
        let data = try encoder.encode(request) + Data([0x0A])
        return try lock.withLock {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
            let line = try readLine(timeout: timeout, method: request.method)
            do {
                return try decoder.decode(MCPJSONRPCResponse.self, from: line)
            } catch {
                throw MCPClientError.invalidResponse(
                    serverID: registration.id,
                    method: request.method,
                    reason: "Malformed JSON-RPC response."
                )
            }
        }
    }

    public func notify(_ notification: MCPJSONRPCNotification) async throws {
        try await start()
        let data = try encoder.encode(notification) + Data([0x0A])
        try lock.withLock {
            try stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }
    }

    private func readLine(timeout: TimeInterval, method: String) throws -> Data {
        let descriptor = stdoutPipe.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(timeout)
        var bytes: [UInt8] = []

        while Date() < deadline {
            var readSet = fd_set()
            fdSet(descriptor, set: &readSet)
            var interval = timeval(from: max(0, deadline.timeIntervalSinceNow))
            let ready = Darwin.select(descriptor + 1, &readSet, nil, nil, &interval)
            if ready == 0 {
                throw MCPClientError.timeout(serverID: registration.id, method: method)
            }
            if ready < 0 {
                throw MCPClientError.transportFailed(serverID: registration.id, method: method, message: "select failed.")
            }

            var byte = UInt8(0)
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 0 {
                throw MCPClientError.transportFailed(serverID: registration.id, method: method, message: "stdio stream closed.")
            }
            if count < 0 {
                throw MCPClientError.transportFailed(serverID: registration.id, method: method, message: "read failed.")
            }
            if byte == 0x0A {
                return Data(bytes)
            }
            bytes.append(byte)
        }

        throw MCPClientError.timeout(serverID: registration.id, method: method)
    }

    private func appendStderr(_ text: String) {
        let redacted = redactor.redact(text).text
        lock.withLock {
            stderrBuffer.append(redacted)
        }
    }

    private func startSync() throws {
        try lock.withLock {
            guard !isStarted else {
                return
            }

            let trimmedCommand = registration.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCommand.contains("/") {
                process.executableURL = URL(fileURLWithPath: trimmedCommand)
                process.arguments = registration.arguments
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = [trimmedCommand] + registration.arguments
            }
            if let workingDirectory = registration.workingDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            }
            process.environment = ProcessInfo.processInfo.environment.merging(resolvedEnvironment) { _, new in new }
            process.standardInput = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                    return
                }
                self?.appendStderr(text)
            }

            try process.run()
            isStarted = true
        }
    }

    private func healthCheckSync() -> Bool {
        lock.withLock {
            process.isRunning
        }
    }

    private func shutdownSync() {
        lock.withLock {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            guard isStarted else {
                return
            }
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
            isStarted = false
        }
    }

    private func killSync() {
        let processIdentifier = lock.withLock {
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            guard process.isRunning else {
                isStarted = false
                return nil as Int32?
            }
            isStarted = false
            return process.processIdentifier
        }
        guard let processIdentifier else {
            return
        }
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/bin/kill")
        killer.arguments = ["-9", "\(processIdentifier)"]
        try? killer.run()
        killer.waitUntilExit()
    }

    private func fdSet(_ fd: Int32, set: inout fd_set) {
        let intOffset = Int(fd / 32)
        let bitOffset = Int(fd % 32)
        let mask = Int32(bitPattern: UInt32(1) << UInt32(bitOffset))
        switch intOffset {
        case 0:
            set.fds_bits.0 |= mask
        case 1:
            set.fds_bits.1 |= mask
        case 2:
            set.fds_bits.2 |= mask
        case 3:
            set.fds_bits.3 |= mask
        case 4:
            set.fds_bits.4 |= mask
        case 5:
            set.fds_bits.5 |= mask
        case 6:
            set.fds_bits.6 |= mask
        case 7:
            set.fds_bits.7 |= mask
        case 8:
            set.fds_bits.8 |= mask
        case 9:
            set.fds_bits.9 |= mask
        case 10:
            set.fds_bits.10 |= mask
        case 11:
            set.fds_bits.11 |= mask
        case 12:
            set.fds_bits.12 |= mask
        case 13:
            set.fds_bits.13 |= mask
        case 14:
            set.fds_bits.14 |= mask
        case 15:
            set.fds_bits.15 |= mask
        case 16:
            set.fds_bits.16 |= mask
        case 17:
            set.fds_bits.17 |= mask
        case 18:
            set.fds_bits.18 |= mask
        case 19:
            set.fds_bits.19 |= mask
        case 20:
            set.fds_bits.20 |= mask
        case 21:
            set.fds_bits.21 |= mask
        case 22:
            set.fds_bits.22 |= mask
        case 23:
            set.fds_bits.23 |= mask
        case 24:
            set.fds_bits.24 |= mask
        case 25:
            set.fds_bits.25 |= mask
        case 26:
            set.fds_bits.26 |= mask
        case 27:
            set.fds_bits.27 |= mask
        case 28:
            set.fds_bits.28 |= mask
        case 29:
            set.fds_bits.29 |= mask
        case 30:
            set.fds_bits.30 |= mask
        case 31:
            set.fds_bits.31 |= mask
        default:
            break
        }
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

private extension timeval {
    init(from interval: TimeInterval) {
        let seconds = max(0, interval)
        let wholeSeconds = Int(seconds)
        self.init(tv_sec: wholeSeconds, tv_usec: Int32((seconds - Double(wholeSeconds)) * 1_000_000))
    }
}
#endif
