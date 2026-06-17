import Foundation

public enum ExternalMCPToolPermission: Equatable, Sendable {
    case read
    case draft
    case writeWithApproval
    case dangerous
    case disabled

    var toolPermissionLevel: ToolPermissionLevel? {
        switch self {
        case .read:
            return .read
        case .draft:
            return .draft
        case .writeWithApproval:
            return .writeWithApproval
        case .dangerous:
            return .dangerous
        case .disabled:
            return nil
        }
    }
}

public enum ToolOrigin: Equatable, Sendable {
    case builtIn(ActionTool)
    case externalMCP(serverID: String, toolName: String)
}

public struct ExternalMCPToolDescriptor: Equatable, Sendable {
    public var origin: ToolOrigin
    public var server: MCPRegisteredServerDescriptor
    public var definition: MCPToolDefinition
    public var permissionLevel: ExternalMCPToolPermission

    public init(
        origin: ToolOrigin,
        server: MCPRegisteredServerDescriptor,
        definition: MCPToolDefinition,
        permissionLevel: ExternalMCPToolPermission
    ) {
        self.origin = origin
        self.server = server
        self.definition = definition
        self.permissionLevel = permissionLevel
    }
}

public struct ExternalMCPToolCatalogRow: Equatable, Sendable {
    public var id: String
    public var serverID: String
    public var serverName: String
    public var toolName: String
    public var title: String
    public var description: String
    public var permissionLevel: ExternalMCPToolPermission
    public var permissionLabel: String
    public var inputSchemaSummary: String
    public var requiresApproval: Bool
    public var isExecutableWithoutApproval: Bool

    public init(descriptor: ExternalMCPToolDescriptor) {
        self.id = "\(descriptor.server.id):\(descriptor.definition.name)"
        self.serverID = descriptor.server.id
        self.serverName = descriptor.server.displayName
        self.toolName = descriptor.definition.name
        self.title = descriptor.definition.title ?? descriptor.definition.name
        self.description = descriptor.definition.description
        self.permissionLevel = descriptor.permissionLevel
        self.permissionLabel = descriptor.permissionLevel.displayLabel
        self.inputSchemaSummary = Self.schemaSummary(descriptor.definition.inputSchema)
        self.requiresApproval = descriptor.permissionLevel == .writeWithApproval
        self.isExecutableWithoutApproval = descriptor.permissionLevel == .read || descriptor.permissionLevel == .draft
    }

    private static func schemaSummary(_ inputSchema: [String: JSONValue]) -> String {
        let required = inputSchema["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let properties = inputSchema["properties"]?.objectValue?.keys.sorted() ?? []
        if required.isEmpty && properties.isEmpty {
            return "No arguments"
        }

        var parts: [String] = []
        if !properties.isEmpty {
            parts.append("properties: \(properties.joined(separator: ", "))")
        }
        if !required.isEmpty {
            parts.append("required: \(required.sorted().joined(separator: ", "))")
        }
        return parts.joined(separator: " / ")
    }
}

public enum ExternalMCPToolCatalog {
    public static func rows(from descriptors: [ExternalMCPToolDescriptor]) -> [ExternalMCPToolCatalogRow] {
        descriptors
            .map(ExternalMCPToolCatalogRow.init)
            .sorted { lhs, rhs in
                if lhs.serverName == rhs.serverName {
                    return lhs.toolName < rhs.toolName
                }
                return lhs.serverName < rhs.serverName
            }
    }
}

public struct ExternalMCPToolClassifier: Sendable {
    private let explicitPolicies: [String: ExternalMCPToolPermission]

    public init(explicitPolicies: [String: ExternalMCPToolPermission] = [:]) {
        self.explicitPolicies = explicitPolicies
    }

    public func classify(_ tool: MCPToolDefinition) -> ExternalMCPToolPermission {
        explicitPolicies[tool.name] ?? .disabled
    }
}

private extension ExternalMCPToolPermission {
    var displayLabel: String {
        switch self {
        case .read:
            return "Read"
        case .draft:
            return "Draft"
        case .writeWithApproval:
            return "Write with approval"
        case .dangerous:
            return "Dangerous"
        case .disabled:
            return "Disabled"
        }
    }
}

public enum ExternalMCPExecutionError: Error, Equatable, Sendable {
    case unknownTool(serverID: String, toolName: String)
    case toolDisabled(serverID: String, toolName: String)
    case dangerousToolBlocked(serverID: String, toolName: String)
    case approvalRequired(serverID: String, toolName: String)
}

public struct ExternalMCPToolRegistry: Sendable {
    private let server: MCPRegisteredServerDescriptor
    private let descriptors: [String: ExternalMCPToolDescriptor]

    public init(
        server: MCPRegisteredServerDescriptor,
        tools: [MCPToolDefinition],
        classifier: ExternalMCPToolClassifier
    ) {
        self.server = server
        self.descriptors = Dictionary(uniqueKeysWithValues: tools.map { tool in
            (
                tool.name,
                ExternalMCPToolDescriptor(
                    origin: .externalMCP(serverID: server.id, toolName: tool.name),
                    server: server,
                    definition: tool,
                    permissionLevel: classifier.classify(tool)
                )
            )
        })
    }

    public func descriptor(named toolName: String) throws -> ExternalMCPToolDescriptor {
        guard let descriptor = descriptors[toolName] else {
            throw ExternalMCPExecutionError.unknownTool(serverID: server.id, toolName: toolName)
        }
        return descriptor
    }

    public var allDescriptors: [ExternalMCPToolDescriptor] {
        descriptors.values.sorted { $0.definition.name < $1.definition.name }
    }

    public func assertExecutable(toolName: String, context: ToolExecutionContext) throws {
        let descriptor = try descriptor(named: toolName)
        switch descriptor.permissionLevel {
        case .read, .draft:
            return
        case .writeWithApproval:
            guard context.approvalToken != nil else {
                throw ExternalMCPExecutionError.approvalRequired(serverID: server.id, toolName: toolName)
            }
        case .dangerous:
            throw ExternalMCPExecutionError.dangerousToolBlocked(serverID: server.id, toolName: toolName)
        case .disabled:
            throw ExternalMCPExecutionError.toolDisabled(serverID: server.id, toolName: toolName)
        }
    }
}
