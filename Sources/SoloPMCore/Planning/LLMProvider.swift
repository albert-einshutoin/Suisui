import Foundation

public protocol LLMProvider: Sendable {
    var providerID: String { get }

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse
}

public enum LLMProviderError: Error, Equatable, Sendable {
    case authenticationFailed
    case rateLimited
    case network(String)
    case invalidResponse(String)
    case executionNotApproved(String)
    case unknown(String)

    public var userMessage: String {
        switch self {
        case .authenticationFailed:
            "The AI provider rejected the configured API key."
        case .rateLimited:
            "The AI provider rate limit was reached. Try again later or switch providers."
        case .network(let message):
            "The AI provider request failed due to a network problem: \(message)"
        case .invalidResponse(let message):
            "The AI provider returned an invalid planning response: \(message)"
        case .executionNotApproved(let message):
            "The AI provider cannot run until local execution is approved: \(message)"
        case .unknown(let message):
            "The AI provider failed unexpectedly: \(message)"
        }
    }
}

enum LLMHTTPErrorMessageExtractor {
    private static let maxPreviewCharacters = 240

    static func message(from data: Data) -> String? {
        if let decodedMessage = decodedErrorMessage(from: data) {
            return decodedMessage
        }

        return redactedBodyPreview(from: data)
    }

    private static func decodedErrorMessage(from data: Data) -> String? {
        guard let errorBody = try? JSONDecoder().decode(ProviderErrorResponseBody.self, from: data) else {
            return nil
        }

        let message = errorBody.error.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return nil
        }
        return DeveloperSecretRedactor().redact(message).text
    }

    private static func redactedBodyPreview(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        guard let rawBody = String(data: data, encoding: .utf8) else {
            return "Non-UTF-8 error body (\(data.count) bytes)."
        }

        let collapsedBody = rawBody
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedBody.isEmpty else {
            return nil
        }

        let redacted = DeveloperSecretRedactor().redact(collapsedBody).text
        let suffix = redacted.count > maxPreviewCharacters ? "..." : ""
        let preview = String(redacted.prefix(maxPreviewCharacters))
        return "Unexpected error body: \(preview)\(suffix)"
    }
}

private struct ProviderErrorResponseBody: Decodable {
    var error: ProviderErrorBody
}

private struct ProviderErrorBody: Decodable {
    var message: String
}
