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
}

