import XCTest
@testable import Suisui

final class TodayDashboardLayoutMetricsTests: XCTestCase {
    func testWidePolicyFitsThe1448CanonicalWindowAfterSidebarAndInsets() {
        // NavigationSplitView expands the 200pt ideal sidebar to 294pt in the
        // real 1448pt product window. The policy must use that observed width,
        // otherwise the reference-size window silently falls back to compact.
        let observedSidebarWidth: CGFloat = 294
        let canonicalDetailWidth = 1_448 - observedSidebarWidth
        let canonicalAvailableWidth = canonicalDetailWidth - TodayDashboardLayoutMetrics.horizontalInsets

        XCTAssertTrue(TodayDashboardLayoutMetrics.isWide(availableWidth: canonicalAvailableWidth))
        XCTAssertLessThanOrEqual(TodayDashboardLayoutMetrics.twoColumnMinimumWidth, canonicalAvailableWidth)
        XCTAssertLessThanOrEqual(
            TodayDashboardLayoutMetrics.twoColumnMinimumWidth
                + TodayDashboardLayoutMetrics.horizontalInsets
                + observedSidebarWidth,
            1_448
        )
    }

    func testWidePolicyMovesTheRailBelowAt1280And1024() {
        let observedSidebarWidth: CGFloat = 294
        let compactDetailWidth = 1_280 - observedSidebarWidth
        let compactAvailableWidth = compactDetailWidth - TodayDashboardLayoutMetrics.horizontalInsets

        XCTAssertFalse(TodayDashboardLayoutMetrics.isWide(availableWidth: compactAvailableWidth))

        let smallDetailWidth = 1_024 - observedSidebarWidth
        XCTAssertFalse(
            TodayDashboardLayoutMetrics.isWide(
                availableWidth: smallDetailWidth - TodayDashboardLayoutMetrics.horizontalInsets
            )
        )
    }
}
