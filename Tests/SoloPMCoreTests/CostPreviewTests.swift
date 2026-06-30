import XCTest
@testable import SoloPMCore

final class CostPreviewTests: XCTestCase {
    func testManagedRateCardEstimatesTokenCostAndCapStatus() {
        let rateCard = AssistantQueueCostRateCard(
            provider: "openai",
            modelName: "gpt-test",
            currencyCode: "USD",
            inputTokenCentsPerMillion: 100,
            outputTokenCentsPerMillion: 300
        )

        let preview = rateCard.preview(
            inputTokens: 1_000,
            outputTokens: 500,
            hardCapCents: 1
        )

        XCTAssertEqual(preview.billingMode, .soloPMManaged)
        XCTAssertEqual(preview.state, .estimated)
        XCTAssertEqual(preview.usage.inputTokens, 1_000)
        XCTAssertEqual(preview.usage.outputTokens, 500)
        XCTAssertEqual(preview.estimatedCostCents ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(preview.currencyCode, "USD")
        XCTAssertEqual(preview.capStatus, .withinLimit)
        XCTAssertEqual(preview.model, ExecutionReceiptModel(provider: "openai", name: "gpt-test"))
        XCTAssertTrue(preview.allowsApprovalAndRun)
        XCTAssertTrue(preview.reviewLabel.contains("Preview only"))
        XCTAssertTrue(preview.reviewLabel.contains("not charged yet"))

        let usage = preview.executionReceiptUsage
        XCTAssertEqual(usage.inputTokens, 1_000)
        XCTAssertEqual(usage.outputTokens, 500)
        XCTAssertEqual(usage.estimatedCostCents ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertEqual(usage.currencyCode, "USD")
        XCTAssertEqual(usage.state, .estimated)
    }

    func testManagedRateCardFlagsHardCapExceedingPreview() {
        let rateCard = AssistantQueueCostRateCard(
            provider: "openai",
            modelName: "gpt-test",
            currencyCode: "USD",
            inputTokenCentsPerMillion: 100,
            outputTokenCentsPerMillion: 300
        )

        let preview = rateCard.preview(
            inputTokens: 1_000,
            outputTokens: 500,
            hardCapCents: 0.10
        )

        XCTAssertEqual(preview.capStatus, .wouldExceedLimit)
        XCTAssertFalse(preview.allowsApprovalAndRun)
    }

    func testLocalAndBYOKPreviewsNeverClaimSoloPMManagedCharges() {
        let local = AssistantQueueCostPreview.localOnly()
        let byok = AssistantQueueCostPreview.userProviderBilled(
            provider: "anthropic",
            modelName: "claude-test"
        )

        XCTAssertEqual(local.billingMode, .localOnly)
        XCTAssertEqual(local.state, .unavailable)
        XCTAssertNil(local.estimatedCostCents)
        XCTAssertEqual(local.executionReceiptUsage.state, .unavailable)
        XCTAssertTrue(local.allowsApprovalAndRun)

        XCTAssertEqual(byok.billingMode, .userProviderBilled)
        XCTAssertEqual(byok.state, .unavailable)
        XCTAssertNil(byok.estimatedCostCents)
        XCTAssertEqual(byok.model, ExecutionReceiptModel(provider: "anthropic", name: "claude-test"))
        XCTAssertEqual(byok.executionReceiptUsage.state, .unavailable)
        XCTAssertTrue(byok.allowsApprovalAndRun)
    }

    func testPreviewRedactsProviderModelAndNoteBeforePersistence() throws {
        let preview = AssistantQueueCostPreview.userProviderBilled(
            provider: "anthropic sk-proj-providerSecret1234567890",
            modelName: "claude sk-proj-modelSecret1234567890",
            note: "Do not persist sk-proj-noteSecret1234567890"
        )

        let data = try JSONEncoder().encode(preview)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertFalse(json.contains("providerSecret"))
        XCTAssertFalse(json.contains("modelSecret"))
        XCTAssertFalse(json.contains("noteSecret"))
        XCTAssertTrue(json.contains("[REDACTED_SECRET]"))
    }
}
