import Foundation
import CryptoKit

extension ProjectBoardViewModel {

    @discardableResult
    public func ingestAssistantQueueAutomationRequests(
        _ requests: [SyncAutomationRequestPayload]
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }

        guard !requests.isEmpty else {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "No remote automation requests to queue.")
            return true
        }

        var queuedItemIDs: [String] = []
        var existingItemIDs: [String] = []
        do {
            for request in requests {
                let item = Self.reviewableAutomationRequestItem(for: request)
                if try assistantQueueStore.insertIfAbsent(item) != nil {
                    queuedItemIDs.append(item.id)
                } else {
                    existingItemIDs.append(item.id)
                }
            }

            if let focusedID = queuedItemIDs.first ?? existingItemIDs.first {
                focusAssistantQueueItem(id: focusedID)
            } else {
                _ = refreshAssistantQueueSnapshot()
            }
            recordOperationFailure(nil)
            integrationStatusMessage = Self.automationRequestIngestMessage(
                queuedCount: queuedItemIDs.count,
                existingCount: existingItemIDs.count
            )
            if !queuedItemIDs.isEmpty {
                onChange()
            }
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    private static func reviewableAutomationRequestItem(
        for request: SyncAutomationRequestPayload
    ) -> AssistantQueueItem {
        var item = AssistantQueueAdapter.makeItem(automationRequest: sanitizedAutomationRequest(request))
        guard item.state != .rejected,
              AssistantQueueExecutableActionPlanFactory.actionPlan(for: item.payload) == nil else {
            return item
        }

        item.state = .blocked
        item.blockingReason = String(localized: "Remote automation request is missing executable task or development PR details.")
        return item
    }

    private static func sanitizedAutomationRequest(
        _ request: SyncAutomationRequestPayload
    ) -> SyncAutomationRequestPayload {
        var sanitized = request
        sanitized.id = sanitizedAutomationRequestID(for: request)
        sanitized.sourceClientID = sanitizedAutomationMetadata(request.sourceClientID, maxLength: 160)
        sanitized.toolName = sanitizedAutomationMetadata(request.toolName, maxLength: 160)
        sanitized.redactedArgumentSummary = sanitizedAutomationMetadata(
            request.redactedArgumentSummary,
            maxLength: 1_200
        )
        if var pullRequest = sanitized.developmentPullRequest {
            pullRequest.pullRequestURL = sanitizedAutomationMetadata(pullRequest.pullRequestURL, maxLength: 500)
            pullRequest.branchName = sanitizedAutomationMetadata(pullRequest.branchName, maxLength: 240)
            pullRequest.baseBranch = sanitizedAutomationMetadata(pullRequest.baseBranch, maxLength: 240)
            sanitized.developmentPullRequest = pullRequest
        }
        return sanitized
    }

    private static func sanitizedAutomationRequestID(
        for request: SyncAutomationRequestPayload
    ) -> String {
        // Remote request IDs can originate outside the Mac trust boundary. Hashing
        // keeps replay identity stable without persisting secrets or unbounded IDs.
        let digestInput = "\(request.source.rawValue):\(request.id.trimmingCharacters(in: .whitespacesAndNewlines))"
        let digest = SHA256.hash(data: Data(digestInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "remote-\(digest.prefix(24))"
    }

    private static func sanitizedAutomationMetadata(
        _ value: String?,
        maxLength: Int
    ) -> String? {
        guard let value else {
            return nil
        }

        let sanitized = sanitizedAutomationMetadata(value, maxLength: maxLength)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func sanitizedAutomationMetadata(
        _ value: String,
        maxLength: Int
    ) -> String {
        let redacted = DeveloperSecretRedactor()
            .redact(value.trimmingCharacters(in: .whitespacesAndNewlines))
            .text
        let localPathRedacted = LocalPathRedactor.redact(redacted)
        guard localPathRedacted.count > maxLength else {
            return localPathRedacted
        }
        return "\(localPathRedacted.prefix(maxLength))..."
    }

    private static func automationRequestIngestMessage(
        queuedCount: Int,
        existingCount: Int
    ) -> String {
        if queuedCount == 1, existingCount == 0 {
            return String(localized: "Queued 1 remote automation request for review.")
        }
        if queuedCount > 1, existingCount == 0 {
            return String(localized: "Queued \(queuedCount) remote automation requests for review.")
        }
        if queuedCount == 0, existingCount == 1 {
            return String(localized: "Remote automation request is already in Assistant Queue.")
        }
        if queuedCount == 0, existingCount > 1 {
            return String(localized: "Remote automation requests are already in Assistant Queue.")
        }
        return String(localized: "Queued \(queuedCount) remote automation requests for review; \(existingCount) were already in Assistant Queue.")
    }

    @discardableResult
    public func enqueueDoneFollowUpDraft(
        for taskID: Int64,
        sourceTranscript: String = "Done follow-up draft",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }

        guard let task = task(id: taskID),
              let draft = DoneFollowUpActionDraftBuilder.makeDraft(
                task: task,
                projectTitle: projectTitle(for: task),
                referenceDate: referenceDate,
                calendar: calendar
              ) else {
            recordOperationFailure(String(localized: "Select a completed task before queuing a Done follow-up."))
            integrationStatusMessage = nil
            return false
        }

        let validation = ActionPlanValidator().validate(draft.actionPlan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Done follow-up generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: draft.actionPlan,
            sourceTranscript: Self.sanitizedDoneFollowUpSourceTranscript(sourceTranscript),
            interpretationSummary: String(localized: "Done follow-up draft"),
            reason: draft.queueReason,
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Done follow-up draft is already in Assistant Queue.")
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Queued Done follow-up draft for approval.")
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func enqueueDailyPlanningActionDraft(
        kind: DailyPlanningActionDraftKind,
        transcript: String = "Today daily planning review",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }

        // An explicit action request owns its transcript/date/calendar. Only a
        // previously prepared review may override those arguments; the passive
        // Today preview must never silently become an action input.
        let review = dailyPlanningReview
            ?? makeDailyPlanningReview(
                transcript: transcript,
                on: referenceDate,
                calendar: calendar
            )
        dailyPlanningReview = review

        guard let recommendedTaskID = review.recommendedTaskID,
              let recommendedTask = task(id: recommendedTaskID),
              let draft = DailyPlanningActionDraftBuilder.makeDraft(
                kind: kind,
                review: review,
                task: recommendedTask,
                referenceDate: referenceDate,
                calendar: calendar
              ) else {
            recordOperationFailure(String(localized: "Daily Planning Review has no recommended task to queue."))
            integrationStatusMessage = nil
            return false
        }

        let validation = ActionPlanValidator().validate(draft.actionPlan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Daily Planning Review generated an invalid action plan."))
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: draft.actionPlan,
            sourceTranscript: Self.sanitizedDailyPlanningSourceTranscript(review.sourceTranscript),
            interpretationSummary: review.headline,
            reason: draft.queueReason,
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Daily Planning Review action is already in Assistant Queue.")
                todayCommandFeedback = integrationStatusMessage
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Queued Daily Planning Review action for approval.")
            todayCommandFeedback = integrationStatusMessage
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func enqueueTodayReminderDraft(
        for taskID: Int64,
        sourceTranscript: String = "Today reminder draft",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        enqueueReminderDraft(
            for: taskID,
            sourceTranscript: sourceTranscript,
            on: referenceDate,
            calendar: calendar,
            planIDPrefix: "today-reminder",
            actionIDPrefix: "today-reminder-task",
            userInput: "Queue Today reminder for approval",
            summary: "Today reminder draft for 1 task.",
            interpretationSummary: String(localized: "Today reminder draft"),
            reviewReason: Self.todayReminderQueueReason(taskCount: 1),
            queuedMessage: String(localized: "Queued Today reminder draft for approval."),
            alreadyQueuedMessage: String(localized: "Today reminder draft is already in Assistant Queue."),
            missingTaskMessage: String(localized: "Select an existing Today task before queuing a reminder."),
            fallbackTranscript: String(localized: "Today reminder draft")
        )
    }

    @discardableResult
    public func enqueueScheduleReminderDraft(
        for taskID: Int64,
        sourceTranscript: String = "Schedule smart reminder draft",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        enqueueReminderDraft(
            for: taskID,
            sourceTranscript: sourceTranscript,
            on: referenceDate,
            calendar: calendar,
            planIDPrefix: "schedule-reminder",
            actionIDPrefix: "schedule-reminder-task",
            userInput: "Queue Schedule reminder for approval",
            summary: "Schedule reminder draft for 1 task.",
            interpretationSummary: String(localized: "Schedule reminder draft"),
            reviewReason: Self.scheduleReminderQueueReason(taskCount: 1),
            queuedMessage: String(localized: "Queued Schedule reminder draft for approval."),
            alreadyQueuedMessage: String(localized: "Schedule reminder draft is already in Assistant Queue."),
            missingTaskMessage: String(localized: "Select an existing Schedule task before queuing a reminder."),
            fallbackTranscript: String(localized: "Schedule reminder draft")
        )
    }

    @discardableResult
    private func enqueueReminderDraft(
        for taskID: Int64,
        sourceTranscript: String,
        on referenceDate: Date,
        calendar: Calendar,
        planIDPrefix: String,
        actionIDPrefix: String,
        userInput: String,
        summary: String,
        interpretationSummary: String,
        reviewReason: String,
        queuedMessage: String,
        alreadyQueuedMessage: String,
        missingTaskMessage: String,
        fallbackTranscript: String
    ) -> Bool {
        // Reminders leave Suisui's local task store. Queueing an executable plan
        // keeps the write auditable and approval-gated before EventKit is touched.
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }

        guard let task = task(id: taskID) else {
            recordOperationFailure(missingTaskMessage)
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let plan = makeReminderActionPlan(
            for: task,
            referenceDate: referenceDate,
            calendar: calendar,
            planIDPrefix: planIDPrefix,
            actionIDPrefix: actionIDPrefix,
            userInput: userInput,
            summary: summary
        )
        let validation = ActionPlanValidator().validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Reminder draft generated an invalid action plan."))
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: Self.sanitizedReminderSourceTranscript(sourceTranscript, fallback: fallbackTranscript),
            interpretationSummary: interpretationSummary,
            reason: reviewReason,
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = alreadyQueuedMessage
                todayCommandFeedback = integrationStatusMessage
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = queuedMessage
            todayCommandFeedback = integrationStatusMessage
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func enqueueScheduleDraftCalendarApply(
        sourceTranscript: String = "Schedule draft Calendar apply",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        // Schedule drafts are generated by Suisui, but Calendar writes cross the
        // user's app boundary. Queueing the executable ActionPlan keeps the
        // generated work reviewable before any external event is created.
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            recordOperationFailure(String(localized: "Assistant Queue is unavailable in this build."))
            integrationStatusMessage = nil
            return false
        }

        guard let draft = scheduleDraft else {
            recordOperationFailure(String(localized: "Create a schedule draft before queuing Calendar apply."))
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let candidates = scheduleDraftWriteCandidates(for: draft)
        guard !candidates.isEmpty else {
            recordOperationFailure(String(localized: "Schedule draft has no calendar-ready time blocks to queue."))
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let plan = makeScheduleDraftCalendarApplyActionPlan(
            candidates: candidates,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let validation = ActionPlanValidator().validate(plan)
        guard validation.isValid else {
            recordOperationFailure(String(localized: "Schedule draft generated an invalid Calendar action plan."))
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: Self.sanitizedScheduleDraftSourceTranscript(sourceTranscript),
            interpretationSummary: String(localized: "Schedule draft Calendar apply"),
            reason: Self.scheduleDraftQueueReason(candidateCount: candidates.count),
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                recordOperationFailure(nil)
                integrationStatusMessage = String(localized: "Schedule draft Calendar apply is already in Assistant Queue.")
                todayCommandFeedback = integrationStatusMessage
                return true
            }

            focusAssistantQueueItem(id: item.id)
            recordOperationFailure(nil)
            integrationStatusMessage = String(localized: "Queued Schedule draft Calendar apply for approval.")
            todayCommandFeedback = integrationStatusMessage
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            recordOperationFailure(AssistantQueueStoreError.userMessage(for: error))
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func playDailyPlanningReviewReadout(
        using previewer: any TextToSpeechPreviewing,
        languageCode: String,
        voiceID: String,
        transcript: String = "Today daily planning review",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        await playDailyPlanningReviewReadout(
            using: previewer,
            languageCode: languageCode,
            voiceID: voiceID,
            provider: .localKokoro,
            transcript: transcript,
            on: referenceDate,
            calendar: calendar
        )
    }
}
