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

    public init(path: String) throws {
        let status = sqlite3_open(path, &database)
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
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )

        let alreadyApplied = Set(try appliedMigrationIDs())

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

    public func appliedMigrationIDs() throws -> [String] {
        try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;")
    }

    public func tableExists(_ tableName: String) throws -> Bool {
        try connection.tableExists(tableName)
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
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
}
