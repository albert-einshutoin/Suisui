import XCTest
@testable import SuisuiCore

final class WorkManagementModelTests: XCTestCase {
    func testProjectTaskStatusNormalizationKeepsAliasMappingStable() {
        XCTAssertEqual(ProjectTaskStatus.normalized("next"), .planned)
        XCTAssertEqual(ProjectTaskStatus.normalized("doing"), .inProgress)
        XCTAssertEqual(ProjectTaskStatus.normalized("active"), .inProgress)
        XCTAssertEqual(ProjectTaskStatus.normalized("done"), .done)
        XCTAssertEqual(ProjectTaskStatus.normalized("closed"), .done)
        XCTAssertEqual(ProjectTaskStatus.normalized("unknown"), .backlog)
    }

    func testProjectTaskPriorityNormalizationKeepsDefaultAndInvalidErrorStable() throws {
        XCTAssertEqual(try ProjectTaskPriority.normalized(nil, column: "tasks.priority"), .medium)
        XCTAssertEqual(try ProjectTaskPriority.normalized(" high ", column: "tasks.priority"), .high)

        XCTAssertThrowsError(try ProjectTaskPriority.normalized("urgent", column: "tasks.priority")) { error in
            XCTAssertEqual(
                error as? LocalStoreDecodingError,
                .invalidEnum(column: "tasks.priority", value: "urgent")
            )
        }
    }

    func testProjectBoardGraphDerivedValuesStayStable() {
        let backlogTask = ProjectBoardTask(
            id: 10,
            projectID: 1,
            title: "Backlog",
            detail: "",
            status: .backlog,
            priority: .medium,
            dueAt: nil
        )
        let doneTask = ProjectBoardTask(
            id: 11,
            projectID: 1,
            title: "Done",
            detail: "",
            status: .done,
            priority: .low,
            dueAt: nil
        )
        let backlogColumn = ProjectBoardColumn(status: .backlog, tasks: [backlogTask])
        let doneColumn = ProjectBoardColumn(status: .done, tasks: [doneTask])
        let project = ProjectBoardProject(
            id: 1,
            title: "Launch",
            status: "completed",
            subtitle: "2 tasks",
            columns: [backlogColumn, doneColumn],
            artifacts: [
                ProjectBoardArtifact(
                    id: 1,
                    projectID: 1,
                    taskID: nil,
                    expectedPath: "/tmp/launch.md",
                    createdState: .expected,
                    lastModifiedAt: nil
                )
            ],
            milestones: [
                ProjectBoardMilestone(id: 1, projectID: 1, title: "Plan", dueAt: nil, isCompleted: true),
                ProjectBoardMilestone(id: 2, projectID: 1, title: "Ship", dueAt: nil, isCompleted: false)
            ]
        )

        XCTAssertEqual(ProjectBoardSnapshot.empty.projects, [])
        XCTAssertEqual(backlogColumn.id, "backlog")
        XCTAssertEqual(backlogColumn.title, "Backlog")
        XCTAssertEqual(project.taskCount, 2)
        XCTAssertEqual(project.tasks.map(\.id), [10, 11])
        XCTAssertTrue(project.isCompleted)
        XCTAssertFalse(project.isArchived)
        XCTAssertEqual(project.milestoneSummary, "1/2 milestones complete")
    }

    func testProjectBoardTaskDraftDefaultsStayStable() {
        let draft = ProjectBoardTaskDraft(projectID: 42, title: "Draft")

        XCTAssertEqual(draft.projectID, 42)
        XCTAssertEqual(draft.title, "Draft")
        XCTAssertEqual(draft.detail, "")
        XCTAssertEqual(draft.status, .backlog)
        XCTAssertEqual(draft.priority, .medium)
        XCTAssertNil(draft.dueAt)
    }

    func testTodayScheduleAndRecommendationValueModelsStayStable() {
        let task = ProjectBoardTask(
            id: 7,
            projectID: 3,
            title: "Review schedule",
            detail: "Check morning focus block",
            status: .planned,
            priority: .high,
            dueAt: "2026-07-03T09:00:00Z"
        )
        let block = TodayTimeBlock(label: "Morning", task: task, startAt: "09:00", endAt: "10:00")
        let plan = TodayWorkflowPlan(
            tasks: [task],
            overdueCount: 1,
            dueTodayCount: 2,
            recommendedTask: task,
            recommendationReason: "High priority",
            timeBlocks: [block]
        )
        let assistantContext = TodayAssistantRailContext(
            source: .recommended,
            task: task,
            projectTitle: "Suisui",
            nextActionTitle: "Start",
            nextActionReason: "Ready",
            nextBlockLabel: "Morning",
            notes: "Notes",
            subtaskSummary: "2 subtasks",
            reminderSummary: "1 reminder"
        )
        let chip = TodayRecommendationChip(
            kind: .highPriority,
            taskID: task.id,
            taskTitle: task.title,
            title: "High priority",
            systemImage: "exclamationmark.circle",
            reason: "Due soon"
        )
        let snapshot = TodayWorkflowSnapshot(
            plan: plan,
            assistantContext: assistantContext,
            recommendationChips: [chip]
        )
        let todayDraft = TodayScheduleDraft(timeBlocks: [block])
        let scheduleDraft = ScheduleDraft(timeBlocks: [block], unscheduledTasks: [task])

        XCTAssertEqual(block.id, "7-Morning")
        XCTAssertEqual(plan.recommendedTask?.id, task.id)
        XCTAssertEqual(assistantContext.source, .recommended)
        XCTAssertEqual(chip.id, "highPriority-7")
        XCTAssertEqual(snapshot.recommendationChips, [chip])
        XCTAssertEqual(todayDraft.timeBlocks, [block])
        XCTAssertEqual(scheduleDraft.unscheduledTasks, [task])
    }

    func testPortfolioDoneAndInboxValueModelsStayStable() {
        let project = ProjectPortfolioSummary(
            projectID: 8,
            title: "Release",
            status: "active",
            progress: 0.5,
            openTaskCount: 4,
            doneTaskCount: 2,
            blockedTaskCount: 1,
            overdueTaskCount: 1,
            nextDueAt: "2026-07-03",
            recentTaskID: 9,
            nextActionTitle: "Ship",
            health: .attention,
            riskReason: "Blocked task",
            localHealthRuleDescription: "Local rule"
        )
        let bestWeekday = DoneAnalyticsBestWeekdaySummary(weekday: 5, completedCount: 3)
        let bestHour = DoneAnalyticsBestHourSummary(hour: 14, timeOfDay: .afternoon, completedCount: 2)
        let done = DoneAnalyticsSummary(
            completedTaskCount: 5,
            completedProjectCount: 1,
            completedTodayCount: 2,
            completedThisWeekCount: 4,
            streakDays: 3,
            completionHeatmapBuckets: [DoneAnalyticsDayBucket(dayKey: "2026-07-03", completedCount: 2)],
            bestWeekdaySummary: bestWeekday,
            bestHourSummary: bestHour,
            recentTasks: [],
            localRuleInsight: "Local only"
        )
        let feedback = InboxClassificationFeedback(
            message: "Classified",
            systemImage: "tray.and.arrow.down",
            canUndo: true
        )
        let triage = InboxTriageSummary(
            sourceLabel: "Voice",
            interpretationLabel: "Task",
            systemImage: "waveform",
            tintName: "blue",
            accessibilityValue: "Voice task"
        )

        XCTAssertEqual(ProjectPortfolioHealth.attention.title, "Needs Attention")
        XCTAssertEqual(project.id, 8)
        XCTAssertEqual(project.health, .attention)
        XCTAssertFalse(bestWeekday.isEmpty)
        XCTAssertFalse(bestHour.isEmpty)
        XCTAssertTrue(DoneAnalyticsBestWeekdaySummary.empty.isEmpty)
        XCTAssertTrue(DoneAnalyticsBestHourSummary.empty.isEmpty)
        XCTAssertEqual(done.completionHeatmapBuckets.first?.completedCount, 2)
        XCTAssertEqual(feedback.systemImage, "tray.and.arrow.down")
        XCTAssertEqual(triage.accessibilityValue, "Voice task")
        XCTAssertEqual(InboxTriageFilter.all.title, "All")
        XCTAssertEqual(InboxTriageFilter.aiSuggested.title, "AI Suggested")
        XCTAssertEqual(InboxTriageFilter.unprocessed.id, "unprocessed")
    }

    func testTodayDueDisplayLabelFormatsOverdueTodayAndDateOnlyValues() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let referenceDate = try isoDate("2026-06-19T08:37:00Z")
        let overdue = ProjectBoardTask(
            id: 1,
            projectID: 1,
            title: "Overdue",
            detail: "",
            status: .planned,
            priority: .high,
            dueAt: "2026-06-18T09:00:00Z"
        )
        let today = ProjectBoardTask(
            id: 2,
            projectID: 1,
            title: "Today",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19T12:00:00Z"
        )
        let dateOnlyToday = ProjectBoardTask(
            id: 3,
            projectID: 1,
            title: "Date only today",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-19"
        )
        let dateOnly = ProjectBoardTask(
            id: 4,
            projectID: 1,
            title: "Date only",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-20"
        )
        var pacificCalendar = Calendar(identifier: .gregorian)
        pacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        var buddhistPacificCalendar = Calendar(identifier: .buddhist)
        buddhistPacificCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let pacificDateOnlyToday = ProjectBoardTask(
            id: 5,
            projectID: 1,
            title: "Pacific date only",
            detail: "",
            status: .planned,
            priority: .medium,
            dueAt: "2026-06-30"
        )

        XCTAssertEqual(
            overdue.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Overdue Jun 18 at 09:00"
        )
        XCTAssertTrue(overdue.isOverdueForToday(on: referenceDate, calendar: calendar))
        XCTAssertEqual(
            today.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Today 12:00"
        )
        XCTAssertFalse(today.isOverdueForToday(on: referenceDate, calendar: calendar))
        XCTAssertEqual(
            dateOnlyToday.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Today"
        )
        XCTAssertEqual(
            dateOnly.todayDueDisplayLabel(on: referenceDate, calendar: calendar, locale: Locale(identifier: "en_US_POSIX")),
            "Due Jun 20"
        )
        XCTAssertEqual(
            pacificDateOnlyToday.todayDueDisplayLabel(
                on: try isoDate("2026-07-01T06:30:00Z"),
                calendar: pacificCalendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Today"
        )
        XCTAssertEqual(
            pacificDateOnlyToday.todayDueDisplayLabel(
                on: try isoDate("2026-07-01T06:30:00Z"),
                calendar: buddhistPacificCalendar,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            "Today"
        )
        XCTAssertFalse(
            pacificDateOnlyToday.isOverdueForToday(
                on: try isoDate("2026-07-01T06:30:00Z"),
                calendar: pacificCalendar
            )
        )
    }

    private func isoDate(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}
