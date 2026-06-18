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

public enum ExternalMCPAuditHistoryError: Error, Equatable, Sendable {
    case missingMetadata(String)
}

public enum ExternalMCPAuditHistory {
    public static func rows(from events: [AuditEvent]) throws -> [ExternalMCPAuditHistoryRow] {
        var rows: [ExternalMCPAuditHistoryRow] = []
        for event in events where event.category == "external_mcp" {
            rows.append(try row(from: event))
        }
        return rows.sorted { $0.timestamp > $1.timestamp }
    }

    private static func row(from event: AuditEvent) throws -> ExternalMCPAuditHistoryRow {
        ExternalMCPAuditHistoryRow(
            timestamp: event.timestamp,
            serverName: event.metadata["server_name"] ?? event.metadata["server_id"] ?? "External MCP",
            toolName: event.metadata["tool_name"] ?? event.action,
            risk: try requiredMetadata(event, key: "risk"),
            approval: try requiredMetadata(event, key: "approval"),
            durationMilliseconds: event.metadata["duration_ms"],
            status: event.status,
            redactedArgumentSummary: event.metadata["arguments"] ?? "",
            errorSummary: event.metadata["error"]
        )
    }

    private static func requiredMetadata(_ event: AuditEvent, key: String) throws -> String {
        guard let value = event.metadata[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExternalMCPAuditHistoryError.missingMetadata(key)
        }
        return value
    }
}
