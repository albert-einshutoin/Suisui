import XCTest
@testable import SoloPMCore

final class DailyPlanningActionDraftTests: XCTestCase {
    func testBuildsStartRecommendedDraftAsReviewableTaskUpdate() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let task = projectTask(
            id: 42,
            title: "Clear billing blocker",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        )
        let review = dailyReview(task: task, referenceDate: referenceDate, calendar: calendar)

        let draft = try XCTUnwrap(DailyPlanningActionDraftBuilder.makeDraft(
            kind: .startRecommended,
            review: review,
            task: task,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(draft.id, "daily-planning:2026-06-30:startRecommended:task:42")
        XCTAssertEqual(draft.queueReason, "Daily Planning Review suggested starting Clear billing blocker.")
        XCTAssertEqual(draft.actionPlan.requiresApproval, true)
        XCTAssertEqual(draft.actionPlan.riskLevel, .write)
        XCTAssertTrue(ActionPlanValidator().validate(draft.actionPlan).isValid)
        XCTAssertEqual(draft.actionPlan.actions.count, 1)
        let action = try XCTUnwrap(draft.actionPlan.actions.first)
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.riskLevel, .write)
        XCTAssertEqual(action.arguments["id"], .number(42))
        XCTAssertEqual(action.arguments["status"], .string(ProjectTaskStatus.inProgress.rawValue))
        assertOnlyLocalTaskTools(draft.actionPlan)
    }

    func testBuildsDeferRecommendedDraftForTomorrowWithoutCalendarWrite() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let task = projectTask(
            id: 43,
            title: "Send status draft",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-29"
        )
        let review = dailyReview(task: task, referenceDate: referenceDate, calendar: calendar)

        let draft = try XCTUnwrap(DailyPlanningActionDraftBuilder.makeDraft(
            kind: .deferRecommendedToTomorrow,
            review: review,
            task: task,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(draft.id, "daily-planning:2026-06-30:deferRecommendedToTomorrow:task:43")
        XCTAssertEqual(draft.queueReason, "Daily Planning Review suggested deferring Send status draft to tomorrow.")
        XCTAssertTrue(ActionPlanValidator().validate(draft.actionPlan).isValid)
        let action = try XCTUnwrap(draft.actionPlan.actions.first)
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.arguments["id"], .number(43))
        XCTAssertEqual(action.arguments["dueAt"], .string("2026-07-01"))
        assertOnlyLocalTaskTools(draft.actionPlan)
    }

    func testBuildsMoveRecommendedDueDateToTodayDraftWithoutCalendarWrite() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let task = projectTask(
            id: 44,
            title: "Review launch notes",
            status: .planned,
            priority: .high,
            dueAt: "2026-07-03"
        )
        let review = dailyReview(task: task, referenceDate: referenceDate, calendar: calendar)

        let draft = try XCTUnwrap(DailyPlanningActionDraftBuilder.makeDraft(
            kind: .moveRecommendedDueDateToToday,
            review: review,
            task: task,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(draft.id, "daily-planning:2026-06-30:moveRecommendedDueDateToToday:task:44")
        XCTAssertEqual(draft.queueReason, "Daily Planning Review suggested moving Review launch notes due date to today.")
        XCTAssertEqual(draft.actionPlan.requiresApproval, true)
        XCTAssertEqual(draft.actionPlan.riskLevel, .write)
        XCTAssertTrue(ActionPlanValidator().validate(draft.actionPlan).isValid)
        XCTAssertEqual(draft.actionPlan.actions.count, 1)
        let action = try XCTUnwrap(draft.actionPlan.actions.first)
        XCTAssertEqual(action.tool, .taskUpdate)
        XCTAssertEqual(action.riskLevel, .write)
        XCTAssertEqual(action.arguments["id"], .number(44))
        XCTAssertEqual(action.arguments["dueAt"], .string("2026-06-30"))
        assertOnlyLocalTaskTools(draft.actionPlan)
    }

    func testBuildsSplitRecommendedDraftAsReviewableTaskCreatePair() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let task = projectTask(
            id: 46,
            title: "Prepare launch report",
            status: .planned,
            priority: .high,
            dueAt: "2026-07-02"
        )
        let review = dailyReview(task: task, referenceDate: referenceDate, calendar: calendar)

        let draft = try XCTUnwrap(DailyPlanningActionDraftBuilder.makeDraft(
            kind: .splitRecommendedTask,
            review: review,
            task: task,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertEqual(draft.id, "daily-planning:2026-06-30:splitRecommendedTask:task:46")
        XCTAssertEqual(draft.queueReason, "Daily Planning Review suggested splitting Prepare launch report into reviewable follow-up tasks.")
        XCTAssertEqual(draft.actionPlan.requiresApproval, true)
        XCTAssertEqual(draft.actionPlan.riskLevel, .write)
        XCTAssertTrue(ActionPlanValidator().validate(draft.actionPlan).isValid)
        XCTAssertEqual(draft.actionPlan.actions.count, 2)
        let first = try XCTUnwrap(draft.actionPlan.actions.first)
        let second = try XCTUnwrap(draft.actionPlan.actions.dropFirst().first)
        XCTAssertEqual(first.tool, .taskCreate)
        XCTAssertEqual(second.tool, .taskCreate)
        XCTAssertEqual(first.arguments["title"], .string("Prepare launch report - Define next slice"))
        XCTAssertEqual(second.arguments["title"], .string("Prepare launch report - Complete remaining work"))
        for action in draft.actionPlan.actions {
            XCTAssertEqual(action.riskLevel, .write)
            XCTAssertEqual(action.arguments["projectId"], .number(7))
            XCTAssertEqual(action.arguments["priority"], .string(ProjectTaskPriority.high.rawValue))
            XCTAssertEqual(action.arguments["dueAt"], .string("2026-07-02"))
            XCTAssertEqual(action.arguments["sourceCommand"], .string("Daily Planning Review split from task 46"))
        }
        assertOnlyLocalTaskCreateTools(draft.actionPlan)
    }

    func testDailyPlanningDraftRedactsSecretsAndLocalPathsFromDurablePlanFields() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let task = projectTask(
            id: 45,
            title: "Review file:///Users/shutoide/Private /var/tmp/build ~/vault token=task-secret",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-29"
        )
        var review = dailyReview(task: task, referenceDate: referenceDate, calendar: calendar)
        review.sourceTranscript = "今日のレビュー token=voice-secret file:///Users/shutoide/Private /var/tmp/build ~/vault"

        let draft = try XCTUnwrap(DailyPlanningActionDraftBuilder.makeDraft(
            kind: .moveRecommendedDueDateToToday,
            review: review,
            task: task,
            referenceDate: referenceDate,
            calendar: calendar
        ))

        XCTAssertTrue(draft.actionPlan.userInput.contains("[REDACTED_SECRET]"))
        XCTAssertTrue(draft.actionPlan.userInput.contains("[REDACTED_LOCAL_PATH]"))
        XCTAssertFalse(draft.actionPlan.userInput.contains("voice-secret"))
        XCTAssertFalse(draft.actionPlan.userInput.contains("/Users/shutoide"))
        XCTAssertFalse(draft.actionPlan.userInput.contains("file:///Users"))
        XCTAssertFalse(draft.actionPlan.userInput.contains("/var/tmp"))
        XCTAssertFalse(draft.actionPlan.userInput.contains("~/vault"))
        XCTAssertTrue(draft.actionPlan.summary.contains("[REDACTED_LOCAL_PATH]"))
        XCTAssertTrue(draft.queueReason.contains("[REDACTED_LOCAL_PATH]"))
        XCTAssertFalse(draft.actionPlan.summary.contains("task-secret"))
        XCTAssertFalse(draft.actionPlan.summary.contains("/Users/shutoide"))
        XCTAssertFalse(draft.actionPlan.summary.contains("file:///Users"))
        XCTAssertFalse(draft.actionPlan.summary.contains("/var/tmp"))
        XCTAssertFalse(draft.actionPlan.summary.contains("~/vault"))
        XCTAssertFalse(draft.queueReason.contains("task-secret"))
        XCTAssertFalse(draft.queueReason.contains("/Users/shutoide"))
        XCTAssertFalse(draft.queueReason.contains("file:///Users"))
        XCTAssertFalse(draft.queueReason.contains("/var/tmp"))
        XCTAssertFalse(draft.queueReason.contains("~/vault"))
    }

    func testReturnsNilWhenReviewHasNoRecommendedTask() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let review = DailyPlanningReview(
            sourceTranscript: "今日やることを確認して",
            phase: .morning,
            requestedMinutes: nil,
            headline: "Morning daily planning review",
            spokenSummary: "No work.",
            overdueCount: 0,
            dueTodayCount: 0,
            inboxUntriagedCount: 0,
            recommendedTaskID: nil,
            focusItems: [],
            scheduleBlocks: []
        )

        let draft = DailyPlanningActionDraftBuilder.makeDraft(
            kind: .startRecommended,
            review: review,
            task: nil,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertNil(draft)
    }

    private func dailyReview(
        task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar
    ) -> DailyPlanningReview {
        DailyPlanningReviewBuilder.review(
            transcript: "今日やることを確認して",
            plan: TodayWorkflowPlan(
                tasks: [task],
                overdueCount: 1,
                dueTodayCount: 0,
                recommendedTask: task,
                recommendationReason: "Overdue work should move first.",
                timeBlocks: [TodayTimeBlock(label: "09:30-10:00", task: task)]
            ),
            workload: DailyWorkloadOverview(days: [], unscheduledTasks: [], inboxUntriagedCount: 0),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private func projectTask(
        id: Int64,
        title: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?
    ) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: 7,
            title: title,
            detail: "",
            status: status,
            priority: priority,
            dueAt: dueAt
        )
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func assertOnlyLocalTaskTools(_ plan: ActionPlan, file: StaticString = #filePath, line: UInt = #line) {
        let tools = Set(plan.actions.map(\.tool))
        XCTAssertEqual(tools, [.taskUpdate], file: file, line: line)
        XCTAssertFalse(tools.contains { tool in
            switch tool.actionType {
            case .calendar, .reminder, .notification, .mailDraft, .filesystem, .developer:
                return true
            case .project, .task, .knowledgeFrame:
                return false
            }
        }, file: file, line: line)
    }

    private func assertOnlyLocalTaskCreateTools(_ plan: ActionPlan, file: StaticString = #filePath, line: UInt = #line) {
        let tools = Set(plan.actions.map(\.tool))
        XCTAssertEqual(tools, [.taskCreate], file: file, line: line)
        XCTAssertFalse(tools.contains { tool in
            switch tool.actionType {
            case .calendar, .reminder, .notification, .mailDraft, .filesystem, .developer:
                return true
            case .project, .task, .knowledgeFrame:
                return false
            }
        }, file: file, line: line)
    }
}
