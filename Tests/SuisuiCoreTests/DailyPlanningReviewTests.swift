import XCTest
@testable import SuisuiCore

final class DailyPlanningReviewTests: XCTestCase {
    func testBuildsMorningReviewWithNinetyMinuteFocusLimit() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T09:10:00Z"))
        let overdue = task(id: 1, title: "Clear billing blocker", status: .blocked, priority: .high, dueAt: "2026-06-29")
        let dueToday = task(id: 2, title: "Draft release checklist", priority: .medium, dueAt: "2026-06-30")
        let lowerPriority = task(id: 3, title: "Refine screenshots", priority: .low, dueAt: "2026-06-30")
        let extra = task(id: 4, title: "Stretch task", priority: .low, dueAt: "2026-06-30")
        let plan = TodayWorkflowPlan(
            tasks: [overdue, dueToday, lowerPriority, extra],
            overdueCount: 1,
            dueTodayCount: 3,
            recommendedTask: overdue,
            recommendationReason: "Overdue high-priority work should be cleared first.",
            timeBlocks: [
                TodayTimeBlock(label: "09:30-10:00", task: overdue),
                TodayTimeBlock(label: "10:00-10:30", task: dueToday),
                TodayTimeBlock(label: "10:30-11:00", task: lowerPriority),
                TodayTimeBlock(label: "11:00-11:30", task: extra)
            ]
        )
        let workload = DailyWorkloadOverview(
            days: [],
            unscheduledTasks: [extra],
            inboxUntriagedCount: 2
        )

        let review = DailyPlanningReviewBuilder.review(
            transcript: "今から90分で今日やることを3つに絞って",
            plan: plan,
            workload: workload,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(review.phase, .morning)
        XCTAssertEqual(review.requestedMinutes, 90)
        XCTAssertEqual(review.overdueCount, 1)
        XCTAssertEqual(review.dueTodayCount, 3)
        XCTAssertEqual(review.inboxUntriagedCount, 2)
        XCTAssertEqual(review.focusItems.map(\.taskID), [1, 2, 3])
        XCTAssertEqual(review.scheduleBlocks.map(\.label), ["09:30-10:00", "10:00-10:30", "10:30-11:00"])
        XCTAssertEqual(review.reviewBoundary, .proposalOnly)
        XCTAssertTrue(review.spokenSummary.contains("1 overdue"))
        XCTAssertTrue(review.spokenSummary.contains("2 Inbox"))
    }

    func testBuildsEveningReviewWithoutOverdueWork() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T19:20:00Z"))
        let dueToday = task(id: 10, title: "Send status draft", priority: .medium, dueAt: "2026-06-30")
        let plan = TodayWorkflowPlan(
            tasks: [dueToday],
            overdueCount: 0,
            dueTodayCount: 1,
            recommendedTask: dueToday,
            recommendationReason: "Earliest due task keeps today on track.",
            timeBlocks: [TodayTimeBlock(label: "19:30-20:00", task: dueToday)]
        )
        let workload = DailyWorkloadOverview(days: [], unscheduledTasks: [], inboxUntriagedCount: 0)

        let review = DailyPlanningReviewBuilder.review(
            transcript: "What should I finish tonight?",
            plan: plan,
            workload: workload,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(review.phase, .evening)
        XCTAssertNil(review.requestedMinutes)
        XCTAssertEqual(review.focusItems.map(\.title), ["Send status draft"])
        XCTAssertTrue(review.headline.contains("Evening"))
        XCTAssertTrue(review.spokenSummary.contains("No overdue work"))
    }

    func testBuildsMiddayReviewPrioritizingOverduePrompt() throws {
        let calendar = fixedCalendar()
        let referenceDate = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T13:15:00Z"))
        let overdue = task(id: 20, title: "Unblock account migration", status: .blocked, priority: .high, dueAt: "2026-06-28")
        let dueToday = task(id: 21, title: "Prepare team handoff", priority: .medium, dueAt: "2026-06-30")
        let plan = TodayWorkflowPlan(
            tasks: [overdue, dueToday],
            overdueCount: 1,
            dueTodayCount: 1,
            recommendedTask: overdue,
            recommendationReason: "Overdue blocked work is the next constraint.",
            timeBlocks: [
                TodayTimeBlock(label: "13:30-14:00", task: overdue),
                TodayTimeBlock(label: "14:00-14:30", task: dueToday)
            ]
        )
        let workload = DailyWorkloadOverview(days: [], unscheduledTasks: [], inboxUntriagedCount: 0)

        let review = DailyPlanningReviewBuilder.review(
            transcript: "遅れてるものだけ教えて",
            plan: plan,
            workload: workload,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(review.phase, .midday)
        XCTAssertNil(review.requestedMinutes)
        XCTAssertEqual(review.overdueCount, 1)
        XCTAssertEqual(review.dueTodayCount, 1)
        XCTAssertEqual(review.recommendedTaskID, 20)
        XCTAssertEqual(review.focusItems.first?.title, "Unblock account migration")
        XCTAssertEqual(review.scheduleBlocks.first?.taskID, 20)
        XCTAssertTrue(review.headline.contains("Midday"))
        XCTAssertTrue(review.spokenSummary.contains("1 overdue"))
        XCTAssertTrue(review.spokenSummary.contains("Resume with Unblock account migration"))
    }

    private func task(
        id: Int64,
        title: String,
        status: ProjectTaskStatus = .planned,
        priority: ProjectTaskPriority = .medium,
        dueAt: String?
    ) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: 1,
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
}
