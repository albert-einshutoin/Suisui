import CryptoKit
import Foundation

public enum ManagedAIUsageLedgerStoreError: Error, Equatable, Sendable {
    case invalidStoredValue(column: String, value: String)
}

public protocol ManagedAIUsageLedgerStore: Sendable {
    func record(_ entry: ManagedAIUsageLedgerEntry) throws
    func list(limit: Int) throws -> [ManagedAIUsageLedgerEntry]
    func usageTotals(
        currencyCode: String,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> ManagedAIUsageLedgerTotals
}

public struct ManagedAIUsageLedgerTotals: Equatable, Sendable {
    public var currencyCode: String
    public var dailyCostCents: Double
    public var monthlyCostCents: Double
    public var workspaceCostCents: Double

    public init(
        currencyCode: String,
        dailyCostCents: Double = 0,
        monthlyCostCents: Double = 0,
        workspaceCostCents: Double = 0
    ) {
        self.currencyCode = Self.normalizedCurrencyCode(currencyCode)
        self.dailyCostCents = Self.normalizedCost(dailyCostCents)
        self.monthlyCostCents = Self.normalizedCost(monthlyCostCents)
        self.workspaceCostCents = Self.normalizedCost(workspaceCostCents)
    }

    public static func from(
        entries: [ManagedAIUsageLedgerEntry],
        currencyCode: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> ManagedAIUsageLedgerTotals {
        let normalizedCurrencyCode = normalizedCurrencyCode(currencyCode)
        let sameCurrencyManagedEntries = entries.filter { entry in
            entry.billingMode == .suisuiManaged && entry.currencyCode == normalizedCurrencyCode
        }
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let monthInterval = calendar.dateInterval(of: .month, for: referenceDate)

        return ManagedAIUsageLedgerTotals(
            currencyCode: normalizedCurrencyCode,
            dailyCostCents: sameCurrencyManagedEntries
                .filter { dayInterval?.contains($0.occurredAt) == true }
                .reduce(0) { $0 + $1.costCents },
            monthlyCostCents: sameCurrencyManagedEntries
                .filter { monthInterval?.contains($0.occurredAt) == true }
                .reduce(0) { $0 + $1.costCents },
            workspaceCostCents: sameCurrencyManagedEntries.reduce(0) { $0 + $1.costCents }
        )
    }

    static func normalizedCurrencyCode(_ value: String) -> String {
        let redacted = AssistantQueueCostPreview.redactedMetadataText(value)
        let trimmed = redacted.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "USD" : trimmed
    }

    private static func normalizedCost(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }
}

public extension ManagedAIUsageLedgerStore {
    func usageTotals(
        currencyCode: String,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> ManagedAIUsageLedgerTotals {
        // Test doubles can rely on the list contract. The production SQLite
        // store overrides this with aggregate SQL so workspace caps are not
        // limited by the read-model pagination used by UI history.
        ManagedAIUsageLedgerTotals.from(
            entries: try list(limit: 500),
            currencyCode: currencyCode,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }
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
              costPreview.billingMode == .suisuiManaged,
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
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?,
                ?
            )
            ON CONFLICT(source_receipt_digest) DO NOTHING
            ON CONFLICT(assistant_queue_item_digest) DO NOTHING;
            """,
            parameters: [
                .text(entry.sourceReceiptDigest),
                SQLiteValue(entry.assistantQueueItemDigest),
                .text(entry.billingMode.rawValue),
                .text(entry.provider),
                .text(entry.modelName),
                .text(entry.usageState.rawValue),
                SQLiteValue(entry.inputTokens),
                SQLiteValue(entry.outputTokens),
                .real(entry.costCents),
                .text(entry.currencyCode),
                .text(Self.timestamp(entry.occurredAt))
            ]
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
            LIMIT ?;
            """,
            parameters: [.integer(Int64(min(max(limit, 1), 500)))]
        ).map(entry(row:))
    }

    public func usageTotals(
        currencyCode: String,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> ManagedAIUsageLedgerTotals {
        lock.lock()
        defer { lock.unlock() }

        let normalizedCurrencyCode = ManagedAIUsageLedgerTotals.normalizedCurrencyCode(currencyCode)
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let monthInterval = calendar.dateInterval(of: .month, for: referenceDate)
        let baseCondition = """
            billing_mode = ?
            AND currency_code = ?
            """
        let baseParameters: [SQLiteValue] = [
            .text(AssistantQueueCostBillingMode.suisuiManaged.rawValue),
            .text(normalizedCurrencyCode)
        ]
        let dailyCondition = intervalCondition(
            baseCondition: baseCondition,
            interval: dayInterval
        )
        let monthlyCondition = intervalCondition(
            baseCondition: baseCondition,
            interval: monthInterval
        )

        return ManagedAIUsageLedgerTotals(
            currencyCode: normalizedCurrencyCode,
            dailyCostCents: try sumCostCents(
                where: dailyCondition.condition,
                parameters: baseParameters + dailyCondition.parameters
            ),
            monthlyCostCents: try sumCostCents(
                where: monthlyCondition.condition,
                parameters: baseParameters + monthlyCondition.parameters
            ),
            workspaceCostCents: try sumCostCents(where: baseCondition, parameters: baseParameters)
        )
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

    private func sumCostCents(where condition: String, parameters: [SQLiteValue]) throws -> Double {
        let rows = try connection.queryRows(
            """
            SELECT COALESCE(SUM(cost_cents), 0) AS total
            FROM managed_ai_usage_ledger
            WHERE \(condition);
            """,
            parameters: parameters
        )
        return Double(rows.first?["total"] ?? "0") ?? 0
    }

    private func intervalCondition(
        baseCondition: String,
        interval: DateInterval?
    ) -> (condition: String, parameters: [SQLiteValue]) {
        guard let interval else {
            return ("\(baseCondition) AND 1 = 0", [])
        }
        return (
            """
            \(baseCondition)
            AND occurred_at >= ?
            AND occurred_at < ?
            """,
            [
                .text(Self.timestamp(interval.start)),
                .text(Self.timestamp(interval.end))
            ]
        )
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func date(from value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}
