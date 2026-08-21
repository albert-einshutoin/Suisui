import SuisuiCore
import XCTest
@testable import Suisui

final class TodayDashboardLayoutMetricsTests: XCTestCase {
    func testWidePolicyFitsThe1024CanonicalWindowAfterTheCappedSidebar() {
        let contentWidth = CockpitLayoutPolicy.contentWidth(forWindowWidth: 1_024)

        XCTAssertEqual(contentWidth, 784)
        XCTAssertTrue(TodayDashboardLayoutMetrics.isWide(availableWidth: CGFloat(contentWidth)))
        XCTAssertTrue(
            TodayDashboardLayoutMetrics.prefersContinuousRail(boardWidth: CGFloat(contentWidth))
        )
        XCTAssertLessThanOrEqual(
            TodayDashboardLayoutMetrics.railMinimumWidth
                + TodayDashboardLayoutMetrics.columnSpacing
                + TodayDashboardLayoutMetrics.primaryMinimumWidth,
            CGFloat(contentWidth)
        )
        XCTAssertEqual(TodayDashboardLayoutMetrics.railMinimumWidth, CGFloat(CockpitLayoutPolicy.railWidth))
        XCTAssertEqual(TodayDashboardLayoutMetrics.sectionSpacing, SuisuiSpacing.lg)
        XCTAssertEqual(TodayDashboardLayoutMetrics.widgetSpacing, SuisuiSpacing.md)
        XCTAssertEqual(TodayDashboardLayoutMetrics.railWidgetMinHeight, 168)
    }

    func testWideBoardKeepsContinuousRailBesidePrimaryColumn() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/SuisuiApp/Views/TodayDashboardView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("accessibilityIdentifier(\"today-wide-board\")"))
        XCTAssertTrue(source.contains("presentsCardsHorizontally: false"))
        XCTAssertTrue(source.contains("showsSecondaryIntegrations: false"))
        XCTAssertTrue(source.contains("Keep the rail outside the primary ScrollView"))
        XCTAssertTrue(source.contains("resolvedPrefersContinuousRail(boardWidth:"))
        XCTAssertTrue(source.contains("let boardWidth = min(layoutWidth, proposedWidth)"))
        XCTAssertTrue(source.contains("cockpitSplitSecondaryRail(width:"))
        XCTAssertTrue(source.contains("let primaryWidth = max("))
        XCTAssertTrue(source.contains(".clipped()"))
        XCTAssertTrue(source.contains("prefersContinuousRail(boardWidth:"))
        XCTAssertFalse(source.contains("TodayDashboardAlignedRow"))
        XCTAssertTrue(
            source.contains("width: TodayDashboardLayoutMetrics.railMinimumWidth + 18")
                || source.contains("let railSpan = TodayDashboardLayoutMetrics.railMinimumWidth + 18")
        )
        XCTAssertTrue(source.contains("width: boardWidth"))
        XCTAssertTrue(source.contains("frame(width: primaryWidth"))
    }

    func testMinimumWindowMovesTheRailBelowTheMainSurface() {
        let compactContentWidth = CockpitLayoutPolicy.contentWidth(forWindowWidth: 960)

        XCTAssertEqual(compactContentWidth, 720)
        XCTAssertFalse(
            TodayDashboardLayoutMetrics.isWide(availableWidth: CGFloat(compactContentWidth))
        )
        XCTAssertFalse(
            TodayDashboardLayoutMetrics.prefersContinuousRail(boardWidth: CGFloat(compactContentWidth))
        )
    }

    func testUnderMeasuredBoardWidthStacksEvenWhenAuthoritativeWidthWouldSplit() {
        // GeometryReader can propose ~600 while AppKit still reports 784.
        // Splitting against the larger width paints the rail over the primary.
        XCTAssertFalse(
            TodayDashboardLayoutMetrics.prefersContinuousRail(boardWidth: 600)
        )
        XCTAssertTrue(
            TodayDashboardLayoutMetrics.prefersContinuousRail(boardWidth: 784)
        )
    }
}
