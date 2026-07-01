import XCTest
@testable import SoloPMCore

final class ManagedAIUsageLedgerTests: XCTestCase {
    func testLedgerEntryInitializerHashesRawIdentifiersAndClampsInvalidCost() {
        let entry = ManagedAIUsageLedgerEntry(
            sourceReceiptDigest: "receipt-sk-secret-/Users/alice/private",
            assistantQueueItemDigest: "queue-sk-secret-/Users/alice/private",
            billingMode: .soloPMManaged,
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
            billingMode: .soloPMManaged,
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
            billingMode: .soloPMManaged,
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
}
