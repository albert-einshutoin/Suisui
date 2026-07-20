import Foundation

public struct ToolArguments: Sendable {
    public var raw: [String: JSONValue]
    public var tool: ActionTool

    public init(_ raw: [String: JSONValue], tool: ActionTool) {
        self.raw = raw
        self.tool = tool
    }

    public func requiredString(_ key: String) throws -> String {
        guard let value = try optionalString(key), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        return value
    }

    public func requiredTrimmedString(_ key: String) throws -> String {
        guard let value = try optionalString(key) else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Missing required argument '\(key)'.")
        }

        return trimmed
    }

    public func optionalString(_ key: String) throws -> String? {
        switch raw[key] {
        case .string(let value):
            return value
        case nil:
            return nil
        default:
            throw invalidString(key)
        }
    }

    public func optionalTrimmedString(_ key: String) throws -> String? {
        guard let value = try optionalString(key) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' cannot be blank.")
        }

        return trimmed
    }

    public func nullableTrimmedString(_ key: String) throws -> NullableFieldUpdate<String> {
        switch raw[key] {
        case .string(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' cannot be blank.")
            }
            return .set(trimmed)
        case .null:
            return .clear
        case nil:
            return .unchanged
        default:
            throw invalidNullableString(key)
        }
    }

    public func optionalNonBlankString(_ key: String) throws -> String? {
        guard let value = try optionalString(key) else {
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

    public func nullableInt64(_ key: String) throws -> NullableFieldUpdate<Int64> {
        switch raw[key] {
        case .number(let value):
            guard let intValue = Int64(exactly: value) else {
                throw invalidInt64(key)
            }
            return .set(intValue)
        case .string(let value):
            guard let intValue = Int64(value) else {
                throw invalidInt64(key)
            }
            return .set(intValue)
        case .null:
            return .clear
        case nil:
            return .unchanged
        default:
            throw invalidInt64(key)
        }
    }

    private func invalidInt64(_ key: String) -> ToolExecutionError {
        .validationFailed(tool, "Argument '\(key)' must be a 64-bit integer.")
    }

    private func invalidString(_ key: String) -> ToolExecutionError {
        .validationFailed(tool, "Argument '\(key)' must be string.")
    }

    private func invalidNullableString(_ key: String) -> ToolExecutionError {
        .validationFailed(tool, "Argument '\(key)' must be string or null.")
    }

    public func stringArray(_ key: String) throws -> [String] {
        try optionalStringArray(key) ?? []
    }

    public func trimmedStringArray(_ key: String) throws -> [String] {
        guard let values = try optionalStringArray(key) else {
            return []
        }

        return try trimmedStringArrayValues(values, key: key)
    }

    public func optionalTrimmedStringArray(_ key: String) throws -> [String]? {
        guard let values = try optionalStringArray(key) else {
            return nil
        }

        return try trimmedStringArrayValues(values, key: key)
    }

    public func nullableTrimmedStringArray(_ key: String) throws -> NullableFieldUpdate<[String]> {
        switch raw[key] {
        case .array:
            return .set(try trimmedStringArray(key))
        case .null:
            return .clear
        case nil:
            return .unchanged
        default:
            throw ToolExecutionError.validationFailed(tool, "Argument '\(key)' must be array or null.")
        }
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

    private func trimmedStringArrayValues(_ values: [String], key: String) throws -> [String] {
        try values.enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ToolExecutionError.validationFailed(tool, "Argument '\(key)[\(index)]' cannot be blank.")
            }
            return trimmed
        }
    }
}

public enum JSONValueFactory {
    public static func strings(_ values: [String]) -> JSONValue {
        .array(values.map(JSONValue.string))
    }
}
