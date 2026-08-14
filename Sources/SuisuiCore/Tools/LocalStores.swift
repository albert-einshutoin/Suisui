import Foundation

public struct ProjectRecord: Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var status: String
    public var priority: String?
    public var deadline: String?
    public var workspacePath: String?
    public var workspaceBookmarkData: Data?
    public var tags: [String]
    public var sourceCommand: String?

    public init(
        id: Int64,
        title: String,
        status: String,
        priority: String? = nil,
        deadline: String? = nil,
        workspacePath: String? = nil,
        workspaceBookmarkData: Data? = nil,
        tags: [String] = [],
        sourceCommand: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.deadline = deadline
        self.workspacePath = workspacePath
        self.workspaceBookmarkData = workspaceBookmarkData
        self.tags = tags
        self.sourceCommand = sourceCommand
    }
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
    public var completedAt: String?
    public var priority: String?
    public var sourceCommand: String?
    public var detail: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var recurrence: String?
    public var mutationRevision: Int64

    public init(
        id: Int64,
        projectID: Int64?,
        title: String,
        status: String,
        dueAt: String?,
        completedAt: String? = nil,
        priority: String?,
        sourceCommand: String?,
        detail: String? = nil,
        updatedAt: String? = nil,
        recurrence: String? = nil
    ) {
        self.init(
            id: id,
            projectID: projectID,
            title: title,
            status: status,
            dueAt: dueAt,
            completedAt: completedAt,
            priority: priority,
            sourceCommand: sourceCommand,
            detail: detail,
            createdAt: nil,
            updatedAt: updatedAt,
            recurrence: recurrence,
            mutationRevision: 0
        )
    }

    public init(
        id: Int64,
        projectID: Int64?,
        title: String,
        status: String,
        dueAt: String?,
        completedAt: String? = nil,
        priority: String?,
        sourceCommand: String?,
        detail: String? = nil,
        createdAt: String?,
        updatedAt: String? = nil,
        recurrence: String? = nil,
        mutationRevision: Int64
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.status = status
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.priority = priority
        self.sourceCommand = sourceCommand
        self.detail = detail
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.recurrence = recurrence
        self.mutationRevision = mutationRevision
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
    public var recurrence: String?

    public init(
        title: String,
        projectID: Int64? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        sourceCommand: String? = nil,
        status: String = "open",
        detail: String? = nil,
        recurrence: String? = nil
    ) {
        self.title = title
        self.projectID = projectID
        self.dueAt = dueAt
        self.priority = priority
        self.sourceCommand = sourceCommand
        self.status = status
        self.detail = detail
        self.recurrence = recurrence
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

public final class SQLiteExternalTaskLinkStore: ExternalTaskLinkStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func link(
        providerID: String,
        externalID: String,
        taskID: Int64,
        projectID: Int64? = nil,
        title: String? = nil
    ) throws -> ExternalTaskLinkRecord {
        let normalizedProviderID = try StoreFieldValidation.requiredTrimmed(providerID, argument: "providerID", tool: .taskUpdate)
        let normalizedExternalID = try StoreFieldValidation.requiredTrimmed(externalID, argument: "externalID", tool: .taskUpdate)

        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO external_task_links (provider_id, external_id, task_id, project_id, title)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(provider_id, external_id) DO UPDATE SET
              task_id = excluded.task_id,
              project_id = excluded.project_id,
              title = excluded.title,
              updated_at = CURRENT_TIMESTAMP;
            """,
            parameters: [
                .text(normalizedProviderID),
                .text(normalizedExternalID),
                .integer(taskID),
                SQLiteValue(projectID),
                SQLiteValue(title)
            ]
        )

        return try getLocked(providerID: normalizedProviderID, externalID: normalizedExternalID)
    }

    public func link(providerID: String, externalID: String) throws -> ExternalTaskLinkRecord? {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM external_task_links
            WHERE provider_id = ?
              AND external_id = ?
            LIMIT 1;
            """,
            parameters: [.text(providerID), .text(externalID)]
        ).first.map(ExternalTaskLinkRecord.init(row:))
    }

    public func links(providerID: String, taskIDs: [Int64]) throws -> [ExternalTaskLinkRecord] {
        lock.lock()
        defer { lock.unlock() }

        let uniqueTaskIDs = Array(Set(taskIDs))
        guard !uniqueTaskIDs.isEmpty else {
            return []
        }

        let placeholders = Array(repeating: "?", count: uniqueTaskIDs.count).joined(separator: ", ")
        return try connection.queryRows(
            """
            SELECT * FROM external_task_links
            WHERE provider_id = ?
              AND task_id IN (\(placeholders))
            ORDER BY id ASC;
            """,
            parameters: [.text(providerID)] + uniqueTaskIDs.map(SQLiteValue.integer)
        ).map(ExternalTaskLinkRecord.init(row:))
    }

    public func links(providerID: String, externalIDs: [String]) throws -> [ExternalTaskLinkRecord] {
        lock.lock()
        defer { lock.unlock() }

        let uniqueExternalIDs = Array(Set(externalIDs))
        guard !uniqueExternalIDs.isEmpty else {
            return []
        }

        let sortedExternalIDs = uniqueExternalIDs.sorted()
        let placeholders = Array(repeating: "?", count: sortedExternalIDs.count).joined(separator: ", ")

        return try connection.queryRows(
            """
            SELECT * FROM external_task_links
            WHERE provider_id = ?
              AND external_id IN (\(placeholders))
            ORDER BY id ASC;
            """,
            parameters: [.text(providerID)] + sortedExternalIDs.map(SQLiteValue.text)
        ).map(ExternalTaskLinkRecord.init(row:))
    }

    public func link(providerID: String, taskID: Int64) throws -> ExternalTaskLinkRecord? {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM external_task_links
            WHERE provider_id = ?
              AND task_id = ?
            LIMIT 1;
            """,
            parameters: [.text(providerID), .integer(taskID)]
        ).first.map(ExternalTaskLinkRecord.init(row:))
    }

    public func list() throws -> [ExternalTaskLinkRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM external_task_links ORDER BY id ASC;").map(ExternalTaskLinkRecord.init(row:))
    }

    private func getLocked(providerID: String, externalID: String) throws -> ExternalTaskLinkRecord {
        guard let row = try connection.queryRows(
            """
            SELECT * FROM external_task_links
            WHERE provider_id = ?
              AND external_id = ?
            LIMIT 1;
            """,
            parameters: [.text(providerID), .text(externalID)]
        ).first else {
            throw DatabaseError.stepFailed("External task link \(providerID):\(externalID) was not found.")
        }
        return try ExternalTaskLinkRecord(row: row)
    }
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
        workspaceBookmarkData: Data? = nil,
        tags: [String] = [],
        sourceCommand: String? = nil
    ) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }
        let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .projectCreate)
        let tagsJSON = try SQL.jsonArray(tags, column: "projects.tags_json")

        try connection.execute(
            """
            INSERT INTO projects (title, status, priority, deadline, workspace_path, workspace_bookmark, tags_json, source_command)
            VALUES (?, 'active', ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                .text(normalizedTitle),
                SQLiteValue(priority),
                SQLiteValue(deadline),
                SQLiteValue(workspacePath),
                SQLiteValue(workspaceBookmarkData?.base64EncodedString()),
                .text(tagsJSON),
                SQLiteValue(sourceCommand)
            ]
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
            SET title = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?;
            """,
            parameters: [.text(normalizedTitle), .integer(id)]
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
            SET status = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?;
            """,
            parameters: [.text(normalizedStatus), .integer(id)]
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
        workspaceBookmarkData: NullableFieldUpdate<Data> = .unchanged,
        tags: NullableFieldUpdate<[String]> = .unchanged
    ) throws -> ProjectRecord {
        lock.lock()
        defer { lock.unlock() }

        var assignments: [String] = []
        var parameters: [SQLiteValue] = []
        if let title {
            let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .projectUpdate)
            assignments.append("title = ?")
            parameters.append(.text(normalizedTitle))
        }
        if let status {
            let normalizedStatus = try StoreFieldValidation.projectStatus(status, tool: .projectUpdate)
            assignments.append("status = ?")
            parameters.append(.text(normalizedStatus))
        }
        switch priority {
        case .unchanged:
            break
        case .set(let priority):
            let normalizedPriority = try StoreFieldValidation.requiredTrimmed(priority, argument: "priority", tool: .projectUpdate)
            assignments.append("priority = ?")
            parameters.append(.text(normalizedPriority))
        case .clear:
            assignments.append("priority = NULL")
        }
        switch deadline {
        case .unchanged:
            break
        case .set(let deadline):
            let normalizedDeadline = try StoreFieldValidation.requiredTrimmed(deadline, argument: "deadline", tool: .projectUpdate)
            assignments.append("deadline = ?")
            parameters.append(.text(normalizedDeadline))
        case .clear:
            assignments.append("deadline = NULL")
        }
        switch workspacePath {
        case .unchanged:
            break
        case .set(let workspacePath):
            let normalizedWorkspacePath = try StoreFieldValidation.requiredTrimmed(workspacePath, argument: "workspacePath", tool: .projectUpdate)
            assignments.append("workspace_path = ?")
            parameters.append(.text(normalizedWorkspacePath))
        case .clear:
            assignments.append("workspace_path = NULL")
        }
        switch workspaceBookmarkData {
        case .unchanged:
            break
        case .set(let workspaceBookmarkData):
            assignments.append("workspace_bookmark = ?")
            parameters.append(.text(workspaceBookmarkData.base64EncodedString()))
        case .clear:
            assignments.append("workspace_bookmark = NULL")
        }
        switch tags {
        case .unchanged:
            break
        case .set(let tags):
            let normalizedTags = try StoreFieldValidation.trimmedStringArray(tags, argument: "tags", tool: .projectUpdate)
            let tagsJSON = try SQL.jsonArray(normalizedTags, column: "projects.tags_json")
            assignments.append("tags_json = ?")
            parameters.append(.text(tagsJSON))
        case .clear:
            assignments.append("tags_json = '[]'")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        try connection.execute(
            "UPDATE projects SET \(assignments.joined(separator: ", ")) WHERE id = ?;",
            parameters: parameters + [.integer(id)]
        )
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
                WHERE id = ?;
                """,
                parameters: [.integer(id)]
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
                WHERE id = ?;
                """,
                parameters: [.integer(id)]
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
        let childTaskPredicate = "project_id = ?"
        let childTaskParameters: [SQLiteValue] = [.integer(id)]
        let linkedProjectOrTaskPredicate = "project_id = ? OR task_id IN (SELECT id FROM tasks WHERE project_id = ?)"
        let linkedProjectOrTaskParameters: [SQLiteValue] = [.integer(id), .integer(id)]
        let taskDeadlinePredicate = "target_type = 'task' AND target_id IN (SELECT id FROM tasks WHERE project_id = ?)"
        let projectDeadlinePredicate = "target_type = 'project' AND target_id = ?"
        let deadlineParameters: [SQLiteValue] = [.integer(id), .integer(id)]
        let artifactPredicate = linkedProjectOrTaskPredicate
        let artifactParameters = linkedProjectOrTaskParameters

        let result = try ProjectDeletionResult(
            project: project,
            deletedTaskCount: rowCountLocked(table: "tasks", where: childTaskPredicate, parameters: childTaskParameters),
            deletedCalendarLinkCount: rowCountIfTableExistsLocked(table: "calendar_links", where: linkedProjectOrTaskPredicate, parameters: linkedProjectOrTaskParameters),
            deletedReminderLinkCount: rowCountIfTableExistsLocked(table: "reminder_links", where: linkedProjectOrTaskPredicate, parameters: linkedProjectOrTaskParameters),
            deletedDeadlineRuleCount: rowCountIfTableExistsLocked(table: "deadline_rules", where: "(\(projectDeadlinePredicate)) OR (\(taskDeadlinePredicate))", parameters: deadlineParameters),
            deletedArtifactCount: rowCountIfTableExistsLocked(table: "artifacts", where: artifactPredicate, parameters: artifactParameters)
        )

        try connection.transaction {
            try deleteRowsIfTableExistsLocked(table: "calendar_links", where: linkedProjectOrTaskPredicate, parameters: linkedProjectOrTaskParameters)
            try deleteRowsIfTableExistsLocked(table: "reminder_links", where: linkedProjectOrTaskPredicate, parameters: linkedProjectOrTaskParameters)
            try deleteRowsIfTableExistsLocked(table: "deadline_rules", where: "(\(projectDeadlinePredicate)) OR (\(taskDeadlinePredicate))", parameters: deadlineParameters)
            try deleteRowsIfTableExistsLocked(table: "artifacts", where: artifactPredicate, parameters: artifactParameters)
            try connection.execute("DELETE FROM tasks WHERE \(childTaskPredicate);", parameters: childTaskParameters)
            try connection.execute("DELETE FROM projects WHERE id = ?;", parameters: [.integer(id)])
        }

        return result
    }

    func deleteForProjectBoard(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try getForProjectBoardLocked(id: id)
        let childTaskPredicate = "project_id = ?"
        let childTaskParameters: [SQLiteValue] = [.integer(id)]
        let linkedProjectOrTaskPredicate = "project_id = ? OR task_id IN (SELECT id FROM tasks WHERE project_id = ?)"
        let linkedProjectOrTaskParameters: [SQLiteValue] = [.integer(id), .integer(id)]
        let taskDeadlinePredicate = "target_type = 'task' AND target_id IN (SELECT id FROM tasks WHERE project_id = ?)"
        let projectDeadlinePredicate = "target_type = 'project' AND target_id = ?"
        let deadlineParameters: [SQLiteValue] = [.integer(id), .integer(id)]
        let artifactPredicate = linkedProjectOrTaskPredicate
        let artifactParameters = linkedProjectOrTaskParameters

        try connection.transaction {
            try deleteRowsIfTableExistsLocked(table: "calendar_links", where: linkedProjectOrTaskPredicate, parameters: linkedProjectOrTaskParameters)
            try deleteRowsIfTableExistsLocked(table: "reminder_links", where: linkedProjectOrTaskPredicate, parameters: linkedProjectOrTaskParameters)
            try deleteRowsIfTableExistsLocked(table: "deadline_rules", where: "(\(projectDeadlinePredicate)) OR (\(taskDeadlinePredicate))", parameters: deadlineParameters)
            try deleteRowsIfTableExistsLocked(table: "artifacts", where: artifactPredicate, parameters: artifactParameters)
            try connection.execute("DELETE FROM tasks WHERE \(childTaskPredicate);", parameters: childTaskParameters)
            try connection.execute("DELETE FROM projects WHERE id = ?;", parameters: [.integer(id)])
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

        let filter = includeArchived ? "" : "WHERE status IN ('active', 'completed')"
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
        guard let row = try connection.queryRows("SELECT * FROM projects WHERE id = ? LIMIT 1;", parameters: [.integer(id)]).first else {
            throw ToolExecutionError.executionFailed(.projectGet, "Project \(id) was not found.")
        }

        return try ProjectRecord(projectBoardRow: row)
    }

    private func getLocked(id: Int64) throws -> ProjectRecord {
        guard let row = try connection.queryRows("SELECT * FROM projects WHERE id = ? LIMIT 1;", parameters: [.integer(id)]).first else {
            throw ToolExecutionError.executionFailed(.projectGet, "Project \(id) was not found.")
        }

        return try ProjectRecord(row: row)
    }

    private func rowCountLocked(table: String, where predicate: String, parameters: [SQLiteValue]) throws -> Int {
        let countValue = try connection
            .queryRows("SELECT COUNT(*) AS count FROM \(table) WHERE \(predicate);", parameters: parameters)
            .first?["count"]
        return Int(try SQL.requiredInt64(countValue, column: "\(table).count"))
    }

    private func rowCountIfTableExistsLocked(table: String, where predicate: String, parameters: [SQLiteValue]) throws -> Int {
        guard try connection.tableExists(table) else {
            return 0
        }

        return try rowCountLocked(table: table, where: predicate, parameters: parameters)
    }

    private func deleteRowsIfTableExistsLocked(table: String, where predicate: String, parameters: [SQLiteValue]) throws {
        guard try connection.tableExists(table) else {
            return
        }

        try connection.execute("DELETE FROM \(table) WHERE \(predicate);", parameters: parameters)
    }
}

public final class SQLiteTaskStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    func withMutationTransaction<T>(
        _ body: () throws -> T
    ) throws -> T {
        try connection.transaction(body)
    }

    public func create(
        title: String,
        projectID: Int64? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        sourceCommand: String? = nil,
        status: String = "open",
        detail: String? = nil,
        recurrence: String? = nil
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
                detail: detail,
                recurrence: recurrence
            ),
            tool: .taskCreate
        )
    }

    /// Backup restore inserts completed tasks with their original completion
    /// timestamp instead of stamping "now", so Done analytics survive a
    /// restore. Only `WorkspaceBackupImporter` and the Project Board undo
    /// restore path (`SQLiteProjectBoardStore.restoreTask(from:)`) should use
    /// this entry point.
    public func createForBackupRestore(_ draft: TaskCreateDraft, completedAt: String?) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        let normalizedTitle = try StoreFieldValidation.requiredTrimmed(draft.title, argument: "title", tool: .taskCreate)
        let normalizedStatus = try StoreFieldValidation.taskStatus(draft.status, tool: .taskCreate)
        let normalizedRecurrence = try draft.recurrence.map { try StoreFieldValidation.taskRecurrence($0, tool: .taskCreate) }
        try connection.execute(
            """
            INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, recurrence)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                SQLiteValue(draft.projectID),
                .text(normalizedTitle),
                .text(normalizedStatus),
                SQLiteValue(draft.detail),
                SQLiteValue(draft.dueAt),
                SQLiteValue(normalizedStatus == "completed" ? completedAt : nil),
                SQLiteValue(draft.priority),
                SQLiteValue(draft.sourceCommand),
                SQLiteValue(normalizedRecurrence)
            ]
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    /// Command-palette content search over open task titles and details.
    /// The quoted FTS phrase keeps non-CJK input literal: FTS operators and
    /// wildcards are never interpreted as part of a command-palette query.
    public func searchOpenTasksByContent(text: String, limit: Int) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else {
            return []
        }

        if Self.containsCJK(trimmed) {
            return try searchOpenTasksByContainsLocked(text: trimmed, limit: limit)
        }

        let ftsCandidates = try connection.queryRows(
            """
            SELECT tasks.* FROM tasks
            JOIN tasks_fts ON tasks_fts.rowid = tasks.id
            LEFT JOIN projects ON projects.id = tasks.project_id
            WHERE tasks_fts MATCH ?
              AND tasks.status != 'completed'
              AND COALESCE(projects.status, 'active') != 'archived'
            ORDER BY tasks.id DESC
            LIMIT ?;
            """,
            parameters: [.text("\"\(SQL.escapeFTS(trimmed))\""), .integer(Int64(limit))]
        ).map(TaskRecord.init(row:))
        // FTS tokenization drops punctuation (for example, `%` in `50%`).
        // Confirm the original literal against source fields before its rows
        // consume the palette limit, then let the bounded fallback fill gaps.
        var matches = ftsCandidates.filter { Self.matchesLiteral($0, text: trimmed) }
        if matches.count < limit {
            // FTS tokenizes "invoice", so it cannot return the historical
            // literal substring query "voice". Complete the bounded result in
            // SQLite even when FTS already found whole-word matches.
            matches += try searchOpenTasksByContainsLocked(
                tokens: [trimmed],
                excludingIDs: Set(matches.map(\.id)),
                limit: limit - matches.count
            )
        }
        return matches
    }

    /// Workspace answers historically match any normalized token. Keep that
    /// behavior in SQLite so a large task history is never materialized only
    /// to discard most rows in Swift.
    func searchOpenTasks(matching tokens: [String], limit: Int) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard limit > 0 else {
            return []
        }
        let boundedTokens = Self.boundedSearchTokens(tokens)
        guard !boundedTokens.isEmpty else {
            return []
        }

        let ftsTerms = boundedTokens
            .filter { !Self.containsCJK($0) }
            .map { "\"\(SQL.escapeFTS($0))\"" }
        var records: [TaskRecord] = []
        var seenIDs = Set<Int64>()

        if !ftsTerms.isEmpty {
            // unicode61 removes diacritics, so FTS can broaden a literal
            // token. Confirm source fields before a false hit consumes a
            // workspace slot; the existing fallback fills the remainder.
            for record in try connection.queryRows(
                """
                SELECT tasks.* FROM tasks
                JOIN tasks_fts ON tasks_fts.rowid = tasks.id
                LEFT JOIN projects ON projects.id = tasks.project_id
                WHERE tasks_fts MATCH ?
                  AND tasks.status != 'completed'
                  AND COALESCE(projects.status, 'active') != 'archived'
                ORDER BY tasks.id ASC
                LIMIT ?;
                """,
                parameters: [.text(ftsTerms.joined(separator: " OR ")), .integer(Int64(limit))]
            ).map(TaskRecord.init(row:)) {
                guard boundedTokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                      seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }

        if records.count < limit {
            // Keep FTS-ranked exact hits first, then recover CJK and ASCII
            // substrings inside bounded SQLite queries; never materialize the
            // task history in Swift just to filter it.
            for record in try searchOpenTasksByContainsLocked(
                tokens: boundedTokens,
                excludingIDs: seenIDs,
                limit: limit - records.count
            ) where seenIDs.insert(record.id).inserted {
                records.append(record)
            }
        }

        return Array(records.prefix(limit))
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
        let normalizedRecurrence = try draft.recurrence.map { try StoreFieldValidation.taskRecurrence($0, tool: tool) }
        try connection.execute(
            """
            INSERT INTO tasks (project_id, title, status, detail, due_at, completed_at, priority, source_command, recurrence)
            VALUES (
              ?,
              ?,
              ?,
              ?,
              ?,
              \(normalizedStatus == "completed" ? "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')" : "NULL"),
              ?,
              ?,
              ?
            );
            """,
            parameters: [
                SQLiteValue(draft.projectID),
                .text(normalizedTitle),
                .text(normalizedStatus),
                SQLiteValue(draft.detail),
                SQLiteValue(draft.dueAt),
                SQLiteValue(draft.priority),
                SQLiteValue(draft.sourceCommand),
                SQLiteValue(normalizedRecurrence)
            ]
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

    public func update(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        detail: String? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        projectID: Int64? = nil,
        expectedSnapshotFingerprint: String
    ) throws -> TaskRecord {
        try updateFields(
            id: id,
            title: title,
            status: status,
            detail: detail.map { .set($0) } ?? .unchanged,
            dueAt: dueAt.map { .set($0) } ?? .unchanged,
            priority: priority.map { .set($0) } ?? .unchanged,
            projectID: projectID.map { .set($0) } ?? .unchanged,
            expectedSnapshotFingerprint: expectedSnapshotFingerprint
        )
    }

    public func updateFields(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        detail: NullableFieldUpdate<String> = .unchanged,
        dueAt: NullableFieldUpdate<String> = .unchanged,
        priority: NullableFieldUpdate<String> = .unchanged,
        projectID: NullableFieldUpdate<Int64> = .unchanged,
        recurrence: NullableFieldUpdate<String> = .unchanged
    ) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        return try updateFieldsLocked(
            id: id,
            title: title,
            status: status,
            detail: detail,
            dueAt: dueAt,
            priority: priority,
            projectID: projectID,
            recurrence: recurrence
        )
    }

    public func updateFields(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        detail: NullableFieldUpdate<String> = .unchanged,
        dueAt: NullableFieldUpdate<String> = .unchanged,
        priority: NullableFieldUpdate<String> = .unchanged,
        projectID: NullableFieldUpdate<Int64> = .unchanged,
        recurrence: NullableFieldUpdate<String> = .unchanged,
        expectedSnapshotFingerprint: String
    ) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }

        return try updateFieldsLocked(
            id: id,
            title: title,
            status: status,
            detail: detail,
            dueAt: dueAt,
            priority: priority,
            projectID: projectID,
            recurrence: recurrence,
            expectedSnapshotFingerprint: expectedSnapshotFingerprint
        )
    }

    // The store lock is not reentrant, so composed operations such as
    // completeAndRegenerate share this locked implementation instead of
    // re-entering the public updateFields entry point.
    private func updateFieldsLocked(
        id: Int64,
        title: String? = nil,
        status: String? = nil,
        detail: NullableFieldUpdate<String> = .unchanged,
        dueAt: NullableFieldUpdate<String> = .unchanged,
        priority: NullableFieldUpdate<String> = .unchanged,
        projectID: NullableFieldUpdate<Int64> = .unchanged,
        recurrence: NullableFieldUpdate<String> = .unchanged,
        expectedSnapshotFingerprint: String? = nil
    ) throws -> TaskRecord {
        let expectedMutationRevision: Int64?
        if let expectedSnapshotFingerprint {
            let current = try getLocked(id: id)
            guard ConversationTaskSnapshotFingerprint.make(current)
                    == expectedSnapshotFingerprint
            else {
                throw TaskSnapshotConflictError(taskID: id)
            }
            expectedMutationRevision = current.mutationRevision
        } else {
            expectedMutationRevision = nil
        }
        var assignments: [String] = []
        var parameters: [SQLiteValue] = []
        if let title {
            let normalizedTitle = try StoreFieldValidation.requiredTrimmed(title, argument: "title", tool: .taskUpdate)
            assignments.append("title = ?")
            parameters.append(.text(normalizedTitle))
        }
        if let status {
            let normalizedStatus = try StoreFieldValidation.taskStatus(status, tool: .taskUpdate)
            assignments.append("status = ?")
            parameters.append(.text(normalizedStatus))
            if normalizedStatus == "completed" {
                // Completion history is intentionally write-once so reopened tasks still appear in Done analytics.
                assignments.append("completed_at = COALESCE(completed_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))")
            }
        }
        switch detail {
        case .unchanged:
            break
        case .set(let detail):
            assignments.append("detail = ?")
            parameters.append(.text(detail))
        case .clear:
            assignments.append("detail = NULL")
        }
        switch dueAt {
        case .unchanged:
            break
        case .set(let dueAt):
            assignments.append("due_at = ?")
            parameters.append(.text(dueAt))
        case .clear:
            assignments.append("due_at = NULL")
        }
        switch priority {
        case .unchanged:
            break
        case .set(let priority):
            assignments.append("priority = ?")
            parameters.append(.text(priority))
        case .clear:
            assignments.append("priority = NULL")
        }
        switch projectID {
        case .unchanged:
            break
        case .set(let projectID):
            assignments.append("project_id = ?")
            parameters.append(.integer(projectID))
        case .clear:
            assignments.append("project_id = NULL")
        }
        switch recurrence {
        case .unchanged:
            break
        case .set(let recurrence):
            let normalizedRecurrence = try StoreFieldValidation.taskRecurrence(recurrence, tool: .taskUpdate)
            assignments.append("recurrence = ?")
            parameters.append(.text(normalizedRecurrence))
        case .clear:
            assignments.append("recurrence = NULL")
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")
        assignments.append("mutation_revision = mutation_revision + 1")

        var predicate = "id = ?"
        var predicateParameters: [SQLiteValue] = [.integer(id)]
        if let expectedMutationRevision {
            predicate += " AND mutation_revision = ?"
            predicateParameters.append(.integer(expectedMutationRevision))
        }
        try connection.execute(
            "UPDATE tasks SET \(assignments.joined(separator: ", ")) WHERE \(predicate);",
            parameters: parameters + predicateParameters
        )
        guard expectedMutationRevision == nil
                || connection.numberOfChanges == 1
        else {
            // The revision comparison is part of the UPDATE itself. A Task
            // changed after review can therefore never be overwritten between
            // the preflight fingerprint read and the actual SQLite write.
            throw TaskSnapshotConflictError(taskID: id)
        }
        return try getLocked(id: id)
    }

    /// Marks a task completed and, when the completed record carries a
    /// recurrence, inserts the next occurrence in the same locked scope.
    ///
    /// This is the completion entry point for user-driven flows (board moves,
    /// inspector saves that transition to done, notification actions). The
    /// LLM-facing taskUpdate tool intentionally keeps calling updateFields, so
    /// model-driven status edits never regenerate occurrences.
    ///
    /// No explicit SQL transaction is opened here: SQLiteConnection.transaction
    /// issues a plain BEGIN and callers such as moveTasks already wrap this in
    /// an outer transaction, so nesting would fail. The store lock serializes
    /// the two statements instead, matching how completeOpenTasks composes.
    @discardableResult
    public func completeAndRegenerate(
        id: Int64,
        now: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) throws -> (completed: TaskRecord, regenerated: TaskRecord?) {
        lock.lock()
        defer { lock.unlock() }

        let completed = try updateFieldsLocked(id: id, status: "completed")
        guard let draft = TaskRecurrenceRegenerator.regenerationDraft(
            for: completed,
            completedAt: now,
            timeZoneIdentifier: timeZoneIdentifier
        ) else {
            return (completed, nil)
        }

        let regenerated = try insertLocked(draft, tool: .taskCreate)
        return (completed, regenerated)
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
                  AND tasks.due_at <= ?
                  AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived')
                ORDER BY tasks.due_at ASC, tasks.id ASC;
                """,
                parameters: [.text(cutoff)]
            )
            .map(TaskRecord.init(row:))
    }

    public func listAll() throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows("SELECT * FROM tasks ORDER BY id ASC;").map(TaskRecord.init(row:))
    }

    func listForProjectBoard() throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        // Project Board immediately groups by project. Reading in project-id
        // order lets SQLite use the work-management index and avoids an
        // unrelated id-order sort before the in-memory board indexes are built.
        return try connection
            .queryRows("SELECT * FROM tasks ORDER BY project_id ASC, id ASC;")
            .map(TaskRecord.init(row:))
    }

    func listForProjectBoard(projectIDs: Set<Int64>, includeDanglingReferences: Bool) throws -> [TaskRecord] {
        lock.lock()
        defer { lock.unlock() }

        var recordsByID: [Int64: TaskRecord] = [:]
        if !projectIDs.isEmpty {
            let sortedProjectIDs = projectIDs.sorted()
            let placeholders = Array(repeating: "?", count: sortedProjectIDs.count).joined(separator: ", ")
            for record in try projectBoardRows(
                where: "project_id IN (\(placeholders))",
                parameters: sortedProjectIDs.map(SQLiteValue.integer)
            ) {
                recordsByID[record.id] = record
            }
        }
        for record in try projectBoardRows(where: "project_id IS NULL") {
            recordsByID[record.id] = record
        }
        if includeDanglingReferences {
            for record in try projectBoardRows(
                where: "project_id IS NOT NULL AND project_id NOT IN (SELECT id FROM projects)"
            ) {
                recordsByID[record.id] = record
            }
        }

        // Separate predicates keep SQLite on indexed SEARCH plans. A single OR
        // query is easier to read but regresses large archived histories into a
        // broad index scan before the active board can render.
        return recordsByID.values.sorted(by: Self.sortForProjectBoard)
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
                  AND tasks.due_at < ?
                  AND COALESCE(projects.status, 'active') NOT IN ('completed', 'archived')
                ORDER BY tasks.due_at ASC, tasks.id ASC;
                """,
                parameters: [.text(cutoff)]
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
                completed_at = COALESCE(completed_at, strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
                updated_at = CURRENT_TIMESTAMP,
                mutation_revision = mutation_revision + 1
            WHERE project_id = ?
              AND status != 'completed';
            """,
            parameters: [.integer(projectID)]
        )

        return try connection
            .queryRows("SELECT * FROM tasks WHERE project_id = ? ORDER BY id ASC;", parameters: [.integer(projectID)])
            .map(TaskRecord.init(row:))
    }

    public func get(id: Int64) throws -> TaskRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    public func exists(id: Int64) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return try !connection.queryStrings(
            "SELECT id FROM tasks WHERE id = ? LIMIT 1;",
            parameters: [.integer(id)]
        ).isEmpty
    }

    public func completedCount(since: String, until: String) throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        let value = try connection.queryStrings(
            """
            SELECT COUNT(*) FROM tasks
            WHERE completed_at IS NOT NULL
              AND completed_at >= ?
              AND completed_at < ?;
            """,
            parameters: [.text(since), .text(until)]
        ).first
        return value.flatMap(Int.init) ?? 0
    }

    public func openCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        let value = try connection.queryStrings(
            "SELECT COUNT(*) FROM tasks WHERE status != 'completed';"
        ).first
        return value.flatMap(Int.init) ?? 0
    }

    @discardableResult
    public func delete(id: Int64) throws -> TaskDeletionResult {
        try delete(id: id, expectedSnapshotFingerprint: nil)
    }

    public func delete(
        id: Int64,
        expectedSnapshotFingerprint: String
    ) throws -> TaskDeletionResult {
        try delete(
            id: id,
            expectedSnapshotFingerprint:
                Optional(expectedSnapshotFingerprint)
        )
    }

    private func delete(
        id: Int64,
        expectedSnapshotFingerprint: String?
    ) throws -> TaskDeletionResult {
        lock.lock()
        defer { lock.unlock() }

        let task = try getLocked(id: id)
        if let expectedSnapshotFingerprint,
           ConversationTaskSnapshotFingerprint.make(task)
            != expectedSnapshotFingerprint {
            throw TaskSnapshotConflictError(taskID: id)
        }
        let taskPredicate = "task_id = ?"
        let taskParameters: [SQLiteValue] = [.integer(id)]
        let deadlinePredicate = "target_type = 'task' AND target_id = ?"
        let deadlineParameters: [SQLiteValue] = [.integer(id)]

        let result = try TaskDeletionResult(
            task: task,
            deletedCalendarLinkCount: rowCountIfTableExistsLocked(table: "calendar_links", where: taskPredicate, parameters: taskParameters),
            deletedReminderLinkCount: rowCountIfTableExistsLocked(table: "reminder_links", where: taskPredicate, parameters: taskParameters),
            deletedDeadlineRuleCount: rowCountIfTableExistsLocked(table: "deadline_rules", where: deadlinePredicate, parameters: deadlineParameters),
            deletedArtifactCount: rowCountIfTableExistsLocked(table: "artifacts", where: taskPredicate, parameters: taskParameters)
        )

        try connection.transaction {
            try deleteRowsIfTableExistsLocked(table: "calendar_links", where: taskPredicate, parameters: taskParameters)
            try deleteRowsIfTableExistsLocked(table: "reminder_links", where: taskPredicate, parameters: taskParameters)
            try deleteRowsIfTableExistsLocked(table: "deadline_rules", where: deadlinePredicate, parameters: deadlineParameters)
            try deleteRowsIfTableExistsLocked(table: "artifacts", where: taskPredicate, parameters: taskParameters)
            var predicate = "id = ?"
            var parameters: [SQLiteValue] = [.integer(id)]
            if expectedSnapshotFingerprint != nil {
                predicate += " AND mutation_revision = ?"
                parameters.append(.integer(task.mutationRevision))
            }
            try connection.execute(
                "DELETE FROM tasks WHERE \(predicate);",
                parameters: parameters
            )
            guard expectedSnapshotFingerprint == nil
                    || connection.numberOfChanges == 1
            else {
                // Rolling back the transaction also restores linked rows that
                // were removed before a competing Task revision was detected.
                throw TaskSnapshotConflictError(taskID: id)
            }
        }

        return result
    }

    private func getLocked(id: Int64) throws -> TaskRecord {
        guard let row = try connection.queryRows("SELECT * FROM tasks WHERE id = ? LIMIT 1;", parameters: [.integer(id)]).first else {
            throw ToolExecutionError.executionFailed(.taskUpdate, "Task \(id) was not found.")
        }

        return try TaskRecord(row: row)
    }

    private func rowCountLocked(table: String, where predicate: String, parameters: [SQLiteValue]) throws -> Int {
        let countValue = try connection
            .queryRows("SELECT COUNT(*) AS count FROM \(table) WHERE \(predicate);", parameters: parameters)
            .first?["count"]
        return Int(try SQL.requiredInt64(countValue, column: "\(table).count"))
    }

    private func rowCountIfTableExistsLocked(table: String, where predicate: String, parameters: [SQLiteValue]) throws -> Int {
        guard try connection.tableExists(table) else {
            return 0
        }

        return try rowCountLocked(table: table, where: predicate, parameters: parameters)
    }

    private func deleteRowsIfTableExistsLocked(table: String, where predicate: String, parameters: [SQLiteValue]) throws {
        guard try connection.tableExists(table) else {
            return
        }

        try connection.execute("DELETE FROM \(table) WHERE \(predicate);", parameters: parameters)
    }

    private func projectBoardRows(where predicate: String, parameters: [SQLiteValue] = []) throws -> [TaskRecord] {
        try connection
            .queryRows(
                """
                SELECT * FROM tasks
                WHERE \(predicate)
                ORDER BY project_id ASC, id ASC;
                """,
                parameters: parameters
            )
            .map(TaskRecord.init(row:))
    }

    private func searchOpenTasksByContainsLocked(text: String, limit: Int) throws -> [TaskRecord] {
        try searchOpenTasksByContainsLocked(tokens: [text], excludingIDs: [], limit: limit)
    }

    private func searchOpenTasksByContainsLocked(
        tokens: [String],
        excludingIDs: Set<Int64>,
        limit: Int
    ) throws -> [TaskRecord] {
        guard limit > 0 else {
            return []
        }
        let predicate = tokens.map { _ in
            """
            (instr(lower(tasks.title), ?) > 0
             OR instr(lower(COALESCE(tasks.detail, '')), ?) > 0)
            """
        }.joined(separator: " OR ")
        let exclusion = excludingIDs.isEmpty
            ? ""
            : " AND tasks.id NOT IN (\(Array(repeating: "?", count: excludingIDs.count).joined(separator: ", ")))"
        var parameters: [SQLiteValue] = []
        for token in tokens {
            let lowered = token.lowercased()
            parameters.append(.text(lowered))
            parameters.append(.text(lowered))
        }
        parameters.append(contentsOf: excludingIDs.sorted().map { .integer($0) })
        parameters.append(.integer(Int64(limit)))
        let candidates = try connection.queryRows(
            """
            SELECT tasks.* FROM tasks
            LEFT JOIN projects ON projects.id = tasks.project_id
            WHERE (\(predicate))
              AND tasks.status != 'completed'
              AND COALESCE(projects.status, 'active') != 'archived'\(exclusion)
            ORDER BY tasks.id DESC
            LIMIT ?;
            """,
            parameters: parameters
        ).map(TaskRecord.init(row:))
        // SQLite `lower()` is ASCII-only. Swift confirms the original
        // case-insensitive contains contract over this bounded result set;
        // Unicode case-folded prefix candidates are added below.
        var records = candidates.filter { record in
            tokens.contains { Self.matchesLiteral(record, text: $0) }
        }
        var seenIDs = excludingIDs
        seenIDs.formUnion(records.map(\.id))
        if records.count < limit, let prefixMatch = Self.unicodePrefixMatch(for: tokens) {
            // unicode61 case-folds Unicode prefix terms. Keep this candidate
            // window bounded, excluding already-selected FTS rows so they
            // cannot consume the caller's remaining result slots before Swift
            // restores literal contains semantics.
            let prefixPlaceholders = seenIDs.map { _ in "?" }.joined(separator: ", ")
            let prefixExclusion = prefixPlaceholders.isEmpty
                ? ""
                : " AND tasks.id NOT IN (\(prefixPlaceholders))"
            var prefixParameters: [SQLiteValue] = [.text(prefixMatch)]
            prefixParameters.append(contentsOf: seenIDs.sorted().map { .integer($0) })
            prefixParameters.append(.integer(Int64(Self.maximumUnicodePrefixCandidates)))
            let prefixCandidates = try connection.queryRows(
                """
                SELECT tasks.* FROM tasks
                JOIN tasks_fts ON tasks_fts.rowid = tasks.id
                LEFT JOIN projects ON projects.id = tasks.project_id
                WHERE tasks_fts MATCH ?
                  AND tasks.status != 'completed'
                  AND COALESCE(projects.status, 'active') != 'archived'
                  \(prefixExclusion)
                ORDER BY tasks.id DESC
                LIMIT ?;
                """,
                parameters: prefixParameters
            ).map(TaskRecord.init(row:))
            for record in prefixCandidates {
                guard tokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                      seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }
        if records.count < limit, let trigramMatch = Self.unicodeTrigramMatch(for: tokens) {
            let placeholders = Array(repeating: "?", count: seenIDs.count).joined(separator: ", ")
            let exclusion = placeholders.isEmpty ? "" : " AND tasks.id NOT IN (\(placeholders))"
            var parameters: [SQLiteValue] = [.text(trigramMatch)]
            parameters.append(contentsOf: seenIDs.sorted().map { .integer($0) })
            parameters.append(.integer(Int64(limit - records.count)))
            // Trigrams index Unicode infixes in SQLite, so the source literal
            // check can find an old `VorÜbergabe` without a fixed Swift window.
            let trigramCandidates = try connection.queryRows(
                """
                SELECT tasks.* FROM tasks
                JOIN tasks_trigram_fts ON tasks_trigram_fts.rowid = tasks.id
                LEFT JOIN projects ON projects.id = tasks.project_id
                WHERE tasks_trigram_fts MATCH ?
                  AND tasks.status != 'completed'
                  AND COALESCE(projects.status, 'active') != 'archived'\(exclusion)
                ORDER BY tasks.id DESC
                LIMIT ?;
                """,
                parameters: parameters
            ).map(TaskRecord.init(row:))
            for record in trigramCandidates {
                guard tokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                      seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }
        if records.count < limit, Self.needsUnicodeLiteralPaging(for: tokens) {
            var cursor: Int64?
            while records.count < limit {
                let candidates = try unicodeLiteralCandidatePageLocked(beforeID: cursor)
                guard let lastID = candidates.last?.id else {
                    break
                }
                cursor = lastID
                for record in candidates {
                    guard tokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                          seenIDs.insert(record.id).inserted else {
                        continue
                    }
                    records.append(record)
                }
                guard candidates.count == Self.unicodeLiteralCandidatePageSize else {
                    break
                }
            }
        }
        return Array(records.sorted { $0.id > $1.id }.prefix(limit))
    }

    private func unicodeLiteralCandidatePageLocked(beforeID: Int64?) throws -> [TaskRecord] {
        let cursorPredicate = beforeID.map { _ in " AND tasks.id < ?" } ?? ""
        var parameters: [SQLiteValue] = []
        if let beforeID {
            parameters.append(.integer(beforeID))
        }
        parameters.append(.integer(Int64(Self.unicodeLiteralCandidatePageSize)))
        // ponytail: FTS5 trigrams cannot index one- or two-scalar literals.
        // Page by keyset instead of materializing history; add a bigram index
        // only if profiling shows these rare short-Unicode queries are hot.
        return try connection.queryRows(
            """
            SELECT tasks.* FROM tasks
            LEFT JOIN projects ON projects.id = tasks.project_id
            WHERE tasks.status != 'completed'
              AND COALESCE(projects.status, 'active') != 'archived'\(cursorPredicate)
            ORDER BY tasks.id DESC
            LIMIT ?;
            """,
            parameters: parameters
        ).map(TaskRecord.init(row:))
    }

    private static func sortForProjectBoard(_ lhs: TaskRecord, _ rhs: TaskRecord) -> Bool {
        switch (lhs.projectID, rhs.projectID) {
        case let (lhsProject?, rhsProject?):
            if lhsProject != rhsProject {
                return lhsProject < rhsProject
            }
        case (nil, _?):
            return true
        case (_?, nil):
            return false
        case (nil, nil):
            break
        }
        return lhs.id < rhs.id
    }

    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0xFF66...0xFF9D:
                return true
            default:
                return false
            }
        }
    }

    private static func matchesLiteral(_ record: TaskRecord, text: String) -> Bool {
        record.title.range(of: text, options: .caseInsensitive) != nil
            || record.detail?.range(of: text, options: .caseInsensitive) != nil
    }

    private static let maximumUnicodePrefixCandidates = 128
    private static let unicodeLiteralCandidatePageSize = 128

    private static func needsUnicodeLiteralPaging(for tokens: [String]) -> Bool {
        tokens.contains { token in
            token.unicodeScalars.count < 3
                && token.unicodeScalars.contains { $0.value > 0x7F }
        }
    }

    private static func unicodePrefixMatch(for tokens: [String]) -> String? {
        let prefixes = tokens.compactMap { token -> String? in
            let leadingWord = token.drop(while: { !$0.isLetter && !$0.isNumber })
            let prefix = String(leadingWord.prefix(while: { $0.isLetter || $0.isNumber }))
            guard !prefix.isEmpty,
                  prefix.unicodeScalars.contains(where: { $0.value > 0x7F }) else {
                return nil
            }
            return "\"\(SQL.escapeFTS(prefix))\"*"
        }
        guard !prefixes.isEmpty else {
            return nil
        }
        return prefixes.joined(separator: " OR ")
    }

    private static func unicodeTrigramMatch(for tokens: [String]) -> String? {
        let terms = tokens.compactMap { token -> String? in
            guard token.unicodeScalars.count >= 3,
                  token.unicodeScalars.contains(where: { $0.value > 0x7F }) else {
                return nil
            }
            // The quoted phrase keeps punctuation literal, while source
            // revalidation prevents FTS tokenization from widening a match.
            return "\"\(SQL.escapeFTS(token))\""
        }
        guard !terms.isEmpty else {
            return nil
        }
        return terms.joined(separator: " OR ")
    }

    static func boundedSearchTokens(_ tokens: [String]) -> [String] {
        let maximumTokenCount = 32
        let maximumTokenLength = 128
        var uniqueTokens: [String] = []
        var seen = Set<String>()
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            let bounded = String(trimmed.prefix(maximumTokenLength))
            guard seen.insert(bounded).inserted else {
                continue
            }
            uniqueTokens.append(bounded)
            if uniqueTokens.count == maximumTokenCount {
                break
            }
        }
        return uniqueTokens
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

        let claimedRequestIDs = try connection.queryStrings(
            """
            INSERT INTO notification_requests (request_id, status, title, scheduled_at)
            VALUES (?, 'pending', ?, ?)
            ON CONFLICT(request_id) DO UPDATE SET
                status = 'pending',
                title = excluded.title,
                scheduled_at = excluded.scheduled_at,
                external_notification_id = NULL,
                failure_reason = NULL,
                updated_at = CURRENT_TIMESTAMP
            WHERE notification_requests.status = 'failed'
            RETURNING request_id;
            """,
            parameters: [.text(requestID), .text(title), .text(scheduledAt)]
        )
        guard claimedRequestIDs == [requestID] else {
            // Reusing an active request identifier could duplicate the external
            // notification. Only a terminal failed request is safe to retry.
            throw ToolClientError.conflict("Notification request \(requestID) is already active.")
        }
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
                external_notification_id = ?,
                failure_reason = NULL,
                updated_at = CURRENT_TIMESTAMP
            WHERE request_id = ?;
            """,
            parameters: [.text(externalNotificationID), .text(requestID)]
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
                failure_reason = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE request_id = ?;
            """,
            parameters: [.text(reason), .text(requestID)]
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
            "SELECT * FROM notification_requests WHERE request_id = ? LIMIT 1;",
            parameters: [.text(requestID)]
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
            VALUES (?, ?, ?, ?);
            """,
            parameters: [.text(eventID), SQLiteValue(projectID), SQLiteValue(taskID), SQLiteValue(title)]
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
            "SELECT * FROM calendar_links WHERE event_id = ? LIMIT 1;",
            parameters: [.text(eventID)]
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
            VALUES (?, ?, ?, ?);
            """,
            parameters: [.text(reminderID), SQLiteValue(projectID), SQLiteValue(taskID), SQLiteValue(title)]
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
            "SELECT * FROM reminder_links WHERE reminder_id = ? LIMIT 1;",
            parameters: [.text(reminderID)]
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
        let indexedBody = Self.indexedKnowledgeBody(body: validatedBody, triggersJSON: triggersJSON)

        return try connection.transaction {
            try connection.execute(
                """
                INSERT INTO knowledge_frames (name, body, triggers_json)
                VALUES (?, ?, ?);
                """,
                parameters: [.text(normalizedName), .text(validatedBody), .text(triggersJSON)]
            )
            let id = connection.lastInsertedRowID
            try connection.execute(
                """
                INSERT INTO knowledge_frames_fts (rowid, name, body)
                VALUES (?, ?, ?);
                """,
                parameters: [.integer(id), .text(normalizedName), .text(indexedBody)]
            )

            return try getLocked(id: id)
        }
    }

    public func update(id: Int64, name: String? = nil, body: String? = nil, triggers: [String]? = nil) throws -> KnowledgeFrameRecord {
        lock.lock()
        defer { lock.unlock() }

        let oldRecord = try getLocked(id: id)
        let oldTriggersJSON = try SQL.jsonArray(oldRecord.triggers, column: "knowledge_frames.triggers_json")
        let oldIndexedBody = Self.indexedKnowledgeBody(body: oldRecord.body, triggersJSON: oldTriggersJSON)
        var assignments: [String] = []
        var parameters: [SQLiteValue] = []
        if let name {
            let normalizedName = try StoreFieldValidation.requiredTrimmed(name, argument: "name", tool: .frameUpdate)
            assignments.append("name = ?")
            parameters.append(.text(normalizedName))
        }
        if let body {
            let validatedBody = try StoreFieldValidation.requiredNonBlank(body, argument: "body", tool: .frameUpdate)
            assignments.append("body = ?")
            parameters.append(.text(validatedBody))
        }
        if let triggers {
            let triggersJSON = try SQL.jsonArray(triggers, column: "knowledge_frames.triggers_json")
            assignments.append("triggers_json = ?")
            parameters.append(.text(triggersJSON))
        }
        assignments.append("updated_at = CURRENT_TIMESTAMP")

        return try connection.transaction {
            try connection.execute(
                """
                INSERT INTO knowledge_frames_fts (knowledge_frames_fts, rowid, name, body)
                VALUES ('delete', ?, ?, ?);
                """,
                parameters: [.integer(id), .text(oldRecord.name), .text(oldIndexedBody)]
            )
            try connection.execute(
                "UPDATE knowledge_frames SET \(assignments.joined(separator: ", ")) WHERE id = ?;",
                parameters: parameters + [.integer(id)]
            )
            let record = try getLocked(id: id)
            let recordTriggersJSON = try SQL.jsonArray(record.triggers, column: "knowledge_frames.triggers_json")
            let recordIndexedBody = Self.indexedKnowledgeBody(body: record.body, triggersJSON: recordTriggersJSON)
            try connection.execute(
                """
                INSERT INTO knowledge_frames_fts (rowid, name, body)
                VALUES (?, ?, ?);
                """,
                parameters: [.integer(id), .text(record.name), .text(recordIndexedBody)]
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
        let triggersJSON = try SQL.jsonArray(record.triggers, column: "knowledge_frames.triggers_json")
        let indexedBody = Self.indexedKnowledgeBody(body: record.body, triggersJSON: triggersJSON)
        try connection.transaction {
            try connection.execute(
                """
                INSERT INTO knowledge_frames_fts (knowledge_frames_fts, rowid, name, body)
                VALUES ('delete', ?, ?, ?);
                """,
                parameters: [.integer(id), .text(record.name), .text(indexedBody)]
            )
            try connection.execute("DELETE FROM knowledge_frames WHERE id = ?;", parameters: [.integer(id)])
        }
    }

    public func search(query: String) throws -> [KnowledgeFrameRecord] {
        lock.lock()
        defer { lock.unlock() }

        return try searchLocked(query: query, limit: nil)
    }

    /// Bounded literal search for interactive callers such as the command palette.
    /// At most 128 rows are returned to keep SQLite bind counts bounded.
    /// The compatibility overload above intentionally remains unbounded for
    /// existing read-only tools that render every matching knowledge frame.
    public func search(query: String, limit: Int) throws -> [KnowledgeFrameRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard limit > 0 else {
            return []
        }
        return try searchLocked(
            query: query,
            limit: min(limit, Self.maximumBoundedSearchResults)
        )
    }

    private func searchLocked(query: String, limit: Int?) throws -> [KnowledgeFrameRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let match = "\"\(SQL.escapeFTS(trimmed))\""
        let ftsLimit = limit.map { _ in "LIMIT ?" } ?? ""
        var ftsParameters: [SQLiteValue] = [.text(match)]
        if let limit {
            ftsParameters.append(.integer(Int64(limit)))
        }
        let ftsCandidates = try connection.queryRows(
            """
            SELECT knowledge_frames.*
            FROM knowledge_frames_fts
            JOIN knowledge_frames ON knowledge_frames_fts.rowid = knowledge_frames.id
            WHERE knowledge_frames_fts MATCH ?
            ORDER BY rank
            \(ftsLimit);
            """,
            parameters: ftsParameters
        ).map(KnowledgeFrameRecord.init(row:))
        // FTS strips punctuation, so an FTS phrase alone can widen a literal
        // palette query. Keep only source-confirmed rows and recover any FTS
        // false negatives with the same SQLite `instr` semantics.
        var records = ftsCandidates.filter { Self.matchesLiteral($0, text: trimmed) }
        var seenIDs = Set(records.map(\.id))
        let remaining = limit.map { $0 - records.count }
        guard remaining != 0 else {
            return records
        }
        let exclusion = seenIDs.isEmpty
            ? ""
            : " AND id NOT IN (\(Array(repeating: "?", count: seenIDs.count).joined(separator: ", ")))"
        let lowered = trimmed.lowercased()
        var parameters: [SQLiteValue] = [.text(lowered), .text(lowered), .text(lowered)]
        parameters.append(contentsOf: seenIDs.sorted().map { .integer($0) })
        let fallbackLimit = remaining.map { _ in "LIMIT ?" } ?? ""
        if let remaining {
            parameters.append(.integer(Int64(remaining)))
        }
        let fallbackCandidates = try connection.queryRows(
            """
            SELECT * FROM knowledge_frames
            WHERE (instr(lower(name), ?) > 0
                   OR instr(lower(body), ?) > 0
                   OR EXISTS (
                       SELECT 1 FROM json_each(knowledge_frames.triggers_json)
                       WHERE instr(lower(json_each.value), ?) > 0
                   ))\(exclusion)
            ORDER BY id ASC
            \(fallbackLimit);
            """,
            parameters: parameters
        ).map(KnowledgeFrameRecord.init(row:))
        for record in fallbackCandidates {
            guard Self.matchesLiteral(record, text: trimmed), seenIDs.insert(record.id).inserted else {
                continue
            }
            records.append(record)
        }
        if limit.map({ records.count < $0 }) ?? true,
           let trigramMatch = Self.unicodeTrigramMatch(for: [trimmed]) {
            let trigramLimit = limit.map { $0 - records.count }
            let exclusion = seenIDs.isEmpty
                ? ""
                : " AND knowledge_frames.id NOT IN (\(Array(repeating: "?", count: seenIDs.count).joined(separator: ", ")))"
            var trigramParameters: [SQLiteValue] = [.text(trigramMatch)]
            trigramParameters.append(contentsOf: seenIDs.sorted().map { .integer($0) })
            let trigramLimitClause = trigramLimit.map { _ in "LIMIT ?" } ?? ""
            if let trigramLimit {
                trigramParameters.append(.integer(Int64(trigramLimit)))
            }
            // Trigrams locate Unicode infixes in SQLite before source fields
            // reapply the literal contract, independent of table age.
            let trigramCandidates = try connection.queryRows(
                """
                SELECT knowledge_frames.*
                FROM knowledge_frames_trigram_fts
                JOIN knowledge_frames ON knowledge_frames_trigram_fts.rowid = knowledge_frames.id
                WHERE knowledge_frames_trigram_fts MATCH ?\(exclusion)
                ORDER BY knowledge_frames.id ASC
                \(trigramLimitClause);
                """,
                parameters: trigramParameters
            ).map(KnowledgeFrameRecord.init(row:))
            for record in trigramCandidates {
                guard Self.matchesLiteral(record, text: trimmed), seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }
        if limit.map({ records.count < $0 }) ?? true,
           Self.needsUnicodeLiteralPaging(for: [trimmed]) {
            var cursor: Int64?
            while limit.map({ records.count < $0 }) ?? true {
                let candidates = try unicodeLiteralCandidatePageLocked(afterID: cursor)
                guard let lastID = candidates.last?.id else {
                    break
                }
                cursor = lastID
                for record in candidates {
                    guard Self.matchesLiteral(record, text: trimmed), seenIDs.insert(record.id).inserted else {
                        continue
                    }
                    records.append(record)
                }
                guard candidates.count == Self.unicodeLiteralCandidatePageSize else {
                    break
                }
            }
        }
        return limit.map { Array(records.prefix($0)) } ?? records
    }

    func search(matching tokens: [String], limit: Int) throws -> [KnowledgeFrameRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard limit > 0 else {
            return []
        }
        let boundedTokens = SQLiteTaskStore.boundedSearchTokens(tokens)
        guard !boundedTokens.isEmpty else {
            return []
        }

        let nonCJK = boundedTokens.filter { !SQLiteTaskStore.containsCJK($0) }
        var records: [KnowledgeFrameRecord] = []
        var seenIDs = Set<Int64>()

        if !nonCJK.isEmpty {
            let match = nonCJK
                .map { "\"\(SQL.escapeFTS($0))\"" }
                .joined(separator: " OR ")
            let ftsCandidates = try connection.queryRows(
                """
                SELECT knowledge_frames.*
                FROM knowledge_frames_fts
                JOIN knowledge_frames ON knowledge_frames_fts.rowid = knowledge_frames.id
                WHERE knowledge_frames_fts MATCH ?
                ORDER BY rank
                LIMIT ?;
                """,
                parameters: [.text(match), .integer(Int64(limit))]
            ).map(KnowledgeFrameRecord.init(row:))
            for record in ftsCandidates {
                guard boundedTokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                      seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }

        let containsTokens = boundedTokens
        if !containsTokens.isEmpty, records.count < limit {
            // unicode61 does not index arbitrary CJK or ASCII substrings. Run
            // this only for the remaining slots so exact FTS hits stay first.
            let predicate = containsTokens.map { _ in
                """
                (instr(lower(name), ?) > 0
                 OR instr(lower(body), ?) > 0
                 OR EXISTS (
                     SELECT 1 FROM json_each(knowledge_frames.triggers_json)
                     WHERE instr(lower(json_each.value), ?) > 0
                 ))
                """
            }.joined(separator: " OR ")
            let exclusion = seenIDs.isEmpty
                ? ""
                : " AND id NOT IN (\(Array(repeating: "?", count: seenIDs.count).joined(separator: ", ")))"
            var parameters: [SQLiteValue] = []
            for token in containsTokens {
                let lowered = token.lowercased()
                parameters.append(.text(lowered))
                parameters.append(.text(lowered))
                parameters.append(.text(lowered))
            }
            parameters.append(contentsOf: seenIDs.sorted().map { .integer($0) })
            parameters.append(.integer(Int64(limit - records.count)))
            let fallbackCandidates = try connection.queryRows(
                """
                SELECT * FROM knowledge_frames
                WHERE (\(predicate))\(exclusion)
                ORDER BY id ASC
                LIMIT ?;
                """,
                parameters: parameters
            ).map(KnowledgeFrameRecord.init(row:))
            for record in fallbackCandidates {
                guard boundedTokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                      seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }

        if records.count < limit, let trigramMatch = Self.unicodeTrigramMatch(for: boundedTokens) {
            let exclusion = seenIDs.isEmpty
                ? ""
                : " AND knowledge_frames.id NOT IN (\(Array(repeating: "?", count: seenIDs.count).joined(separator: ", ")))"
            var trigramParameters: [SQLiteValue] = [.text(trigramMatch)]
            trigramParameters.append(contentsOf: seenIDs.sorted().map { .integer($0) })
            trigramParameters.append(.integer(Int64(limit - records.count)))
            let trigramCandidates = try connection.queryRows(
                """
                SELECT knowledge_frames.*
                FROM knowledge_frames_trigram_fts
                JOIN knowledge_frames ON knowledge_frames_trigram_fts.rowid = knowledge_frames.id
                WHERE knowledge_frames_trigram_fts MATCH ?\(exclusion)
                ORDER BY knowledge_frames.id ASC
                LIMIT ?;
                """,
                parameters: trigramParameters
            ).map(KnowledgeFrameRecord.init(row:))
            for record in trigramCandidates {
                guard boundedTokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                      seenIDs.insert(record.id).inserted else {
                    continue
                }
                records.append(record)
            }
        }

        if records.count < limit, Self.needsUnicodeLiteralPaging(for: boundedTokens) {
            var cursor: Int64?
            while records.count < limit {
                let candidates = try unicodeLiteralCandidatePageLocked(afterID: cursor)
                guard let lastID = candidates.last?.id else {
                    break
                }
                cursor = lastID
                for record in candidates {
                    guard records.count < limit,
                          boundedTokens.contains(where: { Self.matchesLiteral(record, text: $0) }),
                          seenIDs.insert(record.id).inserted else {
                        continue
                    }
                    records.append(record)
                }
                guard candidates.count == Self.unicodeLiteralCandidatePageSize else {
                    break
                }
            }
        }

        return Array(records.prefix(limit))
    }

    private func unicodeLiteralCandidatePageLocked(afterID: Int64?) throws -> [KnowledgeFrameRecord] {
        let cursorPredicate = afterID.map { _ in " WHERE id > ?" } ?? ""
        var parameters: [SQLiteValue] = []
        if let afterID {
            parameters.append(.integer(afterID))
        }
        parameters.append(.integer(Int64(Self.unicodeLiteralCandidatePageSize)))
        // ponytail: FTS5 trigrams cannot index one- or two-scalar literals.
        // Page by keyset instead of materializing history; add a bigram index
        // only if profiling shows these rare short-Unicode queries are hot.
        return try connection.queryRows(
            """
            SELECT * FROM knowledge_frames\(cursorPredicate)
            ORDER BY id ASC
            LIMIT ?;
            """,
            parameters: parameters
        ).map(KnowledgeFrameRecord.init(row:))
    }

    private func getLocked(id: Int64) throws -> KnowledgeFrameRecord {
        guard let row = try connection.queryRows("SELECT * FROM knowledge_frames WHERE id = ? LIMIT 1;", parameters: [.integer(id)]).first else {
            throw ToolExecutionError.executionFailed(.frameGet, "Knowledge frame \(id) was not found.")
        }

        return try KnowledgeFrameRecord(row: row)
    }

    private static func indexedKnowledgeBody(body: String, triggersJSON: String) -> String {
        body + "\n" + triggersJSON
    }

    private static let maximumBoundedSearchResults = 128
    private static let unicodeLiteralCandidatePageSize = 128

    private static func needsUnicodeLiteralPaging(for tokens: [String]) -> Bool {
        tokens.contains { token in
            token.unicodeScalars.count < 3
                && token.unicodeScalars.contains { $0.value > 0x7F }
        }
    }

    private static func unicodeTrigramMatch(for tokens: [String]) -> String? {
        let terms = tokens.compactMap { token -> String? in
            guard token.unicodeScalars.count >= 3,
                  token.unicodeScalars.contains(where: { $0.value > 0x7F }) else {
                return nil
            }
            // The quoted phrase keeps punctuation literal, while source
            // revalidation prevents FTS tokenization from widening a match.
            return "\"\(SQL.escapeFTS(token))\""
        }
        guard !terms.isEmpty else {
            return nil
        }
        return terms.joined(separator: " OR ")
    }

    private static func matchesLiteral(_ record: KnowledgeFrameRecord, text: String) -> Bool {
        record.name.range(of: text, options: .caseInsensitive) != nil
            || record.body.range(of: text, options: .caseInsensitive) != nil
            || record.triggers.contains { $0.range(of: text, options: .caseInsensitive) != nil }
    }
}

private extension ProjectRecord {
    init(row: SQLiteMaterializedRow) throws {
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
            workspaceBookmarkData: ProjectRecord.decodeBookmarkData(row["workspace_bookmark"]),
            tags: try SQL.parseStringArray(
                try SQL.requiredString(row["tags_json"], column: "projects.tags_json"),
                column: "projects.tags_json"
            ),
            sourceCommand: SQL.nilIfEmpty(row["source_command"])
        )
    }

    init(projectBoardRow row: SQLiteMaterializedRow) throws {
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
            workspaceBookmarkData: ProjectRecord.decodeBookmarkData(row["workspace_bookmark"]),
            tags: [],
            sourceCommand: SQL.nilIfEmpty(row["source_command"])
        )
    }

    private static func decodeBookmarkData(_ value: String?) -> Data? {
        guard let value = SQL.nilIfEmpty(value) else {
            return nil
        }
        return Data(base64Encoded: value)
    }
}

private extension TaskRecord {
    init(row: SQLiteMaterializedRow) throws {
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
            completedAt: SQL.nilIfEmpty(row["completed_at"]),
            priority: SQL.nilIfEmpty(row["priority"]),
            sourceCommand: SQL.nilIfEmpty(row["source_command"]),
            detail: SQL.nilIfEmpty(row["detail"]),
            createdAt: SQL.nilIfEmpty(row["created_at"]),
            updatedAt: SQL.nilIfEmpty(row["updated_at"]),
            recurrence: SQL.nilIfEmpty(row["recurrence"]),
            mutationRevision: row.cells["mutation_revision"]
                .flatMap { cell in
                    if case .integer(let value) = cell {
                        return value
                    }
                    return nil
                } ?? 0
        )
    }
}

public struct TaskSnapshotConflictError: Error, Equatable, Sendable {
    public let taskID: Int64

    public init(taskID: Int64) {
        self.taskID = taskID
    }
}

private extension KnowledgeFrameRecord {
    init(row: SQLiteMaterializedRow) throws {
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
    init(row: SQLiteMaterializedRow) throws {
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
    init(row: SQLiteMaterializedRow) throws {
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "calendar_links.id"),
            eventID: try SQL.requiredString(row["event_id"], column: "calendar_links.event_id"),
            projectID: try SQL.optionalInt64(row["project_id"], column: "calendar_links.project_id"),
            taskID: try SQL.optionalInt64(row["task_id"], column: "calendar_links.task_id"),
            title: SQL.nilIfEmpty(row["title"])
        )
    }
}

private extension ExternalTaskLinkRecord {
    init(row: SQLiteMaterializedRow) throws {
        self.init(
            id: try SQL.requiredInt64(row["id"], column: "external_task_links.id"),
            providerID: try SQL.requiredString(row["provider_id"], column: "external_task_links.provider_id"),
            externalID: try SQL.requiredString(row["external_id"], column: "external_task_links.external_id"),
            projectID: try SQL.optionalInt64(row["project_id"], column: "external_task_links.project_id"),
            taskID: try SQL.requiredInt64(row["task_id"], column: "external_task_links.task_id"),
            title: SQL.nilIfEmpty(row["title"])
        )
    }
}

private extension ReminderLinkRecord {
    init(row: SQLiteMaterializedRow) throws {
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

    private static let taskRecurrences = ["daily", "weekly", "monthly"]

    static func taskRecurrence(_ value: String, tool: ActionTool) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            throw ToolExecutionError.validationFailed(tool, "Argument 'recurrence' cannot be blank.")
        }
        guard taskRecurrences.contains(normalized) else {
            throw ToolExecutionError.validationFailed(
                tool,
                "Argument 'recurrence' must be one of \(taskRecurrences.joined(separator: ", "))."
            )
        }
        return normalized
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
