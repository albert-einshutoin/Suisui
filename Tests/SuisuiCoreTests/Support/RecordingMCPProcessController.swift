import Foundation
@testable import SuisuiCore

struct MCPProcessKillRequest: Equatable, Sendable {
    var serverID: String
    var reason: MCPProcessKillReason
}

final class RecordingMCPProcessController: MCPProcessController, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [MCPProcessKillRequest] = []

    var killRequests: [MCPProcessKillRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    func kill(serverID: String, reason: MCPProcessKillReason) async {
        record(MCPProcessKillRequest(serverID: serverID, reason: reason))
    }

    private func record(_ request: MCPProcessKillRequest) {
        lock.lock()
        defer { lock.unlock() }
        requests.append(request)
    }
}
