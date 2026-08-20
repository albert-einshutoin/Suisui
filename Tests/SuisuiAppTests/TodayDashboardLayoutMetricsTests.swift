import SuisuiCore
import XCTest
@testable import Suisui

final class TodayDashboardLayoutMetricsTests: XCTestCase {
    func testWidePolicyFitsThe1024CanonicalWindowAfterTheCappedSidebar() {
        let contentWidth = CockpitLayoutPolicy.contentWidth(forWindowWidth: 1_024)

        XCTAssertEqual(contentWidth, 784)
        XCTAssertTrue(TodayDashboardLayoutMetrics.isWide(availableWidth: CGFloat(contentWidth)))
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
        XCTAssertFalse(source.contains("TodayDashboardAlignedRow"))
        XCTAssertTrue(
            source.contains("width: TodayDashboardLayoutMetrics.railMinimumWidth + 18")
        )
    }

    func testMinimumWindowMovesTheRailBelowTheMainSurface() {
        let compactContentWidth = CockpitLayoutPolicy.contentWidth(forWindowWidth: 960)

        XCTAssertEqual(compactContentWidth, 720)
        XCTAssertFalse(
            TodayDashboardLayoutMetrics.isWide(availableWidth: CGFloat(compactContentWidth))
        )
    }
}
