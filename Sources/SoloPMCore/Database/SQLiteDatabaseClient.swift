import Foundation
import SQLite3

public enum DatabaseError: Error, Equatable {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case missingColumn(String)
    case invalidColumnValue(column: String, value: String)
}

public struct SQLiteRow {
    fileprivate let statement: OpaquePointer?
    fileprivate let columnIndexes: [String: Int32]

    public func string(_ column: String) throws -> String {
        guard let value = try optionalString(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalString(_ column: String) throws -> String? {
        let index = try columnIndex(column)
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        let cString = UnsafeRawPointer(text).assumingMemoryBound(to: CChar.self)
        return String(cString: cString)
    }

    public func int64(_ column: String) throws -> Int64 {
        guard let value = try optionalInt64(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalInt64(_ column: String) throws -> Int64? {
        let index = try columnIndex(column)
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        if sqlite3_column_type(statement, index) == SQLITE_INTEGER {
            return sqlite3_column_int64(statement, index)
        }
        let rawValue = try optionalString(column) ?? ""
        guard let value = Int64(rawValue) else {
            throw DatabaseError.invalidColumnValue(column: column, value: rawValue)
        }
        return value
    }

    public func data(_ column: String) throws -> Data {
        guard let value = try optionalData(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalData(_ column: String) throws -> Data? {
        let index = try columnIndex(column)
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        guard let bytes = sqlite3_column_blob(statement, index) else {
            return Data()
        }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }

    private func columnIndex(_ column: String) throws -> Int32 {
        guard let index = columnIndexes[column] else {
            throw DatabaseError.missingColumn(column)
        }
        return index
    }
}

public enum SQLiteValue: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    public init(_ value: String?) {
        self = value.map(SQLiteValue.text) ?? .null
    }

    public init(_ value: Int64?) {
        self = value.map(SQLiteValue.integer) ?? .null
    }

    public init(_ value: Int?) {
        self = value.map { SQLiteValue.integer(Int64($0)) } ?? .null
    }

    public init(_ value: Double?) {
        self = value.map(SQLiteValue.real) ?? .null
    }

    public init(_ value: Data?) {
        self = value.map(SQLiteValue.blob) ?? .null
    }

    public init(_ value: Bool?) {
        self = value.map { SQLiteValue.integer($0 ? 1 : 0) } ?? .null
    }
}

public final class SQLiteConnection {
    private var database: OpaquePointer?
    // sqlite3_bind copies bound buffers when given SQLITE_TRANSIENT, so Swift
    // strings and Data can be released as soon as the bind call returns.
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let status = sqlite3_open_v2(path, &database, flags, nil)
        guard status == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error."
            throw DatabaseError.openFailed(message)
        }
        try enableForeignKeys()
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

    /// Executes a single statement with `?` placeholders bound to `parameters`.
    /// Binding happens inside SQLite, so values never require manual escaping.
    public func execute(_ sql: String, parameters: [SQLiteValue]) throws {
        let statement = try prepare(sql, parameters: parameters)
        defer { sqlite3_finalize(statement) }

        let stepStatus = sqlite3_step(statement)
        guard stepStatus == SQLITE_DONE || stepStatus == SQLITE_ROW else {
            throw DatabaseError.stepFailed(errorMessage)
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

    public func queryStrings(_ sql: String, parameters: [SQLiteValue] = []) throws -> [String] {
        let statement = try prepare(sql, parameters: parameters)
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

    public func queryRows(_ sql: String, parameters: [SQLiteValue] = []) throws -> [[String: String]] {
        let statement = try prepare(sql, parameters: parameters)
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

    public func query<T>(_ sql: String, parameters: [SQLiteValue] = [], _ map: (SQLiteRow) throws -> T) throws -> [T] {
        let statement = try prepare(sql, parameters: parameters)
        defer { sqlite3_finalize(statement) }

        let row = SQLiteRow(statement: statement, columnIndexes: columnIndexes(for: statement))
        var results: [T] = []

        while true {
            let stepStatus = sqlite3_step(statement)

            if stepStatus == SQLITE_ROW {
                // Hot list paths use typed row access so they do not allocate a full
                // [String: String] dictionary for columns the caller never reads.
                results.append(try map(row))
            } else if stepStatus == SQLITE_DONE {
                return results
            } else {
                throw DatabaseError.stepFailed(errorMessage)
            }
        }
    }

    public var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(database)
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        let result = try queryStrings(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
            parameters: [.text(tableName)]
        )
        return !result.isEmpty
    }

    private func prepare(_ sql: String, parameters: [SQLiteValue]) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, sql, -1, &statement, nil)

        guard prepareStatus == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw DatabaseError.prepareFailed(errorMessage)
        }

        let expectedCount = Int(sqlite3_bind_parameter_count(statement))
        guard expectedCount == parameters.count else {
            sqlite3_finalize(statement)
            throw DatabaseError.prepareFailed(
                "Statement expects \(expectedCount) bound parameters but \(parameters.count) were provided."
            )
        }

        for (offset, parameter) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let bindStatus: Int32
            switch parameter {
            case .null:
                bindStatus = sqlite3_bind_null(statement, index)
            case let .integer(value):
                bindStatus = sqlite3_bind_int64(statement, index, value)
            case let .real(value):
                bindStatus = sqlite3_bind_double(statement, index, value)
            case let .text(value):
                bindStatus = sqlite3_bind_text(statement, index, value, -1, Self.transientDestructor)
            case let .blob(value) where value.isEmpty:
                // An empty Data has no base address; zeroblob keeps the bound
                // value an empty BLOB instead of collapsing it to NULL.
                bindStatus = sqlite3_bind_zeroblob(statement, index, 0)
            case let .blob(value):
                bindStatus = value.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), Self.transientDestructor)
                }
            }
            guard bindStatus == SQLITE_OK else {
                let message = errorMessage
                sqlite3_finalize(statement)
                throw DatabaseError.prepareFailed(message)
            }
        }

        return statement
    }

    private var errorMessage: String {
        database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error."
    }

    private func columnIndexes(for statement: OpaquePointer?) -> [String: Int32] {
        var indexes: [String: Int32] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, index))
            indexes[name] = index
        }
        return indexes
    }

    private func enableForeignKeys() throws {
        let status = sqlite3_exec(database, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        guard status == SQLITE_OK else {
            throw DatabaseError.openFailed(errorMessage)
        }
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
                    "INSERT INTO schema_migrations (id) VALUES (?);",
                    parameters: [.text(migration.id)]
                )
                try connection.execute("COMMIT;")
            } catch {
                try? connection.execute("ROLLBACK;")
                throw error
            }
        }
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
                        workspace_bookmark TEXT,
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
                        completed_at TEXT,
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
            },
            DatabaseMigration(id: "0008_create_mcp_server_registrations") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS mcp_server_registrations (
                        id TEXT PRIMARY KEY NOT NULL,
                        sort_order INTEGER NOT NULL,
                        display_name TEXT NOT NULL,
                        command TEXT NOT NULL,
                        arguments_json TEXT NOT NULL DEFAULT '[]',
                        environment_json TEXT NOT NULL DEFAULT '{}',
                        working_directory TEXT,
                        is_enabled INTEGER NOT NULL DEFAULT 0,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_mcp_server_registrations_sort_order
                    ON mcp_server_registrations(sort_order);
                    """
                )
            },
            DatabaseMigration(id: "0009_create_external_task_links") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS external_task_links (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        provider_id TEXT NOT NULL,
                        external_id TEXT NOT NULL,
                        project_id INTEGER,
                        task_id INTEGER NOT NULL,
                        title TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        UNIQUE(provider_id, external_id),
                        FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
                    );

                    CREATE INDEX IF NOT EXISTS idx_external_task_links_task
                    ON external_task_links(provider_id, task_id);

                    CREATE INDEX IF NOT EXISTS idx_external_task_links_project
                    ON external_task_links(provider_id, project_id);
                    """
                )
            },
            DatabaseMigration(id: "0010_create_inbox_capture_records") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS inbox_capture_records (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        task_id INTEGER NOT NULL,
                        source_kind TEXT NOT NULL CHECK(source_kind IN ('voice_memo')),
                        audio_file_path TEXT NOT NULL,
                        duration_seconds REAL NOT NULL CHECK(duration_seconds >= 0),
                        transcript TEXT,
                        interpretation_summary TEXT,
                        memo TEXT,
                        classification_status TEXT NOT NULL CHECK(classification_status IN ('unclassified', 'classified', 'dismissed')),
                        transcription_status TEXT NOT NULL CHECK(transcription_status IN ('pending', 'succeeded', 'failed')),
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY(task_id) REFERENCES tasks(id) ON DELETE CASCADE
                    );

                    CREATE INDEX IF NOT EXISTS idx_inbox_capture_records_task
                    ON inbox_capture_records(task_id);

                    CREATE INDEX IF NOT EXISTS idx_inbox_capture_records_created_at
                    ON inbox_capture_records(created_at);
                    """
                )
            },
            DatabaseMigration(id: "0011_create_project_milestones") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS project_milestones (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        project_id INTEGER NOT NULL,
                        title TEXT NOT NULL,
                        due_at TEXT,
                        is_completed INTEGER NOT NULL DEFAULT 0 CHECK(is_completed IN (0, 1)),
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
                    );

                    CREATE INDEX IF NOT EXISTS idx_project_milestones_project
                    ON project_milestones(project_id);

                    CREATE INDEX IF NOT EXISTS idx_project_milestones_due_at
                    ON project_milestones(due_at);
                    """
                )
            },
            DatabaseMigration(id: "0012_add_task_completed_at") { connection in
                let columns = try connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
                guard !columns.contains("completed_at") else {
                    return
                }
                try connection.execute("ALTER TABLE tasks ADD COLUMN completed_at TEXT;")
                try connection.execute(
                    """
                    UPDATE tasks
                    SET completed_at = strftime('%Y-%m-%dT%H:%M:%SZ', COALESCE(updated_at, 'now'))
                    WHERE status = 'completed'
                      AND completed_at IS NULL;
                    """
                )
            },
            DatabaseMigration(id: "0013_create_missed_task_review_state") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS missed_task_review_state (
                        task_id INTEGER PRIMARY KEY NOT NULL,
                        last_reviewed_at TEXT,
                        last_reviewed_day TEXT,
                        last_notified_day TEXT,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_missed_task_review_state_reviewed_day
                    ON missed_task_review_state(last_reviewed_day);

                    CREATE INDEX IF NOT EXISTS idx_missed_task_review_state_notified_day
                    ON missed_task_review_state(last_notified_day);
                    """
                )
            },
            DatabaseMigration(id: "0014_add_project_workspace_bookmark") { connection in
                let columns = try connection.queryRows("PRAGMA table_info(projects);").compactMap { $0["name"] }
                guard !columns.contains("workspace_bookmark") else {
                    return
                }
                try connection.execute("ALTER TABLE projects ADD COLUMN workspace_bookmark TEXT;")
            },
            DatabaseMigration(id: "0015_create_assistant_queue_items") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS assistant_queue_items (
                        id TEXT PRIMARY KEY NOT NULL,
                        schema_version INTEGER NOT NULL DEFAULT 1,
                        payload_kind TEXT NOT NULL,
                        payload_json TEXT NOT NULL,
                        state TEXT NOT NULL,
                        risk_level TEXT NOT NULL,
                        source_transcript TEXT,
                        interpretation_summary TEXT,
                        review_reason TEXT NOT NULL,
                        redacted_summary TEXT NOT NULL,
                        required_capabilities_json TEXT NOT NULL DEFAULT '[]',
                        approval_json TEXT,
                        blocking_reason TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_assistant_queue_items_state_updated_at
                    ON assistant_queue_items(state, updated_at);

                    CREATE INDEX IF NOT EXISTS idx_assistant_queue_items_payload_kind
                    ON assistant_queue_items(payload_kind);
                    """
                )
            },
            DatabaseMigration(id: "0016_add_assistant_queue_cost_preview") { connection in
                let columns = try connection.queryRows("PRAGMA table_info(assistant_queue_items);").compactMap { $0["name"] }
                if !columns.contains("cost_preview_json") {
                    try connection.execute("ALTER TABLE assistant_queue_items ADD COLUMN cost_preview_json TEXT;")
                }

                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let previewJSON = String(
                    decoding: try encoder.encode(AssistantQueueCostPreview.localOnly(
                        note: "Legacy local execution preview added during migration. No SoloPM managed charge before run."
                    )),
                    as: UTF8.self
                )
                try connection.execute(
                    """
                    UPDATE assistant_queue_items
                    SET cost_preview_json = ?
                    WHERE cost_preview_json IS NULL;
                    """,
                    parameters: [.text(previewJSON)]
                )

                try connection.execute(
                    """
                    UPDATE assistant_queue_items
                    SET state = 'waitingReview',
                        approval_json = NULL,
                        review_reason = 'Cost preview was added during migration. Review this item again before running.',
                        updated_at = CURRENT_TIMESTAMP
                    WHERE state IN ('approved', 'running');
                    """
                )
            },
            DatabaseMigration(id: "0017_scope_artifact_uniqueness_to_owner") { connection in
                try connection.execute(
                    """
                    CREATE TABLE artifacts_new (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        project_id INTEGER,
                        task_id INTEGER,
                        workspace_path TEXT NOT NULL,
                        expected_path TEXT NOT NULL,
                        created_state TEXT NOT NULL CHECK(created_state IN ('expected', 'created', 'missing')),
                        last_modified_at TEXT,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    INSERT INTO artifacts_new (
                        id,
                        project_id,
                        task_id,
                        workspace_path,
                        expected_path,
                        created_state,
                        last_modified_at,
                        created_at,
                        updated_at
                    )
                    SELECT
                        id,
                        project_id,
                        task_id,
                        workspace_path,
                        expected_path,
                        created_state,
                        last_modified_at,
                        created_at,
                        updated_at
                    FROM artifacts;

                    DELETE FROM artifacts_new
                    WHERE id IN (
                        SELECT id
                        FROM (
                            SELECT
                                id,
                                ROW_NUMBER() OVER (
                                    PARTITION BY IFNULL(project_id, -1), IFNULL(task_id, -1), expected_path
                                    ORDER BY
                                        CASE created_state
                                            WHEN 'created' THEN 0
                                            WHEN 'expected' THEN 1
                                            ELSE 2
                                        END,
                                        CASE WHEN last_modified_at IS NULL THEN 1 ELSE 0 END,
                                        last_modified_at DESC,
                                        id ASC
                                ) AS duplicate_rank
                            FROM artifacts_new
                        )
                        WHERE duplicate_rank > 1
                    );

                    DROP TABLE artifacts;
                    ALTER TABLE artifacts_new RENAME TO artifacts;

                    CREATE INDEX IF NOT EXISTS idx_artifacts_workspace_path
                    ON artifacts(workspace_path);

                    CREATE INDEX IF NOT EXISTS idx_artifacts_last_modified_at
                    ON artifacts(last_modified_at);

                    CREATE UNIQUE INDEX IF NOT EXISTS idx_artifacts_owner_expected_path
                    ON artifacts(IFNULL(project_id, -1), IFNULL(task_id, -1), expected_path);
                    """
                )
            },
            DatabaseMigration(id: "0018_create_managed_ai_usage_ledger") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS managed_ai_usage_ledger (
                        source_receipt_digest TEXT PRIMARY KEY NOT NULL,
                        assistant_queue_item_digest TEXT,
                        billing_mode TEXT NOT NULL CHECK(billing_mode IN ('solopm_managed')),
                        provider TEXT NOT NULL,
                        model_name TEXT NOT NULL,
                        usage_state TEXT NOT NULL CHECK(usage_state IN ('measured', 'estimated', 'unknown', 'unavailable')),
                        input_tokens INTEGER CHECK(input_tokens IS NULL OR input_tokens >= 0),
                        output_tokens INTEGER CHECK(output_tokens IS NULL OR output_tokens >= 0),
                        cost_cents REAL NOT NULL CHECK(cost_cents >= 0),
                        currency_code TEXT NOT NULL,
                        occurred_at TEXT NOT NULL,
                        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );

                    CREATE INDEX IF NOT EXISTS idx_managed_ai_usage_ledger_occurred_at
                    ON managed_ai_usage_ledger(occurred_at);

                    CREATE UNIQUE INDEX IF NOT EXISTS idx_managed_ai_usage_ledger_queue_digest
                    ON managed_ai_usage_ledger(assistant_queue_item_digest);
                    """
                )
            },
            DatabaseMigration(id: "0019_add_work_management_read_model_indexes") { connection in
                try connection.execute(
                    """
                    CREATE INDEX IF NOT EXISTS idx_tasks_project_id
                    ON tasks(project_id);

                    CREATE INDEX IF NOT EXISTS idx_tasks_status_due_at
                    ON tasks(status, due_at);

                    CREATE INDEX IF NOT EXISTS idx_tasks_due_at_status
                    ON tasks(due_at, status);

                    CREATE INDEX IF NOT EXISTS idx_tasks_project_status
                    ON tasks(project_id, status);

                    CREATE INDEX IF NOT EXISTS idx_tasks_completed_at
                    ON tasks(completed_at);

                    CREATE INDEX IF NOT EXISTS idx_projects_status
                    ON projects(status);

                    CREATE INDEX IF NOT EXISTS idx_artifacts_project_task
                    ON artifacts(project_id, task_id);

                    CREATE INDEX IF NOT EXISTS idx_artifacts_task_project
                    ON artifacts(task_id, project_id);

                    CREATE INDEX IF NOT EXISTS idx_project_milestones_project_due_sort
                    ON project_milestones(project_id, due_at IS NULL, due_at);
                    """
                )
            },
            DatabaseMigration(id: "0020_create_morning_digest_state") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS morning_digest_state (
                        id INTEGER PRIMARY KEY CHECK(id = 1),
                        last_digest_day TEXT,
                        recorded_at TEXT,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    """
                )
            },
            DatabaseMigration(id: "0021_create_weekly_review_state") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS weekly_review_state (
                        id INTEGER PRIMARY KEY CHECK(id = 1),
                        last_summary_week TEXT,
                        recorded_at TEXT,
                        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                    );
                    """
                )
            },
        ]
    }
}
