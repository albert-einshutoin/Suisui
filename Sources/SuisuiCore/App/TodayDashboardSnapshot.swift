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
                priorityLabel: task.priority.label,
                timeLabel: task.todayDueDisplayLabel(on: now, calendar: calendar, locale: locale)
            )
        }
        let review = today.dailyPlanningReviewPreview
        let scheduledTaskCount = Set(schedule.weeklyCockpit.days.flatMap(\.blocks).map(\.task.id)).count

        return TodayDashboardSnapshot(
            header: TodayDashboardHeaderSnapshot(
                title: dateTitle(for: now, calendar: calendar, locale: locale),
                greeting: greeting(displayName: displayName, now: now, calendar: calendar)
            ),
            recommendation: recommendation(for: today.plan, now: now, calendar: calendar),
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
                message: review?.headline ?? String(localized: "No review items yet."),
                isError: false
            )
        )
    }

    private static func recommendation(for plan: TodayWorkflowPlan, now: Date, calendar: Calendar) -> TodayRecommendation {
        // Keep fallback ordering stable only when the existing plan has no recommendation.
        let task = plan.recommendedTask
            ?? plan.tasks.first(where: { $0.status == .blocked })
            ?? plan.tasks.first(where: { $0.isOverdueForToday(on: now, calendar: calendar) })
            ?? plan.tasks.first(where: { $0.priority == .high })
            ?? plan.tasks.first

        guard let task else {
            return TodayRecommendation(taskID: nil, title: String(localized: "No recommendation"), reason: String(localized: "Add a task to plan your day."))
        }
        if plan.recommendedTask != nil {
            return TodayRecommendation(taskID: task.id, title: task.title, reason: plan.recommendationReason)
        }
        let reason: String
        if task.status == .blocked {
            reason = String(localized: "Blocked work should be cleared first.")
        } else if task.isOverdueForToday(on: now, calendar: calendar) {
            reason = String(localized: "Overdue work needs attention.")
        } else if task.priority == .high {
            reason = String(localized: "High-priority work should be protected.")
        } else {
            reason = String(localized: "Start with the first planned task.")
        }
        return TodayRecommendation(taskID: task.id, title: task.title, reason: reason)
    }

    private static func greeting(displayName: String, now: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: now)
        let salutation = hour < 12 ? String(localized: "Good morning") : hour < 18 ? String(localized: "Good afternoon") : String(localized: "Good evening")
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? salutation : String(format: String(localized: "%@, %@"), salutation, name)
    }

    private static func dateTitle(for date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

}
