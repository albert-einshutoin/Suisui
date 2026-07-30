import XCTest
@testable import SuisuiCore

final class ConversationActionLinkCoordinatorTests: XCTestCase {
    func testGivenReviewedMultiTaskPlanWhenCreateLinkThenBindsEveryTaskSnapshot() throws {
        let plan = ActionPlan(
            id: "plan-multi-task-update",
            userInput: "Update tasks 41 and 42",
            summary: "Update two tasks",
            actions: [
                PlanAction(
                    id: "action-update-41",
                    tool: .taskUpdate,
                    arguments: [
                        "id": .number(41),
                        "title": .string("Updated 41"),
                    ]
                ),
                PlanAction(
                    id: "action-complete-42",
                    tool: .taskComplete,
                    arguments: ["id": .number(42)]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let queueItem = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: "Review",
            costPreview: .localOnly()
        )

        let link = try ConversationActionLinkCoordinator().makeReviewLink(
            sessionID: UUID(),
            sourceTurnID: UUID(),
            plan: plan,
            queueItem: queueItem,
            taskSnapshotFingerprintProvider: {
                "task:\($0):v1"
            }
        )

        XCTAssertEqual(
            link.taskSnapshots,
            [
                ConversationTaskSnapshot(
                    taskID: 41,
                    fingerprint: "task:41:v1"
                ),
                ConversationTaskSnapshot(
                    taskID: 42,
                    fingerprint: "task:42:v1"
                ),
            ]
        )
    }

    func testGivenTaskMutationWithoutStableIDWhenCreateLinkThenFailsClosed() throws {
        let plan = ActionPlan(
            id: "plan-unbound-task-update",
            userInput: "Update a task",
            summary: "Update unresolved task",
            actions: [
                PlanAction(
                    id: "action-unbound-task-update",
                    tool: .taskUpdate,
                    arguments: ["title": .string("Updated")]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let queueItem = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: "Review",
            costPreview: .localOnly()
        )

        XCTAssertThrowsError(
            try ConversationActionLinkCoordinator().makeReviewLink(
                sessionID: UUID(),
                sourceTurnID: UUID(),
                plan: plan,
                queueItem: queueItem
            )
        ) { error in
            XCTAssertEqual(
                error as? ConversationActionLinkTaskTargetUnavailableError,
                ConversationActionLinkTaskTargetUnavailableError(
                    actionID: "action-unbound-task-update"
                )
            )
        }
    }

    func testGivenReviewedTaskUpdateWhenCreateLinkThenBindsQueueAndTaskSnapshot() throws {
        let plan = ActionPlan(
            id: "plan-update",
            userInput: "Update task 42",
            summary: "Update task",
            actions: [
                PlanAction(
                    id: "action-update",
                    tool: .taskUpdate,
                    arguments: [
                        "id": .number(42),
                        "title": .string("Updated"),
                    ]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let queueItem = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: "Review",
            costPreview: .localOnly()
        )

        let link = try ConversationActionLinkCoordinator().makeReviewLink(
            sessionID: UUID(),
            sourceTurnID: UUID(),
            plan: plan,
            queueItem: queueItem,
            taskSnapshotFingerprintProvider: { id in
                XCTAssertEqual(id, 42)
                return "task:v1"
            }
        )

        XCTAssertEqual(link.actionPlanID, "plan-update")
        XCTAssertEqual(link.assistantQueueItemID, queueItem.id)
        XCTAssertEqual(link.taskID, 42)
        XCTAssertEqual(link.taskSnapshotFingerprint, "task:v1")
        XCTAssertEqual(link.operation, .taskUpdated)
        XCTAssertEqual(
            link.actionStatuses,
            [ConversationActionStatus(actionID: "action-update", status: .pending)]
        )
    }

    func testGivenChangedQueueFingerprintWhenValidateThenRequiresReview() throws {
        let reviewed = try makeApprovedQueueItem(title: "Before")
        let link = try makeLink(queueItem: reviewed)
        var changed = reviewed
        changed.redactedSummary = "After"

        let decision = ConversationActionLinkCoordinator().validate(
            ConversationActionLinkValidationInput(
                link: link,
                queueItem: changed
            )
        )

        XCTAssertEqual(
            decision,
            .requiresReview(reason: "Assistant Queue content changed after review.")
        )
    }

    func testGivenChangedTaskSnapshotWhenValidateThenRequiresReview() throws {
        let item = try makeApprovedQueueItem()
        let link = try makeLink(
            queueItem: item,
            taskSnapshotFingerprint: "task:v1"
        )

        let decision = ConversationActionLinkCoordinator().validate(
            ConversationActionLinkValidationInput(
                link: link,
                queueItem: item,
                currentTaskSnapshotFingerprint: "task:v2"
            )
        )

        XCTAssertEqual(
            decision,
            .requiresReview(reason: "The target Task changed after review.")
        )
    }

    func testGivenSecondTaskChangedWhenValidateThenRequiresReview() throws {
        let plan = ActionPlan(
            id: "plan-multi-task-update",
            userInput: "Update tasks 41 and 42",
            summary: "Update two tasks",
            actions: [
                PlanAction(
                    id: "action-update-41",
                    tool: .taskUpdate,
                    arguments: [
                        "id": .number(41),
                        "title": .string("Updated 41"),
                    ]
                ),
                PlanAction(
                    id: "action-update-42",
                    tool: .taskUpdate,
                    arguments: [
                        "id": .number(42),
                        "title": .string("Updated 42"),
                    ]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let item = try AssistantQueueStateMachine.approve(
            AssistantQueueAdapter.makeItem(
                actionPlan: plan,
                sourceTranscript: plan.userInput,
                interpretationSummary: plan.summary,
                reason: "Review",
                costPreview: .localOnly()
            ),
            reviewerID: "reviewer"
        )
        let link = try ConversationActionLink(
            sessionID: UUID(),
            sourceTurnID: UUID(),
            actionPlanID: plan.id,
            assistantQueueItemID: item.id,
            reviewedFingerprint: try XCTUnwrap(
                item.approval?.reviewedContentFingerprint
            ),
            taskSnapshotFingerprint: nil,
            taskSnapshots: [
                ConversationTaskSnapshot(
                    taskID: 41,
                    fingerprint: "task:41:v1"
                ),
                ConversationTaskSnapshot(
                    taskID: 42,
                    fingerprint: "task:42:v1"
                ),
            ]
        )

        let decision = ConversationActionLinkCoordinator().validate(
            ConversationActionLinkValidationInput(
                link: link,
                queueItem: item,
                currentTaskSnapshotFingerprints: [
                    41: "task:41:v1",
                    42: "task:42:v2",
                ]
            )
        )

        XCTAssertEqual(
            decision,
            .requiresReview(reason: "The target Task changed after review.")
        )
    }

    func testGivenPartialActionSuccessWhenRecordThenKeepsPerActionStatuses() throws {
        let item = try makeApprovedQueueItem()
        let link = try makeLink(queueItem: item)
        let receipt = makeReceipt(
            actions: [
                ExecutionReceiptActionSummary(
                    id: "action-1",
                    toolName: "task.create",
                    status: .succeeded,
                    inputPreview: "Create"
                ),
                ExecutionReceiptActionSummary(
                    id: "action-2",
                    toolName: "task.update",
                    status: .failed,
                    inputPreview: "Update",
                    errorSummary: "Failed"
                ),
                ExecutionReceiptActionSummary(
                    id: "action-3",
                    toolName: "task.complete",
                    status: .skipped,
                    inputPreview: "Complete"
                ),
            ]
        )

        let recorded = try ConversationActionLinkCoordinator()
            .recordExecution(link: link, receipt: receipt)

        XCTAssertEqual(recorded.executionReceiptID, receipt.id)
        XCTAssertEqual(recorded.actionStatuses, [
            ConversationActionStatus(actionID: "action-1", status: .succeeded),
            ConversationActionStatus(actionID: "action-2", status: .failed),
            ConversationActionStatus(actionID: "action-3", status: .skipped),
        ])
        XCTAssertFalse(recorded.isCompleteSuccess)
    }

    func testGivenFailedExecutionWhenRetryThenPriorApprovalIsNotReused() throws {
        let item = try makeApprovedQueueItem()
        let prior = try makeLink(queueItem: item)
        let failed = try ConversationActionLinkCoordinator().recordExecution(
            link: prior,
            receipt: makeReceipt(
                actions: [
                    ExecutionReceiptActionSummary(
                        id: "action-1",
                        toolName: "task.create",
                        status: .failed,
                        inputPreview: "Create"
                    ),
                ]
            )
        )
        let reopened = try AssistantQueueStateMachine
            .reopenFailedForReview(
                AssistantQueueStateMachine.markFailed(
                    AssistantQueueStateMachine.startRunning(item),
                    reason: "failed"
                )
            )

        let retry = try ConversationActionLinkCoordinator().makeRetryLink(
            prior: failed,
            queueItem: reopened
        )

        XCTAssertNil(reopened.approval)
        XCTAssertEqual(retry.retryOfActionLinkID, failed.id)
        XCTAssertEqual(
            ConversationActionLinkCoordinator().validate(
                ConversationActionLinkValidationInput(
                    link: retry,
                    queueItem: reopened
                )
            ),
            .requiresReview(reason: "Assistant Queue approval is missing or stale.")
        )
    }

    func testGivenPriorReceiptWithoutRetryLinkWhenValidateThenRequiresNewLink() throws {
        let item = try makeApprovedQueueItem()
        let prior = try ConversationActionLink(
            sessionID: UUID(),
            sourceTurnID: UUID(),
            actionPlanID: "plan-1",
            assistantQueueItemID: item.id,
            executionReceiptID: "receipt-prior",
            reviewedFingerprint: try XCTUnwrap(
                item.approval?.reviewedContentFingerprint
            )
        )

        XCTAssertEqual(
            ConversationActionLinkCoordinator().validate(
                ConversationActionLinkValidationInput(
                    link: prior,
                    queueItem: item
                )
            ),
            .requiresReview(
                reason: "This retry needs a new reviewed Action Link."
            )
        )
    }

    func testGivenMissingQueueItemWhenValidateThenReturnsUnavailable() throws {
        let item = try makeApprovedQueueItem()
        let link = try makeLink(queueItem: item)

        XCTAssertEqual(
            ConversationActionLinkCoordinator().validate(
                ConversationActionLinkValidationInput(
                    link: link,
                    queueItem: nil
                )
            ),
            .unavailable(reason: "The linked Assistant Queue item is unavailable.")
        )
    }

    func testGivenSecretInTurnLabelWhenCreateReceiptReferencesThenStoresRedactedLabel() throws {
        let item = try makeApprovedQueueItem()
        let link = try makeLink(queueItem: item)

        let references = ConversationActionLinkCoordinator()
            .receiptReferences(
                for: link,
                turnLabel: "token=super-secret release task"
            )

        XCTAssertEqual(
            references.map(\.kind),
            [.reviewSession, .document]
        )
        XCTAssertFalse(references.compactMap(\.label).joined().contains("super-secret"))
        XCTAssertTrue(references.compactMap(\.label).joined().contains("REDACTED"))
    }

    private func makeApprovedQueueItem(
        title: String = "Create release task"
    ) throws -> AssistantQueueItem {
        let plan = ActionPlan(
            id: "plan-1",
            userInput: title,
            summary: title,
            actions: [
                PlanAction(
                    id: "action-1",
                    tool: .taskCreate,
                    arguments: ["title": .string(title)]
                ),
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        let item = AssistantQueueItem(
            id: "queue-1",
            state: .waitingReview,
            payload: .actionPlan(plan),
            riskLevel: .write,
            sourceTranscript: title,
            interpretationSummary: "Create task",
            reviewReason: "Review",
            redactedSummary: title,
            requiredCapabilities: [.tool(.taskCreate)],
            costPreview: .localOnly()
        )
        return try AssistantQueueStateMachine.approve(
            item,
            reviewerID: "reviewer"
        )
    }

    private func makeLink(
        queueItem: AssistantQueueItem,
        taskSnapshotFingerprint: String? = nil
    ) throws -> ConversationActionLink {
        try ConversationActionLink(
            sessionID: UUID(),
            sourceTurnID: UUID(),
            actionPlanID: "plan-1",
            assistantQueueItemID: queueItem.id,
            taskID: taskSnapshotFingerprint == nil ? nil : 42,
            reviewedFingerprint: try XCTUnwrap(
                queueItem.approval?.reviewedContentFingerprint
            ),
            taskSnapshotFingerprint: taskSnapshotFingerprint
        )
    }

    private func makeReceipt(
        actions: [ExecutionReceiptActionSummary]
    ) -> ExecutionReceipt {
        ExecutionReceipt(
            id: "receipt-1",
            runID: "run-1",
            status: actions.allSatisfy { $0.status == .succeeded }
                ? .succeeded
                : .failed,
            inputPreview: "input",
            outputSummary: "output",
            usage: .unknown,
            actions: actions
        )
    }
}
