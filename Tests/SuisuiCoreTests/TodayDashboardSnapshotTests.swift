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
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(snapshot.header.title, "Sunday, Aug 9")
        XCTAssertEqual(snapshot.header.greeting, "Good morning, Shuto")
        XCTAssertEqual(snapshot.header.taskCount, 2)
        XCTAssertEqual(snapshot.header.scheduledTaskCount, 0)
        XCTAssertEqual(snapshot.tasks.map(\.projectTitle), ["Suisui", "Launch"])
        XCTAssertEqual(snapshot.tasks.map(\.priorityLabel), ["High", "Medium"])
        XCTAssertTrue(snapshot.tasks[0].timeLabel?.hasPrefix("Overdue ") == true)
        XCTAssertEqual(snapshot.tasks[1].timeLabel, "Today 14:00")
        XCTAssertEqual(snapshot.workload.plannedTaskCount, 2)
        XCTAssertEqual(snapshot.workload.dailyCapacityMinutes, 360)
        XCTAssertEqual(snapshot.recommendation?.taskID, blocker.id)
        XCTAssertEqual(snapshot.recommendation?.reason, "Blocked work should be cleared first.")
    }

    func testProjectsInjectedCalendarAndSlackStatesIntoOneDashboardSnapshot() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: []),
            schedule: .empty,
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: fixedCalendar(),
            locale: Locale(identifier: "en_US"),
            integrationsState: TodayIntegrationStates(
                calendar: .syncing,
                slack: .synced(lastSyncedAt: now, itemCount: 2)
            )
        )

        XCTAssertEqual(snapshot.integrations.calendar.state, .syncing)
        XCTAssertEqual(snapshot.integrations.calendar.detail, "Syncing")
        XCTAssertEqual(snapshot.integrations.slack.state, .synced(lastSyncedAt: now, itemCount: 2))
        XCTAssertTrue(snapshot.integrations.slack.accessibilityLabel.contains("2 items synced"))
    }

    func testRecommendationOrderIsDeterministicAndFallsBackToFirstTask() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let high = task(id: 3, title: "High", priority: .high, dueAt: nil)
        let overdue = task(id: 2, title: "Overdue", priority: .low, dueAt: "2026-08-08")
        let blocker = task(id: 1, title: "Blocker", status: .blocked, priority: .low, dueAt: nil)

        XCTAssertEqual(make(tasks: [high, overdue, blocker], now: now, calendar: calendar).recommendation?.taskID, blocker.id)
        XCTAssertEqual(make(tasks: [high, overdue], now: now, calendar: calendar).recommendation?.taskID, overdue.id)
        XCTAssertEqual(make(tasks: [task(id: 5, title: "First", priority: .low, dueAt: nil), high], now: now, calendar: calendar).recommendation?.taskID, high.id)
        let fallback = task(id: 4, title: "Fallback", priority: .low, dueAt: nil)
        XCTAssertEqual(make(tasks: [fallback], now: now, calendar: calendar).recommendation?.taskID, fallback.id)
    }

    func testPlanRecommendationWinsWhenTasksContainBlockedOverdueAndHighPriorityWork() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let high = task(id: 1, title: "High", priority: .high, dueAt: nil)
        let overdue = task(id: 2, title: "Overdue", priority: .medium, dueAt: "2026-08-08")
        let blocker = task(id: 3, title: "Blocker", status: .blocked, priority: .low, dueAt: nil)

        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: [blocker, overdue, high], recommendedTask: high, recommendationReason: "Protect the release work."),
            schedule: .empty,
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(snapshot.recommendation?.taskID, high.id)
        XCTAssertEqual(snapshot.recommendation?.reason, "Protect the release work.")
    }

    func testRecommendationsOfferAnAddTaskActionWhenTodayHasNoActionableTasks() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let snapshot = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: []), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(snapshot.recommendations.count, 1)
        XCTAssertNil(snapshot.recommendation?.taskID)
        XCTAssertEqual(snapshot.recommendation?.action, .addTask)
    }

    func testRecommendationsKeepPrimaryThenUniqueChipsThenRemainingTasks() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let primary = task(id: 1, title: "Primary", priority: .high, dueAt: nil)
        let second = task(id: 2, title: "Second", priority: .medium, dueAt: nil)
        let third = task(id: 3, title: "Third", priority: .low, dueAt: nil)
        let fourth = task(id: 4, title: "Fourth", priority: .low, dueAt: nil)
        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(
                tasks: [primary, second, third, fourth],
                recommendedTask: primary,
                recommendationReason: "Start here.",
                chips: [
                    chip(task: primary, kind: .highPriority),
                    chip(task: second, kind: .blocker),
                    chip(task: second, kind: .overdue),
                ]
            ),
            schedule: .empty,
            projectTitlesByTaskID: [third.id: "Suisui"],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(snapshot.recommendations.map(\.taskID), [primary.id, second.id, third.id])
        XCTAssertEqual(snapshot.recommendations.map(\.title), ["Primary", "Resolve blocker", "Third"])
        XCTAssertEqual(snapshot.recommendations.map(\.action), [.startFocus, .selectTask, .selectTask])
        XCTAssertEqual(snapshot.recommendation, snapshot.recommendations.first)
        XCTAssertEqual(snapshot.recommendations.count, 3)
    }

    func testRecommendationsKeepOnePrimaryWhenNoUniqueChipOrRemainingTaskExists() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let primary = task(id: 1, title: "Only", priority: .high, dueAt: nil)
        let snapshot = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [primary], recommendedTask: primary, recommendationReason: "Start here.", chips: [chip(task: primary, kind: .highPriority)]), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(snapshot.recommendations.map(\.taskID), [primary.id, nil, nil])
        XCTAssertEqual(snapshot.recommendations.map(\.action), [.startFocus, .addTask, .suggestBreak])
    }

    func testRecommendationsUseReviewFocusThenPrioritizedUnscheduledTasksWithoutDuplicates() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let primary = task(id: 1, title: "Primary", priority: .high, dueAt: nil)
        let reviewFocus = task(id: 2, title: "Review focus", priority: .medium, dueAt: nil)
        let lowUnscheduled = task(id: 3, title: "Low unscheduled", priority: .low, dueAt: nil)
        let highUnscheduled = task(id: 4, title: "High unscheduled", priority: .high, dueAt: nil)
        let review = DailyPlanningReview(
            sourceTranscript: "",
            phase: .morning,
            requestedMinutes: nil,
            headline: "",
            spokenSummary: "",
            overdueCount: 0,
            dueTodayCount: 0,
            inboxUntriagedCount: 0,
            recommendedTaskID: primary.id,
            focusItems: [
                DailyPlanningFocusItem(taskID: primary.id, title: primary.title, reason: "Duplicate primary."),
                DailyPlanningFocusItem(taskID: reviewFocus.id, title: reviewFocus.title, reason: "Review this next.")
            ],
            scheduleBlocks: []
        )

        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: [primary], recommendedTask: primary, recommendationReason: "Start here.", review: review),
            schedule: schedule(blocks: [], unscheduled: [lowUnscheduled, highUnscheduled]),
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(snapshot.recommendations.map(\.taskID), [primary.id, reviewFocus.id, highUnscheduled.id])
        XCTAssertEqual(snapshot.recommendations.map(\.action), [.startFocus, .openReview, .prepareScheduleDraft])
    }

    func testUnscheduledRecommendationsOnlyIncludeActionableCandidatesInStableOrder() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let low = task(id: 1, title: "Low", priority: .low, dueAt: nil)
        let medium = task(id: 2, title: "Medium", priority: .medium, dueAt: nil)
        let laterHigh = task(id: 9, title: "Later high", priority: .high, dueAt: nil)
        let firstHigh = task(id: 3, title: "First high", priority: .high, dueAt: nil)

        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: []),
            schedule: schedule(blocks: [], unscheduled: [laterHigh, medium, low, firstHigh]),
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(snapshot.recommendations.map(\.taskID), [firstHigh.id, laterHigh.id, nil])
        XCTAssertEqual(snapshot.recommendations.map(\.action), [.prepareScheduleDraft, .prepareScheduleDraft, .addTask])
        XCTAssertEqual(snapshot.recommendations.map(\.reason), ["Needs scheduling", "Needs scheduling", "Add a task to plan your day."])
    }

    func testLocaleCalendarAndGreetingBoundariesAreExplicit() throws {
        let utc = fixedCalendar()
        let tokyo = calendar(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T15:30:00Z"))
        let due = task(id: 1, title: "Due", priority: .medium, dueAt: "2026-08-08")

        let english = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [due]), schedule: .empty, projectTitlesByTaskID: [:], displayName: "Suisui", dailyCapacityMinutes: 480, now: now, calendar: utc, locale: Locale(identifier: "en_US"))
        let japanese = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [due]), schedule: .empty, projectTitlesByTaskID: [:], displayName: "Suisui", dailyCapacityMinutes: 480, now: now, calendar: tokyo, locale: Locale(identifier: "ja_JP"))
        let noon = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: []), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T12:00:00Z")), calendar: utc, locale: Locale(identifier: "en_US"))
        let evening = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: []), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T18:00:00Z")), calendar: utc, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(english.header.title, "Sunday, Aug 9")
        XCTAssertEqual(japanese.header.title, "8月10日 月曜日")
        XCTAssertTrue(japanese.tasks[0].timeLabel?.contains("8月") == true)
        XCTAssertEqual(noon.header.greeting, "Good afternoon")
        XCTAssertEqual(evening.header.greeting, "Good evening")
        XCTAssertTrue(japanese.header.greeting.contains("Suisui"))
    }

    func testWeeklyScheduleCountsUniqueTasksAcrossBlocksAndUnscheduledWork() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let repeated = task(id: 1, title: "Repeated", priority: .medium, dueAt: nil)
        let second = task(id: 2, title: "Second", priority: .medium, dueAt: nil)
        let schedule = schedule(blocks: [repeated, repeated, second], unscheduled: [repeated])

        let snapshot = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: []), schedule: schedule, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar)

        XCTAssertEqual(snapshot.weeklySchedule.scheduledTaskCount, 2)
        XCTAssertEqual(snapshot.weeklySchedule.unscheduledTaskCount, 1)
        XCTAssertEqual(snapshot.weeklySchedule.dayCount, 2)
    }

    func testWeeklyScheduleRowsExposeScheduledAgendaAndHeaderCountsOnlyToday() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let todayTask = task(id: 1, title: "Design review", priority: .high, dueAt: nil)
        let tomorrowTask = task(id: 2, title: "Ship notes", priority: .medium, dueAt: nil)
        let todayWorkload = DailyWorkloadDay(date: now, dateKey: "2026-08-09", totalTaskCount: 1, openTaskCount: 1, inProgressTaskCount: 0, blockedTaskCount: 0, doneTaskCount: 0, overdueTaskCount: 0, progress: 0, projectContributions: [])
        let tomorrow = now.addingTimeInterval(86_400)
        let tomorrowWorkload = DailyWorkloadDay(date: tomorrow, dateKey: "2026-08-10", totalTaskCount: 1, openTaskCount: 1, inProgressTaskCount: 0, blockedTaskCount: 0, doneTaskCount: 0, overdueTaskCount: 0, progress: 0, projectContributions: [])
        let todayBlock = WeeklyScheduleBlock(id: "today", dayKey: "2026-08-09", task: todayTask, projectTitle: "Suisui", source: .scheduleDraft, startAt: now.addingTimeInterval(1_800), endAt: now.addingTimeInterval(4_500), timeLabel: "10:00–10:45")
        let tomorrowBlock = WeeklyScheduleBlock(id: "tomorrow", dayKey: "2026-08-10", task: tomorrowTask, projectTitle: "Suisui", source: .scheduleDraft, startAt: tomorrow.addingTimeInterval(1_800), endAt: tomorrow.addingTimeInterval(3_600), timeLabel: "10:00–10:30")
        let todayDay = WeeklyScheduleDay(date: now, dateKey: "2026-08-09", workload: todayWorkload, blocks: [todayBlock], reminderProposalCount: 0, loadLevel: .open)
        let tomorrowDay = WeeklyScheduleDay(date: tomorrow, dateKey: "2026-08-10", workload: tomorrowWorkload, blocks: [tomorrowBlock], reminderProposalCount: 0, loadLevel: .open)
        let schedule = ProjectBoardScheduleReadModel(
            workloadOverview: DailyWorkloadOverview(days: [todayWorkload, tomorrowWorkload], unscheduledTasks: [], inboxUntriagedCount: 0),
            weeklyCockpit: WeeklyScheduleCockpit(days: [todayDay, tomorrowDay], unscheduledTasks: [], agendaDay: todayDay, focusForecast: WeeklyScheduleFocusForecast(state: .open, overloadedDayKeys: [], heavyDayKeys: [], reminderProposalCount: 0)),
            unscheduledTasks: []
        )

        let snapshot = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [todayTask]), schedule: schedule, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))

        XCTAssertEqual(snapshot.header.scheduledTaskCount, 1)
        XCTAssertEqual(snapshot.weeklySchedule.scheduledTaskCount, 2)
        XCTAssertEqual(snapshot.weeklySchedule.rows.map(\.taskID), [todayTask.id, tomorrowTask.id])
        XCTAssertEqual(snapshot.weeklySchedule.rows.map(\.title), ["Design review", "Ship notes"])
        XCTAssertEqual(snapshot.weeklySchedule.rows.map(\.timeLabel), ["10:00–10:45", "10:00–10:30"])
        XCTAssertEqual(snapshot.weeklySchedule.rows.map(\.durationMinutes), [45, 30])
        XCTAssertEqual(snapshot.weeklySchedule.rows.first?.dateLabel, "Sun, Aug 9")
    }

    func testJapaneseLocalizesGreetingFallbackReviewPriorityAndKnownPlanReason() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let highTask = task(id: 1, title: "Suisui", priority: .high, dueAt: nil)
        let overdue = task(id: 2, title: "期限", priority: .low, dueAt: "2026-08-08")
        let empty = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: []), schedule: .empty, projectTitlesByTaskID: [:], displayName: "Suisui", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "ja_JP"))
        let fallback = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [highTask]), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "ja_JP"))
        let planned = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [highTask], recommendedTask: highTask, recommendationReason: "High-priority work is the best first task."), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "ja_JP"))

        XCTAssertEqual(empty.header.greeting, "Suisui、おはようございます")
        XCTAssertEqual(empty.recommendation?.action, .addTask)
        XCTAssertEqual(empty.review.message, "まだ振り返り項目はありません。")
        XCTAssertEqual(fallback.tasks[0].priorityLabel, "高")
        XCTAssertEqual(fallback.recommendation?.reason, "高優先度の作業を守りましょう。")
        XCTAssertEqual(planned.recommendation?.reason, "高優先度の作業から始めるのが最適です。")
        XCTAssertEqual(overdue.todayDueDisplayLabel(on: now, calendar: calendar, locale: Locale(identifier: "ja_JP")), "期限超過 8月8日")
    }

    func testJapaneseLocalizesDailyPlanningReviewReasonsInRecommendations() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let reasons = [
            ("Blocked work should be unblocked before adding new scope.", "ブロック中の作業を解消してから新しい範囲を追加しましょう。"),
            ("High-priority work protects today's plan.", "高優先度の作業が今日の計画を守ります。"),
            ("Keeps today's due work moving.", "今日が期限の作業を前に進められます。")
        ]

        for (reason, expected) in reasons {
            let review = DailyPlanningReview(
                sourceTranscript: "",
                phase: .morning,
                requestedMinutes: nil,
                headline: "",
                spokenSummary: "",
                overdueCount: 0,
                dueTodayCount: 0,
                inboxUntriagedCount: 0,
                recommendedTaskID: nil,
                focusItems: [DailyPlanningFocusItem(taskID: 1, title: "Task", reason: reason)],
                scheduleBlocks: []
            )
            let snapshot = TodayDashboardSnapshotBuilder.make(
                today: workflowSnapshot(tasks: [], review: review),
                schedule: .empty,
                projectTitlesByTaskID: [:],
                displayName: "",
                dailyCapacityMinutes: 480,
                now: now,
                calendar: calendar,
                locale: Locale(identifier: "ja_JP")
            )

            XCTAssertEqual(snapshot.recommendations.first?.reason, expected)
        }
    }

    func testReviewTitleUsesSemanticFieldsInEnglishAndJapanese() throws {
        let calendar = fixedCalendar()
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T09:30:00Z"))
        let morning = review(phase: .morning, minutes: 90, focusCount: 3)
        let evening = review(phase: .evening, minutes: nil, focusCount: 1)
        let en = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [], review: morning), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "en_US"))
        let ja = TodayDashboardSnapshotBuilder.make(today: workflowSnapshot(tasks: [], review: evening), schedule: .empty, projectTitlesByTaskID: [:], displayName: "", dailyCapacityMinutes: 480, now: now, calendar: calendar, locale: Locale(identifier: "ja_JP"))

        XCTAssertEqual(en.review.message, "Morning focus review: 3 tasks for 90 minutes")
        XCTAssertEqual(ja.review.message, "夜のデイリープランニングレビュー")
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
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(snapshot.header.greeting, "Good morning")
        XCTAssertEqual(snapshot.tasks, [])
        XCTAssertEqual(snapshot.workload.plannedTaskCount, 0)
        XCTAssertEqual(snapshot.workload.dailyCapacityMinutes, 480)
        XCTAssertNil(snapshot.recommendation?.taskID)
        XCTAssertFalse(snapshot.review.isError)
        XCTAssertEqual(snapshot.review.message, "No review items yet.")
    }

    func testDashboardCarriesTheWeatherProjectionWithoutNetworkAccess() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-09T10:30:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let snapshot = TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: []),
            schedule: .empty,
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en"),
            weatherState: .available(temperatureCelsius: 22, location: "Tokyo", updatedAt: now)
        )

        XCTAssertEqual(snapshot.weather.title, "Tokyo · 22°C")
        XCTAssertEqual(snapshot.weather.accessibilityLabel, "Weather: Tokyo, 22°C. Updated 10:30.")
    }

    private func make(tasks: [ProjectBoardTask], now: Date, calendar: Calendar) -> TodayDashboardSnapshot {
        TodayDashboardSnapshotBuilder.make(
            today: workflowSnapshot(tasks: tasks),
            schedule: .empty,
            projectTitlesByTaskID: [:],
            displayName: "",
            dailyCapacityMinutes: 480,
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
    }

    private func workflowSnapshot(
        tasks: [ProjectBoardTask],
        recommendedTask: ProjectBoardTask? = nil,
        recommendationReason: String = "",
        chips: [TodayRecommendationChip] = [],
        review: DailyPlanningReview? = nil
    ) -> TodayWorkflowSnapshot {
        TodayWorkflowSnapshot(
            plan: TodayWorkflowPlan(
                tasks: tasks,
                overdueCount: 0,
                dueTodayCount: 0,
                recommendedTask: recommendedTask,
                recommendationReason: recommendationReason,
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
            recommendationChips: chips,
            dailyPlanningReviewPreview: review
        )
    }

    private func task(id: Int64, title: String, status: ProjectTaskStatus = .planned, priority: ProjectTaskPriority, dueAt: String?) -> ProjectBoardTask {
        ProjectBoardTask(id: id, projectID: 1, title: title, detail: "", status: status, priority: priority, dueAt: dueAt)
    }

    private func chip(task: ProjectBoardTask, kind: TodayRecommendationKind) -> TodayRecommendationChip {
        TodayRecommendationChip(kind: kind, taskID: task.id, taskTitle: task.title, title: kind == .blocker ? "Blocker" : "Chip", systemImage: "sparkles", reason: "Reason for \(task.title)")
    }

    private func fixedCalendar() -> Calendar {
        calendar(timeZone: try! XCTUnwrap(TimeZone(secondsFromGMT: 0)))
    }

    private func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func schedule(blocks: [ProjectBoardTask], unscheduled: [ProjectBoardTask]) -> ProjectBoardScheduleReadModel {
        let date = Date(timeIntervalSince1970: 0)
        let workload = DailyWorkloadDay(date: date, dateKey: "1970-01-01", totalTaskCount: 0, openTaskCount: 0, inProgressTaskCount: 0, blockedTaskCount: 0, doneTaskCount: 0, overdueTaskCount: 0, progress: 0, projectContributions: [])
        let day = WeeklyScheduleDay(date: date, dateKey: "1970-01-01", workload: workload, blocks: blocks.enumerated().map { index, task in
            WeeklyScheduleBlock(id: "\(task.id)-\(index)", dayKey: "1970-01-01", task: task, projectTitle: "Suisui", source: .scheduleDraft, startAt: nil, endAt: nil, timeLabel: "09:00")
        }, reminderProposalCount: 0, loadLevel: .open)
        let nextDate = date.addingTimeInterval(86_400)
        let nextDay = WeeklyScheduleDay(date: nextDate, dateKey: "1970-01-02", workload: workload, blocks: blocks.prefix(1).enumerated().map { index, task in
            WeeklyScheduleBlock(id: "next-\(task.id)-\(index)", dayKey: "1970-01-02", task: task, projectTitle: "Suisui", source: .scheduleDraft, startAt: nil, endAt: nil, timeLabel: "09:00")
        }, reminderProposalCount: 0, loadLevel: .open)
        return ProjectBoardScheduleReadModel(workloadOverview: DailyWorkloadOverview(days: [workload], unscheduledTasks: unscheduled, inboxUntriagedCount: 0), weeklyCockpit: WeeklyScheduleCockpit(days: [day, nextDay], unscheduledTasks: unscheduled, agendaDay: day, focusForecast: WeeklyScheduleFocusForecast(state: .open, overloadedDayKeys: [], heavyDayKeys: [], reminderProposalCount: 0)), unscheduledTasks: unscheduled)
    }

    private func review(phase: DailyPlanningReviewPhase, minutes: Int?, focusCount: Int) -> DailyPlanningReview {
        DailyPlanningReview(sourceTranscript: "", phase: phase, requestedMinutes: minutes, headline: "English headline", spokenSummary: "", overdueCount: 0, dueTodayCount: 0, inboxUntriagedCount: 0, recommendedTaskID: nil, focusItems: (0..<focusCount).map { DailyPlanningFocusItem(taskID: Int64($0), title: "Task", reason: "") }, scheduleBlocks: [])
    }
}
