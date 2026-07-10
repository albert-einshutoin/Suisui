import Foundation

/// Capture-only wall-clock context for reproducible visual evidence.
///
/// Normal launches do not set these narrowly scoped environment variables and
/// therefore continue to use the system date, locale, and calendar. Screenshot
/// capture sets the complete triplet so seeded relative dates and UI read
/// models cannot drift independently when a run crosses midnight or moves to a
/// host with different regional settings.
public struct VisualEvidenceRuntimeContext: Equatable, Sendable {
    public static let referenceInstantEnvironmentKey = "SOLOPM_VISUAL_EVIDENCE_REFERENCE_INSTANT"
    public static let timeZoneEnvironmentKey = "SOLOPM_VISUAL_EVIDENCE_TIME_ZONE"
    public static let localeEnvironmentKey = "SOLOPM_VISUAL_EVIDENCE_LOCALE_IDENTIFIER"

    public let referenceInstant: Date
    public let timeZoneIdentifier: String
    public let localeIdentifier: String

    public init?(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let rawReferenceInstant = environment[Self.referenceInstantEnvironmentKey],
              !rawReferenceInstant.isEmpty,
              let referenceInstant = ISO8601DateFormatter().date(from: rawReferenceInstant),
              let timeZoneIdentifier = environment[Self.timeZoneEnvironmentKey],
              !timeZoneIdentifier.isEmpty,
              TimeZone(identifier: timeZoneIdentifier) != nil,
              let localeIdentifier = environment[Self.localeEnvironmentKey],
              !localeIdentifier.isEmpty else {
            return nil
        }
        self.referenceInstant = referenceInstant
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localeIdentifier = localeIdentifier
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: localeIdentifier)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }

    public static func referenceDate(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        systemNow: () -> Date = Date.init
    ) -> Date {
        Self(environment: environment)?.referenceInstant ?? systemNow()
    }

    public static func runtimeCalendar(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        systemCalendar: () -> Calendar = { .current }
    ) -> Calendar {
        Self(environment: environment)?.calendar ?? systemCalendar()
    }
}
