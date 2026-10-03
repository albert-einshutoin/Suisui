import Foundation
import CryptoKit

extension ProjectBoardViewModel {

    static func scheduleDraftApplyApprovalID() -> String {
        "schedule-draft-apply-approval:\(UUID().uuidString)"
    }

    func scheduleDraftWriteCandidates(for draft: ScheduleDraft) -> [ScheduleDraftApplyWriteCandidate] {
        draft.timeBlocks.compactMap(ScheduleDraftApplyWriteCandidate.init(block:))
    }

    func invalidateApprovedScheduleQueueItems(taskIDs: Set<Int64>) -> Bool {
        guard !taskIDs.isEmpty, let assistantQueueStore else {
            return true
        }

        do {
            // This safety invalidation must inspect every approved item. A windowed
            // fetch could leave an older approved Calendar proposal executable.
            let items = try assistantQueueStore.list(filter: .states([.approved], limit: Int.max))
            for item in items where item.state == .approved {
                guard case .actionPlan(let plan) = item.payload,
                      plan.actions.contains(where: {
                          Self.isCalendarProposalAction($0)
                              && taskIDs.contains(Self.calendarTaskID(in: $0) ?? -1)
                      }) else {
                    continue
                }

                _ = try assistantQueueStore.transition(id: item.id) { current in
                    guard current.state == .approved,
                          case .actionPlan(let currentPlan) = current.payload,
                          currentPlan.actions.contains(where: {
                              Self.isCalendarProposalAction($0)
                                  && taskIDs.contains(Self.calendarTaskID(in: $0) ?? -1)
                          }) else {
                        return current
                    }
                    return try AssistantQueueStateMachine.editReviewDetails(
                        current,
                        reviewReason: "Schedule proposal changed. Review the latest Calendar time before approval.",
                        redactedSummary: current.redactedSummary
                    )
                }
            }
            _ = refreshAssistantQueueSnapshot()
            return true
        } catch {
            let message = AssistantQueueStoreError.userMessage(for: error)
            recordOperationFailure(message)
            todayCommandFeedback = message
            return false
        }
    }

    private static func isCalendarProposalAction(_ action: PlanAction) -> Bool {
        switch action.tool {
        case .calendarCreateEvent, .calendarCreateDeadline, .calendarCreateWorkBlock:
            guard let taskID = calendarTaskID(in: action),
                  action.arguments["proposalID"]?.stringValue == CalendarProposalIdentity.make(taskID: taskID) else {
                return false
            }
            return true
        default:
            return false
        }
    }

    private static func calendarTaskID(in action: PlanAction) -> Int64? {
        switch action.arguments["taskId"] {
        case .number(let value)? where value.isFinite && value.rounded(.towardZero) == value:
            return Int64(exactly: value)
        case .string(let value)?:
            return Int64(value)
        default:
            return nil
        }
    }

    func makeReminderActionPlan(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar,
        planIDPrefix: String,
        actionIDPrefix: String,
        userInput: String,
        summary: String
    ) -> ActionPlan {
        var arguments: [String: JSONValue] = [
            "title": .string(Self.reminderTitle(for: task)),
            "taskId": .number(Double(task.id)),
            "projectId": .number(Double(task.projectID))
        ]
        if let dueAt = Self.trimmedOptional(task.dueAt) {
            arguments["dueAt"] = .string(dueAt)
        }

        return ActionPlan(
            id: Self.reminderPlanID(
                for: task,
                referenceDate: referenceDate,
                calendar: calendar,
                prefix: planIDPrefix
            ),
            userInput: userInput,
            summary: summary,
            actions: [
                PlanAction(
                    id: "\(actionIDPrefix)-\(task.id)",
                    tool: .remindersCreate,
                    arguments: arguments,
                    riskLevel: .write
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func reminderTitle(for task: ProjectBoardTask) -> String {
        String(format: String(localized: "Reminder for %@"), task.title)
    }

    static func reminderPlanID(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar,
        prefix: String
    ) -> String {
        let dayKey = reminderDayKey(referenceDate: referenceDate, calendar: calendar)
        let contentDigest = reminderContentDigest(for: task)
        return "\(prefix):\(dayKey):\(contentDigest):task:\(task.id)"
    }

    private static func reminderContentDigest(for task: ProjectBoardTask) -> String {
        let content = [
            String(task.id),
            String(task.projectID),
            task.title,
            trimmedOptional(task.dueAt) ?? ""
        ].joined(separator: "|")
        // The Queue identity must change when the reminder write changes, but
        // exposing task titles in IDs would leak user work into logs and URLs.
        let digest = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    private static func reminderDayKey(referenceDate: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: referenceDate)
    }

    static func todayReminderQueueReason(taskCount: Int) -> String {
        if taskCount == 1 {
            return String(localized: "Today assistant suggested a Reminders draft for 1 task.")
        }
        return String(format: String(localized: "Today assistant suggested Reminders drafts for %d tasks."), taskCount)
    }

    static func scheduleReminderQueueReason(taskCount: Int) -> String {
        if taskCount == 1 {
            return String(localized: "Schedule assistant suggested a Reminders draft for 1 task.")
        }
        return String(format: String(localized: "Schedule assistant suggested Reminders drafts for %d tasks."), taskCount)
    }

    static func sanitizedDoneFollowUpSourceTranscript(_ sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = ExecutionReceiptRedactor().redact(trimmed)
        let fallback = String(localized: "Done follow-up draft")
        guard !redacted.isEmpty else {
            return fallback
        }
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    static func sanitizedReminderSourceTranscript(_ sourceTranscript: String, fallback: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = DeveloperSecretRedactor().redact(trimmed).text
        guard !redacted.isEmpty else {
            return fallback
        }
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    static func sanitizedDailyPlanningSourceTranscript(_ sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = ExecutionReceiptRedactor().redact(trimmed)
        let fallback = String(localized: "Today daily planning review")
        guard !redacted.isEmpty else {
            return fallback
        }
        // Daily planning transcripts are durable Queue audit context, so keep
        // enough intent for review while avoiding secret/path retention.
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    func makeScheduleDraftCalendarApplyActionPlan(
        candidates: [ScheduleDraftApplyWriteCandidate],
        referenceDate: Date,
        calendar: Calendar
    ) -> ActionPlan {
        ActionPlan(
            id: Self.scheduleDraftCalendarApplyPlanID(
                candidates: candidates,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            userInput: "Queue reviewed Schedule draft for Calendar apply",
            summary: Self.scheduleDraftCalendarApplySummary(
                candidates: candidates,
                calendar: calendar
            ),
            actions: candidates.enumerated().compactMap { offset, candidate in
                guard let durationMinutes = Self.scheduleDraftDurationMinutes(for: candidate) else {
                    return nil
                }
                return PlanAction(
                    id: "calendar-work-block-\(offset + 1)-task-\(candidate.taskID)",
                    tool: .calendarCreateWorkBlock,
                    arguments: [
                        "title": .string(candidate.taskTitle),
                        "startAt": .string(candidate.startAt),
                        "durationMinutes": .number(Double(durationMinutes)),
                        "notes": .string(String(localized: "Created from a reviewed Suisui schedule draft.")),
                        "taskId": .number(Double(candidate.taskID)),
                        "projectId": .number(Double(candidate.projectID)),
                        "proposalID": .string(
                            CalendarProposalIdentity.make(taskID: candidate.taskID)
                        ),
                        "calendarIdentifier": .string(
                            CalendarProposalIdentity.defaultCalendarIdentifier
                        ),
                        "timeZoneIdentifier": .string(calendar.timeZone.identifier)
                    ],
                    riskLevel: .write
                )
            },
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func scheduleDraftCalendarApplyPlanID(
        candidates: [ScheduleDraftApplyWriteCandidate],
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let dayKey = scheduleDraftDayKey(referenceDate: referenceDate, calendar: calendar)
        let contentDigest = scheduleDraftContentDigest(candidates: candidates)
        let taskSegment = candidates.map { String($0.taskID) }.joined(separator: "-")
        let suffix = taskSegment.isEmpty ? "empty" : taskSegment
        return "schedule-draft-calendar-apply:\(dayKey):\(contentDigest):task:\(suffix)"
    }

    private static func scheduleDraftContentDigest(candidates: [ScheduleDraftApplyWriteCandidate]) -> String {
        let content = candidates.map { candidate in
            [
                String(candidate.taskID),
                String(candidate.projectID),
                candidate.taskTitle,
                candidate.startAt,
                candidate.endAt
            ].joined(separator: "|")
        }.joined(separator: "\n")
        // The Queue item ID must change when the reviewed Calendar write changes,
        // but it must not leak task titles. A short SHA-256 prefix keeps identity
        // stable for duplicate detection while preventing stale payload reuse.
        let digest = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    static func scheduleDraftDayKey(referenceDate: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: referenceDate)
    }

    private static func scheduleDraftCalendarApplySummary(
        candidates: [ScheduleDraftApplyWriteCandidate],
        calendar: Calendar
    ) -> String {
        let count = candidates.count
        let blockLabel = count == 1 ? "1 work block" : "\(count) work blocks"
        let times = candidates.map { "\($0.startAt)–\($0.endAt)" }.joined(separator: "; ")
        return "Schedule draft Calendar apply for \(blockLabel). Calendar: \(CalendarProposalIdentity.defaultCalendarIdentifier). Timezone: \(calendar.timeZone.identifier). Times: \(times)."
    }

    static func scheduleDraftQueueReason(candidateCount: Int) -> String {
        if candidateCount == 1 {
            return "Schedule draft suggested 1 Calendar work block."
        }
        return "Schedule draft suggested \(candidateCount) Calendar work blocks."
    }

    static func sanitizedScheduleDraftSourceTranscript(_ sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = DeveloperSecretRedactor().redact(trimmed).text
        let fallback = String(localized: "Schedule draft Calendar apply")
        guard !redacted.isEmpty else {
            return fallback
        }
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func scheduleDraftDurationMinutes(for candidate: ScheduleDraftApplyWriteCandidate) -> Int64? {
        guard let start = ISO8601DateFormatter().date(from: candidate.startAt),
              let end = ISO8601DateFormatter().date(from: candidate.endAt) else {
            return nil
        }
        let minutes = Int64(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else {
            return nil
        }
        // Calendar tool execution derives endAt from durationMinutes. Persisting a
        // duration instead of a second endAt keeps the queued approval surface
        // aligned with the executable tool contract.
        return minutes
    }
}
