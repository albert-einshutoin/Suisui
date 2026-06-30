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

enum AssistantQueueExecutableActionPlanFactory {
    static func actionPlan(for payload: AssistantQueuePayload) -> ActionPlan? {
        switch payload {
        case .actionPlan(let plan):
            return plan
        case .automationRequest(let request):
            return actionPlan(for: request)
        }
    }

    static func reviewSummary(for request: SyncAutomationRequestPayload) -> String {
        guard let mutation = request.taskMutation else {
            let summary = request.redactedArgumentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            return summary.isEmpty ? "Remote automation request" : summary
        }

        let suppliedSummary = request.redactedArgumentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let mutationSummary = mutationReviewSummary(for: request, mutation: mutation)
        guard !suppliedSummary.isEmpty else {
            return mutationSummary
        }
        guard !suppliedSummary.contains(mutationSummary) else {
            return suppliedSummary
        }
        return "\(suppliedSummary)\n\(mutationSummary)"
    }

    private static func actionPlan(for request: SyncAutomationRequestPayload) -> ActionPlan? {
        guard let mutation = request.taskMutation,
              hasRequiredFields(mutation),
              isToolNameConsistent(request.toolName, operation: mutation.operation) else {
            return nil
        }

        let summary = reviewSummary(for: request)
        return ActionPlan(
            id: "automation-request:\(request.id)",
            userInput: summary,
            summary: summary,
            actions: [
                PlanAction(
                    id: "automation-request:\(request.id):\(mutation.operation.rawValue)",
                    tool: tool(for: mutation.operation),
                    arguments: arguments(for: mutation),
                    riskLevel: .write
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func hasRequiredFields(_ mutation: SyncTaskMutationPayload) -> Bool {
        switch mutation.operation {
        case .create:
            return isRequiredString(mutation.title)
                && isOptionalPositiveID(mutation.projectID)
                && optionalStringsAreExecutable([mutation.detail, mutation.dueAt, mutation.priority])
        case .update:
            return isRequiredPositiveID(mutation.taskID)
                && isOptionalPositiveID(mutation.projectID)
                && hasUpdateField(mutation)
                && optionalStringsAreExecutable([
                    mutation.title,
                    mutation.detail,
                    mutation.status,
                    mutation.dueAt,
                    mutation.priority
                ])
        case .complete:
            return isRequiredPositiveID(mutation.taskID)
        case .moveProject:
            return isRequiredPositiveID(mutation.taskID)
                && isRequiredPositiveID(mutation.projectID)
        case .updateDueDate:
            return isRequiredPositiveID(mutation.taskID)
                && isRequiredString(mutation.dueAt)
        }
    }

    private static func isToolNameConsistent(
        _ toolName: String?,
        operation: SyncTaskMutationOperation
    ) -> Bool {
        guard let normalizedToolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedToolName.isEmpty else {
            return true
        }
        return supportedToolNames(for: operation).contains(normalizedToolName)
    }

    private static func supportedToolNames(for operation: SyncTaskMutationOperation) -> Set<String> {
        switch operation {
        case .create:
            return [HostedMCPTaskToolName.taskCreate.rawValue, ActionTool.taskCreate.rawValue]
        case .update:
            return [HostedMCPTaskToolName.taskUpdate.rawValue, ActionTool.taskUpdate.rawValue]
        case .complete:
            return [HostedMCPTaskToolName.taskComplete.rawValue, ActionTool.taskComplete.rawValue]
        case .moveProject:
            return [HostedMCPTaskToolName.taskProjectMove.rawValue, ActionTool.taskUpdate.rawValue]
        case .updateDueDate:
            return [HostedMCPTaskToolName.taskDueDateUpdate.rawValue, ActionTool.taskUpdate.rawValue]
        }
    }

    private static func tool(for operation: SyncTaskMutationOperation) -> ActionTool {
        switch operation {
        case .create:
            return .taskCreate
        case .update, .moveProject, .updateDueDate:
            return .taskUpdate
        case .complete:
            return .taskComplete
        }
    }

    private static func arguments(for mutation: SyncTaskMutationPayload) -> [String: JSONValue] {
        var arguments: [String: JSONValue] = [:]

        // Sync payloads use API-facing names while local TaskTool follows the
        // ActionPlan schema. Keep the boundary explicit so remote connectors do
        // not leak transport field names into the local execution surface.
        switch mutation.operation {
        case .create:
            putString(mutation.title, key: "title", into: &arguments)
            putString(mutation.detail, key: "detail", into: &arguments)
            putInt64(mutation.projectID, key: "projectId", into: &arguments)
            putString(mutation.dueAt, key: "dueAt", into: &arguments)
            putString(mutation.priority, key: "priority", into: &arguments)
        case .update:
            putInt64(mutation.taskID, key: "id", into: &arguments)
            putString(mutation.title, key: "title", into: &arguments)
            putString(mutation.detail, key: "detail", into: &arguments)
            putString(mutation.status, key: "status", into: &arguments)
            putInt64(mutation.projectID, key: "projectId", into: &arguments)
            putString(mutation.dueAt, key: "dueAt", into: &arguments)
            putString(mutation.priority, key: "priority", into: &arguments)
        case .complete:
            putInt64(mutation.taskID, key: "id", into: &arguments)
        case .moveProject:
            putInt64(mutation.taskID, key: "id", into: &arguments)
            putInt64(mutation.projectID, key: "projectId", into: &arguments)
        case .updateDueDate:
            putInt64(mutation.taskID, key: "id", into: &arguments)
            putString(mutation.dueAt, key: "dueAt", into: &arguments)
        }

        return arguments
    }

    private static func mutationReviewSummary(
        for request: SyncAutomationRequestPayload,
        mutation: SyncTaskMutationPayload
    ) -> String {
        var parts = ["operation=\(mutation.operation.rawValue)"]
        if let toolName = request.toolName?.trimmingCharacters(in: .whitespacesAndNewlines), !toolName.isEmpty {
            parts.append("toolName=\(redacted(toolName))")
        }
        append("taskID", mutation.taskID, to: &parts)
        append("projectID", mutation.projectID, to: &parts)
        append("title", mutation.title, to: &parts)
        append("detail", mutation.detail, to: &parts)
        append("status", mutation.status, to: &parts)
        append("dueAt", mutation.dueAt, to: &parts)
        append("priority", mutation.priority, to: &parts)
        return "Mutation: \(parts.joined(separator: ", "))"
    }

    private static func putString(_ value: String?, key: String, into arguments: inout [String: JSONValue]) {
        guard let value = normalizedString(value) else {
            return
        }
        arguments[key] = .string(value)
    }

    private static func putInt64(_ value: Int64?, key: String, into arguments: inout [String: JSONValue]) {
        guard let value else {
            return
        }
        arguments[key] = .number(Double(value))
    }

    private static func isRequiredString(_ value: String?) -> Bool {
        normalizedString(value) != nil
    }

    private static func optionalStringsAreExecutable(_ values: [String?]) -> Bool {
        values.allSatisfy { value in
            value == nil || normalizedString(value) != nil
        }
    }

    private static func hasUpdateField(_ mutation: SyncTaskMutationPayload) -> Bool {
        mutation.title != nil
            || mutation.detail != nil
            || mutation.status != nil
            || mutation.projectID != nil
            || mutation.dueAt != nil
            || mutation.priority != nil
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isRequiredPositiveID(_ value: Int64?) -> Bool {
        guard let value else {
            return false
        }
        return value > 0
    }

    private static func isOptionalPositiveID(_ value: Int64?) -> Bool {
        guard let value else {
            return true
        }
        return value > 0
    }

    private static func append(_ key: String, _ value: Int64?, to parts: inout [String]) {
        guard let value else {
            return
        }
        parts.append("\(key)=\(value)")
    }

    private static func append(_ key: String, _ value: String?, to parts: inout [String]) {
        guard let value = normalizedString(value) else {
            return
        }
        parts.append("\(key)=\(redacted(value))")
    }

    private static func redacted(_ value: String, maxLength: Int = 160) -> String {
        let redacted = DeveloperSecretRedactor().redact(value).text
        guard redacted.count > maxLength else {
            return redacted
        }
        return String(redacted.prefix(maxLength)) + "..."
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
        guard AssistantQueueExecutableActionPlanFactory.actionPlan(for: current.payload) != nil else {
            throw AssistantQueueExecutionError.unsupportedPayload
        }

        let running = try queueStore.transition(id: id) { item in
            try AssistantQueueStateMachine.startRunning(item)
        }
        guard let plan = AssistantQueueExecutableActionPlanFactory.actionPlan(for: running.payload) else {
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
            model: item.costPreview?.model,
            usage: item.costPreview?.executionReceiptUsage ?? .unknown,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }
}
