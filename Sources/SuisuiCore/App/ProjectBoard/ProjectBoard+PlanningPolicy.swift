import Foundation

extension ProjectBoardViewModel {
    func missedTaskReviewState(
        taskID: Int64,
        referenceDate: Date,
        calendar: Calendar,
        didFail: inout Bool
    ) -> (lastReviewedAt: Date?, isNewlyMissed: Bool) {
        do {
            let lastReviewedAt = try missedTaskReviewStateStore.lastReviewedAt(taskID: taskID)
            return (
                lastReviewedAt,
                lastReviewedAt.map { !calendar.isDate($0, inSameDayAs: referenceDate) } ?? true
            )
        } catch {
            // Review state failures use a conservative fallback so a corrupted
            // local store cannot re-queue tasks the user already acknowledged.
            didFail = true
            return (nil, false)
        }
    }

    func todayAssistantRailContext(
        source: TodayAssistantRailSource,
        task: ProjectBoardTask,
        plan: TodayWorkflowPlan,
        referenceDate: Date,
        calendar: Calendar,
        nextActionTitle: String,
        nextActionReason: String
    ) -> TodayAssistantRailContext {
        TodayAssistantRailContext(
            source: source,
            task: task,
            projectTitle: projectTitle(for: task),
            nextActionTitle: nextActionTitle,
            nextActionReason: nextActionReason,
            nextBlockLabel: plan.timeBlocks.first { $0.task.id == task.id }?.label,
            notes: task.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "No notes yet.")
                : task.detail,
            // The rail is read-only: it derives progress from the local board snapshot and
            // reminder safety from Assistant Queue, so opening Today never mutates external apps.
            subtaskSummary: todayTaskProgressSummary(plan: plan, referenceDate: referenceDate, calendar: calendar),
            reminderSummary: todayReminderDraftSummary(for: task, referenceDate: referenceDate, calendar: calendar)
        )
    }

    private func todayTaskProgressSummary(
        plan: TodayWorkflowPlan,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let openCount = plan.tasks.filter { $0.status != .done }.count
        let completedCount = completedTodayTaskCount(referenceDate: referenceDate, calendar: calendar)

        switch (openCount, completedCount) {
        case (0, 0):
            return String(localized: "No open Today tasks.")
        case (let open, 0):
            let format = open == 1
                ? String(localized: "%d open Today task.")
                : String(localized: "%d open Today tasks.")
            return String(format: format, open)
        case (0, let completed):
            let format = completed == 1
                ? String(localized: "%d task done today.")
                : String(localized: "%d tasks done today.")
            return String(format: format, completed)
        case (let open, let completed):
            let format = open == 1
                ? String(localized: "%d open Today task, %d done today.")
                : String(localized: "%d open Today tasks, %d done today.")
            return String(format: format, open, completed)
        }
    }

    private func completedTodayTaskCount(referenceDate: Date, calendar: Calendar) -> Int {
        guard let dayInterval = calendar.dateInterval(of: .day, for: referenceDate) else {
            return 0
        }

        return snapshot.projects
            .filter { !$0.isArchived }
            .flatMap(\.tasks)
            .filter { task in
                guard task.status == .done else {
                    return false
                }
                guard let completedDate = WorkManagementAnalyticsBuilder.completedDate(for: task) else {
                    return false
                }
                return completedDate >= dayInterval.start && completedDate < dayInterval.end
            }
            .count
    }

    private func todayReminderDraftSummary(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let state: AssistantQueueState?
        do {
            state = try todayReminderDraftState(for: task, referenceDate: referenceDate, calendar: calendar)
        } catch {
            let message = String(localized: "Today reminder draft status is unavailable. Reload to try again.")
            recordProviderFailure(message)
            return message
        }
        guard let state else {
            return String(localized: "No Today reminder draft queued.")
        }

        switch state {
        case .captured, .interpreted, .drafted, .waitingReview:
            return String(localized: "Reminder draft is waiting for approval.")
        case .approved, .running:
            return String(localized: "Reminder draft is approved.")
        case .blocked:
            return String(localized: "Reminder draft needs attention.")
        case .failed:
            return String(localized: "Reminder draft failed and needs review.")
        case .deferred:
            return String(localized: "Reminder draft is deferred.")
        case .done:
            return String(localized: "Reminder draft was completed.")
        case .rejected:
            return String(localized: "Reminder draft was rejected.")
        }
    }

    private func todayReminderDraftState(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> AssistantQueueState? {
        let planID = Self.reminderPlanID(
            for: task,
            referenceDate: referenceDate,
            calendar: calendar,
            prefix: "today-reminder"
        )
        let itemID = "action-plan:\(planID)"

        // Match the exact current-day/content queue item. The visible queue snapshot
        // is filter-limited, so completed/deferred/rejected drafts may not be present.
        if let assistantQueueStore {
            do {
                return try assistantQueueStore.get(id: itemID).state
            } catch AssistantQueueStoreError.notFound {
                return nil
            }
        }

        return assistantQueueSnapshot.rows.first { $0.id == itemID }?.state
    }
}
