import XCTest
@testable import SoloPMCore

final class ProjectBoardWindowPresentationStateTests: XCTestCase {
    func testFrameIsClampedToVisibleScreenAndMinimumProductSize() {
        let stored = ProjectBoardWindowFrame(x: 1_300, y: 700, width: 420, height: 300)
        let screen = ProjectBoardWindowFrame(x: 0, y: 0, width: 1_440, height: 900)

        let restored = stored.sanitized(visibleFrames: [screen])

        XCTAssertEqual(restored.width, 960)
        XCTAssertEqual(restored.height, 640)
        XCTAssertEqual(restored.x, 480)
        XCTAssertEqual(restored.y, 260)
    }

    func testOffscreenFrameFallsBackToCenteredDefaultWithoutContentData() throws {
        let stored = ProjectBoardWindowFrame(x: 9_000, y: 9_000, width: 1_100, height: 700)
        let screen = ProjectBoardWindowFrame(x: -1_920, y: 0, width: 1_920, height: 1_080)

        let restored = stored.sanitized(visibleFrames: [screen])

        XCTAssertEqual(restored.width, 1_180)
        XCTAssertEqual(restored.height, 760)
        XCTAssertEqual(restored.x, -1_550)
        XCTAssertEqual(restored.y, 160)

        let encoded = try JSONEncoder().encode(ProjectBoardWindowPresentationState(frame: restored))
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("task"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("transcript"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("approval"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("secret"))
    }

    func testVersionMismatchIsRejected() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "version": 99,
            "frame": ["x": 0, "y": 0, "width": 1_180, "height": 760]
        ])

        XCTAssertNil(ProjectBoardWindowPresentationState.decodeCurrent(from: data))
    }
}
