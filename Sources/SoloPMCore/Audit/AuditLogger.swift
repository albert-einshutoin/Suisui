import Foundation

public struct AuditEvent: Equatable, Sendable {
    public var timestamp: Date
    public var category: String
    public var action: String
    public var status: AuditStatus
    public var metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        category: String,
        action: String,
        status: AuditStatus,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.category = category
        self.action = action
        self.status = status
        self.metadata = metadata
    }
}

public enum AuditStatus: String, Equatable, Sendable {
    case started
    case succeeded
    case failed
    case skipped
}

public protocol AuditLogger: Sendable {
    func record(_ event: AuditEvent) throws
}

public final class SQLiteAuditLogger: AuditLogger, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let dateFormatter = ISO8601DateFormatter()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public convenience init(path: String, migrations: [DatabaseMigration] = CoreMigrations.current) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    public func record(_ event: AuditEvent) throws {
        lock.lock()
        defer { lock.unlock() }

        let metadataData = try JSONEncoder().encode(event.metadata)
        guard let metadata = String(data: metadataData, encoding: .utf8) else {
            throw DatabaseError.executeFailed("Could not encode audit_logs.metadata_json as UTF-8 JSON.")
        }
        try connection.execute(
            """
            INSERT INTO audit_logs (timestamp, category, action, status, metadata_json)
            VALUES (
              '\(SQLAudit.escape(dateFormatter.string(from: event.timestamp)))',
              '\(SQLAudit.escape(event.category))',
              '\(SQLAudit.escape(event.action))',
              '\(SQLAudit.escape(event.status.rawValue))',
              '\(SQLAudit.escape(metadata))'
            );
            """
        )
    }

    public func list(limit: Int = 100) throws -> [AuditEvent] {
        lock.lock()
        defer { lock.unlock() }

        let boundedLimit = max(1, min(limit, 500))
        return try connection.queryRows(
            """
            SELECT timestamp, category, action, status, metadata_json
            FROM audit_logs
            ORDER BY id DESC
            LIMIT \(boundedLimit);
            """
        ).map { row in
            let timestampText = try SQLAudit.requiredString(row["timestamp"], column: "audit_logs.timestamp")
            guard let timestamp = dateFormatter.date(from: timestampText) else {
                throw LocalStoreDecodingError.invalidDate(column: "audit_logs.timestamp", value: timestampText)
            }
            let statusText = try SQLAudit.requiredString(row["status"], column: "audit_logs.status")
            guard let status = AuditStatus(rawValue: statusText) else {
                throw LocalStoreDecodingError.invalidEnum(column: "audit_logs.status", value: statusText)
            }
            return AuditEvent(
                timestamp: timestamp,
                category: try SQLAudit.requiredString(row["category"], column: "audit_logs.category"),
                action: try SQLAudit.requiredString(row["action"], column: "audit_logs.action"),
                status: status,
                metadata: try SQLAudit.decodeMetadata(
                    try SQLAudit.requiredString(row["metadata_json"], column: "audit_logs.metadata_json"),
                    column: "audit_logs.metadata_json"
                )
            )
        }
    }
}

public struct RedactingAuditLogger: AuditLogger {
    private let base: AuditLogger

    public init(base: AuditLogger) {
        self.base = base
    }

    public func record(_ event: AuditEvent) throws {
        var redacted = event
        redacted.metadata = SecretRedactor.redact(metadata: event.metadata)
        try base.record(redacted)
    }
}

private enum SQLAudit {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    static func decodeMetadata(_ value: String, column: String) throws -> [String: String] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw LocalStoreDecodingError.invalidStringMap(column: column)
        }

        return decoded
    }

    static func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        return value
    }
}

public enum SecretRedactor {
    private static let sensitiveFragments = [
        "api_key",
        "apikey",
        "authorization",
        "bearer",
        "secret",
        "token",
        "password"
    ]

    public static func redact(metadata: [String: String]) -> [String: String] {
        metadata.mapValues { value in
            containsSensitiveValue(value) ? "[REDACTED]" : value
        }.reduce(into: [:]) { result, pair in
            let key = pair.key
            let value = pair.value
            result[key] = containsSensitiveKey(key) ? "[REDACTED]" : value
        }
    }

    private static func containsSensitiveKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return sensitiveFragments.contains { normalized.contains($0) }
    }

    private static func containsSensitiveValue(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.hasPrefix("bearer ")
            || normalized.contains("sk-")
            || normalized.contains("api_key=")
            || normalized.contains("apikey=")
            || normalized.contains("authorization=")
            || normalized.contains("token=")
            || normalized.contains("password=")
            || normalized.contains("secret=")
    }
}
