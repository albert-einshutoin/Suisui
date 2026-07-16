import Combine
import SoloPMCore
import XCTest

final class TodayFeatureViewModelTests: XCTestCase {
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
