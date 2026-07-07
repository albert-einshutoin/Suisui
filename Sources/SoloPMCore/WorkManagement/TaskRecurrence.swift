import Foundation

/// Supported completion-driven repeat cadences for local tasks.
public enum TaskRecurrence: String, CaseIterable, Codable, Equatable, Sendable {
    case daily
    case weekly
    case monthly

    /// Returns the next occurrence after the given due date, preserving the
    /// wall-clock time-of-day in the supplied calendar.
    public func nextDueDate(after dueAt: Date, calendar: Calendar) -> Date {
        let next: Date? = switch self {
        case .daily:
            calendar.date(byAdding: .day, value: 1, to: dueAt)
        case .weekly:
            calendar.date(byAdding: .day, value: 7, to: dueAt)
        case .monthly:
            calendar.date(byAdding: .month, value: 1, to: dueAt)
        }
        return next ?? dueAt
    }
}

/// Builds the follow-up task draft for a completed recurring task.
///
/// Regeneration is completion-driven: it only runs from explicit completion
/// entry points (SQLiteTaskStore.completeAndRegenerate). The LLM-facing
/// taskUpdate tool never calls this, so model-driven status edits do not
/// spawn new occurrences.
public enum TaskRecurrenceRegenerator {
    private static let advanceSafetyCap = 1_000

    /// Returns the draft for the next occurrence, or nil when the record has
    /// no parseable recurrence or due date.
    ///
    /// The next occurrence advances from the ORIGINAL due date repeatedly
    /// until it lands strictly in the future of `now`, so completing an
    /// overdue recurring task never spawns an already-overdue copy. The
    /// original time-of-day (or date-only formatting) is preserved.
    public static func regenerationDraft(
        for record: TaskRecord,
        completedAt now: Date,
        timeZoneIdentifier: String
    ) -> TaskCreateDraft? {
        guard let rawRecurrence = record.recurrence,
              let recurrence = TaskRecurrence(rawValue: rawRecurrence),
              let rawDueAt = record.dueAt,
              let dueAt = DeadlineDateParser.date(from: rawDueAt, timeZoneIdentifier: timeZoneIdentifier) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        var nextDueAt = recurrence.nextDueDate(after: dueAt, calendar: calendar)
        var advances = 1
        while nextDueAt <= now, advances < advanceSafetyCap {
            let advanced = recurrence.nextDueDate(after: nextDueAt, calendar: calendar)
            guard advanced > nextDueAt else {
                return nil
            }
            nextDueAt = advanced
            advances += 1
        }
        guard nextDueAt > now else {
            return nil
        }

        return TaskCreateDraft(
            title: record.title,
            projectID: record.projectID,
            dueAt: dueAtString(for: nextDueAt, matchingFormatOf: rawDueAt, timeZone: calendar.timeZone),
            priority: record.priority,
            sourceCommand: "recurrence",
            status: "open",
            detail: record.detail,
            recurrence: rawRecurrence
        )
    }

    private static func dueAtString(for date: Date, matchingFormatOf original: String, timeZone: TimeZone) -> String {
        // Date-only due dates (yyyy-MM-dd) fail the ISO 8601 parse and only
        // resolve through the time-zone-aware fallback; keep the regenerated
        // occurrence in the same date-only shape so board labels stay stable.
        guard DeadlineDateParser.date(from: original) == nil else {
            return DeadlineDateParser.string(from: date)
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
