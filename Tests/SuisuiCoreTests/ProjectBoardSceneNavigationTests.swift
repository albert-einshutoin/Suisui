@testable import SuisuiCore
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

    func testOnboardingTodayRequestCannotBeClaimedByAnotherWindow() {
        let onboardingSceneID = UUID()
        let otherSceneID = UUID()
        var state = ProjectBoardSceneNavigationState()
        state.register(sceneID: onboardingSceneID)
        state.register(sceneID: otherSceneID)
        let request = ProjectBoardOpenRequest(
            targetSceneID: onboardingSceneID,
            route: OnboardingExperience.learnProjectTargetRoute
        )

        XCTAssertTrue(state.submit(request))
        XCTAssertNil(state.consume(requestID: request.id, for: otherSceneID))
        XCTAssertEqual(
            state.consume(requestID: request.id, for: onboardingSceneID),
            request
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

    func testSceneRestorePreservesCatchUpFocusFromAuthoritativeRawValue() {
        XCTAssertEqual(
            ProjectBoardScenePersistence.restoredResolution(
                sceneRawValue: "catch-up",
                initialRawValue: "primary:inbox",
                availableProjectIDs: []
            ),
            ProjectBoardRouteResolution(route: .primary(.today), focus: .catchUp)
        )
        XCTAssertEqual(
            ProjectBoardScenePersistence.restoredResolution(
                sceneRawValue: "",
                initialRawValue: "catch-up",
                availableProjectIDs: []
            ),
            ProjectBoardRouteResolution(route: .primary(.today), focus: .catchUp)
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

    func testPendingRequestLimitRejectsNewestAndPreservesOldestDeliveryOrder() {
        var state = ProjectBoardSceneNavigationState(pendingRequestLimit: 2)
        let requests = [
            ProjectBoardOpenRequest(route: .primary(.today)),
            ProjectBoardOpenRequest(route: .primary(.inbox)),
            ProjectBoardOpenRequest(route: .primary(.projects))
        ]

        XCTAssertTrue(state.submit(requests[0]))
        XCTAssertTrue(state.submit(requests[1]))
        XCTAssertFalse(state.submit(requests[2]))

        state.register(sceneID: firstSceneID)
        XCTAssertEqual(state.consumeNext(for: firstSceneID), requests[0])
        XCTAssertEqual(state.consumeNext(for: firstSceneID), requests[1])
        XCTAssertNil(state.consumeNext(for: firstSceneID))

        // A capacity rejection is not terminal: the caller may retry after an
        // older intent has been delivered without weakening duplicate safety.
        XCTAssertTrue(state.submit(requests[2]))
        XCTAssertEqual(state.consumeNext(for: firstSceneID), requests[2])
        XCTAssertFalse(state.submit(requests[2]))
    }

    func testPayloadStoreLimitRejectsNewestAndReleasesCapacityOnConsumeOrDiscard() {
        var store = ProjectBoardRequestPayloadStore<String>(limit: 2)
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let fourthID = UUID()

        XCTAssertTrue(store.store("first", id: firstID))
        XCTAssertTrue(store.store("second", id: secondID))
        XCTAssertFalse(store.store("third", id: thirdID))
        XCTAssertEqual(store.consume(id: firstID), "first")
        XCTAssertTrue(store.store("third", id: thirdID))
        store.discard(id: secondID)
        XCTAssertTrue(store.store("fourth", id: fourthID))

        XCTAssertEqual(store.consume(id: thirdID), "third")
        XCTAssertEqual(store.consume(id: fourthID), "fourth")
        XCTAssertNil(store.consume(id: secondID))
    }

    func testPayloadStoreDuplicateAtLimitPreservesOriginalWithoutUsingCapacity() {
        var store = ProjectBoardRequestPayloadStore<String>(limit: 1)
        let firstID = UUID()
        let secondID = UUID()

        XCTAssertTrue(store.store("original", id: firstID))
        XCTAssertFalse(store.store("replacement", id: firstID))
        XCTAssertFalse(store.store("second", id: secondID))
        XCTAssertEqual(store.consume(id: firstID), "original")
        XCTAssertTrue(store.store("second", id: secondID))
    }

    func testRouteOnlyRequestDoesNotMisalignBoundedPayloadCleanup() {
        var state = ProjectBoardSceneNavigationState(pendingRequestLimit: 2)
        var payloads = ProjectBoardRequestPayloadStore<String>(limit: 2)
        let routeOnly = ProjectBoardOpenRequest(route: .primary(.today))
        let payloadRequest = ProjectBoardOpenRequest(route: .primary(.inbox))
        let rejectedRequest = ProjectBoardOpenRequest(route: .primary(.projects))

        XCTAssertTrue(state.submit(routeOnly))
        XCTAssertTrue(payloads.store("payload", id: payloadRequest.id))
        XCTAssertTrue(state.submit(payloadRequest))

        // App bridges store before publishing. When the shared request queue is
        // full, the existing caller contract discards only the rejected ID.
        XCTAssertTrue(payloads.store("rejected", id: rejectedRequest.id))
        XCTAssertFalse(state.submit(rejectedRequest))
        payloads.discard(id: rejectedRequest.id)

        state.register(sceneID: firstSceneID)
        XCTAssertEqual(state.consumeNext(for: firstSceneID), routeOnly)
        XCTAssertNil(payloads.consume(id: routeOnly.id))
        XCTAssertEqual(state.consumeNext(for: firstSceneID), payloadRequest)
        XCTAssertEqual(payloads.consume(id: payloadRequest.id), "payload")
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

    func testApplicationAcknowledgementAppearsOnlyAfterExplicitApplyAck() {
        var acknowledgements = ProjectBoardSceneApplicationAcknowledgements()
        let requestID = UUID()

        XCTAssertFalse(acknowledgements.contains(requestID))
        XCTAssertTrue(acknowledgements.acknowledge(requestID))
        XCTAssertTrue(acknowledgements.contains(requestID))
        XCTAssertFalse(acknowledgements.acknowledge(requestID))
    }

    func testApplicationAcknowledgementHistoryIsBounded() {
        var acknowledgements = ProjectBoardSceneApplicationAcknowledgements(limit: 2)
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        acknowledgements.acknowledge(firstID)
        acknowledgements.acknowledge(secondID)
        acknowledgements.acknowledge(thirdID)

        XCTAssertFalse(acknowledgements.contains(firstID))
        XCTAssertTrue(acknowledgements.contains(secondID))
        XCTAssertTrue(acknowledgements.contains(thirdID))
    }
}
