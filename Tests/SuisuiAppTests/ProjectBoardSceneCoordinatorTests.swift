import XCTest
@testable import Suisui
import SuisuiCore

@MainActor
final class ProjectBoardSceneCoordinatorTests: XCTestCase {
    func testClosingActiveSceneFallsBackToRemainingBoard() {
        let coordinator = ProjectBoardSceneCoordinator()
        let firstSceneID = UUID()
        let secondSceneID = UUID()

        coordinator.register(sceneID: firstSceneID)
        coordinator.register(sceneID: secondSceneID)
        coordinator.markActive(sceneID: secondSceneID)
        coordinator.unregister(sceneID: secondSceneID)

        XCTAssertEqual(coordinator.activeSceneID, firstSceneID)
    }

    func testKeyWindowObservedBeforeRegistrationBecomesActiveWhenRegistered() {
        let coordinator = ProjectBoardSceneCoordinator()
        let firstSceneID = UUID()
        let secondSceneID = UUID()

        coordinator.register(sceneID: firstSceneID)
        coordinator.markActive(sceneID: secondSceneID)
        coordinator.register(sceneID: secondSceneID)

        XCTAssertEqual(coordinator.activeSceneID, secondSceneID)
    }

    func testRouteShortcutTargetsActiveBoardWithoutOpeningAnotherWindow() {
        let coordinator = ProjectBoardSceneCoordinator()
        let sceneID = UUID()
        let routeDelivered = expectation(description: "Route delivered to active board")
        var openedWindowCount = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .suisuiProjectBoardShortcutRequested,
            object: nil,
            queue: nil
        ) { notification in
            guard let request = notification.object as? ProjectBoardShortcutRequest,
                  case let .route(route) = request.action else {
                return
            }
            XCTAssertEqual(request.sceneID, sceneID)
            XCTAssertEqual(route, .voiceCommand)
            routeDelivered.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.openInActiveSceneOrRequestNew(route: .settings) {
            openedWindowCount += 1
        }
        XCTAssertEqual(openedWindowCount, 1)
        coordinator.register(sceneID: sceneID)
        XCTAssertEqual(coordinator.consumeNext(for: sceneID)?.route, .settings)

        coordinator.openInActiveSceneOrRequestNew(route: .voiceCommand) {
            openedWindowCount += 1
        }
        XCTAssertEqual(openedWindowCount, 1)
        wait(for: [routeDelivered], timeout: 0)
    }

}
