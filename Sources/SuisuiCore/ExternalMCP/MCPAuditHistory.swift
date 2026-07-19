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
        let serverName = try requiredMetadata(event, key: "server_name")
        let toolName = try requiredMetadata(event, key: "tool_name")
        let risk = try requiredMetadata(event, key: "risk")
        let approval = try requiredMetadata(event, key: "approval")
        let redactedArgumentSummary = try requiredMetadata(event, key: "arguments")
        let durationMilliseconds = try durationMetadata(for: event)
        let errorSummary = try errorMetadata(for: event)

        return ExternalMCPAuditHistoryRow(
            timestamp: event.timestamp,
            serverName: serverName,
            toolName: toolName,
            risk: risk,
            approval: approval,
            durationMilliseconds: durationMilliseconds,
            status: event.status,
            redactedArgumentSummary: redactedArgumentSummary,
            errorSummary: errorSummary
        )
    }

    private static func durationMetadata(for event: AuditEvent) throws -> String? {
        switch event.status {
        case .succeeded, .failed:
            try requiredMetadata(event, key: "duration_ms")
        case .started, .skipped:
            event.metadata["duration_ms"]
        }
    }

    private static func errorMetadata(for event: AuditEvent) throws -> String? {
        switch event.status {
        case .failed:
            try requiredMetadata(event, key: "error")
        case .started, .succeeded, .skipped:
            event.metadata["error"]
        }
    }

    private static func requiredMetadata(_ event: AuditEvent, key: String) throws -> String {
        guard let value = event.metadata[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExternalMCPAuditHistoryError.missingMetadata(key)
        }
        return value
    }
}
