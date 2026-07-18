import Foundation

/// Editable due-date state for structured task forms.
///
/// Natural-language parsing intentionally belongs to Quick Add. An inspector
/// must never reinterpret an existing persisted value and silently overwrite it.
public enum TaskDueDateFieldState: Equatable, Sendable {
    case empty
    case value(Date)

    public var persistedDate: Date? {
        switch self {
        case .empty:
            return nil
        case .value(let date):
            return date
        }
    }

    /// Parses the complete persisted due-date contract used by deadline queries.
    /// Keeping this in Core prevents an editor from rejecting values that the
    /// rest of the product already treats as valid dates.
    public static func parsePersisted(
        _ value: String?,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> (state: TaskDueDateFieldState, isInvalid: Bool) {
        guard let value, !value.isEmpty else { return (.empty, false) }
        guard let date = DeadlineDateParser.date(from: value, timeZoneIdentifier: timeZoneIdentifier) else {
            return (.empty, true)
        }
        return (.value(date), false)
    }
}
