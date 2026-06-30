import Foundation

public enum DailyPlanningActionDraftKind: String, Codable, CaseIterable, Equatable, Sendable {
    case startRecommended
    case deferRecommendedToTomorrow
}

public struct DailyPlanningActionDraft: Equatable, Sendable {
    public var id: String
    public var kind: DailyPlanningActionDraftKind
    public var actionPlan: ActionPlan
    public var queueReason: String

    public init(
        id: String,
        kind: DailyPlanningActionDraftKind,
        actionPlan: ActionPlan,
        queueReason: String
    ) {
        self.id = id
        self.kind = kind
        self.actionPlan = actionPlan
        self.queueReason = queueReason
    }
}

public enum DailyPlanningActionDraftBuilder {
    public static func makeDraft(
        kind: DailyPlanningActionDraftKind,
        review: DailyPlanningReview,
        task: ProjectBoardTask?,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningActionDraft? {
        guard let recommendedTaskID = review.recommendedTaskID,
              let task,
              task.id == recommendedTaskID else {
            return nil
        }

        let redactor = DeveloperSecretRedactor()
        let dateKey = Self.dateKey(for: referenceDate, calendar: calendar)
        let draftID = "daily-planning:\(dateKey):\(kind.rawValue):task:\(task.id)"
        let taskTitle = Self.redactedTaskTitle(task.title, redactor: redactor)
        let summary: String
        let queueReason: String
        let action: PlanAction

        // Daily planning is allowed to recommend writes, but the recommendation
        // must stay reviewable so the Today cockpit never mutates tasks or
        // external calendars before the user approves the Queue item.
        switch kind {
        case .startRecommended:
            summary = "Start \(taskTitle) from Daily Planning Review."
            queueReason = "Daily Planning Review suggested starting \(taskTitle)."
            action = PlanAction(
                id: "\(draftID):start",
                tool: .taskUpdate,
                arguments: [
                    "id": .number(Double(task.id)),
                    "status": .string(ProjectTaskStatus.inProgress.rawValue)
                ],
                riskLevel: .write
            )
        case .deferRecommendedToTomorrow:
            let tomorrowKey = Self.dateKey(
                for: Self.tomorrow(from: referenceDate, calendar: calendar),
                calendar: calendar
            )
            summary = "Defer \(taskTitle) to \(tomorrowKey) from Daily Planning Review."
            queueReason = "Daily Planning Review suggested deferring \(taskTitle) to tomorrow."
            action = PlanAction(
                id: "\(draftID):defer",
                tool: .taskUpdate,
                arguments: [
                    "id": .number(Double(task.id)),
                    "dueAt": .string(tomorrowKey)
                ],
                riskLevel: .write
            )
        }

        return DailyPlanningActionDraft(
            id: draftID,
            kind: kind,
            actionPlan: ActionPlan(
                id: draftID,
                userInput: redactor.redact(review.sourceTranscript).text,
                summary: summary,
                actions: [action],
                riskLevel: .write,
                requiresApproval: true
            ),
            queueReason: queueReason
        )
    }

    private static func redactedTaskTitle(
        _ title: String,
        redactor: DeveloperSecretRedactor
    ) -> String {
        let redactedTitle = redactor.redact(title).text.trimmingCharacters(in: .whitespacesAndNewlines)
        return redactedTitle.isEmpty ? "recommended task" : redactedTitle
    }

    private static func tomorrow(from referenceDate: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? referenceDate
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
