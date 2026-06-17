import Foundation

public struct ActionPlanResponseParser: Sendable {
    private let validator: ActionPlanValidator

    public init(validator: ActionPlanValidator = ActionPlanValidator()) {
        self.validator = validator
    }

    public func parse(rawContent: String, providerID: String) -> PlanningResponse {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return invalidResponse(providerID: providerID, rawContent: rawContent, message: "Response is not UTF-8.")
        }

        do {
            let plan = try JSONDecoder().decode(ActionPlan.self, from: data)
            return PlanningResponse(
                providerID: providerID,
                rawContent: rawContent,
                actionPlan: plan,
                validationResult: validator.validate(plan)
            )
        } catch {
            return invalidResponse(
                providerID: providerID,
                rawContent: rawContent,
                message: error.localizedDescription
            )
        }
    }

    private func invalidResponse(providerID: String, rawContent: String, message: String) -> PlanningResponse {
        PlanningResponse(
            providerID: providerID,
            rawContent: rawContent,
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(
                issues: [
                    .blocking(path: "$", message: "ActionPlan response could not be parsed: \(message)")
                ]
            )
        )
    }
}
