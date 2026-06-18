import Foundation
@testable import SoloPMCore

enum RecordingMCPServerProcessEvent: Equatable, Sendable {
    case started
    case healthChecked
    case shutdown
    case killed
}

final class RecordingMCPServerProcess: MCPServerProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [RecordingMCPServerProcessEvent] = []
    var nextHealthCheck = true

    var events: [RecordingMCPServerProcessEvent] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func start() async throws {
        record(.started)
    }

    func healthCheck() async -> Bool {
        record(.healthChecked)
        if !nextHealthCheck {
            await kill()
        }
        return nextHealthCheck
    }

    func shutdown() async {
        record(.shutdown)
    }

    func kill() async {
        record(.killed)
    }

    private func record(_ event: RecordingMCPServerProcessEvent) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }
}
