import Combine
import Foundation
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
    func testAddingUnscheduledRecommendationToDraftUsesTheLocalScheduleDraft() throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let unscheduled = try XCTUnwrap(board.createTask(
            title: "Schedule release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: nil
        ))
        let feature = TodayFeatureViewModel(board: board)

        XCTAssertTrue(feature.addUnscheduledTaskToScheduleDraft(taskID: unscheduled.id))
        XCTAssertTrue(board.scheduleDraft?.timeBlocks.contains { $0.task.id == unscheduled.id } == true)
    }

    @MainActor
    func testAddingUnscheduledRecommendationToDraftUsesInjectedVisualEvidenceDay() throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let unscheduled = try XCTUnwrap(board.createTask(
            title: "Schedule release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: nil
        ))
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-10T12:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let feature = TodayFeatureViewModel(
            board: board,
            runtimeReferenceDate: { referenceDate },
            runtimeCalendar: { calendar }
        )

        XCTAssertTrue(feature.addUnscheduledTaskToScheduleDraft(taskID: unscheduled.id))
        let rawStartAt = try XCTUnwrap(board.scheduleDraft?.timeBlocks.first(where: { $0.task.id == unscheduled.id })?.startAt)
        let startAt = try XCTUnwrap(ISO8601DateFormatter().date(from: rawStartAt))
        XCTAssertTrue(calendar.isDate(startAt, inSameDayAs: referenceDate))
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

    @MainActor
    func testBoardScheduleReadModelUpdatePublishesUpdatedWeeklyCockpit() async throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let task = try XCTUnwrap(board.createTask(
            title: "Schedule release",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: ISO8601DateFormatter().string(from: Date())
        ))
        let feature = TodayFeatureViewModel(board: board)
        let initialCockpit = feature.schedule.weeklyCockpit
        let publication = expectation(description: "Today publishes updated schedule read model")
        let observation = feature.objectWillChange.sink {
            publication.fulfill()
        }

        _ = board.prepareScheduleDraft()
        await fulfillment(of: [publication], timeout: 1)

        XCTAssertNotEqual(feature.schedule.weeklyCockpit, initialCockpit)
        XCTAssertTrue(feature.schedule.weeklyCockpit.days.flatMap(\.blocks).contains {
            $0.task.id == task.id && $0.source == .scheduleDraft
        })
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testCalendarReadinessPublishesIntoTodayIntegrationStateWithoutViewRuntimeReads() async {
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: StaticGoogleCalendarSync(status: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready))
        )
        let feature = TodayFeatureViewModel(board: board)
        let publication = expectation(description: "Today publishes injected Calendar readiness")
        let observation = feature.objectWillChange.sink {
            publication.fulfill()
        }

        board.refreshGoogleCalendarSyncStatus(now: Date(timeIntervalSince1970: 0))
        await fulfillment(of: [publication], timeout: 1)

        XCTAssertEqual(feature.integrationStates.calendar, .connected)
        XCTAssertEqual(feature.integrationStates.slack, .notConnected)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testPreloadedCalendarReadinessIsAvailableBeforeTodayRenders() {
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            initialGoogleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)
        )
        let feature = TodayFeatureViewModel(board: board)

        XCTAssertEqual(feature.integrationStates.calendar, .connected)
    }

    @MainActor
    func testSettingsReadinessNotificationRefreshesTodayIntegrationOffMain() async {
        let sync = MutableGoogleCalendarSync(
            status: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .oauthDisconnected)
        )
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: sync
        )
        let feature = TodayFeatureViewModel(board: board)
        let publication = expectation(description: "Today publishes refreshed Calendar readiness")
        let observation = feature.objectWillChange.sink {
            publication.fulfill()
        }

        sync.setStatus(GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready))
        NotificationCenter.default.post(name: .suisuiGoogleCalendarReadinessDidChange, object: nil)
        await fulfillment(of: [publication], timeout: 1)

        XCTAssertEqual(feature.integrationStates.calendar, .connected)
        withExtendedLifetime(observation) {}
    }

    @MainActor
    func testInitialBoardLoadKeepsPreloadedCalendarReadinessWithoutRuntimeRead() {
        let sync = CountingGoogleCalendarSync(
            status: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .oauthDisconnected)
        )
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: sync,
            initialGoogleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)
        )

        board.load()

        XCTAssertEqual(board.googleCalendarSyncStatus.state, .ready)
        XCTAssertEqual(sync.statusReadCount, 0)
    }

    @MainActor
    func testInitialBoardLoadWithoutPreloadedReadinessRefreshesTodayIntegrationOffMain() async {
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: StaticGoogleCalendarSync(
                status: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)
            )
        )
        let feature = TodayFeatureViewModel(board: board)
        let publication = expectation(description: "Today receives unpreloaded Calendar readiness")
        Task { @MainActor in
            for _ in 0..<100 where feature.integrationStates.calendar != .connected {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if feature.integrationStates.calendar == .connected {
                publication.fulfill()
            }
        }

        board.load()
        await fulfillment(of: [publication], timeout: 1)

        XCTAssertEqual(feature.integrationStates.calendar, .connected)
    }

    @MainActor
    func testSynchronousReadinessRefreshInvalidatesAnOlderOffMainResult() async {
        let sync = BlockingGoogleCalendarSync(
            firstStatus: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .oauthDisconnected),
            nextStatus: GoogleCalendarRuntimeSyncStatus(plan: .pro, state: .ready)
        )
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            googleCalendarSync: sync
        )

        board.refreshGoogleCalendarSyncStatusOffMain(now: Date(timeIntervalSince1970: 0))
        await Task.yield()
        XCTAssertEqual(sync.waitForFirstStatusStart(), .success)

        board.refreshGoogleCalendarSyncStatus(now: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(board.googleCalendarSyncStatus.state, .ready)

        sync.releaseFirstStatus()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(board.googleCalendarSyncStatus.state, .ready)
    }

    @MainActor
    func testScheduleRefreshLoadsExternalEventsOffMainForVisibleWeek() async throws {
        let event = ExternalScheduleEvent(
            id: "google-event-1",
            title: "Interview",
            startAt: ISO8601DateFormatter().date(from: "2026-08-18T01:00:00Z")!,
            endAt: ISO8601DateFormatter().date(from: "2026-08-18T02:00:00Z")!,
            isAllDay: false
        )
        let source = RecordingExternalScheduleEventSource(events: [event])
        let board = ProjectBoardViewModel(
            store: InMemoryProjectBoardStore(),
            externalScheduleEventSource: source
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let publication = expectation(description: "External Calendar events published")

        board.refreshScheduleReadModel(
            around: ISO8601DateFormatter().date(from: "2026-08-18T12:00:00Z")!,
            calendar: calendar
        )
        Task { @MainActor in
            for _ in 0..<100 where board.externalScheduleEventLoadState != .loaded {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if board.externalScheduleEventLoadState == .loaded { publication.fulfill() }
        }

        await fulfillment(of: [publication], timeout: 1)
        let interval = try XCTUnwrap(source.intervals.first)
        XCTAssertEqual(board.externalScheduleEvents, [event])
        XCTAssertEqual(interval.duration, 7 * 24 * 60 * 60)
        XCTAssertTrue(interval.contains(event.startAt))
    }

    @MainActor
    func testRecommendationFocusStartsSessionAndRequiresExplicitReplacement() throws {
        let board = ProjectBoardViewModel(store: InMemoryProjectBoardStore())
        board.load()
        let project = try XCTUnwrap(board.createProject(title: "Launch"))
        let firstTask = try XCTUnwrap(board.createTask(
            title: "First focus",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: nil
        ))
        let secondTask = try XCTUnwrap(board.createTask(
            title: "Second focus",
            projectID: project.id,
            status: .planned,
            priority: .high,
            dueAt: nil
        ))
        let session = TodayFocusSessionStore(persistence: TestFocusSessionPersistence())
        let feature = TodayFeatureViewModel(
            board: board,
            focusSessionRegistry: TodayFocusSessionStoreRegistry { session }
        )

        XCTAssertEqual(feature.startFocusSession(taskID: firstTask.id, durationSeconds: 1_500), .success(session.record))
        XCTAssertEqual(feature.focusSession.record.taskID, firstTask.id)
        XCTAssertEqual(feature.focusSession.record.state, .running)
        XCTAssertEqual(board.todayFocusTaskID, firstTask.id)

        XCTAssertEqual(
            feature.startFocusSession(taskID: secondTask.id, durationSeconds: 1_500),
            .failure(.requiresReplacement(existingTaskID: firstTask.id))
        )
        XCTAssertEqual(feature.focusSession.record.taskID, firstTask.id)
        XCTAssertEqual(board.todayFocusTaskID, firstTask.id)

        XCTAssertEqual(feature.startFocusSession(taskID: secondTask.id, durationSeconds: 1_500, replaceExisting: true), .success(feature.focusSession.record))
        XCTAssertEqual(feature.focusSession.record.taskID, secondTask.id)
        XCTAssertEqual(board.todayFocusTaskID, secondTask.id)
    }
}

private struct StaticGoogleCalendarSync: GoogleCalendarRuntimeSyncing {
    let status: GoogleCalendarRuntimeSyncStatus

    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus { status }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        GoogleCalendarTaskSyncResult()
    }
}

private final class RecordingExternalScheduleEventSource: ExternalScheduleEventSource, @unchecked Sendable {
    private let lock = NSLock()
    private let events: [ExternalScheduleEvent]
    private var recordedIntervals: [DateInterval] = []

    init(events: [ExternalScheduleEvent]) {
        self.events = events
    }

    var intervals: [DateInterval] {
        lock.lock()
        defer { lock.unlock() }
        return recordedIntervals
    }

    func listEvents(in interval: DateInterval) throws -> [ExternalScheduleEvent] {
        lock.lock()
        recordedIntervals.append(interval)
        lock.unlock()
        return events
    }
}

private final class MutableGoogleCalendarSync: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private var currentStatus: GoogleCalendarRuntimeSyncStatus

    init(status: GoogleCalendarRuntimeSyncStatus) {
        currentStatus = status
    }

    func setStatus(_ status: GoogleCalendarRuntimeSyncStatus) {
        lock.lock()
        defer { lock.unlock() }
        currentStatus = status
    }

    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        lock.lock()
        defer { lock.unlock() }
        return currentStatus
    }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        GoogleCalendarTaskSyncResult()
    }
}

private final class CountingGoogleCalendarSync: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private let currentStatus: GoogleCalendarRuntimeSyncStatus
    private(set) var statusReadCount = 0

    init(status: GoogleCalendarRuntimeSyncStatus) {
        currentStatus = status
    }

    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        lock.lock()
        defer { lock.unlock() }
        statusReadCount += 1
        return currentStatus
    }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        GoogleCalendarTaskSyncResult()
    }
}

private final class BlockingGoogleCalendarSync: GoogleCalendarRuntimeSyncing, @unchecked Sendable {
    private let lock = NSLock()
    private let firstStatus: GoogleCalendarRuntimeSyncStatus
    private let nextStatus: GoogleCalendarRuntimeSyncStatus
    private let firstStatusStarted = DispatchSemaphore(value: 0)
    private let firstStatusRelease = DispatchSemaphore(value: 0)
    private var statusCallCount = 0

    init(firstStatus: GoogleCalendarRuntimeSyncStatus, nextStatus: GoogleCalendarRuntimeSyncStatus) {
        self.firstStatus = firstStatus
        self.nextStatus = nextStatus
    }

    func waitForFirstStatusStart() -> DispatchTimeoutResult {
        firstStatusStarted.wait(timeout: .now() + 1)
    }

    func releaseFirstStatus() {
        firstStatusRelease.signal()
    }

    func status(now: Date) throws -> GoogleCalendarRuntimeSyncStatus {
        lock.lock()
        statusCallCount += 1
        let call = statusCallCount
        lock.unlock()
        guard call == 1 else { return nextStatus }
        firstStatusStarted.signal()
        _ = firstStatusRelease.wait(timeout: .now() + 1)
        return firstStatus
    }

    func syncDueTasks(context: ToolExecutionContext) throws -> GoogleCalendarTaskSyncResult {
        GoogleCalendarTaskSyncResult()
    }
}

private final class TestFocusSessionPersistence: FocusSessionPersistence {
    private var record: FocusSessionRecord?

    func load() -> FocusSessionRecord? { record }

    func save(_ record: FocusSessionRecord?) {
        self.record = record
    }
}
