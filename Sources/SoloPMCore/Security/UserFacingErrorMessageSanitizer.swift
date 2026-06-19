import Foundation

public enum UserFacingErrorMessageSanitizer {
    public static func message(
        from error: Error,
        fallback: String = "Operation failed."
    ) -> String {
        message(from: rawMessage(from: error), fallback: fallback)
    }

    public static func message(
        from text: String,
        fallback: String = "Operation failed."
    ) -> String {
        let redacted = DeveloperSecretRedactor()
            .redact(text)
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return redacted.isEmpty ? fallback : redacted
    }

    private static func rawMessage(from error: Error) -> String {
        let nsError = error as NSError
        if nsError.userInfo[NSLocalizedDescriptionKey] != nil {
            return error.localizedDescription
        }

        if let localizedError = error as? LocalizedError,
           let errorDescription = localizedError.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !errorDescription.isEmpty {
            return errorDescription
        }

        let description = String(describing: error).trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            return description
        }

        return error.localizedDescription
    }
}
