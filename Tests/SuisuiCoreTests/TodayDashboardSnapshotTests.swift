import XCTest
@testable import SuisuiCore

final class TodayDashboardSnapshotTests: XCTestCase {
    func testProjectsTodayPlanIntoDisplayRowsAndWorkload() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let blocker = task(id: 1, title: "Unblock release", status: .blocked, priority: .high, dueAt: "2026-08-08")
        let focus = task(id: 2, title: "Write notes", priority: .medium, dueAt: "2026-08-09T14:00:00Z")
        let today = workflowSnapshot(tasks: [blocker, focus])

        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: today,
            schedule: .empty,
            projectTitlesByTaskID: [1: "Suisui", 2: "Launch"],
            displayName: "Shuto",
            dailyCapacityMinutes: 360,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.header.title, "Sunday, Aug 9")
        XCTAssertEqual(snapshot.header.greeting, "Good morning, Shuto")
        XCTAssertEqual(snapshot.tasks.map(\.projectTitle), ["Suisui", "Launch"])
        XCTAssertEqual(snapshot.tasks.map(\.priorityLabel), ["High", "Medium"])
        XCTAssertTrue(snapshot.tasks[0].timeLabel?.hasPrefix("Overdue ") == true)
        XCTAssertEqual(snapshot.tasks[1].timeLabel, "Today 14:00")
        XCTAssertEqual(snapshot.workload.plannedTaskCount, 2)
        XCTAssertEqual(snapshot.workload.dailyCapacityMinutes, 360)
        XCTAssertEqual(snapshot.recommendation.taskID, blocker.id)
        XCTAssertEqual(snapshot.recommendation.reason, "Blocked work should be cleared first.")
    }

    func testRecommendationOrderIsDeterministicAndFallsBackToFirstTask() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let high = task(id: 3, title: "High", priority: .high, dueAt: nil)
        let overdue = task(id: 2, title: "Overdue", priority: .low, dueAt: "2026-08-08")
        let blocker = task(id: 1, title: "Blocker", status: .blocked, priority: .low, dueAt: nil)

        XCTAssertEqual(make(tasks: [high, overdue, blocker], now: now, calendar: calendar).recommendation.taskID, blocker.id)
        XCTAssertEqual(make(tasks: [high, overdue], now: now, calendar: calendar).recommendation.taskID, overdue.id)
        XCTAssertEqual(make(tasks: [task(id: 5, title: "First", priority: .low, dueAt: nil), high], now: now, calendar: calendar).recommendation.taskID, high.id)
        let fallback = task(id: 4, title: "Fallback", priority: .low, dueAt: nil)
        XCTAssertEqual(make(tasks: [fallback], now: now, calendar: calendar).recommendation.taskID, fallback.id)
    }

    func testZeroDataHasSafeDefaults() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))

        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: []),
            schedule: .empty,
            projectTitlesByTaskID: [:],
            displayName: "   ",
            dailyCapacityMinutes: 0,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(snapshot.header.greeting, "Good morning")
        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.workload.plannedTaskCount, 0)
        XCTAssertEqual(snapshot.workload.dailyCapacityMinutes, 480)
        XCTAssertNil(snapshot.recommendation.taskID)
        XCTAssertFalse(snapshot.review.isError)
        XCTAssertEqual(snapshot.review.message, "No review items yet.")
    }

    private func make(tasks: [ProjectBoardTask], now: Date, calendar: Calendar) -> TodayDashboardSnapshot {
        TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: tasks),
            schedule: .empty,
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar
        )
    }

    private func workflowSnapshot(tasks: [ProjectBoardTask]) -> TodayWorkflowSnapshot {
        TodayWorkflowSnapshot(
            plan: TodayWorkflowPlan(
                tasks: tasks,
                overdueCount: 0,
                dueTodayCount: 0,
                recommendedTask: nil,
                recommendationReason: "",
                timeBlocks: []
            ),
            assistantContext: TodayAssistantRailContext(
                source: .empty,
                task: nil,
                projectTitle: "",
                nextActionTitle: "",
                nextActionReason: "",
                nextBlockLabel: nil,
                notes: "",
                subtaskSummary: "",
                reminderSummary: ""
            ),
            recommendationChips: []
        )
    }

    private func task(id: Int64, title: String, status: ProjectTaskStatus = .planned, priority: ProjectTaskPriority, dueAt: String?) -> ProjectBoardTask {
        ProjectBoardTask(id: id, projectID: 1, title: title, detail: "", status: status, priority: priority, dueAt: dueAt)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try! XCTUnwrap(TimeZone(secondsFromGMT: 0))
        return calendar
    }
}
