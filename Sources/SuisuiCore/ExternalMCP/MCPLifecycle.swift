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
