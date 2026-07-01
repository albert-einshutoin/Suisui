import CryptoKit
import Foundation

public enum ManagedAIUsageLedgerStoreError: Error, Equatable, Sendable {
    case invalidStoredValue(column: String, value: String)
}

public protocol ManagedAIUsageLedgerStore: Sendable {
    func record(_ entry: ManagedAIUsageLedgerEntry) throws
    func list(limit: Int) throws -> [ManagedAIUsageLedgerEntry]
}

public struct ManagedAIUsageLedgerEntry: Codable, Equatable, Sendable {
    public var sourceReceiptDigest: String
    public var assistantQueueItemDigest: String?
    public var billingMode: AssistantQueueCostBillingMode
    public var provider: String
    public var modelName: String
    public var usageState: ExecutionReceiptUsageState
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costCents: Double
    public var currencyCode: String
    public var occurredAt: Date

    public init(
        sourceReceiptDigest: String,
        assistantQueueItemDigest: String?,
        billingMode: AssistantQueueCostBillingMode,
        provider: String,
        modelName: String,
        usageState: ExecutionReceiptUsageState,
        inputTokens: Int?,
        outputTokens: Int?,
        costCents: Double,
        currencyCode: String,
        occurredAt: Date
    ) {
        self.sourceReceiptDigest = Self.normalizedDigest(sourceReceiptDigest)
        self.assistantQueueItemDigest = assistantQueueItemDigest.map(Self.normalizedDigest)
        self.billingMode = billingMode
        self.provider = Self.redactedText(provider, fallback: "unknown")
        self.modelName = Self.redactedText(modelName, fallback: "unknown")
        self.usageState = usageState
        self.inputTokens = inputTokens.map { max(0, $0) }
        self.outputTokens = outputTokens.map { max(0, $0) }
        self.costCents = costCents.isFinite ? max(0, costCents) : 0
        self.currencyCode = Self.redactedText(currencyCode, fallback: "USD").uppercased()
        self.occurredAt = occurredAt
    }

    public static func makeAssistantQueueEntry(
        itemID: String,
        costPreview: AssistantQueueCostPreview?,
        receipt: ExecutionReceipt,
        occurredAt: Date
    ) -> ManagedAIUsageLedgerEntry? {
        guard let costPreview,
              costPreview.billingMode == .soloPMManaged,
              let costCents = costPreview.estimatedCostCents,
              let currencyCode = costPreview.currencyCode
        else {
            return nil
        }

        let model = costPreview.model ?? receipt.model ?? ExecutionReceiptModel(provider: "unknown", name: "unknown")
        let usage = costPreview.executionReceiptUsage
        return ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: digestIdentifier(kind: "receipt", value: receipt.id),
            assistantQueueItemDigest: digestIdentifier(kind: "assistant_queue_item", value: itemID),
            billingMode: costPreview.billingMode,
            provider: model.provider,
            modelName: model.name,
            usageState: usage.state,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            costCents: costCents,
            currencyCode: currencyCode,
            occurredAt: occurredAt
        )
    }

    public static func digestIdentifier(kind: String, value: String) -> String {
        let scopedValue = "\(kind):\(value)"
        let digest = SHA256.hash(data: Data(scopedValue.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedDigest(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return digestIdentifier(kind: "empty", value: "")
        }
        guard trimmed.range(of: #"^sha256:[a-fA-F0-9]{64}$"#, options: .regularExpression) != nil else {
            // Ledger identifiers are always irreversible digests so billing
            // storage cannot accidentally retain queue, receipt, or provider IDs.
            return digestIdentifier(kind: "ledger_identifier", value: trimmed)
        }
        return trimmed.lowercased()
    }

    private static func redactedText(_ value: String, fallback: String) -> String {
        let redacted = metadataSecretPatternRedacted(AssistantQueueCostPreview.redactedMetadataText(value))
        let trimmed = redacted.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func metadataSecretPatternRedacted(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\bsk-[A-Za-z0-9_-]+\b"#,
            with: "[REDACTED_SECRET]",
            options: .regularExpression
        )
    }
}

public final class SQLiteManagedAIUsageLedgerStore: ManagedAIUsageLedgerStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public convenience init(path: String, migrations: [DatabaseMigration] = CoreMigrations.current) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    public func record(_ entry: ManagedAIUsageLedgerEntry) throws {
        lock.lock()
        defer { lock.unlock() }

        // Queue digest is the billing idempotency key. The receipt digest keeps
        // audit provenance for the execution that first made the charge durable.
        try connection.execute(
            """
            INSERT INTO managed_ai_usage_ledger (
                source_receipt_digest,
                assistant_queue_item_digest,
                billing_mode,
                provider,
                model_name,
                usage_state,
                input_tokens,
                output_tokens,
                cost_cents,
                currency_code,
                occurred_at
            )
            VALUES (
                '\(Self.escape(entry.sourceReceiptDigest))',
                \(Self.sqlString(entry.assistantQueueItemDigest)),
                '\(Self.escape(entry.billingMode.rawValue))',
                '\(Self.escape(entry.provider))',
                '\(Self.escape(entry.modelName))',
                '\(Self.escape(entry.usageState.rawValue))',
                \(Self.sqlInt(entry.inputTokens)),
                \(Self.sqlInt(entry.outputTokens)),
                \(entry.costCents),
                '\(Self.escape(entry.currencyCode))',
                '\(Self.escape(Self.timestamp(entry.occurredAt)))'
            )
            ON CONFLICT(source_receipt_digest) DO NOTHING
            ON CONFLICT(assistant_queue_item_digest) DO NOTHING;
            """
        )
    }

    public func list(limit: Int = 100) throws -> [ManagedAIUsageLedgerEntry] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT *
            FROM managed_ai_usage_ledger
            ORDER BY occurred_at DESC, source_receipt_digest ASC
            LIMIT \(min(max(limit, 1), 500));
            """
        ).map(entry(row:))
    }

    private func entry(row: [String: String]) throws -> ManagedAIUsageLedgerEntry {
        guard let rawBillingMode = row["billing_mode"],
              let billingMode = AssistantQueueCostBillingMode(rawValue: rawBillingMode) else {
            throw ManagedAIUsageLedgerStoreError.invalidStoredValue(column: "billing_mode", value: row["billing_mode"] ?? "")
        }
        guard let rawUsageState = row["usage_state"],
              let usageState = ExecutionReceiptUsageState(rawValue: rawUsageState) else {
            throw ManagedAIUsageLedgerStoreError.invalidStoredValue(column: "usage_state", value: row["usage_state"] ?? "")
        }
        guard let rawCost = row["cost_cents"],
              let costCents = Double(rawCost) else {
            throw ManagedAIUsageLedgerStoreError.invalidStoredValue(column: "cost_cents", value: row["cost_cents"] ?? "")
        }
        guard let rawOccurredAt = row["occurred_at"],
              let occurredAt = Self.date(from: rawOccurredAt) else {
            throw ManagedAIUsageLedgerStoreError.invalidStoredValue(column: "occurred_at", value: row["occurred_at"] ?? "")
        }

        return ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: row["source_receipt_digest"] ?? "",
            assistantQueueItemDigest: Self.optionalString(row["assistant_queue_item_digest"]),
            billingMode: billingMode,
            provider: row["provider"] ?? "",
            modelName: row["model_name"] ?? "",
            usageState: usageState,
            inputTokens: Self.optionalInt(row["input_tokens"]),
            outputTokens: Self.optionalInt(row["output_tokens"]),
            costCents: costCents,
            currencyCode: row["currency_code"] ?? "USD",
            occurredAt: occurredAt
        )
    }

    private static func optionalString(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func optionalInt(_ value: String?) -> Int? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return Int(value)
    }

    private static func sqlString(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }
        return "'\(escape(value))'"
    }

    private static func sqlInt(_ value: Int?) -> String {
        value.map(String.init) ?? "NULL"
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
