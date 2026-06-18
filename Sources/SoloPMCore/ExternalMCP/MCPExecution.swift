import Foundation

public struct ExternalMCPExecutionPreview: Equatable, Sendable {
    public var serverID: String
    public var serverName: String
    public var toolName: String
    public var permissionLevel: ExternalMCPToolPermission
    public var inputSchema: [String: JSONValue]
    public var redactedArgumentSummary: String

    public var requiresApproval: Bool {
        permissionLevel == .writeWithApproval
    }
}

public enum MCPProcessKillReason: String, Equatable, Sendable {
    case timeout
    case crashed
}

public protocol MCPProcessController: Sendable {
    func kill(serverID: String, reason: MCPProcessKillReason) async
}

public struct ExternalMCPToolExecutor: Sendable {
    private let server: MCPRegisteredServerDescriptor
    private let registry: ExternalMCPToolRegistry
    private let client: MCPClient
    private let auditLogger: any AuditLogger
    private let processController: any MCPProcessController
    private let redactor: DeveloperSecretRedactor

    public init(
        server: MCPRegisteredServerDescriptor,
        registry: ExternalMCPToolRegistry,
        client: MCPClient,
        auditLogger: any AuditLogger,
        processController: any MCPProcessController,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.server = server
        self.registry = registry
        self.client = client
        self.auditLogger = auditLogger
        self.processController = processController
        self.redactor = redactor
    }

    public func preview(toolName: String, arguments: [String: JSONValue]) throws -> ExternalMCPExecutionPreview {
        let descriptor = try registry.descriptor(named: toolName)
        return ExternalMCPExecutionPreview(
            serverID: server.id,
            serverName: server.displayName,
            toolName: toolName,
            permissionLevel: descriptor.permissionLevel,
            inputSchema: descriptor.definition.inputSchema,
            redactedArgumentSummary: redactedArgumentSummary(arguments)
        )
    }

    public func call(
        toolName: String,
        arguments: [String: JSONValue],
        context: ToolExecutionContext
    ) async throws -> MCPToolCallResult {
        let descriptor = try registry.descriptor(named: toolName)
        try registry.assertExecutable(toolName: toolName, context: context)

        let startedAt = Date()
        try auditLogger.record(AuditEvent(
            category: "external_mcp",
            action: "\(server.id).\(toolName)",
            status: .started,
            metadata: auditMetadata(
                toolName: toolName,
                arguments: arguments,
                context: context,
                descriptor: descriptor,
                startedAt: startedAt
            )
        ))

        do {
            let result = try await client.callTool(name: toolName, arguments: arguments)
            var metadata = auditMetadata(
                toolName: toolName,
                arguments: arguments,
                context: context,
                descriptor: descriptor,
                startedAt: startedAt
            )
            metadata["result"] = result.isError ? "tool_error" : "succeeded"
            metadata["duration_ms"] = "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            try auditLogger.record(AuditEvent(category: "external_mcp", action: "\(server.id).\(toolName)", status: .succeeded, metadata: metadata))
            return result
        } catch {
            if case MCPClientError.timeout(let serverID, _) = error {
                await processController.kill(serverID: serverID, reason: .timeout)
            }

            var metadata = auditMetadata(
                toolName: toolName,
                arguments: arguments,
                context: context,
                descriptor: descriptor,
                startedAt: startedAt
            )
            metadata["duration_ms"] = "\(Int(Date().timeIntervalSince(startedAt) * 1_000))"
            metadata["error"] = redactor.redact(String(describing: error)).text
            try auditLogger.record(AuditEvent(category: "external_mcp", action: "\(server.id).\(toolName)", status: .failed, metadata: metadata))
            throw error
        }
    }

    private func auditMetadata(
        toolName: String,
        arguments: [String: JSONValue],
        context: ToolExecutionContext,
        descriptor: ExternalMCPToolDescriptor,
        startedAt: Date
    ) -> [String: String] {
        return [
            "server_id": server.id,
            "server_name": server.displayName,
            "tool_name": toolName,
            "risk": descriptor.permissionLevel.rawValueForAudit,
            "approval": context.approvalToken == nil ? "missing" : "present",
            "source": context.source.rawValue,
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "arguments": redactedArgumentSummary(arguments)
        ]
    }

    private func redactedArgumentSummary(_ arguments: [String: JSONValue]) -> String {
        guard !arguments.isEmpty else {
            return "No arguments"
        }
        let summary = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .joined(separator: ",")
        return redactor.redact(summary).text
    }
}

private extension ExternalMCPToolPermission {
    var rawValueForAudit: String {
        switch self {
        case .read:
            return "read"
        case .draft:
            return "draft"
        case .writeWithApproval:
            return "writeWithApproval"
        case .dangerous:
            return "dangerous"
        case .disabled:
            return "disabled"
        }
    }
}
