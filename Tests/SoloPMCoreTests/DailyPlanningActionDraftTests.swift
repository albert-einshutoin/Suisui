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
}
