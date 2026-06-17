import Combine
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

public enum MenuBarSummaryTone: Equatable, Sendable {
    case normal
    case attention
}

public struct MenuBarSummaryRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var value: String
    public var systemImage: String
    public var tone: MenuBarSummaryTone

    public init(id: String, title: String, value: String, systemImage: String, tone: MenuBarSummaryTone = .normal) {
        self.id = id
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.tone = tone
    }
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

    public var rows: [MenuBarSummaryRow] {
        [
            MenuBarSummaryRow(id: "today", title: "Today", value: todayLabel, systemImage: "calendar"),
            MenuBarSummaryRow(
                id: "overdue",
                title: "Overdue",
                value: overdueLabel,
                systemImage: "exclamationmark.triangle",
                tone: summary.overdueTaskCount > 0 ? .attention : .normal
            ),
            MenuBarSummaryRow(id: "this-week", title: "This Week", value: thisWeekLabel, systemImage: "clock")
        ]
    }

    public var emptyStateLabel: String? {
        guard summary.todayTaskCount == 0,
              summary.overdueTaskCount == 0,
              summary.dueThisWeekCount == 0,
              summary.recentProjectTitles.isEmpty else {
            return nil
        }

        return "No deadlines need attention"
    }
}

public protocol MenuBarSummaryProviding: Sendable {
    func loadMenuBarSummary() throws -> MenuBarSummary
}

public struct StaticMenuBarSummaryProvider: MenuBarSummaryProviding {
    public var summary: MenuBarSummary

    public init(summary: MenuBarSummary) {
        self.summary = summary
    }

    public func loadMenuBarSummary() throws -> MenuBarSummary {
        summary
    }
}

public final class SQLiteMenuBarSummaryProvider: MenuBarSummaryProviding, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore

    public init(connection: SQLiteConnection) {
        self.connection = connection
        self.projectStore = SQLiteProjectStore(connection: connection)
        self.taskStore = SQLiteTaskStore(connection: connection)
    }

    public convenience init(path: String, migrations: [DatabaseMigration] = CoreMigrations.current) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    public func loadMenuBarSummary() throws -> MenuBarSummary {
        let deadlineSummary = try DeadlineQueryService(projectStore: projectStore, taskStore: taskStore).summary()
        let recentProjectTitles = try projectStore.list().prefix(3).map(\.title)
        return MenuBarSummary(
            deadlineSummary: deadlineSummary,
            recentProjectTitles: Array(recentProjectTitles)
        )
    }
}

@MainActor
public final class MenuBarSummaryController: ObservableObject {
    @Published public private(set) var viewModel: MenuBarSummaryViewModel
    @Published public private(set) var errorMessage: String?

    private let provider: any MenuBarSummaryProviding

    public init(
        provider: any MenuBarSummaryProviding,
        initialViewModel: MenuBarSummaryViewModel = MenuBarSummaryViewModel()
    ) {
        self.provider = provider
        self.viewModel = initialViewModel
    }

    public func refresh() {
        do {
            viewModel = MenuBarSummaryViewModel(summary: try provider.loadMenuBarSummary())
            errorMessage = nil
        } catch {
            viewModel = MenuBarSummaryViewModel(summary: .empty)
            errorMessage = "Menu bar summary is unavailable."
        }
    }
}
