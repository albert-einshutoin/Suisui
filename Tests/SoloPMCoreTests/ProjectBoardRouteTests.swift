@testable import SoloPMCore
import XCTest

final class ProjectBoardRouteTests: XCTestCase {
    func testPrimaryAndReviewCasesHaveStableOrder() {
        XCTAssertEqual(
            BoardPrimaryDestination.allCases,
            [.today, .inbox, .projects, .review]
        )
        XCTAssertEqual(
            ReviewRoute.allCases,
            [.schedule, .completed, .automationActivity, .assistantQueue]
        )
    }

    func testLegacyWorkflowDestinationsMigrateIntoFourPrimaryAreas() {
        XCTAssertEqual(route(from: "today"), .primary(.today))
        XCTAssertEqual(route(from: "inbox"), .primary(.inbox))
        XCTAssertEqual(route(from: "projects"), .primary(.projects))
        XCTAssertEqual(route(from: "schedule"), .review(.schedule))
        XCTAssertEqual(route(from: "done"), .review(.completed))
        XCTAssertEqual(route(from: "assistant-queue"), .review(.assistantQueue))
        XCTAssertEqual(route(from: "catch-up"), .primary(.today))
    }

    func testStableTypedRawValuesDecode() {
        XCTAssertEqual(route(from: "primary:today"), .primary(.today))
        XCTAssertEqual(route(from: "primary:inbox"), .primary(.inbox))
        XCTAssertEqual(route(from: "primary:projects"), .primary(.projects))
        XCTAssertEqual(route(from: "primary:review"), .primary(.review))
        XCTAssertEqual(route(from: "review:schedule"), .review(.schedule))
        XCTAssertEqual(route(from: "review:completed"), .review(.completed))
        XCTAssertEqual(route(from: "review:automation"), .review(.automationActivity))
        XCTAssertEqual(route(from: "review:assistant-queue"), .review(.assistantQueue))
    }

    func testExistingProjectDecodesAndMissingProjectFallsBackToToday() {
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(from: "project:42", availableProjectIDs: [41, 42]),
            .project(42)
        )
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(from: "project:42", availableProjectIDs: [41]),
            .primary(.today)
        )
    }

    func testSmartListIdentifierRoundTripsWithoutLosingColons() {
        let route = BoardRoute.smartList("priority:urgent")

        let rawValue = ProjectBoardRouteCodec.rawValue(for: route)

        XCTAssertEqual(rawValue, "smart-list:priority:urgent")
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: []),
            route
        )
    }

    func testEveryPrimaryAndReviewCaseRoundTripsThroughStableRawValue() {
        let routeRawValues: [(BoardRoute, String)] = [
            (.primary(.today), "primary:today"),
            (.primary(.inbox), "primary:inbox"),
            (.primary(.projects), "primary:projects"),
            (.primary(.review), "primary:review"),
            (.review(.schedule), "review:schedule"),
            (.review(.completed), "review:completed"),
            (.review(.automationActivity), "review:automation"),
            (.review(.assistantQueue), "review:assistant-queue")
        ]

        for (route, expectedRawValue) in routeRawValues {
            let rawValue = ProjectBoardRouteCodec.rawValue(for: route)
            XCTAssertEqual(rawValue, expectedRawValue)
            XCTAssertEqual(
                ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: []),
                route,
                "Expected \(route) to round-trip through \(rawValue)"
            )
        }
    }

    func testValidProjectRoundTripsThroughStableRawValue() {
        let route = BoardRoute.project(42)
        let rawValue = ProjectBoardRouteCodec.rawValue(for: route)

        XCTAssertEqual(rawValue, "project:42")
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: [42]),
            route
        )
    }

    func testInvalidRawValuesSafelyFallBackToToday() {
        let invalidRawValues = [
            "",
            " ",
            "unknown",
            "TODAY",
            "primary:",
            "primary:unknown",
            "primary:today:extra",
            "review:",
            "review:automationActivity",
            "review:assistant-queue:extra",
            "project:",
            "project:not-a-number",
            "project:0",
            "project:-1",
            "project:9223372036854775808",
            "smart-list:",
            "smart-list: ",
            "smart-list: urgent "
        ]

        for rawValue in invalidRawValues {
            XCTAssertEqual(
                ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: [42]),
                .primary(.today),
                "Expected \(rawValue.debugDescription) to fall back to Today"
            )
        }
    }

    func testCodecIsCaseSensitiveAndDoesNotNormalizeWhitespace() {
        XCTAssertEqual(route(from: "Primary:inbox"), .primary(.today))
        XCTAssertEqual(route(from: "review:Schedule"), .primary(.today))
        XCTAssertEqual(route(from: " review:schedule "), .primary(.today))
    }

    private func route(from rawValue: String) -> BoardRoute {
        ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: [])
    }
}
