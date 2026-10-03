import Foundation

extension ProjectBoardViewModel {

    @discardableResult
    public func prepareTodayScheduleDraft(
        prioritizing taskID: Int64? = nil,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayScheduleDraft {
        let plan = todayPlan(on: referenceDate, calendar: calendar)
        let timeBlocks = LocalPlanningPolicy.prioritizedTodayTimeBlocks(
            plan: plan,
            taskID: taskID,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let draft = TodayScheduleDraft(timeBlocks: timeBlocks)
        todayScheduleDraft = draft
        todayCommandFeedback = String(format: String(localized: "Prepared %d time blocks for schedule review."), draft.timeBlocks.count)
        return draft
    }

    @discardableResult
    public func prepareScheduleDraft(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduleDraft {
        let todayDraft = prepareTodayScheduleDraft(on: referenceDate, calendar: calendar)
        let draft = ScheduleDraft(
            timeBlocks: todayDraft.timeBlocks,
            unscheduledTasks: unscheduledScheduleTasks(excludingTaskIDs: [])
        )
        let affectedTaskIDs = Set((scheduleDraft?.timeBlocks ?? []).map(\.task.id))
            .union(draft.timeBlocks.map(\.task.id))
        guard invalidateApprovedScheduleQueueItems(taskIDs: affectedTaskIDs) else {
            return scheduleDraft ?? draft
        }
        scheduleDraft = draft
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        scheduleApplyResult = nil
        todayCommandFeedback = String(
            format: String(localized: "Prepared schedule draft with %d time blocks and %d unscheduled tasks."),
            draft.timeBlocks.count,
            draft.unscheduledTasks.count
        )
        return draft
    }

    @discardableResult
    public func addUnscheduledTaskToScheduleDraft(
        taskID: Int64,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let task = unscheduledScheduleTasks(excludingTaskIDs: []).first(where: { $0.id == taskID }) else {
            recordOperationFailure(String(localized: "Select an unscheduled task before adding it to the draft."))
            todayCommandFeedback = errorMessage
            return false
        }

        var draft = scheduleDraftForAddingUnscheduledTask(on: referenceDate, calendar: calendar)
        if draft.timeBlocks.contains(where: { $0.task.id == taskID }) {
            todayCommandFeedback = String(localized: "Unscheduled task is already in the schedule draft.")
            recordOperationFailure(nil)
            return true
        }

        guard let block = LocalPlanningPolicy.scheduleDraftTimeBlock(
            for: task,
            existingBlocks: draft.timeBlocks,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            recordOperationFailure(String(localized: "Schedule draft could not add the unscheduled task."))
            todayCommandFeedback = errorMessage
            return false
        }

        // This is a local review artifact, not task scheduling. The task keeps
        // its nil due date until the user separately approves Calendar/app writes.
        let affectedTaskIDs = Set((scheduleDraft?.timeBlocks ?? []).map(\.task.id))
            .union(draft.timeBlocks.map(\.task.id))
        guard invalidateApprovedScheduleQueueItems(taskIDs: affectedTaskIDs) else {
            return false
        }
        draft.timeBlocks.append(block)
        draft.unscheduledTasks.removeAll { $0.id == taskID }
        scheduleDraft = draft
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        scheduleApplyResult = nil
        recordOperationFailure(nil)
        todayCommandFeedback = String(format: String(localized: "Added \"%@\" to the local schedule draft."), task.title)
        return true
    }

    @discardableResult
    public func placeTaskInScheduleDraft(
        taskID: Int64,
        startAt: Date,
        endAt: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard endAt > startAt else {
            recordOperationFailure(String(localized: "End time must be later than start time."))
            todayCommandFeedback = errorMessage
            return false
        }
        guard let task = snapshot.projects
            .filter({ !$0.isArchived && !$0.isCompleted })
            .flatMap(\.tasks)
            .first(where: { $0.id == taskID && $0.status != .done }) else {
            recordOperationFailure(String(localized: "Select an active task before placing it on the schedule."))
            todayCommandFeedback = errorMessage
            return false
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = calendar.timeZone
        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.dateFormat = "HH:mm"
        let block = TodayTimeBlock(
            label: "\(labelFormatter.string(from: startAt))-\(labelFormatter.string(from: endAt))",
            task: task,
            startAt: isoFormatter.string(from: startAt),
            endAt: isoFormatter.string(from: endAt)
        )

        let affectedTaskIDs = Set((scheduleDraft?.timeBlocks ?? []).map(\.task.id))
            .union([taskID])
        guard invalidateApprovedScheduleQueueItems(taskIDs: affectedTaskIDs) else {
            return false
        }

        var draft = scheduleDraft ?? ScheduleDraft(
            timeBlocks: [],
            unscheduledTasks: unscheduledScheduleTasks(excludingTaskIDs: [])
        )
        if let visibleWeek = calendar.dateInterval(of: .weekOfYear, for: startAt) {
            draft.timeBlocks.removeAll { existing in
                guard let rawStartAt = existing.startAt,
                      let existingStart = isoFormatter.date(from: rawStartAt) else {
                    return true
                }
                return !visibleWeek.contains(existingStart)
            }
        }
        draft.timeBlocks.removeAll { $0.task.id == taskID }
        draft.timeBlocks.append(block)
        draft.timeBlocks.sort { lhs, rhs in
            guard let lhsStart = lhs.startAt.flatMap({ isoFormatter.date(from: $0) }),
                  let rhsStart = rhs.startAt.flatMap({ isoFormatter.date(from: $0) }) else {
                return lhs.task.id < rhs.task.id
            }
            return lhsStart == rhsStart ? lhs.task.id < rhs.task.id : lhsStart < rhsStart
        }
        draft.unscheduledTasks = unscheduledScheduleTasks(
            excludingTaskIDs: Set(draft.timeBlocks.map(\.task.id))
        )
        scheduleDraft = draft
        rebuildScheduleReadModel(around: startAt, calendar: calendar)
        scheduleApplyResult = nil
        recordOperationFailure(nil)
        todayCommandFeedback = String(format: String(localized: "Placed \"%@\" in the local schedule draft."), task.title)
        return true
    }

    @discardableResult
    public func removeTaskFromScheduleDraft(
        taskID: Int64,
        around referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard var draft = scheduleDraft,
              draft.timeBlocks.contains(where: { $0.task.id == taskID }) else {
            recordOperationFailure(String(localized: "Task is not in the schedule draft."))
            todayCommandFeedback = errorMessage
            return false
        }

        let affectedTaskIDs = Set(draft.timeBlocks.map(\.task.id))
        guard invalidateApprovedScheduleQueueItems(taskIDs: affectedTaskIDs) else {
            return false
        }
        draft.timeBlocks.removeAll { $0.task.id == taskID }
        draft.unscheduledTasks = unscheduledScheduleTasks(
            excludingTaskIDs: Set(draft.timeBlocks.map(\.task.id))
        )
        scheduleDraft = draft
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        scheduleApplyResult = nil
        recordOperationFailure(nil)
        todayCommandFeedback = String(localized: "Removed task from the local schedule draft.")
        return true
    }

    private func scheduleDraftForAddingUnscheduledTask(
        on referenceDate: Date,
        calendar: Calendar
    ) -> ScheduleDraft {
        guard let draft = scheduleDraft else {
            return prepareScheduleDraft(on: referenceDate, calendar: calendar)
        }
        guard scheduleDraft(draft, isAlignedWith: referenceDate, calendar: calendar) else {
            // A Schedule draft is approval payload. Regenerating stale day-local
            // blocks prevents a visible-day Add action from queuing old Calendar writes.
            return prepareScheduleDraft(on: referenceDate, calendar: calendar)
        }
        return draft
    }

    func scheduleDraft(
        _ draft: ScheduleDraft,
        isAlignedWith referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard !draft.timeBlocks.isEmpty else {
            return true
        }
        let formatter = ISO8601DateFormatter()
        let referenceDayKey = Self.scheduleDraftDayKey(referenceDate: referenceDate, calendar: calendar)
        return draft.timeBlocks.allSatisfy { block in
            guard let rawStartAt = block.startAt,
                  let start = formatter.date(from: rawStartAt) else {
                return false
            }
            return Self.scheduleDraftDayKey(referenceDate: start, calendar: calendar) == referenceDayKey
        }
    }

    @discardableResult
    public func applyScheduleDraftToCalendar(approvalToken: String?) -> ScheduleApplyResult {
        guard approvalToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            scheduleApplyResult = .approvalRequired
            todayCommandFeedback = String(localized: "Schedule review approval is required before Calendar write.")
            return .approvalRequired
        }
        let executionApprovalID = Self.scheduleDraftApplyApprovalID()
        guard let draft = scheduleDraft else {
            scheduleApplyResult = .noDraft
            todayCommandFeedback = String(localized: "Create a schedule draft before applying to Calendar.")
            recordOperationFailure(saveScheduleDraftApplyReceipt(
                writeCandidates: [],
                unscheduledTaskCount: 0,
                createdEvents: [],
                approvalID: executionApprovalID,
                status: .skipped
            ))
            return .noDraft
        }
        let writeCandidates = scheduleDraftWriteCandidates(for: draft)
        guard let scheduleCalendarClient else {
            scheduleApplyResult = .calendarNotConfigured
            todayCommandFeedback = String(localized: "Calendar is not configured. No external write was performed.")
            recordOperationFailure(saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: [],
                approvalID: executionApprovalID,
                status: .skipped
            ))
            return .calendarNotConfigured
        }
        let projectTitlesByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
        if let receiptStorageMessage = persistApprovedAIWorkStartReceipt(
            ExecutionReceiptFactory.makeScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: [],
                projectTitlesByID: projectTitlesByID,
                runID: "schedule-draft-apply-start:\(UUID().uuidString)",
                approvalID: executionApprovalID,
                status: .running,
                createdAt: Date()
            )
        ) {
            let result = ScheduleApplyResult.failed(receiptStorageMessage)
            scheduleApplyResult = result
            return result
        }

        var createdEvents: [ScheduleDraftApplyCreatedEvent] = []
        do {
            for candidate in writeCandidates {
                let event = try scheduleCalendarClient.createEvent(CalendarEventDraft(
                    title: candidate.taskTitle,
                    startAt: candidate.startAt,
                    endAt: candidate.endAt,
                    notes: String(localized: "Created from a reviewed Suisui schedule draft.")
                ))
                createdEvents.append(ScheduleDraftApplyCreatedEvent(candidate: candidate, record: event))
            }
            let result = ScheduleApplyResult.applied(eventCount: createdEvents.count)
            scheduleApplyResult = result
            todayCommandFeedback = String(format: String(localized: "Applied %d Calendar events."), createdEvents.count)
            recordOperationFailure(saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: createdEvents,
                approvalID: executionApprovalID,
                status: .succeeded
            ))
            return result
        } catch {
            let message = LocalWorkspaceFailureMessage.message(for: error)
            let result = ScheduleApplyResult.failed(message)
            scheduleApplyResult = result
            todayCommandFeedback = String(localized: "Calendar apply failed.")
            // The Calendar client does not expose rollback, so preserve partial
            // write evidence in a failed receipt instead of hiding the attempt.
            recordOperationFailure(saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: createdEvents,
                approvalID: executionApprovalID,
                status: .failed,
                errorSummary: message
            ))
            return result
        }
    }
}
