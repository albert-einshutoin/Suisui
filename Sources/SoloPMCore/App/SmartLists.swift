import Foundation

/// Filter definition for a smart list. All criteria are ANDed together; a nil
/// field means "no constraint" for that dimension.
public struct SmartListCriteria: Codable, Equatable, Sendable {
    /// Task statuses to include. nil means every status matches.
    public var statuses: Set<ProjectTaskStatus>?
    /// Task priorities to include. nil means every priority matches.
    public var priorities: Set<ProjectTaskPriority>?
    /// Include only tasks whose due date falls in
    /// `startOfToday ..< startOfToday + dueWithinDays` (timezone aware).
    public var dueWithinDays: Int?
    /// Include only tasks whose due date is strictly before the start of today.
    public var overdueOnly: Bool
    /// Case-insensitive substring match against the task title or detail.
    public var searchText: String?

    public init(
        statuses: Set<ProjectTaskStatus>? = nil,
        priorities: Set<ProjectTaskPriority>? = nil,
        dueWithinDays: Int? = nil,
        overdueOnly: Bool = false,
        searchText: String? = nil
    ) {
        self.statuses = statuses
        self.priorities = priorities
        self.dueWithinDays = dueWithinDays
        self.overdueOnly = overdueOnly
        self.searchText = searchText
    }

    public func matches(
        _ task: ProjectBoardTask,
        project: ProjectBoardProject?,
        now: Date,
        timeZoneIdentifier: String
    ) -> Bool {
        // Archived projects are read-only surfaces; smart lists stay focused on
        // actionable work, matching the board's active sidebar behavior.
        if let project, project.isArchived {
            return false
        }
        if let statuses, !statuses.contains(task.status) {
            return false
        }
        if let priorities, !priorities.contains(task.priority) {
            return false
        }

        if overdueOnly || dueWithinDays != nil {
            guard let dueAt = task.dueAt,
                  let dueDate = DeadlineDateParser.date(from: dueAt, timeZoneIdentifier: timeZoneIdentifier) else {
                return false
            }
            let startOfToday = Self.startOfToday(now: now, timeZoneIdentifier: timeZoneIdentifier)
            if overdueOnly, dueDate >= startOfToday {
                return false
            }
            if let dueWithinDays {
                let calendar = Self.calendar(timeZoneIdentifier: timeZoneIdentifier)
                let upperBound = calendar.date(byAdding: .day, value: dueWithinDays, to: startOfToday) ?? startOfToday
                if dueDate < startOfToday || dueDate >= upperBound {
                    return false
                }
            }
        }

        if let searchText {
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let matchesTitle = task.title.range(of: query, options: [.caseInsensitive]) != nil
                let matchesDetail = task.detail.range(of: query, options: [.caseInsensitive]) != nil
                if !matchesTitle && !matchesDetail {
                    return false
                }
            }
        }

        return true
    }

    private static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    private static func startOfToday(now: Date, timeZoneIdentifier: String) -> Date {
        calendar(timeZoneIdentifier: timeZoneIdentifier).startOfDay(for: now)
    }
}

/// A user-visible saved filter over all board tasks. Built-in presets share
/// the same shape but are never persisted.
public struct SmartList: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var criteria: SmartListCriteria

    public init(id: String, name: String, criteria: SmartListCriteria) {
        self.id = id
        self.name = name
        self.criteria = criteria
    }

    /// Statuses that represent open (not completed) work.
    public static let openTaskStatuses: Set<ProjectTaskStatus> = [.backlog, .planned, .inProgress, .blocked]

    public static let dueThisWeekPresetID = "preset-due-this-week"
    public static let highPriorityPresetID = "preset-high-priority"
    public static let overduePresetID = "preset-overdue"

    /// Built-in smart lists. These are composed in code, never persisted, and
    /// always listed before user-saved lists.
    public static let presets: [SmartList] = [
        SmartList(
            id: dueThisWeekPresetID,
            name: "Due this week",
            criteria: SmartListCriteria(statuses: openTaskStatuses, dueWithinDays: 7)
        ),
        SmartList(
            id: highPriorityPresetID,
            name: "High priority",
            criteria: SmartListCriteria(statuses: openTaskStatuses, priorities: [.high])
        ),
        SmartList(
            id: overduePresetID,
            name: "Overdue",
            criteria: SmartListCriteria(statuses: openTaskStatuses, overdueOnly: true)
        )
    ]

    public var isPreset: Bool {
        id.hasPrefix("preset-")
    }

    /// Flattened, deterministically ordered tasks matching this list across
    /// every project in the snapshot: due date ascending (no due date last),
    /// then task ID for stability.
    public func matchingTasks(
        in snapshot: ProjectBoardSnapshot,
        now: Date,
        timeZoneIdentifier: String
    ) -> [ProjectBoardTask] {
        snapshot.projects
            .flatMap { project in
                project.tasks.filter { task in
                    criteria.matches(task, project: project, now: now, timeZoneIdentifier: timeZoneIdentifier)
                }
            }
            .sorted { lhs, rhs in
                let lhsDue = lhs.dueAt ?? "9999"
                let rhsDue = rhs.dueAt ?? "9999"
                if lhsDue != rhsDue {
                    return lhsDue < rhsDue
                }
                return lhs.id < rhs.id
            }
    }
}

public protocol SmartListStore: Sendable {
    func list() throws -> [SmartList]
    /// Inserts the list, or replaces the stored list with the same `id`.
    func save(_ smartList: SmartList) throws
    func delete(id: String) throws
}

/// File-backed smart list persistence. Smart lists are a small user-owned
/// collection, so a single JSON document in Application Support (mirroring
/// `FileExecutionReceiptStore`'s injected-directory style) is durable enough
/// and keeps them out of the SQLite schema.
public final class FileSmartListStore: SmartListStore, @unchecked Sendable {
    private static let fileName = "smart-lists.json"
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()

    public init(directoryURL: URL) throws {
        self.fileURL = directoryURL.appendingPathComponent(Self.fileName)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public func list() throws -> [SmartList] {
        lock.lock()
        defer { lock.unlock() }
        return try loadAll()
    }

    public func save(_ smartList: SmartList) throws {
        lock.lock()
        defer { lock.unlock() }
        var smartLists = try loadAll()
        if let existingIndex = smartLists.firstIndex(where: { $0.id == smartList.id }) {
            smartLists[existingIndex] = smartList
        } else {
            smartLists.append(smartList)
        }
        try write(smartLists)
    }

    public func delete(id: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var smartLists = try loadAll()
        smartLists.removeAll { $0.id == id }
        try write(smartLists)
    }

    private func loadAll() throws -> [SmartList] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }
        return try decoder.decode([SmartList].self, from: data)
    }

    private func write(_ smartLists: [SmartList]) throws {
        let data = try encoder.encode(smartLists)
        try data.write(to: fileURL, options: [.atomic])
    }
}
