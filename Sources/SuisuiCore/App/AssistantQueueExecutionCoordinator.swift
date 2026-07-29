import Foundation

private final class ManagedAIUsageExecutionGate: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        // The execution claim, managed billing totals, and eventual ledger write
        // form one local integrity boundary. Serializing all claims prevents an
        // item from changing billing mode between an unlocked classification read
        // and the atomic transition to running.
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

public struct AssistantQueueExecutionCoordinator {
    private let queueStore: any AssistantQueueStore
    private let executor: ActionExecutor
    private let executionReceiptStore: any ExecutionReceiptStore
    private let managedAIUsageLedgerStore: (any ManagedAIUsageLedgerStore)?
    private let managedAIBillingSettingsProvider: () -> ManagedAIBillingSettings
    private let managedAIUsageCalendar: Calendar
    private var conversationActionLinkStore:
        (any ConversationActionLinkStore)?
    private var taskSnapshotFingerprintProvider: (Int64) throws -> String?
    private static let sharedManagedAIUsageGate = ManagedAIUsageExecutionGate()
    private let runIDProvider: () -> String
    private let now: () -> Date

    public init(
        queueStore: any AssistantQueueStore,
        executor: ActionExecutor,
        executionReceiptStore: any ExecutionReceiptStore,
        managedAIUsageLedgerStore: (any ManagedAIUsageLedgerStore)? = nil,
        managedAIBillingSettings: ManagedAIBillingSettings = .default,
        managedAIBillingSettingsProvider: (() -> ManagedAIBillingSettings)? = nil,
        managedAIUsageCalendar: Calendar = ManagedAIBillingSettings.usageLedgerCalendar(),
        runIDProvider: @escaping () -> String = { "assistant-queue-run:\(UUID().uuidString)" },
        now: @escaping () -> Date = { Date() }
    ) {
        self.queueStore = queueStore
        self.executor = executor
        self.executionReceiptStore = executionReceiptStore
        self.managedAIUsageLedgerStore = managedAIUsageLedgerStore
        self.managedAIBillingSettingsProvider = managedAIBillingSettingsProvider
            ?? { managedAIBillingSettings }
        self.managedAIUsageCalendar = managedAIUsageCalendar
        self.conversationActionLinkStore = nil
        self.taskSnapshotFingerprintProvider = { _ in nil }
        self.runIDProvider = runIDProvider
        self.now = now
    }

    public init(
        queueStore: any AssistantQueueStore,
        executor: ActionExecutor,
        executionReceiptStore: any ExecutionReceiptStore,
        conversationActionLinkStore: any ConversationActionLinkStore,
        taskSnapshotFingerprintProvider: @escaping (Int64) throws -> String?,
        managedAIUsageLedgerStore: (any ManagedAIUsageLedgerStore)? = nil,
        managedAIBillingSettings: ManagedAIBillingSettings = .default,
        managedAIBillingSettingsProvider: (() -> ManagedAIBillingSettings)? = nil,
        managedAIUsageCalendar: Calendar = ManagedAIBillingSettings.usageLedgerCalendar(),
        runIDProvider: @escaping () -> String = { "assistant-queue-run:\(UUID().uuidString)" },
        now: @escaping () -> Date = { Date() }
    ) {
        self.init(
            queueStore: queueStore,
            executor: executor,
            executionReceiptStore: executionReceiptStore,
            managedAIUsageLedgerStore: managedAIUsageLedgerStore,
            managedAIBillingSettings: managedAIBillingSettings,
            managedAIBillingSettingsProvider: managedAIBillingSettingsProvider,
            managedAIUsageCalendar: managedAIUsageCalendar,
            runIDProvider: runIDProvider,
            now: now
        )
        self.conversationActionLinkStore = conversationActionLinkStore
        self.taskSnapshotFingerprintProvider =
            taskSnapshotFingerprintProvider
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use execute(id:expectedMutationRevision:).")
    public func execute(id: String) throws -> AssistantQueueExecutionResult {
        // An unversioned caller cannot prove which approved payload the user
        // reviewed. Never infer the current revision because another window may
        // have edited and reapproved different work under the same durable id.
        throw AssistantQueueStaleReviewError()
    }

    @discardableResult
    public func execute(
        id: String,
        expectedMutationRevision: String
    ) throws -> AssistantQueueExecutionResult {
        try execute(id: id, expectedMutationRevision: Optional(expectedMutationRevision))
    }

    public func recordConversationRetryIfNeeded(
        id: String
    ) throws {
        guard let conversationActionLinkStore,
              let prior = try conversationActionLinkStore.latestActionLink(
                  assistantQueueItemID: id
              )
        else {
            return
        }
        let reopened = try queueStore.get(id: id)
        do {
            try conversationActionLinkStore.saveActionLink(
                ConversationActionLinkCoordinator().makeRetryLink(
                    prior: prior,
                    queueItem: reopened
                )
            )
        } catch {
            let expectedRevision = reopened.mutationRevision
            var queueStateMarkedFailed = false
            do {
                _ = try queueStore.transition(id: id) { current in
                    guard current.mutationRevision == expectedRevision else {
                        throw AssistantQueueStaleReviewError()
                    }
                    // A retry without a successor ActionLink could later
                    // revalidate the prior approval lineage. Keep it visibly
                    // blocked until the user creates a fresh reviewed plan.
                    var blocked = current
                    blocked.state = .blocked
                    blocked.approval = nil
                    blocked.blockingReason =
                        "Conversation retry evidence could not be persisted. Create a new reviewed plan."
                    return blocked
                }
                queueStateMarkedFailed = true
            } catch {
                queueStateMarkedFailed = false
            }
            throw AssistantQueueConversationLinkPersistenceError(
                queueStateMarkedFailed: queueStateMarkedFailed
            )
        }
    }

    private func execute(
        id: String,
        expectedMutationRevision: String?
    ) throws -> AssistantQueueExecutionResult {
        try Self.sharedManagedAIUsageGate.withLock {
            try executeUnlocked(
                id: id,
                expectedMutationRevision: expectedMutationRevision
            )
        }
    }

    private func executeUnlocked(
        id: String,
        expectedMutationRevision: String?
    ) throws -> AssistantQueueExecutionResult {
        let current = try queueStore.get(id: id)
        guard AssistantQueueExecutableActionPlanFactory.actionPlan(for: current.payload) != nil else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }
        guard let currentMutationRevision = current.mutationRevision else {
            throw AssistantQueueStaleReviewError()
        }
        if let expectedMutationRevision,
           expectedMutationRevision != currentMutationRevision {
            throw AssistantQueueStaleReviewError()
        }
        let conversationLink = try currentConversationLink(
            for: current
        )

        let startedAt = now()
        let managedAIBillingSettings = currentManagedAIBillingSettings()
        try enforceManagedUsageCapsBeforeRunning(
            item: current,
            itemID: id,
            expectedMutationRevision: currentMutationRevision,
            referenceDate: startedAt,
            managedAIBillingSettings: managedAIBillingSettings
        )

        let running = try queueStore.transition(id: id) { item in
            // Revalidate after cost/cap inspection inside the store's atomic
            // transition. Another window must not replace the reviewed payload
            // or cost preview between the preflight read and the running claim.
            guard item.mutationRevision == currentMutationRevision,
                  AssistantQueueExecutableActionPlanFactory.actionPlan(for: item.payload) != nil else {
                throw AssistantQueueStaleReviewError()
            }
            return try AssistantQueueStateMachine.startRunning(item)
        }
        guard let plan = AssistantQueueExecutableActionPlanFactory.actionPlan(for: running.payload) else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        let runID = runIDProvider()
        // Queue retries create a fresh in-memory review session, but external
        // side-effect idempotency must remain bound to the durable queue item.
        // Reapproval still issues a new single-use nonce for this execution.
        var session = ReviewSession(
            id: "assistant-queue-item:\(running.id)",
            plan: plan,
            createdAt: startedAt
        )
        if session.canApprove {
            try session.approve(issuedAt: startedAt)
        }

        let executedSession: ReviewSession
        do {
            executedSession = try executor.execute(session, now: startedAt)
        } catch {
            var failedSession = session
            failedSession.executionStatus = .failed
            let receipt = makeReceipt(
                item: running,
                session: failedSession,
                runID: runID,
                startedAt: startedAt,
                finishedAt: now(),
                conversationLink: conversationLink
            )
            try saveReceiptOrMarkQueueFailed(
                receipt,
                itemID: id,
                executionStatus: failedSession.executionStatus
            )
            try recordManagedUsageLedgerOrMarkQueueFailed(
                item: running,
                receipt: receipt,
                itemID: id,
                executionStatus: failedSession.executionStatus
            )
            try recordConversationLinkOrMarkQueueFailed(
                link: conversationLink,
                receipt: receipt,
                itemID: id,
                executionStatus: failedSession.executionStatus
            )
            _ = try queueStore.transition(id: id) { item in
                try AssistantQueueStateMachine.markFailed(
                    item,
                    reason: "Execution failed. Review the receipt before retrying."
                )
            }
            throw error
        }

        let receipt = makeReceipt(
            item: running,
            session: executedSession,
            runID: runID,
            startedAt: startedAt,
            finishedAt: now(),
            conversationLink: conversationLink
        )
        try saveReceiptOrMarkQueueFailed(
            receipt,
            itemID: id,
            executionStatus: executedSession.executionStatus
        )
        try recordManagedUsageLedgerOrMarkQueueFailed(
            item: running,
            receipt: receipt,
            itemID: id,
            executionStatus: executedSession.executionStatus
        )
        try recordConversationLinkOrMarkQueueFailed(
            link: conversationLink,
            receipt: receipt,
            itemID: id,
            executionStatus: executedSession.executionStatus
        )
        let finalItem = try markFinalQueueState(
            id: id,
            status: executedSession.executionStatus
        )
        return AssistantQueueExecutionResult(item: finalItem, session: executedSession, receipt: receipt)
    }

    private func saveReceiptOrMarkQueueFailed(
        _ receipt: ExecutionReceipt,
        itemID: String,
        executionStatus: ReviewExecutionStatus
    ) throws {
        do {
            try executionReceiptStore.save(receipt)
        } catch {
            // A queue item must not stay running after tools have returned. If
            // the durable receipt cannot be written, fail the item so retry
            // starts from explicit human review instead of silently losing audit
            // evidence or marking work done without a receipt.
            var queueStateMarkedFailed = false
            do {
                _ = try queueStore.transition(id: itemID) { item in
                    try AssistantQueueStateMachine.markFailed(
                        item,
                        reason: receiptPersistenceFailureReason(for: executionStatus)
                    )
                }
                queueStateMarkedFailed = true
            } catch {
                queueStateMarkedFailed = false
            }
            throw AssistantQueueExecutionError.receiptPersistenceFailed(queueStateMarkedFailed: queueStateMarkedFailed)
        }
    }

    private func enforceManagedUsageCapsBeforeRunning(
        item: AssistantQueueItem,
        itemID: String,
        expectedMutationRevision: String,
        referenceDate: Date,
        managedAIBillingSettings: ManagedAIBillingSettings
    ) throws {
        guard managedAIBillingSettings.hasLedgerBackedUsageCap else {
            return
        }
        guard item.state == .approved else {
            return
        }
        guard AssistantQueueStateMachine.hasCurrentApproval(item) else {
            return
        }
        guard let costPreview = item.costPreview,
              costPreview.billingMode == .suisuiManaged,
              costPreview.allowsApprovalAndRun,
              let currencyCode = costPreview.currencyCode
        else {
            return
        }
        guard let managedAIUsageLedgerStore else {
            let queueStateMarkedFailed = markQueueExecutionBlocked(
                itemID: itemID,
                expectedMutationRevision: expectedMutationRevision,
                reason: managedUsageCapCheckFailureReason
            )
            throw AssistantQueueExecutionError.managedUsageCapCheckFailed(queueStateMarkedFailed: queueStateMarkedFailed)
        }

        let totals: ManagedAIUsageLedgerTotals
        do {
            totals = try managedAIUsageLedgerStore.usageTotals(
                currencyCode: currencyCode,
                referenceDate: referenceDate,
                calendar: managedAIUsageCalendar
            )
        } catch {
            let queueStateMarkedFailed = markQueueExecutionBlocked(
                itemID: itemID,
                expectedMutationRevision: expectedMutationRevision,
                reason: managedUsageCapCheckFailureReason
            )
            throw AssistantQueueExecutionError.managedUsageCapCheckFailed(queueStateMarkedFailed: queueStateMarkedFailed)
        }

        guard let projection = managedAIBillingSettings.firstExceededUsageCap(
            totals: totals,
            pendingCostPreview: costPreview
        ) else {
            return
        }

        let queueStateMarkedFailed = markQueueExecutionBlocked(
            itemID: itemID,
            expectedMutationRevision: expectedMutationRevision,
            reason: projection.blockingReason
        )
        throw AssistantQueueExecutionError.managedUsageCapExceeded(
            projection: projection,
            queueStateMarkedFailed: queueStateMarkedFailed
        )
    }

    private func currentManagedAIBillingSettings() -> ManagedAIBillingSettings {
        managedAIBillingSettingsProvider().normalized
    }

    private func recordManagedUsageLedgerOrMarkQueueFailed(
        item: AssistantQueueItem,
        receipt: ExecutionReceipt,
        itemID: String,
        executionStatus: ReviewExecutionStatus
    ) throws {
        guard let managedAIUsageLedgerStore else {
            return
        }
        guard item.costPreview?.billingMode == .suisuiManaged else {
            return
        }
        guard let entry = ManagedAIUsageLedgerEntry.makeAssistantQueueEntry(
            itemID: item.id,
            costPreview: item.costPreview,
            receipt: receipt,
            occurredAt: receipt.finishedAt ?? now()
        ) else {
            try failQueueForManagedUsageLedgerIssue(itemID: itemID, executionStatus: executionStatus)
        }

        do {
            try managedAIUsageLedgerStore.record(entry)
        } catch {
            try failQueueForManagedUsageLedgerIssue(itemID: itemID, executionStatus: executionStatus)
        }
    }

    private func failQueueForManagedUsageLedgerIssue(
        itemID: String,
        executionStatus: ReviewExecutionStatus
    ) throws -> Never {
        var queueStateMarkedFailed = false
        do {
            _ = try queueStore.transition(id: itemID) { item in
                try AssistantQueueStateMachine.markFailed(
                    item,
                    reason: managedUsageLedgerPersistenceFailureReason(for: executionStatus)
                )
            }
            queueStateMarkedFailed = true
        } catch {
            queueStateMarkedFailed = false
        }
        throw AssistantQueueExecutionError.managedUsageLedgerPersistenceFailed(queueStateMarkedFailed: queueStateMarkedFailed)
    }

    private func markQueueExecutionBlocked(
        itemID: String,
        expectedMutationRevision: String,
        reason: String
    ) -> Bool {
        do {
            _ = try queueStore.transition(id: itemID) { item in
                // A slow ledger read must not apply its old cap decision to a
                // newer payload, approval, or cost preview.
                guard item.mutationRevision == expectedMutationRevision else {
                    throw AssistantQueueStaleReviewError()
                }
                return try AssistantQueueStateMachine.markExecutionBlocked(
                    item,
                    reason: reason
                )
            }
            return true
        } catch {
            return false
        }
    }

    private func markFinalQueueState(
        id: String,
        status: ReviewExecutionStatus
    ) throws -> AssistantQueueItem {
        switch status {
        case .completed:
            return try queueStore.transition(id: id) { item in
                try AssistantQueueStateMachine.markDone(item)
            }
        case .failed:
            return try queueStore.transition(id: id) { item in
                try AssistantQueueStateMachine.markFailed(
                    item,
                    reason: "Execution failed. Review the receipt before retrying."
                )
            }
        case .notStarted, .executing, .canceled:
            return try queueStore.transition(id: id) { item in
                try AssistantQueueStateMachine.markFailed(
                    item,
                    reason: "Execution stopped before completion."
                )
            }
        }
    }

    private func managedUsageLedgerPersistenceFailureReason(for status: ReviewExecutionStatus) -> String {
        switch status {
        case .completed:
            return "Execution completed, but the managed AI usage ledger could not be saved. Fix billing ledger storage before retrying."
        case .notStarted, .executing, .failed, .canceled:
            return "Execution failed, and the managed AI usage ledger could not be saved. Fix billing ledger storage before retrying."
        }
    }

    private var managedUsageCapCheckFailureReason: String {
        "Managed AI usage caps could not be checked. Fix billing ledger storage before retrying."
    }

    private func makeReceipt(
        item: AssistantQueueItem,
        session: ReviewSession,
        runID: String,
        startedAt: Date,
        finishedAt: Date,
        conversationLink: ConversationActionLink?
    ) -> ExecutionReceipt {
        let receipt = ExecutionReceiptFactory.makeAssistantQueueReceipt(
            item: item,
            session: session,
            runID: runID,
            model: item.costPreview?.model,
            usage: item.costPreview?.executionReceiptUsage ?? .unknown,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        guard let conversationLink else {
            return receipt
        }
        let references = ConversationActionLinkCoordinator()
            .receiptReferences(
                for: conversationLink,
                turnLabel: item.sourceTranscript
            )
        return receipt.addingReferences(references)
    }

    private func currentConversationLink(
        for item: AssistantQueueItem
    ) throws -> ConversationActionLink? {
        guard let conversationActionLinkStore,
              let link = try conversationActionLinkStore.latestActionLink(
                  assistantQueueItemID: item.id
              )
        else {
            return nil
        }
        let currentTaskSnapshot = try link.taskID.flatMap {
            try taskSnapshotFingerprintProvider($0)
        }
        switch ConversationActionLinkCoordinator().validate(
            ConversationActionLinkValidationInput(
                link: link,
                queueItem: item,
                currentTaskSnapshotFingerprint: currentTaskSnapshot
            )
        ) {
        case .current(let current):
            return current
        case .requiresReview(let reason):
            throw AssistantQueueConversationLinkRequiresReviewError(
                reason: reason
            )
        case .unavailable(let reason):
            throw AssistantQueueConversationLinkUnavailableError(
                reason: reason
            )
        }
    }

    private func recordConversationLinkOrMarkQueueFailed(
        link: ConversationActionLink?,
        receipt: ExecutionReceipt,
        itemID: String,
        executionStatus: ReviewExecutionStatus
    ) throws {
        guard let link, let conversationActionLinkStore else {
            return
        }
        do {
            try conversationActionLinkStore.saveActionLink(
                ConversationActionLinkCoordinator().recordExecution(
                    link: link,
                    receipt: receipt
                )
            )
        } catch {
            var queueStateMarkedFailed = false
            do {
                _ = try queueStore.transition(id: itemID) { item in
                    try AssistantQueueStateMachine.markFailed(
                        item,
                        reason: receiptPersistenceFailureReason(
                            for: executionStatus
                        )
                    )
                }
                queueStateMarkedFailed = true
            } catch {
                queueStateMarkedFailed = false
            }
            throw AssistantQueueConversationLinkPersistenceError(
                queueStateMarkedFailed: queueStateMarkedFailed
            )
        }
    }

    private func receiptPersistenceFailureReason(for status: ReviewExecutionStatus) -> String {
        switch status {
        case .completed:
            return "Execution completed, but the execution receipt could not be saved. Fix receipt storage before retrying."
        case .notStarted, .executing, .failed, .canceled:
            return "Execution failed, and the execution receipt could not be saved. Fix receipt storage before retrying."
        }
    }
}
