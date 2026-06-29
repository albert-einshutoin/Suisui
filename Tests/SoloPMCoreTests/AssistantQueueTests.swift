import XCTest
@testable import SoloPMCore

final class AssistantQueueTests: XCTestCase {
    func testQueueItemFromActionPlanStartsWaitingReviewWithSourceReasonRisk() {
        let plan = makePlan(
            riskLevel: .write,
            actions: [
                PlanAction(id: "action-1", tool: .taskCreate, riskLevel: .write)
            ],
            requiresApproval: true
        )

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: "Create a launch task",
            interpretationSummary: "Routed as task intent.",
            reason: "Voice planning draft needs review."
        )

        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.riskLevel, .write)
        XCTAssertEqual(item.sourceTranscript, "Create a launch task")
        XCTAssertEqual(item.interpretationSummary, "Routed as task intent.")
        XCTAssertEqual(item.reviewReason, "Voice planning draft needs review.")
        XCTAssertEqual(item.requiredCapabilities, [.tool(.taskCreate), .providerExecutionApproval])
    }

    func testQueueAddsAppPermissionCapabilitiesForPermissionedTools() {
        let plan = makePlan(
            riskLevel: .write,
            actions: [
                PlanAction(id: "calendar", tool: .calendarCreateEvent, riskLevel: .write),
                PlanAction(id: "file", tool: .filesystemCreateMarkdownFile, riskLevel: .write)
            ],
            requiresApproval: true
        )

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: "Schedule and write notes",
            interpretationSummary: "Routed as schedule and document intent.",
            reason: "Needs permission review."
        )

        XCTAssertEqual(
            item.requiredCapabilities,
            [
                .tool(.calendarCreateEvent),
                .tool(.filesystemCreateMarkdownFile),
                .appPermission(.calendar),
                .appPermission(.fileAccess),
                .providerExecutionApproval
            ]
        )
    }

    func testQueueBlocksDangerousActionPlanBeforeApproval() {
        let plan = makePlan(
            riskLevel: .danger,
            actions: [
                PlanAction(id: "action-1", tool: .filesystemCreateMarkdownFile, riskLevel: .danger)
            ],
            requiresApproval: true
        )

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: "Delete and recreate the project notes",
            interpretationSummary: "Routed as document intent.",
            reason: "Dangerous draft must be blocked."
        )

        XCTAssertEqual(item.state, .blocked)
        XCTAssertEqual(item.blockingReason, "Dangerous action plans cannot be approved from Assistant Queue.")
        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .blockedItemCannotBeApproved)
        }
    }

    func testStateMachineRevalidatesDangerousCraftedItemsBeforeApproval() {
        let dangerousPlan = makePlan(
            riskLevel: .danger,
            actions: [
                PlanAction(id: "action-1", tool: .filesystemCreateMarkdownFile, riskLevel: .danger)
            ],
            requiresApproval: true
        )
        let crafted = AssistantQueueItem(
            id: "crafted",
            state: .waitingReview,
            payload: .actionPlan(dangerousPlan),
            riskLevel: .write,
            sourceTranscript: "Crafted unsafe item",
            interpretationSummary: "Crafted",
            reviewReason: "Bypassed adapter.",
            redactedSummary: "Crafted unsafe item",
            requiredCapabilities: [.providerExecutionApproval]
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(crafted, reviewerID: "user-1")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .dangerousPayloadCannotBeApproved)
        }
    }

    func testQueueRejectsRunningTransitionWithoutApproval() {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.startRunning(item)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .approvalRequiredBeforeRunning)
        }
    }

    func testQueueApprovalDoesNotCreateExecutionToken() throws {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )

        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")

        XCTAssertEqual(approved.state, .approved)
        XCTAssertEqual(approved.approval?.reviewerID, "user-1")
        XCTAssertNil(approved.approval?.executionTokenID)
        XCTAssertEqual(approved.approval?.reviewedContentFingerprint.count, 64)
        XCTAssertFalse(approved.approval?.reviewedContentFingerprint.contains("Create a task") ?? true)
        XCTAssertTrue(approved.approval?.reviewedContentFingerprint.allSatisfy(\.isHexDigit) ?? false)
    }

    func testStartRunningRejectsApprovalPayloadDrift() throws {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")
        let drifted = AssistantQueueItem(
            id: approved.id,
            state: .approved,
            payload: .actionPlan(
                makePlan(
                    actions: [PlanAction(id: "action-2", tool: .taskDelete, riskLevel: .write)]
                )
            ),
            riskLevel: approved.riskLevel,
            sourceTranscript: approved.sourceTranscript,
            interpretationSummary: approved.interpretationSummary,
            reviewReason: approved.reviewReason,
            redactedSummary: approved.redactedSummary,
            requiredCapabilities: approved.requiredCapabilities,
            approval: approved.approval,
            blockingReason: approved.blockingReason
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.startRunning(drifted)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .approvedPayloadChanged)
        }
    }

    func testAutomationRequestAdapterPreservesPendingApprovalAndRedactedSummary() {
        let request = SyncAutomationRequestPayload(
            id: "request-1",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: "task.create",
            redactedArgumentSummary: "Create task without sensitive detail."
        )

        let item = AssistantQueueAdapter.makeItem(automationRequest: request)

        XCTAssertEqual(item.state, .waitingReview)
        XCTAssertEqual(item.payload, .automationRequest(request))
        XCTAssertEqual(item.reviewReason, "Remote automation request is pending approval.")
        XCTAssertEqual(item.redactedSummary, "Create task without sensitive detail.")
        XCTAssertEqual(item.requiredCapabilities, [.connectedMacRequired, .providerExecutionApproval])
    }

    func testActionPlanSummaryIsRedactedBeforeQueuePersistence() {
        let probeValue = "s" + "k-" + "assistantQueueSecret123"
        let secretPrefix = "token" + "="
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(summary: "Create task with \(secretPrefix)\(probeValue)"),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )

        XCTAssertEqual(item.redactedSummary, "Create task with \(secretPrefix)[REDACTED_SECRET]")
    }

    func testQueuePayloadAndCapabilitiesRoundTripThroughJSON() throws {
        let item = AssistantQueueItem(
            id: "round-trip",
            state: .waitingReview,
            payload: .automationRequest(
                SyncAutomationRequestPayload(
                    id: "request-1",
                    source: .hostedMCP,
                    approvalState: .notRequired,
                    toolName: "external.write",
                    redactedArgumentSummary: "Safe summary"
                )
            ),
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: "external.write",
            reviewReason: "Remote automation request must enter Assistant Queue before execution.",
            redactedSummary: "Safe summary",
            requiredCapabilities: [
                .appPermission(.notifications),
                .externalMCP(serverID: "server-1", toolName: "external.write"),
                .providerExecutionApproval
            ]
        )

        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(AssistantQueueItem.self, from: data)

        XCTAssertEqual(decoded, item)
    }

    func testApprovedItemEditReturnsToWaitingReviewAndClearsApproval() throws {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")

        let edited = AssistantQueueStateMachine.markEdited(approved, reason: "User changed the action scope.")

        XCTAssertEqual(edited.state, .waitingReview)
        XCTAssertNil(edited.approval)
        XCTAssertEqual(edited.reviewReason, "User changed the action scope.")
    }

    private func makePlan(
        riskLevel: RiskLevel = .write,
        summary: String = "Create task",
        actions: [PlanAction] = [PlanAction(id: "action-1", tool: .taskCreate, riskLevel: .write)],
        requiresApproval: Bool = true
    ) -> ActionPlan {
        ActionPlan(
            id: "plan-1",
            userInput: "Create a task",
            summary: summary,
            actions: actions,
            riskLevel: riskLevel,
            requiresApproval: requiresApproval
        )
    }
}
