import XCTest
@testable import Suisui

final class TodayDashboardLayoutMetricsTests: XCTestCase {
    func testWidePolicyFitsThe1448CanonicalWindowAfterSidebarAndInsets() {
        let nativeSplitChromeWidth: CGFloat = 20
        let canonicalDetailWidth = 1_448 - ProjectBoardLayoutMetrics.sidebarColumnIdealWidth - nativeSplitChromeWidth
        let canonicalAvailableWidth = canonicalDetailWidth - TodayDashboardLayoutMetrics.horizontalInsets

        XCTAssertTrue(TodayDashboardLayoutMetrics.isWide(availableWidth: canonicalAvailableWidth))
        XCTAssertLessThanOrEqual(TodayDashboardLayoutMetrics.twoColumnMinimumWidth, canonicalAvailableWidth)
        XCTAssertLessThanOrEqual(
            TodayDashboardLayoutMetrics.twoColumnMinimumWidth
                + TodayDashboardLayoutMetrics.horizontalInsets
                + ProjectBoardLayoutMetrics.sidebarColumnIdealWidth
                + nativeSplitChromeWidth,
            1_448
        )
    }

    func testWidePolicyKeepsThe1024CanonicalWindowCompact() {
        let nativeSplitChromeWidth: CGFloat = 20
        let compactDetailWidth = 1_024 - ProjectBoardLayoutMetrics.sidebarColumnIdealWidth - nativeSplitChromeWidth
        let compactAvailableWidth = compactDetailWidth - TodayDashboardLayoutMetrics.horizontalInsets

        XCTAssertFalse(TodayDashboardLayoutMetrics.isWide(availableWidth: compactAvailableWidth))
    }
}
