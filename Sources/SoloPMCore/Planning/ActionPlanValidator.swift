import Foundation

public struct ActionPlanValidator: Sendable {
    private let schemaValidator: ActionPlanJSONSchemaValidator

    public init(schemaValidator: ActionPlanJSONSchemaValidator = ActionPlanJSONSchemaValidator()) {
        self.schemaValidator = schemaValidator
    }

    public func validate(_ plan: ActionPlan) -> ActionPlanValidationResult {
        var issues: [ActionPlanValidationIssue] = []

        if plan.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.blocking(path: "id", message: "ActionPlan id is required."))
        }

        if plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.blocking(path: "summary", message: "ActionPlan summary is required."))
        }

        if plan.actions.isEmpty {
            issues.append(.blocking(path: "actions", message: "ActionPlan must contain at least one action."))
        }

        let highestActionRisk = plan.actions.map(\.riskLevel).max() ?? .read
        if plan.riskLevel < highestActionRisk {
            issues.append(
                .blocking(
                    path: "riskLevel",
                    message: "ActionPlan riskLevel cannot be lower than its highest-risk action."
                )
            )
        }

        let containsWriteAction = plan.actions.contains { $0.riskLevel >= .write }
        if containsWriteAction && !plan.requiresApproval {
            issues.append(
                .blocking(
                    path: "requiresApproval",
                    message: "Write actions require explicit user approval."
                )
            )
        }

        for (index, action) in plan.actions.enumerated() {
            issues.append(contentsOf: validate(action, index: index))
        }

        return ActionPlanValidationResult(issues: issues)
    }

    public func validate(jsonData: Data) -> ActionPlanValidationResult {
        let schemaIssues = schemaValidator.validate(jsonData: jsonData)
        if !schemaIssues.isEmpty {
            return ActionPlanValidationResult(issues: schemaIssues)
        }

        do {
            let plan = try JSONDecoder().decode(ActionPlan.self, from: jsonData)
            return validate(plan)
        } catch {
            return ActionPlanValidationResult(
                issues: [
                    .blocking(path: "$", message: "ActionPlan JSON could not be decoded: \(error.localizedDescription)")
                ]
            )
        }
    }

    private func validate(_ action: PlanAction, index: Int) -> [ActionPlanValidationIssue] {
        let path = "actions[\(index)]"
        var issues: [ActionPlanValidationIssue] = []

        if action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.blocking(path: "\(path).id", message: "Action id is required."))
        }

        if action.riskLevel < action.tool.defaultRiskLevel {
            issues.append(
                .blocking(
                    path: "\(path).riskLevel",
                    message: "Action riskLevel cannot be lower than the tool default risk."
                )
            )
        }

        if action.riskLevel == .danger {
            issues.append(
                .blocking(
                    path: "\(path).riskLevel",
                    message: "Dangerous actions are not allowed in the MVP."
                )
            )
        }

        if action.requiresUserConfirmation {
            issues.append(
                .warning(
                    path: "\(path).requiresUserConfirmation",
                    message: "Action contains ambiguous information and must be confirmed by the user."
                )
            )
        }

        return issues
    }
}

public struct ActionPlanValidationResult: Equatable, Sendable {
    public var issues: [ActionPlanValidationIssue]

    public init(issues: [ActionPlanValidationIssue]) {
        self.issues = issues
    }

    public var isValid: Bool {
        !issues.contains { $0.severity == .blocking }
    }

    public var requiresUserConfirmation: Bool {
        issues.contains { $0.severity == .warning }
    }
}

public struct ActionPlanValidationIssue: Equatable, Sendable {
    public var severity: ActionPlanValidationSeverity
    public var path: String
    public var message: String

    public init(severity: ActionPlanValidationSeverity, path: String, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }

    public static func blocking(path: String, message: String) -> ActionPlanValidationIssue {
        ActionPlanValidationIssue(severity: .blocking, path: path, message: message)
    }

    public static func warning(path: String, message: String) -> ActionPlanValidationIssue {
        ActionPlanValidationIssue(severity: .warning, path: path, message: message)
    }
}

public enum ActionPlanValidationSeverity: String, Equatable, Sendable {
    case warning
    case blocking
}
