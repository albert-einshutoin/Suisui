import SuisuiCore
import XCTest

final class PublicAPISourceCompatibilityTests: XCTestCase {
    func testLegacyAssistantQueueStoreConformerCompilesAndFailsClosedForAtomicInsert() throws {
        let store = LegacyCompatibleAssistantQueueStore()

        XCTAssertThrowsError(try store.insertIfAbsent(makeQueueItem())) { error in
            XCTAssertEqual(error as? AssistantQueueStoreError, .saveFailed)
        }
        XCTAssertTrue(store.savedItems.isEmpty)
    }

    func testLegacyPublicInitializersRemainAvailable() {
        let requirement = AccessibilityFocusPathRequirement(
            requiredNodeIDs: ["legacy-node"],
            dynamicRequiredNodeIDPrefixes: ["legacy"]
        )
        let row = AssistantQueueReadModelRow(
            id: "legacy-row",
            state: .waitingReview,
            stateLabel: "Waiting Review",
            riskLabel: "Write",
            title: "Legacy row",
            redactedSummary: "Legacy row",
            sourcePreview: nil,
            reviewReason: "Compatibility",
            capabilityLabels: [],
            blockingReason: nil,
            canApprove: true,
            canRun: false,
            canDefer: true,
            canEdit: true,
            canRetry: false,
            canReject: true
        )

        XCTAssertEqual(requirement.requiredNodeIDs, ["legacy-node"])
        XCTAssertNil(row.mutationRevision)
    }

    func testOriginalAccessibilityFindingKindSwitchRemainsExhaustive() {
        XCTAssertEqual(legacyFindingLabel(.missingRequiredNode), "missing")
    }

    func testStaleReviewErrorIsPubliclyConstructible() {
        XCTAssertEqual(
            AssistantQueueStaleReviewError(),
            AssistantQueueStaleReviewError()
        )
    }

    private func legacyFindingLabel(_ kind: AccessibilityFocusPathFindingKind) -> String {
        switch kind {
        case .missingRequiredNode:
            "missing"
        case .disabledRequiredNode:
            "disabled"
        case .outOfOrderRequiredNode:
            "out-of-order"
        case .duplicateNodeID:
            "duplicate"
        case .blankNodeID:
            "blank"
        case .unlabeledRequiredNode:
            "unlabeled-required"
        case .unlabeledInteractiveNode:
            "unlabeled-interactive"
        case .genericButtonWithoutHelp:
            "generic-button"
        case .missingDestructiveConfirmation:
            "missing-confirmation"
        }
    }

    private func makeQueueItem() -> AssistantQueueItem {
        AssistantQueueItem(
            id: "legacy-store-item",
            state: .waitingReview,
            payload: .actionPlan(
                ActionPlan(
                    id: "legacy-store-plan",
                    userInput: "Verify legacy store compatibility",
                    summary: "Verify legacy store compatibility",
                    actions: [],
                    riskLevel: .read,
                    requiresApproval: false
                )
            ),
            riskLevel: .read,
            sourceTranscript: nil,
            interpretationSummary: nil,
            reviewReason: "Compatibility",
            redactedSummary: "Compatibility",
            requiredCapabilities: [],
            costPreview: .localOnly()
        )
    }
}

private final class LegacyCompatibleAssistantQueueStore: AssistantQueueStore {
    private(set) var savedItems: [AssistantQueueItem] = []

    func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        savedItems.append(item)
        return item
    }

    func get(id: String) throws -> AssistantQueueItem {
        throw AssistantQueueStoreError.notFound(id)
    }

    func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] {
        savedItems.filter { filter.includes($0.state) }
    }

    func stateCounts() throws -> AssistantQueueStateCounts {
        AssistantQueueStateCounts(items: savedItems)
    }

    func transition(
        id: String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) throws -> AssistantQueueItem {
        throw AssistantQueueStoreError.notFound(id)
    }
}
