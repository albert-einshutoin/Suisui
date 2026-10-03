import Foundation

extension ProjectBoardViewModel {

    @discardableResult
    public func playDailyPlanningReviewReadout(
        using previewer: any TextToSpeechPreviewing,
        languageCode: String,
        voiceID: String,
        provider: TTSProvider,
        transcript: String = "Today daily planning review",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        // Readout callers with explicit inputs must receive a review built from
        // those inputs unless the user already prepared an explicit review.
        let review = dailyPlanningReview
            ?? makeDailyPlanningReview(
                transcript: transcript,
                on: referenceDate,
                calendar: calendar
            )
        dailyPlanningReview = review

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: languageCode,
            voiceID: voiceID,
            provider: provider
        )

        do {
            try await previewer.playPreview(request)
            integrationStatusMessage = nil
            todayCommandFeedback = String(localized: "Read daily planning review aloud.")
            return true
        } catch {
            integrationStatusMessage = nil
            todayCommandFeedback = Self.dailyPlanningReadoutFailureMessage(for: error)
            return false
        }
    }

    public func todayAssistantRailContext(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayAssistantRailContext {
        todayAssistantRailContext(
            plan: todayPlan(on: referenceDate, calendar: calendar),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func todayAssistantRailContext(
        plan: TodayWorkflowPlan,
        referenceDate: Date,
        calendar: Calendar
    ) -> TodayAssistantRailContext {
        // Keep explicit focus ahead of selection so the rail reflects the user's active work.
        if let todayFocusTaskID,
           let focusedTask = plan.tasks.first(where: { $0.id == todayFocusTaskID && $0.status != .done }) {
            return todayAssistantRailContext(
                source: .focused,
                task: focusedTask,
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar,
                nextActionTitle: String(localized: "Resume focused task"),
                nextActionReason: String(localized: "This task is already in focus.")
            )
        }

        if let selectedTask = selectedTask,
           plan.tasks.contains(where: { $0.id == selectedTask.id }) {
            return todayAssistantRailContext(
                source: .selected,
                task: selectedTask,
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar,
                nextActionTitle: String(localized: "Review selected task"),
                nextActionReason: String(localized: "You selected this Today task for review.")
            )
        }

        if let recommendedTask = plan.recommendedTask {
            return todayAssistantRailContext(
                source: .recommended,
                task: recommendedTask,
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar,
                nextActionTitle: String(localized: "Start recommended task"),
                nextActionReason: plan.recommendationReason
            )
        }

        return TodayAssistantRailContext(
            source: .empty,
            task: nil,
            projectTitle: String(localized: "No project selected"),
            nextActionTitle: String(localized: "Capture the next task"),
            nextActionReason: plan.recommendationReason,
            nextBlockLabel: nil,
            notes: String(localized: "Add a Today command or schedule Inbox work to create a focus path."),
            // Subtasks remain local command drafts. Reminder writes now cross an
            // app boundary, so the rail points users to Assistant Queue review.
            subtaskSummary: String(localized: "Subtask capture is staged through the Today command."),
            reminderSummary: String(localized: "Reminder drafts queue for approval before external writes.")
        )
    }

    @discardableResult
    public func submitTodayCommand(_ rawTitle: String) -> ProjectBoardTask? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            todayCommandFeedback = String(localized: "Today command needs a title.")
            return nil
        }

        let task = createInboxTask(title: title)
        if task != nil {
            todayCommandFeedback = String(format: String(localized: "Added \"%@\" to Inbox."), title)
        }
        return task
    }

    /// Records a local break suggestion for the Today review surface. This is
    /// deliberately feedback-only: it does not create a task or write to any
    /// Calendar/Reminder provider from a recommendation card.
    public func suggestTodayBreak() {
        todayCommandFeedback = String(localized: "Take a short break before the next task.")
    }

    public func todayRecommendationChips(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodayRecommendationChip] {
        todayRecommendationChips(
            from: todayTasks(on: referenceDate, calendar: calendar),
            on: referenceDate,
            calendar: calendar
        )
    }

    func todayRecommendationChips(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [TodayRecommendationChip] {
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        var usedTaskIDs = Set<Int64>()

        func firstTask(
            matching predicate: (ProjectBoardTask) -> Bool
        ) -> ProjectBoardTask? {
            for task in tasks {
                guard !usedTaskIDs.contains(task.id), predicate(task) else {
                    continue
                }
                return task
            }
            return nil
        }

        var chips: [TodayRecommendationChip] = []
        if let task = firstTask(matching: { $0.status == .blocked }) {
            usedTaskIDs.insert(task.id)
            chips.append(TodayRecommendationChip(
                kind: .blocker,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "Resolve blocker"),
                systemImage: "exclamationmark.triangle",
                reason: String(format: String(localized: "%@ is blocking today's plan."), task.title)
            ))
        }
        // Prefer yesterday's overdue for the chip so older mid-week dues do not
        // steal the slot from a distinct "clear overdue" action.
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart
        if let task = firstTask(matching: {
            guard let due = LocalPlanningPolicy.dueDate(for: $0.dueAt, calendar: calendar) else { return false }
            return due < dayStart && due >= yesterdayStart
        }) ?? firstTask(matching: {
            LocalPlanningPolicy.dueDate(for: $0.dueAt, calendar: calendar).map { $0 < dayStart } == true
        }) {
            usedTaskIDs.insert(task.id)
            chips.append(TodayRecommendationChip(
                kind: .overdue,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "Clear overdue"),
                systemImage: "clock.badge.exclamationmark",
                reason: String(format: String(localized: "%@ is overdue."), task.title)
            ))
        }
        if let task = firstTask(matching: { $0.priority == .high }) {
            chips.append(TodayRecommendationChip(
                kind: .highPriority,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "High priority"),
                systemImage: "flag.fill",
                reason: String(format: String(localized: "%@ is high priority."), task.title)
            ))
        }

        return chips
    }

    public func missedTaskReview(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current,
        staleAfterDays: Int = 7
    ) -> MissedTaskReviewSummary {
        missedTaskReview(
            on: referenceDate,
            calendar: calendar,
            staleAfterDays: staleAfterDays,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    func missedTaskReview(
        on referenceDate: Date,
        calendar: Calendar,
        staleAfterDays: Int = 7,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> MissedTaskReviewSummary {
        guard let dayInterval = calendar.dateInterval(of: .day, for: referenceDate) else {
            return .empty
        }

        let staleCutoff = calendar.date(byAdding: .day, value: -max(staleAfterDays, 1), to: dayInterval.start) ?? dayInterval.start
        var didFailToLoadReviewState = false
        let items = inputs.committedActiveProjects
            .flatMap { project in
                project.tasks.compactMap { task -> MissedTaskReviewItem? in
                    guard task.status != .done else {
                        return nil
                    }

                    let reasons = LocalPlanningPolicy.missedTaskReasons(
                        for: task,
                        dayInterval: dayInterval,
                        staleCutoff: staleCutoff
                    )
                    guard !reasons.isEmpty else {
                        return nil
                    }

                    let reviewState = missedTaskReviewState(
                        taskID: task.id,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        didFail: &didFailToLoadReviewState
                    )
                    return MissedTaskReviewItem(
                        task: task,
                        projectTitle: project.title,
                        reasons: reasons,
                        lastReviewedAt: reviewState.lastReviewedAt,
                        isNewlyMissed: reviewState.isNewlyMissed
                    )
                }
            }
            .sorted(by: LocalPlanningPolicy.sortMissedTaskReviewItems)

        let immediateQueue = items
            .filter { $0.isNewlyMissed && LocalPlanningPolicy.isImmediateMissedTask($0) }
            .sorted(by: LocalPlanningPolicy.sortMissedTaskReviewItems)

        return MissedTaskReviewSummary(
            items: items,
            immediateQueue: immediateQueue,
            overdueCount: items.filter { $0.reasons.contains(.overdue) }.count,
            dueTodayCount: items.filter { $0.reasons.contains(.dueToday) }.count,
            blockedCount: items.filter { $0.reasons.contains(.blocked) }.count,
            unscheduledCount: items.filter { $0.reasons.contains(.unscheduled) }.count,
            staleCount: items.filter { $0.reasons.contains(.stale) }.count,
            newlyMissedCount: immediateQueue.count,
            stateErrorMessage: didFailToLoadReviewState ? String(localized: "Missed task review state could not be loaded.") : nil
        )
    }

    @discardableResult
    public func scheduleMissedTaskDailyFollowUp(
        settings: AppSettings,
        dateProvider: any DateProvider = SystemDateProvider(),
        calendar: Calendar? = nil
    ) -> MissedTaskDailyFollowUpResult? {
        guard let missedTaskFollowUpNotificationClient else {
            return nil
        }

        let normalizedSettings = settings.normalizedForRuntime
        let reviewCalendar = calendar ?? Self.reviewCalendar(timeZoneIdentifier: normalizedSettings.timeZoneIdentifier)
        let summary = missedTaskReview(on: dateProvider.now, calendar: reviewCalendar)
        let result = MissedTaskDailyFollowUpScheduler(
            stateStore: missedTaskReviewStateStore,
            notificationClient: missedTaskFollowUpNotificationClient,
            dateProvider: dateProvider,
            settings: normalizedSettings
        )
        .scheduleIfNeeded(summary: summary)

        if let assistantQueueStore {
            // Best-effort assistant suggestion: overdue/stalled tasks gain a
            // one-tap "reschedule to tomorrow" item in the Assistant Queue.
            _ = MissedTaskRescheduleSuggestionPlanner(
                queueStore: assistantQueueStore,
                dateProvider: dateProvider,
                settings: normalizedSettings
            ).enqueueSuggestions(for: summary)
        }

        if result.status == .failed {
            integrationStatusMessage = result.message
        }
        return result
    }

    public func completeMissedTask(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            recordOperationFailure("Task is no longer available.")
            return
        }

        let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()
        do {
            _ = try store.moveTask(id: taskID, to: .done)
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            load()
            recordStatusMoveUndo(
                previousTasks: [task],
                to: .done,
                taskIDsBeforeMutation: taskIDsBeforeMutation
            )
            selectedProjectID = task.projectID
            selectedTaskID = taskID
            todayCommandFeedback = String(format: String(localized: "Completed \"%@\" from missed review."), task.title)
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before moving tasks.")
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
        }
    }

    public func rescheduleMissedTaskForToday(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            recordOperationFailure("Task is no longer available.")
            return
        }

        do {
            let updatedTask = try store.updateTask(
                id: taskID,
                ProjectBoardTaskDraft(
                    projectID: task.projectID,
                    title: task.title,
                    detail: task.detail,
                    status: .planned,
                    priority: task.priority,
                    dueAt: ISO8601DateFormatter().string(from: referenceDate),
                    recurrence: task.recurrence
                )
            )
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            load()
            selectedProjectID = updatedTask.projectID
            selectedTaskID = updatedTask.id
            todayCommandFeedback = String(format: String(localized: "Rescheduled \"%@\" for today."), task.title)
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordOperationFailure("Restore the project before editing tasks.")
        } catch ProjectBoardStoreError.emptyTitle {
            recordOperationFailure("Task title is required.")
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
        }
    }

    public func deferMissedTaskForLater(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            recordOperationFailure("Task is no longer available.")
            return
        }

        do {
            // Deferring from Catch Up is review-state only: it removes the item
            // from today's recovery queue without hiding or mutating the task.
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            refreshMissedTaskReviewReadModel(on: referenceDate)
            selectedProjectID = task.projectID
            selectedTaskID = task.id
            todayCommandFeedback = String(format: String(localized: "Deferred \"%@\" from today's missed queue."), task.title)
            recordOperationFailure(nil)
            onChange()
        } catch {
            recordOperationFailure(LocalWorkspaceFailureMessage.message(for: error))
        }
    }

    public func startFocus(taskID: Int64) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            recordOperationFailure("Task is no longer available.")
            return
        }

        // Focus is intentionally local UI state. It must not move task status or
        // write Calendar/Reminder records before the user reviews a schedule.
        todayFocusTaskID = task.id
        selectedProjectID = task.projectID
        selectedTaskID = task.id
        todayCommandFeedback = String(format: String(localized: "Focused on \"%@\"."), task.title)
        recordOperationFailure(nil)
    }

    @discardableResult
    public func prepareTaskAutomationReview(
        settings: TaskAutoExecutionSettings,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        let history = sessionAutomationHistory(for: referenceDate, calendar: calendar)
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Preparing a local review candidate must not spend the LLM API budget.
        // The session ledger is charged only after a provider request is
        // successfully assembled, so opening the review UI cannot exhaust the
        // user's configured daily automation allowance.
        taskAutomationSessionHistory = history
        return decision
    }

    private static func dailyPlanningReadoutFailureMessage(for error: Error) -> String {
        let rawMessage: String
        if let error = error as? TTSProviderError {
            rawMessage = error.userMessage
        } else if let error = error as? SpeechAudioPlaybackError {
            rawMessage = error.userMessage
        } else {
            rawMessage = UserFacingErrorMessageSanitizer.message(from: error)
        }
        let redactedSecrets = UserFacingErrorMessageSanitizer.message(
            from: rawMessage,
            fallback: "Playback failed."
        )
        return String(
            format: String(localized: "Daily Planning readout failed. %@"),
            LocalPathRedactor.redact(redactedSecrets)
        )
    }

    private static func reviewCalendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }
}
