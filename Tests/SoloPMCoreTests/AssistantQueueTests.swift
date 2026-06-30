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
        XCTAssertNotNil(approved.approval?.approvalID)
        XCTAssertEqual(approved.approval?.reviewedContentFingerprint.count, 64)
        XCTAssertFalse(approved.approval?.reviewedContentFingerprint.contains("Create a task") ?? true)
        XCTAssertTrue(approved.approval?.reviewedContentFingerprint.allSatisfy(\.isHexDigit) ?? false)
    }

    func testQueueApprovalRequiresCostPreview() throws {
        let item = AssistantQueueItem(
            id: "missing-cost-preview",
            state: .waitingReview,
            payload: .actionPlan(makePlan()),
            riskLevel: .write,
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reviewReason: "Needs review.",
            redactedSummary: "Create task",
            requiredCapabilities: [.tool(.taskCreate), .providerExecutionApproval]
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .costPreviewRequiredBeforeApproval)
        }
    }

    func testManagedCostCapExceededBlocksApprovalAndRunning() throws {
        let withinCap = makeCostPreview(inputTokens: 500, outputTokens: 200, hardCapCents: 2)
        let overCap = makeCostPreview(inputTokens: 2_000, outputTokens: 1_000, hardCapCents: 0.10)
        let item = AssistantQueueItem(
            id: "managed-cost-cap",
            state: .waitingReview,
            payload: .actionPlan(makePlan()),
            riskLevel: .write,
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reviewReason: "Needs review.",
            redactedSummary: "Create task",
            requiredCapabilities: [.tool(.taskCreate), .providerExecutionApproval],
            costPreview: overCap
        )
        XCTAssertEqual(overCap.capStatus, .wouldExceedLimit)

        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .managedCostCapExceeded)
        }

        let approved = try AssistantQueueStateMachine.approve(
            AssistantQueueItem(
                id: item.id,
                state: .waitingReview,
                payload: item.payload,
                riskLevel: item.riskLevel,
                sourceTranscript: item.sourceTranscript,
                interpretationSummary: item.interpretationSummary,
                reviewReason: item.reviewReason,
                redactedSummary: item.redactedSummary,
                requiredCapabilities: item.requiredCapabilities,
                costPreview: withinCap
            ),
            reviewerID: "user-1"
        )
        let driftedOverCap = AssistantQueueItem(
            id: approved.id,
            state: approved.state,
            payload: approved.payload,
            riskLevel: approved.riskLevel,
            sourceTranscript: approved.sourceTranscript,
            interpretationSummary: approved.interpretationSummary,
            reviewReason: approved.reviewReason,
            redactedSummary: approved.redactedSummary,
            requiredCapabilities: approved.requiredCapabilities,
            approval: approved.approval,
            blockingReason: approved.blockingReason,
            costPreview: overCap
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.startRunning(driftedOverCap)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .managedCostCapExceeded)
        }
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
            blockingReason: approved.blockingReason,
            costPreview: approved.costPreview
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.startRunning(drifted)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .approvedPayloadChanged)
        }
    }

    func testStartRunningRejectsApprovalCostPreviewDrift() throws {
        let item = AssistantQueueItem(
            id: "cost-preview-drift",
            state: .waitingReview,
            payload: .actionPlan(makePlan()),
            riskLevel: .write,
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reviewReason: "Needs review.",
            redactedSummary: "Create task",
            requiredCapabilities: [.tool(.taskCreate), .providerExecutionApproval],
            costPreview: makeCostPreview(inputTokens: 500, outputTokens: 200)
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")
        let drifted = AssistantQueueItem(
            id: approved.id,
            state: .approved,
            payload: approved.payload,
            riskLevel: approved.riskLevel,
            sourceTranscript: approved.sourceTranscript,
            interpretationSummary: approved.interpretationSummary,
            reviewReason: approved.reviewReason,
            redactedSummary: approved.redactedSummary,
            requiredCapabilities: approved.requiredCapabilities,
            approval: approved.approval,
            blockingReason: approved.blockingReason,
            costPreview: makeCostPreview(inputTokens: 2_000, outputTokens: 1_000)
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.startRunning(drifted)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .approvedPayloadChanged)
        }
    }

    func testRunningItemCanCompleteOrFailAndThenBecomesTerminal() throws {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")
        let running = try AssistantQueueStateMachine.startRunning(approved)

        let done = try AssistantQueueStateMachine.markDone(running)
        XCTAssertEqual(done.state, .done)
        XCTAssertNil(done.blockingReason)
        XCTAssertEqual(done.approval, approved.approval)
        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(done, reviewerID: "user-1")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .terminalItemCannotTransition)
        }

        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Tool failed.")
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.blockingReason, "Tool failed.")
        XCTAssertEqual(failed.approval, approved.approval)
        XCTAssertThrowsError(try AssistantQueueStateMachine.approve(failed, reviewerID: "user-1")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .terminalItemCannotTransition)
        }
    }

    func testFailedActionPlanCanReopenForRetryReview() throws {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")
        let running = try AssistantQueueStateMachine.startRunning(approved)
        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Tool failed.")

        let retry = try AssistantQueueStateMachine.reopenFailedForReview(failed)

        XCTAssertEqual(retry.id, failed.id)
        XCTAssertEqual(retry.state, .waitingReview)
        XCTAssertEqual(retry.payload, failed.payload)
        XCTAssertEqual(retry.riskLevel, failed.riskLevel)
        XCTAssertEqual(retry.sourceTranscript, failed.sourceTranscript)
        XCTAssertEqual(retry.interpretationSummary, failed.interpretationSummary)
        XCTAssertEqual(retry.redactedSummary, failed.redactedSummary)
        XCTAssertEqual(retry.requiredCapabilities, failed.requiredCapabilities)
        XCTAssertNil(retry.approval)
        XCTAssertNil(retry.blockingReason)
        XCTAssertEqual(retry.reviewReason, "Retry after failed execution. Review this Assistant Queue item before running it again.")
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNotNil(failed.approval)
    }

    func testFailedTaskMutationAutomationRequestCanReopenForRetryReview() throws {
        let item = AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: "automation-retry-task-mutation",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            sourceClientID: "web",
            toolName: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            redactedArgumentSummary: "taskID=42, dueAt=2026-07-01T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .updateDueDate,
                dueAt: "2026-07-01T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
        let approved = try AssistantQueueStateMachine.approve(item, reviewerID: "user-1")
        let running = try AssistantQueueStateMachine.startRunning(approved)
        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Remote task update failed.")

        let retry = try AssistantQueueStateMachine.reopenFailedForReview(failed)

        XCTAssertEqual(retry.id, failed.id)
        XCTAssertEqual(retry.state, .waitingReview)
        XCTAssertEqual(retry.payload, failed.payload)
        XCTAssertEqual(retry.riskLevel, failed.riskLevel)
        XCTAssertNil(retry.approval)
        XCTAssertNil(retry.blockingReason)
        XCTAssertEqual(retry.reviewReason, "Retry after failed execution. Review this Assistant Queue item before running it again.")
        XCTAssertEqual(failed.state, .failed)
        XCTAssertNotNil(failed.approval)
    }

    func testRetryReviewRequiresSafeFailedRunnablePayload() throws {
        let waiting = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )
        let automation = AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: "automation-1",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            toolName: "task.create",
            redactedArgumentSummary: "Create remote task"
        ))
        let failedAutomation = AssistantQueueItem(
            id: automation.id,
            state: .failed,
            payload: automation.payload,
            riskLevel: automation.riskLevel,
            sourceTranscript: automation.sourceTranscript,
            interpretationSummary: automation.interpretationSummary,
            reviewReason: automation.reviewReason,
            redactedSummary: automation.redactedSummary,
            requiredCapabilities: automation.requiredCapabilities,
            approval: automation.approval,
            blockingReason: "Remote execution failed."
        )
        let runnableAutomation = AssistantQueueAdapter.makeItem(automationRequest: SyncAutomationRequestPayload(
            id: "automation-danger-runnable",
            source: .cloudRelay,
            approvalState: .pendingApproval,
            toolName: HostedMCPTaskToolName.taskDueDateUpdate.rawValue,
            redactedArgumentSummary: "taskID=42, dueAt=2026-07-01T09:00:00Z",
            taskMutation: SyncTaskMutationPayload(
                taskID: 42,
                operation: .updateDueDate,
                dueAt: "2026-07-01T09:00:00Z",
                source: .cloudRelay,
                approvalState: .pendingApproval
            )
        ))
        let dangerousAutomation = AssistantQueueItem(
            id: runnableAutomation.id,
            state: .failed,
            payload: runnableAutomation.payload,
            riskLevel: .danger,
            sourceTranscript: runnableAutomation.sourceTranscript,
            interpretationSummary: runnableAutomation.interpretationSummary,
            reviewReason: runnableAutomation.reviewReason,
            redactedSummary: runnableAutomation.redactedSummary,
            requiredCapabilities: runnableAutomation.requiredCapabilities,
            approval: runnableAutomation.approval,
            blockingReason: "Dangerous automation requests cannot be retried."
        )
        let danger = AssistantQueueItem(
            id: "danger-retry",
            state: .failed,
            payload: .actionPlan(makePlan(riskLevel: .danger)),
            riskLevel: .danger,
            sourceTranscript: "Delete everything",
            interpretationSummary: "Dangerous task intent.",
            reviewReason: "Danger retry.",
            redactedSummary: "Danger retry.",
            requiredCapabilities: [.tool(.taskDelete), .providerExecutionApproval],
            approval: nil,
            blockingReason: "Dangerous action plans cannot be retried."
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.reopenFailedForReview(waiting)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .retryRequiresFailedRunnablePayload)
        }
        XCTAssertThrowsError(try AssistantQueueStateMachine.reopenFailedForReview(failedAutomation)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .retryRequiresFailedRunnablePayload)
        }
        XCTAssertThrowsError(try AssistantQueueStateMachine.reopenFailedForReview(dangerousAutomation)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .dangerousPayloadCannotBeApproved)
        }
        XCTAssertThrowsError(try AssistantQueueStateMachine.reopenFailedForReview(danger)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .dangerousPayloadCannotBeApproved)
        }
    }

    func testDoneAndFailedRequireRunningState() throws {
        let item = AssistantQueueAdapter.makeItem(
            actionPlan: makePlan(),
            sourceTranscript: "Create a task",
            interpretationSummary: "Routed as task intent.",
            reason: "Needs review."
        )

        XCTAssertThrowsError(try AssistantQueueStateMachine.markDone(item)) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .runningRequiredBeforeCompletion)
        }
        XCTAssertThrowsError(try AssistantQueueStateMachine.markFailed(item, reason: "No run.")) { error in
            XCTAssertEqual(error as? AssistantQueueTransitionError, .runningRequiredBeforeCompletion)
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

        let edited = try AssistantQueueStateMachine.markEdited(approved, reason: "User changed the action scope.")

        XCTAssertEqual(edited.state, .waitingReview)
        XCTAssertNil(edited.approval)
        XCTAssertEqual(edited.reviewReason, "User changed the action scope.")
    }

    func testEditReviewDetailsRedactsTextAndRejectsNonEditableStates() throws {
        let approved = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(
                actionPlan: makePlan(summary: "Create a launch task"),
                sourceTranscript: "Create a task",
                interpretationSummary: "Routed as task intent.",
                reason: "Needs review."
            ),
            reviewerID: "user-1"
        )

        let edited = try AssistantQueueStateMachine.editReviewDetails(
            approved,
            reviewReason: "Use safer scope with sk-proj-secret",
            redactedSummary: "Create launch task in /Users/alice/private-roadmap.md"
        )

        XCTAssertEqual(edited.state, .waitingReview)
        XCTAssertNil(edited.approval)
        XCTAssertFalse(edited.reviewReason.contains("sk-proj-secret"))
        XCTAssertFalse(edited.redactedSummary.contains("/Users/alice/private-roadmap.md"))
        XCTAssertEqual(edited.redactedSummary, "Create launch task in [REDACTED_LOCAL_PATH]")
        XCTAssertEqual(edited.payload, approved.payload)
        XCTAssertEqual(edited.requiredCapabilities, approved.requiredCapabilities)

        let longSummary = String(repeating: "Detailed review surface. ", count: 80) + "Final detail."
        XCTAssertGreaterThan(longSummary.count, 1_200)
        let longEdited = try AssistantQueueStateMachine.editReviewDetails(
            approved,
            reviewReason: "Keep full review surface",
            redactedSummary: longSummary
        )
        XCTAssertEqual(longEdited.redactedSummary, longSummary)

        let running = try AssistantQueueStateMachine.startRunning(approved)
        let failed = try AssistantQueueStateMachine.markFailed(running, reason: "Tool failed.")
        for item in [
            running,
            failed,
            try AssistantQueueStateMachine.markDone(running),
            AssistantQueueStateMachine.reject(approved),
            AssistantQueueItem(
                id: "blocked-edit",
                state: .blocked,
                payload: .actionPlan(makePlan(summary: "Danger", actions: [
                    PlanAction(id: "danger", tool: .taskDelete, riskLevel: .danger)
                ])),
                riskLevel: .danger,
                sourceTranscript: nil,
                interpretationSummary: nil,
                reviewReason: "Dangerous item.",
                redactedSummary: "Danger",
                requiredCapabilities: [.tool(.taskDelete), .providerExecutionApproval],
                blockingReason: "Dangerous action plans cannot be approved from Assistant Queue."
            )
        ] {
            XCTAssertThrowsError(
                try AssistantQueueStateMachine.editReviewDetails(item, reviewReason: "Edit", redactedSummary: "Edit")
            ) { error in
                XCTAssertEqual(error as? AssistantQueueTransitionError, .editRequiresReviewableItem)
            }
        }
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

    private func makeCostPreview(
        inputTokens: Int,
        outputTokens: Int,
        hardCapCents: Double = 2
    ) -> AssistantQueueCostPreview {
        AssistantQueueCostRateCard(
            provider: "openai",
            modelName: "gpt-test",
            currencyCode: "USD",
            inputTokenCentsPerMillion: 100,
            outputTokenCentsPerMillion: 300
        ).preview(inputTokens: inputTokens, outputTokens: outputTokens, hardCapCents: hardCapCents)
    }
}
