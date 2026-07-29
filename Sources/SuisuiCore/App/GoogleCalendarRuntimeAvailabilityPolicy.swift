import Foundation

package enum GoogleCalendarRuntimeBuildPolicy: String, Equatable, Sendable {
    case publicAlpha = "public-alpha"
    case development
}

package enum GoogleCalendarRuntimeAvailabilityPolicy {
    package static func isEnabled(
        buildPolicy: GoogleCalendarRuntimeBuildPolicy,
        environmentOptIn: Bool
    ) -> Bool {
        // Public Alpha intentionally excludes the live Google Calendar surface.
        // Requiring both a development-built bundle and an explicit launch
        // opt-in prevents a user from enabling OAuth or writes on a distributed
        // Public Alpha bundle merely by changing its process environment.
        buildPolicy == .development && environmentOptIn
    }
}
