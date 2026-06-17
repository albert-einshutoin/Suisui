import Foundation

public struct ActionPlanJSONSchemaValidator: Sendable {
    private let allowedRootKeys: Set<String> = [
        "id",
        "userInput",
        "summary",
        "actions",
        "riskLevel",
        "requiresApproval"
    ]
    private let requiredRootKeys: Set<String> = [
        "id",
        "userInput",
        "summary",
        "actions",
        "riskLevel",
        "requiresApproval"
    ]
    private let allowedActionKeys: Set<String> = [
        "id",
        "tool",
        "arguments",
        "riskLevel",
        "requiresUserConfirmation"
    ]

    public init() {}

    public func validate(jsonData: Data) -> [ActionPlanValidationIssue] {
        do {
            let object = try JSONSerialization.jsonObject(with: jsonData)
            guard let root = object as? [String: Any] else {
                return [.blocking(path: "$", message: "ActionPlan JSON must be an object.")]
            }

            return validate(root: root)
        } catch {
            return [
                .blocking(path: "$", message: "ActionPlan JSON could not be parsed: \(error.localizedDescription)")
            ]
        }
    }

    private func validate(root: [String: Any]) -> [ActionPlanValidationIssue] {
        var issues: [ActionPlanValidationIssue] = []

        issues.append(contentsOf: validateKeys(
            actual: Set(root.keys),
            allowed: allowedRootKeys,
            required: requiredRootKeys,
            path: "$"
        ))

        issues.append(contentsOf: validateNonEmptyString(root["id"], path: "id"))
        issues.append(contentsOf: validateNonEmptyString(root["summary"], path: "summary"))
        issues.append(contentsOf: validateString(root["userInput"], path: "userInput"))
        issues.append(contentsOf: validateRiskLevel(root["riskLevel"], path: "riskLevel"))

        if root["requiresApproval"] != nil, !(root["requiresApproval"] is Bool) {
            issues.append(.blocking(path: "requiresApproval", message: "requiresApproval must be a boolean."))
        }

        guard let actions = root["actions"] as? [[String: Any]] else {
            if root["actions"] != nil {
                issues.append(.blocking(path: "actions", message: "actions must be an array of objects."))
            }
            return issues
        }

        if actions.isEmpty {
            issues.append(.blocking(path: "actions", message: "actions must contain at least one action."))
        }

        for (index, action) in actions.enumerated() {
            issues.append(contentsOf: validate(action: action, index: index))
        }

        return issues
    }

    private func validate(action: [String: Any], index: Int) -> [ActionPlanValidationIssue] {
        let path = "actions[\(index)]"
        var issues: [ActionPlanValidationIssue] = []

        issues.append(contentsOf: validateKeys(
            actual: Set(action.keys),
            allowed: allowedActionKeys,
            required: ["id", "tool"],
            path: path
        ))

        issues.append(contentsOf: validateNonEmptyString(action["id"], path: "\(path).id"))
        issues.append(contentsOf: validateTool(action["tool"], path: "\(path).tool"))

        if let riskLevel = action["riskLevel"] {
            issues.append(contentsOf: validateRiskLevel(riskLevel, path: "\(path).riskLevel"))
        }

        if let requiresUserConfirmation = action["requiresUserConfirmation"],
           !(requiresUserConfirmation is Bool) {
            issues.append(.blocking(
                path: "\(path).requiresUserConfirmation",
                message: "requiresUserConfirmation must be a boolean."
            ))
        }

        if let arguments = action["arguments"], !(arguments is [String: Any]) {
            issues.append(.blocking(path: "\(path).arguments", message: "arguments must be an object."))
        }

        return issues
    }

    private func validateKeys(
        actual: Set<String>,
        allowed: Set<String>,
        required: Set<String>,
        path: String
    ) -> [ActionPlanValidationIssue] {
        var issues: [ActionPlanValidationIssue] = []

        for key in required.subtracting(actual).sorted() {
            issues.append(.blocking(path: path, message: "Missing required property '\(key)'."))
        }

        for key in actual.subtracting(allowed).sorted() {
            issues.append(.blocking(path: path == "$" ? key : "\(path).\(key)", message: "Unknown property '\(key)'."))
        }

        return issues
    }

    private func validateNonEmptyString(_ value: Any?, path: String) -> [ActionPlanValidationIssue] {
        guard let value else {
            return []
        }

        guard let string = value as? String else {
            return [.blocking(path: path, message: "\(path) must be a string.")]
        }

        if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.blocking(path: path, message: "\(path) must not be blank.")]
        }

        return []
    }

    private func validateString(_ value: Any?, path: String) -> [ActionPlanValidationIssue] {
        guard let value, !(value is String) else {
            return []
        }

        return [.blocking(path: path, message: "\(path) must be a string.")]
    }

    private func validateRiskLevel(_ value: Any?, path: String) -> [ActionPlanValidationIssue] {
        guard let value else {
            return []
        }

        guard let riskLevel = value as? String, RiskLevel(rawValue: riskLevel) != nil else {
            return [.blocking(path: path, message: "\(path) must be a supported risk level.")]
        }

        return []
    }

    private func validateTool(_ value: Any?, path: String) -> [ActionPlanValidationIssue] {
        guard let value else {
            return []
        }

        guard let tool = value as? String, ActionTool(rawValue: tool) != nil else {
            return [.blocking(path: path, message: "\(path) must be a supported tool.")]
        }

        return []
    }
}
