@testable import SuisuiCore
import XCTest

final class ProjectBoardCompactNavigationPresentationTests: XCTestCase {
    private let reviewLabelsByDestination: [ReviewRoute: String] = [
        .schedule: "Schedule",
        .completed: "Completed",
        .automationActivity: "Automation Activity",
        .assistantQueue: "Assistant Queue",
    ]

    func testReviewFixtureCoversEveryDestination() {
        XCTAssertEqual(reviewLabelsByDestination.count, ReviewRoute.allCases.count)
        XCTAssertEqual(Set(reviewLabelsByDestination.keys), Set(ReviewRoute.allCases))
    }

    func testReviewMapsEveryReviewDestinationToItsLocalizedLabel() throws {
        for destination in ReviewRoute.allCases {
            let expectedLabel = try XCTUnwrap(reviewLabelsByDestination[destination])

            XCTAssertEqual(
                ProjectBoardCompactNavigationPresentation.review(
                    route: .review(destination),
                    assistantQueueCount: 0
                ),
                ProjectBoardCompactNavigationPresentation(
                    label: .localized(expectedLabel)
                )
            )
        }
    }

    func testReviewPrimaryRouteUsesLocalizedReviewLabel() {
        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.review(
                route: .primary(.review),
                assistantQueueCount: 0
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .localized("Review")
            )
        )
    }

    func testReviewShowsPositiveAssistantQueueBadge() {
        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.review(
                route: .review(.assistantQueue),
                assistantQueueCount: 3
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .localized("Assistant Queue"),
                badgeCount: 3
            )
        )
    }

    func testReviewHidesZeroAndNegativeAssistantQueueBadges() {
        for count in [0, -1, -20] {
            XCTAssertNil(
                ProjectBoardCompactNavigationPresentation.review(
                    route: .review(.assistantQueue),
                    assistantQueueCount: count
                ).badgeCount
            )
        }
    }

    func testReviewFallbackRoutesUseReviewWithoutBadge() {
        let fallbackRoutes: [BoardRoute] = [
            .primary(.today),
            .primary(.inbox),
            .primary(.projects),
            .project(42),
            .smartList("custom"),
        ]

        for route in fallbackRoutes {
            XCTAssertEqual(
                ProjectBoardCompactNavigationPresentation.review(
                    route: route,
                    assistantQueueCount: 9
                ),
                ProjectBoardCompactNavigationPresentation(
                    label: .localized("Review")
                )
            )
        }
    }

    func testProjectsPrimaryRouteUsesLocalizedPortfolioLabel() {
        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .primary(.projects),
                projects: [],
                smartLists: []
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .localized("Portfolio")
            )
        )
    }

    func testProjectsUsesExactVerbatimProjectTitleWhenFound() {
        let project = makeProject(id: 42, title: "  発売準備 🚀  ")

        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .project(42),
                projects: [project],
                smartLists: []
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .verbatim("  発売準備 🚀  ")
            )
        )
    }

    func testProjectsUsesLocalizedProjectNotFoundWhenProjectIsMissing() {
        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .project(404),
                projects: [makeProject(id: 42, title: "Launch")],
                smartLists: []
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .localized("Project Not Found")
            )
        )
    }

    func testProjectsUsesFirstProjectWhenIDsAreDuplicated() {
        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .project(42),
                projects: [
                    makeProject(id: 42, title: "First project"),
                    makeProject(id: 42, title: "Second project"),
                ],
                smartLists: []
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .verbatim("First project")
            )
        )
    }

    func testProjectsUsesLocalizedPresetSmartListName() {
        let preset = SmartList.presets[0]

        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .smartList(preset.id),
                projects: [],
                smartLists: [preset]
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .localized(preset.name)
            )
        )
    }

    func testProjectsUsesExactVerbatimCustomSmartListName() {
        let custom = SmartList(
            id: "custom-japanese",
            name: "  今週の最優先 🚀  ",
            criteria: SmartListCriteria()
        )

        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .smartList(custom.id),
                projects: [],
                smartLists: [custom]
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .verbatim("  今週の最優先 🚀  ")
            )
        )
    }

    func testProjectsUsesLocalizedSmartListNotFoundWhenSmartListIsMissing() {
        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .smartList("missing"),
                projects: [],
                smartLists: []
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .localized("Smart List Not Found")
            )
        )
    }

    func testProjectsUsesFirstSmartListWhenIDsAreDuplicated() {
        let smartLists = [
            SmartList(
                id: "duplicate",
                name: "First smart list",
                criteria: SmartListCriteria()
            ),
            SmartList(
                id: "duplicate",
                name: "Second smart list",
                criteria: SmartListCriteria()
            ),
        ]

        XCTAssertEqual(
            ProjectBoardCompactNavigationPresentation.projects(
                route: .smartList("duplicate"),
                projects: [],
                smartLists: smartLists
            ),
            ProjectBoardCompactNavigationPresentation(
                label: .verbatim("First smart list")
            )
        )
    }

    func testProjectsFallbackRoutesUseLocalizedProjectNotFound() {
        let fallbackRoutes: [BoardRoute] = [
            .primary(.today),
            .primary(.inbox),
            .primary(.review),
            .review(.schedule),
            .review(.completed),
            .review(.automationActivity),
            .review(.assistantQueue),
        ]

        for route in fallbackRoutes {
            XCTAssertEqual(
                ProjectBoardCompactNavigationPresentation.projects(
                    route: route,
                    projects: [],
                    smartLists: []
                ),
                ProjectBoardCompactNavigationPresentation(
                    label: .localized("Project Not Found")
                )
            )
        }
    }

    private func makeProject(id: Int64, title: String) -> ProjectBoardProject {
        ProjectBoardProject(
            id: id,
            title: title,
            subtitle: "",
            columns: []
        )
    }
}
