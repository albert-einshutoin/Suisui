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

    public func requiredTrimmedString(_ key: String) throws -> String {
        guard let value = optionalString(key) else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        return trimmed
    }

    public func optionalString(_ key: String) -> String? {
        guard case .string(let value)? = raw[key] else {
            return nil
        }

        return value
    }

    public func optionalTrimmedString(_ key: String) throws -> String? {
        guard let value = optionalString(key) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' cannot be blank.")
        }

        return trimmed
    }

    public func optionalNonBlankString(_ key: String) throws -> String? {
        guard let value = optionalString(key) else {
            return nil
        }

        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' cannot be blank.")
        }

        return value
    }

    public func requiredInt64(_ key: String) throws -> Int64 {
        guard let value = try optionalInt64(key) else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        return value
    }

    public func optionalInt64(_ key: String) throws -> Int64? {
        switch raw[key] {
        case .number(let value):
            guard let intValue = Int64(exactly: value) else {
                throw invalidInt64(key)
            }
            return intValue
        case .string(let value):
            guard let intValue = Int64(value) else {
                throw invalidInt64(key)
            }
            return intValue
        case nil:
            return nil
        default:
            throw invalidInt64(key)
        }
    }

    private func invalidInt64(_ key: String) -> ToolExecutionError {
        .validationFailed(tool, "Argument '\(key)' must be a 64-bit integer.")
    }

    public func stringArray(_ key: String) throws -> [String] {
        try optionalStringArray(key) ?? []
    }

    public func trimmedStringArray(_ key: String) throws -> [String] {
        guard let values = try optionalStringArray(key) else {
            return []
        }

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func optionalTrimmedStringArray(_ key: String) throws -> [String]? {
        guard let values = try optionalStringArray(key) else {
            return nil
        }

        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    public func optionalStringArray(_ key: String) throws -> [String]? {
        guard let rawValue = raw[key] else {
            return nil
        }

        guard case .array(let values) = rawValue else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' must be array.")
        }

        return try values.enumerated().map { index, value in
            guard case .string(let stringValue) = value else {
                throw ToolExecutionError.validationFailed(tool, "Argument '\(key)[\(index)]' must be string.")
            }
            return stringValue
        }
    }

    public func objectArray(_ key: String) throws -> [[String: JSONValue]] {
        guard let rawValue = raw[key] else {
            return []
        }

        guard case .array(let values) = rawValue else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' must be array.")
        }

        return try values.enumerated().map { index, value in
            guard case .object(let objectValue) = value else {
                throw ToolExecutionError.validationFailed(tool, "Argument '\(key)[\(index)]' must be object.")
            }
            return objectValue
        }
    }
}

public enum JSONValueFactory {
    public static func strings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }
}
