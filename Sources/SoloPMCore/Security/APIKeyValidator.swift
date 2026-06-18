import Foundation

public enum APIKeyValidationError: Error, Equatable, Sendable {
    case empty
    case containsWhitespace
}

public enum APIKeyValidator {
    public static func normalize(_ value: String?) throws -> String {
        guard let value else {
            throw APIKeyValidationError.empty
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIKeyValidationError.empty
        }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw APIKeyValidationError.containsWhitespace
        }

        return trimmed
    }

    public static func isValid(_ value: String) -> Bool {
        do {
            _ = try normalize(value)
            return true
        } catch {
            return false
        }
    }
}
