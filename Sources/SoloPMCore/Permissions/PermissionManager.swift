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

