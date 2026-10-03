import Foundation

/// Canonical redacted failure messages for local board and menu capture.
public enum LocalWorkspaceFailureMessage {
    public static func message(for error: Error) -> String {
        message(for: error, fallback: String(localized: "Project board unavailable"))
    }

    public static func message(for error: Error, fallback: String) -> String {
        if let storeError = error as? ProjectBoardStoreError {
            switch storeError {
            case .emptyTitle: return String(localized: "Task title is required.")
            case .emptyProjectTitle: return String(localized: "Project title is required.")
            case .archivedProjectCannotAcceptTasks: return String(localized: "Restore the project before adding tasks.")
            default: break
            }
        }
        if let databaseError = error as? DatabaseError {
            let message: String
            switch databaseError {
            case .openFailed(let detail), .executeFailed(let detail),
                 .prepareFailed(let detail), .stepFailed(let detail),
                 .missingColumn(let detail):
                message = detail
            case .busyTimeout(let operation):
                message = "The local database stayed busy during \(operation). Try again."
            case .duplicateColumnName(let column):
                message = "The local database query returned duplicate column \(column)."
            case .invalidColumnValue(let column, let value):
                message = "\(column) contains invalid value \(value)."
            case .nestedTransaction:
                message = "A nested local database transaction was rejected."
            }
            return UserFacingErrorMessageSanitizer.message(from: message, fallback: fallback)
        }
        guard let decodingError = error as? LocalStoreDecodingError else {
            return UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: fallback
            )
        }

        return repairGuidance(for: decodingError)
    }

    private static func repairGuidance(for error: LocalStoreDecodingError) -> String {
        let action = "Restore from backup or repair the local database, then reopen Suisui."
        switch error {
        case .invalidStringArray(let column):
            return "Local board data needs repair: \(column) contains invalid list JSON. \(action)"
        case .invalidDoubleArray(let column):
            return "Local board data needs repair: \(column) contains invalid numeric vector JSON. \(action)"
        case .invalidStringMap(let column):
            return "Local board data needs repair: \(column) contains invalid key-value JSON. \(action)"
        case .inconsistentDimensions(let column, let expected, let actual):
            return "Local board data needs repair: \(column) has \(actual) values, expected \(expected). \(action)"
        case .missingRequiredColumn(let column):
            return "Local board data needs repair: \(column) is missing. \(action)"
        case .invalidInt64(let column, let value):
            return "Local board data needs repair: \(column) contains invalid integer value \(quotedDisplayValue(value)). \(action)"
        case .invalidEnum(let column, let value):
            return "Local board data needs repair: \(column) contains unsupported value \(quotedDisplayValue(value)). \(action)"
        case .invalidDate(let column, let value):
            return "Local board data needs repair: \(column) contains invalid date value \(quotedDisplayValue(value)). \(action)"
        }
    }

    private static func quotedDisplayValue(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let maxVisibleCharacters = 80
        guard normalized.count > maxVisibleCharacters else {
            return "\"\(normalized)\""
        }
        return "\"\(String(normalized.prefix(maxVisibleCharacters)))...\""
    }

}
