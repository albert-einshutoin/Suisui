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
        let automationSettings = TaskAutoExecutionSettings(
            isEnabled: true,
            mode: .reviewOnly,
            cadence: .manual
        )
        let referenceDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-17T08:00:00Z")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        _ = board.prepareTaskAutomationReview(
            settings: automationSettings,
            trigger: .manual,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let feature = TodayFeatureViewModel(board: board)
        var publicationCount = 0
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
        }

        _ = board.prepareTaskAutomationReview(
            settings: automationSettings,
            trigger: .manual,
            referenceDate: referenceDate,
            calendar: calendar
        )
        board.setExecutionReceiptHistorySearchText("reviewed")

        XCTAssertEqual(publicationCount, 0)
        withExtendedLifetime(observation) {}
    }
}
