import Combine
import Foundation

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

public protocol LaunchAtLoginClient: Sendable {
    func status() -> LaunchAtLoginStatus
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus
}

public final class InMemoryLaunchAtLoginClient: LaunchAtLoginClient, @unchecked Sendable {
    private var isEnabled: Bool
    private let lock = NSLock()

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func status() -> LaunchAtLoginStatus {
        lock.lock()
        defer { lock.unlock() }
        return isEnabled ? .enabled : .disabled
    }

    public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        lock.lock()
        defer { lock.unlock() }
        isEnabled = enabled
        return isEnabled ? .enabled : .disabled
    }
}

@MainActor
public final class LaunchAtLoginSettingsViewModel: ObservableObject {
    @Published public private(set) var status: LaunchAtLoginStatus
    @Published public private(set) var errorMessage: String?

    private let client: any LaunchAtLoginClient

    public init(client: any LaunchAtLoginClient) {
        self.client = client
        self.status = client.status()
    }

    public var isEnabled: Bool {
        status == .enabled
    }

    public var canToggle: Bool {
        switch status {
        case .enabled, .disabled:
            true
        case .requiresApproval, .unavailable:
            false
        }
    }

    public var statusLabel: String {
        switch status {
        case .enabled:
            "On"
        case .disabled:
            "Off"
        case .requiresApproval:
            "Requires approval"
        case .unavailable:
            "Unavailable"
        }
    }

    public func refresh() {
        status = client.status()
    }

    public func setEnabled(_ enabled: Bool) {
        do {
            status = try client.setEnabled(enabled)
            errorMessage = nil
        } catch {
            status = client.status()
            errorMessage = error.localizedDescription
        }
    }
}
