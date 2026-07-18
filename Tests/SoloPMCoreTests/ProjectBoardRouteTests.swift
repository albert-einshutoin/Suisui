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

    func testHubPresentationProtectsContentAtCompactWidths() {
        XCTAssertEqual(ProjectBoardHubPresentationPolicy.presentation(for: 960), .compact)
        XCTAssertEqual(ProjectBoardHubPresentationPolicy.presentation(for: 1_099), .compact)
        XCTAssertEqual(ProjectBoardHubPresentationPolicy.presentation(for: 1_100), .wide)
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

    func testLegacyCatchUpResolutionPreservesOneShotTodayFocusIntent() {
        XCTAssertEqual(
            ProjectBoardRouteCodec.resolution(
                from: "catch-up",
                availableProjectIDs: []
            ),
            ProjectBoardRouteResolution(route: .primary(.today), focus: .catchUp)
        )
        XCTAssertEqual(
            ProjectBoardRouteCodec.resolution(
                from: "primary:today",
                availableProjectIDs: []
            ),
            ProjectBoardRouteResolution(route: .primary(.today), focus: nil)
        )
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
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(from: "project:0", availableProjectIDs: []),
            .primary(.today)
        )
        XCTAssertEqual(
            ProjectBoardRouteCodec.route(from: "project:-1", availableProjectIDs: []),
            .primary(.today)
        )
    }

    func testSmartListCanonicalEncodingPreservesEveryStringPayload() {
        let identifiers = [
            "",
            " ",
            " leading",
            "trailing ",
            "priority:urgent",
            "日本語:🚀",
            "line\nfeed",
            "nul\u{0000}byte",
            "v1:not-base64"
        ]

        for identifier in identifiers {
            let route = BoardRoute.smartList(identifier)
            let rawValue = ProjectBoardRouteCodec.rawValue(for: route)

            XCTAssertTrue(rawValue.hasPrefix("smart-list-v1:"))
            XCTAssertEqual(
                ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: []),
                route,
                "Expected \(identifier.debugDescription) to round-trip losslessly"
            )
        }
        XCTAssertEqual(
            ProjectBoardRouteCodec.rawValue(for: .smartList("priority:urgent")),
            "smart-list-v1:cHJpb3JpdHk6dXJnZW50"
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

    func testProjectIdentifiersRoundTripAcrossEntireInt64RangeWhenAvailable() {
        let projectIDs = [Int64.min, -1, 0, 42, Int64.max]

        for projectID in projectIDs {
            let route = BoardRoute.project(projectID)
            let rawValue = ProjectBoardRouteCodec.rawValue(for: route)

            XCTAssertEqual(rawValue, "project:\(projectID)")
            XCTAssertEqual(
                ProjectBoardRouteCodec.route(from: rawValue, availableProjectIDs: [projectID]),
                route
            )
        }
    }

    func testLegacySmartListValueIncludingV1PrefixRemainsCompatible() {
        XCTAssertEqual(
            route(from: "smart-list:priority:urgent"),
            .smartList("priority:urgent")
        )
        XCTAssertEqual(
            route(from: "smart-list:v1:not-base64"),
            .smartList("v1:not-base64")
        )
        XCTAssertEqual(
            route(from: ProjectBoardRouteCodec.rawValue(for: .smartList("v1:not-base64"))),
            .smartList("v1:not-base64")
        )
        XCTAssertTrue(
            ProjectBoardRouteCodec.rawValue(for: .smartList("v1:not-base64"))
                .hasPrefix("smart-list-v1:")
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
            "project:9223372036854775808",
            "smart-list:",
            "smart-list: ",
            "smart-list: urgent ",
            "smart-list:urgent\u{0000}now",
            "smart-list:urgent\nnow",
            "smart-list-v1:====",
            "smart-list-v1:Zg",
            "smart-list-v1:/w=="
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
