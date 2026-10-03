import Foundation

extension ProjectBoardViewModel {

    func saveApprovedAutomationExecutionReceipt(_ receipt: ApprovedAutomationExecutionReceipt) -> String? {
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return Self.executionReceiptStorageUnavailableMessage()
        }

        let commonReceipt = ExecutionReceiptFactory.makeApprovedAutomationReceipt(
            receipt,
            runID: "approved-automation-run:\(UUID().uuidString)",
            approvalID: nil,
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(commonReceipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            return String(localized: "Approved automation ran, but the execution receipt could not be saved.")
        }
    }

    func saveScheduleDraftApplyReceipt(
        writeCandidates: [ScheduleDraftApplyWriteCandidate],
        unscheduledTaskCount: Int,
        createdEvents: [ScheduleDraftApplyCreatedEvent],
        approvalID: String?,
        status: ExecutionReceiptStatus,
        errorSummary: String? = nil
    ) -> String? {
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return Self.executionReceiptStorageUnavailableMessage()
        }

        let projectTitlesByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
        let receipt = ExecutionReceiptFactory.makeScheduleDraftApplyReceipt(
            writeCandidates: writeCandidates,
            unscheduledTaskCount: unscheduledTaskCount,
            createdEvents: createdEvents,
            projectTitlesByID: projectTitlesByID,
            runID: "schedule-draft-apply-run:\(UUID().uuidString)",
            approvalID: approvalID,
            status: status,
            errorSummary: errorSummary,
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            if status == .failed {
                return String(localized: "Calendar apply failed, and the execution receipt could not be saved.")
            }
            if status == .skipped {
                return String(localized: "Schedule apply was skipped, and the execution receipt could not be saved.")
            }
            return String(localized: "Schedule applied to Calendar, but the execution receipt could not be saved.")
        }
    }

    func saveTaskAutomationDocumentDeliverableReceipt(
        _ deliverables: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask]
    ) -> String? {
        guard !deliverables.isEmpty else {
            return nil
        }
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return Self.executionReceiptStorageUnavailableMessage()
        }

        let receipt = ExecutionReceiptFactory.makeDocumentDeliverableReceipt(
            deliverables: deliverables,
            selectedTasks: selectedTasks,
            runID: "document-deliverable-run:\(UUID().uuidString)",
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            return String(localized: "Document deliverable drafts were prepared, but the execution receipt could not be saved.")
        }
    }

    private static func executionReceiptStorageUnavailableMessage() -> String {
        String(localized: "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work.")
    }

    func markExecutionReceiptStorageUnavailable() -> String {
        let message = Self.executionReceiptStorageUnavailableMessage()
        refreshExecutionReceiptHistorySnapshot()
        // Approved AI work must never complete without durable receipt storage;
        // otherwise the user cannot audit what was read, changed, sent, or billed.
        todayCommandFeedback = message
        integrationStatusMessage = message
        recordOperationFailure(message)
        return message
    }

    func persistApprovedAIWorkStartReceipt(_ receipt: ExecutionReceipt) -> String? {
        guard let executionReceiptStore else {
            return markExecutionReceiptStorageUnavailable()
        }
        do {
            // This reservation is intentionally persisted before any approved
            // write or review-evidence exposure so receipt storage failures
            // cannot leave unauditable AI work behind.
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            return markExecutionReceiptStorageUnavailable()
        }
    }

    func persistDocumentDeliverableStartReceipt(
        _ documentDeliverableReviews: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask]
    ) throws {
        guard !documentDeliverableReviews.isEmpty else {
            return
        }
        let receipt = ExecutionReceiptFactory.makeDocumentDeliverableReceipt(
            deliverables: documentDeliverableReviews,
            selectedTasks: selectedTasks,
            runID: "document-deliverable-start:\(UUID().uuidString)",
            status: .running,
            createdAt: Date()
        )
        guard persistApprovedAIWorkStartReceipt(receipt) == nil else {
            taskAutomationDocumentDeliverableReviews = []
            throw TaskAutoExecutionPlanningRequestError.executionReceiptStoreUnavailable
        }
    }

    func refreshExecutionReceiptHistorySnapshot(for snapshot: ProjectBoardSnapshot) {
        guard let executionReceiptStore else {
            executionReceiptHistorySnapshot = .empty
            executionUsageMeterSnapshot = ExecutionUsageMeterSnapshot(
                unavailableMessage: String(localized: "Execution usage meter is unavailable")
            )
            executionReceiptHistorySnapshotsByTaskID = [:]
            executionReceiptHistorySnapshotsByProjectID = [:]
            return
        }

        do {
            executionReceiptHistorySnapshot = try globalExecutionReceiptHistorySnapshot(store: executionReceiptStore)
            executionUsageMeterSnapshot = try executionUsageMeterSnapshot(store: executionReceiptStore)
            resetScopedExecutionReceiptHistorySnapshots()
        } catch {
            resetScopedExecutionReceiptHistorySnapshots()
            executionReceiptHistorySnapshot = ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
            executionUsageMeterSnapshot = ExecutionUsageMeterSnapshot(
                unavailableMessage: String(localized: "Execution usage meter is unavailable")
            )
        }
    }

    func executionUsageMeterSnapshot(
        store: any ExecutionReceiptStore
    ) throws -> ExecutionUsageMeterSnapshot {
        let receiptLimit = 500
        let receipts = try store.list(
            matching: ExecutionReceiptSearchFilter(visibleSurface: .auditLog),
            limit: receiptLimit
        )
        return ExecutionUsageMeterReadModel.snapshot(
            from: receipts,
            scopeLabel: String(format: String(localized: "Recent audit receipts (UTC buckets, up to %d receipts)"), receiptLimit)
        )
    }

    public func executionReceiptHistorySnapshot(forTaskID taskID: Int64) -> ExecutionReceiptHistorySnapshot {
        if let cached = executionReceiptHistorySnapshotsByTaskID[taskID] {
            return cached
        }

        let snapshot = scopedExecutionReceiptSnapshot(
            referenceKind: .task,
            referenceID: String(taskID),
            visibleSurface: .taskDetail
        )
        executionReceiptHistorySnapshotsByTaskID[taskID] = snapshot
        return snapshot
    }

    public func executionReceiptHistorySnapshot(forProjectID projectID: Int64) -> ExecutionReceiptHistorySnapshot {
        if let cached = executionReceiptHistorySnapshotsByProjectID[projectID] {
            return cached
        }

        let snapshot = scopedExecutionReceiptSnapshot(
            referenceKind: .project,
            referenceID: String(projectID),
            visibleSurface: .projectDetail
        )
        executionReceiptHistorySnapshotsByProjectID[projectID] = snapshot
        return snapshot
    }

    private func scopedExecutionReceiptSnapshot(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface
    ) -> ExecutionReceiptHistorySnapshot {
        guard let executionReceiptStore else {
            return ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: executionReceiptHistorySnapshot.unavailableMessage
            )
        }

        do {
            // Detail receipts are needed only for the currently opened inspector.
            // Loading every task and project scope during Project Board startup
            // creates N+1 file reads on DMG launches with large local histories.
            let receipts = try executionReceiptStore.list(
                referenceKind: referenceKind,
                referenceID: referenceID,
                visibleSurface: visibleSurface,
                limit: 5
            )
            return ExecutionReceiptHistoryReadModel.snapshot(from: receipts, limit: 5)
        } catch {
            return ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
        }
    }
}
