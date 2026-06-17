import Foundation

public enum MCPServerProcessState: Equatable, Sendable {
    case notStarted
    case running
    case crashed
    case stopped
}

public protocol MCPServerProcess: Sendable {
    func start() async throws
    func healthCheck() async -> Bool
    func shutdown() async
    func kill() async
}

public struct MCPProcessLifecycleManager: Sendable {
    public let serverID: String
    private let process: any MCPServerProcess

    public init(serverID: String, process: any MCPServerProcess) {
        self.serverID = serverID
        self.process = process
    }

    public func start() async throws {
        try await process.start()
    }

    public func healthCheck() async -> MCPServerProcessState {
        await process.healthCheck() ? .running : .crashed
    }

    public func shutdown() async {
        await process.shutdown()
    }

    public func killHungProcess() async {
        await process.kill()
    }
}

public enum RecordingMCPServerProcessEvent: Equatable, Sendable {
    case started
    case healthChecked
    case shutdown
    case killed
}

public final class RecordingMCPServerProcess: MCPServerProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [RecordingMCPServerProcessEvent] = []
    public var nextHealthCheck = true

    public init() {}

    public var events: [RecordingMCPServerProcessEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    public func start() async throws {
        record(.started)
    }

    public func healthCheck() async -> Bool {
        record(.healthChecked)
        if !nextHealthCheck {
            await kill()
        }
        return nextHealthCheck
    }

    public func shutdown() async {
        record(.shutdown)
    }

    public func kill() async {
        record(.killed)
    }

    private func record(_ event: RecordingMCPServerProcessEvent) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }
}
