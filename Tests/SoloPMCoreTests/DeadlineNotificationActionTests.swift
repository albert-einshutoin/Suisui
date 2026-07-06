import XCTest
@testable import SoloPMCore

final class DeadlineNotificationActionTests: XCTestCase {
    private final class RecordingNotificationClient: NotificationClient, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [NotificationDraft] = []

        var scheduledDrafts: [NotificationDraft] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
            lock.lock()
            defer { lock.unlock() }
            storage.append(draft)
            return NotificationRecord(
                id: draft.identifierHint ?? "generated",
                title: draft.title,
                body: draft.body,
                scheduledAt: draft.scheduledAt
            )
        }

        func cancel(id: String) throws {}

        func listScheduled() throws -> [NotificationRecord] {
            []
        }
    }

    private struct FixedDateProvider: DateProvider {
        let now: Date
    }

    private func makeTaskStore() throws -> SQLiteTaskStore {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return SQLiteTaskStore(connection: connection)
    }

    func testCompleteActionMarksTaskCompleted() throws {
        let taskStore = try makeTaskStore()
        let task = try taskStore.create(title: "Ship the release notes")
        let handler = DeadlineNotificationActionHandler(
            taskStore: taskStore,
            notificationClient: RecordingNotificationClient()
        )

        let outcome = handler.handle(
            actionIdentifier: DeadlineNotificationInteraction.completeTaskActionIdentifier,
            notificationTitle: "Deadline: Ship the release notes",
            notificationBody: "1 unfinished.",
            userInfo: [DeadlineNotificationInteraction.taskIDUserInfoKey: String(task.id)]
        )

        XCTAssertEqual(outcome, .completedTask(taskID: task.id))
        XCTAssertEqual(try taskStore.get(id: task.id).status, "completed")
    }

    func testSnoozeActionSchedulesFollowUpNotificationWithSameActionMetadata() throws {
        let taskStore = try makeTaskStore()
        let task = try taskStore.create(title: "Prepare demo")
        let client = RecordingNotificationClient()
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let handler = DeadlineNotificationActionHandler(
            taskStore: taskStore,
            notificationClient: client,
            dateProvider: FixedDateProvider(now: now)
        )
        let userInfo = [DeadlineNotificationInteraction.taskIDUserInfoKey: String(task.id)]

        let outcome = handler.handle(
            actionIdentifier: DeadlineNotificationInteraction.snoozeOneHourActionIdentifier,
            notificationTitle: "Deadline: Prepare demo",
            notificationBody: "1 unfinished.",
            userInfo: userInfo
        )

        let expectedDate = now.addingTimeInterval(DeadlineNotificationInteraction.snoozeInterval)
        guard case let .snoozed(notificationID, until) = outcome else {
            XCTFail("Expected snoozed outcome, got \(outcome).")
            return
        }
        XCTAssertEqual(until, expectedDate)
        XCTAssertTrue(notificationID.hasPrefix("solopm-snooze-\(task.id)-"))

        XCTAssertEqual(client.scheduledDrafts.count, 1)
        let draft = try XCTUnwrap(client.scheduledDrafts.first)
        XCTAssertEqual(draft.title, "Deadline: Prepare demo")
        XCTAssertEqual(draft.body, "1 unfinished.")
        XCTAssertEqual(draft.scheduledAt, DeadlineDateParser.string(from: expectedDate))
        XCTAssertEqual(draft.categoryIdentifier, DeadlineNotificationInteraction.taskCategoryIdentifier)
        XCTAssertEqual(draft.userInfo, userInfo)
        XCTAssertEqual(try taskStore.get(id: task.id).status, "open")
    }

    func testUnknownActionAndMissingTaskReferenceAreIgnored() throws {
        let taskStore = try makeTaskStore()
        let task = try taskStore.create(title: "Untouched")
        let handler = DeadlineNotificationActionHandler(
            taskStore: taskStore,
            notificationClient: RecordingNotificationClient()
        )

        XCTAssertEqual(
            handler.handle(
                actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier",
                notificationTitle: "Deadline: Untouched",
                notificationBody: nil,
                userInfo: [DeadlineNotificationInteraction.taskIDUserInfoKey: String(task.id)]
            ),
            .ignoredUnknownAction
        )
        XCTAssertEqual(
            handler.handle(
                actionIdentifier: DeadlineNotificationInteraction.completeTaskActionIdentifier,
                notificationTitle: "Deadline: Untouched",
                notificationBody: nil,
                userInfo: [:]
            ),
            .ignoredMissingTaskReference
        )
        XCTAssertEqual(try taskStore.get(id: task.id).status, "open")
    }

    func testCompleteActionForMissingTaskReportsFailure() throws {
        let handler = DeadlineNotificationActionHandler(
            taskStore: try makeTaskStore(),
            notificationClient: RecordingNotificationClient()
        )

        let outcome = handler.handle(
            actionIdentifier: DeadlineNotificationInteraction.completeTaskActionIdentifier,
            notificationTitle: "Deadline: Ghost",
            notificationBody: nil,
            userInfo: [DeadlineNotificationInteraction.taskIDUserInfoKey: "404"]
        )

        guard case .failed = outcome else {
            XCTFail("Expected failed outcome for a missing task, got \(outcome).")
            return
        }
    }

    func testSchedulerAttachesActionCategoryAndTaskReferenceForTaskItems() throws {
        let client = RecordingNotificationClient()
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: client,
            dateProvider: FixedDateProvider(now: now)
        )
        let dueAt = now.addingTimeInterval(7 * 24 * 3_600)

        let taskResult = scheduler.schedule(
            rule: DeadlineRule(target: .task(7), kind: .overdueDaily),
            item: DeadlineItem(id: 7, kind: .task, title: "Write brief", dueAt: dueAt)
        )
        XCTAssertEqual(taskResult.status, .scheduled)

        let projectResult = scheduler.schedule(
            rule: DeadlineRule(target: .project(3), kind: .overdueDaily),
            item: DeadlineItem(id: 3, kind: .project, title: "Launch", dueAt: dueAt)
        )
        XCTAssertEqual(projectResult.status, .scheduled)

        XCTAssertEqual(client.scheduledDrafts.count, 2)
        let taskDraft = try XCTUnwrap(client.scheduledDrafts.first)
        XCTAssertEqual(taskDraft.categoryIdentifier, DeadlineNotificationInteraction.taskCategoryIdentifier)
        XCTAssertEqual(taskDraft.userInfo, [DeadlineNotificationInteraction.taskIDUserInfoKey: "7"])

        let projectDraft = try XCTUnwrap(client.scheduledDrafts.last)
        XCTAssertNil(projectDraft.categoryIdentifier)
        XCTAssertTrue(projectDraft.userInfo.isEmpty)
    }
}
