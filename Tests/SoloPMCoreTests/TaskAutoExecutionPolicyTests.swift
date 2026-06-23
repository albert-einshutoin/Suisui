import XCTest
@testable import SoloPMCore

final class TaskAutoExecutionPolicyTests: XCTestCase {
    func testPlannerRanksOverdueAndHighPriorityTasksBeforeFutureWork() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(tasks: [
                makeTask(id: 1, title: "Low future", priority: .low, dueAt: "2026-06-30T09:00:00Z"),
                makeTask(id: 2, title: "High due today", priority: .high, dueAt: "2026-06-22T18:00:00Z"),
                makeTask(id: 3, title: "Medium overdue", priority: .medium, dueAt: "2026-06-20T18:00:00Z"),
                makeTask(id: 4, title: "Done overdue", status: .done, priority: .high, dueAt: "2026-06-19T18:00:00Z"),
                makeTask(id: 5, title: "High overdue", priority: .high, dueAt: "2026-06-21T18:00:00Z")
            ])
        ])
        let settings = TaskAutoExecutionSettings(
            isEnabled: true,
            mode: .reviewOnly,
            cadence: .hourly,
            maxTasksPerRun: 3,
            dailyLLMCallLimit: 6,
            lookaheadHours: 48
        )

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: settings,
            history: .empty,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .readyForReview)
        XCTAssertEqual(decision.selectedTasks.map(\.title), ["High overdue", "Medium overdue", "High due today"])
        XCTAssertTrue(decision.requiresUserApproval)
        XCTAssertFalse(decision.allowsDirectExecution)
        XCTAssertEqual(decision.llmCallBudgetRemaining, 6)
    }

    func testPlannerKeepsHighPriorityNoDueWorkAheadOfLowerPriorityFutureWork() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(tasks: [
                makeTask(id: 1, title: "Low within lookahead", priority: .low, dueAt: "2026-06-23T08:00:00Z"),
                makeTask(id: 2, title: "High without due date", priority: .high),
                makeTask(id: 3, title: "Medium within lookahead", priority: .medium, dueAt: "2026-06-23T08:00:00Z"),
                makeTask(id: 4, title: "High within lookahead", priority: .high, dueAt: "2026-06-23T08:00:00Z"),
                makeTask(id: 5, title: "High outside lookahead", priority: .high, dueAt: "2026-06-25T09:01:00Z")
            ])
        ])

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .hourly,
                maxTasksPerRun: 10,
                lookaheadHours: 48
            ),
            history: .empty,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .readyForReview)
        XCTAssertEqual(decision.selectedTasks.map(\.title), [
            "High within lookahead",
            "High without due date",
            "Medium within lookahead",
            "Low within lookahead"
        ])
        XCTAssertFalse(decision.selectedTasks.contains { $0.title == "High outside lookahead" })
    }

    func testPlannerIgnoresCompletedAndArchivedProjectsEvenWhenTasksLookUrgent() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(
                title: "Completed project",
                status: "completed",
                tasks: [
                    makeTask(id: 1, title: "Completed project overdue", priority: .high, dueAt: "2026-06-20T18:00:00Z")
                ]
            ),
            makeProject(
                title: "Archived project",
                status: "archived",
                tasks: [
                    makeTask(id: 2, title: "Archived project overdue", priority: .high, dueAt: "2026-06-20T18:00:00Z")
                ]
            ),
            makeProject(
                title: "Active project",
                tasks: [
                    makeTask(id: 3, title: "Active project review", priority: .medium, dueAt: "2026-06-22T18:00:00Z")
                ]
            )
        ])

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly, maxTasksPerRun: 10),
            history: .empty,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .readyForReview)
        XCTAssertEqual(decision.selectedTasks.map(\.title), ["Active project review"])
    }

    func testPlannerThrottlesByCadenceBeforeCallingLLM() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(tasks: [
                makeTask(id: 1, title: "High due today", priority: .high, dueAt: "2026-06-22T18:00:00Z")
            ])
        ])
        let history = TaskAutoExecutionHistory(
            lastRunAt: try isoDate("2026-06-22T08:30:00Z"),
            llmCallsToday: 0
        )

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly),
            history: history,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .throttled)
        XCTAssertEqual(decision.selectedTasks, [])
        XCTAssertFalse(decision.shouldCallLLM)
    }

    func testPlannerAllowsUrgentOverdueWorkAfterUrgentCooldownEvenWhenDailyCadenceHasNotElapsed() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(tasks: [
                makeTask(id: 1, title: "High overdue release fix", priority: .high, dueAt: "2026-06-21T18:00:00Z"),
                makeTask(id: 2, title: "Medium future cleanup", priority: .medium, dueAt: "2026-06-24T18:00:00Z")
            ])
        ])
        let history = TaskAutoExecutionHistory(
            lastRunAt: try isoDate("2026-06-22T07:00:00Z"),
            llmCallsToday: 1
        )

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .daily,
                maxTasksPerRun: 3,
                dailyLLMCallLimit: 4,
                lookaheadHours: 72,
                urgentReviewCooldownMinutes: 30
            ),
            history: history,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .readyForReview)
        XCTAssertEqual(decision.selectedTasks.map(\.title), ["High overdue release fix"])
        XCTAssertTrue(decision.shouldCallLLM)
        XCTAssertEqual(decision.llmCallBudgetRemaining, 3)
    }

    func testPlannerKeepsUrgentWorkThrottledInsideUrgentCooldown() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(tasks: [
                makeTask(id: 1, title: "High overdue release fix", priority: .high, dueAt: "2026-06-21T18:00:00Z")
            ])
        ])
        let history = TaskAutoExecutionHistory(
            lastRunAt: try isoDate("2026-06-22T08:45:00Z"),
            llmCallsToday: 1
        )

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: .init(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .daily,
                dailyLLMCallLimit: 4,
                urgentReviewCooldownMinutes: 30
            ),
            history: history,
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .throttled)
        XCTAssertEqual(decision.selectedTasks, [])
        XCTAssertEqual(decision.reason, "Urgent task automation cooldown has not elapsed.")
        XCTAssertFalse(decision.shouldCallLLM)
    }

    func testPlannerStopsWhenDailyLLMBudgetIsExhausted() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(tasks: [
                makeTask(id: 1, title: "High due today", priority: .high, dueAt: "2026-06-22T18:00:00Z")
            ])
        ])

        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly, dailyLLMCallLimit: 2),
            history: .init(lastRunAt: nil, llmCallsToday: 2),
            referenceDate: referenceDate,
            calendar: utcCalendar()
        )

        XCTAssertEqual(decision.status, .budgetExhausted)
        XCTAssertFalse(decision.shouldCallLLM)
        XCTAssertEqual(decision.reason, "Daily LLM automation budget is exhausted.")
    }

    func testPlanningRequestIsReviewOnlyAndCarriesTaskPriorityDueDateAndDetail() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let task = makeTask(
            id: 7,
            title: "Write public alpha notes",
            detail: "Summarize release blockers without exposing secrets.",
            priority: .high,
            dueAt: "2026-06-22T18:00:00Z"
        )
        let decision = TaskAutoExecutionDecision(
            status: .readyForReview,
            selectedTasks: [task],
            reason: "High priority work is due today.",
            llmCallBudgetRemaining: 3,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )

        let request = try TaskAutoExecutionPlanningRequestBuilder().makePlanningRequest(
            decision: decision,
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly),
            referenceDate: referenceDate,
            timeZoneIdentifier: "UTC"
        )

        XCTAssertTrue(request.userInput.contains("review-only"))
        XCTAssertTrue(request.userInput.contains("Write public alpha notes"))
        XCTAssertTrue(request.userInput.contains("high"))
        XCTAssertTrue(request.userInput.contains("2026-06-22T18:00:00Z"))
        XCTAssertTrue(request.userInput.contains("Summarize release blockers"))
        XCTAssertTrue(request.availableTools.contains(.taskUpdate))
        XCTAssertFalse(request.availableTools.contains(.projectDelete))
        XCTAssertFalse(request.availableTools.contains(.taskDelete))
    }

    func testPlanningRequestExplainsWhyEachTaskWasSelected() throws {
        let referenceDate = try isoDate("2026-06-22T09:00:00Z")
        let overdue = makeTask(id: 11, title: "Patch stale release evidence", priority: .high, dueAt: "2026-06-21T18:00:00Z")
        let dueToday = makeTask(id: 12, title: "Review VoiceOver notes", priority: .medium, dueAt: "2026-06-22T18:00:00Z")
        let future = makeTask(id: 13, title: "Prepare benchmark worksheet", priority: .low, dueAt: "2026-06-24T09:00:00Z")
        let highNoDue = makeTask(id: 14, title: "Investigate blocked packaging", priority: .high)
        let decision = TaskAutoExecutionDecision(
            status: .readyForReview,
            selectedTasks: [overdue, dueToday, future, highNoDue],
            reason: "Priority and due date policy selected review candidates.",
            llmCallBudgetRemaining: 4,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )

        let request = try TaskAutoExecutionPlanningRequestBuilder().makePlanningRequest(
            decision: decision,
            settings: .init(isEnabled: true, mode: .reviewOnly, cadence: .hourly, lookaheadHours: 72),
            referenceDate: referenceDate,
            timeZoneIdentifier: "UTC"
        )

        XCTAssertTrue(request.userInput.contains("selectionReason=overdue by 1 day; priority=high"))
        XCTAssertTrue(request.userInput.contains("selectionReason=due today; priority=medium"))
        XCTAssertTrue(request.userInput.contains("selectionReason=due within 48 hours; priority=low"))
        XCTAssertTrue(request.userInput.contains("selectionReason=high priority without due date; priority=high"))
        XCTAssertTrue(request.userInput.contains("Review these reasons before proposing any task update."))
    }

    func testAppSettingsPersistTaskAutoExecutionControls() throws {
        let suiteName = "SoloPM.TaskAutoExecutionSettings.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        let settings = AppSettings(
            taskAutoExecution: TaskAutoExecutionSettings(
                isEnabled: true,
                mode: .reviewOnly,
                cadence: .daily,
                maxTasksPerRun: 4,
                dailyLLMCallLimit: 5,
                lookaheadHours: 72
            )
        )

        try store.save(settings)

        XCTAssertEqual(try store.load().taskAutoExecution, settings.taskAutoExecution)
        XCTAssertTrue(try store.load().validate().isEmpty)
    }

    func testTaskAutoExecutionSettingsDecodeLegacyPayloadWithDefaultUrgentCooldown() throws {
        let data = Data(
            """
            {
              "isEnabled": true,
              "mode": "reviewOnly",
              "cadence": "daily",
              "maxTasksPerRun": 3,
              "dailyLLMCallLimit": 6,
              "lookaheadHours": 48
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(TaskAutoExecutionSettings.self, from: data)

        XCTAssertEqual(settings.urgentReviewCooldownMinutes, 60)
        XCTAssertEqual(settings.normalized.urgentReviewCooldownMinutes, 60)
        XCTAssertTrue(settings.validationIssues().isEmpty)
    }

    private func makeProject(
        title: String = "Launch",
        status: String = "active",
        tasks: [ProjectBoardTask]
    ) -> ProjectBoardProject {
        ProjectBoardProject(
            id: 1,
            title: title,
            status: status,
            subtitle: "\(tasks.count) tasks",
            columns: ProjectTaskStatus.allCases.map { status in
                ProjectBoardColumn(status: status, tasks: tasks.filter { $0.status == status })
            }
        )
    }

    private func makeTask(
        id: Int64,
        title: String,
        detail: String = "",
        status: ProjectTaskStatus = .planned,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: 1,
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueAt
        )
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
