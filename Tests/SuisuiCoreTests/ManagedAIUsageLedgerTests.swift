import XCTest
@testable import SuisuiCore

final class ManagedAIUsageLedgerTests: XCTestCase {
    func testLedgerEntryInitializerHashesRawIdentifiersAndClampsInvalidCost() {
        let entry = ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: "receipt-sk-secret-/Users/alice/private",
            assistantQueueItemDigest: "queue-sk-secret-/Users/alice/private",
            billingMode: .suisuiManaged,
            provider: "openai",
            modelName: "gpt-managed",
            usageState: .estimated,
            inputTokens: 100,
            outputTokens: 20,
            costCents: .infinity,
            currencyCode: "USD",
            occurredAt: Date(timeIntervalSince1970: 125)
        )

        XCTAssertTrue(entry.sourceReceiptDigest.hasPrefix("sha256:"))
        XCTAssertTrue(entry.assistantQueueItemDigest?.hasPrefix("sha256:") == true)
        XCTAssertFalse(entry.sourceReceiptDigest.contains("receipt-sk-secret"))
        XCTAssertFalse(entry.assistantQueueItemDigest?.contains("queue-sk-secret") == true)
        XCTAssertEqual(entry.costCents, 0)
    }

    func testSQLiteLedgerPersistsManagedEntriesIdempotentlyWithoutRawIdentifiers() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteManagedAIUsageLedgerStore(connection: connection)
        let entry = ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: "receipt-sk-secret-/Users/alice/private"),
            assistantQueueItemDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "assistant_queue_item", value: "queue-sk-secret-/Users/alice/private"),
            billingMode: .suisuiManaged,
            provider: "openai sk-secret /Users/alice/private",
            modelName: "gpt-managed",
            usageState: .estimated,
            inputTokens: 1_000,
            outputTokens: 500,
            costCents: 0.25,
            currencyCode: "USD",
            occurredAt: Date(timeIntervalSince1970: 126)
        )
        let retryEntry = ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: "receipt-retry-sk-secret-/Users/alice/private"),
            assistantQueueItemDigest: entry.assistantQueueItemDigest,
            billingMode: .suisuiManaged,
            provider: "openai",
            modelName: "gpt-managed",
            usageState: .estimated,
            inputTokens: 9_999,
            outputTokens: 9_999,
            costCents: 9.99,
            currencyCode: "USD",
            occurredAt: Date(timeIntervalSince1970: 127)
        )

        try store.record(entry)
        try store.record(entry)
        try store.record(retryEntry)

        let entries = try store.list(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.sourceReceiptDigest, entry.sourceReceiptDigest)
        XCTAssertEqual(entries.first?.assistantQueueItemDigest, entry.assistantQueueItemDigest)
        XCTAssertEqual(entries.first?.provider, "openai [REDACTED_SECRET] [REDACTED_LOCAL_PATH]")
        XCTAssertEqual(entries.first?.costCents ?? -1, 0.25, accuracy: 0.0001)

        let rawRows = try connection.queryRows("SELECT * FROM managed_ai_usage_ledger;")
        let rawStorage = String(describing: rawRows)
        XCTAssertFalse(rawStorage.contains("receipt-sk-secret"))
        XCTAssertFalse(rawStorage.contains("queue-sk-secret"))
        XCTAssertFalse(rawStorage.contains("/Users/alice"))
        XCTAssertFalse(rawStorage.contains("sk-secret"))
    }

    func testSQLiteLedgerUsageTotalsAggregateManagedUsageByUTCPeriodAndCurrency() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let store = SQLiteManagedAIUsageLedgerStore(connection: connection)

        try store.record(ledgerEntry(id: "same-day", costCents: 20, currencyCode: "USD", occurredAt: "2026-07-15T09:00:00Z"))
        try store.record(ledgerEntry(id: "same-month", costCents: 30, currencyCode: "USD", occurredAt: "2026-07-01T09:00:00Z"))
        try store.record(ledgerEntry(id: "prior-month", costCents: 40, currencyCode: "USD", occurredAt: "2026-06-30T23:59:00Z"))
        try store.record(ledgerEntry(id: "other-currency", costCents: 999, currencyCode: "EUR", occurredAt: "2026-07-15T09:00:00Z"))

        let totals = try store.usageTotals(
            currencyCode: "usd",
            referenceDate: isoDate("2026-07-15T10:00:00Z"),
            calendar: ManagedAIBillingSettings.usageLedgerCalendar()
        )

        XCTAssertEqual(totals.currencyCode, "USD")
        XCTAssertEqual(totals.dailyCostCents, 20)
        XCTAssertEqual(totals.monthlyCostCents, 50)
        XCTAssertEqual(totals.workspaceCostCents, 90)
    }

    func testLedgerEntryFactorySkipsLocalAndProviderBilledPreviews() {
        let local = AssistantQueueCostPreview.localOnly()
        let providerBilled = AssistantQueueCostPreview.userProviderBilled(
            provider: "openai",
            modelName: "gpt-5.5",
            observedUsage: ExecutionReceiptUsage(inputTokens: 10, outputTokens: 5, isEstimated: false)
        )
        let receipt = ExecutionReceipt(
            id: "receipt-provider",
            runID: "run-provider",
            status: .succeeded,
            inputPreview: "redacted",
            outputSummary: "done",
            usage: providerBilled.executionReceiptUsage,
            visibleSurfaces: [.auditLog]
        )

        XCTAssertNil(ManagedAIUsageLedgerEntry.makeAssistantQueueEntry(
            itemID: "queue-local",
            costPreview: local,
            receipt: receipt,
            occurredAt: Date(timeIntervalSince1970: 127)
        ))
        XCTAssertNil(ManagedAIUsageLedgerEntry.makeAssistantQueueEntry(
            itemID: "queue-provider",
            costPreview: providerBilled,
            receipt: receipt,
            occurredAt: Date(timeIntervalSince1970: 128)
        ))
    }

    func testBillingSettingsProjectsLedgerTotalsAgainstDailyMonthlyAndWorkspaceCaps() {
        let preview = AssistantQueueCostPreview(
            billingMode: .suisuiManaged,
            state: .estimated,
            estimatedCostCents: 15,
            currencyCode: "USD",
            capStatus: .withinLimit
        )
        let totals = ManagedAIUsageLedgerTotals(
            currencyCode: "usd",
            dailyCostCents: 20,
            monthlyCostCents: 90,
            workspaceCostCents: 120
        )

        let monthlyProjection = ManagedAIBillingSettings(
            isEnabled: true,
            dailyCapCents: 100,
            monthlyCapCents: 100,
            workspaceCapCents: 500
        ).firstExceededUsageCap(totals: totals, pendingCostPreview: preview)
        XCTAssertEqual(monthlyProjection?.scope, .monthly)
        XCTAssertEqual(monthlyProjection?.projectedCents, 105)

        let workspaceProjection = ManagedAIBillingSettings(
            isEnabled: true,
            dailyCapCents: 100,
            monthlyCapCents: 200,
            workspaceCapCents: 130
        ).firstExceededUsageCap(totals: totals, pendingCostPreview: preview)
        XCTAssertEqual(workspaceProjection?.scope, .workspace)
        XCTAssertEqual(workspaceProjection?.projectedCents, 135)

        let withinLimit = ManagedAIBillingSettings(
            isEnabled: true,
            dailyCapCents: 100,
            monthlyCapCents: 200,
            workspaceCapCents: 200
        ).firstExceededUsageCap(totals: totals, pendingCostPreview: preview)
        XCTAssertNil(withinLimit)
    }

    private func ledgerEntry(
        id: String,
        billingMode: AssistantQueueCostBillingMode = .suisuiManaged,
        costCents: Double,
        currencyCode: String,
        occurredAt: String
    ) -> ManagedAIUsageLedgerEntry {
        ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "receipt", value: id),
            assistantQueueItemDigest: ManagedAIUsageLedgerEntry.digestIdentifier(kind: "assistant_queue_item", value: id),
            billingMode: billingMode,
            provider: "openai",
            modelName: "gpt-managed",
            usageState: .estimated,
            inputTokens: 1,
            outputTokens: 1,
            costCents: costCents,
            currencyCode: currencyCode,
            occurredAt: isoDate(occurredAt)
        )
    }

    private func isoDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
