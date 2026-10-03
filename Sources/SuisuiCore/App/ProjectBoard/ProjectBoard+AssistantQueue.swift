import Foundation

extension ProjectBoardViewModel {

    func refreshAssistantQueueSnapshot() -> String? {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            return nil
        }

        do {
            // Project Board owns the central task cockpit, so it reads a compact
            // queue snapshot instead of querying local stores from SwiftUI views.
            // Receipts are outcome-only metadata; queue state remains the source of truth.
            // Counts come from state aggregates so terminal queue history cannot
            // hide older review work behind the row fetch limit.
            var receiptErrorMessage: String?
            let receipts: [ExecutionReceipt]
            do {
                receipts = try executionReceiptStore?.list(
                    matching: ExecutionReceiptSearchFilter(visibleSurface: .assistantQueue),
                    limit: 100
                ) ?? []
            } catch {
                receipts = []
                receiptErrorMessage = assistantQueueReceiptUnavailableMessage
            }
            assistantQueueSnapshot = try assistantQueueStore.readModelSnapshot(
                filter: assistantQueueViewFilter.storeFilter(limit: 100),
                receipts: receipts,
                viewFilter: assistantQueueViewFilter,
                sort: assistantQueueSort
            )
            pruneAssistantQueueSelectionToVisibleRows()
            return receiptErrorMessage
        } catch {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            return AssistantQueueStoreError.userMessage(for: error)
        }
    }

    public func setAssistantQueueViewFilter(_ filter: AssistantQueueViewFilter) {
        guard assistantQueueViewFilter != filter else {
            return
        }
        assistantQueueViewFilter = filter
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
    }

    public func setAssistantQueueSort(_ sort: AssistantQueueSort) {
        guard assistantQueueSort != sort else {
            return
        }
        assistantQueueSort = sort
        _ = refreshAssistantQueueSnapshot()
    }

    func focusAssistantQueueItem(id: String) {
        assistantQueueViewFilter = .needsAttention
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
        if setAssistantQueueSelection(id: id, selected: true) {
            return
        }

        assistantQueueViewFilter = .all
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
        _ = setAssistantQueueSelection(id: id, selected: true)
    }

    @discardableResult
    public func toggleAssistantQueueSelection(id: String) -> Bool {
        setAssistantQueueSelection(
            id: id,
            selected: !assistantQueueSelectedItemIDs.contains(id)
        )
    }

    @discardableResult
    public func setAssistantQueueSelection(id: String, selected: Bool) -> Bool {
        guard let row = assistantQueueSnapshot.rows.first(where: { $0.id == id }) else {
            return false
        }
        if selected {
            guard (row.canDefer || row.canReject), row.mutationRevision != nil else {
                // Batch review actions cannot cancel running work or rewrite a
                // terminal outcome. Missing revisions also fail closed because
                // the batch must compare the exact state the reviewer saw.
                assistantQueueSelectedItemIDs.remove(id)
                return false
            }
            assistantQueueSelectedItemIDs.insert(id)
        } else {
            assistantQueueSelectedItemIDs.remove(id)
        }
        return true
    }

    private var assistantQueueItemUnavailableMessage: String {
        String(localized: "Assistant Queue item is no longer available.")
    }

    private var assistantQueueReceiptUnavailableMessage: String {
        String(localized: "Assistant Queue execution receipts are unavailable. Queue state is still shown.")
    }

    @discardableResult
    public func focusAssistantQueueExecutionHandoff(id: String) -> Bool {
        let itemID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !itemID.isEmpty else {
            recordOperationFailure(assistantQueueItemUnavailableMessage)
            integrationStatusMessage = nil
            return false
        }

        // Voice handoff targets already-approved work. Force the narrow
        // runnable filter so stale persisted filters such as Done or Deferred
        // do not hide the item the user just approved.
        assistantQueueViewFilter = .approved
        assistantQueueSelectedItemIDs = []
        let approvedRefreshMessage = refreshAssistantQueueSnapshot()
        if setAssistantQueueSelection(id: itemID, selected: true) {
            recordOperationFailure(nil)
            integrationStatusMessage = nil
            return true
        }
        if let approvedRefreshMessage,
           approvedRefreshMessage != assistantQueueReceiptUnavailableMessage {
            recordOperationFailure(approvedRefreshMessage)
            integrationStatusMessage = nil
            return false
        }

        assistantQueueViewFilter = .all
        assistantQueueSelectedItemIDs = []
        let allRefreshMessage = refreshAssistantQueueSnapshot()
        if setAssistantQueueSelection(id: itemID, selected: true) {
            recordOperationFailure(nil)
            integrationStatusMessage = nil
            return true
        }
        if let allRefreshMessage,
           allRefreshMessage != assistantQueueReceiptUnavailableMessage {
            recordOperationFailure(allRefreshMessage)
            integrationStatusMessage = nil
            return false
        }

        recordOperationFailure(assistantQueueItemUnavailableMessage)
        integrationStatusMessage = nil
        return false
    }

    @discardableResult
    public func deferSelectedAssistantQueueItems() -> Bool {
        transitionSelectedAssistantQueueItems(
            eligible: \.canDefer,
            emptyMessage: String(localized: "No selected Assistant Queue items can be deferred."),
            invalidSelectionMessage: String(localized: "Every selected Assistant Queue item must support Defer."),
            successMessage: { count in
                String(format: String(localized: "Deferred %d Assistant Queue items."), count)
            }
        ) { item in
            try AssistantQueueStateMachine.deferForReview(item)
        }
    }

    @discardableResult
    public func rejectSelectedAssistantQueueItems() -> Bool {
        transitionSelectedAssistantQueueItems(
            eligible: \.canReject,
            emptyMessage: String(localized: "No selected Assistant Queue items can be rejected."),
            invalidSelectionMessage: String(localized: "Every selected Assistant Queue item must support Reject."),
            successMessage: { count in
                String(format: String(localized: "Rejected %d Assistant Queue items."), count)
            }
        ) { item in
            try AssistantQueueStateMachine.rejectForReview(item)
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use approveAssistantQueueItem(id:expectedMutationRevision:).")
    public func approveAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func approveAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
    }

    /// Approves and immediately runs one reviewed item while keeping approval
    /// and execution as separate durable transitions. Execution keeps the exact
    /// revision returned by approval so a concurrent mutation fails closed.
    @discardableResult
    public func approveAndRunAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        guard resolvedAssistantQueueExecutionCoordinator != nil else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Assistant Queue execution is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard let assistantQueueStore else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        do {
            let currentItem = try assistantQueueStore.get(id: id)
            guard currentItem.mutationRevision == expectedMutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            guard AssistantQueueExecutableActionPlanFactory.actionPlan(for: currentItem.payload) != nil else {
                _ = refreshAssistantQueueSnapshot()
                recordOperationFailure(Self.assistantQueueExecutionMessage(
                    for: AssistantQueueExecutionError.unsupportedPayload
                ))
                integrationStatusMessage = nil
                return false
            }
        } catch is AssistantQueueStaleReviewError {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueMutationFailure.staleUserMessage)
            integrationStatusMessage = nil
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
        var approvedRevision: String?
        let didApprove = transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            let approved = try AssistantQueueStateMachine.approve(
                item,
                reviewerID: "local-user"
            )
            approvedRevision = approved.mutationRevision
            return approved
        }
        guard didApprove else {
            return false
        }
        guard let approvedRevision else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(assistantQueueItemUnavailableMessage)
            integrationStatusMessage = nil
            return false
        }
        return runAssistantQueueItem(
            id: id,
            expectedMutationRevision: approvedRevision
        )
    }

    /// Missed-task reschedule suggestions still waiting for review in the
    /// currently visible Assistant Queue rows, in display order.
    public var openRescheduleSuggestionIDs: [String] {
        assistantQueueSnapshot.rows
            .filter { row in
                row.id.hasPrefix(MissedTaskRescheduleSuggestionPlanner.itemIDPrefix)
                    && row.state == .waitingReview
            }
            .map(\.id)
    }

    /// Approves every open reschedule suggestion through the same single-item
    /// approval path so audit granularity stays per-item. Stops at the first
    /// failure: the failed and remaining suggestions stay `waitingReview` and
    /// the per-item error surface keeps the failure message.
    @discardableResult
    public func approveAllRescheduleSuggestions() -> Int {
        let suggestionIDs = openRescheduleSuggestionIDs
        guard !suggestionIDs.isEmpty, !isApprovingAllRescheduleSuggestions else {
            return 0
        }

        isApprovingAllRescheduleSuggestions = true
        defer { isApprovingAllRescheduleSuggestions = false }

        var approvedCount = 0
        for suggestionID in suggestionIDs {
            guard let expectedRevision = assistantQueueSnapshot.rows
                .first(where: { $0.id == suggestionID })?
                .mutationRevision,
                approveAssistantQueueItem(
                    id: suggestionID,
                    expectedMutationRevision: expectedRevision
                ) else {
                // approveAssistantQueueItem already refreshed the snapshot and
                // published the per-item error message.
                return approvedCount
            }
            approvedCount += 1
        }

        integrationStatusMessage = String(
            format: String(localized: "Approved %d reschedule suggestions."),
            approvedCount
        )
        return approvedCount
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use deferAssistantQueueItem(id:expectedMutationRevision:).")
    public func deferAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func deferAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            try AssistantQueueStateMachine.deferForReview(item)
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use rejectAssistantQueueItem(id:expectedMutationRevision:).")
    public func rejectAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func rejectAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            try AssistantQueueStateMachine.rejectForReview(item)
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use editAssistantQueueItem(id:expectedMutationRevision:reviewReason:redactedSummary:).")
    public func editAssistantQueueItem(
        id: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func editAssistantQueueItem(
        id: String,
        expectedMutationRevision: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        editVersionedAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision,
            reviewReason: reviewReason,
            redactedSummary: redactedSummary
        )
    }

    private func editVersionedAssistantQueueItem(
        id: String,
        expectedMutationRevision: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision,
            successMessage: "Updated Assistant Queue review details.",
            preserveVisibleItemOnStale: true
        ) { item in
            return try AssistantQueueStateMachine.editReviewDetails(
                item,
                reviewReason: reviewReason,
                redactedSummary: redactedSummary
            )
        }
    }

    private func failClosedUnversionedAssistantQueueMutation() -> Bool {
        // Legacy callers cannot prove which review state the user saw. Refresh
        // for recovery guidance, but never infer a token and mutate current data.
        _ = refreshAssistantQueueSnapshot()
        recordOperationFailure(AssistantQueueMutationFailure.unversionedUserMessage)
        integrationStatusMessage = nil
        return false
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use retryAssistantQueueItem(id:expectedMutationRevision:).")
    public func retryAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func retryAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        let reopened = transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision,
            successMessage: "Reopened Assistant Queue item for review."
        ) { item in
            try AssistantQueueStateMachine.reopenFailedForReview(item)
        }
        guard reopened else {
            return false
        }
        do {
            try resolvedAssistantQueueExecutionCoordinator?
                .recordConversationRetryIfNeeded(id: id)
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(Self.assistantQueueExecutionMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use runAssistantQueueItem(id:expectedMutationRevision:).")
    public func runAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func runAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        guard let assistantQueueExecutionCoordinator = resolvedAssistantQueueExecutionCoordinator else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Assistant Queue execution is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        do {
            let result = try assistantQueueExecutionCoordinator.execute(
                id: id,
                expectedMutationRevision: expectedMutationRevision
            )
            recordPublicAlphaExecution(result.receipt, isRecovery: false)
            _ = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot()
            if result.item.state == .done {
                recordOperationFailure(nil)
                integrationStatusMessage = "Executed Assistant Queue item."
                onChange()
                return true
            }
            recordOperationFailure("Assistant Queue execution failed. Review the receipt before retrying.")
            integrationStatusMessage = nil
            onChange()
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot()
            recordOperationFailure(Self.assistantQueueExecutionMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    func recordPublicAlphaExecution(_ receipt: ExecutionReceipt, isRecovery: Bool) {
        guard [.succeeded, .failed, .canceled].contains(receipt.status),
              let queueID = receipt.assistantQueueItemID,
              let reference = try? publicAlphaMeasurement?.workReference(sourceID: queueID, stage: .reviewableActionPlan)
        else { return }
        publicAlphaMeasurement?.record(
            .localExecution, mark: receipt.status == .succeeded ? .completed : .failed,
            sourceID: receipt.id, workReference: reference,
            isRecovery: isRecovery,
            failureCategory: receipt.status == .succeeded ? nil : .reliability,
            at: receipt.finishedAt ?? receipt.createdAt
        )
    }

    private func transitionAssistantQueueItem(
        id: String,
        expectedMutationRevision: String? = nil,
        successMessage: String? = nil,
        preserveVisibleItemOnStale: Bool = false,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            recordOperationFailure("Assistant Queue is unavailable in this build.")
            return false
        }

        do {
            let updated = try assistantQueueStore.transition(id: id) { current in
                if let expectedMutationRevision,
                   current.mutationRevision != expectedMutationRevision {
                    throw AssistantQueueStaleReviewError()
                }
                return try transform(current)
            }
            if updated.state == .approved,
               let reference = try? publicAlphaMeasurement?.workReference(sourceID: id, stage: .reviewableActionPlan) {
                publicAlphaMeasurement?.record(
                    .approvedLocalAction, mark: .completed, sourceID: id, workReference: reference
                )
            }
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(nil)
            integrationStatusMessage = successMessage
            onChange()
            return true
        } catch AssistantQueueTransitionError.blockedItemCannotBeApproved {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Blocked Assistant Queue items cannot be approved.")
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.dangerousPayloadCannotBeApproved {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Dangerous action plans cannot be approved from Assistant Queue.")
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.costPreviewRequiredBeforeApproval {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Review the cost preview before approving this Assistant Queue item.")
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.managedCostCapExceeded {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("This managed cost preview exceeds the configured cap. Adjust the request before approving.")
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.terminalItemCannotTransition {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Assistant Queue item was already reviewed.")
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.retryRequiresFailedRunnablePayload {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Only failed runnable Assistant Queue items can be retried.")
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.editRequiresReviewableItem {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Only reviewable Assistant Queue items can be edited.")
            integrationStatusMessage = nil
            return false
        } catch is AssistantQueueReviewActionUnavailableError {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("This Assistant Queue item cannot be changed by that review action in its current state.")
            integrationStatusMessage = nil
            return false
        } catch is AssistantQueueStaleReviewError {
            if preserveVisibleItemOnStale {
                // A stale edit may have moved outside the active filter. Reveal
                // all states before refresh so SwiftUI preserves the row identity,
                // local draft, and focus until the reviewer reloads or cancels.
                assistantQueueViewFilter = .all
            }
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueMutationFailure.staleUserMessage)
            integrationStatusMessage = nil
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    private func transitionSelectedAssistantQueueItems(
        eligible: KeyPath<AssistantQueueReadModelRow, Bool>,
        emptyMessage: String,
        invalidSelectionMessage: String,
        successMessage: (Int) -> String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure("Assistant Queue is unavailable in this build.")
            return false
        }

        let selectedRows = assistantQueueSnapshot.rows.filter {
            assistantQueueSelectedItemIDs.contains($0.id)
        }
        guard !selectedRows.isEmpty else {
            recordOperationFailure(emptyMessage)
            integrationStatusMessage = nil
            return false
        }
        guard selectedRows.count == assistantQueueSelectedItemIDs.count,
              selectedRows.allSatisfy({ $0[keyPath: eligible] }),
              selectedRows.allSatisfy({ $0.mutationRevision != nil }) else {
            recordOperationFailure(invalidSelectionMessage)
            integrationStatusMessage = nil
            return false
        }
        let eligibleIDs = selectedRows.map(\.id)
        let expectedRevisions = Dictionary(
            uniqueKeysWithValues: selectedRows.compactMap { row in
                row.mutationRevision.map { (row.id, $0) }
            }
        )

        guard let atomicStore = assistantQueueStore as? any AtomicAssistantQueueStore else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("Batch Assistant Queue actions require an atomic queue store.")
            integrationStatusMessage = nil
            return false
        }

        do {
            _ = try atomicStore.transitionAll(
                ids: eligibleIDs,
                expectedRevisions: expectedRevisions,
                transform
            )
            assistantQueueSelectedItemIDs = []
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(nil)
            integrationStatusMessage = successMessage(eligibleIDs.count)
            onChange()
            return true
        } catch is AssistantQueueReviewActionUnavailableError {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure("This Assistant Queue item cannot be changed by that review action in its current state.")
            integrationStatusMessage = nil
            return false
        } catch is AssistantQueueStaleReviewError {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueMutationFailure.staleUserMessage)
            integrationStatusMessage = nil
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    private func pruneAssistantQueueSelectionToVisibleRows() {
        let batchSelectableIDs = Set(
            assistantQueueSnapshot.rows
                .filter { row in
                    (row.canDefer || row.canReject) && row.mutationRevision != nil
                }
                .map(\.id)
        )
        assistantQueueSelectedItemIDs.formIntersection(batchSelectableIDs)
    }

    private static func assistantQueueExecutionMessage(for error: Error) -> String {
        switch error {
        case is AssistantQueueStaleReviewError:
            return "This Assistant Queue item changed. Review the latest details before running it."
        case let error as AssistantQueueConversationLinkRequiresReviewError:
            return UserFacingErrorMessageSanitizer.message(
                from: error.reason,
                fallback: "Review this conversation action again."
            )
        case let error as AssistantQueueConversationLinkUnavailableError:
            return UserFacingErrorMessageSanitizer.message(
                from: error.reason,
                fallback: "Conversation execution evidence is unavailable."
            )
        case let error as AssistantQueueConversationLinkPersistenceError:
            return error.queueStateMarkedFailed
                ? "Conversation execution evidence could not be saved. Create a new reviewed plan before retrying."
                : "Conversation execution evidence and queue recovery could not be saved. Check local storage before retrying."
        case AssistantQueueExecutionError.unsupportedPayload:
            return "This Assistant Queue item cannot run from Project Board yet."
        case AssistantQueueExecutionError.receiptPersistenceFailed(let queueStateMarkedFailed):
            if queueStateMarkedFailed {
                return "Assistant Queue execution finished, but the execution receipt could not be saved. Fix receipt storage before retrying."
            }
            return "Assistant Queue execution finished, but receipt storage and queue state update both failed. Check local data storage before retrying."
        case AssistantQueueExecutionError.managedUsageLedgerPersistenceFailed(let queueStateMarkedFailed):
            if queueStateMarkedFailed {
                return "Assistant Queue execution finished, but managed AI usage could not be saved. Fix billing ledger storage before retrying."
            }
            return "Assistant Queue execution finished, but managed AI usage and queue state update both failed. Check local billing storage before retrying."
        case AssistantQueueExecutionError.managedUsageCapCheckFailed(let queueStateMarkedFailed):
            if queueStateMarkedFailed {
                return "Managed AI usage caps could not be checked. Fix billing ledger storage before retrying."
            }
            return "Managed AI usage caps could not be checked, and the queue state could not be updated. Check local billing storage before retrying."
        case AssistantQueueExecutionError.managedUsageCapExceeded(let projection, _):
            return projection.blockingReason
        case AssistantQueueTransitionError.approvalRequiredBeforeRunning:
            return "Approve this Assistant Queue item before running it."
        case AssistantQueueTransitionError.costPreviewRequiredBeforeApproval,
             AssistantQueueTransitionError.costPreviewRequiredBeforeRunning:
            return "Review the cost preview before running this Assistant Queue item."
        case AssistantQueueTransitionError.managedCostCapExceeded:
            return "This managed cost preview exceeds the configured cap. Adjust the request before running."
        case AssistantQueueTransitionError.approvedPayloadChanged:
            return "Review this Assistant Queue item again because it changed after approval."
        case AssistantQueueTransitionError.runningRequiredBeforeCompletion:
            return "Assistant Queue execution is not in a runnable state."
        case AssistantQueueTransitionError.blockedItemCannotBeApproved,
             AssistantQueueTransitionError.dangerousPayloadCannotBeApproved:
            return "Dangerous Assistant Queue items cannot be executed."
        case AssistantQueueTransitionError.terminalItemCannotTransition:
            return "Assistant Queue item was already reviewed."
        case AssistantQueueTransitionError.editRequiresReviewableItem:
            return "Only reviewable Assistant Queue items can be edited."
        default:
            return "Assistant Queue execution could not be completed."
        }
    }
}
