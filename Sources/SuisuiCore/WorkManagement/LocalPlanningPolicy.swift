import Foundation

/// Deterministic workspace decisions. No view state, stores, or providers.
enum LocalPlanningPolicy {
    static func dueDate(for rawDueAt: String?, calendar: Calendar? = nil) -> Date? {
        guard let rawDueAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawDueAt) {
            return date
        }

        let formatter = DateFormatter()
        var parsingCalendar = Calendar(identifier: .gregorian)
        parsingCalendar.timeZone = calendar?.timeZone ?? TimeZone(secondsFromGMT: 0)!
        formatter.calendar = parsingCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = parsingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawDueAt)
    }

    private static func updatedDate(for rawUpdatedAt: String?) -> Date? {
        guard let rawUpdatedAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawUpdatedAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: rawUpdatedAt) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawUpdatedAt)
    }

    static func missedTaskReasons(
        for task: ProjectBoardTask,
        dayInterval: DateInterval,
        staleCutoff: Date
    ) -> [MissedTaskReviewReason] {
        var reasons: [MissedTaskReviewReason] = []
        let taskDueDate = dueDate(for: task.dueAt)
        if taskDueDate.map({ $0 < dayInterval.start }) == true {
            reasons.append(.overdue)
        } else if let taskDueDate, taskDueDate >= dayInterval.start && taskDueDate < dayInterval.end {
            reasons.append(.dueToday)
        }
        if task.status == .blocked {
            reasons.append(.blocked)
        }
        if task.dueAt == nil {
            reasons.append(.unscheduled)
        }
        if updatedDate(for: task.updatedAt).map({ $0 < staleCutoff }) == true {
            reasons.append(.stale)
        }
        return reasons
    }

    static func isImmediateMissedTask(_ item: MissedTaskReviewItem) -> Bool {
        item.reasons.contains(.overdue)
            || item.reasons.contains(.blocked)
            || item.reasons.contains(.unscheduled)
            || item.reasons.contains(.stale)
    }

    static func sortMissedTaskReviewItems(_ lhs: MissedTaskReviewItem, _ rhs: MissedTaskReviewItem) -> Bool {
        let lhsRank = missedTaskQueueRank(lhs)
        let rhsRank = missedTaskQueueRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.task.priority.sortRank != rhs.task.priority.sortRank {
            return lhs.task.priority.sortRank < rhs.task.priority.sortRank
        }
        let lhsDueDate = dueDate(for: lhs.task.dueAt) ?? .distantFuture
        let rhsDueDate = dueDate(for: rhs.task.dueAt) ?? .distantFuture
        if lhsDueDate != rhsDueDate {
            return lhsDueDate < rhsDueDate
        }
        return lhs.task.id > rhs.task.id
    }

    private static func missedTaskQueueRank(_ item: MissedTaskReviewItem) -> Int {
        if item.reasons.contains(.overdue) {
            return 0
        }
        if item.reasons.contains(.blocked) {
            return 1
        }
        if item.reasons.contains(.stale) {
            return 2
        }
        if item.reasons.contains(.unscheduled) {
            return 3
        }
        return 4
    }

    static func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }

    static func recommendedTodayTask(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> ProjectBoardTask? {
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let overdueTasks = tasks.filter { task in
            dueDate(for: task.dueAt, calendar: calendar).map { $0 < dayStart } == true
        }
        if let highPriorityOverdue = overdueTasks.first(where: { $0.priority == .high }) {
            return highPriorityOverdue
        }
        if let overdueTask = overdueTasks.first {
            return overdueTask
        }
        if let highPriorityTask = tasks.first(where: { $0.priority == .high }) {
            return highPriorityTask
        }
        return tasks.first
    }

    static func recommendationReason(
        for task: ProjectBoardTask?,
        on referenceDate: Date,
        calendar: Calendar
    ) -> String {
        guard let task else {
            return "No due work is scheduled for today."
        }

        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let isOverdue = dueDate(for: task.dueAt, calendar: calendar).map { $0 < dayStart } == true
        if isOverdue && task.priority == .high {
            return "Overdue high-priority work should be cleared first."
        }
        if isOverdue {
            return "Overdue work should be cleared before new tasks."
        }
        if task.priority == .high {
            return "High-priority work is the best first task."
        }
        return "Earliest due task keeps today on track."
    }

    static func prioritizedTodayTimeBlocks(
        plan: TodayWorkflowPlan,
        taskID: Int64?,
        referenceDate: Date,
        calendar: Calendar
    ) -> [TodayTimeBlock] {
        guard let taskID,
              let task = plan.tasks.first(where: { $0.id == taskID }) else {
            return plan.timeBlocks
        }

        // The rail action is an explicit user choice, so the draft must include
        // that task even when the normal recommendation order would place it later.
        return timeBlocks(
            for: orderedTimeBlockTasks(plan.tasks, recommendedTask: task),
            startingAt: referenceDate,
            calendar: calendar
        )
    }

    static func orderedTimeBlockTasks(
        _ tasks: [ProjectBoardTask],
        recommendedTask: ProjectBoardTask?
    ) -> [ProjectBoardTask] {
        guard let recommendedTask else {
            return tasks
        }

        return [recommendedTask] + tasks.filter { $0.id != recommendedTask.id }
    }

    static func timeBlocks(
        for tasks: [ProjectBoardTask],
        startingAt referenceDate: Date,
        calendar: Calendar
    ) -> [TodayTimeBlock] {
        let firstBlockStart = roundedTimeBlockStart(from: referenceDate, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = calendar.timeZone

        return tasks.prefix(4).enumerated().compactMap { offset, task in
            guard let start = calendar.date(byAdding: .minute, value: offset * 30, to: firstBlockStart),
                  let end = calendar.date(byAdding: .minute, value: 30, to: start) else {
                return nil
            }
            return TodayTimeBlock(
                label: "\(formatter.string(from: start))-\(formatter.string(from: end))",
                task: task,
                startAt: isoFormatter.string(from: start),
                endAt: isoFormatter.string(from: end)
            )
        }
    }

    static func scheduleDraftTimeBlock(
        for task: ProjectBoardTask,
        existingBlocks: [TodayTimeBlock],
        referenceDate: Date,
        calendar: Calendar
    ) -> TodayTimeBlock? {
        let isoFormatter = ISO8601DateFormatter()
        let nextStart = existingBlocks.last?.endAt.flatMap { isoFormatter.date(from: $0) }
            ?? calendar.date(
                byAdding: .minute,
                value: existingBlocks.count * 30,
                to: roundedTimeBlockStart(from: referenceDate, calendar: calendar)
            )
            ?? referenceDate
        return timeBlocks(
            for: [task],
            startingAt: nextStart,
            calendar: calendar
        ).first
    }

    private static func roundedTimeBlockStart(from referenceDate: Date, calendar: Calendar) -> Date {
        DailyPlanningReviewRefreshSchedule.roundedTimeBlockStart(
            from: referenceDate,
            calendar: calendar
        )
    }
}

extension ProjectTaskPriority {
    var sortRank: Int {
        switch self {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }
}
