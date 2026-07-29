import Foundation

public struct ConversationActionLinkValidationInput: Equatable, Sendable {
    public let link: ConversationActionLink
    public let queueItem: AssistantQueueItem?
    public let currentTaskSnapshotFingerprint: String?

    public init(
        link: ConversationActionLink,
        queueItem: AssistantQueueItem?,
        currentTaskSnapshotFingerprint: String? = nil
    ) {
        self.link = link
        self.queueItem = queueItem
        self.currentTaskSnapshotFingerprint = currentTaskSnapshotFingerprint
    }
}

public enum ConversationActionLinkDecision: Equatable, Sendable {
    case current(ConversationActionLink)
    case requiresReview(reason: String)
    case unavailable(reason: String)
}

public struct ConversationActionLinkCoordinator: Sendable {
    private let receiptRedactor: ExecutionReceiptRedactor

    public init(
        redactionPolicy: ExecutionReceiptRedactionPolicy =
            ExecutionReceiptRedactionPolicy()
    ) {
        receiptRedactor = ExecutionReceiptRedactor(policy: redactionPolicy)
    }

    public func validate(
        _ input: ConversationActionLinkValidationInput
    ) -> ConversationActionLinkDecision {
        guard let queueItem = input.queueItem,
              queueItem.id == input.link.assistantQueueItemID
        else {
            return .unavailable(
                reason: "The linked Assistant Queue item is unavailable."
            )
        }
        guard input.link.executionReceiptID == nil else {
            return .requiresReview(
                reason: "This retry needs a new reviewed Action Link."
            )
        }
        guard queueItem.approval?.reviewedContentFingerprint
            == input.link.reviewedFingerprint,
            queueItem.contentFingerprint == input.link.reviewedFingerprint
        else {
            return .requiresReview(
                reason: queueItem.approval == nil
                    ? "Assistant Queue approval is missing or stale."
                    : "Assistant Queue content changed after review."
            )
        }
        if let reviewedTaskSnapshot = input.link.taskSnapshotFingerprint {
            guard let currentTaskSnapshot =
                    input.currentTaskSnapshotFingerprint
            else {
                return .unavailable(
                    reason: "The linked Task snapshot is unavailable."
                )
            }
            guard reviewedTaskSnapshot == currentTaskSnapshot else {
                return .requiresReview(
                    reason: "The target Task changed after review."
                )
            }
        }
        return .current(input.link)
    }

    public func makeReviewLink(
        sessionID: UUID,
        sourceTurnID: UUID,
        plan: ActionPlan,
        queueItem: AssistantQueueItem,
        taskSnapshotFingerprintProvider: (Int64) throws -> String? = {
            _ in nil
        }
    ) throws -> ConversationActionLink {
        guard case .actionPlan(let queuedPlan) = queueItem.payload,
              queuedPlan.id == plan.id,
              let fingerprint = queueItem.contentFingerprint
        else {
            throw ConversationActionLinkCoordinatorError
                .unavailableQueueFingerprint
        }
        let taskID = Self.singleStableTaskID(in: plan)
        return try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            actionPlanID: plan.id,
            assistantQueueItemID: queueItem.id,
            taskID: taskID,
            operation: Self.operation(for: plan),
            reviewedFingerprint: fingerprint,
            taskSnapshotFingerprint: try taskID.flatMap(
                taskSnapshotFingerprintProvider
            ),
            actionStatuses: plan.actions.map {
                ConversationActionStatus(
                    actionID: $0.id,
                    status: .pending
                )
            }
        )
    }

    public func recordExecution(
        link: ConversationActionLink,
        receipt: ExecutionReceipt
    ) throws -> ConversationActionLink {
        try ConversationActionLink(
            sessionID: link.sessionID,
            sourceTurnID: link.sourceTurnID,
            actionPlanID: link.actionPlanID,
            assistantQueueItemID: link.assistantQueueItemID,
            taskID: link.taskID,
            executionReceiptID: receipt.id,
            operation: link.operation,
            reviewedFingerprint: link.reviewedFingerprint,
            taskSnapshotFingerprint: link.taskSnapshotFingerprint,
            actionStatuses: receipt.actions.map {
                ConversationActionStatus(
                    actionID: $0.id,
                    status: ConversationActionExecutionStatus($0.status)
                )
            },
            retryOfActionLinkID: link.retryOfActionLinkID
        )
    }

    public func makeRetryLink(
        prior: ConversationActionLink,
        queueItem: AssistantQueueItem
    ) throws -> ConversationActionLink {
        guard queueItem.approval == nil else {
            throw ConversationActionLinkCoordinatorError
                .retryStillCarriesApproval
        }
        guard let currentFingerprint = queueItem.contentFingerprint else {
            throw ConversationActionLinkCoordinatorError
                .unavailableQueueFingerprint
        }
        return try ConversationActionLink(
            sessionID: prior.sessionID,
            sourceTurnID: prior.sourceTurnID,
            actionPlanID: prior.actionPlanID,
            assistantQueueItemID: queueItem.id,
            taskID: prior.taskID,
            operation: prior.operation,
            reviewedFingerprint: currentFingerprint,
            taskSnapshotFingerprint: prior.taskSnapshotFingerprint,
            actionStatuses: prior.actionStatuses.map {
                ConversationActionStatus(
                    actionID: $0.actionID,
                    status: .pending
                )
            },
            retryOfActionLinkID: prior.id
        )
    }

    public func receiptReferences(
        for link: ConversationActionLink,
        turnLabel: String?
    ) -> [ExecutionReceiptReference] {
        [
            ExecutionReceiptReference(
                kind: .conversationSession,
                id: link.sessionID.uuidString
            ),
            ExecutionReceiptReference(
                kind: .conversationTurn,
                id: link.sourceTurnID.uuidString,
                label: turnLabel.map {
                    receiptRedactor.redact($0, maxLength: 160)
                }
            ),
        ]
    }

    private static func singleStableTaskID(
        in plan: ActionPlan
    ) -> Int64? {
        let taskIDs = Set(
            plan.actions.compactMap { action -> Int64? in
                guard action.tool == .taskUpdate
                    || action.tool == .taskComplete
                    || action.tool == .taskDelete
                else {
                    return nil
                }
                for key in ["id", "taskId", "taskID"] {
                    switch action.arguments[key] {
                    case .number(let value)?
                        where value.isFinite
                            && value.rounded(.towardZero) == value
                            && value > 0
                            && value <= Double(Int64.max):
                        return Int64(value)
                    case .string(let value)?:
                        if let id = Int64(value), id > 0 {
                            return id
                        }
                    default:
                        continue
                    }
                }
                return nil
            }
        )
        return taskIDs.count == 1 ? taskIDs.first : nil
    }

    private static func operation(
        for plan: ActionPlan
    ) -> ConversationActionLinkOperation {
        let operations = Set(plan.actions.map(\.tool))
        guard operations.count == 1, let tool = operations.first else {
            return .unspecified
        }
        switch tool {
        case .taskCreate, .taskBulkCreate:
            return .taskCreated
        case .taskUpdate:
            return .taskUpdated
        case .taskComplete:
            return .taskCompleted
        case .taskDelete:
            return .taskDeleted
        default:
            return .unspecified
        }
    }
}

public enum ConversationTaskSnapshotFingerprint {
    public static func make(_ task: TaskRecord) -> String {
        // The digest covers every mutable Task field that can change the
        // meaning of an approved action. Raw content remains outside the
        // ActionLink while execution can still fail closed on review drift.
        AssistantQueueMutationRevision.canonicalDigest([
            String(task.id),
            task.projectID.map(String.init),
            task.title,
            task.status,
            task.dueAt,
            task.completedAt,
            task.priority,
            task.sourceCommand,
            task.detail,
            task.updatedAt,
            task.recurrence,
        ])
    }
}

public enum ConversationActionLinkCoordinatorError:
    Error,
    Equatable,
    Sendable
{
    case retryStillCarriesApproval
    case unavailableQueueFingerprint
}
