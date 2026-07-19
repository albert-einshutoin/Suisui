import Foundation

public struct ProjectMilestoneRecord: Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64
    public var title: String
    public var dueAt: String?
    public var isCompleted: Bool

    public init(id: Int64, projectID: Int64, title: String, dueAt: String?, isCompleted: Bool) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.dueAt = dueAt
        self.isCompleted = isCompleted
    }
}

public enum ProjectMilestoneStoreError: Error, Equatable {
    case notFound(Int64)
}

public final class SQLiteProjectMilestoneStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    @discardableResult
    public func create(projectID: Int64, title: String, dueAt: String?) throws -> ProjectMilestoneRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO project_milestones (project_id, title, due_at, is_completed)
            VALUES (?, ?, ?, 0);
            """,
            parameters: [.integer(projectID), .text(title), SQLiteValue(MilestoneSQL.nilIfEmpty(dueAt))]
        )
        return try getLocked(id: connection.lastInsertedRowID)
    }

    @discardableResult
    public func update(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectMilestoneRecord {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            UPDATE project_milestones
            SET title = ?,
                due_at = ?,
                is_completed = ?,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?;
            """,
            parameters: [
                .text(title),
                SQLiteValue(MilestoneSQL.nilIfEmpty(dueAt)),
                .integer(isCompleted ? 1 : 0),
                .integer(id)
            ]
        )
        return try getLocked(id: id)
    }

    public func get(id: Int64) throws -> ProjectMilestoneRecord {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    public func list() throws -> [ProjectMilestoneRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try connection.queryRows("SELECT * FROM project_milestones ORDER BY due_at IS NULL, due_at ASC, id ASC;").map(ProjectMilestoneRecord.init(row:))
    }

    func listForProjectBoard() throws -> [ProjectMilestoneRecord] {
        lock.lock()
        defer { lock.unlock() }
        // Project Board renders milestones inside each project card; project-id
        // order lines the SQL read up with the snapshot grouping pass.
        return try connection
            .queryRows("SELECT * FROM project_milestones ORDER BY project_id ASC, due_at IS NULL, due_at ASC, id ASC;")
            .map(ProjectMilestoneRecord.init(row:))
    }

    func listForProjectBoard(projectIDs: Set<Int64>) throws -> [ProjectMilestoneRecord] {
        guard !projectIDs.isEmpty else {
            return []
        }

        lock.lock()
        defer { lock.unlock() }
        // Archived project milestones can be numerous history. Active board
        // loads only need milestones belonging to the visible project set.
        let sortedIDs = projectIDs.sorted()
        let placeholders = Array(repeating: "?", count: sortedIDs.count).joined(separator: ", ")
        return try connection
            .queryRows(
                """
                SELECT * FROM project_milestones
                WHERE project_id IN (\(placeholders))
                ORDER BY project_id ASC, due_at IS NULL, due_at ASC, id ASC;
                """,
                parameters: sortedIDs.map { .integer($0) }
            )
            .map(ProjectMilestoneRecord.init(row:))
    }

    public func delete(id: Int64) throws {
        lock.lock()
        defer { lock.unlock() }

        _ = try getLocked(id: id)
        try connection.execute("DELETE FROM project_milestones WHERE id = ?;", parameters: [.integer(id)])
    }

    private func getLocked(id: Int64) throws -> ProjectMilestoneRecord {
        guard let row = try connection.queryRows(
            "SELECT * FROM project_milestones WHERE id = ? LIMIT 1;",
            parameters: [.integer(id)]
        ).first else {
            throw ProjectMilestoneStoreError.notFound(id)
        }
        return try ProjectMilestoneRecord(row: row)
    }
}

private extension ProjectMilestoneRecord {
    init(row: [String: String]) throws {
        self.init(
            id: try MilestoneSQL.requiredInt64(row["id"], column: "project_milestones.id"),
            projectID: try MilestoneSQL.requiredInt64(row["project_id"], column: "project_milestones.project_id"),
            title: try MilestoneSQL.requiredString(row["title"], column: "project_milestones.title"),
            dueAt: MilestoneSQL.nilIfEmpty(row["due_at"]),
            isCompleted: try MilestoneSQL.requiredInt64(row["is_completed"], column: "project_milestones.is_completed") == 1
        )
    }
}

private enum MilestoneSQL {
    static func nilIfEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    static func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        return value
    }

    static func requiredInt64(_ value: String?, column: String) throws -> Int64 {
        guard let value, let intValue = Int64(value) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: value ?? "")
        }
        return intValue
    }
}
