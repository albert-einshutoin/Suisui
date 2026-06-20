import Foundation

public struct ExternalMCPExecutionPreview: Equatable, Sendable {
    public var serverID: String
    public var serverName: String
    public var toolName: String
    public var permissionLevel: ExternalMCPToolPermission
    public var inputSchema: [String: JSONValue]
    public var redactedArgumentSummary: String

    public var requiresApproval: Bool {
        permissionLevel.requiresUserApproval
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
    private let entitlementChecker: EntitlementChecker
    private let redactor: DeveloperSecretRedactor

    public init(
        server: MCPRegisteredServerDescriptor,
        registry: ExternalMCPToolRegistry,
        client: MCPClient,
        auditLogger: any AuditLogger,
        processController: any MCPProcessController,
        entitlementChecker: EntitlementChecker,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.server = server
        self.registry = registry
        self.client = client
        self.auditLogger = auditLogger
        self.processController = processController
        self.entitlementChecker = entitlementChecker
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
        try entitlementChecker.require(.advancedMCPExecution)
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
            _ = try await client.initialize()
            let result = try await client.callTool(name: toolName, arguments: arguments)
            try validateStructuredOutputIfNeeded(result, descriptor: descriptor)
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

    private func validateStructuredOutputIfNeeded(
        _ result: MCPToolCallResult,
        descriptor: ExternalMCPToolDescriptor
    ) throws {
        guard !result.isError else {
            return
        }
        guard let outputSchema = descriptor.definition.outputSchema else {
            return
        }
        guard let structuredContent = result.structuredContent else {
            throw MCPClientError.invalidResponse(
                serverID: server.id,
                method: "tools/call",
                reason: "Missing result.structuredContent for tool outputSchema."
            )
        }
        guard let structuredObject = structuredContent.objectValue else {
            throw MCPClientError.invalidResponse(
                serverID: server.id,
                method: "tools/call",
                reason: "result.structuredContent must be an object for tool outputSchema."
            )
        }

        try validateRequiredOutputFields(outputSchema: outputSchema, structuredObject: structuredObject)
        try validatePrimitiveOutputTypes(outputSchema: outputSchema, structuredObject: structuredObject)
    }

    private func validateRequiredOutputFields(
        outputSchema: [String: JSONValue],
        structuredObject: [String: JSONValue]
    ) throws {
        guard case .array(let requiredFields)? = outputSchema["required"] else {
            return
        }

        for field in requiredFields.compactMap(\.stringValue) where structuredObject[field] == nil {
            throw MCPClientError.invalidResponse(
                serverID: server.id,
                method: "tools/call",
                reason: "structuredContent missing required output field: \(field)."
            )
        }
    }

    private func validatePrimitiveOutputTypes(
        outputSchema: [String: JSONValue],
        structuredObject: [String: JSONValue]
    ) throws {
        guard let propertySchemas = outputSchema["properties"]?.objectValue else {
            return
        }

        for propertyName in propertySchemas.keys.sorted() {
            guard let value = structuredObject[propertyName],
                  let expectedType = propertySchemas[propertyName]?.objectValue?["type"]?.stringValue else {
                continue
            }
            guard value.matchesOutputSchemaType(expectedType) else {
                throw MCPClientError.invalidResponse(
                    serverID: server.id,
                    method: "tools/call",
                    reason: "structuredContent.\(propertyName) must match outputSchema type \(expectedType)."
                )
            }
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
            "permission": descriptor.permissionLevel.rawValueForAudit,
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
            .map { "\($0.key)=\(argumentValueSummary(key: $0.key, value: $0.value))" }
            .joined(separator: ",")
        return redactor.redact(summary).text
    }

    private func argumentValueSummary(key: String, value: JSONValue) -> String {
        Self.isSensitiveArgumentKey(key) ? "[REDACTED_SECRET]" : String(describing: value)
    }

    private static func isSensitiveArgumentKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return [
            "apikey",
            "authorization",
            "bearer",
            "credential",
            "password",
            "privatekey",
            "secret",
            "token"
        ].contains { normalized.contains($0) }
    }
}

private extension JSONValue {
    func matchesOutputSchemaType(_ expectedType: String) -> Bool {
        switch expectedType {
        case "string":
            if case .string = self { return true }
            return false
        case "number":
            if case .number = self { return true }
            return false
        case "integer":
            guard case .number(let value) = self else { return false }
            return value.isFinite && value.rounded(.towardZero) == value
        case "boolean":
            if case .bool = self { return true }
            return false
        case "object":
            if case .object = self { return true }
            return false
        case "array":
            if case .array = self { return true }
            return false
        case "null":
            if case .null = self { return true }
            return false
        default:
            return true
        }
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
