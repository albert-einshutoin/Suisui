import SuisuiCore
import XCTest

final class TodayPrimaryActionPresentationTests: XCTestCase {
    func testRecommendedTaskWinsOverCommandAndSecondaryActions() {
        XCTAssertEqual(
            TodayPrimaryActionPresentation.make(
                recommendedTaskID: 42,
                recommendedTaskTitle: "Ship release",
                commandText: "Capture notes",
                taskCount: 3
            ),
            .startFocus(taskID: 42, title: "Ship release")
        )
    }

    func testCommandTextBecomesInboxActionWithoutRecommendedTask() {
        XCTAssertEqual(
            TodayPrimaryActionPresentation.make(
                recommendedTaskID: nil,
                recommendedTaskTitle: nil,
                commandText: "  Capture notes  ",
                taskCount: 0
            ),
            .addToInbox(text: "Capture notes")
        )
    }

    func testEmptyTodayOffersAddTaskAction() {
        XCTAssertEqual(
            TodayPrimaryActionPresentation.make(
                recommendedTaskID: nil,
                recommendedTaskTitle: nil,
                commandText: "",
                taskCount: 0
            ),
            .addTaskForToday
        )
    }

    func testOpenTodayWithoutExecutableRecommendationExplainsWhyPrimaryIsAbsent() {
        XCTAssertEqual(
            TodayPrimaryActionPresentation.make(
                recommendedTaskID: nil,
                recommendedTaskTitle: nil,
                commandText: "",
                taskCount: 3
            ),
            .unavailable(reason: "No recommended task is ready to focus.")
        )
    }

    func testIncompleteCapturePrefixDoesNotBecomeInboxAction() {
        XCTAssertEqual(
            TodayPrimaryActionPresentation.make(
                recommendedTaskID: nil,
                recommendedTaskTitle: nil,
                commandText: "New task: ",
                taskCount: 0
            ),
            .addTaskForToday
        )
    }
}
