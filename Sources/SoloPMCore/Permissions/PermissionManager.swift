import Foundation

public enum AppPermission: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case calendar
    case reminders
    case notifications
    case fileAccess
    case microphone
}

public enum PermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

public struct PermissionSnapshot: Equatable, Sendable {
    private var statuses: [AppPermission: PermissionStatus]

    public init(statuses: [AppPermission: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    public static let empty = PermissionSnapshot()

    public func status(for permission: AppPermission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    public mutating func setStatus(_ status: PermissionStatus, for permission: AppPermission) {
        statuses[permission] = status
    }
}

public protocol PermissionManager: Sendable {
    func snapshot() -> PermissionSnapshot
    func status(for permission: AppPermission) -> PermissionStatus
}

public enum PermissionDisplayPolicy {
    public static func label(for status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            "Not requested"
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }

    public static func isActionDisabled(for status: PermissionStatus) -> Bool {
        status == .denied || status == .restricted
    }

    public static func integrationStatusLabel(for status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            "Not configured"
        case .granted:
            "Connected"
        case .denied:
            "Permission denied"
        case .restricted:
            "Restricted"
        }
    }
}
