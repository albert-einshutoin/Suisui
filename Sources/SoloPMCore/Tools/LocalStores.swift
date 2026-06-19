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

public struct ProjectDeletionResult: Equatable, Sendable {
    public var project: ProjectRecord
    public var deletedTaskCount: Int
    public var deletedCalendarLinkCount: Int
    public var deletedReminderLinkCount: Int
    public var deletedDeadlineRuleCount: Int
    public var deletedArtifactCount: Int

    public init(
        project: ProjectRecord,
        deletedTaskCount: Int,
        deletedCalendarLinkCount: Int,
        deletedReminderLinkCount: Int,
        deletedDeadlineRuleCount: Int,
        deletedArtifactCount: Int
    ) {
        self.project = project
        self.deletedTaskCount = deletedTaskCount
        self.deletedCalendarLinkCount = deletedCalendarLinkCount
        self.deletedReminderLinkCount = deletedReminderLinkCount
        self.deletedDeadlineRuleCount = deletedDeadlineRuleCount
        self.deletedArtifactCount = deletedArtifactCount
    }
}

public struct TaskDeletionResult: Equatable, Sendable {
    public var task: TaskRecord
    public var deletedCalendarLinkCount: Int
    public var deletedReminderLinkCount: Int
    public var deletedDeadlineRuleCount: Int
    public var deletedArtifactCount: Int

    public init(
        task: TaskRecord,
        deletedCalendarLinkCount: Int,
        deletedReminderLinkCount: Int,
        deletedDeadlineRuleCount: Int,
        deletedArtifactCount: Int
    ) {
        self.task = task
        self.deletedCalendarLinkCount = deletedCalendarLinkCount
        self.deletedReminderLinkCount = deletedReminderLinkCount
        self.deletedDeadlineRuleCount = deletedDeadlineRuleCount
        self.deletedArtifactCount = deletedArtifactCount
    }
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

public enum NullableFieldUpdate<Value: Equatable & Sendable>: Equatable, Sendable {
    case unchanged
    case set(Value)
    case clear

    public func applying(to currentValue: Value?) -> Value? {
        switch self {
        case .unchanged:
            currentValue
        case .set(let value):
            value
        case .clear:
            nil
        }
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

public enum LocalStoreDecodingError: Error, Equatable, Sendable {
    case invalidStringArray(column: String)
    case invalidDoubleArray(column: String)
    case invalidStringMap(column: String)
    case inconsistentDimensions(column: String, expected: Int, actual: Int)
    case missingRequiredColumn(column: String)
    case invalidInt64(column: String, value: String)
    case invalidEnum(column: String, value: String)
    case invalidDate(column: String, value: String)
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
        let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .projectCreate)
        let tagsJSON = try SQL.jsonArray(tags, column: "projects.tags_json")

        try connection.execute(
            """
            INSERT INTO projects (title, status, priority, deadline, workspace_path, tags_json, source_command)
            VALUES (
              '\(SQL.escape(normalizedTitle))',
              'active',
              \(SQL.optional(priority)),
              \(SQL.optional(deadline)),
              \(SQL.optional(workspacePath)),
              '\(SQL.escape(tagsJSON))',
              \(SQL.optional(sourceCommand))
            );
            """
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func update(id: Int64, title: String? = nil, status: String? = nil) throws -> ProjectRecord {
        try updateFields(id: id, title: title, status: status)
    }

    func updateTitleForProjectBoard(id: Int64, title: String) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .projectUpdate)
        try connection.execute(
            """
            UPDATE projects
            SET title = '\(SQL.escape(normalizedTitle))',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = \(id);
            """
        )
        return try getForProjectBoardLocked(id: id)
    }

    func updateStatusForProjectBoard(id: Int64, status: String) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        let normalizedStatus = try StoreFieldValidation.projectStatus(status, tool: .projectUpdate)
        try connection.execute(
            """
            UPDATE projects
            SET status = '\(SQL.escape(normalizedStatus))',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = \(id);
            """
        )
        return try getForProjectBoardLocked(id: id)
    }

    public func updateFields(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        priority: NullableFieldUpdate<String> = .unchanged,
        deadline: NullableFieldUpdate<String> = .unchanged,
        workspacePath: NullableFieldUpdate<String> = .unchanged,
        tags: NullableFieldUpdate<[String]> = .unchanged
    ) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        if let title {
            let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .projectUpdate)
            assignments.append("title = '\(SQL.escape(normalizedTitle))'")
        }
        if let status {
            let normalizedStatus = try StoreFieldValidation.projectStatus(status, tool: .projectUpdate)
            assignments.append("status = '\(SQL.escape(normalizedStatus))'")
        }
        switch priority {
        case .unchanged:
            break
        case .set(let priority):
            let normalizedPriority = try StoreFieldValidation.requiredTrimmed(priority, argument: "priority", tool: .projectUpdate)
            assignments.append("priority = '\(SQL.escape(normalizedPriority))'")
        case .clear:
            assignments.append("priority = NULL")
        }
        switch deadline {
        case .unchanged:
            break
        case .set(let deadline):
            let normalizedDeadline = try StoreFieldValidation.requiredTrimmed(deadline, argument: "deadline", tool: .projectUpdate)
            assignments.append("deadline = '\(SQL.escape(normalizedDeadline))'")
        case .clear:
            assignments.append("deadline = NULL")
        }
        switch workspacePath {
        case .unchanged:
            break
        case .set(let workspacePath):
            let normalizedWorkspacePath = try StoreFieldValidation.requiredTrimmed(workspacePath, argument: "workspacePath", tool: .projectUpdate)
            assignments.append("workspace_path = '\(SQL.escape(normalizedWorkspacePath))'")
        case .clear:
            assignments.append("workspace_path = NULL")
        }
        switch tags {
        case .unchanged:
            break
        case .set(let tags):
            let normalizedTags = try StoreFieldValidation.trimmedStringArray(tags, argument: "tags", tool: .projectUpdate)
            let tagsJSON = try SQL.jsonArray(normalizedTags, column: "projects.tags_json")
            assignments.append("tags_json = '\(SQL.escape(tagsJSON))'")
        case .clear:
            assignments.append("tags_json = '[]'")
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

    func completeForProjectBoard(id: Int64, taskStore: SQLiteTaskStore) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        return try connection.transaction {
            try connection.execute(
                """
                UPDATE projects
                SET status = 'completed',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = \(id);
                """
            )
            let record = try getForProjectBoardLocked(id: id)
            _ = try taskStore.completeOpenTasks(projectID: id)
            return record
        }
    }

    public func complete(id: Int64, taskStore: SQLiteTaskStore) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        return try connection.transaction {
            try connection.execute(
                """
                UPDATE projects
                SET status = 'completed',
                    updated_at = CURRENT_TIMESTAMP
                WHERE id = \(id);
                """
            )
            let record = try getLocked(id: id)
            _ = try taskStore.completeOpenTasks(projectID: id)
            return record
        }
    }

    @discardableResult
    public func delete(id: Int64) throws -> ProjectDeletionResult {
        lock.lock()
        defer { lock.unlock() }

        let project = try getLocked(id: id)
        let childTaskPredicate = "project_id = \(id)"
        let linkedProjectOrTaskPredicate = "project_id = \(id) OR task_id IN (SELECT id FROM tasks WHERE project_id = \(id))"
        let taskDeadlinePredicate = "target_type = 'task' AND target_id IN (SELECT id FROM tasks WHERE project_id = \(id))"
        let projectDeadlinePredicate = "target_type = 'project' AND target_id = \(id)"
        let artifactPredicate = linkedProjectOrTaskPredicate

        let result = try ProjectDeletionResult(
            project: project,
            deletedTaskCount: rowCountLocked(table: "tasks", where: childTaskPredicate),
            deletedCalendarLinkCount: rowCountIfTableExistsLocked(table: "calendar_links", where: linkedProjectOrTaskPredicate),
            deletedReminderLinkCount: rowCountIfTableExistsLocked(table: "reminder_links", where: linkedProjectOrTaskPredicate),
            deletedDeadlineRuleCount: rowCountIfTableExistsLocked(table: "deadline_rules", where: "(\(projectDeadlinePredicate)) OR (\(taskDeadlinePredicate))"),
            deletedArtifactCount: rowCountIfTableExistsLocked(table: "artifacts", where: artifactPredicate)
        )

        try connection.transaction {
            try deleteRowsIfTableExistsLocked(table: "calendar_links", where: linkedProjectOrTaskPredicate)
            try deleteRowsIfTableExistsLocked(table: "reminder_links", where: linkedProjectOrTaskPredicate)
            try deleteRowsIfTableExistsLocked(table: "deadline_rules", where: "(\(projectDeadlinePredicate)) OR (\(taskDeadlinePredicate))")
            try deleteRowsIfTableExistsLocked(table: "artifacts", where: artifactPredicate)
            try connection.execute("DELETE FROM tasks WHERE \(childTaskPredicate);")
            try connection.execute("DELETE FROM projects WHERE id = \(id);")
        }

        return result
    }

    func deleteForProjectBoard(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try getForProjectBoardLocked(id: id)
        let childTaskPredicate = "project_id = \(id)"
        let linkedProjectOrTaskPredicate = "project_id = \(id) OR task_id IN (SELECT id FROM tasks WHERE project_id = \(id))"
        let taskDeadlinePredicate = "target_type = 'task' AND target_id IN (SELECT id FROM tasks WHERE project_id = \(id))"
        let projectDeadlinePredicate = "target_type = 'project' AND target_id = \(id)"
        let artifactPredicate = linkedProjectOrTaskPredicate

        try connection.transaction {
            try deleteRowsIfTableExistsLocked(table: "calendar_links", where: linkedProjectOrTaskPredicate)
            try deleteRowsIfTableExistsLocked(table: "reminder_links", where: linkedProjectOrTaskPredicate)
            try deleteRowsIfTableExistsLocked(table: "deadline_rules", where: "(\(projectDeadlinePredicate)) OR (\(taskDeadlinePredicate))")
            try deleteRowsIfTableExistsLocked(table: "artifacts", where: artifactPredicate)
            try connection.execute("DELETE FROM tasks WHERE \(childTaskPredicate);")
            try connection.execute("DELETE FROM projects WHERE id = \(id);")
        }
    }

    public func list(includeArchived: Bool = false) throws -> [ProjectRecord] {
        lock.lock()
        defer { lock.unlock() }

        let filter = includeArchived ? "" : "WHERE status != 'archived'"
        return try connection.queryRows("SELECT * FROM projects \(filter) ORDER BY id DESC;").map(ProjectRecord.init(row:))
    }

    func listForProjectBoard(includeArchived: Bool = false) throws -> [ProjectRecord] {
        lock.lock()
        defer { lock.unlock() }

        let filter = includeArchived ? "" : "WHERE status != 'archived'"
        return try connection.queryRows("SELECT * FROM projects \(filter) ORDER BY id DESC;").map(ProjectRecord.init(projectBoardRow:))
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

    func getForProjectBoard(id: Int64) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getForProjectBoardLocked(id: id)
    }

    private func getForProjectBoardLocked(id: Int64) throws -> ProjectRecord {
        guard let row = try connection.queryRows("SELECT * FROM projects WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.projectGet, "Project \(id) was not found.")
        }

        return try ProjectRecord(projectBoardRow: row)
    }

    private func getLocked(id: Int64) throws -> ProjectRecord {
        guard let row = try connection.queryRows("SELECT * FROM projects WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.projectGet, "Project \(id) was not found.")
        }

        return try ProjectRecord(row: row)
    }

    private func rowCountLocked(table: String, where predicate: String) throws -> Int {
        let countValue = try connection
            .queryRows("SELECT COUNT(*) AS count FROM \(table) WHERE \(predicate);")
            .first?["count"]
        return Int(try SQL.requiredInt64(countValue, column: "\(table).count"))
    }

    private func rowCountIfTableExistsLocked(table: String, where predicate: String) throws -> Int {
        guard try connection.tableExists(table) else {
            return 0
        }

        return try rowCountLocked(table: table, where: predicate)
    }

    private func deleteRowsIfTableExistsLocked(table: String, where predicate: String) throws {
        guard try connection.tableExists(table) else {
            return
        }

        try connection.execute("DELETE FROM \(table) WHERE \(predicate);")
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
            ),
            tool: .taskCreate
        )
    }

    public func createMany(_ drafts: [TaskCreateDraft]) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.transaction {
            try drafts.map { try insertLocked($0, tool: .taskBulkCreate) }
        }
    }

    private func insertLocked(_ draft: TaskCreateDraft, tool: ActionTool) throws -> TaskRecord {
        let normalizedTitle = try StoreFieldValidation.requiredTrimmed(draft.title, argument: "title", tool: tool)
        let normalizedStatus = try StoreFieldValidation.taskStatus(draft.status, tool: tool)
        try connection.execute(
            """
            INSERT INTO tasks (project_id, title, status, detail, due_at, priority, source_command)
            VALUES (
              \(draft.projectID.map(String.init) ?? "NULL"),
              '\(SQL.escape(normalizedTitle))',
              '\(SQL.escape(normalizedStatus))',
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
        try updateFields(
            id: id,
            title: title,
            status: status,
            detail: detail.map { .set($0) } ?? .unchanged,
            dueAt: dueAt.map { .set($0) } ?? .unchanged,
            priority: priority.map { .set($0) } ?? .unchanged,
            projectID: projectID.map { .set($0) } ?? .unchanged
        )
    }

    public func updateFields(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        detail: NullableFieldUpdate<String> = .unchanged,
        dueAt: NullableFieldUpdate<String> = .unchanged,
        priority: NullableFieldUpdate<String> = .unchanged,
        projectID: NullableFieldUpdate<Int64> = .unchanged
    ) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        if let title {
            let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .taskUpdate)
            assignments.append("title = '\(SQL.escape(normalizedTitle))'")
        }
        if let status {
            let normalizedStatus = try StoreFieldValidation.taskStatus(status, tool: .taskUpdate)
            assignments.append("status = '\(SQL.escape(normalizedStatus))'")
        }
        switch detail {
        case .unchanged:
            break
        case .set(let detail):
            assignments.append("detail = '\(SQL.escape(detail))'")
        case .clear:
            assignments.append("detail = NULL")
        }
        switch dueAt {
        case .unchanged:
            break
        case .set(let dueAt):
            assignments.append("due_at = '\(SQL.escape(dueAt))'")
        case .clear:
            assignments.append("due_at = NULL")
        }
        switch priority {
        case .unchanged:
            break
        case .set(let priority):
            assignments.append("priority = '\(SQL.escape(priority))'")
        case .clear:
            assignments.append("priority = NULL")
        }
        switch projectID {
        case .unchanged:
            break
        case .set(let projectID):
            assignments.append("project_id = \(projectID)")
        case .clear:
            assignments.append("project_id = NULL")
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

    @discardableResult
    public func delete(id: Int64) throws -> TaskDeletionResult {
        lock.lock()
        defer { lock.unlock() }

        let task = try getLocked(id: id)
        let taskPredicate = "task_id = \(id)"
        let deadlinePredicate = "target_type = 'task' AND target_id = \(id)"

        let result = try TaskDeletionResult(
            task: task,
            deletedCalendarLinkCount: rowCountIfTableExistsLocked(table: "calendar_links", where: taskPredicate),
            deletedReminderLinkCount: rowCountIfTableExistsLocked(table: "reminder_links", where: taskPredicate),
            deletedDeadlineRuleCount: rowCountIfTableExistsLocked(table: "deadline_rules", where: deadlinePredicate),
            deletedArtifactCount: rowCountIfTableExistsLocked(table: "artifacts", where: taskPredicate)
        )

        try connection.transaction {
            try deleteRowsIfTableExistsLocked(table: "calendar_links", where: taskPredicate)
            try deleteRowsIfTableExistsLocked(table: "reminder_links", where: taskPredicate)
            try deleteRowsIfTableExistsLocked(table: "deadline_rules", where: deadlinePredicate)
            try deleteRowsIfTableExistsLocked(table: "artifacts", where: taskPredicate)
            try connection.execute("DELETE FROM tasks WHERE id = \(id);")
        }

        return result
    }

    private func getLocked(id: Int64) throws -> TaskRecord {
        guard let row = try connection.queryRows("SELECT * FROM tasks WHERE id = \(id) LIMIT 1;").first else {
            throw ToolExecutionError.executionFailed(.taskUpdate, "Task \(id) was not found.")
        }

        return try TaskRecord(row: row)
    }

    private func rowCountLocked(table: String, where predicate: String) throws -> Int {
        let countValue = try connection
            .queryRows("SELECT COUNT(*) AS count FROM \(table) WHERE \(predicate);")
            .first?["count"]
        return Int(try SQL.requiredInt64(countValue, column: "\(table).count"))
    }

    private func rowCountIfTableExistsLocked(table: String, where predicate: String) throws -> Int {
        guard try connection.tableExists(table) else {
            return 0
        }

        return try rowCountLocked(table: table, where: predicate)
    }

    private func deleteRowsIfTableExistsLocked(table: String, where predicate: String) throws {
        guard try connection.tableExists(table) else {
            return
        }

        try connection.execute("DELETE FROM \(table) WHERE \(predicate);")
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
        return try NotificationRequestRecord(row: row)
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
        return try CalendarLinkRecord(row: row)
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
        return try ReminderLinkRecord(row: row)
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
        let normalizedName = try StoreFieldValidation.requiredTrimmed(name, argument: "name", tool: .frameCreate)
        let validatedBody = try StoreFieldValidation.requiredNonBlank(body, argument: "body", tool: .frameCreate)
        let triggersJSON = try SQL.jsonArray(triggers, column: "knowledge_frames.triggers_json")

        return try connection.transaction {
            try connection.execute(
                """
                INSERT INTO knowledge_frames (name, body, triggers_json)
                VALUES ('\(SQL.escape(normalizedName))', '\(SQL.escape(validatedBody))', '\(SQL.escape(triggersJSON))');
                """
            )
            let id = connection.lastInsertedRowID
            try connection.execute(
                """
                INSERT INTO knowledge_frames_fts (rowid, name, body)
                VALUES (\(id), '\(SQL.escape(normalizedName))', '\(SQL.escape(validatedBody))');
                """
            )

            return try getLocked(id: id)
        }
    }

    public func update(id: Int64, name: String? = nil, body: String? = nil, triggers: [String]? = nil) throws -> KnowledgeFrameRecord {
        lock.lock()
        defer { lock.unlock() }

        let oldRecord = try getLocked(id: id)
        var assignments: [String] = []
        if let name {
            let normalizedName = try StoreFieldValidation.requiredTrimmed(name, argument: "name", tool: .frameUpdate)
            assignments.append("name = '\(SQL.escape(normalizedName))'")
        }
        if let body {
            let validatedBody = try StoreFieldValidation.requiredNonBlank(body, argument: "body", tool: .frameUpdate)
            assignments.append("body = '\(SQL.escape(validatedBody))'")
        }
        if let triggers {
            let triggersJSON = try SQL.jsonArray(triggers, column: "knowledge_frames.triggers_json")
            assignments.append("triggers_json = '\(SQL.escape(triggersJSON))'")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        return try connection.transaction {
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
        try connection.transaction {
            try connection.execute(
                """
                INSERT INTO knowledge_frames_fts (knowledge_frames_fts, rowid, name, body)
                VALUES ('delete', \(id), '\(SQL.escape(record.name))', '\(SQL.escape(record.body))');
                """
            )
            try connection.execute("DELETE FROM knowledge_frames WHERE id = \(id);")
        }
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

        return try KnowledgeFrameRecord(row: row)
    }
}

private extension ProjectRecord {
    init(row: [String: String]) throws {
        let status = try StoreFieldValidation.persistedProjectStatus(
            try SQL.requiredString(row["status"], column: "projects.status"),
            column: "projects.status"
        )
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "projects.id"),
            title: try SQL.requiredString(row["title"], column: "projects.title"),
            status: status,
            priority: SQL.nilIfEmpty(row["priority"]),
            deadline: SQL.nilIfEmpty(row["deadline"]),
            workspacePath: SQL.nilIfEmpty(row["workspace_path"]),
            tags: try SQL.parseStringArray(
                try SQL.requiredString(row["tags_json"], column: "projects.tags_json"),
                column: "projects.tags_json"
            ),
            sourceCommand: SQL.nilIfEmpty(row["source_command"])
        )
    }

    init(projectBoardRow row: [String: String]) throws {
        let status = try StoreFieldValidation.persistedProjectStatus(
            try SQL.requiredString(row["status"], column: "projects.status"),
            column: "projects.status"
        )
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "projects.id"),
            title: try SQL.requiredString(row["title"], column: "projects.title"),
            status: status,
            priority: SQL.nilIfEmpty(row["priority"]),
            deadline: SQL.nilIfEmpty(row["deadline"]),
            workspacePath: SQL.nilIfEmpty(row["workspace_path"]),
            tags: [],
            sourceCommand: SQL.nilIfEmpty(row["source_command"])
        )
    }
}

private extension TaskRecord {
    init(row: [String: String]) throws {
        let status = try StoreFieldValidation.persistedTaskStatus(
            try SQL.requiredString(row["status"], column: "tasks.status"),
            column: "tasks.status"
        )
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "tasks.id"),
            projectID: try SQL.optionalInt64(row["project_id"], column: "tasks.project_id"),
            title: try SQL.requiredString(row["title"], column: "tasks.title"),
            status: status,
            dueAt: SQL.nilIfEmpty(row["due_at"]),
            priority: SQL.nilIfEmpty(row["priority"]),
            sourceCommand: SQL.nilIfEmpty(row["source_command"]),
            detail: SQL.nilIfEmpty(row["detail"])
        )
    }
}

private extension KnowledgeFrameRecord {
    init(row: [String: String]) throws {
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "knowledge_frames.id"),
            name: try SQL.requiredString(row["name"], column: "knowledge_frames.name"),
            body: try SQL.requiredString(row["body"], column: "knowledge_frames.body"),
            triggers: try SQL.parseStringArray(
                try SQL.requiredString(row["triggers_json"], column: "knowledge_frames.triggers_json"),
                column: "knowledge_frames.triggers_json"
            )
        )
    }
}

private extension NotificationRequestRecord {
    init(row: [String: String]) throws {
        let status = try StoreFieldValidation.persistedNotificationStatus(
            try SQL.requiredString(row["status"], column: "notification_requests.status"),
            column: "notification_requests.status"
        )
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "notification_requests.id"),
            requestID: try SQL.requiredString(row["request_id"], column: "notification_requests.request_id"),
            status: status,
            title: try SQL.requiredString(row["title"], column: "notification_requests.title"),
            scheduledAt: try SQL.requiredString(row["scheduled_at"], column: "notification_requests.scheduled_at"),
            externalNotificationID: SQL.nilIfEmpty(row["external_notification_id"]),
            failureReason: SQL.nilIfEmpty(row["failure_reason"])
        )
    }
}

private extension CalendarLinkRecord {
    init(row: [String: String]) throws {
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "calendar_links.id"),
            eventID: try SQL.requiredString(row["event_id"], column: "calendar_links.event_id"),
            projectID: try SQL.optionalInt64(row["project_id"], column: "calendar_links.project_id"),
            taskID: try SQL.optionalInt64(row["task_id"], column: "calendar_links.task_id"),
            title: SQL.nilIfEmpty(row["title"])
        )
    }
}

private extension ReminderLinkRecord {
    init(row: [String: String]) throws {
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "reminder_links.id"),
            reminderID: try SQL.requiredString(row["reminder_id"], column: "reminder_links.reminder_id"),
            projectID: try SQL.optionalInt64(row["project_id"], column: "reminder_links.project_id"),
            taskID: try SQL.optionalInt64(row["task_id"], column: "reminder_links.task_id"),
            title: SQL.nilIfEmpty(row["title"])
        )
    }
}

enum StoreFieldValidation {
    private static let projectStatuses = ["active", "completed", "archived"]
    private static let taskStatuses = ["open", "backlog", "planned", "in_progress", "blocked", "completed"]
    private static let notificationStatuses = ["pending", "scheduled", "failed"]
    private static let legacyTaskBacklogAlias = "to" + "do"

    static func requiredTrimmed(_ value: String, argument: String, tool: ActionTool) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(argument)' cannot be blank.")
        }
        return trimmed
    }

    static func requiredNonBlank(_ value: String, argument: String, tool: ActionTool) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument '\(argument)' cannot be blank.")
        }
        return value
    }

    static func trimmedStringArray(_ values: [String], argument: String, tool: ActionTool) throws -> [String] {
        try values.enumerated().map { index, value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ToolExecutionError.validationFailed(tool, "Argument '\(argument)[\(index)]' cannot be blank.")
            }
            return trimmed
        }
    }

    static func projectStatus(_ value: String, tool: ActionTool) throws -> String {
        let normalized = normalizedStatusKey(value)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument 'status' cannot be blank.")
        }
        guard projectStatuses.contains(normalized) else {
            throw ToolExecutionError.validationFailed(
                tool,
                "Argument 'status' must be one of \(projectStatuses.joined(separator: ", "))."
            )
        }
        return normalized
    }

    static func taskStatus(_ value: String, tool: ActionTool) throws -> String {
        let normalized = normalizedStatusKey(value)
        guard !normalized.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument 'status' cannot be blank.")
        }
        let canonical: String? = switch normalized {
        case "open":
            "open"
        case legacyTaskBacklogAlias, "backlog":
            "backlog"
        case "next", "planned":
            "planned"
        case "active", "doing", "in_progress":
            "in_progress"
        case "blocked":
            "blocked"
        case "closed", "done", "completed":
            "completed"
        default:
            nil
        }

        guard let canonical else {
            throw ToolExecutionError.validationFailed(
                tool,
                "Argument 'status' must be one of \(taskStatuses.joined(separator: ", "))."
            )
        }
        return canonical
    }

    private static func normalizedStatusKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    static func persistedProjectStatus(_ value: String, column: String) throws -> String {
        let normalized = normalizedStatusKey(value)
        guard projectStatuses.contains(normalized) else {
            throw LocalStoreDecodingError.invalidEnum(column: column, value: value)
        }
        return normalized
    }

    static func persistedTaskStatus(_ value: String, column: String) throws -> String {
        let normalized = normalizedStatusKey(value)
        guard taskStatuses.contains(normalized) else {
            throw LocalStoreDecodingError.invalidEnum(column: column, value: value)
        }
        return normalized
    }

    static func persistedNotificationStatus(_ value: String, column: String) throws -> String {
        let normalized = normalizedStatusKey(value)
        guard notificationStatuses.contains(normalized) else {
            throw LocalStoreDecodingError.invalidEnum(column: column, value: value)
        }
        return normalized
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

    static func jsonArray(_ values: [String], column: String) throws -> String {
        let data = try JSONEncoder().encode(values)
        guard let json = String(data: data, encoding: .utf8) else {
            throw DatabaseError.executeFailed("Could not encode \(column) as UTF-8 JSON.")
        }
        return json
    }

    static func parseStringArray(_ value: String, column: String) throws -> [String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            throw LocalStoreDecodingError.invalidStringArray(column: column)
        }
        return decoded
    }

    static func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        return value
    }

    static func requiredInt64(_ value: String?, column: String) throws -> Int64 {
        let required = try requiredString(value, column: column)
        guard let int = Int64(required) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: required)
        }
        return int
    }

    static func optionalInt64(_ value: String?, column: String) throws -> Int64? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !normalized.isEmpty else {
            return nil
        }
        guard let int = Int64(normalized) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: normalized)
        }
        return int
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
