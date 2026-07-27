import Combine
import SuisuiCore
import XCTest

final class TodayFeatureViewModelTests: XCTestCase {
    @MainActor
    func testTodayRelevantTaskMutationPublishesOneAggregateFeatureChange() throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let task = try XCTUnwrap(board.createTask(
            title: "Ship release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: ISO8601DateFormatter().string(from: Date())
        ))
        let feature = TodayFeatureViewModel(board: board)
        var publicationCount = 0
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
        }

        feature.toggleTaskCompletion(id: task.id)

        XCTAssertEqual(publicationCount, 1)
        XCTAssertFalse(feature.snapshot.plan.tasks.contains { $0.id == task.id })
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testScheduleDraftAndFeedbackPublishAsOneFeatureChange() throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let task = try XCTUnwrap(board.createTask(
            title: "Ship release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: ISO8601DateFormatter().string(from: Date())
        ))
        let feature = TodayFeatureViewModel(board: board)
        var publicationCount = 0
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
        }

        let draft = feature.prepareTodayScheduleDraft(prioritizing: task.id)

        XCTAssertNotNil(draft)
        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(feature.scheduleDraft, draft)
        XCTAssertNotNil(feature.commandFeedback)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testRenamingAnotherTodayTasksProjectPublishesUpdatedFeatureOwnedTitle() async throws {
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
        let publication = expectation(description: "Today publishes renamed project title")
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
            publication.fulfill()
        }

        _ = try store.updateProject(id: otherProject.id, title: "Renamed Other Project")
        board.load()
        await fulfillment(of: [publication], timeout: 1)

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(feature.projectTitlesByTaskID[otherTask.id], "Renamed Other Project")
        XCTAssertEqual(feature.projectTitle(for: otherTask), "Renamed Other Project")
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testWaitingOnlyTaskKeepsItsProjectTitleInToday() throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "External Review"))
        let waitingTask = try XCTUnwrap(board.createTask(
            title: "Wait for approval",
            projectID: project.id,
            status: .planned,
            priority: .medium,
            dueAt: nil
        ))
        board.setTaskWaiting(taskID: waitingTask.id, waitingOn: "Client")

        let feature = TodayFeatureViewModel(board: board)

        XCTAssertFalse(feature.snapshot.plan.tasks.contains { $0.id == waitingTask.id })
        XCTAssertTrue(feature.waitingTasks.contains { $0.id == waitingTask.id })
        XCTAssertEqual(feature.projectTitle(for: waitingTask), "External Review")
    }

    @MainActor
    func testDirectBoardSelectionPublishesOneConsistentTodayState() async throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let dueToday = ISO8601DateFormatter().string(from: Date())
        let first = try XCTUnwrap(board.createTask(
            title: "First",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: dueToday
        ))
        let second = try XCTUnwrap(board.createTask(
            title: "Second",
            projectID: project.id,
            status: .planned,
            priority: .low,
            dueAt: dueToday
        ))
        board.selectedTaskID = first.id
        let feature = TodayFeatureViewModel(board: board)
        var publicationCount = 0
        let publication = expectation(description: "Today publishes final direct selection state")
        let observation = feature.objectWillChange.sink {
            publicationCount += 1
            publication.fulfill()
        }

        board.selectedTaskID = second.id
        await fulfillment(of: [publication], timeout: 1)

        XCTAssertEqual(publicationCount, 1)
        XCTAssertEqual(feature.selectedTaskID, second.id)
        XCTAssertEqual(feature.snapshot.assistantContext.task?.id, second.id)
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
