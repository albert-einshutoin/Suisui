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

/// A safe failure category for presentation. Provider diagnostics are never
/// retained in a snapshot because SwiftUI inspection can reflect its values.
public enum TodayIntegrationFailureCategory: Equatable, Sendable {
    case permissionNeeded
    case unavailable
}

/// Read-only state exposed to Today UI. Unlike `TodayIntegrationState`, this
/// value intentionally has no provider error payload.
public enum TodayIntegrationPresentationState: Equatable, Sendable {
    case notConnected
    case permissionPending
    case connected
    case syncing
    case synced(lastSyncedAt: Date?, itemCount: Int)
    case failed(lastSyncedAt: Date?, itemCount: Int, category: TodayIntegrationFailureCategory)
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
    public let state: TodayIntegrationPresentationState
    public let title: String
    public let detail: String
    public let accessibilityLabel: String

    public init(
        service: TodayIntegrationService,
        state: TodayIntegrationPresentationState,
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
        let presentationState = presentationState(from: state)
        let detail: String
        switch presentationState {
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
        case let .failed(lastSyncedAt, itemCount, category):
            let failure = failureDetail(category: category, locale: locale)
            let context = syncDetail(lastSyncedAt: lastSyncedAt, itemCount: itemCount, now: now, calendar: calendar, locale: locale)
            detail = "\(failure) \(context)"
        }
        let accessibilityLabel = String(format: localized("%@: %@.", locale: locale), title, detail)
        return TodayIntegrationSnapshot(
            service: service,
            state: presentationState,
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

    private static func presentationState(from state: TodayIntegrationState) -> TodayIntegrationPresentationState {
        switch state {
        case .notConnected:
            .notConnected
        case .permissionPending:
            .permissionPending
        case .connected:
            .connected
        case .syncing:
            .syncing
        case let .synced(lastSyncedAt, itemCount):
            .synced(lastSyncedAt: lastSyncedAt, itemCount: itemCount)
        case let .failed(lastSyncedAt, itemCount, message):
            .failed(
                lastSyncedAt: lastSyncedAt,
                itemCount: itemCount,
                category: failureCategory(message: message)
            )
        }
    }

    private static func failureCategory(message: String) -> TodayIntegrationFailureCategory {
        let normalized = message.lowercased()
        if normalized.contains("permission")
            || normalized.contains("denied")
            || normalized.contains("scope")
            || normalized.contains("oauth") {
            return .permissionNeeded
        }
        // Provider error bodies can contain tokens, account IDs, or URLs. Today
        // exposes only a stable category, then discards the diagnostic payload.
        return .unavailable
    }

    private static func failureDetail(category: TodayIntegrationFailureCategory, locale: Locale) -> String {
        switch category {
        case .permissionNeeded:
            localized("Permission needed", locale: locale)
        case .unavailable:
            localized("Sync failed.", locale: locale)
        }
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        let language = locale.identifier.hasPrefix("ja") ? "ja" : "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale)
    }
}
