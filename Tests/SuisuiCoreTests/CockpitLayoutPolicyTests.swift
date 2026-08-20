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
        XCTAssertTrue(CockpitLayoutPolicy.presentsSplitRail(contentWidth: 730))
        XCTAssertFalse(CockpitLayoutPolicy.presentsSplitRail(contentWidth: 729))
    }

    func testInboxTriageRailIsWiderThanSharedWorkflowRails() {
        XCTAssertEqual(CockpitLayoutPolicy.railWidth, 240)
        XCTAssertEqual(CockpitLayoutPolicy.inboxRailWidth, 280)
        XCTAssertGreaterThan(
            CockpitLayoutPolicy.inboxRailWidth,
            CockpitLayoutPolicy.railWidth
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
}
