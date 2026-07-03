import Foundation

public enum DailyPlanningActionDraftKind: String, Codable, CaseIterable, Equatable, Sendable {
    case startRecommended
    case deferRecommendedToTomorrow
    case moveRecommendedDueDateToToday
    case splitRecommendedTask
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

        let redactor = ExecutionReceiptRedactor()
        let dateKey = Self.dateKey(for: referenceDate, calendar: calendar)
        let draftID = "daily-planning:\(dateKey):\(kind.rawValue):task:\(task.id)"
        let taskTitle = Self.redactedTaskTitle(task.title, redactor: redactor)
        let sourceTranscript = Self.redactedSourceTranscript(review.sourceTranscript, redactor: redactor)
        let summary: String
        let queueReason: String
        let actions: [PlanAction]

        // Daily planning is allowed to recommend writes, but the recommendation
        // must stay reviewable so the Today cockpit never mutates tasks or
        // external calendars before the user approves the Queue item.
        switch kind {
        case .startRecommended:
            summary = "Start \(taskTitle) from Daily Planning Review."
            queueReason = "Daily Planning Review suggested starting \(taskTitle)."
            actions = [PlanAction(
                id: "\(draftID):start",
                tool: .taskUpdate,
                arguments: [
                    "id": .number(Double(task.id)),
                    "status": .string(ProjectTaskStatus.inProgress.rawValue)
                ],
                riskLevel: .write
            )]
        case .deferRecommendedToTomorrow:
            let tomorrowKey = Self.dateKey(
                for: Self.tomorrow(from: referenceDate, calendar: calendar),
                calendar: calendar
            )
            summary = "Defer \(taskTitle) to \(tomorrowKey) from Daily Planning Review."
            queueReason = "Daily Planning Review suggested deferring \(taskTitle) to tomorrow."
            actions = [PlanAction(
                id: "\(draftID):defer",
                tool: .taskUpdate,
                arguments: [
                    "id": .number(Double(task.id)),
                    "dueAt": .string(tomorrowKey)
                ],
                riskLevel: .write
            )]
        case .moveRecommendedDueDateToToday:
            summary = "Move \(taskTitle) due date to \(dateKey) from Daily Planning Review."
            queueReason = "Daily Planning Review suggested moving \(taskTitle) due date to today."
            actions = [PlanAction(
                id: "\(draftID):move-today",
                tool: .taskUpdate,
                arguments: [
                    "id": .number(Double(task.id)),
                    "dueAt": .string(dateKey)
                ],
                riskLevel: .write
            )]
        case .splitRecommendedTask:
            summary = "Split \(taskTitle) into reviewable follow-up tasks from Daily Planning Review."
            queueReason = "Daily Planning Review suggested splitting \(taskTitle) into reviewable follow-up tasks."
            actions = Self.splitTaskCreateActions(
                draftID: draftID,
                task: task,
                taskTitle: taskTitle
            )
        }

        return DailyPlanningActionDraft(
            id: draftID,
            kind: kind,
            actionPlan: ActionPlan(
                id: draftID,
                userInput: sourceTranscript,
                summary: summary,
                actions: actions,
                riskLevel: .write,
                requiresApproval: true
            ),
            queueReason: queueReason
        )
    }

    private static func redactedTaskTitle(
        _ title: String,
        redactor: ExecutionReceiptRedactor
    ) -> String {
        let redactedTitle = redactor.redact(title).trimmingCharacters(in: .whitespacesAndNewlines)
        return redactedTitle.isEmpty ? "recommended task" : redactedTitle
    }

    private static func redactedSourceTranscript(
        _ sourceTranscript: String,
        redactor: ExecutionReceiptRedactor
    ) -> String {
        // ActionPlan is persisted inside Assistant Queue payload JSON, so the
        // same durable-audit redaction must run before the plan is built.
        return redactor.redact(sourceTranscript)
    }

    private static func splitTaskCreateActions(
        draftID: String,
        task: ProjectBoardTask,
        taskTitle: String
    ) -> [PlanAction] {
        [
            splitTaskCreateAction(
                id: "\(draftID):split-1",
                title: "\(taskTitle) - Define next slice",
                task: task
            ),
            splitTaskCreateAction(
                id: "\(draftID):split-2",
                title: "\(taskTitle) - Complete remaining work",
                task: task
            )
        ]
    }

    private static func splitTaskCreateAction(
        id: String,
        title: String,
        task: ProjectBoardTask
    ) -> PlanAction {
        var arguments: [String: JSONValue] = [
            "title": .string(title),
            "projectId": .number(Double(task.projectID)),
            "priority": .string(task.priority.rawValue),
            "sourceCommand": .string("Daily Planning Review split from task \(task.id)"),
            "detail": .string("Reviewable follow-up task generated from Daily Planning Review. Original task ID: \(task.id).")
        ]
        if let dueAt = task.dueAt?.trimmingCharacters(in: .whitespacesAndNewlines), dueAt.isEmpty == false {
            arguments["dueAt"] = .string(dueAt)
        }
        return PlanAction(
            id: id,
            tool: .taskCreate,
            arguments: arguments,
            riskLevel: .write
        )
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
