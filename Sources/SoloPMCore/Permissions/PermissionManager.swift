import Foundation

public enum AppPermission: String, CaseIterable, Equatable, Hashable, Sendable {
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

public struct StaticPermissionManager: PermissionManager {
    private var currentSnapshot: PermissionSnapshot

    public init(snapshot: PermissionSnapshot = .empty) {
        self.currentSnapshot = snapshot
    }

    public func snapshot() -> PermissionSnapshot {
        currentSnapshot
    }

    public func status(for permission: AppPermission) -> PermissionStatus {
        currentSnapshot.status(for: permission)
    }
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
}
