import Foundation
import SQLite3

public enum DatabaseError: Error, Equatable {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
}

public final class SQLiteConnection {
    private var database: OpaquePointer?

    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let status = sqlite3_open_v2(path, &database, flags, nil)
        guard status == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error."
            throw DatabaseError.openFailed(message)
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard status == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite execution error."
            sqlite3_free(errorMessage)
            throw DatabaseError.executeFailed(message)
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func queryStrings(_ sql: String) throws -> [String] {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareStatus == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage)
        }

        defer { sqlite3_finalize(statement) }

        var results: [String] = []

        while true {
            let stepStatus = sqlite3_step(statement)

            if stepStatus == SQLITE_ROW {
                if let text = sqlite3_column_text(statement, 0) {
                    let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
                    results.append(String(cString: cString))
                }
            } else if stepStatus == SQLITE_DONE {
                return results
            } else {
                throw DatabaseError.stepFailed(errorMessage)
            }
        }
    }

    public func queryRows(_ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareStatus == SQLITE_OK else {
            throw DatabaseError.prepareFailed(errorMessage)
        }

        defer { sqlite3_finalize(statement) }

        var rows: [[String: String]] = []

        while true {
            let stepStatus = sqlite3_step(statement)

            if stepStatus == SQLITE_ROW {
                var row: [String: String] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    if let text = sqlite3_column_text(statement, index) {
                        let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
                        row[name] = String(cString: cString)
                    } else {
                        row[name] = ""
                    }
                }
                rows.append(row)
            } else if stepStatus == SQLITE_DONE {
                return rows
            } else {
                throw DatabaseError.stepFailed(errorMessage)
            }
        }
    }

    public var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(database)
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        let escaped = tableName.replacingOccurrences(of: "'", with: "''")
        let result = try queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '\(escaped)' LIMIT 1;"
        )
        return !result.isEmpty
    }

    private var errorMessage: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
    }
}

public struct DatabaseMigration {
    public var id: String
    public var apply: (SQLiteConnection) throws -> Void

    public init(id: String, apply: @escaping (SQLiteConnection) throws -> Void) {
        self.id = id
        self.apply = apply
    }
}

public enum SQLiteMigrationRunner {
    public static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )

        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))

        for migration in migrations where !alreadyApplied.contains(migration.id) {
            do {
                try connection.execute("BEGIN;")
                try migration.apply(connection)
                try connection.execute(
                    "INSERT INTO schema_migrations (id) VALUES ('\(escape(migration.id))');"
                )
                try connection.execute("COMMIT;")
            } catch {
                try? connection.execute("ROLLBACK;")
                throw error
            }
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}

public protocol DatabaseClient {
    func migrate(_ migrations: [DatabaseMigration]) throws
    func appliedMigrationIDs() throws -> [String]
    func tableExists(_ tableName: String) throws -> Bool
}

public final class SQLiteDatabaseClient: DatabaseClient {
    private let connection: SQLiteConnection

    public init(path: String) throws {
        self.connection = try SQLiteConnection(path: path)
    }

    public func migrate(_ migrations: [DatabaseMigration]) throws {
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
    }

    public func appliedMigrationIDs() throws -> [String] {
        try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;")
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        try connection.tableExists(tableName)
    }

}

public enum CoreMigrations {
    public static var phase0: [DatabaseMigration] {
        [
            DatabaseMigration(id: "0001_create_settings_and_audit_logs") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS settings (
                        key TEXT PRIMARY KEY NOT NULL,
                        value TEXT NOT NULL,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE TABLE IF NOT EXISTS audit_logs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        timestamp TEXT NOT NULL,
                        category TEXT NOT NULL,
                        action TEXT NOT NULL,
                        status TEXT NOT NULL,
                        metadata_json TEXT NOT NULL DEFAULT '{}'
                    );
                    """
                )
            }
        ]
    }

    public static var phase2: [DatabaseMigration] {
        phase0 + [
            DatabaseMigration(id: "0002_create_projects_tasks_and_knowledge") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS projects (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        title TEXT NOT NULL,
                        status TEXT NOT NULL,
                        priority TEXT,
                        deadline TEXT,
                        workspace_path TEXT,
                        tags_json TEXT NOT NULL DEFAULT '[]',
                        source_command TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE TABLE IF NOT EXISTS tasks (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        project_id INTEGER,
                        title TEXT NOT NULL,
                        status TEXT NOT NULL,
                        detail TEXT,
                        due_at TEXT,
                        priority TEXT,
                        source_command TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE TABLE IF NOT EXISTS knowledge_frames (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        body TEXT NOT NULL,
                        triggers_json TEXT NOT NULL DEFAULT '[]',
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_frames_fts USING fts5(
                        name,
                        body,
                        content='knowledge_frames',
                        content_rowid='id'
                    );
                    """
                )
            },
            DatabaseMigration(id: "0002b_create_system_tool_state") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS notification_requests (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        request_id TEXT NOT NULL UNIQUE,
                        status TEXT NOT NULL CHECK(status IN ('pending', 'scheduled', 'failed')),
                        title TEXT NOT NULL,
                        scheduled_at TEXT NOT NULL,
                        external_notification_id TEXT,
                        failure_reason TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE TABLE IF NOT EXISTS calendar_links (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        event_id TEXT NOT NULL UNIQUE,
                        project_id INTEGER,
                        task_id INTEGER,
                        title TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_calendar_links_project
                    ON calendar_links(project_id);

                    CREATE INDEX IF NOT EXISTS idx_calendar_links_task
                    ON calendar_links(task_id);

                    CREATE TABLE IF NOT EXISTS reminder_links (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        reminder_id TEXT NOT NULL UNIQUE,
                        project_id INTEGER,
                        task_id INTEGER,
                        title TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_reminder_links_project
                    ON reminder_links(project_id);

                    CREATE INDEX IF NOT EXISTS idx_reminder_links_task
                    ON reminder_links(task_id);
                    """
                )
            }
        ]
    }

    public static var phase4: [DatabaseMigration] {
        phase2 + [
            DatabaseMigration(id: "0003_create_deadline_rules") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS deadline_rules (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        target_type TEXT NOT NULL CHECK(target_type IN ('project', 'task')),
                        target_id INTEGER NOT NULL,
                        kind TEXT NOT NULL,
                        custom_notify_at TEXT,
                        muted_at TEXT,
                        last_notified_at TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE(target_type, target_id, kind, custom_notify_at)
                    );

                    CREATE INDEX IF NOT EXISTS idx_deadline_rules_target
                    ON deadline_rules(target_type, target_id);
                    """
                )
            },
            DatabaseMigration(id: "0004_create_daily_check_state") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS daily_check_state (
                        id INTEGER PRIMARY KEY CHECK(id = 1),
                        last_run_at TEXT,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    """
                )
            },
            DatabaseMigration(id: "0005_create_artifacts") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS artifacts (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        project_id INTEGER,
                        task_id INTEGER,
                        workspace_path TEXT NOT NULL,
                        expected_path TEXT NOT NULL,
                        created_state TEXT NOT NULL CHECK(created_state IN ('expected', 'created', 'missing')),
                        last_modified_at TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE(workspace_path, expected_path)
                    );

                    CREATE INDEX IF NOT EXISTS idx_artifacts_workspace_path
                    ON artifacts(workspace_path);

                    CREATE INDEX IF NOT EXISTS idx_artifacts_last_modified_at
                    ON artifacts(last_modified_at);
                    """
                )
            }
        ]
    }

    public static var phase9: [DatabaseMigration] {
        phase4 + [
            DatabaseMigration(id: "0006_create_knowledge_vector_indexes") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS knowledge_frame_vectors (
                        frame_id INTEGER PRIMARY KEY NOT NULL,
                        provider_id TEXT NOT NULL,
                        dimensions INTEGER NOT NULL,
                        vector_json TEXT NOT NULL,
                        redacted_preview TEXT NOT NULL,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY(frame_id) REFERENCES knowledge_frames(id) ON DELETE CASCADE
                    );

                    CREATE TABLE IF NOT EXISTS knowledge_retrieval_eval_runs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        mode TEXT NOT NULL,
                        query TEXT NOT NULL,
                        expected_frame_id INTEGER NOT NULL,
                        top_frame_id INTEGER,
                        is_match INTEGER NOT NULL,
                        latency_ms REAL NOT NULL,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_knowledge_frame_vectors_provider
                    ON knowledge_frame_vectors(provider_id);
                    """
                )
            }
        ]
    }

    public static var current: [DatabaseMigration] {
        phase9 + [
            DatabaseMigration(id: "0007_add_task_detail") { connection in
                let columns = try connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
                guard !columns.contains("detail") else {
                    return
                }
                try connection.execute("ALTER TABLE tasks ADD COLUMN detail TEXT;")
            }
        ]
    }
}
