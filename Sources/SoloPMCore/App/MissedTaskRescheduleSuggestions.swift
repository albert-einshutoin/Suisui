import Foundation

public struct MissedTaskRescheduleSuggestionResult: Equatable, Sendable {
    public var enqueuedItemIDs: [String]
    public var skippedTaskIDs: [Int64]
    public var errorMessage: String?

    public init(
        enqueuedItemIDs: [String] = [],
        skippedTaskIDs: [Int64] = [],
        errorMessage: String? = nil
    ) {
        self.enqueuedItemIDs = enqueuedItemIDs
        self.skippedTaskIDs = skippedTaskIDs
        self.errorMessage = errorMessage
    }
}

/// Turns missed-task review findings into one-tap reschedule suggestions:
/// each overdue/stale task in the immediate queue gets an Assistant Queue
/// item whose action plan moves the due date to tomorrow. The user approves
/// and runs it from the existing queue review surfaces — the assistant never
/// moves a deadline on its own.
public final class MissedTaskRescheduleSuggestionPlanner: @unchecked Sendable {
    public static let maxSuggestionsPerRun = 3
    public static let itemIDPrefix = "solopm-reschedule-"

    private let queueStore: any AssistantQueueStore
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        queueStore: any AssistantQueueStore,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.queueStore = queueStore
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func enqueueSuggestions(for summary: MissedTaskReviewSummary) -> MissedTaskRescheduleSuggestionResult {
        let candidates = summary.immediateQueue
            .filter { item in
                item.reasons.contains(.overdue) || item.reasons.contains(.stale)
            }
            .prefix(Self.maxSuggestionsPerRun)
        guard !candidates.isEmpty else {
            return MissedTaskRescheduleSuggestionResult()
        }

        let now = dateProvider.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current
        let day = MorningDigestScheduler.dayString(for: now, timeZone: calendar.timeZone)

        let pendingSuggestionTaskKeys: Set<String>
        do {
            // One open suggestion per task: skip tasks that already have a
            // reschedule item the user has not acted on yet, whatever day it
            // was proposed.
            let openStates: Set<AssistantQueueState> = [.waitingReview, .approved, .running, .blocked]
            pendingSuggestionTaskKeys = Set(
                try queueStore.list(filter: .states(openStates, limit: 500))
                    .compactMap { Self.taskKey(fromItemID: $0.id) }
            )
        } catch {
            return MissedTaskRescheduleSuggestionResult(
                errorMessage: UserFacingErrorMessageSanitizer.message(from: error)
            )
        }

        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
              let rescheduleDate = calendar.date(
                bySettingHour: QuickAddDueDateParser.defaultDayHour,
                minute: 0,
                second: 0,
                of: tomorrowStart
              ) else {
            return MissedTaskRescheduleSuggestionResult()
        }
        let rescheduledDueAt = DeadlineDateParser.string(from: rescheduleDate)

        var enqueued: [String] = []
        var skipped: [Int64] = []
        var errorMessage: String?

        for candidate in candidates {
            let taskID = candidate.task.id
            guard !pendingSuggestionTaskKeys.contains(String(taskID)) else {
                skipped.append(taskID)
                continue
            }

            let item = Self.makeSuggestionItem(
                taskID: taskID,
                taskTitle: candidate.task.title,
                reasons: candidate.reasons,
                day: day,
                rescheduledDueAt: rescheduledDueAt
            )
            do {
                _ = try queueStore.save(item)
                enqueued.append(item.id)
            } catch {
                errorMessage = UserFacingErrorMessageSanitizer.message(from: error)
            }
        }

        return MissedTaskRescheduleSuggestionResult(
            enqueuedItemIDs: enqueued,
            skippedTaskIDs: skipped,
            errorMessage: errorMessage
        )
    }

    static func makeSuggestionItem(
        taskID: Int64,
        taskTitle: String,
        reasons: [MissedTaskReviewReason],
        day: String,
        rescheduledDueAt: String
    ) -> AssistantQueueItem {
        let itemID = "\(itemIDPrefix)\(taskID)-\(day)"
        let redactedTitle = DeveloperSecretRedactor().redact(taskTitle).text
        let reasonLabel = reasons.contains(.overdue) ? "overdue" : "stalled"
        let plan = ActionPlan(
            id: itemID,
            userInput: "Missed task review follow-up",
            summary: "Reschedule \"\(redactedTitle)\" to tomorrow.",
            actions: [
                PlanAction(
                    id: "\(itemID)-task-update",
                    tool: .taskUpdate,
                    arguments: [
                        "id": .number(Double(taskID)),
                        "dueAt": .string(rescheduledDueAt)
                    ]
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )

        return AssistantQueueItem(
            id: itemID,
            state: .waitingReview,
            payload: .actionPlan(plan),
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: "\"\(redactedTitle)\" is \(reasonLabel); moving the due date to tomorrow keeps it visible.",
            reviewReason: "Assistant suggestion: reschedule a \(reasonLabel) task to tomorrow. Nothing changes until you approve and run it.",
            redactedSummary: "Reschedule 1 \(reasonLabel) task to tomorrow.",
            requiredCapabilities: [.tool(.taskUpdate)],
            costPreview: .localOnly(
                note: "Local reschedule suggestion. No SoloPM managed charge before run."
            )
        )
    }

    static func taskKey(fromItemID itemID: String) -> String? {
        guard itemID.hasPrefix(itemIDPrefix) else {
            return nil
        }
        let suffix = itemID.dropFirst(itemIDPrefix.count)
        guard let separator = suffix.lastIndex(of: "-"), separator > suffix.startIndex else {
            return nil
        }
        // The day suffix is yyyy-MM-dd; strip the last three dash components.
        let components = suffix.split(separator: "-")
        guard components.count >= 4 else {
            return nil
        }
        return components.dropLast(3).joined(separator: "-")
    }
}
