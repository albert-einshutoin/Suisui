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
    }

    func testVoiceEvidenceWidthKeepsConversationAndUnderstandingSideBySide() {
        XCTAssertTrue(CockpitLayoutPolicy.presentsSplitRail(contentWidth: 760))
        XCTAssertFalse(CockpitLayoutPolicy.presentsSplitRail(contentWidth: 759))
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
}
