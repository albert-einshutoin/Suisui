import Foundation

public enum ActionPlanSchemaError: Error, Equatable, Sendable {
    case resourceNotFound
    case invalidUTF8
}

public enum ActionPlanSchema: Sendable {
    public static let fileName = "action-plan.schema"
    public static let fileExtension = "json"
    public static let subdirectory = "Schemas"

    public static func loadData() throws -> Data {
        try loadData(
            primary: { try loadData(bundle: .main) },
            module: {
#if SWIFT_PACKAGE
                try loadData(bundle: .module)
#else
                throw ActionPlanSchemaError.resourceNotFound
#endif
            }
        )
    }

    static func loadData(primary: () throws -> Data, module: () throws -> Data) throws -> Data {
        do {
            return try primary()
        } catch ActionPlanSchemaError.resourceNotFound {
            return try module()
        } catch {
            throw error
        }
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
        let data = try loadData()
        guard let schema = String(data: data, encoding: .utf8) else {
            throw ActionPlanSchemaError.invalidUTF8
        }

        return schema
    }

    public static func loadString(bundle: Bundle) throws -> String {
        let data = try loadData(bundle: bundle)
        guard let schema = String(data: data, encoding: .utf8) else {
            throw ActionPlanSchemaError.invalidUTF8
        }

        return schema
    }

}
