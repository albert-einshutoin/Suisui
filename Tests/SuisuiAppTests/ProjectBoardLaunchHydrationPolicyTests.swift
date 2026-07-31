import XCTest
@testable import Suisui

final class ProjectBoardLaunchHydrationPolicyTests: XCTestCase {
    func testWindowGroupSkipsHydrationWhenRequestedDirectFallbackAlreadyOwnsAWindow() {
        XCTAssertFalse(
            ProjectBoardLaunchHydrationPolicy.shouldHydrateWindowGroup(
                directFallbackRequested: true,
                directFallbackWindowExists: true
            )
        )
    }

    func testWindowGroupHydratesWhenRequestedFallbackWasNotCreated() {
        XCTAssertTrue(
            ProjectBoardLaunchHydrationPolicy.shouldHydrateWindowGroup(
                directFallbackRequested: true,
                directFallbackWindowExists: false
            )
        )
    }

    func testNormalWindowGroupHydratesEvenIfProductionRecoveryOwnsAFallbackWindow() {
        XCTAssertTrue(
            ProjectBoardLaunchHydrationPolicy.shouldHydrateWindowGroup(
                directFallbackRequested: false,
                directFallbackWindowExists: true
            )
        )
    }
}
