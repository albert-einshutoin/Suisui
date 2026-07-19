import ServiceManagement
import SuisuiCore

public final class SMAppServiceLaunchAtLoginClient: LaunchAtLoginClient, @unchecked Sendable {
    public init() {}

    public func status() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            .enabled
        case .notRegistered:
            .disabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        return status()
    }
}
