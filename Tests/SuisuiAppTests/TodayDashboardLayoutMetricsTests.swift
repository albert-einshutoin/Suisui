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
        let wideStart = try XCTUnwrap(source.range(of: "private func wideBoard("))
        let wideEnd = try XCTUnwrap(
            source.range(of: "private func mainContent(", range: wideStart.upperBound..<source.endIndex)
        )
        let wideBoard = String(source[wideStart.lowerBound..<wideEnd.lowerBound])

        XCTAssertTrue(wideBoard.contains("accessibilityIdentifier(\"today-wide-board\")"))
        XCTAssertTrue(wideBoard.contains("presentsCardsHorizontally: false"))
        XCTAssertTrue(wideBoard.contains("showsSecondaryIntegrations: false"))
        XCTAssertTrue(wideBoard.contains("TodayDashboardRailView(") || wideBoard.contains("rail("))
        XCTAssertFalse(wideBoard.contains("TodayDashboardAlignedRow"))
        XCTAssertTrue(
            wideBoard.contains("width: TodayDashboardLayoutMetrics.railMinimumWidth")
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
