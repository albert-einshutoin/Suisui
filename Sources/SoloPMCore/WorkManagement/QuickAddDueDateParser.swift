import Foundation

public struct QuickAddParseResult: Equatable, Sendable {
    public var title: String
    public var dueAt: Date?
    public var matchedPhrase: String?

    public init(title: String, dueAt: Date? = nil, matchedPhrase: String? = nil) {
        self.title = title
        self.dueAt = dueAt
        self.matchedPhrase = matchedPhrase
    }
}

/// Extracts a due date from natural-language quick-add input in English and
/// Japanese ("明日15時 レポート提出", "ship notes fri 3pm") and returns the
/// title with the date phrase removed. Parsing is deterministic and
/// vocabulary-based so behavior is stable across OS versions and testable.
public enum QuickAddDueDateParser {
    /// Hour used when the input names a day without a time.
    public static let defaultDayHour = 18
    /// Hour used for "tonight" / 「今晩」 when no explicit time is given.
    public static let eveningHour = 20

    public static func parse(
        _ input: String,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> QuickAddParseResult {
        let text = input as NSString
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dayMatch = firstDayMatch(in: text)
        let timeMatch = firstTimeMatch(in: text, excluding: dayMatch?.range)

        guard dayMatch != nil || timeMatch != nil else {
            return QuickAddParseResult(title: input.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let matchedRanges = [dayMatch?.range, timeMatch?.range].compactMap { $0 }
        let title = removingRanges(matchedRanges, from: text)
        guard !title.isEmpty else {
            // The whole input was a date phrase; a task still needs a title,
            // so treat the input as a plain title instead.
            return QuickAddParseResult(title: input.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let dueAt = composeDate(
            day: dayMatch?.day,
            time: timeMatch?.time,
            now: now,
            calendar: calendar
        )
        let matchedPhrase = matchedRanges
            .sorted { $0.location < $1.location }
            .map { text.substring(with: $0).trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")

        return QuickAddParseResult(title: title, dueAt: dueAt, matchedPhrase: matchedPhrase)
    }

    // MARK: - Day phrases

    private struct DayMatch {
        var range: NSRange
        var day: DayResolution
    }

    private enum DayResolution {
        case offset(Int)
        case offsetEvening(Int)
        case upcomingWeekday(Int)
        case nextWeekWeekday(Int)
    }

    private struct DayPattern: @unchecked Sendable {
        var regex: NSRegularExpression
        var resolve: @Sendable (NSTextCheckingResult, NSString) -> DayResolution
    }

    private static let japaneseWeekdays: [Character: Int] = [
        "日": 1, "月": 2, "火": 3, "水": 4, "木": 5, "金": 6, "土": 7
    ]

    private static let englishWeekdays: [String: Int] = [
        "sunday": 1, "sun": 1,
        "monday": 2, "mon": 2,
        "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5,
        "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7
    ]

    private static let dayPatterns: [DayPattern] = {
        func pattern(_ source: String, _ resolve: @escaping @Sendable (NSTextCheckingResult, NSString) -> DayResolution) -> DayPattern {
            DayPattern(
                regex: try! NSRegularExpression(pattern: source, options: [.caseInsensitive]),
                resolve: resolve
            )
        }

        let weekdayAlternation = englishWeekdays.keys.sorted { $0.count > $1.count }.joined(separator: "|")

        return [
            pattern("明後日") { _, _ in .offset(2) },
            pattern("明日") { _, _ in .offset(1) },
            pattern("今日|本日") { _, _ in .offset(0) },
            pattern("今晩|今夜") { _, _ in .offsetEvening(0) },
            pattern("来週([月火水木金土日])曜(?:日)?") { match, text in
                let symbol = text.substring(with: match.range(at: 1)).first
                return .nextWeekWeekday(symbol.flatMap { japaneseWeekdays[$0] } ?? 2)
            },
            pattern("来週") { _, _ in .nextWeekWeekday(2) },
            pattern("([月火水木金土日])曜(?:日)?") { match, text in
                let symbol = text.substring(with: match.range(at: 1)).first
                return .upcomingWeekday(symbol.flatMap { japaneseWeekdays[$0] } ?? 2)
            },
            pattern("(\\d{1,3})日後") { match, text in
                .offset(Int(text.substring(with: match.range(at: 1))) ?? 0)
            },
            pattern("\\btonight\\b") { _, _ in .offsetEvening(0) },
            pattern("\\btomorrow\\b") { _, _ in .offset(1) },
            pattern("\\btoday\\b") { _, _ in .offset(0) },
            pattern("\\bnext\\s+(\(weekdayAlternation))\\b") { match, text in
                .nextWeekWeekday(englishWeekdays[text.substring(with: match.range(at: 1)).lowercased()] ?? 2)
            },
            pattern("\\bnext\\s+week\\b") { _, _ in .nextWeekWeekday(2) },
            pattern("\\b(\(weekdayAlternation))\\b") { match, text in
                .upcomingWeekday(englishWeekdays[text.substring(with: match.range(at: 1)).lowercased()] ?? 2)
            },
            pattern("\\bin\\s+(\\d{1,3})\\s+days?\\b") { match, text in
                .offset(Int(text.substring(with: match.range(at: 1))) ?? 0)
            }
        ]
    }()

    private static func firstDayMatch(in text: NSString) -> DayMatch? {
        var best: (match: DayMatch, location: Int)?
        for pattern in dayPatterns {
            let range = NSRange(location: 0, length: text.length)
            guard let match = pattern.regex.firstMatch(in: text as String, range: range) else {
                continue
            }
            if best == nil || match.range.location < best!.location {
                best = (DayMatch(range: match.range, day: pattern.resolve(match, text)), match.range.location)
            }
        }
        return best?.match
    }

    // MARK: - Time phrases

    private struct TimeMatch {
        var range: NSRange
        var time: (hour: Int, minute: Int)
    }

    private static let japaneseTimeRegex = try! NSRegularExpression(
        pattern: "(午前|午後)?(\\d{1,2})時(?:(\\d{1,2})分|(半))?"
    )
    private static let clockTimeRegex = try! NSRegularExpression(
        pattern: "(?:\\bat\\s+)?\\b(\\d{1,2}):(\\d{2})\\s*(am|pm)?\\b",
        options: [.caseInsensitive]
    )
    private static let meridiemTimeRegex = try! NSRegularExpression(
        pattern: "(?:\\bat\\s+)?\\b(\\d{1,2})\\s*(am|pm)\\b",
        options: [.caseInsensitive]
    )

    private static func firstTimeMatch(in text: NSString, excluding dayRange: NSRange?) -> TimeMatch? {
        let fullRange = NSRange(location: 0, length: text.length)
        var best: TimeMatch?

        func consider(_ match: NSTextCheckingResult, hour: Int, minute: Int) {
            if let dayRange, NSIntersectionRange(dayRange, match.range).length > 0 {
                return
            }
            guard (0...23).contains(hour), (0...59).contains(minute) else {
                return
            }
            if best == nil || match.range.location < best!.range.location {
                best = TimeMatch(range: match.range, time: (hour, minute))
            }
        }

        for match in japaneseTimeRegex.matches(in: text as String, range: fullRange) {
            guard var hour = Int(text.substring(with: match.range(at: 2))) else {
                continue
            }
            if match.range(at: 1).location != NSNotFound,
               text.substring(with: match.range(at: 1)) == "午後",
               hour < 12 {
                hour += 12
            }
            var minute = 0
            if match.range(at: 3).location != NSNotFound {
                minute = Int(text.substring(with: match.range(at: 3))) ?? 0
            } else if match.range(at: 4).location != NSNotFound {
                minute = 30
            }
            consider(match, hour: hour, minute: minute)
        }

        for match in clockTimeRegex.matches(in: text as String, range: fullRange) {
            guard var hour = Int(text.substring(with: match.range(at: 1))),
                  let minute = Int(text.substring(with: match.range(at: 2))) else {
                continue
            }
            if match.range(at: 3).location != NSNotFound {
                let meridiem = text.substring(with: match.range(at: 3)).lowercased()
                if meridiem == "pm", hour < 12 {
                    hour += 12
                } else if meridiem == "am", hour == 12 {
                    hour = 0
                }
            }
            consider(match, hour: hour, minute: minute)
        }

        for match in meridiemTimeRegex.matches(in: text as String, range: fullRange) {
            guard var hour = Int(text.substring(with: match.range(at: 1))) else {
                continue
            }
            let meridiem = text.substring(with: match.range(at: 2)).lowercased()
            if meridiem == "pm", hour < 12 {
                hour += 12
            } else if meridiem == "am", hour == 12 {
                hour = 0
            }
            consider(match, hour: hour, minute: 0)
        }

        return best
    }

    // MARK: - Composition

    private static func composeDate(
        day: DayResolution?,
        time: (hour: Int, minute: Int)?,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let todayStart = calendar.startOfDay(for: now)

        func dayStart(forOffset offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: todayStart) ?? todayStart
        }

        func upcoming(_ weekday: Int) -> Date {
            let current = calendar.component(.weekday, from: todayStart)
            let offset = (weekday - current + 7) % 7
            return dayStart(forOffset: offset)
        }

        func nextWeek(_ weekday: Int) -> Date {
            // Anchor on next week's Monday, then advance to the requested day
            // within that week (Sunday lands at the end of next week).
            let current = calendar.component(.weekday, from: todayStart)
            let daysUntilNextMonday = ((2 - current + 7) % 7 == 0) ? 7 : (2 - current + 7) % 7
            let nextMonday = dayStart(forOffset: daysUntilNextMonday)
            let offsetFromMonday = (weekday - 2 + 7) % 7
            return calendar.date(byAdding: .day, value: offsetFromMonday, to: nextMonday) ?? nextMonday
        }

        var defaultHour = defaultDayHour
        let base: Date
        switch day {
        case .offset(let offset):
            base = dayStart(forOffset: offset)
        case .offsetEvening(let offset):
            base = dayStart(forOffset: offset)
            defaultHour = eveningHour
        case .upcomingWeekday(let weekday):
            base = upcoming(weekday)
        case .nextWeekWeekday(let weekday):
            base = nextWeek(weekday)
        case nil:
            base = todayStart
        }

        let hour = time?.hour ?? defaultHour
        let minute = time?.minute ?? 0
        guard var composed = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) else {
            return nil
        }

        // A bare time ("15時に" already passed) rolls to tomorrow; an explicit
        // day is kept even if it is already in the past.
        if day == nil, composed <= now {
            composed = calendar.date(byAdding: .day, value: 1, to: composed) ?? composed
        }
        return composed
    }

    // MARK: - Title cleanup

    private static func removingRanges(_ ranges: [NSRange], from text: NSString) -> String {
        var result = text as String
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            guard let swiftRange = Range(range, in: result) else {
                continue
            }
            result.removeSubrange(swiftRange)
        }
        return result
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "、,:："))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
