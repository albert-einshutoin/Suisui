import Foundation

public enum TodayIntegrationService: Equatable, Sendable {
    case calendar
    case slack
}

/// Read-only integration state injected by the runtime. Today never contacts a
/// provider from this model, so rendering remains safe when connectors are off.
public enum TodayIntegrationState: Equatable, Sendable {
    case notConnected
    case permissionPending
    case connected
    case syncing
    case synced(lastSyncedAt: Date?, itemCount: Int)
    case failed(lastSyncedAt: Date?, itemCount: Int, message: String)

    public static func calendar(from status: GoogleCalendarRuntimeSyncStatus) -> TodayIntegrationState {
        switch status.state {
        case .ready:
            .connected
        case .oauthDisconnected, .missingRequiredScope, .tokenExpiredWithoutRefresh:
            .permissionPending
        case .failed(let message):
            .failed(lastSyncedAt: nil, itemCount: 0, message: message)
        case .upgradeRequired, .calendarNotConfigured, .invalidCalendarID, .runtimeNotConfigured:
            .notConnected
        }
    }
}

public struct TodayIntegrationStates: Equatable, Sendable {
    public let calendar: TodayIntegrationState
    public let slack: TodayIntegrationState

    public init(calendar: TodayIntegrationState = .notConnected, slack: TodayIntegrationState = .notConnected) {
        self.calendar = calendar
        self.slack = slack
    }

    public static let notConfigured = TodayIntegrationStates()
}

public struct TodayIntegrationSnapshot: Equatable, Sendable {
    public let service: TodayIntegrationService
    public let state: TodayIntegrationState
    public let title: String
    public let detail: String
    public let accessibilityLabel: String

    public init(
        service: TodayIntegrationService,
        state: TodayIntegrationState,
        title: String,
        detail: String,
        accessibilityLabel: String
    ) {
        self.service = service
        self.state = state
        self.title = title
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct TodayIntegrationsSnapshot: Equatable, Sendable {
    public let calendar: TodayIntegrationSnapshot
    public let slack: TodayIntegrationSnapshot

    public init(calendar: TodayIntegrationSnapshot, slack: TodayIntegrationSnapshot) {
        self.calendar = calendar
        self.slack = slack
    }

    public static let notConfigured = TodayIntegrationsSnapshot(
        calendar: TodayIntegrationSnapshot(
            service: .calendar,
            state: .notConnected,
            title: "Calendar",
            detail: "Not connected",
            accessibilityLabel: "Calendar: Not connected."
        ),
        slack: TodayIntegrationSnapshot(
            service: .slack,
            state: .notConnected,
            title: "Slack",
            detail: "Not connected",
            accessibilityLabel: "Slack: Not connected."
        )
    )
}

public enum TodayIntegrationSnapshotBuilder {
    public static func make(
        service: TodayIntegrationService,
        state: TodayIntegrationState,
        now: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> TodayIntegrationSnapshot {
        let title = localized(service == .calendar ? "Calendar" : "Slack", locale: locale)
        let detail: String
        switch state {
        case .notConnected:
            detail = localized("Not connected", locale: locale)
        case .permissionPending:
            detail = localized("Permission needed", locale: locale)
        case .connected:
            detail = localized("Connected", locale: locale)
        case .syncing:
            detail = localized("Syncing", locale: locale)
        case let .synced(lastSyncedAt, itemCount):
            detail = syncDetail(lastSyncedAt: lastSyncedAt, itemCount: itemCount, now: now, calendar: calendar, locale: locale)
        case let .failed(lastSyncedAt, itemCount, message):
            let failure = failureDetail(message: message, locale: locale)
            let context = syncDetail(lastSyncedAt: lastSyncedAt, itemCount: itemCount, now: now, calendar: calendar, locale: locale)
            detail = "\(failure) \(context)"
        }
        let accessibilityLabel = String(format: localized("%@: %@.", locale: locale), title, detail)
        return TodayIntegrationSnapshot(
            service: service,
            state: state,
            title: title,
            detail: detail,
            accessibilityLabel: accessibilityLabel
        )
    }

    public static func make(
        states: TodayIntegrationStates,
        now: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> TodayIntegrationsSnapshot {
        TodayIntegrationsSnapshot(
            calendar: make(service: .calendar, state: states.calendar, now: now, calendar: calendar, locale: locale),
            slack: make(service: .slack, state: states.slack, now: now, calendar: calendar, locale: locale)
        )
    }

    private static func syncDetail(
        lastSyncedAt: Date?,
        itemCount: Int,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let count = max(0, itemCount)
        let items = String(format: localized(count == 1 ? "%d item synced" : "%d items synced", locale: locale), count)
        guard let lastSyncedAt else { return items }
        let time = calendar.isDate(lastSyncedAt, inSameDayAs: now)
            ? SuisuiTimestampDisplay.time(lastSyncedAt, calendar: calendar, locale: locale)
            : SuisuiTimestampDisplay.formatted(lastSyncedAt, template: "MMMd HH:mm", calendar: calendar, locale: locale)
        return String(format: localized("Last synced %@. %@", locale: locale), time, items)
    }

    private static func failureDetail(message: String, locale: Locale) -> String {
        let normalized = message.lowercased()
        if normalized.contains("permission")
            || normalized.contains("denied")
            || normalized.contains("scope")
            || normalized.contains("oauth") {
            return localized("Permission needed", locale: locale)
        }
        // Provider error bodies can contain tokens, account IDs, or URLs. Today
        // exposes only a stable category; detailed diagnostics stay outside UI.
        return localized("Sync failed.", locale: locale)
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        let language = locale.identifier.hasPrefix("ja") ? "ja" : "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale)
    }
}
