import Foundation

public enum DoneHistorySection: String, CaseIterable, Hashable, Sendable {
    case today
    case yesterday
    case lastSevenDays
    case older
}

public struct DoneHistoryGroup: Equatable, Sendable {
    public var section: DoneHistorySection
    public var tasks: [ProjectBoardTask]

    public init(section: DoneHistorySection, tasks: [ProjectBoardTask]) {
        self.section = section
        self.tasks = tasks
    }
}

public enum DoneHistoryGrouping {
    public static func section(
        completedAt: Date?,
        now: Date,
        calendar: Calendar
    ) -> DoneHistorySection {
        guard let completedAt else {
            return .older
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfLastSevenDays = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday

        if completedAt >= startOfToday {
            return .today
        }
        if completedAt >= startOfYesterday {
            return .yesterday
        }
        if completedAt >= startOfLastSevenDays {
            return .lastSevenDays
        }
        return .older
    }

    public static func grouped(
        tasks: [ProjectBoardTask],
        now: Date,
        calendar: Calendar
    ) -> [DoneHistoryGroup] {
        var buckets: [DoneHistorySection: [ProjectBoardTask]] = [:]
        for task in tasks {
            let completedDate = task.completedAt.flatMap { SuisuiTimestampDisplay.parse($0, calendar: calendar)?.date }
            let section = section(completedAt: completedDate, now: now, calendar: calendar)
            buckets[section, default: []].append(task)
        }

        return DoneHistorySection.allCases.compactMap { section in
            guard let tasks = buckets[section], tasks.isEmpty == false else {
                return nil
            }
            return DoneHistoryGroup(section: section, tasks: tasks)
        }
    }
}
