import Foundation

public struct ToolInputSchema: Equatable, Sendable {
    public var required: [String]
    public var properties: [String: String]
    public var additionalProperties: Bool

    public init(required: [String] = [], properties: [String: String] = [:], additionalProperties: Bool = false) {
        self.required = required
        self.properties = properties
        self.additionalProperties = additionalProperties
    }
}

public struct ToolInputValidationIssue: Equatable, Sendable {
    public var actionID: String?
    public var field: String
    public var message: String

    public init(actionID: String? = nil, field: String, message: String) {
        self.actionID = actionID
        self.field = field
        self.message = message
    }
}

public extension ToolInputSchema {
    func validate(arguments: [String: JSONValue], tool: ActionTool, actionID: String? = nil) -> [ToolInputValidationIssue] {
        var issues: [ToolInputValidationIssue] = []

        for key in required {
            guard let value = arguments[key], !value.isBlankString else {
                issues.append(
                    ToolInputValidationIssue(
                        actionID: actionID,
                        field: key,
                        message: "Missing required argument '\(key)' for \(tool.rawValue)."
                    )
                )
                continue
            }
        }

        if !additionalProperties {
            let knownKeys = Set(properties.keys).union(required)
            for key in arguments.keys.sorted() where !knownKeys.contains(key) {
                issues.append(
                    ToolInputValidationIssue(
                        actionID: actionID,
                        field: key,
                        message: "Unknown argument '\(key)' for \(tool.rawValue)."
                    )
                )
            }
        }

        for (key, value) in arguments {
            guard let expectedType = properties[key], !value.matchesSchemaType(expectedType) else {
                continue
            }

            issues.append(
                ToolInputValidationIssue(
                    actionID: actionID,
                    field: key,
                    message: "Argument '\(key)' must be \(expectedType) for \(tool.rawValue)."
                )
            )
        }

        return issues
    }
}

public enum ToolPermissionLevel: String, Equatable, Sendable {
    case read
    case draft
    case writeWithApproval
    case dangerous
}

public struct ApprovalToken: Equatable, Sendable {
    public var id: String
    public var sessionID: String
    public var approvedAt: Date

    public init(id: String, sessionID: String, approvedAt: Date = Date()) {
        self.id = id
        self.sessionID = sessionID
        self.approvedAt = approvedAt
    }
}

public struct ToolExecutionContext: Sendable {
    public var approvalToken: ApprovalToken?
    public var now: Date
    public var source: ToolExecutionSource

    public init(approvalToken: ApprovalToken? = nil, now: Date = Date(), source: ToolExecutionSource) {
        self.approvalToken = approvalToken
        self.now = now
        self.source = source
    }
}

public enum ToolExecutionSource: String, Equatable, Sendable {
    case developerHarness
    case reviewUI
    case test
}

public enum ToolExecutionStatus: String, Equatable, Sendable {
    case succeeded
    case failed
    case skipped
}

public struct ToolResult: Equatable, Sendable {
    public var tool: ActionTool
    public var status: ToolExecutionStatus
    public var summary: String
    public var output: [String: JSONValue]
    public var rollbackMetadata: [String: JSONValue]
    public var compensationHint: String?

    public init(
        tool: ActionTool,
        status: ToolExecutionStatus,
        summary: String,
        output: [String: JSONValue] = [:],
        rollbackMetadata: [String: JSONValue] = [:],
        compensationHint: String? = nil
    ) {
        self.tool = tool
        self.status = status
        self.summary = summary
        self.output = output
        self.rollbackMetadata = rollbackMetadata
        self.compensationHint = compensationHint
    }
}

public enum ToolExecutionError: Error, Equatable, Sendable {
    case duplicateTool(ActionTool)
    case unknownTool(ActionTool)
    case approvalRequired(ActionTool)
    case dangerousToolBlocked(ActionTool)
    case validationFailed(ActionTool, String)
    case executionFailed(ActionTool, String)
}

public extension ToolExecutionError {
    static func validationFailed(_ tool: ActionTool, issues: [ToolInputValidationIssue]) -> ToolExecutionError {
        let message = issues.map(\.message).joined(separator: " ")
        return .validationFailed(tool, message.isEmpty ? "Invalid tool arguments." : message)
    }
}

public protocol Tool: Sendable {
    var name: ActionTool { get }
    var description: String { get }
    var inputSchema: ToolInputSchema { get }
    var permissionLevel: ToolPermissionLevel { get }

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult
}

public extension Tool {
    func enforcePermission(context: ToolExecutionContext) throws {
        switch permissionLevel {
        case .read, .draft:
            return
        case .writeWithApproval:
            guard context.approvalToken != nil else {
                throw ToolExecutionError.approvalRequired(name)
            }
        case .dangerous:
            throw ToolExecutionError.dangerousToolBlocked(name)
        }
    }

    func validateRequiredArguments(_ arguments: [String: JSONValue]) throws {
        for key in inputSchema.required where arguments[key] == nil {
            throw ToolExecutionError.validationFailed(name, "Missing required argument '\(key)'.")
        }
    }
}

public final class ToolRegistry: @unchecked Sendable {
    private var tools: [ActionTool: any Tool]
    private let lock = NSLock()

    public init() {
        self.tools = [:]
    }

    public init(tools: [any Tool]) throws {
        self.tools = [:]
        for tool in tools {
            try register(tool)
        }
    }

    public func register(_ tool: any Tool) throws {
        lock.lock()
        defer { lock.unlock() }

        guard tools[tool.name] == nil else {
            throw ToolExecutionError.duplicateTool(tool.name)
        }

        tools[tool.name] = tool
    }

    public func tool(named name: ActionTool) throws -> any Tool {
        lock.lock()
        defer { lock.unlock() }

        guard let tool = tools[name] else {
            throw ToolExecutionError.unknownTool(name)
        }

        return tool
    }

    public func contains(_ name: ActionTool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tools[name] != nil
    }

    public func schema(for name: ActionTool) -> ToolInputSchema? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]?.inputSchema
    }

    public func validate(action: PlanAction) -> [ToolInputValidationIssue] {
        lock.lock()
        defer { lock.unlock() }

        guard let schema = tools[action.tool]?.inputSchema else {
            return []
        }

        return schema.validate(arguments: action.arguments, tool: action.tool, actionID: action.id)
    }

    public var registeredTools: [ActionTool] {
        lock.lock()
        defer { lock.unlock() }
        return tools.keys.sorted { $0.rawValue < $1.rawValue }
    }

    public var schemaList: [ToolSchemaExport] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values
            .map {
                ToolSchemaExport(
                    name: $0.name,
                    description: $0.description,
                    inputSchema: $0.inputSchema,
                    permissionLevel: $0.permissionLevel
                )
            }
            .sorted { $0.name.rawValue < $1.name.rawValue }
    }
}

public struct ToolSchemaExport: Equatable, Sendable {
    public var name: ActionTool
    public var description: String
    public var inputSchema: ToolInputSchema
    public var permissionLevel: ToolPermissionLevel

    public init(
        name: ActionTool,
        description: String,
        inputSchema: ToolInputSchema,
        permissionLevel: ToolPermissionLevel
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.permissionLevel = permissionLevel
    }
}

private extension JSONValue {
    var isBlankString: Bool {
        guard case .string(let value) = self else {
            return false
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matchesSchemaType(_ expectedType: String) -> Bool {
        switch expectedType {
        case "string":
            if case .string = self {
                return true
            }
            return false
        case "number":
            switch self {
            case .number:
                return true
            case .string(let value):
                return Double(value) != nil
            default:
                return false
            }
        case "array":
            if case .array = self {
                return true
            }
            return false
        case "object":
            if case .object = self {
                return true
            }
            return false
        case "bool", "boolean":
            if case .bool = self {
                return true
            }
            return false
        default:
            return true
        }
    }
}
