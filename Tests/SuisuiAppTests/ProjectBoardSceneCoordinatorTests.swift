import XCTest
@testable import Suisui

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
}
