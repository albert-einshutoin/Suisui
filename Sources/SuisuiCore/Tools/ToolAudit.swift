import Foundation

public struct AuditedTool: Tool {
    private let base: any Tool
    private let logger: any AuditLogger
    private let redactor: DeveloperSecretRedactor

    public var name: ActionTool { base.name }
    public var description: String { base.description }
    public var inputSchema: ToolInputSchema { base.inputSchema }
    public var permissionLevel: ToolPermissionLevel { base.permissionLevel }

    public init(
        base: any Tool,
        logger: any AuditLogger,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.base = base
        self.logger = logger
        self.redactor = redactor
    }

    public func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        try logger.record(
            AuditEvent(
                category: "tool",
                action: name.rawValue,
                status: .started,
                metadata: metadata(arguments: arguments, context: context)
            )
        )

        var result: ToolResult
        do {
            result = try base.execute(arguments: arguments, context: context)
        } catch {
            var eventMetadata = metadata(arguments: arguments, context: context)
            eventMetadata["error"] = redacted(String(describing: error))
            // Preserve reconciliation evidence even when failure auditing is unavailable.
            try? logger.record(AuditEvent(category: "tool", action: name.rawValue, status: .failed, metadata: eventMetadata))
            throw error
        }
        var eventMetadata = metadata(arguments: arguments, context: context)
        eventMetadata["result"] = result.status.rawValue
        eventMetadata["summary"] = redacted(result.summary)
        do {
            try logger.record(AuditEvent(category: "tool", action: name.rawValue, status: .succeeded, metadata: eventMetadata))
        } catch {
            // The tool already returned its outcome; audit failure cannot undo it.
            result.auditErrorMessage = "Action audit log could not be saved."
        }
        return result
    }

    private func metadata(arguments: [String: JSONValue], context: ToolExecutionContext) -> [String: String] {
        [
            "tool": name.rawValue,
            "risk_level": name.defaultRiskLevel.rawValue,
            "permission_level": permissionLevel.rawValue,
            "source": context.source.rawValue,
            "approval_state": context.approvalToken == nil ? "missing" : "present",
            "arguments": argumentSummary(arguments)
        ]
    }

    private func argumentSummary(_ arguments: [String: JSONValue]) -> String {
        let summary = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(argumentValueSummary(key: $0.key, value: $0.value))" }
            .joined(separator: ",")
        let redactedSummary = redacted(summary)
        guard redactedSummary.count > 256 else {
            return redactedSummary
        }
        return String(redactedSummary.prefix(256))
    }

    private func argumentValueSummary(key: String, value: JSONValue) -> String {
        Self.isSensitiveArgumentKey(key) ? "[REDACTED_SECRET]" : String(describing: value)
    }

    private func redacted(_ value: String) -> String {
        redactor.redact(value).text
    }

    private static func isSensitiveArgumentKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        // Free-form bodies can contain proprietary code, customer notes, or long
        // prompts even when they do not match token regexes, so audit only records
        // that such fields were present.
        if ["body", "content", "contents", "markdown", "text"].contains(normalized) {
            return true
        }
        return [
            "api_key",
            "apikey",
            "authorization",
            "bearer",
            "password",
            "secret",
            "token"
        ].contains { normalized.contains($0) }
    }
}
