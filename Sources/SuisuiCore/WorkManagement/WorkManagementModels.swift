import Foundation

public enum ProjectTaskStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case backlog
    case planned
    case inProgress = "in_progress"
    case blocked
    case done = "completed"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .backlog:
            "Backlog"
        case .planned:
            "Planned"
        case .inProgress:
            "In Progress"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        }
    }

    public static func normalized(_ rawStatus: String) -> ProjectTaskStatus {
        switch rawStatus.lowercased().replacingOccurrences(of: " ", with: "_") {
        case "planned", "next":
            .planned
        case "in_progress", "doing", "active":
            .inProgress
        case "blocked":
            .blocked
        case "completed", "done", "closed":
            .done
        default:
            .backlog
        }
    }
}

public enum ProjectTaskPriority: String, Codable, CaseIterable, Identifiable, Sendable {
    case low
    case medium
    case high

    public var id: String { rawValue }

    public var label: String {
        rawValue.capitalized
    }

    public static func normalized(_ rawPriority: String?, column: String) throws -> ProjectTaskPriority {
        guard let rawPriority else {
            return .medium
        }

        let normalized = rawPriority.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let priority = ProjectTaskPriority(rawValue: normalized) else {
            throw LocalStoreDecodingError.invalidEnum(column: column, value: rawPriority)
        }
        return priority
    }
}

public struct ProjectBoardSnapshot: Equatable, Sendable {
    public var projects: [ProjectBoardProject]

    public init(projects: [ProjectBoardProject]) {
        self.projects = projects
    }

    public static let empty = ProjectBoardSnapshot(projects: [])
}

public struct ProjectBoardProject: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var status: String
    public var subtitle: String
    public var hasWorkspaceDirectory: Bool
    public var hasWorkspaceBookmark: Bool
    public var workspacePath: String?
    public var workspaceDisplayName: String?
    public var columns: [ProjectBoardColumn]
    public var artifacts: [ProjectBoardArtifact]
    public var milestones: [ProjectBoardMilestone]

    public init(
        id: Int64,
        title: String,
        status: String = "active",
        subtitle: String,
        hasWorkspaceDirectory: Bool = false,
        hasWorkspaceBookmark: Bool = false,
        workspacePath: String? = nil,
        workspaceDisplayName: String? = nil,
        columns: [ProjectBoardColumn],
        artifacts: [ProjectBoardArtifact] = [],
        milestones: [ProjectBoardMilestone] = []
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.subtitle = subtitle
        self.hasWorkspaceDirectory = hasWorkspaceDirectory
        self.hasWorkspaceBookmark = hasWorkspaceBookmark
        self.workspacePath = workspacePath
        self.workspaceDisplayName = workspaceDisplayName
        self.columns = columns
        self.artifacts = artifacts
        self.milestones = milestones
    }

    public var taskCount: Int {
        columns.reduce(0) { $0 + $1.tasks.count }
    }

    public var tasks: [ProjectBoardTask] {
        columns.flatMap(\.tasks)
    }

    public var isCompleted: Bool {
        status == "completed"
    }

    public var isArchived: Bool {
        status == "archived"
    }

    public var milestoneSummary: String {
        let completedCount = milestones.filter(\.isCompleted).count
        return "\(completedCount)/\(milestones.count) milestones complete"
    }
}

public struct ProjectBoardArtifact: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64?
    public var taskID: Int64?
    public var expectedPath: String
    public var createdState: ArtifactCreatedState
    public var lastModifiedAt: Date?

    public init(
        id: Int64,
        projectID: Int64?,
        taskID: Int64?,
        expectedPath: String,
        createdState: ArtifactCreatedState,
        lastModifiedAt: Date?
    ) {
        self.id = id
        self.projectID = projectID
        self.taskID = taskID
        self.expectedPath = expectedPath
        self.createdState = createdState
        self.lastModifiedAt = lastModifiedAt
    }
}

public struct ProjectBoardMilestone: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64
    public var title: String
    public var dueAt: String?
    public var isCompleted: Bool

    public init(id: Int64, projectID: Int64, title: String, dueAt: String?, isCompleted: Bool) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.dueAt = dueAt
        self.isCompleted = isCompleted
    }
}

public struct ProjectBoardColumn: Identifiable, Equatable, Sendable {
    public var id: String { status.id }
    public var status: ProjectTaskStatus
    public var title: String
    public var tasks: [ProjectBoardTask]

    public init(status: ProjectTaskStatus, tasks: [ProjectBoardTask]) {
        self.status = status
        self.title = status.title
        self.tasks = tasks
    }
}

public struct ProjectBoardTask: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?
    public var completedAt: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var recurrence: String?

    public init(
        id: Int64,
        projectID: Int64,
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?,
        completedAt: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        recurrence: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recurrence = recurrence
    }

    /// The label every board surface shows for a due date. `dueAt` stays the
    /// raw stored string for persistence and API compatibility; this is the
    /// only thing a person should ever see, so the kanban card cannot print
    /// `2026-07-10` while Today prints `Overdue Jul 10` for the same task.
    public var dueLabel: String? {
        dueAt.map { SuisuiTimestampDisplay.dayLabel($0) }
    }

    // Today surfaces optimize for quick scanning; keep the stored dueAt raw for
    // persistence/API compatibility and derive the friendlier label at the edge.
    public func todayDueDisplayLabel(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let dueAt else {
            return nil
        }
        guard let parsedDue = SuisuiTimestampDisplay.parse(dueAt, calendar: calendar) else {
            return dueAt
        }

        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let dateText = SuisuiTimestampDisplay.formatted(
            parsedDue.date,
            template: parsedDue.includesTime ? "MMM d HH:mm" : "MMM d",
            calendar: calendar,
            locale: locale
        )

        if isOverdueForToday(on: referenceDate, calendar: calendar) {
            return String(format: localizedTodayLabel("Overdue %@", locale: locale), dateText)
        }
        if let dayInterval,
           parsedDue.date >= dayInterval.start,
           parsedDue.date < dayInterval.end {
            guard parsedDue.includesTime else {
                return localizedTodayLabel("Today", locale: locale)
            }
            return String(
                format: localizedTodayLabel("Today %@", locale: locale),
                SuisuiTimestampDisplay.time(parsedDue.date, calendar: calendar, locale: locale)
            )
        }
        return String(format: localizedTodayLabel("Due %@", locale: locale), dateText)
    }

    public func isOverdueForToday(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let dueAt,
              let parsedDue = SuisuiTimestampDisplay.parse(dueAt, calendar: calendar),
              let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start else {
            return false
        }
        return parsedDue.date < dayStart && status != .done
    }
}

private func localizedTodayLabel(_ key: String, locale: Locale) -> String {
    let language = locale.identifier.hasPrefix("ja") ? "ja" : "en"
    let bundle = Bundle.module.url(forResource: language, withExtension: "lproj")
        .flatMap(Bundle.init(url:)) ?? .module
    return String(localized: String.LocalizationValue(key), bundle: bundle, locale: locale)
}

public struct ProjectBoardTaskDraft: Equatable, Sendable {
    public var projectID: Int64
    public var title: String
    public var detail: String
    public var status: ProjectTaskStatus
    public var priority: ProjectTaskPriority
    public var dueAt: String?
    public var recurrence: String?

    public init(
        projectID: Int64,
        title: String,
        detail: String = "",
        status: ProjectTaskStatus = .backlog,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil,
        recurrence: String? = nil
    ) {
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.status = status
        self.priority = priority
        self.dueAt = dueAt
        self.recurrence = recurrence
    }
}

public struct TodayTimeBlock: Identifiable, Equatable, Sendable {
    public var id: String { "\(task.id)-\(label)" }
    public var label: String
    public var task: ProjectBoardTask
    public var startAt: String?
    public var endAt: String?

    public init(label: String, task: ProjectBoardTask, startAt: String? = nil, endAt: String? = nil) {
        self.label = label
        self.task = task
        self.startAt = startAt
        self.endAt = endAt
    }
}

public struct TodayWorkflowPlan: Equatable, Sendable {
    public var tasks: [ProjectBoardTask]
    public var overdueCount: Int
    public var dueTodayCount: Int
    public var recommendedTask: ProjectBoardTask?
    public var recommendationReason: String
    public var timeBlocks: [TodayTimeBlock]

    public init(
        tasks: [ProjectBoardTask],
        overdueCount: Int,
        dueTodayCount: Int,
        recommendedTask: ProjectBoardTask?,
        recommendationReason: String,
        timeBlocks: [TodayTimeBlock]
    ) {
        self.tasks = tasks
        self.overdueCount = overdueCount
        self.dueTodayCount = dueTodayCount
        self.recommendedTask = recommendedTask
        self.recommendationReason = recommendationReason
        self.timeBlocks = timeBlocks
    }
}

public enum TodayAssistantRailSource: String, Codable, Equatable, Sendable {
    case focused
    case selected
    case recommended
    case empty
}

public struct TodayAssistantRailContext: Equatable, Sendable {
    public var source: TodayAssistantRailSource
    public var task: ProjectBoardTask?
    public var projectTitle: String
    public var nextActionTitle: String
    public var nextActionReason: String
    public var nextBlockLabel: String?
    public var notes: String
    public var subtaskSummary: String
    public var reminderSummary: String

    public init(
        source: TodayAssistantRailSource,
        task: ProjectBoardTask?,
        projectTitle: String,
        nextActionTitle: String,
        nextActionReason: String,
        nextBlockLabel: String?,
        notes: String,
        subtaskSummary: String,
        reminderSummary: String
    ) {
        self.source = source
        self.task = task
        self.projectTitle = projectTitle
        self.nextActionTitle = nextActionTitle
        self.nextActionReason = nextActionReason
        self.nextBlockLabel = nextBlockLabel
        self.notes = notes
        self.subtaskSummary = subtaskSummary
        self.reminderSummary = reminderSummary
    }
}

public enum TodayRecommendationKind: String, Codable, Equatable, Sendable {
    case blocker
    case overdue
    case highPriority
}

public struct TodayRecommendationChip: Identifiable, Equatable, Sendable {
    public var id: String { "\(kind.rawValue)-\(taskID)" }
    public var kind: TodayRecommendationKind
    public var taskID: Int64
    public var taskTitle: String
    public var title: String
    public var systemImage: String
    public var reason: String

    public init(
        kind: TodayRecommendationKind,
        taskID: Int64,
        taskTitle: String,
        title: String,
        systemImage: String,
        reason: String
    ) {
        self.kind = kind
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.title = title
        self.systemImage = systemImage
        self.reason = reason
    }
}

public struct PlanningDayKey: Hashable, Sendable {
    public let localDate: Date
    public let calendarIdentifier: Calendar.Identifier
    public let timeZoneIdentifier: String

    public init(referenceDate: Date, calendar: Calendar) {
        self.localDate = calendar.startOfDay(for: referenceDate)
        self.calendarIdentifier = calendar.identifier
        self.timeZoneIdentifier = calendar.timeZone.identifier
    }

    public static let empty = PlanningDayKey(
        referenceDate: Date(timeIntervalSince1970: 0),
        calendar: Calendar(identifier: .gregorian)
    )
}

public struct TodayWorkflowSnapshot: Equatable, Sendable {
    public var planningDayKey: PlanningDayKey
    public var plan: TodayWorkflowPlan
    public var assistantContext: TodayAssistantRailContext
    public var recommendationChips: [TodayRecommendationChip]
    public var dailyPlanningReviewPreview: DailyPlanningReview?

    public init(
        plan: TodayWorkflowPlan,
        assistantContext: TodayAssistantRailContext,
        recommendationChips: [TodayRecommendationChip],
        planningDayKey: PlanningDayKey = .empty,
        dailyPlanningReviewPreview: DailyPlanningReview? = nil
    ) {
        self.planningDayKey = planningDayKey
        self.plan = plan
        self.assistantContext = assistantContext
        self.recommendationChips = recommendationChips
        self.dailyPlanningReviewPreview = dailyPlanningReviewPreview
    }
}

public struct TodayScheduleDraft: Equatable, Sendable {
    public var timeBlocks: [TodayTimeBlock]

    public init(timeBlocks: [TodayTimeBlock]) {
        self.timeBlocks = timeBlocks
    }
}

public struct ScheduleDraft: Equatable, Sendable {
    public var timeBlocks: [TodayTimeBlock]
    public var unscheduledTasks: [ProjectBoardTask]

    public init(timeBlocks: [TodayTimeBlock], unscheduledTasks: [ProjectBoardTask]) {
        self.timeBlocks = timeBlocks
        self.unscheduledTasks = unscheduledTasks
    }
}

public enum ProjectPortfolioHealth: String, CaseIterable, Identifiable, Sendable {
    case onTrack
    case attention
    case atRisk
    case completed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .onTrack:
            "On Track"
        case .attention:
            "Needs Attention"
        case .atRisk:
            "At Risk"
        case .completed:
            "Completed"
        }
    }
}

public struct ProjectPortfolioSummary: Identifiable, Equatable, Sendable {
    public var id: Int64 { projectID }
    public var projectID: Int64
    public var title: String
    public var status: String
    public var progress: Double
    public var openTaskCount: Int
    public var doneTaskCount: Int
    public var blockedTaskCount: Int
    public var overdueTaskCount: Int
    public var nextDueAt: String?
    public var recentTaskID: Int64?
    public var nextActionTitle: String
    public var health: ProjectPortfolioHealth
    public var riskReason: String
    public var localHealthRuleDescription: String

    public init(
        projectID: Int64,
        title: String,
        status: String,
        progress: Double,
        openTaskCount: Int,
        doneTaskCount: Int,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        nextDueAt: String?,
        recentTaskID: Int64?,
        nextActionTitle: String,
        health: ProjectPortfolioHealth,
        riskReason: String,
        localHealthRuleDescription: String
    ) {
        self.projectID = projectID
        self.title = title
        self.status = status
        self.progress = progress
        self.openTaskCount = openTaskCount
        self.doneTaskCount = doneTaskCount
        self.blockedTaskCount = blockedTaskCount
        self.overdueTaskCount = overdueTaskCount
        self.nextDueAt = nextDueAt
        self.recentTaskID = recentTaskID
        self.nextActionTitle = nextActionTitle
        self.health = health
        self.riskReason = riskReason
        self.localHealthRuleDescription = localHealthRuleDescription
    }
}

public struct DoneAnalyticsSummary: Equatable, Sendable {
    public var completedTaskCount: Int
    public var completedProjectCount: Int
    public var completedTodayCount: Int
    public var completedThisWeekCount: Int
    public var streakDays: Int
    public var completionHeatmapBuckets: [DoneAnalyticsDayBucket]
    public var bestWeekdaySummary: DoneAnalyticsBestWeekdaySummary
    public var bestHourSummary: DoneAnalyticsBestHourSummary
    public var recentTasks: [ProjectBoardTask]
    public var localRuleInsight: String

    public init(
        completedTaskCount: Int,
        completedProjectCount: Int,
        completedTodayCount: Int,
        completedThisWeekCount: Int,
        streakDays: Int,
        completionHeatmapBuckets: [DoneAnalyticsDayBucket] = [],
        bestWeekdaySummary: DoneAnalyticsBestWeekdaySummary = .empty,
        bestHourSummary: DoneAnalyticsBestHourSummary = .empty,
        recentTasks: [ProjectBoardTask],
        localRuleInsight: String
    ) {
        self.completedTaskCount = completedTaskCount
        self.completedProjectCount = completedProjectCount
        self.completedTodayCount = completedTodayCount
        self.completedThisWeekCount = completedThisWeekCount
        self.streakDays = streakDays
        self.completionHeatmapBuckets = completionHeatmapBuckets
        self.bestWeekdaySummary = bestWeekdaySummary
        self.bestHourSummary = bestHourSummary
        self.recentTasks = recentTasks
        self.localRuleInsight = localRuleInsight
    }
}

public struct DoneAnalyticsDayBucket: Equatable, Sendable {
    public var dayKey: String
    public var completedCount: Int

    public init(dayKey: String, completedCount: Int) {
        self.dayKey = dayKey
        self.completedCount = completedCount
    }
}

public struct DoneAnalyticsBestWeekdaySummary: Equatable, Sendable {
    public var weekday: Int?
    public var completedCount: Int

    public var isEmpty: Bool {
        weekday == nil
    }

    public init(weekday: Int?, completedCount: Int = 0) {
        self.weekday = weekday
        self.completedCount = completedCount
    }

    public static let empty = DoneAnalyticsBestWeekdaySummary(
        weekday: nil,
        completedCount: 0
    )
}

public struct DoneAnalyticsBestHourSummary: Equatable, Sendable {
    public var hour: Int?
    public var timeOfDay: DoneAnalyticsTimeOfDay?
    public var completedCount: Int

    public init(
        hour: Int?,
        timeOfDay: DoneAnalyticsTimeOfDay?,
        completedCount: Int = 0
    ) {
        self.hour = hour
        self.timeOfDay = timeOfDay
        self.completedCount = completedCount
    }

    public var isEmpty: Bool {
        hour == nil || timeOfDay == nil
    }

    public static let empty = DoneAnalyticsBestHourSummary(
        hour: nil,
        timeOfDay: nil,
        completedCount: 0
    )
}

public enum DoneAnalyticsTimeOfDay: String, Equatable, Sendable {
    case morning
    case afternoon
    case evening
    case night
}

public struct InboxClassificationFeedback: Equatable, Sendable {
    public var message: String
    public var systemImage: String
    public var canUndo: Bool

    public init(message: String, systemImage: String, canUndo: Bool) {
        self.message = message
        self.systemImage = systemImage
        self.canUndo = canUndo
    }
}

public struct InboxTriageSummary: Equatable, Sendable {
    public var sourceLabel: String
    public var interpretationLabel: String
    public var systemImage: String
    public var tintName: String
    public var accessibilityValue: String

    public init(
        sourceLabel: String,
        interpretationLabel: String,
        systemImage: String,
        tintName: String,
        accessibilityValue: String
    ) {
        self.sourceLabel = sourceLabel
        self.interpretationLabel = interpretationLabel
        self.systemImage = systemImage
        self.tintName = tintName
        self.accessibilityValue = accessibilityValue
    }
}

public enum InboxTriageFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case voice
    case aiSuggested
    case manual
    case unprocessed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All"
        case .voice:
            "Voice"
        case .aiSuggested:
            "AI Suggested"
        case .manual:
            "Manual"
        case .unprocessed:
            "Unprocessed"
        }
    }
}

/// Categories used by the reference Inbox surface. This is intentionally
/// separate from `InboxTriageFilter`: triage filters describe capture origin
/// and processing state, while the reference tabs describe the user's review
/// queue. Keeping both contracts lets the workflow retain its existing
/// lifecycle semantics while presenting the product-facing taxonomy.
public enum InboxReferenceFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case task
    case proposal
    case notification

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all:
            "All"
        case .task:
            "Tasks"
        case .proposal:
            "Proposals"
        case .notification:
            "Notifications"
        }
    }

    public var category: InboxReferenceCategory? {
        switch self {
        case .all:
            nil
        case .task:
            .task
        case .proposal:
            .proposal
        case .notification:
            .notification
        }
    }
}

public enum InboxReferenceCategory: String, Sendable {
    case task
    case proposal
    case notification
}
