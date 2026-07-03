import Foundation

private final class ManagedAIUsageExecutionGate: @unchecked Sendable {
    private let lock = NSLock()

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        // Managed billing caps depend on reading ledger totals and later
        // recording the same run. Keep that section serialized so concurrent
        // local runs cannot each pass against the same pre-run balance.
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
        self.runIDProvider = runIDProvider
        self.now = now
    }

    @discardableResult
    public func execute(id: String) throws -> AssistantQueueExecutionResult {
        let current = try queueStore.get(id: id)
        guard AssistantQueueExecutableActionPlanFactory.actionPlan(for: current.payload) != nil else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        if shouldSerializeManagedUsage(item: current, settings: currentManagedAIBillingSettings()) {
            return try Self.sharedManagedAIUsageGate.withLock {
                try executeUnlocked(id: id)
            }
        }

        return try executeUnlocked(id: id)
    }

    private func executeUnlocked(id: String) throws -> AssistantQueueExecutionResult {
        let current = try queueStore.get(id: id)
        guard AssistantQueueExecutableActionPlanFactory.actionPlan(for: current.payload) != nil else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        let startedAt = now()
        let managedAIBillingSettings = currentManagedAIBillingSettings()
        try enforceManagedUsageCapsBeforeRunning(
            item: current,
            itemID: id,
            referenceDate: startedAt,
            managedAIBillingSettings: managedAIBillingSettings
        )

        let running = try queueStore.transition(id: id) { item in
            try AssistantQueueStateMachine.startRunning(item)
        }
        guard let plan = AssistantQueueExecutableActionPlanFactory.actionPlan(for: running.payload) else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        let runID = runIDProvider()
        var session = ReviewSession(plan: plan, createdAt: startedAt)
        if session.canApprove {
            try session.approve(token: ApprovalToken(
                id: "assistant-queue-execution:\(id):\(UUID().uuidString)",
                sessionID: session.id,
                approvedAt: startedAt
            ))
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
                finishedAt: now()
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
            finishedAt: now()
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
              costPreview.billingMode == .soloPMManaged,
              costPreview.allowsApprovalAndRun,
              let currencyCode = costPreview.currencyCode
        else {
            return
        }
        guard let managedAIUsageLedgerStore else {
            let queueStateMarkedFailed = markQueueExecutionBlocked(
                itemID: itemID,
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

    private func shouldSerializeManagedUsage(
        item: AssistantQueueItem,
        settings: ManagedAIBillingSettings
    ) -> Bool {
        settings.hasLedgerBackedUsageCap
            && item.costPreview?.billingMode == .soloPMManaged
            && item.state == .approved
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
        guard item.costPreview?.billingMode == .soloPMManaged else {
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

    private func markQueueExecutionBlocked(itemID: String, reason: String) -> Bool {
        do {
            _ = try queueStore.transition(id: itemID) { item in
                try AssistantQueueStateMachine.markExecutionBlocked(item, reason: reason)
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
        finishedAt: Date
    ) -> ExecutionReceipt {
        ExecutionReceiptFactory.makeAssistantQueueReceipt(
            item: item,
            session: session,
            runID: runID,
            model: item.costPreview?.model,
            usage: item.costPreview?.executionReceiptUsage ?? .unknown,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
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
