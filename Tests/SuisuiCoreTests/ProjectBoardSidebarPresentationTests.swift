@testable import SuisuiCore
import XCTest

final class ProjectBoardSidebarPresentationTests: XCTestCase {
    func testItemsMatchApprovedSevenItemOrderAndSymbols() {
        XCTAssertEqual(
            ProjectBoardSidebarPresentation.items,
            [
                .init(id: .inbox, title: "Inbox", systemImage: "tray", behavior: .route(.primary(.inbox))),
                .init(id: .today, title: "Today", systemImage: "sun.max", behavior: .route(.primary(.today))),
                .init(id: .projects, title: "Projects", systemImage: "folder", behavior: .route(.primary(.projects))),
                .init(id: .schedule, title: "Schedule", systemImage: "calendar", behavior: .route(.review(.schedule))),
                .init(id: .completed, title: "Completed", systemImage: "checkmark.circle", behavior: .route(.review(.completed))),
                .init(id: .voiceCommand, title: "Voice Command", systemImage: "mic", behavior: .openVoiceCommand),
                .init(id: .settings, title: "Settings", systemImage: "gearshape", behavior: .openSettings),
            ]
        )
    }

    func testQuickActionsMatchApprovedOrderAndSymbols() {
        XCTAssertEqual(ProjectBoardSidebarQuickAction.allCases, [.addTask, .addByVoice, .blockTime])
        XCTAssertEqual(ProjectBoardSidebarQuickAction.addTask.systemImage, "plus.circle")
        XCTAssertEqual(ProjectBoardSidebarQuickAction.addByVoice.systemImage, "mic.circle")
        XCTAssertEqual(ProjectBoardSidebarQuickAction.blockTime.systemImage, "calendar.badge.clock")
    }

    func testRouteSelectionMapsOnlyOwnedDestinations() {
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.inbox)), .inbox)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.today)), .today)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.projects)), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .project(42)), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .smartList("urgent")), .projects)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.schedule)), .schedule)
        XCTAssertEqual(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.completed)), .completed)
    }

    func testUnrepresentedReviewRoutesFailClosedWithoutSelection() {
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .primary(.review)))
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.automationActivity)))
        XCTAssertNil(ProjectBoardSidebarPresentation.selectedItemID(for: .review(.assistantQueue)))
    }
}
