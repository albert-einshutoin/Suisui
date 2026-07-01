import Foundation

public enum WeeklyScheduleBlockSource: String, Equatable, Sendable {
    case scheduleDraft
    case dueTask
}

public enum WeeklyScheduleLoadLevel: String, Equatable, Sendable {
    case open
    case focused
    case heavy
    case overloaded

    public var title: String {
        switch self {
        case .open:
            "Open"
        case .focused:
            "Focused"
        case .heavy:
            "Heavy"
        case .overloaded:
            "Overloaded"
        }
    }
}

public enum WeeklyScheduleFocusForecastState: String, Equatable, Sendable {
    case open
    case heavy
    case overloaded
}

public struct WeeklyScheduleBlock: Identifiable, Equatable, Sendable {
    public var id: String
    public var dayKey: String
    public var task: ProjectBoardTask
    public var projectTitle: String
    public var source: WeeklyScheduleBlockSource
    public var startAt: Date?
    public var endAt: Date?
    public var timeLabel: String
    public var overlapLane: Int
    public var overlapGroupSize: Int

    public init(
        id: String,
        dayKey: String,
        task: ProjectBoardTask,
        projectTitle: String,
        source: WeeklyScheduleBlockSource,
        startAt: Date?,
        endAt: Date?,
        timeLabel: String,
        overlapLane: Int = 0,
        overlapGroupSize: Int = 1
    ) {
        self.id = id
        self.dayKey = dayKey
        self.task = task
        self.projectTitle = projectTitle
        self.source = source
        self.startAt = startAt
        self.endAt = endAt
        self.timeLabel = timeLabel
        self.overlapLane = overlapLane
        self.overlapGroupSize = overlapGroupSize
    }
}

public struct WeeklyScheduleDay: Identifiable, Equatable, Sendable {
    public var id: String { dateKey }
    public var date: Date
    public var dateKey: String
    public var workload: DailyWorkloadDay
    public var blocks: [WeeklyScheduleBlock]
    public var reminderProposalCount: Int
    public var completionHistoryCount: Int
    public var loadLevel: WeeklyScheduleLoadLevel

    public init(
        date: Date,
        dateKey: String,
        workload: DailyWorkloadDay,
        blocks: [WeeklyScheduleBlock],
        reminderProposalCount: Int,
        completionHistoryCount: Int = 0,
        loadLevel: WeeklyScheduleLoadLevel
    ) {
        self.date = date
        self.dateKey = dateKey
        self.workload = workload
        self.blocks = blocks
        self.reminderProposalCount = reminderProposalCount
        self.completionHistoryCount = completionHistoryCount
        self.loadLevel = loadLevel
    }
}

public struct WeeklyScheduleFocusForecast: Equatable, Sendable {
    public var state: WeeklyScheduleFocusForecastState
    public var overloadedDayKeys: [String]
    public var heavyDayKeys: [String]
    public var completedDayKeys: [String]
    public var reminderProposalCount: Int
    public var completionHistoryCount: Int

    public init(
        state: WeeklyScheduleFocusForecastState,
        overloadedDayKeys: [String],
        heavyDayKeys: [String],
        completedDayKeys: [String] = [],
        reminderProposalCount: Int,
        completionHistoryCount: Int = 0
    ) {
        self.state = state
        self.overloadedDayKeys = overloadedDayKeys
        self.heavyDayKeys = heavyDayKeys
        self.completedDayKeys = completedDayKeys
        self.reminderProposalCount = reminderProposalCount
        self.completionHistoryCount = completionHistoryCount
    }
}

public struct WeeklyScheduleCockpit: Equatable, Sendable {
    public var days: [WeeklyScheduleDay]
    public var unscheduledTasks: [ProjectBoardTask]
    public var agendaDay: WeeklyScheduleDay?
    public var focusForecast: WeeklyScheduleFocusForecast

    public init(
        days: [WeeklyScheduleDay],
        unscheduledTasks: [ProjectBoardTask],
        agendaDay: WeeklyScheduleDay?,
        focusForecast: WeeklyScheduleFocusForecast
    ) {
        self.days = days
        self.unscheduledTasks = unscheduledTasks
        self.agendaDay = agendaDay
        self.focusForecast = focusForecast
    }
}

enum WeeklyScheduleCockpitBuilder {
    static func cockpit(
        from snapshot: ProjectBoardSnapshot,
        workload: DailyWorkloadOverview,
        scheduleDraft: ScheduleDraft?,
        around referenceDate: Date,
        calendar inputCalendar: Calendar
    ) -> WeeklyScheduleCockpit {
        let calendar = inputCalendar
        let projectTitles = projectTitleLookup(from: snapshot)
        let draftBlocks = scheduleDraftBlocks(
            from: scheduleDraft,
            projectTitles: projectTitles,
            calendar: calendar
        )
        let draftTaskIDsByDay = Dictionary(
            grouping: draftBlocks,
            by: \.dayKey
        ).mapValues { Set($0.map(\.task.id)) }
        let completionHistoryCounts = completionHistoryCountsByDay(
            from: snapshot,
            calendar: calendar
        )

        let days = workload.days.map { workloadDay -> WeeklyScheduleDay in
            let dayDraftBlocks = draftBlocks.filter { $0.dayKey == workloadDay.dateKey }
            let dueBlocks = dueTaskBlocks(
                from: workloadDay,
                excludingTaskIDs: draftTaskIDsByDay[workloadDay.dateKey, default: []],
                calendar: calendar
            )
            let blocks = assignOverlapLanes(
                to: (dayDraftBlocks + dueBlocks).sorted(by: sortBlocks)
            )
            let reminderProposalCount = reminderProposalCount(for: workloadDay)
            let completionHistoryCount = completionHistoryCounts[workloadDay.dateKey, default: 0]
            let loadLevel = loadLevel(
                for: workloadDay,
                blockCount: blocks.count,
                reminderProposalCount: reminderProposalCount
            )

            return WeeklyScheduleDay(
                date: workloadDay.date,
                dateKey: workloadDay.dateKey,
                workload: workloadDay,
                blocks: blocks,
                reminderProposalCount: reminderProposalCount,
                completionHistoryCount: completionHistoryCount,
                loadLevel: loadLevel
            )
        }

        let agendaDay = days.first { day in
            day.dateKey == dateKey(for: referenceDate, calendar: calendar)
        } ?? days.first { !$0.blocks.isEmpty || $0.workload.totalTaskCount > 0 }
        let focusForecast = focusForecast(for: days)

        return WeeklyScheduleCockpit(
            days: days,
            unscheduledTasks: workload.unscheduledTasks,
            agendaDay: agendaDay,
            focusForecast: focusForecast
        )
    }

    private static func projectTitleLookup(from snapshot: ProjectBoardSnapshot) -> [Int64: String] {
        Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
    }

    private static func scheduleDraftBlocks(
        from draft: ScheduleDraft?,
        projectTitles: [Int64: String],
        calendar: Calendar
    ) -> [WeeklyScheduleBlock] {
        guard let draft else {
            return []
        }

        return draft.timeBlocks.compactMap { block in
            guard let start = parseDate(block.startAt, calendar: calendar),
                  let end = parseDate(block.endAt, calendar: calendar) else {
                return nil
            }
            let dayKey = dateKey(for: start, calendar: calendar)
            return WeeklyScheduleBlock(
                id: "\(dayKey)-draft-\(block.task.id)-\(block.label)",
                dayKey: dayKey,
                task: block.task,
                projectTitle: projectTitles[block.task.projectID] ?? "Project",
                source: .scheduleDraft,
                startAt: start,
                endAt: end,
                timeLabel: block.label
            )
        }
    }

    private static func dueTaskBlocks(
        from day: DailyWorkloadDay,
        excludingTaskIDs draftTaskIDs: Set<Int64>,
        calendar: Calendar
    ) -> [WeeklyScheduleBlock] {
        day.projectContributions.flatMap { contribution in
            contribution.tasks.compactMap { task -> WeeklyScheduleBlock? in
                guard task.status != .done,
                      !draftTaskIDs.contains(task.id),
                      let dueAt = task.dueAt,
                      let dueDate = parseDate(dueAt, calendar: calendar) else {
                    return nil
                }

                if isDateOnly(dueAt) {
                    return WeeklyScheduleBlock(
                        id: "\(day.dateKey)-due-\(task.id)-all-day",
                        dayKey: day.dateKey,
                        task: task,
                        projectTitle: contribution.projectTitle,
                        source: .dueTask,
                        startAt: nil,
                        endAt: nil,
                        timeLabel: "All day"
                    )
                }

                let end = calendar.date(byAdding: .minute, value: 30, to: dueDate) ?? dueDate
                return WeeklyScheduleBlock(
                    id: "\(day.dateKey)-due-\(task.id)-\(timeLabel(start: dueDate, end: end, calendar: calendar))",
                    dayKey: day.dateKey,
                    task: task,
                    projectTitle: contribution.projectTitle,
                    source: .dueTask,
                    startAt: dueDate,
                    endAt: end,
                    timeLabel: timeLabel(start: dueDate, end: end, calendar: calendar)
                )
            }
        }
    }

    private static func assignOverlapLanes(to blocks: [WeeklyScheduleBlock]) -> [WeeklyScheduleBlock] {
        var assigned: [WeeklyScheduleBlock] = []

        for block in blocks {
            guard let start = block.startAt,
                  let end = block.endAt else {
                var allDayBlock = block
                allDayBlock.overlapLane = 0
                allDayBlock.overlapGroupSize = 1
                assigned.append(allDayBlock)
                continue
            }

            let overlappingPrevious = assigned.filter { other in
                guard let otherStart = other.startAt, let otherEnd = other.endAt else {
                    return false
                }
                return start < otherEnd && otherStart < end
            }
            let usedLanes = Set(overlappingPrevious.map(\.overlapLane))
            let lane = firstAvailableLane(excluding: usedLanes)
            let groupSize = max(1, overlappingPrevious.count + 1)
            var next = block
            next.overlapLane = lane
            next.overlapGroupSize = groupSize
            assigned.append(next)

            // Overlap width is a visual invariant: update earlier direct overlaps
            // so later blocks do not make the first block look conflict-free.
            for index in assigned.indices.dropLast() {
                guard let otherStart = assigned[index].startAt,
                      let otherEnd = assigned[index].endAt,
                      start < otherEnd,
                      otherStart < end else {
                    continue
                }
                assigned[index].overlapGroupSize = max(assigned[index].overlapGroupSize, groupSize)
            }
        }

        return assigned
    }

    private static func firstAvailableLane(excluding usedLanes: Set<Int>) -> Int {
        var candidate = 0
        while usedLanes.contains(candidate) {
            candidate += 1
        }
        return candidate
    }

    private static func reminderProposalCount(for day: DailyWorkloadDay) -> Int {
        day.projectContributions
            .flatMap(\.tasks)
            .filter { $0.status != .done }
            .count
    }

    private static func loadLevel(
        for day: DailyWorkloadDay,
        blockCount: Int,
        reminderProposalCount: Int
    ) -> WeeklyScheduleLoadLevel {
        let pressure = day.openTaskCount + day.blockedTaskCount + max(0, blockCount - 2) + max(0, reminderProposalCount - 3)
        if day.overdueTaskCount > 0 || (day.blockedTaskCount > 0 && day.openTaskCount >= 2) || pressure >= 5 {
            return .overloaded
        }
        if pressure >= 3 {
            return .heavy
        }
        if pressure > 0 {
            return .focused
        }
        return .open
    }

    private static func focusForecast(for days: [WeeklyScheduleDay]) -> WeeklyScheduleFocusForecast {
        let overloaded = days.filter { $0.loadLevel == .overloaded }.map(\.dateKey)
        let heavy = days.filter { $0.loadLevel == .heavy }.map(\.dateKey)
        let completed = days.filter { $0.completionHistoryCount > 0 }.map(\.dateKey)
        let reminderCount = days.reduce(0) { $0 + $1.reminderProposalCount }
        let completionHistoryCount = days.reduce(0) { $0 + $1.completionHistoryCount }
        let state: WeeklyScheduleFocusForecastState = if !overloaded.isEmpty {
            .overloaded
        } else if !heavy.isEmpty {
            .heavy
        } else {
            .open
        }

        return WeeklyScheduleFocusForecast(
            state: state,
            overloadedDayKeys: overloaded,
            heavyDayKeys: heavy,
            completedDayKeys: completed,
            reminderProposalCount: reminderCount,
            completionHistoryCount: completionHistoryCount
        )
    }

    private static func completionHistoryCountsByDay(
        from snapshot: ProjectBoardSnapshot,
        calendar: Calendar
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        snapshot.projects
            .filter { !$0.isArchived && !$0.isCompleted && !isInboxProject($0) }
            .flatMap(\.tasks)
            .forEach { task in
                guard let completedDate = completedDate(task.completedAt, calendar: calendar) else {
                    return
                }
                counts[dateKey(for: completedDate, calendar: calendar), default: 0] += 1
            }
        return counts
    }

    private static func sortBlocks(_ lhs: WeeklyScheduleBlock, _ rhs: WeeklyScheduleBlock) -> Bool {
        switch (lhs.startAt, rhs.startAt) {
        case let (lhsStart?, rhsStart?):
            if lhsStart != rhsStart {
                return lhsStart < rhsStart
            }
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            break
        }

        if lhs.source != rhs.source {
            return lhs.source == .scheduleDraft
        }
        return lhs.task.id > rhs.task.id
    }

    private static func parseDate(_ raw: String?, calendar: Calendar) -> Date? {
        guard let raw else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private static func completedDate(_ raw: String?, calendar: Calendar) -> Date? {
        guard let raw else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: raw) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: raw) {
            return date
        }
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }

    private static func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }

    private static func isDateOnly(_ raw: String) -> Bool {
        raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func dateKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func timeLabel(start: Date, end: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }
}
