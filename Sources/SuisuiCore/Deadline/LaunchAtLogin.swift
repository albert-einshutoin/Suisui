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

    public var statusDetail: String? {
        switch status {
        case .enabled, .disabled:
            nil
        case .requiresApproval:
            "macOS requires approval in System Settings before Suisui can launch at login."
        case .unavailable:
            "Launch at Login is unavailable for this app bundle. Use a signed app installed in Applications for release verification."
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
            errorMessage = UserFacingErrorMessageSanitizer.message(from: error)
        }
    }
}
