import Foundation

public struct ExternalMCPAuditHistoryRow: Equatable, Sendable {
    public var timestamp: Date
    public var serverName: String
    public var toolName: String
    public var risk: String
    public var approval: String
    public var durationMilliseconds: String?
    public var status: AuditStatus
    public var redactedArgumentSummary: String
    public var errorSummary: String?

    public var statusLabel: String {
        switch status {
        case .started:
            return "Started"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .skipped:
            return "Skipped"
        }
    }
}

public enum ExternalMCPAuditHistory {
    public static func rows(from events: [AuditEvent]) -> [ExternalMCPAuditHistoryRow] {
        events
            .filter { $0.category == "external_mcp" }
            .map { event in
                ExternalMCPAuditHistoryRow(
                    timestamp: event.timestamp,
                    serverName: event.metadata["server_name"] ?? event.metadata["server_id"] ?? "External MCP",
                    toolName: event.metadata["tool_name"] ?? event.action,
                    risk: event.metadata["risk"] ?? "unknown",
                    approval: event.metadata["approval"] ?? "unknown",
                    durationMilliseconds: event.metadata["duration_ms"],
                    status: event.status,
                    redactedArgumentSummary: event.metadata["arguments"] ?? "",
                    errorSummary: event.metadata["error"]
                )
            }
            .sorted { $0.timestamp > $1.timestamp }
    }
}
