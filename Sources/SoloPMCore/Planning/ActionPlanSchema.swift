import Foundation

public enum ActionPlanSchemaError: Error, Equatable, Sendable {
    case resourceNotFound
    case invalidUTF8
}

public enum ActionPlanSchema: Sendable {
    public static let fileName = "action-plan.schema"
    public static let fileExtension = "json"
    public static let subdirectory = "Schemas"

    public static let fallbackPromptContract = """
    {
      "type": "object",
      "additionalProperties": false,
      "required": ["id", "userInput", "summary", "actions", "riskLevel", "requiresApproval"]
    }
    """

    public static func loadData() throws -> Data {
        try loadData(bundle: .module)
    }

    public static func loadData(bundle: Bundle) throws -> Data {
        let url = bundle.url(
            forResource: fileName,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) ?? bundle.url(
            forResource: fileName,
            withExtension: fileExtension
        )

        guard let url else {
            throw ActionPlanSchemaError.resourceNotFound
        }

        return try Data(contentsOf: url)
    }

    public static func loadString() throws -> String {
        try loadString(bundle: .module)
    }

    public static func loadString(bundle: Bundle) throws -> String {
        let data = try loadData(bundle: bundle)
        guard let schema = String(data: data, encoding: .utf8) else {
            throw ActionPlanSchemaError.invalidUTF8
        }

        return schema
    }
}
