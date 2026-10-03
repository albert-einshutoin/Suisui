import Foundation

public struct ProjectBoardSidebarMetrics: Equatable, Sendable {
    public var inboxCount: Int
    public var todayCount: Int
    public var catchUpCount: Int
    public var scheduleCount: Int
    public var doneCount: Int
    public var projectsCount: Int

    public init(
        inboxCount: Int,
        todayCount: Int,
        catchUpCount: Int,
        scheduleCount: Int,
        doneCount: Int,
        projectsCount: Int
    ) {
        self.inboxCount = inboxCount
        self.todayCount = todayCount
        self.catchUpCount = catchUpCount
        self.scheduleCount = scheduleCount
        self.doneCount = doneCount
        self.projectsCount = projectsCount
    }

    public static let empty = ProjectBoardSidebarMetrics(
        inboxCount: 0,
        todayCount: 0,
        catchUpCount: 0,
        scheduleCount: 0,
        doneCount: 0,
        projectsCount: 0
    )
}

public struct ProjectBoardScheduleReadModel: Equatable, Sendable {
    public var workloadOverview: DailyWorkloadOverview
    public var weeklyCockpit: WeeklyScheduleCockpit
    public var unscheduledTasks: [ProjectBoardTask]

    public init(
        workloadOverview: DailyWorkloadOverview,
        weeklyCockpit: WeeklyScheduleCockpit,
        unscheduledTasks: [ProjectBoardTask]
    ) {
        self.workloadOverview = workloadOverview
        self.weeklyCockpit = weeklyCockpit
        self.unscheduledTasks = unscheduledTasks
    }

    public static let empty = ProjectBoardScheduleReadModel(
        workloadOverview: DailyWorkloadOverview(days: [], unscheduledTasks: [], inboxUntriagedCount: 0),
        weeklyCockpit: WeeklyScheduleCockpit(
            days: [],
            unscheduledTasks: [],
            agendaDay: nil,
            focusForecast: WeeklyScheduleFocusForecast(
                state: .open,
                overloadedDayKeys: [],
                heavyDayKeys: [],
                reminderProposalCount: 0
            )
        ),
        unscheduledTasks: []
    )
}

public struct ProjectBoardDerivedReadModels: Equatable, Sendable {
    public var sidebarMetrics: ProjectBoardSidebarMetrics
    public var todayWorkflowSnapshot: TodayWorkflowSnapshot
    public var schedule: ProjectBoardScheduleReadModel
    public var doneAnalytics: DoneAnalyticsSummary
    public var missedTaskReview: MissedTaskReviewSummary
    public var projectPortfolioSummaries: [ProjectPortfolioSummary]
    public var builtAt: Date

    public init(
        sidebarMetrics: ProjectBoardSidebarMetrics,
        todayWorkflowSnapshot: TodayWorkflowSnapshot,
        schedule: ProjectBoardScheduleReadModel,
        doneAnalytics: DoneAnalyticsSummary,
        missedTaskReview: MissedTaskReviewSummary,
        projectPortfolioSummaries: [ProjectPortfolioSummary],
        builtAt: Date
    ) {
        self.sidebarMetrics = sidebarMetrics
        self.todayWorkflowSnapshot = todayWorkflowSnapshot
        self.schedule = schedule
        self.doneAnalytics = doneAnalytics
        self.missedTaskReview = missedTaskReview
        self.projectPortfolioSummaries = projectPortfolioSummaries
        self.builtAt = builtAt
    }

    public static let empty = ProjectBoardDerivedReadModels(
        sidebarMetrics: .empty,
        todayWorkflowSnapshot: TodayWorkflowSnapshot(
            plan: TodayWorkflowPlan(
                tasks: [],
                overdueCount: 0,
                dueTodayCount: 0,
                recommendedTask: nil,
                recommendationReason: "No open tasks due today.",
                timeBlocks: []
            ),
            assistantContext: TodayAssistantRailContext(
                source: .empty,
                task: nil,
                projectTitle: "Today",
                nextActionTitle: "No open tasks due today",
                nextActionReason: "Captured work remains in Inbox until it is scheduled or moved to a project.",
                nextBlockLabel: nil,
                notes: "",
                subtaskSummary: "No subtasks",
                reminderSummary: "No reminders"
            ),
            recommendationChips: []
        ),
        schedule: .empty,
        doneAnalytics: DoneAnalyticsSummary(
            completedTaskCount: 0,
            completedProjectCount: 0,
            completedTodayCount: 0,
            completedThisWeekCount: 0,
            streakDays: 0,
            recentTasks: [],
            localRuleInsight: "Done analytics uses local completed_at history; reopened tasks remain visible in completion history."
        ),
        missedTaskReview: .empty,
        projectPortfolioSummaries: [],
        builtAt: Date(timeIntervalSince1970: 0)
    )
}

public extension TodayWorkflowPlan {
    func primaryActionPresentation(commandText: String) -> TodayPrimaryActionPresentation {
        TodayPrimaryActionPresentation.make(
            recommendedTaskID: recommendedTask?.id,
            recommendedTaskTitle: recommendedTask?.title,
            commandText: commandText,
            taskCount: tasks.count
        )
    }
}

struct ProjectBoardDerivedReadModelInputs {
    var nonArchivedProjects: [ProjectBoardProject]
    var committedActiveProjects: [ProjectBoardProject]
    var portfolioProjects: [ProjectBoardProject]
    var completedProjects: [ProjectBoardProject]
    var inboxProject: ProjectBoardProject?
    var inboxTasks: [ProjectBoardTask]
    var inboxUntriagedCount: Int
    var visibleNonArchivedTasks: [ProjectBoardTask]
    var nonArchivedTasks: [ProjectBoardTask]

    init(
        snapshot: ProjectBoardSnapshot,
        showsCompletedWorkflowTasks: Bool,
        inboxUntriagedCountOverride: Int? = nil
    ) {
        let nonArchivedProjects = snapshot.projects.filter { !$0.isArchived }
        let activeProjects = nonArchivedProjects.filter { !$0.isCompleted }
        let inboxProject = nonArchivedProjects.first(where: Self.isInboxProject)

        self.nonArchivedProjects = nonArchivedProjects
        // Inbox is intake, not committed work; Catch Up should not make raw captures
        // look like forgotten tasks before the user triages them into a project.
        self.committedActiveProjects = activeProjects.filter { !Self.isInboxProject($0) }
        self.portfolioProjects = nonArchivedProjects.filter { !Self.isInboxProject($0) }
        self.completedProjects = nonArchivedProjects.filter { $0.isCompleted && !Self.isInboxProject($0) }
        self.inboxProject = inboxProject
        self.inboxTasks = inboxProject?
            .tasks
            .filter { showsCompletedWorkflowTasks || $0.status != .done }
            .sorted { $0.id > $1.id } ?? []
        self.inboxUntriagedCount = inboxUntriagedCountOverride
            ?? inboxProject?.tasks.filter { $0.status != .done }.count
            ?? 0
        self.nonArchivedTasks = nonArchivedProjects.flatMap(\.tasks)
        // Rebuilds need several workflow projections. Flattening once keeps a
        // large local board from paying the same project/task traversal for
        // Today, Done, Catch Up, and sidebar counts during a single refresh.
        self.visibleNonArchivedTasks = self.nonArchivedTasks.filter { showsCompletedWorkflowTasks || $0.status != .done }
    }

    static func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }
}

public enum TodaySnapshotInvalidationReason: String, Sendable {
    case storeReload
    case taskMutation
    case projectMutation
    case completedVisibilityChanged
    case dateBoundaryChanged
    case timezoneOrCalendarChanged
}
