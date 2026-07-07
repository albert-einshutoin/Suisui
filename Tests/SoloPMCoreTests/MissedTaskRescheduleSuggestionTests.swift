import XCTest
@testable import SoloPMCore

final class MissedTaskRescheduleSuggestionTests: XCTestCase {
    private struct FixedDateProvider: DateProvider {
        let now: Date
    }

    // Tuesday 2026-07-07T10:00:00Z
    private let now = Date(timeIntervalSince1970: 1_783_418_400)

    private func makeQueueStore() throws -> SQLiteAssistantQueueStore {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return SQLiteAssistantQueueStore(connection: connection)
    }

    private func makePlanner(queueStore: any AssistantQueueStore) -> MissedTaskRescheduleSuggestionPlanner {
        MissedTaskRescheduleSuggestionPlanner(
            queueStore: queueStore,
            dateProvider: FixedDateProvider(now: now),
            settings: AppSettings(notificationsEnabled: true, timeZoneIdentifier: "UTC")
        )
    }

    private func makeItem(
        id: Int64,
        title: String,
        reasons: [MissedTaskReviewReason]
    ) -> MissedTaskReviewItem {
        MissedTaskReviewItem(
            task: ProjectBoardTask(
                id: id,
                projectID: id * 10,
                title: title,
                detail: "",
                status: .planned,
                priority: .medium,
                dueAt: nil
            ),
            projectTitle: "Project",
            reasons: reasons,
            lastReviewedAt: nil,
            isNewlyMissed: true
        )
    }

    private func makeSummary(_ items: [MissedTaskReviewItem]) -> MissedTaskReviewSummary {
        MissedTaskReviewSummary(
            items: items,
            immediateQueue: items,
            overdueCount: items.filter { $0.reasons.contains(.overdue) }.count,
            dueTodayCount: 0,
            blockedCount: 0,
            unscheduledCount: 0,
            staleCount: items.filter { $0.reasons.contains(.stale) }.count,
            newlyMissedCount: items.count
        )
    }

    func testEnqueuesApprovalGatedRescheduleForOverdueTask() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore)
        let summary = makeSummary([makeItem(id: 7, title: "Ship release notes", reasons: [.overdue])])

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertEqual(result.enqueuedItemIDs, ["solopm-reschedule-7-2026-07-07"])
        XCTAssertNil(result.errorMessage)

        let saved = try queueStore.get(id: "solopm-reschedule-7-2026-07-07")
        XCTAssertEqual(saved.state, .waitingReview)
        XCTAssertEqual(saved.riskLevel, .write)
        XCTAssertEqual(saved.requiredCapabilities, [.tool(.taskUpdate)])
        XCTAssertEqual(saved.costPreview?.billingMode, .localOnly)

        guard case let .actionPlan(plan) = saved.payload else {
            XCTFail("Expected an action plan payload.")
            return
        }
        XCTAssertTrue(plan.requiresApproval)
        XCTAssertEqual(plan.actions.count, 1)
        let action = try XCTUnwrap(plan.actions.first)
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.arguments["id"], .number(7))
        XCTAssertEqual(action.arguments["dueAt"], .string("2026-07-08T18:00:00Z"))
        XCTAssertTrue(plan.summary.contains("Ship release notes"))
    }

    func testOnlyOverdueAndStaleTasksProduceSuggestionsAndCapAtThree() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore)
        let summary = makeSummary([
            makeItem(id: 1, title: "Overdue one", reasons: [.overdue]),
            makeItem(id: 2, title: "Blocked only", reasons: [.blocked]),
            makeItem(id: 3, title: "Stale one", reasons: [.stale]),
            makeItem(id: 4, title: "Unscheduled only", reasons: [.unscheduled]),
            makeItem(id: 5, title: "Overdue two", reasons: [.overdue]),
            makeItem(id: 6, title: "Overdue three", reasons: [.overdue])
        ])

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertEqual(result.enqueuedItemIDs.count, 3)
        XCTAssertEqual(
            result.enqueuedItemIDs,
            [
                "solopm-reschedule-1-2026-07-07",
                "solopm-reschedule-3-2026-07-07",
                "solopm-reschedule-5-2026-07-07"
            ]
        )
    }

    func testOpenSuggestionBlocksDuplicatesAcrossDays() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore)
        let summary = makeSummary([makeItem(id: 7, title: "Ship release notes", reasons: [.overdue])])

        // An earlier suggestion for the same task is still waiting for review.
        _ = try queueStore.save(
            MissedTaskRescheduleSuggestionPlanner.makeSuggestionItem(
                taskID: 7,
                taskTitle: "Ship release notes",
                reasons: [.overdue],
                day: "2026-07-06",
                rescheduledDueAt: "2026-07-07T18:00:00Z"
            )
        )

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertTrue(result.enqueuedItemIDs.isEmpty)
        XCTAssertEqual(result.skippedTaskIDs, [7])
    }

    func testResolvedSuggestionDoesNotBlockANewOne() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore)
        let summary = makeSummary([makeItem(id: 7, title: "Ship release notes", reasons: [.overdue])])

        var resolved = MissedTaskRescheduleSuggestionPlanner.makeSuggestionItem(
            taskID: 7,
            taskTitle: "Ship release notes",
            reasons: [.overdue],
            day: "2026-07-06",
            rescheduledDueAt: "2026-07-07T18:00:00Z"
        )
        resolved.state = .done
        _ = try queueStore.save(resolved)

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertEqual(result.enqueuedItemIDs, ["solopm-reschedule-7-2026-07-07"])
        XCTAssertTrue(result.skippedTaskIDs.isEmpty)
    }

    func testSuggestionSummaryRedactsSecrets() throws {
        let item = MissedTaskRescheduleSuggestionPlanner.makeSuggestionItem(
            taskID: 9,
            taskTitle: "Rotate credentials token=sk-secret today",
            reasons: [.stale],
            day: "2026-07-07",
            rescheduledDueAt: "2026-07-08T18:00:00Z"
        )

        guard case let .actionPlan(plan) = item.payload else {
            XCTFail("Expected an action plan payload.")
            return
        }
        XCTAssertFalse(plan.summary.contains("sk-secret"))
        XCTAssertFalse(item.interpretationSummary?.contains("sk-secret") ?? true)
    }
}
