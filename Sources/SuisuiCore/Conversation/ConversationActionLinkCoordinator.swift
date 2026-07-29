import Foundation

public struct ConversationActionLinkValidationInput: Equatable, Sendable {
    public let link: ConversationActionLink
    public let queueItem: AssistantQueueItem?
    public let currentTaskSnapshotFingerprint: String?
    public let currentTaskSnapshotFingerprints: [Int64: String]?

    public init(
        link: ConversationActionLink,
        queueItem: AssistantQueueItem?,
        currentTaskSnapshotFingerprint: String? = nil,
        currentTaskSnapshotFingerprints: [Int64: String]? = nil
    ) {
        self.link = link
        self.queueItem = queueItem
        self.currentTaskSnapshotFingerprint = currentTaskSnapshotFingerprint
        if let currentTaskSnapshotFingerprints {
            self.currentTaskSnapshotFingerprints =
                currentTaskSnapshotFingerprints
        } else if let taskID = link.taskID,
                  let currentTaskSnapshotFingerprint {
            self.currentTaskSnapshotFingerprints = [
                taskID: currentTaskSnapshotFingerprint,
            ]
        } else {
            self.currentTaskSnapshotFingerprints = nil
        }
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
        let currentPlan = AssistantQueueExecutableActionPlanFactory
            .actionPlan(for: queueItem.payload)
        if currentPlan?.actions.contains(where: {
            Self.isTaskMutation($0.tool)
                && Self.stableTaskID(in: $0) == nil
        }) == true {
            return .requiresReview(
                reason: "The target Task changed after review."
            )
        }
        let planTaskIDs = currentPlan.map(Self.stableTaskIDs(in:)) ?? []
        let reviewedTaskSnapshots = Dictionary(
            uniqueKeysWithValues: input.link.taskSnapshots.map {
                ($0.taskID, $0.fingerprint)
            }
        )
        guard Set(planTaskIDs) == Set(reviewedTaskSnapshots.keys) else {
            return .requiresReview(
                reason: "The target Task changed after review."
            )
        }
        if !reviewedTaskSnapshots.isEmpty {
            guard let currentTaskSnapshots =
                    input.currentTaskSnapshotFingerprints
            else {
                return .unavailable(
                    reason: "The linked Task snapshot is unavailable."
                )
            }
            guard currentTaskSnapshots.count
                    == reviewedTaskSnapshots.count,
                  reviewedTaskSnapshots.allSatisfy({
                      currentTaskSnapshots[$0.key] == $0.value
                  })
            else {
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
        if let unresolvedAction = plan.actions.first(where: {
            Self.isTaskMutation($0.tool)
                && Self.stableTaskID(in: $0) == nil
        }) {
            throw ConversationActionLinkTaskTargetUnavailableError(
                actionID: unresolvedAction.id
            )
        }
        let taskIDs = Self.stableTaskIDs(in: plan)
        let taskSnapshots = try taskIDs.map { taskID in
            guard let fingerprint = try taskSnapshotFingerprintProvider(
                taskID
            ) else {
                throw ConversationActionLinkTaskSnapshotUnavailableError(
                    taskID: taskID
                )
            }
            return ConversationTaskSnapshot(
                taskID: taskID,
                fingerprint: fingerprint
            )
        }
        return try ConversationActionLink(
            sessionID: sessionID,
            sourceTurnID: sourceTurnID,
            actionPlanID: plan.id,
            assistantQueueItemID: queueItem.id,
            taskID: taskSnapshots.count == 1
                ? taskSnapshots[0].taskID
                : nil,
            operation: Self.operation(for: plan),
            reviewedFingerprint: fingerprint,
            taskSnapshotFingerprint: taskSnapshots.count == 1
                ? taskSnapshots[0].fingerprint
                : nil,
            taskSnapshots: taskSnapshots,
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
            taskSnapshots: link.taskSnapshots,
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
            taskSnapshots: prior.taskSnapshots,
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
                // A conversation is the review session that authorized the
                // action. Reusing the established receipt kind preserves the
                // public enum's source compatibility for SwiftPM clients.
                kind: .reviewSession,
                id: link.sessionID.uuidString,
                label: "Conversation Session"
            ),
            ExecutionReceiptReference(
                // A persisted turn is a text record within that review
                // session, so `document` is the closest existing durable kind.
                kind: .document,
                id: link.sourceTurnID.uuidString,
                label: turnLabel.map {
                    receiptRedactor.redact($0, maxLength: 160)
                }
            ),
        ]
    }

    private static func stableTaskIDs(
        in plan: ActionPlan
    ) -> [Int64] {
        Array(Set(
            plan.actions.compactMap(Self.stableTaskID(in:))
        )).sorted()
    }

    private static func stableTaskID(
        in action: PlanAction
    ) -> Int64? {
        guard isTaskMutation(action.tool) else {
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

    private static func isTaskMutation(_ tool: ActionTool) -> Bool {
        tool == .taskUpdate
            || tool == .taskComplete
            || tool == .taskDelete
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
            task.createdAt,
            task.updatedAt,
            task.recurrence,
            String(task.mutationRevision),
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

public struct ConversationActionLinkTaskSnapshotUnavailableError:
    Error,
    Equatable,
    Sendable
{
    public let taskID: Int64

    public init(taskID: Int64) {
        self.taskID = taskID
    }
}

public struct ConversationActionLinkTaskTargetUnavailableError:
    Error,
    Equatable,
    Sendable
{
    public let actionID: String

    public init(actionID: String) {
        self.actionID = actionID
    }
}
