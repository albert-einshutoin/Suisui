import Foundation

public enum SuisuiCLIReadOnlyError: Error, Equatable, LocalizedError {
    case missingTable(String, databasePath: String)

    public var errorDescription: String? {
        switch self {
        case let .missingTable(table, databasePath):
            "Suisui database at \(databasePath) is missing required table '\(table)'. Open the app once to run migrations."
        }
    }
}

public struct SuisuiCLIReadOnlyReporter {
    private let databaseURL: URL
    private let now: Date
    private let fileManager: FileManager

    public init(databaseURL: URL, now: Date = Date(), fileManager: FileManager = .default) {
        self.databaseURL = databaseURL
        self.now = now
        self.fileManager = fileManager
    }

    public func statusLines() throws -> [String] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return [
                "Suisui CLI status",
                "database: missing \(databaseURL.path)"
            ]
        }

        let connection = try openConnection(requiredTables: ["projects", "tasks", "knowledge_frames"])
        let dueTasks = try SQLiteTaskStore(connection: connection).listDue(onOrBefore: nowISO8601String())
        let knowledgeFrames = try SQLiteKnowledgeFrameStore(connection: connection).list()

        return [
            "Suisui CLI status",
            "database: \(databaseURL.path)",
            "projects active: \(try countRows(connection, sql: "SELECT COUNT(*) AS count FROM projects WHERE status = 'active';"))",
            "projects archived: \(try countRows(connection, sql: "SELECT COUNT(*) AS count FROM projects WHERE status = 'archived';"))",
            "tasks open: \(try countRows(connection, sql: activeOpenTaskCountSQL))",
            "tasks due: \(dueTasks.count)",
            "knowledge frames: \(knowledgeFrames.count)"
        ]
    }

    public func tasksDueLines() throws -> [String] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return [
                "Suisui tasks due",
                "database: missing \(databaseURL.path)"
            ]
        }

        let connection = try openConnection(requiredTables: ["projects", "tasks"])
        let tasks = try SQLiteTaskStore(connection: connection).listDue(onOrBefore: nowISO8601String())
        var lines = [
            "Suisui tasks due",
            "database: \(databaseURL.path)",
            "count: \(tasks.count)"
        ]

        if tasks.isEmpty {
            lines.append("No due tasks.")
        } else {
            lines.append(contentsOf: tasks.map(formatTaskLine))
        }

        return lines
    }

    public func framesSearchLines(query: String) throws -> [String] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return [
                "Suisui frames search",
                "database: missing \(databaseURL.path)",
                "query: \(query)"
            ]
        }

        let connection = try openConnection(requiredTables: ["knowledge_frames", "knowledge_frames_fts"])
        let frames = try SQLiteKnowledgeFrameStore(connection: connection).search(query: query)
        var lines = [
            "Suisui frames search",
            "database: \(databaseURL.path)",
            "query: \(query)",
            "count: \(frames.count)"
        ]

        if frames.isEmpty {
            lines.append("No matching frames.")
        } else {
            lines.append(contentsOf: frames.map { "- \($0.name)" })
        }

        return lines
    }

    private func openConnection(requiredTables: [String]) throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: databaseURL.path, readOnly: true)
        for table in requiredTables {
            guard try connection.tableExists(table) else {
                throw SuisuiCLIReadOnlyError.missingTable(table, databasePath: databaseURL.path)
            }
        }
        return connection
    }

    private func countRows(_ connection: SQLiteConnection, sql: String) throws -> Int {
        try Self.parseCountValue(try connection.queryRows(sql).first?["count"])
    }

    static func parseCountValue(_ value: String?, column: String = "count") throws -> Int {
        guard let value else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        guard let count = Int(value) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: value)
        }
        return count
    }

    private func nowISO8601String() -> String {
        ISO8601DateFormatter().string(from: now)
    }

    private func formatTaskLine(_ task: TaskRecord) -> String {
        var parts = ["- \(task.title)"]
        if let dueAt = task.dueAt {
            parts.append("due: \(dueAt)")
        }
        if let priority = task.priority {
            parts.append("priority: \(priority)")
        }
        return parts.joined(separator: " | ")
    }

    private var activeOpenTaskCountSQL: String {
        """
        SELECT COUNT(*) AS count FROM tasks
        LEFT JOIN projects ON tasks.project_id = projects.id
        WHERE tasks.status != 'completed'
          AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived');
        """
    }
}
