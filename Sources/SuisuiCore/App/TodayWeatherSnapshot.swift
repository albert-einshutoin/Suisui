import Foundation

/// UI-ready weather input. Acquisition stays outside Today so an unavailable
/// provider or network never blocks the dashboard's local-first rendering.
public enum TodayWeatherState: Equatable, Sendable {
    case notConfigured
    case permissionPending
    case loading
    case available(temperatureCelsius: Int, location: String, updatedAt: Date)
    case failed
}

public struct TodayWeatherSnapshot: Equatable, Sendable {
    public let state: TodayWeatherState
    public let title: String
    public let detail: String
    public let accessibilityLabel: String

    public init(state: TodayWeatherState, title: String, detail: String, accessibilityLabel: String) {
        self.state = state
        self.title = title
        self.detail = detail
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum TodayWeatherSnapshotBuilder {
    public static func make(
        state: TodayWeatherState,
        now: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> TodayWeatherSnapshot {
        switch state {
        case .notConfigured:
            return unavailable(state, title: "Weather unavailable", detail: "Weather is unavailable right now.", locale: locale)
        case .permissionPending:
            return unavailable(state, title: "Weather needs permission", detail: "Allow location access to show weather.", locale: locale)
        case .loading:
            return unavailable(state, title: "Loading weather", detail: "Checking the latest conditions.", locale: locale)
        case .failed:
            // Do not surface provider failures: they can contain endpoint or account details.
            return unavailable(state, title: "Weather unavailable", detail: "Weather could not be loaded.", locale: locale)
        case let .available(temperatureCelsius, location, updatedAt):
            let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
            let temperature = String(format: "%d°C", temperatureCelsius)
            let separator = locale.identifier.hasPrefix("ja") ? "・" : " · "
            let title = place.isEmpty ? temperature : "\(place)\(separator)\(temperature)"
            let updateTime = calendar.isDate(updatedAt, inSameDayAs: now)
                ? SuisuiTimestampDisplay.time(updatedAt, calendar: calendar, locale: locale)
                : SuisuiTimestampDisplay.formatted(updatedAt, template: "MMMd HH:mm", calendar: calendar, locale: locale)
            let detail = localized("Updated %@", updateTime, locale: locale)
            let accessibilityLabel = place.isEmpty
                ? localized("Weather: %@. %@.", temperature, detail, locale: locale)
                : localized("Weather: %@, %@. %@.", place, temperature, detail, locale: locale)
            return TodayWeatherSnapshot(state: state, title: title, detail: detail, accessibilityLabel: accessibilityLabel)
        }
    }

    private static func unavailable(
        _ state: TodayWeatherState,
        title: String,
        detail: String,
        locale: Locale
    ) -> TodayWeatherSnapshot {
        let title = localized(title, locale: locale)
        let detail = localized(detail, locale: locale)
        return TodayWeatherSnapshot(
            state: state,
            title: title,
            detail: detail,
            accessibilityLabel: localized("Weather: %@. %@", title, detail, locale: locale)
        )
    }

    private static func localized(_ key: String, _ arguments: CVarArg..., locale: Locale) -> String {
        let language = locale.identifier.hasPrefix("ja") ? "ja" : "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return String(format: String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale), arguments: arguments)
    }
}
