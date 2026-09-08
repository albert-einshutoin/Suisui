@testable import SuisuiCore
import XCTest

final class ProjectBoardSidebarPresentationTests: XCTestCase {
    private struct QuickActionFixture: Equatable {
        let title: String
        let systemImage: String
    }

    func testItemsMatchSecretaryScheduleWorkOrderAndSymbols() {
        XCTAssertEqual(
            ProjectBoardSidebarPresentation.items,
            [
                .init(id: .secretary, title: "Secretary", systemImage: "person.crop.circle", behavior: .route(.voiceCommand)),
                .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
                .init(id: .work, title: "Work", systemImage: "checklist", behavior: .route(.primary(.today))),
            ]
        )
        XCTAssertEqual(
            ProjectBoardSidebarPresentation.utilityItems,
            [
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
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .voiceCommand), .secretary)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.schedule)), .schedule)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.today)), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.inbox)), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.projects)), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .project(42)), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .smartList("urgent")), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.completed)), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .settings), .settings)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.assistantQueue)), .work)
    }

    func testRemovedReviewRoutesRemainInsideWorkInsteadOfPrimaryNavigation() {
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.review)), .work)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.automationActivity)), .work)
    }
}
