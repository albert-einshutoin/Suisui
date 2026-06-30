import Foundation

public enum AssistantQueueExecutionError: Error, Equatable, Sendable {
    case unsupportedPayload
}

public struct AssistantQueueExecutionResult: Equatable, Sendable {
    public var item: AssistantQueueItem
    public var session: ReviewSession
    public var receipt: ExecutionReceipt

    public init(item: AssistantQueueItem, session: ReviewSession, receipt: ExecutionReceipt) {
        self.item = item
        self.session = session
        self.receipt = receipt
    }
}

public struct AssistantQueueExecutionCoordinator {
    private let queueStore: any AssistantQueueStore
    private let executor: ActionExecutor
    private let executionReceiptStore: any ExecutionReceiptStore
    private let runIDProvider: () -> String
    private let now: () -> Date

    public init(
        queueStore: any AssistantQueueStore,
        executor: ActionExecutor,
        executionReceiptStore: any ExecutionReceiptStore,
        runIDProvider: @escaping () -> String = { "assistant-queue-run:\(UUID().uuidString)" },
        now: @escaping () -> Date = { Date() }
    ) {
        self.queueStore = queueStore
        self.executor = executor
        self.executionReceiptStore = executionReceiptStore
        self.runIDProvider = runIDProvider
        self.now = now
    }

    @discardableResult
    public func execute(id: String) throws -> AssistantQueueExecutionResult {
        let current = try queueStore.get(id: id)
        guard case .actionPlan = current.payload else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        let running = try queueStore.transition(id: id) { item in
            try AssistantQueueStateMachine.startRunning(item)
        }
        guard case .actionPlan(let plan) = running.payload else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        let runID = runIDProvider()
        let startedAt = now()
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
            try executionReceiptStore.save(receipt)
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
        try executionReceiptStore.save(receipt)
        let finalItem = try markFinalQueueState(
            id: id,
            status: executedSession.executionStatus
        )
        return AssistantQueueExecutionResult(item: finalItem, session: executedSession, receipt: receipt)
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
            model: nil,
            usage: .unknown,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}
