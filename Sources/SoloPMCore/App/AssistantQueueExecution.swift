import Foundation

public enum AssistantQueueExecutionError: Error, Equatable, Sendable {
    case unsupportedPayload
    case receiptPersistenceFailed(queueStateMarkedFailed: Bool)
    case managedUsageLedgerPersistenceFailed(queueStateMarkedFailed: Bool)
    case managedUsageCapCheckFailed(queueStateMarkedFailed: Bool)
    case managedUsageCapExceeded(projection: ManagedAIUsageCapProjection, queueStateMarkedFailed: Bool)
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
        if let mutation = request.taskMutation {
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

        if let pullRequest = request.developmentPullRequest {
            let suppliedSummary = request.redactedArgumentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let pullRequestSummary = developmentPullRequestReviewSummary(for: request, pullRequest: pullRequest)
            guard !suppliedSummary.isEmpty else {
                return pullRequestSummary
            }
            guard !suppliedSummary.contains(pullRequestSummary) else {
                return suppliedSummary
            }
            return "\(suppliedSummary)\n\(pullRequestSummary)"
        }

        let summary = request.redactedArgumentSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? "Remote automation request" : summary
    }

    private static func actionPlan(for request: SyncAutomationRequestPayload) -> ActionPlan? {
        guard hasSingleExecutablePayload(request) else {
            return nil
        }

        if let mutation = request.taskMutation {
            guard hasRequiredFields(mutation),
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

        if let pullRequest = request.developmentPullRequest {
            guard hasRequiredFields(pullRequest),
                  isToolNameConsistent(request.toolName, operation: pullRequest.operation) else {
                return nil
            }

            let summary = reviewSummary(for: request)
            return ActionPlan(
                id: "automation-request:\(request.id)",
                userInput: summary,
                summary: summary,
                actions: [
                    PlanAction(
                        id: "automation-request:\(request.id):\(pullRequest.operation.rawValue)",
                        tool: tool(for: pullRequest.operation),
                        arguments: arguments(for: pullRequest),
                        riskLevel: .write
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
        }

        return nil
    }

    private static func hasSingleExecutablePayload(_ request: SyncAutomationRequestPayload) -> Bool {
        let payloadCount = [
            request.taskMutation != nil,
            request.developmentPullRequest != nil
        ].filter { $0 }.count
        // Mixed transport payloads make approval fingerprints ambiguous. Keep
        // remote work one executable intent per queue item.
        return payloadCount == 1
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

    private static func hasRequiredFields(_ pullRequest: SyncDevelopmentPullRequestPayload) -> Bool {
        // Remote PR automation can merge code on GitHub, so the queue only
        // accepts payloads that already match the local developer-mode gate.
        guard pullRequest.projectID > 0,
              let pullRequestURL = normalizedString(pullRequest.pullRequestURL),
              let branchName = normalizedString(pullRequest.branchName),
              let baseBranch = normalizedString(pullRequest.baseBranch),
              (try? DevelopmentGitHubPRCommandPolicy.validatedPullRequestURL(
                pullRequestURL,
                redactor: DeveloperSecretRedactor()
              )) != nil,
              (try? DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(branchName)) != nil,
              (try? DevelopmentBranchNamePolicy.validated(baseBranch)) != nil else {
            return false
        }
        return branchName != baseBranch
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

    private static func isToolNameConsistent(
        _ toolName: String?,
        operation: SyncDevelopmentPullRequestOperation
    ) -> Bool {
        guard let normalizedToolName = toolName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedToolName.isEmpty else {
            return false
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

    private static func supportedToolNames(for operation: SyncDevelopmentPullRequestOperation) -> Set<String> {
        switch operation {
        case .reviewGate:
            return [
                ActionTool.developmentReviewPullRequestGate.rawValue,
                "development_pr_review_gate"
            ]
        case .merge:
            return [
                ActionTool.developmentMergePullRequest.rawValue,
                "development_pr_merge"
            ]
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

    private static func tool(for operation: SyncDevelopmentPullRequestOperation) -> ActionTool {
        switch operation {
        case .reviewGate:
            return .developmentReviewPullRequestGate
        case .merge:
            return .developmentMergePullRequest
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

    private static func arguments(for pullRequest: SyncDevelopmentPullRequestPayload) -> [String: JSONValue] {
        [
            "projectId": .number(Double(pullRequest.projectID)),
            "pullRequestURL": .string(normalizedString(pullRequest.pullRequestURL) ?? ""),
            "branchName": .string(normalizedString(pullRequest.branchName) ?? ""),
            "baseBranch": .string(normalizedString(pullRequest.baseBranch) ?? "")
        ]
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

    private static func developmentPullRequestReviewSummary(
        for request: SyncAutomationRequestPayload,
        pullRequest: SyncDevelopmentPullRequestPayload
    ) -> String {
        var parts = ["operation=\(pullRequest.operation.rawValue)"]
        if let toolName = request.toolName?.trimmingCharacters(in: .whitespacesAndNewlines), !toolName.isEmpty {
            parts.append("toolName=\(redacted(toolName))")
        }
        parts.append("projectID=\(pullRequest.projectID)")
        append("pullRequestURL", pullRequest.pullRequestURL, to: &parts)
        append("branchName", pullRequest.branchName, to: &parts)
        append("baseBranch", pullRequest.baseBranch, to: &parts)
        return "Development PR: \(parts.joined(separator: ", "))"
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
