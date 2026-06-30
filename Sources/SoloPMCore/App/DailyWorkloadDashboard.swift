import Foundation

public struct DailyWorkloadProjectContribution: Identifiable, Equatable, Sendable {
    public var id: Int64 { projectID }
    public var projectID: Int64
    public var projectTitle: String
    public var tasks: [ProjectBoardTask]
    public var openTaskCount: Int
    public var doneTaskCount: Int
    public var blockedTaskCount: Int

    public init(
        projectID: Int64,
        projectTitle: String,
        tasks: [ProjectBoardTask],
        openTaskCount: Int,
        doneTaskCount: Int,
        blockedTaskCount: Int
    ) {
        self.projectID = projectID
        self.projectTitle = projectTitle
        self.tasks = tasks
        self.openTaskCount = openTaskCount
        self.doneTaskCount = doneTaskCount
        self.blockedTaskCount = blockedTaskCount
    }
}

public struct DailyWorkloadDay: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public var date: Date
    public var dateKey: String
    public var totalTaskCount: Int
    public var openTaskCount: Int
    public var inProgressTaskCount: Int
    public var blockedTaskCount: Int
    public var doneTaskCount: Int
    public var overdueTaskCount: Int
    public var progress: Double
    public var projectContributions: [DailyWorkloadProjectContribution]

    public init(
        date: Date,
        dateKey: String,
        totalTaskCount: Int,
        openTaskCount: Int,
        inProgressTaskCount: Int,
        blockedTaskCount: Int,
        doneTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double,
        projectContributions: [DailyWorkloadProjectContribution]
    ) {
        self.date = date
        self.dateKey = dateKey
        self.totalTaskCount = totalTaskCount
        self.openTaskCount = openTaskCount
        self.inProgressTaskCount = inProgressTaskCount
        self.blockedTaskCount = blockedTaskCount
        self.doneTaskCount = doneTaskCount
        self.overdueTaskCount = overdueTaskCount
        self.progress = progress
        self.projectContributions = projectContributions
    }
}

public struct DailyWorkloadOverview: Equatable, Sendable {
    public var days: [DailyWorkloadDay]
    public var unscheduledTasks: [ProjectBoardTask]
    public var inboxUntriagedCount: Int

    public init(
        days: [DailyWorkloadDay],
        unscheduledTasks: [ProjectBoardTask],
        inboxUntriagedCount: Int
    ) {
        self.days = days
        self.unscheduledTasks = unscheduledTasks
        self.inboxUntriagedCount = inboxUntriagedCount
    }
}

enum DailyWorkloadDashboardBuilder {
    static func overview(
        from snapshot: ProjectBoardSnapshot,
        around referenceDate: Date,
        calendar inputCalendar: Calendar,
        visibleDayCount: Int
    ) -> DailyWorkloadOverview {
        let calendar = inputCalendar
        let activeProjects = snapshot.projects.filter { project in
            !project.isArchived && !project.isCompleted
        }
        // Inbox captures are intake, not committed workload. Keeping them as a
        // separate triage count preserves Catch Up semantics and prevents raw
        // voice notes from diluting daily progress percentages.
        let inboxProjects = activeProjects.filter(isInboxProject)
        let committedProjects = activeProjects.filter { !isInboxProject($0) }
        let dayStarts = visibleDayStarts(
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: visibleDayCount
        )
        let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate

        let days = dayStarts.map { dayStart in
            day(
                for: dayStart,
                referenceDayStart: referenceDayStart,
                projects: committedProjects,
                calendar: calendar
            )
        }

        return DailyWorkloadOverview(
            days: days,
            unscheduledTasks: unscheduledTasks(from: committedProjects),
            inboxUntriagedCount: inboxProjects.flatMap(\.tasks).filter { $0.status != .done }.count
        )
    }

    private static func day(
        for dayStart: Date,
        referenceDayStart: Date,
        projects: [ProjectBoardProject],
        calendar: Calendar
    ) -> DailyWorkloadDay {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let contributions = projects.compactMap { project -> DailyWorkloadProjectContribution? in
            let tasks = project.tasks
                .filter { task in
                    guard let dueDate = dueDate(for: task.dueAt, calendar: calendar) else {
                        return false
                    }
                    return dueDate >= dayStart && dueDate < dayEnd
                }
                .sorted { sortTasks($0, $1, calendar: calendar) }
            guard !tasks.isEmpty else {
                return nil
            }
            return DailyWorkloadProjectContribution(
                projectID: project.id,
                projectTitle: project.title,
                tasks: tasks,
                openTaskCount: tasks.filter { $0.status != .done }.count,
                doneTaskCount: tasks.filter { $0.status == .done }.count,
                blockedTaskCount: tasks.filter { $0.status == .blocked }.count
            )
        }
        .sorted { lhs, rhs in
            lhs.projectTitle.localizedStandardCompare(rhs.projectTitle) == .orderedAscending
        }
        let tasks = contributions.flatMap(\.tasks)
        let totalTaskCount = tasks.count
        let doneTaskCount = tasks.filter { $0.status == .done }.count
        let openTaskCount = totalTaskCount - doneTaskCount
        let overdueTaskCount = tasks.filter { task in
            task.status != .done
                && dueDate(for: task.dueAt, calendar: calendar).map { $0 < referenceDayStart } == true
        }.count

        return DailyWorkloadDay(
            date: dayStart,
            dateKey: dateKey(for: dayStart, calendar: calendar),
            totalTaskCount: totalTaskCount,
            openTaskCount: openTaskCount,
            inProgressTaskCount: tasks.filter { $0.status == .inProgress }.count,
            blockedTaskCount: tasks.filter { $0.status == .blocked }.count,
            doneTaskCount: doneTaskCount,
            overdueTaskCount: overdueTaskCount,
            progress: totalTaskCount == 0 ? 0 : Double(doneTaskCount) / Double(totalTaskCount),
            projectContributions: contributions
        )
    }

    private static func visibleDayStarts(
        around referenceDate: Date,
        calendar: Calendar,
        visibleDayCount: Int
    ) -> [Date] {
        let count = max(1, visibleDayCount)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: referenceDate)?.start
        let firstDay = weekStart ?? calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: firstDay)
        }
    }

    private static func unscheduledTasks(from projects: [ProjectBoardProject]) -> [ProjectBoardTask] {
        projects
            .flatMap(\.tasks)
            .filter { task in
                task.status != .done && task.dueAt == nil
            }
            .sorted { sortTasks($0, $1, calendar: .current) }
    }

    private static func sortTasks(_ lhs: ProjectBoardTask, _ rhs: ProjectBoardTask, calendar: Calendar) -> Bool {
        let lhsPriorityRank = priorityRank(lhs.priority)
        let rhsPriorityRank = priorityRank(rhs.priority)
        if lhsPriorityRank != rhsPriorityRank {
            return lhsPriorityRank < rhsPriorityRank
        }
        let lhsDue = dueDate(for: lhs.dueAt, calendar: calendar) ?? .distantFuture
        let rhsDue = dueDate(for: rhs.dueAt, calendar: calendar) ?? .distantFuture
        if lhsDue != rhsDue {
            return lhsDue < rhsDue
        }
        return lhs.id > rhs.id
    }

    private static func priorityRank(_ priority: ProjectTaskPriority) -> Int {
        switch priority {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }

    private static func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }

    private static func dueDate(for rawDueAt: String?, calendar: Calendar) -> Date? {
        guard let rawDueAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawDueAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawDueAt)
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
