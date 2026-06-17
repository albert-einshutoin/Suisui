import Foundation

public struct ProjectRecord: Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var status: String
    public var priority: String?
    public var deadline: String?
    public var workspacePath: String?
    public var tags: [String]
    public var sourceCommand: String?
}

public struct TaskRecord: Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64?
    public var title: String
    public var status: String
    public var dueAt: String?
    public var priority: String?
    public var sourceCommand: String?
}

public struct KnowledgeFrameRecord: Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var body: String
    public var triggers: [String]
}

public final class SQLiteProjectStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func create(
        title: String,
        priority: String? = nil,
        deadline: String? = nil,
        workspacePath: String? = nil,
        tags: [String] = [],
        sourceCommand: String? = nil
    ) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
            VALUES (
              '\(SQL.escape(title))',
              'active',
              \(SQL.optional(priority)),
              \(SQL.optional(deadline)),
              \(SQL.optional(workspacePath)),
              '\(SQL.escape(SQL.jsonArray(tags)))',
              \(SQL.optional(sourceCommand))
            );
            """
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func update(id: Int64, title: String? = nil, status: String? = nil) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        if let title {
            assignments.append("title = '\(SQL.escape(title))'")
        }
        if let status {
            assignments.append("status = '\(SQL.escape(status))'")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        try connection.execute("UPDATE projects SET \(assignments.joined(separator: ", ")) WHERE id = \(id);")
        return try getLocked(id: id)
    }

    public func list() throws -> [ProjectRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM projects ORDER BY id DESC;").map(ProjectRecord.init(row:))
    }

    public func listDeadlineCandidates() throws -> [ProjectRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM projects
            WHERE status != 'completed' AND deadline IS NOT NULL
            ORDER BY deadline ASC, id ASC;
            """
        ).map(ProjectRecord.init(row:))
    }

    public func get(id: Int64) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    private func getLocked(id: Int64) throws -> ProjectRecord {
        guard let row = try connection.queryRows("SELECT * FROM projects WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.projectGet, "Project \(id) was not found.")
        }

        return ProjectRecord(row: row)
    }
}

public final class SQLiteTaskStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func create(
        title: String,
        projectID: Int64? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        sourceCommand: String? = nil
    ) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO tasks (project_id, title, status, due_at, priority, source_command)
            VALUES (
              \(projectID.map(String.init) ?? "NULL"),
              '\(SQL.escape(title))',
              'open',
              \(SQL.optional(dueAt)),
              \(SQL.optional(priority)),
              \(SQL.optional(sourceCommand))
            );
            """
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func update(id: Int64, title: String? = nil, status: String? = nil) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        if let title {
            assignments.append("title = '\(SQL.escape(title))'")
        }
        if let status {
            assignments.append("status = '\(SQL.escape(status))'")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        try connection.execute("UPDATE tasks SET \(assignments.joined(separator: ", ")) WHERE id = \(id);")
        return try getLocked(id: id)
    }

    public func listDue(onOrBefore cutoff: String) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection
            .queryRows("SELECT * FROM tasks WHERE due_at IS NOT NULL AND due_at <= '\(SQL.escape(cutoff))' ORDER BY due_at ASC, id ASC;")
            .map(TaskRecord.init(row:))
    }

    public func listOverdue(before cutoff: String) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection
            .queryRows("SELECT * FROM tasks WHERE status != 'completed' AND due_at IS NOT NULL AND due_at < '\(SQL.escape(cutoff))' ORDER BY due_at ASC, id ASC;")
            .map(TaskRecord.init(row:))
    }

    public func listDeadlineCandidates() throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM tasks
            WHERE status != 'completed' AND due_at IS NOT NULL
            ORDER BY due_at ASC, id ASC;
            """
        ).map(TaskRecord.init(row:))
    }

    public func get(id: Int64) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    private func getLocked(id: Int64) throws -> TaskRecord {
        guard let row = try connection.queryRows("SELECT * FROM tasks WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.taskUpdate, "Task \(id) was not found.")
        }

        return TaskRecord(row: row)
    }
}

public final class SQLiteKnowledgeFrameStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func create(name: String, body: String, triggers: [String] = []) throws -> KnowledgeFrameRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO knowledge_frames (name, body, triggers_json)
            VALUES ('\(SQL.escape(name))', '\(SQL.escape(body))', '\(SQL.escape(SQL.jsonArray(triggers)))');
            """
        )
        let id = connection.lastInsertedRowID
        try connection.execute(
            """
            INSERT INTO knowledge_frames_fts (rowid, name, body)
            VALUES (\(id), '\(SQL.escape(name))', '\(SQL.escape(body))');
            """
        )

        return try getLocked(id: id)
    }

    public func update(id: Int64, name: String? = nil, body: String? = nil, triggers: [String]? = nil) throws -> KnowledgeFrameRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        if let name {
            assignments.append("name = '\(SQL.escape(name))'")
        }
        if let body {
            assignments.append("body = '\(SQL.escape(body))'")
        }
        if let triggers {
            assignments.append("triggers_json = '\(SQL.escape(SQL.jsonArray(triggers)))'")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        try connection.execute("UPDATE knowledge_frames SET \(assignments.joined(separator: ", ")) WHERE id = \(id);")
        let record = try getLocked(id: id)
        try connection.execute("DELETE FROM knowledge_frames_fts WHERE rowid = \(id);")
        try connection.execute(
            """
            INSERT INTO knowledge_frames_fts (rowid, name, body)
            VALUES (\(id), '\(SQL.escape(record.name))', '\(SQL.escape(record.body))');
            """
        )
        return record
    }

    public func get(id: Int64) throws -> KnowledgeFrameRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    public func list() throws -> [KnowledgeFrameRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM knowledge_frames ORDER BY id DESC;").map(KnowledgeFrameRecord.init(row:))
    }

    public func search(query: String) throws -> [KnowledgeFrameRecord] {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let match = "\"\(SQL.escapeFTS(trimmed))\""
        return try connection.queryRows(
            """
            SELECT knowledge_frames.*
            FROM knowledge_frames_fts
            JOIN knowledge_frames ON knowledge_frames_fts.rowid = knowledge_frames.id
            WHERE knowledge_frames_fts MATCH '\(SQL.escape(match))'
            ORDER BY rank;
            """
        ).map(KnowledgeFrameRecord.init(row:))
    }

    private func getLocked(id: Int64) throws -> KnowledgeFrameRecord {
        guard let row = try connection.queryRows("SELECT * FROM knowledge_frames WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.frameGet, "Knowledge frame \(id) was not found.")
        }

        return KnowledgeFrameRecord(row: row)
    }
}

private extension ProjectRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            title: row["title"] ?? "",
            status: row["status"] ?? "",
            priority: SQL.nilIfEmpty(row["priority"]),
            deadline: SQL.nilIfEmpty(row["deadline"]),
            workspacePath: SQL.nilIfEmpty(row["workspace_path"]),
            tags: SQL.parseStringArray(row["tags_json"] ?? "[]"),
            sourceCommand: SQL.nilIfEmpty(row["source_command"])
        )
    }
}

private extension TaskRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            projectID: Int64(row["project_id"] ?? ""),
            title: row["title"] ?? "",
            status: row["status"] ?? "",
            dueAt: SQL.nilIfEmpty(row["due_at"]),
            priority: SQL.nilIfEmpty(row["priority"]),
            sourceCommand: SQL.nilIfEmpty(row["source_command"])
        )
    }
}

private extension KnowledgeFrameRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            name: row["name"] ?? "",
            body: row["body"] ?? "",
            triggers: SQL.parseStringArray(row["triggers_json"] ?? "[]")
        )
    }
}

private enum SQL {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    static func optional(_ value: String?) -> String {
        guard let value else {
            return "NULL"
        }

        return "'\(escape(value))'"
    }

    static func jsonArray(_ values: [String]) -> String {
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func parseStringArray(_ value: String) -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return decoded
    }

    static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    static func escapeFTS(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "\"\"")
    }
}
