import XCTest
@testable import SoloPMCore

final class MenuBarSummaryViewModelTests: XCTestCase {
    func testEmptySummaryLabelsAreStable() {
        let viewModel = MenuBarSummaryViewModel()

        XCTAssertEqual(viewModel.todayLabel, "0 tasks today")
        XCTAssertEqual(viewModel.overdueLabel, "0 overdue")
        XCTAssertEqual(viewModel.thisWeekLabel, "0 due this week")
        XCTAssertFalse(viewModel.hasRecentProjects)
    }

    func testSummaryLabelsUseSingularForms() {
        let viewModel = MenuBarSummaryViewModel(
            summary: MenuBarSummary(
                todayTaskCount: 1,
                overdueTaskCount: 1,
                dueThisWeekCount: 1,
                recentProjectTitles: ["QZT article"]
            )
        )

        XCTAssertEqual(viewModel.todayLabel, "1 task today")
        XCTAssertEqual(viewModel.overdueLabel, "1 overdue")
        XCTAssertEqual(viewModel.thisWeekLabel, "1 due this week")
        XCTAssertTrue(viewModel.hasRecentProjects)
    }

    func testSummaryRowsKeepStableScanningOrder() {
        let viewModel = MenuBarSummaryViewModel(
            summary: MenuBarSummary(todayTaskCount: 2, overdueTaskCount: 1, dueThisWeekCount: 4)
        )

        XCTAssertEqual(viewModel.rows.map(\.title), ["Today", "Overdue", "This Week"])
        XCTAssertEqual(viewModel.rows.map(\.value), ["2 tasks today", "1 overdue", "4 due this week"])
        XCTAssertEqual(viewModel.rows.map(\.tone), [.normal, .attention, .normal])
    }

    func testEmptyStateLabelIsCalmWhenNothingNeedsAttention() {
        let viewModel = MenuBarSummaryViewModel()

        XCTAssertEqual(viewModel.emptyStateLabel, "No deadlines need attention")
    }

    func testEmptyStateLabelIsHiddenWhenAnySummaryHasWork() {
        let viewModel = MenuBarSummaryViewModel(summary: MenuBarSummary(overdueTaskCount: 1))

        XCTAssertNil(viewModel.emptyStateLabel)
    }

    @MainActor
    func testMenuBarSummaryControllerRefreshesFromProvider() {
        let provider = MutableMenuBarSummaryProvider(summary: MenuBarSummary(todayTaskCount: 1))
        let controller = MenuBarSummaryController(provider: provider)

        controller.refresh()
        XCTAssertEqual(controller.viewModel.todayLabel, "1 task today")

        provider.summary = MenuBarSummary(todayTaskCount: 2, overdueTaskCount: 1, dueThisWeekCount: 4)
        controller.refresh()

        XCTAssertEqual(controller.viewModel.rows.map(\.value), ["2 tasks today", "1 overdue", "4 due this week"])
        XCTAssertNil(controller.errorMessage)
    }

    @MainActor
    func testMenuBarSummaryControllerKeepsLastSummaryWhenRefreshFails() {
        let provider = FailingAfterFirstMenuBarSummaryProvider(summary: MenuBarSummary(todayTaskCount: 3))
        let controller = MenuBarSummaryController(provider: provider)

        controller.refresh()
        provider.shouldFail = true
        controller.refresh()

        XCTAssertEqual(controller.viewModel.todayLabel, "3 tasks today")
        XCTAssertEqual(controller.errorMessage, "Menu bar summary is unavailable.")
    }

    func testSQLiteMenuBarSummaryProviderReadsLatestProjectBoardChanges() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let boardStore = SQLiteProjectBoardStore(connection: connection)
        let provider = SQLiteMenuBarSummaryProvider(connection: connection)

        let project = try boardStore.createProject(title: "Launch Readiness")
        _ = try boardStore.createTask(ProjectBoardTaskDraft(
            projectID: project.id,
            title: "Ship investor demo",
            status: .planned,
            priority: .high,
            dueAt: "2099-01-01"
        ))

        let summary = try provider.loadMenuBarSummary()

        XCTAssertEqual(summary.recentProjectTitles.first, "Launch Readiness")
    }
}

private final class MutableMenuBarSummaryProvider: MenuBarSummaryProviding, @unchecked Sendable {
    var summary: MenuBarSummary

    init(summary: MenuBarSummary) {
        self.summary = summary
    }

    func loadMenuBarSummary() throws -> MenuBarSummary {
        summary
    }
}

private final class FailingAfterFirstMenuBarSummaryProvider: MenuBarSummaryProviding, @unchecked Sendable {
    var summary: MenuBarSummary
    var shouldFail = false

    init(summary: MenuBarSummary) {
        self.summary = summary
    }

    func loadMenuBarSummary() throws -> MenuBarSummary {
        if shouldFail {
            throw DatabaseError.stepFailed("summary unavailable")
        }
        return summary
    }
}
