import Foundation

public struct ActionPlanResponseParser: Sendable {
    private let validator: ActionPlanValidator
    private let schemaValidator: ActionPlanJSONSchemaValidator

    public init(
        validator: ActionPlanValidator = ActionPlanValidator(),
        schemaValidator: ActionPlanJSONSchemaValidator = ActionPlanJSONSchemaValidator()
    ) {
        self.validator = validator
        self.schemaValidator = schemaValidator
    }

    public func parse(
        rawContent: String,
        providerID: String,
        model: ExecutionReceiptModel? = nil,
        usage: ExecutionReceiptUsage = .unknown
    ) -> PlanningResponse {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return invalidResponse(
                providerID: providerID,
                rawContent: rawContent,
                model: model,
                usage: usage,
                message: "Response is not UTF-8."
            )
        }

        let schemaIssues = schemaValidator.validate(jsonData: data)
        guard schemaIssues.isEmpty else {
            return invalidResponse(
                providerID: providerID,
                rawContent: rawContent,
                model: model,
                usage: usage,
                issues: schemaIssues
            )
        }

        do {
            let plan = try JSONDecoder().decode(ActionPlan.self, from: data)
            return PlanningResponse(
                providerID: providerID,
                rawContent: rawContent,
                actionPlan: plan,
                validationResult: validator.validate(plan),
                model: model,
                usage: usage
            )
        } catch {
            return invalidResponse(
                providerID: providerID,
                rawContent: rawContent,
                model: model,
                usage: usage,
                message: error.localizedDescription
            )
        }
    }

    private func invalidResponse(
        providerID: String,
        rawContent: String,
        model: ExecutionReceiptModel?,
        usage: ExecutionReceiptUsage,
        message: String
    ) -> PlanningResponse {
        invalidResponse(
            providerID: providerID,
            rawContent: rawContent,
            model: model,
            usage: usage,
            issues: [
                .blocking(path: "$", message: "ActionPlan response could not be parsed: \(message)")
            ]
        )
    }

    private func invalidResponse(
        providerID: String,
        rawContent: String,
        model: ExecutionReceiptModel?,
        usage: ExecutionReceiptUsage,
        issues: [ActionPlanValidationIssue]
    ) -> PlanningResponse {
        PlanningResponse(
            providerID: providerID,
            rawContent: rawContent,
            actionPlan: nil,
            validationResult: ActionPlanValidationResult(issues: issues),
            model: model,
            usage: usage
        )
    }
}
