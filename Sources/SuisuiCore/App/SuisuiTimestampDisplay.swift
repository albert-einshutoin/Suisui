import Foundation

/// The single place that turns a stored timestamp string into text a person can
/// read.
///
/// Suisui persists timestamps as ISO8601 (`2026-07-10T09:00:00Z`) or as a plain
/// day (`2026-07-10`) for API and database compatibility. Before this type
/// existed, each surface re-derived its own display: the kanban card printed the
/// stored string verbatim, Today printed a localized relative label, Done
/// printed the raw UTC instant, and Schedule used a hardcoded `"E d"` pattern
/// that ignores the user's locale. The same moment therefore rendered three
/// different ways in one app. Every surface must route through this type so
/// that cannot happen again.
public enum SuisuiTimestampDisplay {
    public struct Parsed: Equatable, Sendable {
        public var date: Date
        /// `false` for day-only values such as `2026-07-10`, so callers do not
        /// invent a midnight time the user never entered.
        public var includesTime: Bool

        public init(date: Date, includesTime: Bool) {
            self.date = date
            self.includesTime = includesTime
        }
    }

    public static func parse(
        _ rawValue: String,
        calendar: Calendar = .current
    ) -> Parsed? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let date = FormatterCache.shared.iso8601.date(from: trimmed) {
            return Parsed(date: date, includesTime: trimmed.contains("T"))
        }
        if let date = FormatterCache.shared.iso8601WithFractionalSeconds.date(from: trimmed) {
            return Parsed(date: date, includesTime: true)
        }
        if let date = FormatterCache.shared.dayOnly(timeZone: calendar.timeZone).date(from: trimmed) {
            return Parsed(date: date, includesTime: false)
        }
        return nil
    }

    /// `Jul 10` / `Jul 10, 09:00` — locale-aware, and never a raw ISO string.
    /// Unparseable input is returned unchanged so a malformed stored value is
    /// visible to the user rather than silently blanked.
    public static func absolute(
        _ rawValue: String,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let parsed = parse(rawValue, calendar: calendar) else {
            return rawValue
        }
        return absolute(parsed, calendar: calendar, locale: locale)
    }

    public static func absolute(
        _ parsed: Parsed,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(
            parsed.date,
            template: parsed.includesTime ? "yMMMd HH:mm" : "yMMMd",
            calendar: calendar,
            locale: locale
        )
    }

    public static func absolute(
        _ date: Date,
        includesTime: Bool = false,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(
            date,
            template: includesTime ? "yMMMd HH:mm" : "yMMMd",
            calendar: calendar,
            locale: locale
        )
    }

    /// `Jul 10` / `Jul 10, 09:00` without the year, for dense rows where the
    /// year is implied by surrounding context.
    public static func compact(
        _ rawValue: String,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let parsed = parse(rawValue, calendar: calendar) else {
            return rawValue
        }
        return formatted(
            parsed.date,
            template: parsed.includesTime ? "MMMd HH:mm" : "MMMd",
            calendar: calendar,
            locale: locale
        )
    }

    /// The label task rows and cards show for a due date: `Jul 10` in the
    /// reference year, `Jul 10, 2027` outside it. Dropping the year everywhere
    /// makes a task due two years out look imminent; keeping it everywhere
    /// wastes the narrowest column in the app.
    public static func dayLabel(
        _ rawValue: String,
        relativeTo referenceDate: Date = VisualEvidenceRuntimeContext.referenceDate(),
        calendar: Calendar = VisualEvidenceRuntimeContext.runtimeCalendar(),
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        guard let parsed = parse(rawValue, calendar: calendar) else {
            return rawValue
        }
        let isReferenceYear = calendar.component(.year, from: parsed.date)
            == calendar.component(.year, from: referenceDate)
        let template: String
        switch (isReferenceYear, parsed.includesTime) {
        case (true, false): template = "MMMd"
        case (true, true): template = "MMMd HH:mm"
        case (false, false): template = "yMMMd"
        case (false, true): template = "yMMMd HH:mm"
        }
        return formatted(parsed.date, template: template, calendar: calendar, locale: locale)
    }

    /// Weekday plus day-of-month, e.g. `Fri 10` / `金 10`. Replaces the
    /// hardcoded `"E d"` pattern, which produced English-ordered output in
    /// every locale.
    public static func weekdayAndDay(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(date, template: "Ed", calendar: calendar, locale: locale)
    }

    public static func time(
        _ date: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(date, template: "HH:mm", calendar: calendar, locale: locale)
    }

    /// Stable machine key (`yyyy-MM-dd`) for grouping and persistence. Always
    /// POSIX so a locale change cannot alter stored identity.
    public static func dayKey(
        _ date: Date,
        calendar: Calendar = .current
    ) -> String {
        FormatterCache.shared.dayOnly(timeZone: calendar.timeZone).string(from: date)
    }

    public static func formatted(
        _ date: Date,
        template: String,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        FormatterCache.shared.localized(
            template: template,
            calendar: calendar,
            locale: locale
        ).string(from: date)
    }
}

/// `DateFormatter` is expensive to build and is not `Sendable`, but the view
/// layer formats one per row on every redraw. The cache keeps a single instance
/// per (template, locale, time zone) behind a lock instead.
private final class FormatterCache: @unchecked Sendable {
    static let shared = FormatterCache()

    private let lock = NSLock()
    private var localizedFormatters: [String: DateFormatter] = [:]
    private var dayOnlyFormatters: [String: DateFormatter] = [:]

    let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func localized(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(calendar.timeZone.identifier)|\(calendar.identifier)"
        return lock.withLock {
            if let cached = localizedFormatters[key] {
                return cached
            }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            localizedFormatters[key] = formatter
            return formatter
        }
    }

    func dayOnly(timeZone: TimeZone) -> DateFormatter {
        lock.withLock {
            if let cached = dayOnlyFormatters[timeZone.identifier] {
                return cached
            }
            let formatter = DateFormatter()
            var parsingCalendar = Calendar(identifier: .gregorian)
            parsingCalendar.timeZone = timeZone
            formatter.calendar = parsingCalendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            dayOnlyFormatters[timeZone.identifier] = formatter
            return formatter
        }
    }
}
