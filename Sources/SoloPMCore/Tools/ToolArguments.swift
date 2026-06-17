import Foundation

public struct ToolArguments: Sendable {
    public var raw: [String: JSONValue]
    public var tool: ActionTool

    public init(_ raw: [String: JSONValue], tool: ActionTool) {
        self.raw = raw
        self.tool = tool
    }

    public func requiredString(_ key: String) throws -> String {
        guard let value = optionalString(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        return value
    }

    public func optionalString(_ key: String) -> String? {
        guard case .string(let value)? = raw[key] else {
            return nil
        }

        return value
    }

    public func requiredInt64(_ key: String) throws -> Int64 {
        guard let value = optionalInt64(key) else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        return value
    }

    public func optionalInt64(_ key: String) -> Int64? {
        switch raw[key] {
        case .number(let value):
            Int64(value)
        case .string(let value):
            Int64(value)
        default:
            nil
        }
    }

    public func stringArray(_ key: String) -> [String] {
        optionalStringArray(key) ?? []
    }

    public func optionalStringArray(_ key: String) -> [String]? {
        guard case .array(let values)? = raw[key] else {
            return nil
        }

        return values.compactMap {
            guard case .string(let value) = $0 else {
                return nil
            }
            return value
        }
    }

    public func objectArray(_ key: String) -> [[String: JSONValue]] {
        guard case .array(let values)? = raw[key] else {
            return []
        }

        return values.compactMap {
            guard case .object(let value) = $0 else {
                return nil
            }
            return value
        }
    }
}

public enum JSONValueFactory {
    public static func strings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }
}
