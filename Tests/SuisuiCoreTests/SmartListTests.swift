import XCTest
@testable import SuisuiCore

final class SmartListTests: XCTestCase {
    private let tokyo = "Asia/Tokyo"
    private let utc = "UTC"

    /// 2026-07-06T15:30:00Z == 2026-07-07T00:30+09:00 in Tokyo, so "today"
    /// differs between UTC and Tokyo for the same instant.
    private var now: Date {
        ISO8601DateFormatter().date(from: "2026-07-06T15:30:00Z")!
    }

    private func makeTask(
        id: Int64 = 1,
        projectID: Int64 = 10,
        title: String = "Prepare launch checklist",
        detail: String = "",
        status: ProjectTaskStatus = .planned,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask {
        ProjectBoardTask(
            id: id,
            projectID: projectID,
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueAt
        )
    }

    private func makeProject(
        id: Int64 = 10,
        status: String = "active",
        tasks: [ProjectBoardTask]
    ) -> ProjectBoardProject {
        ProjectBoardProject(
            id: id,
            title: "Project \(id)",
            status: status,
            subtitle: "",
            columns: [ProjectBoardColumn(status: .planned, tasks: tasks)]
        )
    }

    // MARK: - Criteria matching

    func testStatusCriteriaFiltersAndNilMatchesEveryStatus() {
        let criteria = SmartListCriteria(statuses: [.planned, .inProgress])

        XCTAssertTrue(criteria.matches(makeTask(status: .planned), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertTrue(criteria.matches(makeTask(status: .inProgress), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(status: .done), project: nil, now: now, timeZoneIdentifier: utc))

        let unconstrained = SmartListCriteria()
        for status in ProjectTaskStatus.allCases {
            XCTAssertTrue(unconstrained.matches(makeTask(status: status), project: nil, now: now, timeZoneIdentifier: utc))
        }
    }

    func testPriorityCriteriaFiltersAndNilMatchesEveryPriority() {
        let criteria = SmartListCriteria(priorities: [.high])

        XCTAssertTrue(criteria.matches(makeTask(priority: .high), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(priority: .medium), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(priority: .low), project: nil, now: now, timeZoneIdentifier: utc))

        let unconstrained = SmartListCriteria()
        for priority in ProjectTaskPriority.allCases {
            XCTAssertTrue(unconstrained.matches(makeTask(priority: priority), project: nil, now: now, timeZoneIdentifier: utc))
        }
    }

    func testDueWithinDaysUsesHalfOpenWindowFromStartOfToday() {
        let criteria = SmartListCriteria(dueWithinDays: 7)

        // UTC "today" is 2026-07-06. Window: [2026-07-06T00:00Z, 2026-07-13T00:00Z).
        XCTAssertTrue(criteria.matches(makeTask(dueAt: "2026-07-06T00:00:00Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertTrue(criteria.matches(makeTask(dueAt: "2026-07-12T23:59:59Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(dueAt: "2026-07-13T00:00:00Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(dueAt: "2026-07-05T23:59:59Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(dueAt: nil), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(dueAt: "not-a-date"), project: nil, now: now, timeZoneIdentifier: utc))
    }

    func testDueWithinDaysIsTimeZoneAwareForDateOnlyDueValues() {
        let criteria = SmartListCriteria(dueWithinDays: 1)

        // Same instant, different local days: Tokyo is already on 2026-07-07.
        let dueTomorrowTokyo = makeTask(dueAt: "2026-07-07")
        XCTAssertTrue(criteria.matches(dueTomorrowTokyo, project: nil, now: now, timeZoneIdentifier: tokyo))

        // In UTC the same date-only value falls outside [today, today+1) only
        // if it is not the UTC today; 2026-07-07 is tomorrow in UTC, so the
        // 1-day window [2026-07-06, 2026-07-07) excludes it.
        XCTAssertFalse(criteria.matches(dueTomorrowTokyo, project: nil, now: now, timeZoneIdentifier: utc))
    }

    func testOverdueOnlyMeansDueBeforeStartOfTodayInTheGivenTimeZone() {
        let criteria = SmartListCriteria(overdueOnly: true)
        let dueJulySixth = makeTask(dueAt: "2026-07-06")

        // Tokyo: today is 2026-07-07, so a 2026-07-06 due date is overdue.
        XCTAssertTrue(criteria.matches(dueJulySixth, project: nil, now: now, timeZoneIdentifier: tokyo))
        // UTC: today is still 2026-07-06, so the same task is not overdue yet.
        XCTAssertFalse(criteria.matches(dueJulySixth, project: nil, now: now, timeZoneIdentifier: utc))

        XCTAssertFalse(criteria.matches(makeTask(dueAt: nil), project: nil, now: now, timeZoneIdentifier: tokyo))
    }

    func testSearchTextMatchesTitleOrDetailCaseInsensitively() {
        let criteria = SmartListCriteria(searchText: "launch")

        XCTAssertTrue(criteria.matches(makeTask(title: "Prepare LAUNCH checklist"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertTrue(criteria.matches(makeTask(title: "Other", detail: "Coordinate Launch window"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(title: "Other", detail: "No match"), project: nil, now: now, timeZoneIdentifier: utc))

        let blankSearch = SmartListCriteria(searchText: "   ")
        XCTAssertTrue(blankSearch.matches(makeTask(title: "Anything"), project: nil, now: now, timeZoneIdentifier: utc))
    }

    func testArchivedProjectTasksNeverMatch() {
        let criteria = SmartListCriteria()
        let task = makeTask()

        XCTAssertTrue(criteria.matches(task, project: makeProject(tasks: [task]), now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(task, project: makeProject(status: "archived", tasks: [task]), now: now, timeZoneIdentifier: utc))
    }

    func testCombinedCriteriaRequireEveryConstraint() {
        let criteria = SmartListCriteria(
            statuses: [.planned],
            priorities: [.high],
            dueWithinDays: 7,
            searchText: "release"
        )
        let matching = makeTask(title: "Cut release", status: .planned, priority: .high, dueAt: "2026-07-08T00:00:00Z")

        XCTAssertTrue(criteria.matches(matching, project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(title: "Cut release", status: .done, priority: .high, dueAt: "2026-07-08T00:00:00Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(title: "Cut release", status: .planned, priority: .low, dueAt: "2026-07-08T00:00:00Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(title: "Unrelated", status: .planned, priority: .high, dueAt: "2026-07-08T00:00:00Z"), project: nil, now: now, timeZoneIdentifier: utc))
        XCTAssertFalse(criteria.matches(makeTask(title: "Cut release", status: .planned, priority: .high, dueAt: nil), project: nil, now: now, timeZoneIdentifier: utc))
    }

    // MARK: - Presets

    func testPresetsComposeDueThisWeekHighPriorityAndOverdue() {
        let presets = SmartList.presets

        XCTAssertEqual(presets.map(\.id), [
            SmartList.dueThisWeekPresetID,
            SmartList.highPriorityPresetID,
            SmartList.overduePresetID
        ])
        XCTAssertEqual(presets.map(\.name), ["Due this week", "High priority", "Overdue"])
        XCTAssertTrue(presets.allSatisfy(\.isPreset))

        let dueThisWeek = presets[0].criteria
        XCTAssertEqual(dueThisWeek.dueWithinDays, 7)
        XCTAssertEqual(dueThisWeek.statuses, SmartList.openTaskStatuses)
        XCTAssertFalse(dueThisWeek.overdueOnly)

        let highPriority = presets[1].criteria
        XCTAssertEqual(highPriority.priorities, [.high])
        XCTAssertEqual(highPriority.statuses, SmartList.openTaskStatuses)

        let overdue = presets[2].criteria
        XCTAssertTrue(overdue.overdueOnly)
        XCTAssertEqual(overdue.statuses, SmartList.openTaskStatuses)

        // Presets never surface completed work.
        let doneTask = makeTask(status: .done, priority: .high, dueAt: "2026-07-06T00:00:00Z")
        for preset in presets {
            XCTAssertFalse(preset.criteria.matches(doneTask, project: nil, now: now, timeZoneIdentifier: utc))
        }
    }

    func testMatchingTasksFlattensProjectsAndOrdersByDueDateThenID() {
        let overdueTask = makeTask(id: 3, projectID: 10, status: .planned, dueAt: "2026-07-01T00:00:00Z")
        let laterTask = makeTask(id: 1, projectID: 11, status: .inProgress, dueAt: "2026-07-08T00:00:00Z")
        let noDueTask = makeTask(id: 2, projectID: 11, status: .backlog, dueAt: nil)
        let archivedTask = makeTask(id: 4, projectID: 12, status: .planned, dueAt: "2026-07-01T00:00:00Z")
        let snapshot = ProjectBoardSnapshot(projects: [
            makeProject(id: 10, tasks: [overdueTask]),
            makeProject(id: 11, tasks: [laterTask, noDueTask]),
            makeProject(id: 12, status: "archived", tasks: [archivedTask])
        ])
        let smartList = SmartList(id: "all-open", name: "All open", criteria: SmartListCriteria(statuses: SmartList.openTaskStatuses))

        let taskIDs = smartList.matchingTasks(in: snapshot, now: now, timeZoneIdentifier: utc).map(\.id)

        XCTAssertEqual(taskIDs, [3, 1, 2], "due ascending, no due date last, archived excluded")
    }

    // MARK: - FileSmartListStore

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-list-store-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL
    }

    func testFileSmartListStoreRoundTripsSaveUpsertAndDelete() throws {
        let directoryURL = try makeTemporaryDirectory()
        let store = try FileSmartListStore(directoryURL: directoryURL)

        XCTAssertEqual(try store.list(), [])

        let first = SmartList(
            id: "list-1",
            name: "Blocked reviews",
            criteria: SmartListCriteria(statuses: [.blocked], searchText: "review")
        )
        let second = SmartList(
            id: "list-2",
            name: "Due soon",
            criteria: SmartListCriteria(dueWithinDays: 3, overdueOnly: false)
        )
        try store.save(first)
        try store.save(second)
        XCTAssertEqual(try store.list(), [first, second])

        var renamed = first
        renamed.name = "Blocked work"
        renamed.criteria.priorities = [.high, .medium]
        try store.save(renamed)
        XCTAssertEqual(try store.list(), [renamed, second], "save upserts in place without reordering")

        try store.delete(id: second.id)
        XCTAssertEqual(try store.list(), [renamed])

        // A fresh store instance reads the same file (durable round trip).
        let reopenedStore = try FileSmartListStore(directoryURL: directoryURL)
        XCTAssertEqual(try reopenedStore.list(), [renamed])
    }

    func testFileSmartListStoreDeleteOfUnknownIDIsHarmless() throws {
        let store = try FileSmartListStore(directoryURL: makeTemporaryDirectory())
        let smartList = SmartList(id: "keep", name: "Keep", criteria: SmartListCriteria())
        try store.save(smartList)

        try store.delete(id: "missing")

        XCTAssertEqual(try store.list(), [smartList])
    }

    // MARK: - Command palette composition

    func testCommandPaletteEmptyQueryListsSmartListsBetweenWindowActionsAndProjects() {
        let items = CommandPaletteComposer.items(
            query: "",
            projects: [(id: 1, title: "Release prep", isArchived: false)],
            smartLists: [
                (id: SmartList.overduePresetID, name: "Overdue"),
                (id: "list-1", name: "Blocked reviews")
            ]
        )

        XCTAssertEqual(items.map(\.id), [
            "destination-today",
            "destination-inbox",
            "destination-assistant-queue",
            "destination-schedule",
            "destination-done",
            "destination-catch-up",
            "window-voice-command",
            "window-settings",
            "smart-list-\(SmartList.overduePresetID)",
            "smart-list-list-1",
            "project-1"
        ])
        XCTAssertEqual(
            items[8].kind,
            .openSmartList(id: SmartList.overduePresetID, name: "Overdue")
        )
        XCTAssertEqual(items[8].subtitle, "Smart List")
    }

    func testCommandPaletteQueryFuzzyMatchesSmartListNames() {
        let items = CommandPaletteComposer.items(
            query: "ovr",
            projects: [],
            smartLists: [(id: SmartList.overduePresetID, name: "Overdue")]
        )

        XCTAssertTrue(items.contains { item in
            item.kind == .openSmartList(id: SmartList.overduePresetID, name: "Overdue")
        })

        let missItems = CommandPaletteComposer.items(
            query: "zzz",
            projects: [],
            smartLists: [(id: SmartList.overduePresetID, name: "Overdue")]
        )
        XCTAssertFalse(missItems.contains { item in
            if case .openSmartList = item.kind {
                return true
            }
            return false
        })
    }
}
