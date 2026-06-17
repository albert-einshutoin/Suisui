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
