@testable import SuisuiCore
import XCTest

final class CockpitLayoutPolicyTests: XCTestCase {
    func testStandardBoardWindowKeepsSplitRailsBesideTheMainSurface() {
        XCTAssertTrue(
            CockpitLayoutPolicy.presentsSplitRail(
                contentWidth: CockpitLayoutPolicy.contentWidth(forWindowWidth: 1_024)
            )
        )
        XCTAssertTrue(
            CockpitLayoutPolicy.presentsSplitRail(
                contentWidth: CockpitLayoutPolicy.standardContentWidth
            )
        )
        XCTAssertEqual(CockpitLayoutPolicy.standardContentWidth, 784)
    }

    func testMinimumBoardWindowMovesRailsBelowTheMainSurface() {
        XCTAssertFalse(
            CockpitLayoutPolicy.presentsSplitRail(
                contentWidth: CockpitLayoutPolicy.contentWidth(forWindowWidth: 960)
            )
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.contentWidth(forWindowWidth: 960),
            720
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.narrowSecondaryPlacement(contentWidth: 720),
            .stackBelowPrimary
        )
    }

    func testSplitThresholdBoundary() {
        XCTAssertTrue(CockpitLayoutPolicy.presentsSplitRail(contentWidth: 730))
        XCTAssertFalse(CockpitLayoutPolicy.presentsSplitRail(contentWidth: 729))
        XCTAssertEqual(
            CockpitLayoutPolicy.windowWidth(forContentWidth: 730),
            970
        )
    }

    func testWindowRungsMatchSidebarContract() {
        XCTAssertEqual(CockpitLayoutPolicy.minimumWindowWidth, 960)
        XCTAssertEqual(CockpitLayoutPolicy.standardWindowWidth, 1_024)
        XCTAssertEqual(CockpitLayoutPolicy.defaultLaunchWindowWidth, 1_180)
        XCTAssertEqual(CockpitLayoutPolicy.sidebarMaxWidth, 240)
        XCTAssertEqual(
            CockpitLayoutPolicy.contentWidth(forWindowWidth: 1_180),
            940
        )
    }

    func testFixedAndExpandingRailWidthsPerDesk() {
        XCTAssertEqual(CockpitLayoutPolicy.railWidth, 240)
        XCTAssertEqual(CockpitLayoutPolicy.inboxRailWidth, 280)
        XCTAssertEqual(CockpitLayoutPolicy.settingsRailWidth, 280)
        XCTAssertEqual(CockpitLayoutPolicy.conversationUnderstandingRailWidth, 330)
        XCTAssertEqual(
            CockpitLayoutPolicy.railWidth(for: .today, contentWidth: 784),
            240
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.railWidth(for: .inbox, contentWidth: 784),
            280
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.railWidth(for: .settings, contentWidth: 784),
            280
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.railWidth(for: .schedule, contentWidth: 730),
            240
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.railWidth(for: .schedule, contentWidth: 784),
            246.48,
            accuracy: 0.01
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.railWidth(for: .schedule, contentWidth: 1_400),
            320
        )
    }

    func testEveryDeskStacksSecondaryRailWhenNarrow() {
        for desk in CockpitLayoutPolicy.Desk.allCases {
            XCTAssertEqual(
                CockpitLayoutPolicy.narrowSecondaryPlacement(for: desk),
                .stackBelowPrimary,
                "\(desk.rawValue) must keep secondary content reachable by stacking"
            )
        }
    }

    func testAuthoritativeContentWidthOverridesUnderReportedGeometry() {
        // GeometryReader under-reports (~500) while the AppKit window still hosts
        // the 1024 desk (784 content). Prefer the authoritative window width.
        XCTAssertTrue(
            CockpitLayoutPolicy.presentsSplitRail(
                measuredContentWidth: 500,
                authoritativeContentWidth: 784
            )
        )
        XCTAssertFalse(
            CockpitLayoutPolicy.presentsSplitRail(
                measuredContentWidth: 800,
                authoritativeContentWidth: 720
            )
        )
        XCTAssertTrue(
            CockpitLayoutPolicy.presentsSplitRail(
                measuredContentWidth: 784,
                authoritativeContentWidth: nil
            )
        )
    }

    func testLayoutContentWidthCapsIdealInflationAtStandardDetail() {
        XCTAssertEqual(
            CockpitLayoutPolicy.layoutContentWidth(measuredContentWidth: 1_050),
            CockpitLayoutPolicy.standardContentWidth
        )
        XCTAssertEqual(
            CockpitLayoutPolicy.layoutContentWidth(measuredContentWidth: 640),
            640
        )
    }

    func testSecondaryIntegrationsAreOmittedWhenTheRailStacks() {
        XCTAssertTrue(
            CockpitLayoutPolicy.showsSecondaryIntegrations(
                contentWidth: CockpitLayoutPolicy.standardContentWidth
            )
        )
        XCTAssertFalse(
            CockpitLayoutPolicy.showsSecondaryIntegrations(
                contentWidth: CockpitLayoutPolicy.contentWidth(forWindowWidth: 960)
            )
        )
    }

    func testPrimaryColumnMinimumLeavesRoomBesideFixedRails() {
        // At the split floor, every fixed rail still leaves a usable primary.
        let floor = CockpitLayoutPolicy.splitMinimumContentWidth
        let spacing = CockpitLayoutPolicy.splitSpacing
        XCTAssertGreaterThanOrEqual(
            floor - CockpitLayoutPolicy.railWidth - spacing,
            CockpitLayoutPolicy.primaryColumnMinimumWidth
        )
        XCTAssertGreaterThanOrEqual(
            floor - CockpitLayoutPolicy.inboxRailWidth - spacing,
            400
        )
    }
}
