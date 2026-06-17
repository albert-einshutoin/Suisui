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

    public init(approvalToken: ApprovalToken? = nil, now: Date = Date(), source: ToolExecutionSource = .developerHarness) {
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

    public init(tools: [any Tool] = []) throws {
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

public struct StaticTool: Tool {
    public var name: ActionTool
    public var description: String
    public var inputSchema: ToolInputSchema
    public var permissionLevel: ToolPermissionLevel
    private var handler: @Sendable ([String: JSONValue], ToolExecutionContext) throws -> ToolResult

    public init(
        name: ActionTool,
        description: String,
        inputSchema: ToolInputSchema,
        permissionLevel: ToolPermissionLevel,
        handler: @escaping @Sendable ([String: JSONValue], ToolExecutionContext) throws -> ToolResult
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.permissionLevel = permissionLevel
        self.handler = handler
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try enforcePermission(context: context)
        try validateRequiredArguments(arguments)
        return try handler(arguments, context)
    }
}
