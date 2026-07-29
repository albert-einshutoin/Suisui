import CryptoKit
import Foundation

public struct ExecutionReceiptHistorySnapshot: Equatable, Sendable {
    public var rows: [ExecutionReceiptHistoryRow]
    public var unavailableMessage: String?

    public init(rows: [ExecutionReceiptHistoryRow], unavailableMessage: String? = nil) {
        self.rows = rows
        self.unavailableMessage = unavailableMessage
    }

    public static let empty = ExecutionReceiptHistorySnapshot(rows: [])
}

public struct ExecutionReceiptHistoryRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var status: ExecutionReceiptStatus
    public var statusLabel: String
    public var toolLabel: String
    public var outcomeSummary: String
    public var usageLabel: String
    public var referenceSummary: String
    public var sourceSummary: String
    public var occurredAt: Date
    public var occurredAtLabel: String
    public var receiptIDLabel: String
    public var accessibilityValue: String

    public init(
        id: String,
        status: ExecutionReceiptStatus,
        statusLabel: String,
        toolLabel: String,
        outcomeSummary: String,
        usageLabel: String,
        referenceSummary: String,
        sourceSummary: String,
        occurredAt: Date,
        occurredAtLabel: String,
        receiptIDLabel: String,
        accessibilityValue: String
    ) {
        self.id = id
        self.status = status
        self.statusLabel = statusLabel
        self.toolLabel = toolLabel
        self.outcomeSummary = outcomeSummary
        self.usageLabel = usageLabel
        self.referenceSummary = referenceSummary
        self.sourceSummary = sourceSummary
        self.occurredAt = occurredAt
        self.occurredAtLabel = occurredAtLabel
        self.receiptIDLabel = receiptIDLabel
        self.accessibilityValue = accessibilityValue
    }
}

public enum ExecutionReceiptHistoryReadModel {
    public static func snapshot(
        from receipts: [ExecutionReceipt],
        limit: Int = 10
    ) -> ExecutionReceiptHistorySnapshot {
        let boundedLimit = max(1, min(limit, 100))
        let rows = receipts
            .sorted { lhs, rhs in
                occurrenceDate(for: lhs) > occurrenceDate(for: rhs)
            }
            .prefix(boundedLimit)
            .map(row)
        return ExecutionReceiptHistorySnapshot(rows: Array(rows))
    }

    public static func snapshot(
        from receipts: [ExecutionReceipt],
        matching filter: ExecutionReceiptSearchFilter,
        limit: Int = 10
    ) -> ExecutionReceiptHistorySnapshot {
        snapshot(
            from: receipts.filter { filter.matches($0) },
            limit: limit
        )
    }

    public static func snapshot(
        from receipts: [ExecutionReceipt],
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface,
        limit: Int = 5
    ) -> ExecutionReceiptHistorySnapshot {
        let matchingReceipts = receipts.filter { receipt in
            receipt.visibleSurfaces.contains(visibleSurface)
                && receipt.references.contains { reference in
                    reference.kind == referenceKind && reference.id == referenceID
                }
        }
        return snapshot(from: matchingReceipts, limit: limit)
    }

    private static func row(from receipt: ExecutionReceipt) -> ExecutionReceiptHistoryRow {
        let redactor = ExecutionReceiptRedactor()
        let occurredAt = occurrenceDate(for: receipt)
        let statusLabel = label(for: receipt.status)
        // The global history is safe to show broadly because rows never carry raw
        // prompts, action arguments, source URLs, document bodies, or raw receipt IDs.
        let fallbackToolLabel = String(localized: "AI work")
        let toolLabel = redactor.redact(receipt.primaryToolName ?? receipt.actions.first?.toolName ?? fallbackToolLabel, maxLength: 120)
        let outcomeSummary = redactor.redact(receipt.outputSummary, maxLength: 280)
        let usageLabel = usageLabel(for: receipt.usage)
        let referenceSummary = referenceSummary(for: receipt.references)
        let sourceSummary = sourceSummary(for: receipt.sourceLinks)
        let occurredAtLabel = dateLabel(for: occurredAt)
        let receiptDigest = displayDigest(for: receipt)
        let receiptIDLabel = String(format: String(localized: "Receipt Digest: %@"), receiptDigest)
        let accessibilityValue = [
            statusLabel,
            toolLabel,
            outcomeSummary,
            usageLabel,
            referenceSummary,
            sourceSummary,
            occurredAtLabel,
            receiptIDLabel
        ].joined(separator: ", ")

        return ExecutionReceiptHistoryRow(
            id: receiptDigest,
            status: receipt.status,
            statusLabel: statusLabel,
            toolLabel: toolLabel,
            outcomeSummary: outcomeSummary,
            usageLabel: usageLabel,
            referenceSummary: referenceSummary,
            sourceSummary: sourceSummary,
            occurredAt: occurredAt,
            occurredAtLabel: occurredAtLabel,
            receiptIDLabel: receiptIDLabel,
            accessibilityValue: accessibilityValue
        )
    }

    private static func occurrenceDate(for receipt: ExecutionReceipt) -> Date {
        receipt.finishedAt ?? receipt.startedAt ?? receipt.createdAt
    }

    private static func label(for status: ExecutionReceiptStatus) -> String {
        switch status {
        case .notStarted:
            return String(localized: "Not Started")
        case .running:
            return String(localized: "Running")
        case .succeeded:
            return String(localized: "Succeeded")
        case .failed:
            return String(localized: "Failed")
        case .skipped:
            return String(localized: "Skipped")
        case .canceled:
            return String(localized: "Canceled")
        }
    }

    private static func usageLabel(for usage: ExecutionReceiptUsage) -> String {
        switch usage.state {
        case .measured:
            return measuredOrEstimatedUsageLabel(prefix: String(localized: "Measured"), usage: usage)
        case .estimated:
            return measuredOrEstimatedUsageLabel(prefix: String(localized: "Estimated"), usage: usage)
        case .unknown:
            return String(localized: "Usage Unknown")
        case .unavailable:
            return String(localized: "Usage Unavailable")
        }
    }

    private static func measuredOrEstimatedUsageLabel(prefix: String, usage: ExecutionReceiptUsage) -> String {
        var parts: [String] = []
        if let totalTokens = usage.totalTokens {
            parts.append(String(format: String(localized: "%d tokens"), totalTokens))
        }
        if let estimatedCostCents = usage.estimatedCostCents,
           let currencyCode = usage.currencyCode,
           !currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("\(currencyCode) \(String(format: "%.2f", estimatedCostCents / 100.0))")
        }
        guard !parts.isEmpty else {
            return String(format: String(localized: "%@ usage"), prefix)
        }
        return "\(prefix): \(parts.joined(separator: ", "))"
    }

    private static func referenceSummary(for references: [ExecutionReceiptReference]) -> String {
        compactKindSummary(prefix: String(localized: "References"), kinds: references.map(\.kind))
    }

    private static func sourceSummary(for sourceLinks: [ExecutionReceiptSourceLink]) -> String {
        compactKindSummary(prefix: String(localized: "Sources"), kinds: sourceLinks.map(\.kind))
    }

    private static func compactKindSummary(
        prefix: String,
        kinds: [ExecutionReceiptReferenceKind]
    ) -> String {
        guard !kinds.isEmpty else {
            return String(format: String(localized: "%@: none"), prefix)
        }
        let counts = Dictionary(grouping: kinds, by: { $0 }).mapValues(\.count)
        let parts = counts
            .sorted { label(for: $0.key) < label(for: $1.key) }
            .map { kind, count in
                "\(label(for: kind)) \(count)"
            }
        return "\(prefix): \(parts.joined(separator: ", "))"
    }

    private static func label(for kind: ExecutionReceiptReferenceKind) -> String {
        switch kind {
        case .unknown:
            return String(localized: "Unknown")
        case .assistantQueue:
            return String(localized: "Assistant Queue")
        case .actionPlan:
            return String(localized: "Action Plan")
        case .reviewSession:
            return String(localized: "Review Session")
        case .task:
            return String(localized: "Task")
        case .project:
            return String(localized: "Project")
        case .document:
            return String(localized: "Document")
        case .calendarEvent:
            return String(localized: "Calendar Event")
        case .notification:
            return String(localized: "Notification")
        case .reminder:
            return String(localized: "Reminder")
        case .developmentBranch:
            return String(localized: "Development Branch")
        case .developmentBaseBranch:
            return String(localized: "Development Base Branch")
        case .developmentCommit:
            return String(localized: "Development Commit")
        case .file:
            return String(localized: "File")
        case .pullRequest:
            return String(localized: "Pull Request")
        case .externalMCP:
            return String(localized: "External MCP")
        case .conversationSession:
            return String(localized: "Conversation Session")
        case .conversationTurn:
            return String(localized: "Conversation Turn")
        }
    }

    private static func dateLabel(for date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func displayDigest(for receipt: ExecutionReceipt) -> String {
        let digestInput = [
            "execution-receipt-history",
            receipt.id,
            receipt.runID,
            String(Int(receipt.createdAt.timeIntervalSince1970 * 1_000))
        ].joined(separator: ":")
        let digest = SHA256.hash(data: Data(digestInput.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return "receipt-\(hex)"
    }
}

public struct ExecutionReceiptHistoryExportDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var rowCount: Int
    public var rows: [ExecutionReceiptHistoryExportRow]

    public init(snapshot: ExecutionReceiptHistorySnapshot, exportedAt: Date) {
        self.schemaVersion = 1
        self.exportedAt = exportedAt
        self.rowCount = snapshot.rows.count
        self.rows = snapshot.rows.map(ExecutionReceiptHistoryExportRow.init(row:))
    }
}

public struct ExecutionReceiptHistoryExportRow: Codable, Equatable, Sendable {
    public var receiptDigest: String
    public var status: ExecutionReceiptStatus
    public var statusLabel: String
    public var toolLabel: String
    public var outcomeSummary: String
    public var usageLabel: String
    public var referenceSummary: String
    public var sourceSummary: String
    public var occurredAt: Date
    public var occurredAtLabel: String

    public init(row: ExecutionReceiptHistoryRow) {
        self.receiptDigest = row.id
        self.status = row.status
        self.statusLabel = row.statusLabel
        self.toolLabel = row.toolLabel
        self.outcomeSummary = row.outcomeSummary
        self.usageLabel = row.usageLabel
        self.referenceSummary = row.referenceSummary
        self.sourceSummary = row.sourceSummary
        self.occurredAt = row.occurredAt
        self.occurredAtLabel = row.occurredAtLabel
    }
}

public enum ExecutionReceiptHistoryExporter {
    public static func exportJSON(
        snapshot: ExecutionReceiptHistorySnapshot,
        exportedAt: Date = Date()
    ) throws -> Data {
        let document = ExecutionReceiptHistoryExportDocument(
            snapshot: snapshot,
            exportedAt: exportedAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}
