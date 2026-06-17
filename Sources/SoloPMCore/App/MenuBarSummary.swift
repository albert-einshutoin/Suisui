import Foundation

public struct MenuBarSummary: Equatable, Sendable {
    public var todayTaskCount: Int
    public var overdueTaskCount: Int
    public var dueThisWeekCount: Int
    public var recentProjectTitles: [String]

    public init(
        todayTaskCount: Int = 0,
        overdueTaskCount: Int = 0,
        dueThisWeekCount: Int = 0,
        recentProjectTitles: [String] = []
    ) {
        self.todayTaskCount = todayTaskCount
        self.overdueTaskCount = overdueTaskCount
        self.dueThisWeekCount = dueThisWeekCount
        self.recentProjectTitles = recentProjectTitles
    }

    public init(deadlineSummary: DeadlineSummary, recentProjectTitles: [String] = []) {
        self.init(
            todayTaskCount: deadlineSummary.today.count,
            overdueTaskCount: deadlineSummary.overdue.count,
            dueThisWeekCount: deadlineSummary.thisWeek.count,
            recentProjectTitles: recentProjectTitles
        )
    }

    public static let empty = MenuBarSummary()
}

public struct MenuBarSummaryViewModel: Equatable, Sendable {
    public var summary: MenuBarSummary

    public init(summary: MenuBarSummary = .empty) {
        self.summary = summary
    }

    public var todayLabel: String {
        summary.todayTaskCount == 1 ? "1 task today" : "\(summary.todayTaskCount) tasks today"
    }

    public var overdueLabel: String {
        summary.overdueTaskCount == 1 ? "1 overdue" : "\(summary.overdueTaskCount) overdue"
    }

    public var thisWeekLabel: String {
        summary.dueThisWeekCount == 1 ? "1 due this week" : "\(summary.dueThisWeekCount) due this week"
    }

    public var hasRecentProjects: Bool {
        !summary.recentProjectTitles.isEmpty
    }
}
