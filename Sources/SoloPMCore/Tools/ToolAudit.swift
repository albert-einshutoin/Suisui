import Foundation

public struct AuditedTool: Tool {
    private let base: any Tool
    private let logger: any AuditLogger

    public var name: ActionTool { base.name }
    public var description: String { base.description }
    public var inputSchema: ToolInputSchema { base.inputSchema }
    public var permissionLevel: ToolPermissionLevel { base.permissionLevel }

    public init(base: any Tool, logger: any AuditLogger) {
        self.base = base
        self.logger = logger
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

        do {
            let result = try base.execute(arguments: arguments, context: context)
            var eventMetadata = metadata(arguments: arguments, context: context)
            eventMetadata["result"] = result.status.rawValue
            eventMetadata["summary"] = result.summary
            try logger.record(AuditEvent(category: "tool", action: name.rawValue, status: .succeeded, metadata: eventMetadata))
            return result
        } catch {
            var eventMetadata = metadata(arguments: arguments, context: context)
            eventMetadata["error"] = String(describing: error)
            try logger.record(AuditEvent(category: "tool", action: name.rawValue, status: .failed, metadata: eventMetadata))
            throw error
        }
    }

    private func metadata(arguments: [String: JSONValue], context: ToolExecutionContext) -> [String: String] {
        [
            "tool": name.rawValue,
            "risk_level": name.defaultRiskLevel.rawValue,
            "permission_level": permissionLevel.rawValue,
            "source": context.source.rawValue,
            "approval_state": context.approvalToken == nil ? "missing" : "present",
            "arguments": Self.argumentSummary(arguments)
        ]
    }

    private static func argumentSummary(_ arguments: [String: JSONValue]) -> String {
        let summary = arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(describing: $0.value))" }
            .joined(separator: ",")
        guard summary.count > 256 else {
            return summary
        }
        return String(summary.prefix(256))
    }
}
