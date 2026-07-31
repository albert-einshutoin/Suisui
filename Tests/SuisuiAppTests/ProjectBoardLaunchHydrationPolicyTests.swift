import XCTest
@testable import Suisui

@MainActor
final class ProjectBoardLaunchHydrationPolicyTests: XCTestCase {
    func testWindowGroupWaitsForRequestedDirectFallbackThenSuppressesInitialScene() async {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()
        let initialDecision = Task { @MainActor in
            await policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true
            )
        }

        await Task.yield()
        policy.resolveDirectFallbackCreation(created: true)

        let shouldHydrateInitialScene = await initialDecision.value
        let shouldHydrateReconstructedScene = await policy.shouldHydrateWindowGroup(
            sceneID: initialSceneID,
            directFallbackRequested: true
        )
        XCTAssertFalse(shouldHydrateInitialScene)
        XCTAssertFalse(shouldHydrateReconstructedScene)
    }

    func testWindowGroupWaitsForRequestedDirectFallbackThenHydratesWhenCreationFails() async {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()
        let decision = Task { @MainActor in
            await policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true
            )
        }

        await Task.yield()
        policy.resolveDirectFallbackCreation(created: false)

        let shouldHydrate = await decision.value
        XCTAssertTrue(shouldHydrate)
    }

    func testLateFallbackResolutionDoesNotSuppressAUserWindowAfterInitialWindowHydrated() async {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()
        let initialDecision = Task { @MainActor in
            await policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true
            )
        }

        await Task.yield()
        policy.resolveDirectFallbackCreation(created: false)
        policy.resolveDirectFallbackCreation(created: true)

        let shouldHydrateInitialScene = await initialDecision.value
        let shouldHydrateLaterScene = await policy.shouldHydrateWindowGroup(
            sceneID: UUID(),
            directFallbackRequested: true
        )
        XCTAssertTrue(shouldHydrateInitialScene)
        XCTAssertTrue(shouldHydrateLaterScene)
    }

    func testLaterUserCreatedWindowHydratesAfterInitialWindowWasSuppressed() async {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()
        let laterSceneID = UUID()
        let initialDecision = Task { @MainActor in
            await policy.shouldHydrateWindowGroup(
                sceneID: initialSceneID,
                directFallbackRequested: true
            )
        }

        await Task.yield()
        policy.resolveDirectFallbackCreation(created: true)

        let shouldHydrateInitialScene = await initialDecision.value
        let shouldHydrateLaterScene = await policy.shouldHydrateWindowGroup(
            sceneID: laterSceneID,
            directFallbackRequested: true
        )
        XCTAssertFalse(shouldHydrateInitialScene)
        XCTAssertTrue(shouldHydrateLaterScene)
    }

    func testFallbackResolutionBeforeWindowGroupProducesTheSameOwnershipDecision() async {
        let policy = ProjectBoardLaunchHydrationPolicy()
        let initialSceneID = UUID()
        policy.resolveDirectFallbackCreation(created: true)

        let shouldHydrateInitialScene = await policy.shouldHydrateWindowGroup(
            sceneID: initialSceneID,
            directFallbackRequested: true
        )
        let shouldHydrateLaterScene = await policy.shouldHydrateWindowGroup(
            sceneID: UUID(),
            directFallbackRequested: true
        )
        XCTAssertFalse(shouldHydrateInitialScene)
        XCTAssertTrue(shouldHydrateLaterScene)
    }

    func testNormalWindowGroupHydratesEvenIfProductionRecoveryOwnsAFallbackWindow() async {
        let policy = ProjectBoardLaunchHydrationPolicy()
        policy.resolveDirectFallbackCreation(created: true)

        let shouldHydrate = await policy.shouldHydrateWindowGroup(
            sceneID: UUID(),
            directFallbackRequested: false
        )
        XCTAssertTrue(shouldHydrate)
    }
}
