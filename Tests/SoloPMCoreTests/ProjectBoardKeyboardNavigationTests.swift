import XCTest
@testable import SoloPMCore

final class ProjectBoardKeyboardNavigationTests: XCTestCase {
    private let orderedTaskIDs: [Int64] = [11, 22, 33]

    func testNextTaskIDAdvancesAndClampsAtTheEnd() {
        XCTAssertEqual(ProjectBoardKeyboardNavigation.nextTaskID(after: 11, in: orderedTaskIDs), 22)
        XCTAssertEqual(ProjectBoardKeyboardNavigation.nextTaskID(after: 22, in: orderedTaskIDs), 33)
        XCTAssertEqual(ProjectBoardKeyboardNavigation.nextTaskID(after: 33, in: orderedTaskIDs), 33, "no wrap at the end")
    }

    func testPreviousTaskIDRetreatsAndClampsAtTheStart() {
        XCTAssertEqual(ProjectBoardKeyboardNavigation.previousTaskID(before: 33, in: orderedTaskIDs), 22)
        XCTAssertEqual(ProjectBoardKeyboardNavigation.previousTaskID(before: 22, in: orderedTaskIDs), 11)
        XCTAssertEqual(ProjectBoardKeyboardNavigation.previousTaskID(before: 11, in: orderedTaskIDs), 11, "no wrap at the start")
    }

    func testMissingSelectionStartsAtFirstForNextAndLastForPrevious() {
        XCTAssertEqual(ProjectBoardKeyboardNavigation.nextTaskID(after: nil, in: orderedTaskIDs), 11)
        XCTAssertEqual(ProjectBoardKeyboardNavigation.previousTaskID(before: nil, in: orderedTaskIDs), 33)
        XCTAssertEqual(ProjectBoardKeyboardNavigation.nextTaskID(after: 999, in: orderedTaskIDs), 11, "stale selection restarts at the top")
        XCTAssertEqual(ProjectBoardKeyboardNavigation.previousTaskID(before: 999, in: orderedTaskIDs), 33)
    }

    func testEmptyOrderingReturnsNil() {
        XCTAssertNil(ProjectBoardKeyboardNavigation.nextTaskID(after: nil, in: []))
        XCTAssertNil(ProjectBoardKeyboardNavigation.previousTaskID(before: 7, in: []))
    }

    func testOrderedTaskIDsFlattenColumnsInBoardRenderOrder() {
        let project = ProjectBoardProject(
            id: 1,
            title: "Launch",
            subtitle: "",
            columns: [
                ProjectBoardColumn(status: .backlog, tasks: [
                    makeTask(id: 5, status: .backlog),
                    makeTask(id: 2, status: .backlog)
                ]),
                ProjectBoardColumn(status: .planned, tasks: []),
                ProjectBoardColumn(status: .inProgress, tasks: [
                    makeTask(id: 9, status: .inProgress)
                ])
            ]
        )

        XCTAssertEqual(ProjectBoardKeyboardNavigation.orderedTaskIDs(in: project), [5, 2, 9])
    }

    private func makeTask(id: Int64, status: ProjectTaskStatus) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: 1,
            title: "Task \(id)",
            detail: "",
            status: status,
            priority: .medium,
            dueAt: nil
        )
    }
}
