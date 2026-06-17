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
        case .unknown(let message):
            "The AI provider failed unexpectedly: \(message)"
        }
    }
}
