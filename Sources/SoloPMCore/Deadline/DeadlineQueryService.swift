import Foundation

public protocol DateProvider: Sendable {
    var now: Date { get }
}

public struct SystemDateProvider: DateProvider {
    public init() {}

    public var now: Date {
        Date()
    }
}

public enum DeadlineItemKind: String, Equatable, Sendable {
    case project
    case task

    fileprivate var sortOrder: Int {
        switch self {
        case .project:
            0
        case .task:
            1
        }
    }
}

public struct DeadlineItem: Equatable, Sendable {
    public var id: Int64
    public var kind: DeadlineItemKind
    public var title: String
    public var dueAt: Date
    public var priority: String?

    public init(id: Int64, kind: DeadlineItemKind, title: String, dueAt: Date, priority: String? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.dueAt = dueAt
        self.priority = priority
    }
}

public struct DeadlineSummary: Equatable, Sendable {
    public var today: [DeadlineItem]
    public var tomorrow: [DeadlineItem]
    public var nextThreeDays: [DeadlineItem]
    public var thisWeek: [DeadlineItem]
    public var overdue: [DeadlineItem]

    public init(
        today: [DeadlineItem] = [],
        tomorrow: [DeadlineItem] = [],
        nextThreeDays: [DeadlineItem] = [],
        thisWeek: [DeadlineItem] = [],
        overdue: [DeadlineItem] = []
    ) {
        self.today = today
        self.tomorrow = tomorrow
        self.nextThreeDays = nextThreeDays
        self.thisWeek = thisWeek
        self.overdue = overdue
    }
}

public final class DeadlineQueryService: @unchecked Sendable {
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func summary() throws -> DeadlineSummary {
        let items = try deadlineItems()
        let bounds = DayBounds(now: dateProvider.now, timeZoneIdentifier: settings.timeZoneIdentifier)

        return DeadlineSummary(
            today: items.inRange(bounds.todayStart, bounds.tomorrowStart),
            tomorrow: items.inRange(bounds.tomorrowStart, bounds.dayAfterTomorrowStart),
            nextThreeDays: items.inRange(bounds.todayStart, bounds.nextThreeDaysEnd),
            thisWeek: items.inRange(bounds.todayStart, bounds.thisWeekEnd),
            overdue: items.before(bounds.todayStart)
        )
    }

    private func deadlineItems() throws -> [DeadlineItem] {
        let projects = try projectStore.listDeadlineCandidates().compactMap { record -> DeadlineItem? in
            guard let deadline = record.deadline,
                  let dueAt = DateParser.iso8601(deadline) else {
                return nil
            }

            return DeadlineItem(id: record.id, kind: .project, title: record.title, dueAt: dueAt, priority: record.priority)
        }

        let tasks = try taskStore.listDeadlineCandidates().compactMap { record -> DeadlineItem? in
            guard let dueAtString = record.dueAt,
                  let dueAt = DateParser.iso8601(dueAtString) else {
                return nil
            }

            return DeadlineItem(id: record.id, kind: .task, title: record.title, dueAt: dueAt, priority: record.priority)
        }

        return (projects + tasks).deadlineSorted()
    }
}

private struct DayBounds {
    var todayStart: Date
    var tomorrowStart: Date
    var dayAfterTomorrowStart: Date
    var nextThreeDaysEnd: Date
    var thisWeekEnd: Date

    init(now: Date, timeZoneIdentifier: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        todayStart = calendar.startOfDay(for: now)
        tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        dayAfterTomorrowStart = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? tomorrowStart
        nextThreeDaysEnd = calendar.date(byAdding: .day, value: 3, to: todayStart) ?? dayAfterTomorrowStart
        thisWeekEnd = calendar.date(byAdding: .day, value: 7, to: todayStart) ?? nextThreeDaysEnd
    }
}

private enum DateParser {
    static func iso8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

private extension Array where Element == DeadlineItem {
    func inRange(_ lowerBound: Date, _ upperBound: Date) -> [DeadlineItem] {
        filter { $0.dueAt >= lowerBound && $0.dueAt < upperBound }.deadlineSorted()
    }

    func before(_ upperBound: Date) -> [DeadlineItem] {
        filter { $0.dueAt < upperBound }.deadlineSorted()
    }

    func deadlineSorted() -> [DeadlineItem] {
        sorted { lhs, rhs in
            if lhs.dueAt != rhs.dueAt {
                return lhs.dueAt < rhs.dueAt
            }
            if lhs.kind != rhs.kind {
                return lhs.kind.sortOrder < rhs.kind.sortOrder
            }
            return lhs.id < rhs.id
        }
    }
}
