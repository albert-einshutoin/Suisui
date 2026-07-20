import Foundation
@testable import SuisuiCore
import XCTest

final class ProjectBoardSelectionPersistenceTests: XCTestCase {
    override func tearDown() {
        unsetenv(ProjectBoardSelectionPersistence.environmentOverrideKey)
        unsetenv(ProjectBoardTaskSelectionPersistence.environmentOverrideKey)
        super.tearDown()
    }

    func testRawValuesRemainStableForSavedProjectBoardSelection() {
        XCTAssertEqual(ProjectBoardSelectionPersistence.storageKey, "suisui.projectBoard.selectedDestination")
        XCTAssertEqual(ProjectBoardSelectionPersistence.environmentOverrideKey, "SUISUI_PROJECT_BOARD_SELECTED_DESTINATION")
        XCTAssertEqual(ProjectBoardSelectionPersistence.defaultRawValue, "today")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .inbox), "inbox")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .assistantQueue), "assistant-queue")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .today), "today")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .schedule), "schedule")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .done), "done")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .projects), "projects")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(for: .project(42)), "project:42")
    }

    func testDestinationRestoresExistingProjectSelection() {
        let projects = [
            makeProject(id: 41),
            makeProject(id: 42)
        ]

        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "assistant-queue",
                availableProjects: projects
            ),
            .assistantQueue
        )

        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "project:42",
                availableProjects: projects
            ),
            .project(42)
        )
    }

    func testDestinationFallsBackToTodayWhenSavedProjectWasDeleted() {
        let projects = [
            makeProject(id: 41),
            makeProject(id: 43)
        ]

        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "project:42",
                availableProjects: projects
            ),
            .today
        )
        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "project:42",
                availableProjects: []
            ),
            .today
        )
    }

    func testDestinationFallsBackToTodayForMalformedSavedSelection() {
        let projects = [makeProject(id: 42)]

        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "project:not-a-number",
                availableProjects: projects
            ),
            .today
        )
        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "unknown:42",
                availableProjects: projects
            ),
            .today
        )
        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "",
                availableProjects: projects
            ),
            .today
        )
    }

    func testTypedRouteAdapterAcceptsLegacyFixtureValuesWithoutChangingLegacyDestinationAPI() {
        let projects = [makeProject(id: 42)]

        XCTAssertEqual(
            ProjectBoardSelectionPersistence.route(
                from: "assistant-queue",
                availableProjects: projects
            ),
            .review(.assistantQueue)
        )
        XCTAssertEqual(
            ProjectBoardSelectionPersistence.destination(
                from: "assistant-queue",
                availableProjects: projects
            ),
            .assistantQueue
        )
    }

    func testTypedRouteAdapterEmitsStableNewRawValues() {
        XCTAssertEqual(
            ProjectBoardSelectionPersistence.rawValue(forTypedRoute: .primary(.review)),
            "primary:review"
        )
        XCTAssertEqual(
            ProjectBoardSelectionPersistence.rawValue(forTypedRoute: .review(.automationActivity)),
            "review:automation"
        )
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(forTypedRoute: .project(0)), "project:0")
        XCTAssertEqual(ProjectBoardSelectionPersistence.rawValue(forTypedRoute: .smartList("")), "smart-list-v1:")
    }

    func testEnvironmentOverrideTrimsWhitespaceAndIgnoresEmptyValues() {
        setenv(ProjectBoardSelectionPersistence.environmentOverrideKey, "  project:42  ", 1)
        XCTAssertEqual(ProjectBoardSelectionPersistence.environmentOverrideRawValue, "project:42")

        setenv(ProjectBoardSelectionPersistence.environmentOverrideKey, "   ", 1)
        XCTAssertNil(ProjectBoardSelectionPersistence.environmentOverrideRawValue)
    }

    func testTaskEnvironmentOverrideAcceptsPositiveTaskIDOnly() {
        XCTAssertEqual(ProjectBoardTaskSelectionPersistence.environmentOverrideKey, "SUISUI_PROJECT_BOARD_SELECTED_TASK_ID")

        setenv(ProjectBoardTaskSelectionPersistence.environmentOverrideKey, "  42  ", 1)
        XCTAssertEqual(ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID, 42)

        setenv(ProjectBoardTaskSelectionPersistence.environmentOverrideKey, "0", 1)
        XCTAssertNil(ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID)

        setenv(ProjectBoardTaskSelectionPersistence.environmentOverrideKey, "not-a-task", 1)
        XCTAssertNil(ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID)

        setenv(ProjectBoardTaskSelectionPersistence.environmentOverrideKey, "   ", 1)
        XCTAssertNil(ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID)
    }

    private func makeProject(id: Int64) -> ProjectBoardProject {
        ProjectBoardProject(
            id: id,
            title: "Project \(id)",
            subtitle: "Selection test fixture",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: [])
            }
        )
    }
}
