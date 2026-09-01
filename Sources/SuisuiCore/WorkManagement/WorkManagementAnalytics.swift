import Foundation

enum WorkManagementAnalyticsBuilder {
    private static let heatmapWindowDays = 28

    static func projectPortfolioSummaries(
        projects: [ProjectBoardProject],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [ProjectPortfolioSummary] {
        projects
            .map { projectPortfolioSummary(for: $0, on: referenceDate, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.health.sortRank != rhs.health.sortRank {
                    return lhs.health.sortRank < rhs.health.sortRank
                }
                if lhs.overdueTaskCount != rhs.overdueTaskCount {
                    return lhs.overdueTaskCount > rhs.overdueTaskCount
                }
                return lhs.projectID > rhs.projectID
            }
    }

    static func doneAnalytics(
        completedProjects: [ProjectBoardProject],
        tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> DoneAnalyticsSummary {
        // Reopened tasks keep their completedAt timestamp so Done analytics can preserve actual completion history.
        let historyTasks = tasks.filter { task in task.completedAt != nil || task.status == .done }
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let rollingWeekStart = calendar.date(byAdding: .day, value: -6, to: dayInterval?.start ?? referenceDate) ?? referenceDate
        let completedTodayCount = historyTasks.filter { task in
            guard let dayInterval, let completedDate = completedDate(for: task) else {
                return false
            }
            return completedDate >= dayInterval.start && completedDate < dayInterval.end
        }.count
        let completedThisWeekCount = historyTasks.filter { task in
            guard let completedDate = completedDate(for: task) else {
                return false
            }
            return completedDate >= rollingWeekStart && completedDate <= referenceDate
        }.count
        let completedDates = historyTasks.compactMap(completedDate(for:))
        let completedCountsByDayStart = completedDates.reduce(into: [Date: Int]()) { partialResult, completedDate in
            guard let dayStart = calendar.dateInterval(of: .day, for: completedDate)?.start else {
                return
            }
            partialResult[dayStart, default: 0] += 1
        }
        let completedDayStarts = Set(completedCountsByDayStart.keys)
        let recentTasks = historyTasks
            .sorted { lhs, rhs in
                switch (completedDate(for: lhs), completedDate(for: rhs)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.id > rhs.id
                    }
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id > rhs.id
                }
            }

        return DoneAnalyticsSummary(
            completedTaskCount: historyTasks.count,
            completedProjectCount: completedProjects.count,
            completedTodayCount: completedTodayCount,
            completedThisWeekCount: completedThisWeekCount,
            streakDays: streakDays(
                from: completedDayStarts,
                on: referenceDate,
                calendar: calendar
            ),
            onTimeRate: onTimeRate(tasks: historyTasks, calendar: calendar),
            weeklyTrendBuckets: weeklyTrendBuckets(
                from: completedCountsByDayStart,
                on: referenceDate,
                calendar: calendar
            ),
            completionHeatmapBuckets: heatmapBuckets(
                from: completedCountsByDayStart,
                on: referenceDate,
                calendar: calendar
            ),
            bestWeekdaySummary: bestWeekdaySummary(from: completedDates, calendar: calendar),
            bestHourSummary: bestHourSummary(from: completedDates, calendar: calendar),
            recentTasks: Array(recentTasks.prefix(12)),
            localRuleInsight: "Done analytics uses local completed_at history; reopened tasks remain visible in completion history."
        )
    }

    static func completedDate(for task: ProjectBoardTask) -> Date? {
        guard let rawCompletedAt = task.completedAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawCompletedAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: rawCompletedAt) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawCompletedAt)
    }

    private static func heatmapBuckets(
        from completedCountsByDayStart: [Date: Int],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [DoneAnalyticsDayBucket] {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start,
              let firstDay = calendar.date(byAdding: .day, value: -(heatmapWindowDays - 1), to: referenceDayStart) else {
            return []
        }

        return (0..<heatmapWindowDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            return DoneAnalyticsDayBucket(
                dayKey: dayKey(for: day, calendar: calendar),
                completedCount: completedCountsByDayStart[day, default: 0]
            )
        }
    }

    private static func bestWeekdaySummary(
        from completedDates: [Date],
        calendar: Calendar
    ) -> DoneAnalyticsBestWeekdaySummary {
        let counts = completedDates.reduce(into: [Int: Int]()) { partialResult, date in
            partialResult[calendar.component(.weekday, from: date), default: 0] += 1
        }
        guard let bestWeekday = counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return .empty
        }

        return DoneAnalyticsBestWeekdaySummary(weekday: bestWeekday.key, completedCount: bestWeekday.value)
    }

    private static func bestHourSummary(
        from completedDates: [Date],
        calendar: Calendar
    ) -> DoneAnalyticsBestHourSummary {
        let counts = completedDates.reduce(into: [Int: Int]()) { partialResult, date in
            partialResult[calendar.component(.hour, from: date), default: 0] += 1
        }
        guard let bestHour = counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return .empty
        }

        return DoneAnalyticsBestHourSummary(
            hour: bestHour.key,
            timeOfDay: timeOfDay(for: bestHour.key),
            completedCount: bestHour.value
        )
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func timeOfDay(for hour: Int) -> DoneAnalyticsTimeOfDay {
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }

    private static func onTimeRate(tasks: [ProjectBoardTask], calendar: Calendar) -> Double? {
        let tasksWithDue = tasks.filter { $0.dueAt != nil && $0.completedAt != nil }
        guard !tasksWithDue.isEmpty else { return nil }
        let onTime = tasksWithDue.filter { task in
            guard let dueAt = task.dueAt,
                  let dueParsed = SuisuiTimestampDisplay.parse(dueAt),
                  let completedAt = task.completedAt,
                  let completedDate = SuisuiTimestampDisplay.parse(completedAt)?.date else {
                return false
            }
            let dueDeadline: Date
            if dueParsed.includesTime {
                dueDeadline = dueParsed.date
            } else {
                dueDeadline = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueParsed.date)) ?? dueParsed.date
            }
            return completedDate < dueDeadline
        }
        return Double(onTime.count) / Double(tasksWithDue.count)
    }

    private static func weeklyTrendBuckets(
        from completedCountsByDayStart: [Date: Int],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [DoneAnalyticsWeekBucket] {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start else {
            return []
        }
        return (0..<4).reversed().compactMap { weekOffset -> DoneAnalyticsWeekBucket? in
            guard let weekEnd = calendar.date(byAdding: .day, value: -(weekOffset * 7), to: referenceDayStart),
                  let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd) else {
                return nil
            }
            let count = (0..<7).reduce(0) { total, dayOffset in
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                    return total
                }
                return total + completedCountsByDayStart[day, default: 0]
            }
            return DoneAnalyticsWeekBucket(
                weekLabel: "\(4 - weekOffset)\(String(localized: "week suffix"))",
                completedCount: count
            )
        }
    }

    private static func streakDays(
        from completedDayStarts: Set<Date>,
        on referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start else {
            return 0
        }

        var streak = 0
        var cursor = referenceDayStart
        while completedDayStarts.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }

    private static func projectPortfolioSummary(
        for project: ProjectBoardProject,
        on referenceDate: Date,
        calendar: Calendar
    ) -> ProjectPortfolioSummary {
        let tasks = project.tasks
        let openTasks = tasks.filter { $0.status != .done }
        let doneTaskCount = tasks.count - openTasks.count
        let blockedTaskCount = openTasks.filter { $0.status == .blocked }.count
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let overdueTasks = openTasks.filter { task in
            dueDate(for: task.dueAt).map { $0 < dayStart } == true
        }
        let nextDueTask = openTasks
            .filter { dueDate(for: $0.dueAt) != nil }
            .sorted { lhs, rhs in
                let lhsDate = dueDate(for: lhs.dueAt) ?? .distantFuture
                let rhsDate = dueDate(for: rhs.dueAt) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.id > rhs.id
                }
                return lhsDate < rhsDate
            }
            .first
        let nextActionTask = openTasks
            .sorted { lhs, rhs in
                if lhs.status == .blocked && rhs.status != .blocked {
                    return true
                }
                if lhs.status != .blocked && rhs.status == .blocked {
                    return false
                }
                let lhsDate = dueDate(for: lhs.dueAt) ?? .distantFuture
                let rhsDate = dueDate(for: rhs.dueAt) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.id > rhs.id
                }
                return lhsDate < rhsDate
            }
            .first
        let progress = tasks.isEmpty ? 0 : Double(doneTaskCount) / Double(tasks.count)
        let health = projectPortfolioHealth(
            project: project,
            openTaskCount: openTasks.count,
            blockedTaskCount: blockedTaskCount,
            overdueTaskCount: overdueTasks.count,
            progress: progress
        )

        return ProjectPortfolioSummary(
            projectID: project.id,
            title: project.title,
            status: project.status,
            progress: progress,
            openTaskCount: openTasks.count,
            doneTaskCount: doneTaskCount,
            blockedTaskCount: blockedTaskCount,
            overdueTaskCount: overdueTasks.count,
            nextDueAt: nextDueTask?.dueAt,
            recentTaskID: tasks.map(\.id).max(),
            nextActionTitle: nextActionTask?.title ?? "No open tasks",
            health: health,
            riskReason: projectPortfolioRiskReason(
                health: health,
                blockedTaskCount: blockedTaskCount,
                overdueTaskCount: overdueTasks.count,
                progress: progress
            ),
            // The portfolio view must be explainable and work offline; keep this
            // deterministic instead of routing health through an LLM.
            localHealthRuleDescription: "Local Health prioritizes blocked tasks, then overdue work, then open task progress."
        )
    }

    private static func projectPortfolioHealth(
        project: ProjectBoardProject,
        openTaskCount: Int,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double
    ) -> ProjectPortfolioHealth {
        if project.isCompleted || (openTaskCount == 0 && progress > 0) {
            return .completed
        }
        if blockedTaskCount > 0 || overdueTaskCount > 0 {
            return .atRisk
        }
        if progress < 0.25 && openTaskCount > 0 {
            return .attention
        }
        return .onTrack
    }

    private static func projectPortfolioRiskReason(
        health: ProjectPortfolioHealth,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double
    ) -> String {
        var reasons: [String] = []
        if blockedTaskCount > 0 {
            reasons.append("\(blockedTaskCount) blocked")
        }
        if overdueTaskCount > 0 {
            reasons.append("\(overdueTaskCount) overdue")
        }
        if !reasons.isEmpty {
            return reasons.joined(separator: ", ")
        }
        switch health {
        case .completed:
            return "All tracked tasks are done."
        case .attention:
            return "Progress is below 25% with open work."
        case .onTrack:
            return "No blocked or overdue open tasks."
        case .atRisk:
            return "Local risk rule detected schedule pressure."
        }
    }

    private static func dueDate(for rawDueAt: String?) -> Date? {
        guard let rawDueAt else {
            return nil
        }
        if let date = ISO8601DateFormatter().date(from: rawDueAt) {
            return date
        }

        let formatter = DateFormatter()
        var parsingCalendar = Calendar(identifier: .gregorian)
        parsingCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        formatter.calendar = parsingCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = parsingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawDueAt)
    }
}

private extension ProjectPortfolioHealth {
    var sortRank: Int {
        switch self {
        case .atRisk:
            0
        case .attention:
            1
        case .onTrack:
            2
        case .completed:
            3
        }
    }
}
