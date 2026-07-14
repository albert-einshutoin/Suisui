@testable import SoloPMCore
import XCTest

final class ProjectBoardSceneNavigationTests: XCTestCase {
    private let firstSceneID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let secondSceneID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

    func testOnlyMatchingSceneCanConsumeTargetedRequest() {
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: firstSceneID,
            route: .review(.assistantQueue)
        )

        XCTAssertNil(ProjectBoardSceneNavigation.route(for: request, sceneID: secondSceneID))
        XCTAssertEqual(
            ProjectBoardSceneNavigation.route(for: request, sceneID: firstSceneID),
            .review(.assistantQueue)
        )
    }

    func testUntargetedRequestMatchesEverySceneAtPureRoutingBoundary() {
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: nil,
            route: .primary(.today)
        )

        XCTAssertEqual(ProjectBoardSceneNavigation.route(for: request, sceneID: firstSceneID), .primary(.today))
        XCTAssertEqual(ProjectBoardSceneNavigation.route(for: request, sceneID: secondSceneID), .primary(.today))
    }

    func testDuplicateRequestIDCanOnlyBeConsumedOnce() {
        var state = ProjectBoardSceneNavigationState()
        state.register(sceneID: firstSceneID)
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: firstSceneID,
            route: .primary(.inbox)
        )

        XCTAssertTrue(state.submit(request))
        XCTAssertFalse(state.submit(request))
        XCTAssertEqual(state.consumeNext(for: firstSceneID), request)
        XCTAssertNil(state.consumeNext(for: firstSceneID))
        XCTAssertFalse(state.submit(request))
    }

    func testTwoRegisteredScenesProduceExactlyOneBroadcastConsumer() {
        var state = ProjectBoardSceneNavigationState()
        state.register(sceneID: firstSceneID)
        state.register(sceneID: secondSceneID)
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: nil,
            route: .review(.completed)
        )

        XCTAssertTrue(state.submit(request))
        XCTAssertEqual(state.consumeNext(for: secondSceneID), request)
        XCTAssertNil(state.consumeNext(for: firstSceneID))
    }

    func testNotificationRequestIDStillRequiresMatchingRegisteredScene() {
        var state = ProjectBoardSceneNavigationState()
        state.register(sceneID: firstSceneID)
        state.register(sceneID: secondSceneID)
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: firstSceneID,
            route: .primary(.inbox)
        )
        XCTAssertTrue(state.submit(request))

        XCTAssertNil(state.consume(requestID: request.id, for: secondSceneID))
        XCTAssertEqual(state.consume(requestID: request.id, for: firstSceneID), request)
        XCTAssertNil(state.consume(requestID: request.id, for: firstSceneID))
    }

    func testUnregisteredSceneCannotConsumeAndTargetedRequestExpiresWhenSceneCloses() {
        var state = ProjectBoardSceneNavigationState()
        state.register(sceneID: firstSceneID)
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: firstSceneID,
            route: .project(42)
        )
        XCTAssertTrue(state.submit(request))

        state.unregister(sceneID: firstSceneID)

        XCTAssertNil(state.consumeNext(for: firstSceneID))
        state.register(sceneID: firstSceneID)
        XCTAssertNil(state.consumeNext(for: firstSceneID))
        XCTAssertFalse(state.submit(request))
    }

    func testClosingOneSceneDoesNotExpireBroadcastForAnotherRegisteredScene() {
        var state = ProjectBoardSceneNavigationState()
        state.register(sceneID: firstSceneID)
        state.register(sceneID: secondSceneID)
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: nil,
            route: .primary(.projects)
        )
        XCTAssertTrue(state.submit(request))

        state.unregister(sceneID: firstSceneID)

        XCTAssertNil(state.consumeNext(for: firstSceneID))
        XCTAssertEqual(state.consumeNext(for: secondSceneID), request)
    }

    func testBroadcastRemainsPendingUntilARegisteredSceneCanClaimIt() {
        var state = ProjectBoardSceneNavigationState()
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: nil,
            route: .primary(.projects)
        )

        XCTAssertTrue(state.submit(request))
        XCTAssertNil(state.consumeNext(for: firstSceneID))
        state.register(sceneID: firstSceneID)
        XCTAssertEqual(state.consumeNext(for: firstSceneID), request)
    }

    func testSceneRestoreOverridesNewWindowInitialRoute() {
        XCTAssertEqual(
            ProjectBoardScenePersistence.restoredRoute(
                sceneRawValue: "review:schedule",
                initialRawValue: "primary:inbox",
                availableProjectIDs: []
            ),
            .review(.schedule)
        )
    }

    func testNewWindowUsesInitialRouteAndMissingProjectFallsBackToToday() {
        XCTAssertEqual(
            ProjectBoardScenePersistence.restoredRoute(
                sceneRawValue: "",
                initialRawValue: "primary:projects",
                availableProjectIDs: []
            ),
            .primary(.projects)
        )
        XCTAssertEqual(
            ProjectBoardScenePersistence.restoredRoute(
                sceneRawValue: "project:42",
                initialRawValue: "primary:inbox",
                availableProjectIDs: []
            ),
            .primary(.today)
        )
    }

    func testOnlyBroadcastRequestUpdatesNewWindowInitialRoute() {
        let targeted = ProjectBoardOpenRequest(
            targetSceneID: firstSceneID,
            route: .primary(.inbox)
        )
        let broadcast = ProjectBoardOpenRequest(
            targetSceneID: nil,
            route: .review(.assistantQueue)
        )

        XCTAssertFalse(ProjectBoardScenePersistence.shouldUpdateInitialRoute(for: targeted))
        XCTAssertTrue(ProjectBoardScenePersistence.shouldUpdateInitialRoute(for: broadcast))
    }

    func testPayloadStoreKeepsConsecutiveRequestsUntilTheirOwnIDIsConsumed() {
        var store = ProjectBoardRequestPayloadStore<String>()
        let firstID = UUID()
        let secondID = UUID()

        XCTAssertTrue(store.store("first", id: firstID))
        XCTAssertTrue(store.store("second", id: secondID))
        XCTAssertEqual(store.consume(id: secondID), "second")
        XCTAssertEqual(store.consume(id: firstID), "first")
        XCTAssertNil(store.consume(id: firstID))
    }

    func testPayloadStoreDuplicateIDPreservesOriginalPayloadAndScopedDiscard() {
        var store = ProjectBoardRequestPayloadStore<String>()
        let firstID = UUID()
        let secondID = UUID()

        XCTAssertTrue(store.store("original", id: firstID))
        XCTAssertFalse(store.store("replacement", id: firstID))
        XCTAssertTrue(store.store("other", id: secondID))
        store.discard(id: secondID)

        XCTAssertEqual(store.consume(id: firstID), "original")
        XCTAssertNil(store.consume(id: secondID))
    }

    func testConsecutiveBroadcastPayloadsSurviveDelayedWindowRegistration() {
        var state = ProjectBoardSceneNavigationState()
        var payloads = ProjectBoardRequestPayloadStore<String>()
        let first = ProjectBoardOpenRequest(route: .primary(.today))
        let second = ProjectBoardOpenRequest(route: .primary(.inbox))

        XCTAssertTrue(payloads.store("first", id: first.id))
        XCTAssertTrue(state.submit(first))
        XCTAssertTrue(payloads.store("second", id: second.id))
        XCTAssertTrue(state.submit(second))

        state.register(sceneID: firstSceneID)
        XCTAssertEqual(state.consumeNext(for: firstSceneID), first)
        XCTAssertEqual(payloads.consume(id: first.id), "first")
        XCTAssertEqual(state.consumeNext(for: firstSceneID), second)
        XCTAssertEqual(payloads.consume(id: second.id), "second")
    }

    func testTerminalHistoryPrunesOldestIDAndKeepsRecentDuplicateProtection() {
        var state = ProjectBoardSceneNavigationState(terminalHistoryLimit: 2)
        state.register(sceneID: firstSceneID)
        let requests = (0..<3).map { index in
            ProjectBoardOpenRequest(
                id: UUID(),
                targetSceneID: firstSceneID,
                route: .project(Int64(index))
            )
        }

        for request in requests {
            XCTAssertTrue(state.submit(request))
            XCTAssertEqual(state.consumeNext(for: firstSceneID), request)
        }

        // IDs older than the bounded process-local history may be reused;
        // recent deliveries remain protected from duplicate handling.
        XCTAssertTrue(state.submit(requests[0]))
        XCTAssertFalse(state.submit(requests[1]))
        XCTAssertFalse(state.submit(requests[2]))
    }

    func testUnknownTargetIsRejectedWithoutPendingAndCanRetryAfterRegistration() {
        var state = ProjectBoardSceneNavigationState()
        let request = ProjectBoardOpenRequest(
            id: UUID(),
            targetSceneID: secondSceneID,
            route: .primary(.inbox)
        )

        XCTAssertFalse(state.submit(request))
        state.register(sceneID: secondSceneID)
        XCTAssertNil(state.consumeNext(for: secondSceneID))
        XCTAssertTrue(state.submit(request))
        XCTAssertEqual(state.consumeNext(for: secondSceneID), request)
    }
}
