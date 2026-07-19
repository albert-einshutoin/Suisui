import Foundation

public struct UnavailableLLMProvider: LLMProvider {
    private let provider: LLMProviderID
    private let reason: String

    public var providerID: String {
        provider.rawValue
    }

    public init(providerID: LLMProviderID, reason: String) {
        self.provider = providerID
        self.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        throw LLMProviderError.executionNotApproved(unavailableMessage)
    }

    private var unavailableMessage: String {
        let displayName = LLMProviderCatalog.entry(for: provider).displayName
        guard !reason.isEmpty else {
            return "\(displayName) is not available in this build."
        }
        if reason == LLMProviderCatalog.unavailableReason {
            return "\(displayName) is not available in this build."
        }
        return "\(displayName) is unavailable: \(reason)"
    }
}
