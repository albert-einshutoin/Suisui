@testable import SuisuiCore
import XCTest

final class ProjectBoardSidebarPresentationTests: XCTestCase {
    private struct QuickActionFixture: Equatable {
        let title: String
        let systemImage: String
    }

    func testItemsMatchApprovedSevenItemOrderAndSymbols() {
        XCTAssertEqual(
            ProjectBoardSidebarPresentation.items,
            [
                .init(id: .inbox, title: "Inbox", systemImage: "tray", behavior: .route(.primary(.inbox))),
                .init(id: .today, title: "Today", systemImage: "sun.max", behavior: .route(.primary(.today))),
                .init(id: .projects, title: "Projects", systemImage: "folder", behavior: .route(.primary(.projects))),
                .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
                .init(id: .completed, title: "Completed", systemImage: "checkmark.circle", behavior: .route(.review(.completed))),
                .init(id: .voiceCommand, title: "Voice Quick Capture", systemImage: "mic", behavior: .route(.voiceCommand)),
                .init(id: .settings, title: "Settings", systemImage: "gearshape", behavior: .route(.settings)),
            ]
        )
    }

    func testQuickActionsMatchApprovedOrderTitlesAndSymbols() {
        XCTAssertEqual(
            ProjectBoardSidebarQuickAction.allCases.map {
                QuickActionFixture(title: $0.title, systemImage: $0.systemImage)
            },
            [
                .init(title: "Add Task", systemImage: "plus.circle"),
                .init(title: "Add by Voice", systemImage: "mic.circle"),
                .init(title: "Block Time", systemImage: "calendar.badge.clock"),
                .init(title: "Import Tasks", systemImage: "square.and.arrow.down"),
            ]
        )
    }

    func testRouteSelectionMapsOnlyOwnedDestinations() {
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.inbox)), .inbox)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.today)), .today)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.projects)), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .project(42)), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .smartList("urgent")), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.schedule)), .schedule)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.completed)), .completed)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .settings), .settings)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .voiceCommand), .voiceCommand)
    }

    func testUnrepresentedReviewRoutesFailClosedWithoutSelection() {
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.review)))
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.automationActivity)))
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.assistantQueue)))
    }
}
