import Foundation

/// User-configurable quiet-hours window during which notifications are
/// deferred (never dropped) to the first instant after the window ends.
public struct NotificationQuietHoursSettings: Codable, Equatable, Sendable {
    public static let defaultStartMinuteOfDay = 22 * 60
    public static let defaultEndMinuteOfDay = 8 * 60
    public static let minutesPerDay = 24 * 60

    public var enabled: Bool
    /// Window start as minutes since local midnight (22:00 by default).
    public var startMinuteOfDay: Int
    /// Window end as minutes since local midnight (08:00 by default).
    public var endMinuteOfDay: Int

    private enum CodingKeys: String, CodingKey {
        case enabled
        case startMinuteOfDay
        case endMinuteOfDay
    }

    public init(
        enabled: Bool = false,
        startMinuteOfDay: Int = NotificationQuietHoursSettings.defaultStartMinuteOfDay,
        endMinuteOfDay: Int = NotificationQuietHoursSettings.defaultEndMinuteOfDay
    ) {
        self.enabled = enabled
        self.startMinuteOfDay = startMinuteOfDay
        self.endMinuteOfDay = endMinuteOfDay
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Settings persisted before quiet hours existed have none of these
        // keys; decoding must fall back to the disabled default window.
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        self.startMinuteOfDay = try container.decodeIfPresent(Int.self, forKey: .startMinuteOfDay)
            ?? Self.defaultStartMinuteOfDay
        self.endMinuteOfDay = try container.decodeIfPresent(Int.self, forKey: .endMinuteOfDay)
            ?? Self.defaultEndMinuteOfDay
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(startMinuteOfDay, forKey: .startMinuteOfDay)
        try container.encode(endMinuteOfDay, forKey: .endMinuteOfDay)
    }

    public static let `default` = NotificationQuietHoursSettings()

    /// Clamp persisted or crafted minute values into a single day so the
    /// deferral math never has to reason about out-of-range windows.
    public var normalized: NotificationQuietHoursSettings {
        var copy = self
        copy.startMinuteOfDay = min(max(copy.startMinuteOfDay, 0), Self.minutesPerDay - 1)
        copy.endMinuteOfDay = min(max(copy.endMinuteOfDay, 0), Self.minutesPerDay - 1)
        return copy
    }

    /// A degenerate start == end window has no interior and is treated as
    /// disabled instead of swallowing the whole day.
    public var isWindowActive: Bool {
        let normalized = self.normalized
        return normalized.enabled && normalized.startMinuteOfDay != normalized.endMinuteOfDay
    }
}

/// Pure quiet-hours deferral. The window is half-open `[start, end)`: an
/// instant exactly at the start is deferred, an instant exactly at the end
/// (or later) is delivered unchanged.
public enum NotificationQuietHours {
    public static func deferredFireDate(
        for date: Date,
        settings: NotificationQuietHoursSettings,
        timeZone: TimeZone = .current
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return deferredFireDate(for: date, settings: settings, calendar: calendar)
    }

    public static func deferredFireDate(
        for date: Date,
        settings: NotificationQuietHoursSettings,
        calendar: Calendar
    ) -> Date {
        guard settings.isWindowActive else {
            return date
        }
        let normalized = settings.normalized
        let start = normalized.startMinuteOfDay
        let end = normalized.endMinuteOfDay

        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        let isInsideWindow: Bool
        if start < end {
            // Same-day window, e.g. 13:00-15:00.
            isInsideWindow = minuteOfDay >= start && minuteOfDay < end
        } else {
            // Overnight window crossing midnight, e.g. 22:00-08:00.
            isInsideWindow = minuteOfDay >= start || minuteOfDay < end
        }
        guard isInsideWindow else {
            return date
        }

        guard let sameDayEnd = calendar.date(
            bySettingHour: end / 60,
            minute: end % 60,
            second: 0,
            of: date
        ) else {
            return date
        }
        if sameDayEnd > date {
            return sameDayEnd
        }
        // Evening side of an overnight window: the window ends tomorrow.
        return calendar.date(byAdding: .day, value: 1, to: sameDayEnd) ?? sameDayEnd
    }
}

/// How far ahead of the due instant a deadline task reminder should fire.
public enum DeadlineReminderLeadTime: String, Codable, CaseIterable, Equatable, Sendable {
    case atDue
    case thirtyMinutesBefore
    case oneHourBefore
    case oneDayBefore

    public var interval: TimeInterval {
        switch self {
        case .atDue:
            0
        case .thirtyMinutesBefore:
            30 * 60
        case .oneHourBefore:
            60 * 60
        case .oneDayBefore:
            24 * 60 * 60
        }
    }

    public var label: String {
        switch self {
        case .atDue:
            "At due time"
        case .thirtyMinutesBefore:
            "30 minutes before"
        case .oneHourBefore:
            "1 hour before"
        case .oneDayBefore:
            "1 day before"
        }
    }
}

/// Notification delivery preferences persisted alongside the existing
/// `AppSettings.notificationsEnabled` flag. Follows the
/// `TaskAutoExecutionSettings` persistence pattern: absent keys decode to
/// backward-compatible defaults so settings saved before this struct existed
/// keep loading.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    public var quietHours: NotificationQuietHoursSettings
    public var deadlineReminderLeadTime: DeadlineReminderLeadTime
    /// Reschedule suggestions for missed tasks skip Saturday/Sunday targets
    /// and land on the following Monday when enabled.
    public var avoidsWeekends: Bool

    private enum CodingKeys: String, CodingKey {
        case quietHours
        case deadlineReminderLeadTime
        case avoidsWeekends
    }

    public init(
        quietHours: NotificationQuietHoursSettings = .default,
        deadlineReminderLeadTime: DeadlineReminderLeadTime = .atDue,
        avoidsWeekends: Bool = true
    ) {
        self.quietHours = quietHours
        self.deadlineReminderLeadTime = deadlineReminderLeadTime
        self.avoidsWeekends = avoidsWeekends
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.quietHours = try container.decodeIfPresent(
            NotificationQuietHoursSettings.self,
            forKey: .quietHours
        ) ?? .default
        self.deadlineReminderLeadTime = try container.decodeIfPresent(
            DeadlineReminderLeadTime.self,
            forKey: .deadlineReminderLeadTime
        ) ?? .atDue
        self.avoidsWeekends = try container.decodeIfPresent(Bool.self, forKey: .avoidsWeekends) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quietHours, forKey: .quietHours)
        try container.encode(deadlineReminderLeadTime, forKey: .deadlineReminderLeadTime)
        try container.encode(avoidsWeekends, forKey: .avoidsWeekends)
    }

    public static let `default` = NotificationPreferences()
}

/// Single choke point where notification fire dates are finalized before any
/// `NotificationClient.schedule` call. Deadline task reminders shift earlier
/// by the configured lead time and then pass through quiet-hours deferral;
/// fixed-time notifications (morning digest, weekly review, overdue alerts,
/// snooze follow-ups) pass through quiet-hours deferral only, so they are
/// deferred but never dropped.
public enum NotificationSchedulingPolicy {
    public enum FireDateKind: Equatable, Sendable {
        /// Reminder scheduled ahead of a due date: lead time + quiet hours.
        case preDeadlineReminder
        /// Fixed-time notification: quiet hours only.
        case fixedTime
    }

    public static func finalFireDate(
        proposed: Date,
        kind: FireDateKind,
        preferences: NotificationPreferences,
        timeZone: TimeZone
    ) -> Date {
        var fireDate = proposed
        if kind == .preDeadlineReminder {
            fireDate = fireDate.addingTimeInterval(-preferences.deadlineReminderLeadTime.interval)
        }
        return NotificationQuietHours.deferredFireDate(
            for: fireDate,
            settings: preferences.quietHours,
            timeZone: timeZone
        )
    }
}
