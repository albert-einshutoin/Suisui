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
    public var detail: String?

    public init(
        id: Int64,
        projectID: Int64?,
        title: String,
        status: String,
        dueAt: String?,
        priority: String?,
        sourceCommand: String?,
        detail: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.status = status
        self.dueAt = dueAt
        self.priority = priority
        self.sourceCommand = sourceCommand
        self.detail = detail
    }
}

public struct TaskCreateDraft: Equatable, Sendable {
    public var title: String
    public var projectID: Int64?
    public var dueAt: String?
    public var priority: String?
    public var sourceCommand: String?
    public var status: String
    public var detail: String?

    public init(
        title: String,
        projectID: Int64? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        sourceCommand: String? = nil,
        status: String = "open",
        detail: String? = nil
    ) {
        self.title = title
        self.projectID = projectID
        self.dueAt = dueAt
        self.priority = priority
        self.sourceCommand = sourceCommand
        self.status = status
        self.detail = detail
    }
}

public struct KnowledgeFrameRecord: Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var body: String
    public var triggers: [String]
}

public struct NotificationRequestRecord: Equatable, Sendable {
    public var id: Int64
    public var requestID: String
    public var status: String
    public var title: String
    public var scheduledAt: String
    public var externalNotificationID: String?
    public var failureReason: String?
}

public struct CalendarLinkRecord: Equatable, Sendable {
    public var id: Int64
    public var eventID: String
    public var projectID: Int64?
    public var taskID: Int64?
    public var title: String?
}

public struct ReminderLinkRecord: Equatable, Sendable {
    public var id: Int64
    public var reminderID: String
    public var projectID: Int64?
    public var taskID: Int64?
    public var title: String?
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

    public func archive(id: Int64) throws -> ProjectRecord {
        try update(id: id, status: "archived")
    }

    public func restore(id: Int64) throws -> ProjectRecord {
        try update(id: id, status: "active")
    }

    public func list(includeArchived: Bool = false) throws -> [ProjectRecord] {
        lock.lock()
        defer { lock.unlock() }

        let filter = includeArchived ? "" : "WHERE status != 'archived'"
        return try connection.queryRows("SELECT * FROM projects \(filter) ORDER BY id DESC;").map(ProjectRecord.init(row:))
    }

    public func listDeadlineCandidates() throws -> [ProjectRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM projects
            WHERE status NOT IN ('completed', 'archived') AND deadline IS NOT NULL
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
        sourceCommand: String? = nil,
        status: String = "open",
        detail: String? = nil
    ) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        return try insertLocked(
            TaskCreateDraft(
                title: title,
                projectID: projectID,
                dueAt: dueAt,
                priority: priority,
                sourceCommand: sourceCommand,
                status: status,
                detail: detail
            )
        )
    }

    public func createMany(_ drafts: [TaskCreateDraft]) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.transaction {
            try drafts.map(insertLocked)
        }
    }

    private func insertLocked(_ draft: TaskCreateDraft) throws -> TaskRecord {
        try connection.execute(
            """
            INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command)
            VALUES (
              \(draft.projectID.map(String.init) ?? "NULL"),
              '\(SQL.escape(draft.title))',
              '\(SQL.escape(draft.status))',
              \(SQL.optional(draft.detail)),
              \(SQL.optional(draft.dueAt)),
              \(SQL.optional(draft.priority)),
              \(SQL.optional(draft.sourceCommand))
            );
            """
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func update(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        detail: String? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        projectID: Int64? = nil
    ) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        if let title {
            assignments.append("title = '\(SQL.escape(title))'")
        }
        if let status {
            assignments.append("status = '\(SQL.escape(status))'")
        }
        if let detail {
            assignments.append("detail = '\(SQL.escape(detail))'")
        }
        if let dueAt {
            assignments.append("due_at = '\(SQL.escape(dueAt))'")
        }
        if let priority {
            assignments.append("priority = '\(SQL.escape(priority))'")
        }
        if let projectID {
            assignments.append("project_id = \(projectID)")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        try connection.execute("UPDATE tasks SET \(assignments.joined(separator: ", ")) WHERE id = \(id);")
        return try getLocked(id: id)
    }

    public func listDue(onOrBefore cutoff: String) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection
            .queryRows(
                """
                SELECT tasks.* FROM tasks
                LEFT JOIN projects ON tasks.project_id = projects.id
                WHERE tasks.status != 'completed'
                  AND tasks.due_at IS NOT NULL
                  AND tasks.due_at <= '\(SQL.escape(cutoff))'
                  AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived')
                ORDER BY tasks.due_at ASC, tasks.id ASC;
                """
            )
            .map(TaskRecord.init(row:))
    }

    public func listAll() throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM tasks ORDER BY id ASC;").map(TaskRecord.init(row:))
    }

    public func listOverdue(before cutoff: String) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection
            .queryRows(
                """
                SELECT tasks.* FROM tasks
                LEFT JOIN projects ON tasks.project_id = projects.id
                WHERE tasks.status != 'completed'
                  AND tasks.due_at IS NOT NULL
                  AND tasks.due_at < '\(SQL.escape(cutoff))'
                  AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived')
                ORDER BY tasks.due_at ASC, tasks.id ASC;
                """
            )
            .map(TaskRecord.init(row:))
    }

    public func listDeadlineCandidates() throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT tasks.* FROM tasks
            LEFT JOIN projects ON tasks.project_id = projects.id
            WHERE tasks.status != 'completed'
              AND tasks.due_at IS NOT NULL
              AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived')
            ORDER BY tasks.due_at ASC, tasks.id ASC;
            """
        ).map(TaskRecord.init(row:))
    }

    public func completeOpenTasks(projectID: Int64) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            UPDATE tasks
            SET status = 'completed',
                updated_at = CURRENT_TIMESTAMP
            WHERE project_id = \(projectID)
              AND status != 'completed';
            """
        )

        return try connection
            .queryRows("SELECT * FROM tasks WHERE project_id = \(projectID) ORDER BY id ASC;")
            .map(TaskRecord.init(row:))
    }

    public func get(id: Int64) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    public func delete(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try getLocked(id: id)
        try connection.execute("DELETE FROM tasks WHERE id = \(id);")
    }

    private func getLocked(id: Int64) throws -> TaskRecord {
        guard let row = try connection.queryRows("SELECT * FROM tasks WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.taskUpdate, "Task \(id) was not found.")
        }

        return TaskRecord(row: row)
    }
}

public final class SQLiteNotificationRequestStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    @discardableResult
    public func createPending(requestID: String, title: String, scheduledAt: String) throws -> NotificationRequestRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO notification_requests (request_id, status, title, scheduled_at)
            VALUES ('\(SQL.escape(requestID))', 'pending', '\(SQL.escape(title))', '\(SQL.escape(scheduledAt))');
            """
        )
        return try getLocked(requestID: requestID)
    }

    @discardableResult
    public func markScheduled(requestID: String, externalNotificationID: String) throws -> NotificationRequestRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            UPDATE notification_requests
            SET status = 'scheduled',
                external_notification_id = '\(SQL.escape(externalNotificationID))',
                failure_reason = NULL,
                updated_at = CURRENT_TIMESTAMP
            WHERE request_id = '\(SQL.escape(requestID))';
            """
        )
        return try getLocked(requestID: requestID)
    }

    @discardableResult
    public func markFailed(requestID: String, reason: String) throws -> NotificationRequestRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            UPDATE notification_requests
            SET status = 'failed',
                failure_reason = '\(SQL.escape(reason))',
                updated_at = CURRENT_TIMESTAMP
            WHERE request_id = '\(SQL.escape(requestID))';
            """
        )
        return try getLocked(requestID: requestID)
    }

    public func list() throws -> [NotificationRequestRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM notification_requests ORDER BY id ASC;").map(NotificationRequestRecord.init(row:))
    }

    private func getLocked(requestID: String) throws -> NotificationRequestRecord {
        guard let row = try connection.queryRows(
            "SELECT * FROM notification_requests WHERE request_id = '\(SQL.escape(requestID))' LIMIT 1;"
        ).first else {
            throw DatabaseError.stepFailed("Notification request \(requestID) was not found.")
        }
        return NotificationRequestRecord(row: row)
    }
}

public final class SQLiteCalendarLinkStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    @discardableResult
    public func link(eventID: String, projectID: Int64? = nil, taskID: Int64? = nil, title: String? = nil) throws -> CalendarLinkRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO calendar_links (event_id, project_id, task_id, title)
            VALUES ('\(SQL.escape(eventID))', \(projectID.map(String.init) ?? "NULL"), \(taskID.map(String.init) ?? "NULL"), \(SQL.optional(title)));
            """
        )
        return try getLocked(eventID: eventID)
    }

    public func list() throws -> [CalendarLinkRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM calendar_links ORDER BY id ASC;").map(CalendarLinkRecord.init(row:))
    }

    private func getLocked(eventID: String) throws -> CalendarLinkRecord {
        guard let row = try connection.queryRows(
            "SELECT * FROM calendar_links WHERE event_id = '\(SQL.escape(eventID))' LIMIT 1;"
        ).first else {
            throw DatabaseError.stepFailed("Calendar link \(eventID) was not found.")
        }
        return CalendarLinkRecord(row: row)
    }
}

public final class SQLiteReminderLinkStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    @discardableResult
    public func link(reminderID: String, projectID: Int64? = nil, taskID: Int64? = nil, title: String? = nil) throws -> ReminderLinkRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO reminder_links (reminder_id, project_id, task_id, title)
            VALUES ('\(SQL.escape(reminderID))', \(projectID.map(String.init) ?? "NULL"), \(taskID.map(String.init) ?? "NULL"), \(SQL.optional(title)));
            """
        )
        return try getLocked(reminderID: reminderID)
    }

    public func list() throws -> [ReminderLinkRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM reminder_links ORDER BY id ASC;").map(ReminderLinkRecord.init(row:))
    }

    private func getLocked(reminderID: String) throws -> ReminderLinkRecord {
        guard let row = try connection.queryRows(
            "SELECT * FROM reminder_links WHERE reminder_id = '\(SQL.escape(reminderID))' LIMIT 1;"
        ).first else {
            throw DatabaseError.stepFailed("Reminder link \(reminderID) was not found.")
        }
        return ReminderLinkRecord(row: row)
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

        let oldRecord = try getLocked(id: id)
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

        try connection.execute(
            """
            INSERT INTO knowledge_frames_fts (knowledge_frames_fts, rowid, name, body)
            VALUES ('delete', \(id), '\(SQL.escape(oldRecord.name))', '\(SQL.escape(oldRecord.body))');
            """
        )
        try connection.execute("UPDATE knowledge_frames SET \(assignments.joined(separator: ", ")) WHERE id = \(id);")
        let record = try getLocked(id: id)
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

    public func delete(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        let record = try getLocked(id: id)
        try connection.execute(
            """
            INSERT INTO knowledge_frames_fts (knowledge_frames_fts, rowid, name, body)
            VALUES ('delete', \(id), '\(SQL.escape(record.name))', '\(SQL.escape(record.body))');
            """
        )
        try connection.execute("DELETE FROM knowledge_frames WHERE id = \(id);")
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
            sourceCommand: SQL.nilIfEmpty(row["source_command"]),
            detail: SQL.nilIfEmpty(row["detail"])
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

private extension NotificationRequestRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            requestID: row["request_id"] ?? "",
            status: row["status"] ?? "",
            title: row["title"] ?? "",
            scheduledAt: row["scheduled_at"] ?? "",
            externalNotificationID: SQL.nilIfEmpty(row["external_notification_id"]),
            failureReason: SQL.nilIfEmpty(row["failure_reason"])
        )
    }
}

private extension CalendarLinkRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            eventID: row["event_id"] ?? "",
            projectID: Int64(row["project_id"] ?? ""),
            taskID: Int64(row["task_id"] ?? ""),
            title: SQL.nilIfEmpty(row["title"])
        )
    }
}

private extension ReminderLinkRecord {
    init(row: [String: String]) {
        self.init(
            id: Int64(row["id"] ?? "") ?? 0,
            reminderID: row["reminder_id"] ?? "",
            projectID: Int64(row["project_id"] ?? ""),
            taskID: Int64(row["task_id"] ?? ""),
            title: SQL.nilIfEmpty(row["title"])
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
