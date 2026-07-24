import Foundation
import SQLite3

public enum DatabaseError: Error, Equatable, Sendable {
    case openFailed(String)
    case executeFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case busyTimeout(operation: String)
    case missingColumn(String)
    case duplicateColumnName(String)
    case invalidColumnValue(column: String, value: String)
    case nestedTransaction
}

public enum SQLiteCell: Equatable, Sendable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    fileprivate var storageClass: String {
        switch self {
        case .null:
            "null"
        case .integer:
            "integer"
        case .real:
            "real"
        case .text:
            "text"
        case .blob:
            "blob"
        }
    }

    fileprivate var legacyString: String? {
        switch self {
        case .null:
            nil
        case .integer(let value):
            String(value)
        case .real(let value):
            String(value)
        case .text(let value):
            value
        case .blob(let value):
            String(decoding: value, as: UTF8.self)
        }
    }
}

public struct SQLiteMaterializedRow: Equatable, Sendable {
    public let cells: [String: SQLiteCell]

    public init(cells: [String: SQLiteCell]) {
        self.cells = cells
    }

    public subscript(column: String) -> String? {
        cells[column]?.legacyString
    }

    public func cell(_ column: String) throws -> SQLiteCell {
        guard let value = cells[column] else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func string(_ column: String) throws -> String {
        guard let value = try optionalString(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalString(_ column: String) throws -> String? {
        switch try cell(column) {
        case .null:
            return nil
        case .text(let value):
            return value
        case let value:
            throw DatabaseError.invalidColumnValue(column: column, value: value.storageClass)
        }
    }

    public func int64(_ column: String) throws -> Int64 {
        guard let value = try optionalInt64(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalInt64(_ column: String) throws -> Int64? {
        switch try cell(column) {
        case .null:
            return nil
        case .integer(let value):
            return value
        case let value:
            throw DatabaseError.invalidColumnValue(column: column, value: value.storageClass)
        }
    }

    public func double(_ column: String) throws -> Double {
        guard let value = try optionalDouble(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalDouble(_ column: String) throws -> Double? {
        switch try cell(column) {
        case .null:
            return nil
        case .real(let value):
            return value
        case let value:
            throw DatabaseError.invalidColumnValue(column: column, value: value.storageClass)
        }
    }

    public func bool(_ column: String) throws -> Bool {
        guard let value = try optionalBool(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalBool(_ column: String) throws -> Bool? {
        switch try cell(column) {
        case .null:
            return nil
        case .integer(0):
            return false
        case .integer(1):
            return true
        case let value:
            throw DatabaseError.invalidColumnValue(column: column, value: value.storageClass)
        }
    }

    public func data(_ column: String) throws -> Data {
        guard let value = try optionalData(column) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalData(_ column: String) throws -> Data? {
        switch try cell(column) {
        case .null:
            return nil
        case .blob(let value):
            return value
        case let value:
            throw DatabaseError.invalidColumnValue(column: column, value: value.storageClass)
        }
    }

    public func date(
        _ column: String,
        using parser: (String) -> Date?
    ) throws -> Date {
        guard let value = try optionalDate(column, using: parser) else {
            throw DatabaseError.missingColumn(column)
        }
        return value
    }

    public func optionalDate(
        _ column: String,
        using parser: (String) -> Date?
    ) throws -> Date? {
        guard let value = try optionalString(column) else {
            return nil
        }
        guard let date = parser(value) else {
            throw DatabaseError.invalidColumnValue(column: column, value: "text")
        }
        return date
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

public struct SQLiteDatabaseMetric: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case lockWait
        case operationDuration
        case rollback
    }

    public let kind: Kind
    public let operation: String
    public let durationMilliseconds: Double?
    public let category: String?

    public init(
        kind: Kind,
        operation: String,
        durationMilliseconds: Double? = nil,
        category: String? = nil
    ) {
        self.kind = kind
        self.operation = operation
        self.durationMilliseconds = durationMilliseconds
        self.category = category
    }
}

public final class SQLiteConnection: @unchecked Sendable {
    public static let busyTimeoutMilliseconds: Int32 = 250
    public static let walAutoCheckpointPages = 1_000

    private var database: OpaquePointer?
    private let accessLock = NSRecursiveLock()
    private var accessDepth = 0
    private var transactionDepth = 0
    private let metricSink: (@Sendable (SQLiteDatabaseMetric) -> Void)?
    // sqlite3_bind copies bound buffers when given SQLITE_TRANSIENT, so Swift
    // strings and Data can be released as soon as the bind call returns.
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(
        path: String,
        readOnly: Bool = false,
        metricSink: (@Sendable (SQLiteDatabaseMetric) -> Void)? = nil
    ) throws {
        self.metricSink = metricSink
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
            | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(path, &database, flags, nil)
        guard status == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite open error."
            throw DatabaseError.openFailed(message)
        }
        try configure(readOnly: readOnly)
    }

    deinit {
        accessLock.lock()
        sqlite3_close(database)
        accessLock.unlock()
    }

    public var numberOfChanges: Int {
        withAccessLock(operation: "number_of_changes") {
            Int(sqlite3_changes(database))
        }
    }

    public func execute(_ sql: String) throws {
        try withAccessLock(operation: "execute") {
            try executeUnlocked(sql)
        }
    }

    private func executeUnlocked(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<Int8>?
        let status = sqlite3_exec(database, sql, nil, nil, &errorMessage)

        guard status == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite execution error."
            sqlite3_free(errorMessage)
            throw classifiedError(status: status, operation: "execute", fallback: .executeFailed(message))
        }
    }

    /// Executes a single statement with `?` placeholders bound to `parameters`.
    /// Binding happens inside SQLite, so values never require manual escaping.
    public func execute(_ sql: String, parameters: [SQLiteValue]) throws {
        try withAccessLock(operation: "execute_bound") {
            let statement = try prepare(sql, parameters: parameters)
            defer { sqlite3_finalize(statement) }

            let stepStatus = sqlite3_step(statement)
            guard stepStatus == SQLITE_DONE || stepStatus == SQLITE_ROW else {
                throw classifiedError(
                    status: stepStatus,
                    operation: "execute step",
                    fallback: .stepFailed(errorMessage)
                )
            }
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        var rollbackCategory: String?
        do {
            return try withAccessLock(operation: "transaction") {
                guard transactionDepth == 0 else {
                    throw DatabaseError.nestedTransaction
                }
                transactionDepth = 1
                defer { transactionDepth = 0 }

                try executeUnlocked("BEGIN;")
                do {
                    let result = try body()
                    try executeUnlocked("COMMIT;")
                    return result
                } catch {
                    rollbackCategory = Self.rollbackCategory(for: error)
                    try? executeUnlocked("ROLLBACK;")
                    throw error
                }
            }
        } catch {
            if let rollbackCategory {
                metricSink?(
                    SQLiteDatabaseMetric(
                        kind: .rollback,
                        operation: "transaction",
                        category: rollbackCategory
                    )
                )
            }
            throw error
        }
    }

    public func queryStrings(_ sql: String, parameters: [SQLiteValue] = []) throws -> [String] {
        try withAccessLock(operation: "query_strings") {
            let statement = try prepare(sql, parameters: parameters)
            defer { sqlite3_finalize(statement) }

            var results: [String] = []

            while true {
                let stepStatus = sqlite3_step(statement)

                if stepStatus == SQLITE_ROW {
                    if let value = Self.materializedCell(
                        statement: statement,
                        index: 0
                    ).legacyString {
                        results.append(value)
                    }
                } else if stepStatus == SQLITE_DONE {
                    return results
                } else {
                    throw classifiedError(
                        status: stepStatus,
                        operation: "query strings step",
                        fallback: .stepFailed(errorMessage)
                    )
                }
            }
        }
    }

    public func materializedRows(
        _ sql: String,
        parameters: [SQLiteValue] = []
    ) throws -> [SQLiteMaterializedRow] {
        try withAccessLock(operation: "query_materialized") {
            let statement = try prepare(sql, parameters: parameters)
            defer { sqlite3_finalize(statement) }

            let columns = try columnIndexes(for: statement)
            var rows: [SQLiteMaterializedRow] = []

            while true {
                let stepStatus = sqlite3_step(statement)

                if stepStatus == SQLITE_ROW {
                    var cells: [String: SQLiteCell] = [:]
                    for (name, index) in columns {
                        cells[name] = Self.materializedCell(statement: statement, index: index)
                    }
                    rows.append(SQLiteMaterializedRow(cells: cells))
                } else if stepStatus == SQLITE_DONE {
                    return rows
                } else {
                    throw classifiedError(
                        status: stepStatus,
                        operation: "materialized query step",
                        fallback: .stepFailed(errorMessage)
                    )
                }
            }
        }
    }

    public func queryRows(
        _ sql: String,
        parameters: [SQLiteValue] = []
    ) throws -> [SQLiteMaterializedRow] {
        try materializedRows(sql, parameters: parameters)
    }

    public var lastInsertedRowID: Int64 {
        withAccessLock(operation: "last_inserted_row_id") {
            sqlite3_last_insert_rowid(database)
        }
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
            throw classifiedError(
                status: prepareStatus,
                operation: "prepare",
                fallback: .prepareFailed(errorMessage)
            )
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
                // Bind the explicit UTF-8 byte count so embedded NUL remains
                // data instead of being mistaken for a C-string terminator.
                bindStatus = value.utf8CString.withUnsafeBufferPointer { buffer in
                    sqlite3_bind_text(
                        statement,
                        index,
                        buffer.baseAddress,
                        Int32(buffer.count - 1),
                        Self.transientDestructor
                    )
                }
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

    private func columnIndexes(for statement: OpaquePointer?) throws -> [String: Int32] {
        var indexes: [String: Int32] = [:]
        for index in 0..<sqlite3_column_count(statement) {
            let name = String(cString: sqlite3_column_name(statement, index))
            guard indexes[name] == nil else {
                throw DatabaseError.duplicateColumnName(name)
            }
            indexes[name] = index
        }
        return indexes
    }

    fileprivate static func materializedCell(
        statement: OpaquePointer?,
        index: Int32
    ) -> SQLiteCell {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return .null
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let bytes = sqlite3_column_text(statement, index) else {
                return .text("")
            }
            let count = Int(sqlite3_column_bytes(statement, index))
            let buffer = UnsafeRawBufferPointer(start: bytes, count: count)
            return .text(String(decoding: buffer, as: UTF8.self))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(statement, index))
            guard count > 0, let bytes = sqlite3_column_blob(statement, index) else {
                return .blob(Data())
            }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private func configure(readOnly: Bool) throws {
        let timeoutStatus = sqlite3_busy_timeout(database, Self.busyTimeoutMilliseconds)
        guard timeoutStatus == SQLITE_OK else {
            throw DatabaseError.openFailed(errorMessage)
        }

        // SQLite reports an empty main filename for transient databases. Use
        // the opened handle as the source of truth instead of parsing input paths.
        let isFileBacked = sqlite3_db_filename(database, "main")
            .map { !String(cString: $0).isEmpty } ?? false
        try configurePragma("foreign_keys", value: "ON")
        try configurePragma("temp_store", value: "MEMORY")
        if !readOnly {
            if isFileBacked {
                try configurePragma("journal_mode", value: "WAL")
                try configurePragma(
                    "wal_autocheckpoint",
                    value: String(Self.walAutoCheckpointPages)
                )
            }
            try configurePragma("synchronous", value: "NORMAL")
        }

        try verifyPragma("foreign_keys", expected: "1")
        try verifyPragma("busy_timeout", expected: String(Self.busyTimeoutMilliseconds))
        try verifyPragma("temp_store", expected: "2")
        if !readOnly {
            try verifyPragma("synchronous", expected: "1")
            if isFileBacked {
                try verifyPragma("journal_mode", expected: "wal")
                try verifyPragma(
                    "wal_autocheckpoint",
                    expected: String(Self.walAutoCheckpointPages)
                )
            }
        }
    }

    private func configurePragma(_ name: String, value: String) throws {
        let status = sqlite3_exec(database, "PRAGMA \(name) = \(value);", nil, nil, nil)
        guard status == SQLITE_OK else {
            throw DatabaseError.openFailed(errorMessage)
        }
    }

    private func verifyPragma(_ name: String, expected: String) throws {
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(database, "PRAGMA \(name);", -1, &statement, nil)
        guard prepareStatus == SQLITE_OK else {
            sqlite3_finalize(statement)
            throw DatabaseError.openFailed(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let actual = Self.materializedCell(
                  statement: statement,
                  index: 0
              ).legacyString?.lowercased(),
              actual == expected.lowercased() else {
            throw DatabaseError.openFailed(
                "SQLite PRAGMA \(name) did not apply the required value."
            )
        }
    }

    private func classifiedError(
        status: Int32,
        operation: String,
        fallback: DatabaseError
    ) -> DatabaseError {
        if status == SQLITE_BUSY || status == SQLITE_LOCKED {
            return .busyTimeout(operation: operation)
        }
        return fallback
    }

    private static func rollbackCategory(for error: Error) -> String {
        switch error {
        case is CancellationError:
            "cancelled"
        case DatabaseError.busyTimeout:
            "busy_timeout"
        case DatabaseError.nestedTransaction:
            "nested_transaction"
        default:
            "operation_failed"
        }
    }

    private func withAccessLock<T>(
        operation: String,
        _ body: () throws -> T
    ) rethrows -> T {
        let waitStartedAt = ProcessInfo.processInfo.systemUptime
        accessLock.lock()
        let acquiredAt = ProcessInfo.processInfo.systemUptime
        let shouldEmitMetrics = accessDepth == 0
        accessDepth += 1
        do {
            let result = try body()
            let finishedAt = ProcessInfo.processInfo.systemUptime
            accessDepth -= 1
            accessLock.unlock()
            if shouldEmitMetrics {
                // Nested connection calls inherit the outer operation's timing.
                // Emitting only after the outermost unlock keeps metric sinks
                // outside the SQLite ownership boundary and avoids callback re-entry.
                emitTimingMetrics(
                    operation: operation,
                    waitStartedAt: waitStartedAt,
                    acquiredAt: acquiredAt,
                    finishedAt: finishedAt
                )
            }
            return result
        } catch {
            let finishedAt = ProcessInfo.processInfo.systemUptime
            accessDepth -= 1
            accessLock.unlock()
            if shouldEmitMetrics {
                emitTimingMetrics(
                    operation: operation,
                    waitStartedAt: waitStartedAt,
                    acquiredAt: acquiredAt,
                    finishedAt: finishedAt
                )
            }
            throw error
        }
    }

    private func emitTimingMetrics(
        operation: String,
        waitStartedAt: TimeInterval,
        acquiredAt: TimeInterval,
        finishedAt: TimeInterval
    ) {
        guard let metricSink else {
            return
        }
        metricSink(
            SQLiteDatabaseMetric(
                kind: .lockWait,
                operation: operation,
                durationMilliseconds: (acquiredAt - waitStartedAt) * 1_000
            )
        )
        metricSink(
            SQLiteDatabaseMetric(
                kind: .operationDuration,
                operation: operation,
                durationMilliseconds: (finishedAt - acquiredAt) * 1_000
            )
        )
    }
}

public actor SQLiteDatabaseWorker {
    private let connection: SQLiteConnection

    public init(path: String, readOnly: Bool = false) throws {
        self.connection = try SQLiteConnection(path: path, readOnly: readOnly)
    }

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func run<T: Sendable>(
        _ operation: @Sendable (SQLiteConnection) throws -> T
    ) throws -> T {
        try Task.checkCancellation()
        let result = try operation(connection)
        try Task.checkCancellation()
        return result
    }

    public func transaction<T: Sendable>(
        _ operation: @Sendable (SQLiteConnection) throws -> T
    ) throws -> T {
        try Task.checkCancellation()
        return try connection.transaction {
            let result = try operation(connection)
            // Cancellation is checked before COMMIT so an abandoned task
            // rolls back instead of publishing a partial user operation.
            try Task.checkCancellation()
            return result
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
            try connection.transaction {
                try migration.apply(connection)
                try connection.execute(
                    "INSERT INTO schema_migrations (id) VALUES (?);",
                    parameters: [.text(migration.id)]
                )
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
                        recurrence TEXT,
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
                        note: "Legacy local execution preview added during migration. No Suisui managed charge before run."
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
                        billing_mode TEXT NOT NULL CHECK(billing_mode IN ('suisui_managed')),
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
            DatabaseMigration(id: "0022_add_task_recurrence") { connection in
                let columns = try connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
                guard !columns.contains("recurrence") else {
                    return
                }
                try connection.execute("ALTER TABLE tasks ADD COLUMN recurrence TEXT;")
            },
            DatabaseMigration(id: "0023_create_approval_execution_nonces") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS approval_execution_nonces (
                        nonce TEXT PRIMARY KEY NOT NULL,
                        approval_id TEXT NOT NULL,
                        session_id TEXT NOT NULL,
                        plan_id TEXT NOT NULL,
                        canonical_plan_digest BLOB NOT NULL CHECK(length(canonical_plan_digest) = 32),
                        state TEXT NOT NULL CHECK(state IN ('started', 'completed', 'failed', 'unknown')),
                        claimed_at TEXT NOT NULL,
                        updated_at TEXT NOT NULL
                    );

                    CREATE INDEX IF NOT EXISTS idx_approval_execution_nonces_approval_id
                    ON approval_execution_nonces(approval_id);
                    """
                )
            },
            DatabaseMigration(id: "0024_create_external_side_effect_journal") { connection in
                try connection.execute(
                    """
                    CREATE TABLE IF NOT EXISTS external_side_effect_journal (
                        id TEXT PRIMARY KEY NOT NULL,
                        execution_id TEXT NOT NULL,
                        review_session_id TEXT NOT NULL,
                        action_id TEXT NOT NULL,
                        item_index INTEGER,
                        tool TEXT NOT NULL,
                        canonical_arguments_digest BLOB NOT NULL
                            CHECK(length(canonical_arguments_digest) = 32),
                        idempotency_key TEXT NOT NULL UNIQUE,
                        attempt INTEGER NOT NULL CHECK(attempt > 0),
                        state TEXT NOT NULL CHECK(state IN (
                            'prepared',
                            'started',
                            'succeeded',
                            'unknown',
                            'failed_before_side_effect',
                            'compensated'
                        )),
                        external_resource_id TEXT,
                        prepared_at TEXT NOT NULL,
                        started_at TEXT,
                        completed_at TEXT,
                        updated_at TEXT NOT NULL,
                        failure_category TEXT,
                        reconciliation_result TEXT,
                        result_json BLOB
                    );

                    CREATE INDEX IF NOT EXISTS idx_external_side_effect_journal_execution
                    ON external_side_effect_journal(execution_id, item_index);

                    CREATE INDEX IF NOT EXISTS idx_external_side_effect_journal_reconciliation
                    ON external_side_effect_journal(state, updated_at);
                    """
                )
            },
        ]
    }
}
