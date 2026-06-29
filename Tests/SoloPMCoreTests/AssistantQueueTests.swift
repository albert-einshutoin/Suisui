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
        actions: [PlanAction] = [PlanAction(id: "action-1", tool: .taskCreate, riskLevel: .write)],
        requiresApproval: Bool = true
    ) -> ActionPlan {
        ActionPlan(
            id: "plan-1",
            userInput: "Create a task",
            summary: "Create task",
            actions: actions,
            riskLevel: riskLevel,
            requiresApproval: requiresApproval
        )
    }
}
