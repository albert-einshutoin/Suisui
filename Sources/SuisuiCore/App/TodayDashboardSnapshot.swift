import Foundation

public struct TodayDashboardHeaderSnapshot: Equatable, Sendable {
    public let title: String
    public let greeting: String

    public init(title: String, greeting: String) {
        self.title = title
        self.greeting = greeting
    }
}

public struct TodayRecommendation: Equatable, Sendable {
    public let taskID: Int64?
    public let title: String
    public let reason: String

    public init(taskID: Int64?, title: String, reason: String) {
        self.taskID = taskID
        self.title = title
        self.reason = reason
    }
}

public struct TodayTaskRowSnapshot: Equatable, Sendable {
    public let taskID: Int64
    public let title: String
    public let projectTitle: String
    public let priorityLabel: String
    public let timeLabel: String?

    public init(taskID: Int64, title: String, projectTitle: String, priorityLabel: String, timeLabel: String?) {
        self.taskID = taskID
        self.title = title
        self.projectTitle = projectTitle
        self.priorityLabel = priorityLabel
        self.timeLabel = timeLabel
    }
}

public struct TodayWorkloadSnapshot: Equatable, Sendable {
    public let plannedTaskCount: Int
    public let dailyCapacityMinutes: Int

    public init(plannedTaskCount: Int, dailyCapacityMinutes: Int) {
        self.plannedTaskCount = plannedTaskCount
        self.dailyCapacityMinutes = dailyCapacityMinutes
    }
}

public struct TodayWeeklyScheduleSnapshot: Equatable, Sendable {
    public let scheduledTaskCount: Int
    public let unscheduledTaskCount: Int
    public let dayCount: Int

    public init(scheduledTaskCount: Int, unscheduledTaskCount: Int, dayCount: Int) {
        self.scheduledTaskCount = scheduledTaskCount
        self.unscheduledTaskCount = unscheduledTaskCount
        self.dayCount = dayCount
    }
}

public struct TodayReviewSnapshot: Equatable, Sendable {
    public let message: String
    public let isError: Bool

    public init(message: String, isError: Bool) {
        self.message = message
        self.isError = isError
    }
}

public struct TodayDashboardSnapshot: Equatable, Sendable {
    public let header: TodayDashboardHeaderSnapshot
    public let recommendation: TodayRecommendation
    public let tasks: [TodayTaskRowSnapshot]
    public let workload: TodayWorkloadSnapshot
    public let weeklySchedule: TodayWeeklyScheduleSnapshot
    public let review: TodayReviewSnapshot

    public init(
        header: TodayDashboardHeaderSnapshot,
        recommendation: TodayRecommendation,
        tasks: [TodayTaskRowSnapshot],
        workload: TodayWorkloadSnapshot,
        weeklySchedule: TodayWeeklyScheduleSnapshot,
        review: TodayReviewSnapshot
    ) {
        self.header = header
        self.recommendation = recommendation
        self.tasks = tasks
        self.workload = workload
        self.weeklySchedule = weeklySchedule
        self.review = review
    }
}

public enum TodayDashboardSnapshotBuilder {
    public static func make(
        today: TodayWorkflowSnapshot,
        schedule: ProjectBoardScheduleReadModel,
        projectTitlesByTaskID: [Int64: String],
        displayName: String,
        dailyCapacityMinutes: Int,
        now: Date,
        calendar: Calendar,
        locale: Locale = .autoupdatingCurrent
    ) -> TodayDashboardSnapshot {
        let tasks = today.plan.tasks.map { task in
            TodayTaskRowSnapshot(
                taskID: task.id,
                title: task.title,
                projectTitle: projectTitlesByTaskID[task.id] ?? "",
                priorityLabel: localized(task.priority.label, locale: locale),
                timeLabel: task.todayDueDisplayLabel(on: now, calendar: calendar, locale: locale)
            )
        }
        let review = today.dailyPlanningReviewPreview
        let scheduledTaskCount = Set(schedule.weeklyCockpit.days.flatMap(\.blocks).map(\.task.id)).count

        return TodayDashboardSnapshot(
            header: TodayDashboardHeaderSnapshot(
                title: dateTitle(for: now, calendar: calendar, locale: locale),
                greeting: greeting(displayName: displayName, now: now, calendar: calendar, locale: locale)
            ),
            recommendation: recommendation(for: today.plan, now: now, calendar: calendar, locale: locale),
            tasks: tasks,
            workload: TodayWorkloadSnapshot(
                plannedTaskCount: tasks.count,
                dailyCapacityMinutes: dailyCapacityMinutes > 0 ? dailyCapacityMinutes : 480
            ),
            weeklySchedule: TodayWeeklyScheduleSnapshot(
                scheduledTaskCount: scheduledTaskCount,
                unscheduledTaskCount: schedule.unscheduledTasks.count,
                dayCount: schedule.weeklyCockpit.days.count
            ),
            review: TodayReviewSnapshot(
                message: review.map { reviewTitle(for: $0, locale: locale) } ?? localized("No review items yet.", locale: locale),
                isError: false
            )
        )
    }

    private static func recommendation(for plan: TodayWorkflowPlan, now: Date, calendar: Calendar, locale: Locale) -> TodayRecommendation {
        // Keep fallback ordering stable only when the existing plan has no recommendation.
        let task = plan.recommendedTask
            ?? plan.tasks.first(where: { $0.status == .blocked })
            ?? plan.tasks.first(where: { $0.isOverdueForToday(on: now, calendar: calendar) })
            ?? plan.tasks.first(where: { $0.priority == .high })
            ?? plan.tasks.first

        guard let task else {
            return TodayRecommendation(taskID: nil, title: localized("No recommendation", locale: locale), reason: localized("Add a task to plan your day.", locale: locale))
        }
        if plan.recommendedTask != nil {
            return TodayRecommendation(taskID: task.id, title: task.title, reason: localizedPlanReason(plan.recommendationReason, locale: locale))
        }
        let reason: String
        if task.status == .blocked {
            reason = localized("Blocked work should be cleared first.", locale: locale)
        } else if task.isOverdueForToday(on: now, calendar: calendar) {
            reason = localized("Overdue work needs attention.", locale: locale)
        } else if task.priority == .high {
            reason = localized("High-priority work should be protected.", locale: locale)
        } else {
            reason = localized("Start with the first planned task.", locale: locale)
        }
        return TodayRecommendation(taskID: task.id, title: task.title, reason: reason)
    }

    private static func greeting(displayName: String, now: Date, calendar: Calendar, locale: Locale) -> String {
        let hour = calendar.component(.hour, from: now)
        let salutation = hour < 12 ? localized("Good morning", locale: locale) : hour < 18 ? localized("Good afternoon", locale: locale) : localized("Good evening", locale: locale)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? salutation : String(format: localized("%@, %@", locale: locale), salutation, name)
    }

    private static func dateTitle(for date: Date, calendar: Calendar, locale: Locale) -> String {
        SuisuiTimestampDisplay.formatted(
            date,
            template: "EEEEMMMd",
            calendar: calendar,
            locale: locale
        )
    }

    private static func localized(_ key: String, locale: Locale) -> String {
        let language = locale.identifier.hasPrefix("ja") ? "ja" : "en"
        let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
            .flatMap(Bundle.init(url:)) ?? .module
        return String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale)
    }

    private static func localizedPlanReason(_ reason: String, locale: Locale) -> String {
        switch reason {
        case "No open tasks due today.",
             "No due work is scheduled for today.",
             "Overdue high-priority work should be cleared first.",
             "Overdue work should be cleared before new tasks.",
             "High-priority work is the best first task.",
             "Earliest due task keeps today on track.":
            localized(reason, locale: locale)
        default:
            reason
        }
    }

    private static func reviewTitle(for review: DailyPlanningReview, locale: Locale) -> String {
        let phase = switch review.phase {
        case .morning: localized("Morning", locale: locale)
        case .midday: localized("Midday", locale: locale)
        case .evening: localized("Evening", locale: locale)
        }
        if let minutes = review.requestedMinutes {
            return String(format: localized("%@ focus review: %d tasks for %d minutes", locale: locale), phase, review.focusItems.count, minutes)
        }
        return String(format: localized("%@ daily planning review", locale: locale), phase)
    }

}
