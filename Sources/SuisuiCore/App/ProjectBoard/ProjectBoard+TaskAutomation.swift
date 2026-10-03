import Foundation
import CryptoKit

extension ProjectBoardViewModel {

    @discardableResult
    public func prepareTaskAutomationReview(
        settings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        // Whole-board automation must reuse the deterministic planner before
        // any provider request so cadence, lookahead, trigger, and LLM budget
        // settings cannot be bypassed by a UI or future scheduled entry point.
        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )

        guard decision.status == .readyForReview else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = decision.reason
            return decision
        }

        taskAutomationReviewDecision = decision
        taskAutomationDocumentDeliverableReviews = []
        if let firstTask = decision.selectedTasks.first {
            selectedProjectID = firstTask.projectID
            selectedTaskID = firstTask.id
        }
        todayCommandFeedback = String(
            format: String(localized: "Prepared review-only automation for %d tasks."),
            decision.selectedTasks.count
        )
        integrationStatusMessage = String(
            format: String(localized: "Prepared review-only automation for %d tasks."),
            decision.selectedTasks.count
        )
        recordOperationFailure(nil)
        return decision
    }

    public func makeTaskAutomationPlanningRequest(
        settings: TaskAutoExecutionSettings,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft] = []
    ) throws -> PlanningRequest {
        let history = sessionAutomationHistory(for: referenceDate, calendar: calendar)
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let request = try buildTaskAutomationPlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
        let documentDeliverableReviews = documentDeliverableReviews(from: documentDeliverableDrafts)
        try persistDocumentDeliverableStartReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        )
        taskAutomationDocumentDeliverableReviews = documentDeliverableReviews
        if let receiptPersistenceMessage = saveTaskAutomationDocumentDeliverableReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        ) {
            recordOperationFailure(receiptPersistenceMessage)
        }

        // The session budget is charged only after the provider request is
        // successfully assembled. Throttled or invalid review attempts still
        // update feedback but do not consume the daily LLM review allowance.
        taskAutomationSessionHistory = TaskAutoExecutionHistory(
            lastRunAt: referenceDate,
            llmCallsToday: history.llmCallsToday + 1
        )
        return request
    }

    public func makeTaskAutomationPlanningRequest(
        settings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft] = []
    ) throws -> PlanningRequest {
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let request = try buildTaskAutomationPlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
        let documentDeliverableReviews = documentDeliverableReviews(from: documentDeliverableDrafts)
        try persistDocumentDeliverableStartReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        )
        taskAutomationDocumentDeliverableReviews = documentDeliverableReviews
        if let receiptPersistenceMessage = saveTaskAutomationDocumentDeliverableReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        ) {
            recordOperationFailure(receiptPersistenceMessage)
        }
        return request
    }

    private func buildTaskAutomationPlanningRequest(
        decision: TaskAutoExecutionDecision,
        settings: TaskAutoExecutionSettings,
        referenceDate: Date,
        timeZoneIdentifier: String,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft]
    ) throws -> PlanningRequest {
        try TaskAutoExecutionPlanningRequestBuilder().makePlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
    }

    func sessionAutomationHistory(
        for referenceDate: Date,
        calendar: Calendar
    ) -> TaskAutoExecutionHistory {
        guard let lastRunAt = taskAutomationSessionHistory.lastRunAt,
              calendar.isDate(lastRunAt, inSameDayAs: referenceDate) else {
            return TaskAutoExecutionHistory(lastRunAt: taskAutomationSessionHistory.lastRunAt, llmCallsToday: 0)
        }
        return taskAutomationSessionHistory
    }

    public func prepareAutomationReviewForSelectedTask() {
        guard let selectedTask else {
            todayCommandFeedback = String(localized: "Select a task before reviewing automation.")
            return
        }
        guard isEligibleForTaskAutomation(selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Only open unblocked tasks can be reviewed for automation.")
            return
        }

        taskAutomationReviewDecision = TaskAutoExecutionDecision(
            status: .readyForReview,
            selectedTasks: [selectedTask],
            reason: String(localized: "Selected task is ready for review-only automation."),
            llmCallBudgetRemaining: 1,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )
        taskAutomationDocumentDeliverableReviews = []
        integrationStatusMessage = String(format: String(localized: "Prepared review-only automation for \"%@\"."), selectedTask.title)
        recordOperationFailure(nil)
    }

    public func runApprovedAutomationForSelectedTask() {
        guard let selectedTask else {
            todayCommandFeedback = String(localized: "Select a task before running automation.")
            return
        }
        guard let reviewDecision = taskAutomationReviewDecision,
              let reviewedTask = reviewDecision.selectedTasks.first(where: { $0.id == selectedTask.id }) else {
            todayCommandFeedback = String(localized: "Review the automation plan before running it.")
            return
        }
        guard isEligibleForTaskAutomation(selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Task automation stopped because the task is blocked or complete.")
            return
        }
        guard matchesReviewedAutomationTask(reviewedTask, current: selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Review the automation plan again because the task changed after review.")
            return
        }
        let executionReceipt = ApprovedAutomationExecutionReceipt(
            task: selectedTask,
            statusAfter: .inProgress,
            reviewReason: reviewDecision.reason
        )
        guard executionReceiptStore != nil else {
            _ = markExecutionReceiptStorageUnavailable()
            return
        }
        guard let assistantQueueStore else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return
        }
        guard resolvedAssistantQueueExecutionCoordinator != nil else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(String(localized: "Assistant Queue execution is unavailable in this build."))
            integrationStatusMessage = nil
            return
        }
        do {
            var item = AssistantQueueAdapter.makeItem(
                actionPlan: approvedAutomationActionPlan(
                    for: selectedTask,
                    reviewReason: reviewDecision.reason
                ),
                sourceTranscript: String(localized: "Run approved local task automation."),
                interpretationSummary: String(localized: "Move reviewed task into active work."),
                reason: reviewDecision.reason,
                costPreview: .localOnly()
            )
            // Keep the queue entry non-actionable until the durable start
            // receipt exists. The queue and receipt stores cannot participate
            // in one transaction, so publishing waitingReview first could
            // expose work that has no auditable execution reservation.
            item.state = .blocked
            item.blockingReason = String(localized: "Execution receipt reservation must complete before this automation can be reviewed.")
            guard let inserted = try assistantQueueStore.insertIfAbsent(item) else {
                _ = refreshAssistantQueueSnapshot()
                recordOperationFailure(String(localized: "This reviewed automation is already in Assistant Queue. Review the existing item before running it."))
                integrationStatusMessage = nil
                return
            }
            guard persistApprovedAIWorkStartReceipt(
                ExecutionReceiptFactory.makeApprovedAutomationReceipt(
                    executionReceipt,
                    runID: "approved-automation-start:\(UUID().uuidString)",
                    approvalID: nil,
                    status: .running,
                    createdAt: Date()
                )
            ) == nil else {
                _ = refreshAssistantQueueSnapshot()
                return
            }
            guard let insertedMutationRevision = inserted.mutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            let reviewable = try assistantQueueStore.transition(id: inserted.id) { current in
                guard current.mutationRevision == insertedMutationRevision else {
                    throw AssistantQueueStaleReviewError()
                }
                // This is a publication barrier rather than a user transition:
                // only the successful receipt reservation may expose review
                // controls for this previously blocked provisional item.
                var updated = current
                updated.state = .waitingReview
                updated.blockingReason = nil
                updated.approval = nil
                return updated
            }
            guard let reviewableMutationRevision = reviewable.mutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            let approved = try assistantQueueStore.transition(id: reviewable.id) { current in
                guard current.mutationRevision == reviewableMutationRevision else {
                    throw AssistantQueueStaleReviewError()
                }
                return try AssistantQueueStateMachine.approve(
                    current,
                    reviewerID: "local-user"
                )
            }
            guard let approvedMutationRevision = approved.mutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            guard runAssistantQueueItem(
                id: approved.id,
                expectedMutationRevision: approvedMutationRevision
            ) else {
                return
            }
            load()
            selectedProjectID = selectedTask.projectID
            selectedTaskID = selectedTask.id
            let receipt = executionReceipt
            lastApprovedAutomationExecutionReceipt = receipt
            approvedAutomationExecutionReceipts.append(receipt)
            let receiptPersistenceMessage = saveApprovedAutomationExecutionReceipt(receipt)
            // Approved automation is still local and review-gated, but it must
            // leave a visible content-execution trail so a status move cannot
            // masquerade as executing the reviewed task body.
            todayCommandFeedback = String(format: String(localized: "Executed approved automation for \"%@\"."), selectedTask.title)
            integrationStatusMessage = String(format: String(localized: "Executed approved automation for \"%@\"."), selectedTask.title)
            recordOperationFailure(receiptPersistenceMessage)
            retainUnexecutedReviewedTasks(from: reviewDecision, excludingTaskID: selectedTask.id)
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before running automation.")
        } catch ProjectBoardStoreError.emptyTitle {
            recordOperationFailure("Task title is required.")
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
        }
    }

    private func isEligibleForTaskAutomation(_ task: ProjectBoardTask) -> Bool {
        task.status != .blocked && task.status != .done
    }

    private func approvedAutomationExecutionDetail(for task: ProjectBoardTask) -> String {
        let marker = "Suisui approved automation execution"
        let note = "\(marker): Run approved plan moved this task into active work after reviewing its current title, detail, priority, and due date."
        let trimmedDetail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.contains(marker) else {
            return task.detail
        }
        guard !trimmedDetail.isEmpty else {
            return note
        }
        return "\(trimmedDetail)\n\n\(note)"
    }

    private func approvedAutomationActionPlan(
        for task: ProjectBoardTask,
        reviewReason: String
    ) -> ActionPlan {
        var arguments: [String: JSONValue] = [
            "id": .number(Double(task.id)),
            "title": .string(task.title),
            "detail": .string(approvedAutomationExecutionDetail(for: task)),
            "projectId": .number(Double(task.projectID)),
            "status": .string(ProjectTaskStatus.inProgress.rawValue),
            "priority": .string(task.priority.rawValue)
        ]
        if let dueAt = task.dueAt {
            arguments["dueAt"] = .string(dueAt)
        }

        return ActionPlan(
            id: "approved-task-automation:\(task.id):\(Self.approvedAutomationPlanDigest(task: task, reviewReason: reviewReason))",
            userInput: "Run reviewed task automation for \(task.title).",
            summary: "Move reviewed task \(task.title) into active work after explicit approval.",
            actions: [
                PlanAction(
                    id: "approved-task-automation:update:\(task.id)",
                    tool: .taskUpdate,
                    arguments: arguments,
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func approvedAutomationPlanDigest(
        task: ProjectBoardTask,
        reviewReason: String
    ) -> String {
        let input = [
            String(task.id),
            String(task.projectID),
            task.title,
            task.detail,
            task.status.rawValue,
            task.priority.rawValue,
            task.dueAt ?? "",
            reviewReason
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    private func retainUnexecutedReviewedTasks(
        from reviewDecision: TaskAutoExecutionDecision,
        excludingTaskID executedTaskID: Int64
    ) {
        let remainingTasks = reviewDecision.selectedTasks.filter { $0.id != executedTaskID }
        guard !remainingTasks.isEmpty else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            return
        }
        // A configured review can contain several priority/due-date selected
        // tasks. Keep the still-unexecuted snapshots so one approved task run
        // cannot erase the user's review queue or hide missing execution
        // receipts for the rest of the batch.
        taskAutomationReviewDecision = TaskAutoExecutionDecision(
            status: reviewDecision.status,
            selectedTasks: remainingTasks,
            reason: reviewDecision.reason,
            llmCallBudgetRemaining: reviewDecision.llmCallBudgetRemaining,
            requiresUserApproval: reviewDecision.requiresUserApproval,
            allowsDirectExecution: reviewDecision.allowsDirectExecution
        )
    }

    func documentDeliverableReviews(
        from drafts: [DocumentAutomationDeliverableDraft]
    ) -> [TaskAutomationDocumentDeliverableReview] {
        // Keep the review UI bound to the same approval-gated draft set that
        // enters provider planning. Rendering only redacted previews lets users
        // audit source evidence without exposing raw document bodies in the UI.
        return TaskAutomationDocumentDeliverableReviewPolicy()
            .reviewableDeliverables(from: drafts)
            .map { deliverable in
                let draft = deliverable.draft
                return TaskAutomationDocumentDeliverableReview(
                    kind: draft.kind,
                    title: draft.title,
                    suggestedPath: draft.suggestedPath,
                    sourceDocuments: deliverable.sourceDocuments.map {
                        TaskAutomationDocumentSourceReview(
                            id: $0.id,
                            title: $0.title,
                            redactedSummary: $0.redactedSummary,
                            inclusionReason: $0.inclusionReason
                        )
                    },
                    rationale: draft.rationale,
                    riskLevel: draft.riskLevel,
                    requiresApproval: draft.requiresApproval
                )
            }
    }

    private func matchesReviewedAutomationTask(_ reviewedTask: ProjectBoardTask, current: ProjectBoardTask) -> Bool {
        // The LLM plan is based on a point-in-time task snapshot. Requiring the
        // same content and scheduling fields keeps a reviewed plan from being
        // reused after the user edits the work it was meant to describe.
        reviewedTask.id == current.id
            && reviewedTask.projectID == current.projectID
            && reviewedTask.title == current.title
            && reviewedTask.detail == current.detail
            && reviewedTask.status == current.status
            && reviewedTask.priority == current.priority
            && reviewedTask.dueAt == current.dueAt
    }
}
