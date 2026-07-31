import XCTest
@testable import Suisui

@MainActor
final class ProjectBoardLaunchHydrationPolicyTests: XCTestCase {
    func testInitialWindowGroupRemainsSuppressedWhileRequestedDirectFallbackOwnsAWindow() {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()

        XCTAssertFalse(
            policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true,
                directFallbackWindowExists: true
            )
        )
        XCTAssertFalse(
            policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true,
                directFallbackWindowExists: true
            )
        )
    }

    func testWindowGroupHydratesWhenRequestedFallbackWasNotCreated() {
        let policy = ProjectBoardLaunchHydrationPolicy()

        XCTAssertTrue(
            policy.shouldHydrateWindowGroup(
                sceneID: UUID(),
                directFallbackRequested: true,
                directFallbackWindowExists: false
            )
        )
    }

    func testLateFallbackDoesNotSuppressAUserWindowAfterInitialWindowHydrated() {
        let policy = ProjectBoardLaunchHydrationPolicy()

        XCTAssertTrue(
            policy.shouldHydrateWindowGroup(
                sceneID: UUID(),
                directFallbackRequested: true,
                directFallbackWindowExists: false
            )
        )
        XCTAssertTrue(
            policy.shouldHydrateWindowGroup(
                sceneID: UUID(),
                directFallbackRequested: true,
                directFallbackWindowExists: true
            )
        )
    }

    func testLaterUserCreatedWindowHydratesAfterInitialWindowWasSuppressed() {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()
        let laterSceneID = UUID()

        XCTAssertFalse(
            policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true,
                directFallbackWindowExists: true
            )
        )
        XCTAssertTrue(
            policy.shouldHydrateWindowGroup(
                sceneID: laterSceneID,
                directFallbackRequested: true,
                directFallbackWindowExists: true
            )
        )
    }

    func testNormalWindowGroupHydratesEvenIfProductionRecoveryOwnsAFallbackWindow() {
        let policy = ProjectBoardLaunchHydrationPolicy()

        XCTAssertTrue(
            policy.shouldHydrateWindowGroup(
                sceneID: UUID(),
                directFallbackRequested: false,
                directFallbackWindowExists: true
            )
        )
    }
}
