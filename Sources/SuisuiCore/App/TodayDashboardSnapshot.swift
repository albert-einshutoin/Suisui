import Foundation

public struct TodayDashboardHeaderSnapshot: Equatable, Sendable {
    public let title: String
    public let greeting: String
    public let taskCount: Int
    public let scheduledTaskCount: Int

    public init(title: String, greeting: String, taskCount: Int = 0, scheduledTaskCount: Int = 0) {
        self.title = title
        self.greeting = greeting
        self.taskCount = taskCount
        self.scheduledTaskCount = scheduledTaskCount
    }
}

public struct TodayRecommendation: Equatable, Sendable {
    public let taskID: Int64?
    public let title: String
    public let reason: String
    public let action: TodayRecommendationAction

    /// Stable identity for SwiftUI collections, including task-less actions
    /// such as Add Task and Catch Up.
    public var id: String {
        if let taskID {
            return "task-\(taskID)-\(action.rawValue)"
        }
        return "action-\(action.rawValue)-\(title)"
    }

    public init(
        taskID: Int64?,
        title: String,
        reason: String,
        action: TodayRecommendationAction = .selectTask
    ) {
        self.taskID = taskID
        self.title = title
        self.reason = reason
        self.action = action
    }
}

public enum TodayRecommendationAction: String, Equatable, Sendable {
    case startFocus
    case selectTask
    case openReview
    case prepareScheduleDraft
    case addTask
    case openCatchUp
    case suggestBreak
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

public struct TodayWeeklyScheduleSnapshot: Equatable, Sendable {
    public let scheduledTaskCount: Int
    public let unscheduledTaskCount: Int
    public let dayCount: Int
    public let rows: [TodayWeeklyScheduleRow]

    public init(
        scheduledTaskCount: Int,
        unscheduledTaskCount: Int,
        dayCount: Int,
        rows: [TodayWeeklyScheduleRow] = []
    ) {
        self.scheduledTaskCount = scheduledTaskCount
        self.unscheduledTaskCount = unscheduledTaskCount
        self.dayCount = dayCount
        self.rows = rows
    }
}

/// A presentation-ready scheduled block. Keep source dates and duration
/// numeric so UI can use its locale-aware duration formatter without parsing.
public struct TodayWeeklyScheduleRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let taskID: Int64
    public let title: String
    public let dateLabel: String
    public let timeLabel: String
    public let durationMinutes: Int?

    public init(
        id: String,
        taskID: Int64,
        title: String,
        dateLabel: String,
        timeLabel: String,
        durationMinutes: Int?
    ) {
        self.id = id
        self.taskID = taskID
        self.title = title
        self.dateLabel = dateLabel
        self.timeLabel = timeLabel
        self.durationMinutes = durationMinutes
    }
}

public enum TodayReviewItemKind: Equatable, Sendable {
    case dailyPlanning
    case catchUp
}

public struct TodayReviewItemSnapshot: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: TodayReviewItemKind
    public let title: String
    public let detail: String

    public init(id: String, kind: TodayReviewItemKind, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct TodayReviewSnapshot: Equatable, Sendable {
    public let message: String
    public let isError: Bool
    public let items: [TodayReviewItemSnapshot]

    public init(message: String, isError: Bool, items: [TodayReviewItemSnapshot] = []) {
        self.message = message
        self.isError = isError
        self.items = items
    }
}

public struct TodayDashboardSnapshot: Equatable, Sendable {
    public let header: TodayDashboardHeaderSnapshot
    public let weather: TodayWeatherSnapshot
    public let integrations: TodayIntegrationsSnapshot
    public let externalActivity: TodayExternalActivityModel
    public let recommendations: [TodayRecommendation]
    public let tasks: [TodayTaskRowSnapshot]
    public let workload: TodayWorkloadSnapshot
    public let weeklySchedule: TodayWeeklyScheduleSnapshot
    public let review: TodayReviewSnapshot

    public init(
        header: TodayDashboardHeaderSnapshot,
        weather: TodayWeatherSnapshot,
        integrations: TodayIntegrationsSnapshot,
        externalActivity: TodayExternalActivityModel = .empty,
        recommendations: [TodayRecommendation],
        tasks: [TodayTaskRowSnapshot],
        workload: TodayWorkloadSnapshot,
        weeklySchedule: TodayWeeklyScheduleSnapshot,
        review: TodayReviewSnapshot
    ) {
        self.header = header
        self.weather = weather
        self.integrations = integrations
        self.externalActivity = externalActivity
        self.recommendations = recommendations
        self.tasks = tasks
        self.workload = workload
        self.weeklySchedule = weeklySchedule
        self.review = review
    }

    public var recommendation: TodayRecommendation? {
        recommendations.first
    }

    public init(
        header: TodayDashboardHeaderSnapshot,
        recommendation: TodayRecommendation,
        tasks: [TodayTaskRowSnapshot],
        workload: TodayWorkloadSnapshot,
        weeklySchedule: TodayWeeklyScheduleSnapshot,
        review: TodayReviewSnapshot,
        weather: TodayWeatherSnapshot = TodayWeatherSnapshot(
            state: .notConfigured,
            title: "Weather unavailable",
            detail: "Weather is unavailable right now.",
            accessibilityLabel: "Weather: Weather unavailable. Weather is unavailable right now."
        )
    ) {
        self.init(
            header: header,
            weather: weather,
            integrations: .notConfigured,
            externalActivity: TodayExternalActivityModelBuilder.make(integrations: .notConfigured),
            recommendations: recommendation.taskID == nil ? [] : [recommendation],
            tasks: tasks,
            workload: workload,
            weeklySchedule: weeklySchedule,
            review: review
        )
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
        locale: Locale = .autoupdatingCurrent,
        weatherState: TodayWeatherState = .notConfigured,
        integrationsState: TodayIntegrationStates = .notConfigured,
        catchUpCount: Int = 0
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
        let weeklyScheduledTaskCount = Set(schedule.weeklyCockpit.days.flatMap(\.blocks).map(\.task.id)).count
        let todayScheduledTaskCount = Set(
            schedule.weeklyCockpit.days
                .filter { calendar.isDate($0.date, inSameDayAs: now) }
                .flatMap(\.blocks)
                .map(\.task.id)
        ).count
        let weeklyScheduleRows = weeklyScheduleRows(
            from: schedule.weeklyCockpit,
            calendar: calendar,
            locale: locale
        )
        let primaryRecommendation = recommendation(for: today.plan, now: now, calendar: calendar, locale: locale)
        let recommendations = recommendations(
            primary: primaryRecommendation,
            chips: today.recommendationChips,
            review: today.dailyPlanningReviewPreview,
            unscheduledTasks: schedule.unscheduledTasks,
            tasks: tasks,
            now: now,
            calendar: calendar,
            locale: locale,
            catchUpCount: catchUpCount
        )
        let integrations = TodayIntegrationSnapshotBuilder.make(
            states: integrationsState,
            now: now,
            calendar: calendar,
            locale: locale
        )

        return TodayDashboardSnapshot(
            header: TodayDashboardHeaderSnapshot(
                title: dateTitle(for: now, calendar: calendar, locale: locale),
                greeting: greeting(displayName: displayName, now: now, calendar: calendar, locale: locale),
                taskCount: tasks.count,
                scheduledTaskCount: todayScheduledTaskCount
            ),
            weather: TodayWeatherSnapshotBuilder.make(
                state: weatherState,
                now: now,
                calendar: calendar,
                locale: locale
            ),
            integrations: integrations,
            externalActivity: TodayExternalActivityModelBuilder.make(integrations: integrations),
            recommendations: recommendations,
            tasks: tasks,
            workload: TodayWorkloadSnapshotBuilder.make(
                timeBlocks: today.plan.timeBlocks,
                focusTaskID: primaryRecommendation.taskID,
                capacityMinutes: dailyCapacityMinutes == 0 ? AppSettings.default.dailyWorkCapacityMinutes : dailyCapacityMinutes,
                plannedTaskCount: tasks.count
            ),
            weeklySchedule: TodayWeeklyScheduleSnapshot(
                scheduledTaskCount: weeklyScheduledTaskCount,
                unscheduledTaskCount: schedule.unscheduledTasks.count,
                dayCount: schedule.weeklyCockpit.days.count,
                rows: weeklyScheduleRows
            ),
            review: TodayReviewSnapshot(
                message: review.map { reviewTitle(for: $0, locale: locale) } ?? localized("No review items yet.", locale: locale),
                isError: false,
                items: reviewItems(review: review, catchUpCount: catchUpCount, locale: locale)
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
            return TodayRecommendation(taskID: nil, title: localized("Add a task", locale: locale), reason: localized("Add a task to plan your day.", locale: locale), action: .addTask)
        }
        if plan.recommendedTask != nil {
            return TodayRecommendation(taskID: task.id, title: task.title, reason: localizedPlanReason(plan.recommendationReason, locale: locale), action: .startFocus)
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
        return TodayRecommendation(taskID: task.id, title: task.title, reason: reason, action: .startFocus)
    }

    private static func weeklyScheduleRows(
        from cockpit: WeeklyScheduleCockpit,
        calendar: Calendar,
        locale: Locale
    ) -> [TodayWeeklyScheduleRow] {
        cockpit.days.flatMap { day in
            day.blocks.map { block in
                TodayWeeklyScheduleRow(
                    id: block.id,
                    taskID: block.task.id,
                    title: block.task.title,
                    dateLabel: SuisuiTimestampDisplay.formatted(
                        day.date,
                        template: "EEEMMMd",
                        calendar: calendar,
                        locale: locale
                    ),
                    timeLabel: block.timeLabel,
                    durationMinutes: durationMinutes(startAt: block.startAt, endAt: block.endAt)
                )
            }
        }
    }

    private static func durationMinutes(startAt: Date?, endAt: Date?) -> Int? {
        guard let startAt, let endAt else { return nil }
        let seconds = endAt.timeIntervalSince(startAt)
        guard seconds > 0 else { return nil }
        return Int(seconds / 60)
    }

    private static func recommendations(
        primary: TodayRecommendation,
        chips: [TodayRecommendationChip],
        review: DailyPlanningReview?,
        unscheduledTasks: [ProjectBoardTask],
        tasks: [TodayTaskRowSnapshot],
        now: Date,
        calendar: Calendar,
        locale: Locale,
        catchUpCount: Int
    ) -> [TodayRecommendation] {
        var recommendations: [TodayRecommendation] = []
        var usedTaskIDs = Set<Int64>()

        func append(_ recommendation: TodayRecommendation) {
            guard recommendations.count < 3 else { return }
            if let taskID = recommendation.taskID {
                guard usedTaskIDs.insert(taskID).inserted else { return }
            } else {
                guard recommendation.action == .addTask
                    || recommendation.action == .openCatchUp
                    || recommendation.action == .suggestBreak,
                    !recommendations.contains(where: { $0.action == recommendation.action }) else {
                    return
                }
            }
            recommendations.append(recommendation)
        }

        // An empty plan's synthetic Add Task action should not displace a
        // real unscheduled or review candidate. Append it after actionable
        // task recommendations have had a chance to fill the three slots.
        let deferredEmptyPlanAction = primary.taskID == nil && primary.action == .addTask
        if !deferredEmptyPlanAction {
            append(primary)
        }
        for chip in chips {
            let localizedChip = localizedRecommendationChip(chip, locale: locale)
            append(TodayRecommendation(taskID: chip.taskID, title: localizedChip.title, reason: localizedChip.reason, action: .selectTask))
        }
        for item in review?.focusItems ?? [] {
            append(TodayRecommendation(taskID: item.taskID, title: item.title, reason: localizedPlanReason(item.reason, locale: locale), action: .openReview))
        }
        let unscheduledCandidates = unscheduledTasks
            .filter { isUnscheduledRecommendationCandidate($0, now: now, calendar: calendar) }
            .sorted(by: isHigherPriority)
        for task in unscheduledCandidates {
            append(TodayRecommendation(
                taskID: task.id,
                title: task.title,
                reason: localized("Needs scheduling", locale: locale),
                action: .prepareScheduleDraft
            ))
        }
        for task in tasks {
            append(
                TodayRecommendation(
                    taskID: task.taskID,
                    title: task.title,
                    reason: task.timeLabel ?? (task.projectTitle.isEmpty
                        ? localized("Start with the first planned task.", locale: locale)
                        : task.projectTitle),
                    action: .selectTask
                )
            )
        }

        if catchUpCount > 0 {
            append(TodayRecommendation(
                taskID: nil,
                title: localized("Catch up", locale: locale),
                reason: localizedCount(catchUpCount, one: "%d task needs follow-up", other: "%d tasks need follow-up", locale: locale),
                action: .openCatchUp
            ))
        }
        if deferredEmptyPlanAction {
            append(primary)
        } else if tasks.count < 2 || recommendations.isEmpty {
            append(TodayRecommendation(
                taskID: nil,
                title: localized("Add a task", locale: locale),
                reason: localized("Add a task to plan your day.", locale: locale),
                action: .addTask
            ))
        }
        if !tasks.isEmpty {
            append(TodayRecommendation(
                taskID: nil,
                title: localized("Take a break", locale: locale),
                reason: localized("Protect a short break before the next task.", locale: locale),
                action: .suggestBreak
            ))
        }
        return recommendations
    }

    private static func localizedRecommendationChip(
        _ chip: TodayRecommendationChip,
        locale: Locale
    ) -> (title: String, reason: String) {
        switch chip.kind {
        case .blocker:
            return (
                localized("Resolve blocker", locale: locale),
                String(format: localized("%@ is blocking today's plan.", locale: locale), chip.taskTitle)
            )
        case .overdue:
            return (
                localized("Clear overdue", locale: locale),
                String(format: localized("%@ is overdue.", locale: locale), chip.taskTitle)
            )
        case .highPriority:
            return (
                localized("High priority", locale: locale),
                String(format: localized("%@ is high priority.", locale: locale), chip.taskTitle)
            )
        }
    }

    private static func localizedCount(_ count: Int, one: String, other: String, locale: Locale) -> String {
        String(format: localized(count == 1 ? one : other, locale: locale), count)
    }

    private static func isHigherPriority(_ lhs: ProjectBoardTask, _ rhs: ProjectBoardTask) -> Bool {
        let lhsRank = priorityRank(lhs.priority)
        let rhsRank = priorityRank(rhs.priority)
        return lhsRank == rhsRank ? lhs.id < rhs.id : lhsRank < rhsRank
    }

    private static func isUnscheduledRecommendationCandidate(
        _ task: ProjectBoardTask,
        now: Date,
        calendar: Calendar
    ) -> Bool {
        task.priority == .high
            || task.status == .blocked
            || task.isOverdueForToday(on: now, calendar: calendar)
    }

    private static func priorityRank(_ priority: ProjectTaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
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
             "Earliest due task keeps today on track.",
             "Blocked work should be unblocked before adding new scope.",
             "High-priority work protects today's plan.",
             "Keeps today's due work moving.":
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

    private static func reviewItems(
        review: DailyPlanningReview?,
        catchUpCount: Int,
        locale: Locale
    ) -> [TodayReviewItemSnapshot] {
        // The reference card is intentionally a two-row summary. Reserve one
        // row for overdue follow-up when it exists, then keep the complete
        // review workflow available through the Review destination.
        let planningLimit = catchUpCount > 0 ? 1 : 2
        var items = (review?.focusItems ?? []).prefix(planningLimit).map { item in
            TodayReviewItemSnapshot(
                id: "daily-planning-\(item.taskID)",
                kind: .dailyPlanning,
                title: item.title,
                detail: item.reason
            )
        }
        if catchUpCount > 0 {
            items.append(
                TodayReviewItemSnapshot(
                    id: "catch-up",
                    kind: .catchUp,
                    title: localized("Catch up", locale: locale),
                    detail: localizedCount(
                        catchUpCount,
                        one: "%d task needs follow-up",
                        other: "%d tasks need follow-up",
                        locale: locale
                    )
                )
            )
        }
        return items
    }

}
