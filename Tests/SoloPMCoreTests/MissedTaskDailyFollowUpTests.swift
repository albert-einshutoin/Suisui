import XCTest
@testable import SoloPMCore

final class MissedTaskDailyFollowUpTests: XCTestCase {
    func testSchedulerSchedulesOneCountOnlyFollowUpAndRecordsDay() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        let notificationClient = InMemoryNotificationClient()
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )

        let result = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())
        let scheduled = try notificationClient.listScheduled()

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.day, "2026-06-30")
        XCTAssertEqual(result.missedCount, 3)
        XCTAssertEqual(result.notificationID, "missed-task-review-2026-06-30")
        XCTAssertEqual(result.message, "Scheduled missed task review follow-up.")
        XCTAssertEqual(try stateStore.lastNotifiedDay(), "2026-06-30")
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.id, "missed-task-review-2026-06-30")
        XCTAssertEqual(scheduled.first?.title, "SoloPM Catch Up")
        XCTAssertEqual(scheduled.first?.scheduledAt, "2026-06-30T09:00:00Z")
        XCTAssertEqual(
            scheduled.first?.body,
            "3 tasks need review. Overdue: 1, due today: 1, blocked: 1, unscheduled: 1, stale: 1."
        )
        XCTAssertFalse((scheduled.first?.body ?? "").contains("sk-secret"))
        XCTAssertFalse((scheduled.first?.body ?? "").contains("/Users/alice/customer.md"))
        XCTAssertFalse((scheduled.first?.body ?? "").contains("Sensitive customer"))
    }

    func testSchedulerSkipsWhenAlreadyNotifiedToday() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        try stateStore.recordNotification(day: "2026-06-30", at: try Date.iso8601("2026-06-30T08:00:00Z"))
        let notificationClient = InMemoryNotificationClient()
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )

        let result = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())

        XCTAssertEqual(result.status, .skippedAlreadyNotifiedToday)
        XCTAssertEqual(result.day, "2026-06-30")
        XCTAssertEqual(result.missedCount, 3)
        XCTAssertEqual(result.message, "Missed task review follow-up already ran today.")
        XCTAssertEqual(try notificationClient.listScheduled(), [])
    }

    func testSchedulerSkipsExistingPendingNotificationAndRepairsNotificationDay() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        let notificationClient = InMemoryNotificationClient()
        _ = try notificationClient.schedule(NotificationDraft(
            title: "SoloPM Catch Up",
            body: "Already pending.",
            scheduledAt: "2026-06-30T08:00:00Z",
            identifierHint: "missed-task-review-2026-06-30"
        ))
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )

        let result = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())

        XCTAssertEqual(result.status, .skippedAlreadyScheduled)
        XCTAssertEqual(result.notificationID, "missed-task-review-2026-06-30")
        XCTAssertEqual(result.message, "Missed task review follow-up is already scheduled.")
        XCTAssertEqual(try stateStore.lastNotifiedDay(), "2026-06-30")
        XCTAssertEqual(try notificationClient.listScheduled().count, 1)
    }

    func testSchedulerDoesNotDuplicateAfterRecordNotificationFailure() throws {
        let stateStore = RecordFailingMissedTaskReviewStateStore()
        let notificationClient = InMemoryNotificationClient()
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )

        let first = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())
        let second = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())

        XCTAssertEqual(first.status, .failed)
        XCTAssertEqual(second.status, .failed)
        XCTAssertEqual(try notificationClient.listScheduled().count, 1)
        XCTAssertEqual(stateStore.recordNotificationCallCount, 2)
    }

    func testSchedulerSkipsWhenNotificationsAreDisabled() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        let notificationClient = InMemoryNotificationClient()
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: false, timeZoneIdentifier: "UTC")
        )

        let result = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())

        XCTAssertEqual(result.status, .skippedNotificationsDisabled)
        XCTAssertEqual(result.message, "Missed task review follow-up is disabled.")
        XCTAssertNil(try stateStore.lastNotifiedDay())
        XCTAssertEqual(try notificationClient.listScheduled(), [])
    }

    func testSchedulerSkipsWhenImmediateQueueIsEmpty() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        let notificationClient = InMemoryNotificationClient()
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )

        let result = scheduler.scheduleIfNeeded(summary: .empty)

        XCTAssertEqual(result.status, .skippedNoMissedTasks)
        XCTAssertEqual(result.missedCount, 0)
        XCTAssertNil(try stateStore.lastNotifiedDay())
        XCTAssertEqual(try notificationClient.listScheduled(), [])
    }

    func testSchedulerDoesNotRecordDayWhenNotificationFailsAndRedactsMessage() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        let secret = "sk-missed-task-secret"
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: FailingMissedTaskNotificationClient(
                error: ToolClientError.invalidRequest("token=\(secret) could not schedule")
            ),
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T09:00:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )

        let result = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "token=[REDACTED_SECRET] could not schedule")
        XCTAssertFalse(result.message.contains(secret))
        XCTAssertNil(try stateStore.lastNotifiedDay())
    }

    func testSchedulerUsesConfiguredTimeZoneForNotificationDay() throws {
        let stateStore = VolatileMissedTaskReviewStateStore()
        let notificationClient = InMemoryNotificationClient()
        let scheduler = MissedTaskDailyFollowUpScheduler(
            stateStore: stateStore,
            notificationClient: notificationClient,
            dateProvider: FixedMissedTaskDateProvider(now: try Date.iso8601("2026-06-30T15:30:00Z")),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "Asia/Tokyo")
        )

        let result = scheduler.scheduleIfNeeded(summary: makeSummaryWithSensitiveTaskContent())

        XCTAssertEqual(result.status, .scheduled)
        XCTAssertEqual(result.day, "2026-07-01")
        XCTAssertEqual(result.notificationID, "missed-task-review-2026-07-01")
        XCTAssertEqual(try stateStore.lastNotifiedDay(), "2026-07-01")
    }
}

private func makeSummaryWithSensitiveTaskContent() -> MissedTaskReviewSummary {
    let overdue = makeMissedTaskReviewItem(
        id: 1,
        title: "Sensitive customer escalation sk-secret",
        detail: "Read /Users/alice/customer.md before replying.",
        reasons: [.overdue],
        projectTitle: "Customer files"
    )
    let blocked = makeMissedTaskReviewItem(
        id: 2,
        title: "Blocked API token sk-secret",
        detail: "Contains token=sk-secret",
        reasons: [.dueToday, .blocked],
        projectTitle: "Launch"
    )
    let stale = makeMissedTaskReviewItem(
        id: 3,
        title: "Draft from local path",
        detail: "Source /Users/alice/customer.md",
        reasons: [.unscheduled, .stale],
        projectTitle: "Docs"
    )
    return MissedTaskReviewSummary(
        items: [overdue, blocked, stale],
        immediateQueue: [overdue, blocked, stale],
        overdueCount: 1,
        dueTodayCount: 1,
        blockedCount: 1,
        unscheduledCount: 1,
        staleCount: 1,
        newlyMissedCount: 3
    )
}

private func makeMissedTaskReviewItem(
    id: Int64,
    title: String,
    detail: String,
    reasons: [MissedTaskReviewReason],
    projectTitle: String
) -> MissedTaskReviewItem {
    MissedTaskReviewItem(
        task: ProjectBoardTask(
            id: id,
            projectID: id * 10,
            title: title,
            detail: detail,
            status: .planned,
            priority: .medium,
            dueAt: nil
        ),
        projectTitle: projectTitle,
        reasons: reasons,
        lastReviewedAt: nil,
        isNewlyMissed: true
    )
}

private struct FixedMissedTaskDateProvider: DateProvider {
    let now: Date
}

private struct FailingMissedTaskNotificationClient: NotificationClient {
    let error: Error

    func schedule(_ draft: NotificationDraft) throws -> NotificationRecord {
        throw error
    }

    func cancel(id: String) throws {
        throw error
    }

    func listScheduled() throws -> [NotificationRecord] {
        []
    }
}

private final class RecordFailingMissedTaskReviewStateStore: MissedTaskReviewStateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var recordCallCount = 0

    var recordNotificationCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordCallCount
    }

    func lastReviewedAt(taskID: Int64) throws -> Date? {
        nil
    }

    func markReviewed(taskID: Int64, at date: Date) throws {}

    func lastNotifiedDay() throws -> String? {
        nil
    }

    func recordNotification(day: String, at date: Date) throws {
        lock.lock()
        recordCallCount += 1
        lock.unlock()
        throw ToolClientError.invalidRequest("token=sk-record-failure could not persist")
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
