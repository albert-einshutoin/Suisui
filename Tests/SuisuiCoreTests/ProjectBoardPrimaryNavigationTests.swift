@testable import SuisuiCore
import XCTest

final class ProjectBoardPrimaryNavigationTests: XCTestCase {
    func testPrimaryDestinationsAreFourStableItems() {
        XCTAssertEqual(
            BoardPrimaryDestination.allCases,
            [.today, .inbox, .projects, .review]
        )
    }

    func testReviewContainsEveryFormerWorkflowDestinationInStableOrder() {
        XCTAssertEqual(
            ReviewRoute.allCases,
            [.schedule, .completed, .automationActivity, .assistantQueue]
        )
    }

    func testLegacyTopLevelWorkflowValuesSelectTheirNewOwningSurface() {
        XCTAssertEqual(route(from: "catch-up"), .primary(.today))
        XCTAssertEqual(route(from: "schedule"), .review(.schedule))
        XCTAssertEqual(route(from: "done"), .review(.completed))
        XCTAssertEqual(route(from: "assistant-queue"), .review(.assistantQueue))
    }

    func testTypedReviewRoutesPreserveTheSelectedChild() {
        XCTAssertEqual(route(from: "primary:review"), .primary(.review))
        XCTAssertEqual(route(from: "review:schedule"), .review(.schedule))
        XCTAssertEqual(route(from: "review:completed"), .review(.completed))
        XCTAssertEqual(route(from: "review:automation"), .review(.automationActivity))
        XCTAssertEqual(route(from: "review:assistant-queue"), .review(.assistantQueue))
    }

    func testProjectAndSmartListRoutesRemainOwnedByProjects() {
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(
                from: "project:42",
                availableProjectIDs: [42]
            ),
            .project(42)
        )
        XCTAssertEqual(
            route(from: ProjectBoardRouteCodec.rawValue(for: .smartList("priority:urgent"))),
            .smartList("priority:urgent")
        )
    }

    private func route(from rawValue: String) -> BoardRoute {
        ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: [])
    }
}
