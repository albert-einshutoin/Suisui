import AppKit
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

    func testKeyWindowObservedBeforeRegistrationBecomesActiveWhenRegistered() {
        let coordinator = ProjectBoardSceneCoordinator()
        let firstSceneID = UUID()
        let secondSceneID = UUID()

        coordinator.register(sceneID: firstSceneID)
        coordinator.markActive(sceneID: secondSceneID)
        coordinator.register(sceneID: secondSceneID)

        XCTAssertEqual(coordinator.activeSceneID, secondSceneID)
    }

    func testShortcutBringsTargetBoardWindowForward() {
        let sceneID = UUID()
        let windowCoordinator = ProjectBoardWindowStateBridge.Coordinator(
            sceneID: sceneID,
            restoresPrimaryWindow: false
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        windowCoordinator.attach(to: window)
        window.orderOut(nil)

        NotificationCenter.default.post(
            name: .suisuiProjectBoardShortcutRequested,
            object: ProjectBoardShortcutRequest(sceneID: sceneID, action: .commandPalette)
        )

        XCTAssertTrue(window.isVisible)
        windowCoordinator.detach(savingCurrentFrame: false)
        window.close()
    }
}
