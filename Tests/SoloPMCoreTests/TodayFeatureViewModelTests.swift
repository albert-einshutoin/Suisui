import Combine
import SoloPMCore
import XCTest

final class TodayFeatureViewModelTests: XCTestCase {
    @MainActor
    func testRenamingAnotherTodayTasksProjectPublishesUpdatedFeatureOwnedTitle() throws {
        let store = InMemoryProjectBoardStore()
        let board = ProjectBoardViewModel(store: store)
        board.load()
        let recommendedProject = try XCTUnwrap(board.createProject(title: "Recommended Project"))
        let otherProject = try XCTUnwrap(board.createProject(title: "Other Project"))
        let dueToday = ISO8601DateFormatter().string(from: Date())
        let recommendedTask = try XCTUnwrap(board.createTask(
            title: "Recommended Today Task",
            projectID: recommendedProject.id,
            status: .planned,
            priority: .high,
            dueAt: dueToday
        ))
        let otherTask = try XCTUnwrap(board.createTask(
            title: "Other Today Task",
            projectID: otherProject.id,
            status: .planned,
            priority: .low,
            dueAt: dueToday
        ))
        board.selectedTaskID = recommendedTask.id
        let feature = TodayFeatureViewModel(board: board)
        XCTAssertEqual(feature.snapshot.plan.recommendedTask?.id, recommendedTask.id)
        XCTAssertEqual(feature.selectedTaskID, recommendedTask.id)
        XCTAssertEqual(feature.projectTitlesByTaskID[otherTask.id], "Other Project")
        XCTAssertEqual(feature.projectTitle(for: otherTask), "Other Project")

        var publicationCount = 0
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
        }

        _ = try store.updateProject(id: otherProject.id, title: "Renamed Other Project")
        board.load()

        XCTAssertGreaterThan(publicationCount, 0)
        XCTAssertEqual(feature.projectTitlesByTaskID[otherTask.id], "Renamed Other Project")
        XCTAssertEqual(feature.projectTitle(for: otherTask), "Renamed Other Project")
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testAutomationAndReceiptChangesDoNotPublishTodayFeatureChanges() throws {
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            executionReceiptStore: VolatileExecutionReceiptStore()
        )
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        _ = try XCTUnwrap(board.createTask(
            title: "Ship release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: "2026-07-17T09:00:00Z"
        ))
        let feature = TodayFeatureViewModel(board: board)
        var publicationCount = 0
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
        }
        var boardPublicationCount = 0
        let boardObservation = board.objectWillChange.sink {
            boardPublicationCount += 1
        }

        board.clearDevelopmentAutomationReviewPlan()
        board.setExecutionReceiptHistorySearchText("reviewed")

        XCTAssertGreaterThan(boardPublicationCount, 0)
        XCTAssertEqual(publicationCount, 0)
        withExtendedLifetime(observation) {}
        withExtendedLifetime(boardObservation) {}
    }
}
