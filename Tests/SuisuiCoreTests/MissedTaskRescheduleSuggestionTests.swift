import XCTest
@testable import SuisuiCore

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

    private func makePlanner(
        queueStore: any AssistantQueueStore,
        now: Date? = nil,
        avoidsWeekends: Bool = true
    ) -> MissedTaskRescheduleSuggestionPlanner {
        MissedTaskRescheduleSuggestionPlanner(
            queueStore: queueStore,
            dateProvider: FixedDateProvider(now: now ?? self.now),
            settings: AppSettings(
                notificationsEnabled: true,
                notificationPreferences: NotificationPreferences(avoidsWeekends: avoidsWeekends),
                timeZoneIdentifier: "UTC"
            )
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

        XCTAssertEqual(result.enqueuedItemIDs, ["suisui-reschedule-7-2026-07-07"])
        XCTAssertNil(result.errorMessage)

        let saved = try queueStore.get(id: "suisui-reschedule-7-2026-07-07")
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
                "suisui-reschedule-1-2026-07-07",
                "suisui-reschedule-3-2026-07-07",
                "suisui-reschedule-5-2026-07-07"
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

        XCTAssertEqual(result.enqueuedItemIDs, ["suisui-reschedule-7-2026-07-07"])
        XCTAssertTrue(result.skippedTaskIDs.isEmpty)
    }

    // Friday 2026-07-10T10:00:00Z
    private let fridayNow = Date(timeIntervalSince1970: 1_783_677_600)
    // Saturday 2026-07-11T10:00:00Z
    private let saturdayNow = Date(timeIntervalSince1970: 1_783_764_000)

    func testFridayRunSkipsWeekendAndTargetsMondayWithShiftReason() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore, now: fridayNow)
        let summary = makeSummary([makeItem(id: 7, title: "Ship release notes", reasons: [.overdue])])

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertEqual(result.enqueuedItemIDs, ["suisui-reschedule-7-2026-07-10"])
        let saved = try queueStore.get(id: "suisui-reschedule-7-2026-07-10")
        guard case let .actionPlan(plan) = saved.payload else {
            XCTFail("Expected an action plan payload.")
            return
        }
        // Tomorrow is Saturday; the target moves to Monday at the same hour.
        XCTAssertEqual(
            try XCTUnwrap(plan.actions.first).arguments["dueAt"],
            .string("2026-07-13T18:00:00Z")
        )
        XCTAssertTrue(plan.summary.contains("Monday"))
        let interpretationSummary = try XCTUnwrap(saved.interpretationSummary)
        XCTAssertTrue(interpretationSummary.contains("Monday"))
        XCTAssertTrue(interpretationSummary.contains("weekend"))
        XCTAssertTrue(saved.reviewReason.contains("Monday, skipping the weekend"))
    }

    func testSaturdayRunAlsoTargetsMonday() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore, now: saturdayNow)
        let summary = makeSummary([makeItem(id: 8, title: "Stale spec", reasons: [.stale])])

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertEqual(result.enqueuedItemIDs, ["suisui-reschedule-8-2026-07-11"])
        let saved = try queueStore.get(id: "suisui-reschedule-8-2026-07-11")
        guard case let .actionPlan(plan) = saved.payload else {
            XCTFail("Expected an action plan payload.")
            return
        }
        // Tomorrow is Sunday; the target moves to Monday at the same hour.
        XCTAssertEqual(
            try XCTUnwrap(plan.actions.first).arguments["dueAt"],
            .string("2026-07-13T18:00:00Z")
        )
        XCTAssertTrue(saved.reviewReason.contains("weekend"))
    }

    func testWeekendAvoidanceDisabledKeepsTomorrowEvenOnSaturday() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore, now: fridayNow, avoidsWeekends: false)
        let summary = makeSummary([makeItem(id: 9, title: "Ship release notes", reasons: [.overdue])])

        let result = planner.enqueueSuggestions(for: summary)

        XCTAssertEqual(result.enqueuedItemIDs, ["suisui-reschedule-9-2026-07-10"])
        let saved = try queueStore.get(id: "suisui-reschedule-9-2026-07-10")
        guard case let .actionPlan(plan) = saved.payload else {
            XCTFail("Expected an action plan payload.")
            return
        }
        XCTAssertEqual(
            try XCTUnwrap(plan.actions.first).arguments["dueAt"],
            .string("2026-07-11T18:00:00Z")
        )
        XCTAssertTrue(plan.summary.contains("tomorrow"))
        XCTAssertFalse(saved.reviewReason.contains("weekend"))
    }

    func testWeekdayRunKeepsTomorrowReasonWording() throws {
        let queueStore = try makeQueueStore()
        let planner = makePlanner(queueStore: queueStore)
        let summary = makeSummary([makeItem(id: 10, title: "Ship release notes", reasons: [.overdue])])

        _ = planner.enqueueSuggestions(for: summary)

        let saved = try queueStore.get(id: "suisui-reschedule-10-2026-07-07")
        XCTAssertEqual(
            saved.interpretationSummary,
            "\"Ship release notes\" is overdue; moving the due date to tomorrow keeps it visible."
        )
        XCTAssertEqual(
            saved.reviewReason,
            "Assistant suggestion: reschedule a overdue task to tomorrow. Nothing changes until you approve and run it."
        )
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

    // MARK: - Approve all reschedules

    private final class FailingTransitionAssistantQueueStore: AssistantQueueStore {
        struct ScriptedFailure: Error {}

        private let base: SQLiteAssistantQueueStore
        var failingTransitionID: String?

        init(base: SQLiteAssistantQueueStore) {
            self.base = base
        }

        func save(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
            try base.save(item)
        }

        func insertIfAbsent(_ item: AssistantQueueItem) throws -> AssistantQueueItem? {
            try base.insertIfAbsent(item)
        }

        func get(id: String) throws -> AssistantQueueItem {
            try base.get(id: id)
        }

        func list(filter: AssistantQueueFilter) throws -> [AssistantQueueItem] {
            try base.list(filter: filter)
        }

        func stateCounts() throws -> AssistantQueueStateCounts {
            try base.stateCounts()
        }

        func readModelSnapshot(
            filter: AssistantQueueFilter,
            receipts: [ExecutionReceipt],
            viewFilter: AssistantQueueViewFilter,
            sort: AssistantQueueSort
        ) throws -> AssistantQueueSnapshot {
            try base.readModelSnapshot(filter: filter, receipts: receipts, viewFilter: viewFilter, sort: sort)
        }

        func transition(
            id: String,
            _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
        ) throws -> AssistantQueueItem {
            if id == failingTransitionID {
                throw ScriptedFailure()
            }
            return try base.transition(id: id, transform)
        }
    }

    @MainActor
    private func makeApproveAllFixture(
        suggestionTaskIDs: [Int64]
    ) throws -> (viewModel: ProjectBoardViewModel, store: FailingTransitionAssistantQueueStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let queueStore = FailingTransitionAssistantQueueStore(
            base: SQLiteAssistantQueueStore(connection: connection)
        )
        for taskID in suggestionTaskIDs {
            _ = try queueStore.save(
                MissedTaskRescheduleSuggestionPlanner.makeSuggestionItem(
                    taskID: taskID,
                    taskTitle: "Task \(taskID)",
                    reasons: [.overdue],
                    day: "2026-07-07",
                    rescheduledDueAt: "2026-07-08T18:00:00Z"
                )
            )
        }
        let viewModel = ProjectBoardViewModel(
            store: SQLiteProjectBoardStore(connection: connection),
            assistantQueueStore: queueStore
        )
        viewModel.load()
        return (viewModel, queueStore)
    }

    @MainActor
    func testApproveAllRescheduleSuggestionsApprovesEachThroughSingleItemPath() throws {
        let fixture = try makeApproveAllFixture(suggestionTaskIDs: [1, 2, 3])
        let suggestionIDs = fixture.viewModel.openRescheduleSuggestionIDs
        XCTAssertEqual(suggestionIDs.count, 3)

        let approvedCount = fixture.viewModel.approveAllRescheduleSuggestions()

        XCTAssertEqual(approvedCount, 3)
        for suggestionID in suggestionIDs {
            XCTAssertEqual(try fixture.store.get(id: suggestionID).state, .approved)
        }
        XCTAssertTrue(fixture.viewModel.openRescheduleSuggestionIDs.isEmpty)
        XCTAssertNil(fixture.viewModel.errorMessage)
        XCTAssertEqual(
            fixture.viewModel.integrationStatusMessage,
            "Approved 3 reschedule suggestions."
        )
        XCTAssertFalse(fixture.viewModel.isApprovingAllRescheduleSuggestions)
    }

    @MainActor
    func testApproveAllStopsAtFirstFailureAndKeepsRemainingWaitingReview() throws {
        let fixture = try makeApproveAllFixture(suggestionTaskIDs: [1, 2, 3])
        let suggestionIDs = fixture.viewModel.openRescheduleSuggestionIDs
        XCTAssertEqual(suggestionIDs.count, 3)
        fixture.store.failingTransitionID = suggestionIDs[1]

        let approvedCount = fixture.viewModel.approveAllRescheduleSuggestions()

        XCTAssertEqual(approvedCount, 1)
        XCTAssertEqual(try fixture.store.get(id: suggestionIDs[0]).state, .approved)
        // The failed item and every item after it stay reviewable.
        XCTAssertEqual(try fixture.store.get(id: suggestionIDs[1]).state, .waitingReview)
        XCTAssertEqual(try fixture.store.get(id: suggestionIDs[2]).state, .waitingReview)
        XCTAssertNotNil(fixture.viewModel.errorMessage)
        XCTAssertNil(fixture.viewModel.integrationStatusMessage)
        XCTAssertEqual(
            Set(fixture.viewModel.openRescheduleSuggestionIDs),
            Set([suggestionIDs[1], suggestionIDs[2]])
        )
        XCTAssertFalse(fixture.viewModel.isApprovingAllRescheduleSuggestions)
    }

    @MainActor
    func testOpenRescheduleSuggestionIDsIgnoreNonRescheduleAndNonWaitingItems() throws {
        let fixture = try makeApproveAllFixture(suggestionTaskIDs: [1, 2])
        var resolved = MissedTaskRescheduleSuggestionPlanner.makeSuggestionItem(
            taskID: 3,
            taskTitle: "Task 3",
            reasons: [.overdue],
            day: "2026-07-06",
            rescheduledDueAt: "2026-07-07T18:00:00Z"
        )
        resolved.state = .done
        _ = try fixture.store.save(resolved)
        fixture.viewModel.load()

        XCTAssertEqual(fixture.viewModel.openRescheduleSuggestionIDs.count, 2)
        XCTAssertFalse(
            fixture.viewModel.openRescheduleSuggestionIDs.contains("suisui-reschedule-3-2026-07-06")
        )
    }
}
