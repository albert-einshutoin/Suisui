import Foundation

public final class SQLiteDeadlineRuleStore: @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func create(_ rule: DeadlineRule) throws -> DeadlineRule {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO deadline_rules (
              target_type,
              target_id,
              kind,
              custom_notify_at,
              muted_at,
              last_notified_at
            )
            VALUES (
              '\(SQL.escape(rule.target.targetType))',
              \(rule.target.targetID),
              '\(SQL.escape(rule.kind.rawValue))',
              \(SQL.optionalDate(rule.customNotifyAt)),
              \(SQL.optionalDate(rule.mutedAt)),
              \(SQL.optionalDate(rule.lastNotifiedAt))
            );
            """
        )

        return try getLocked(id: connection.lastInsertedRowID)
    }

    public func list() throws -> [DeadlineRule] {
        lock.lock()
        defer { lock.unlock() }

        return try connection
            .queryRows("SELECT * FROM deadline_rules ORDER BY id ASC;")
            .map { try DeadlineRule(row: $0) }
    }

    public func list(for target: DeadlineRuleTarget) throws -> [DeadlineRule] {
        lock.lock()
        defer { lock.unlock() }

        return try connection.queryRows(
            """
            SELECT * FROM deadline_rules
            WHERE target_type = '\(SQL.escape(target.targetType))' AND target_id = \(target.targetID)
            ORDER BY id ASC;
            """
        ).map { try DeadlineRule(row: $0) }
    }

    public func markNotified(id: Int64, at notifiedAt: Date) throws -> DeadlineRule {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            UPDATE deadline_rules
            SET last_notified_at = '\(SQL.escape(DeadlineDateParser.string(from: notifiedAt)))',
                updated_at = CURRENT_TIMESTAMP
            WHERE id = \(id);
            """
        )
        return try getLocked(id: id)
    }

    public func get(id: Int64) throws -> DeadlineRule {
        lock.lock()
        defer { lock.unlock() }
        return try getLocked(id: id)
    }

    private func getLocked(id: Int64) throws -> DeadlineRule {
        guard let row = try connection
            .queryRows("SELECT * FROM deadline_rules WHERE id = \(id) LIMIT 1;")
            .first else {
            throw DatabaseError.stepFailed("Deadline rule \(id) was not found.")
        }

        return try DeadlineRule(row: row)
    }
}

private extension DeadlineRule {
    init(row: [String: String]) throws {
        let id = try SQL.requiredInt64(row["id"], column: "deadline_rules.id")
        let targetType = try SQL.requiredString(row["target_type"], column: "deadline_rules.target_type")
        let targetID = try SQL.requiredInt64(row["target_id"], column: "deadline_rules.target_id")
        guard let target = DeadlineRuleTarget(targetType: targetType, targetID: targetID) else {
            throw LocalStoreDecodingError.invalidEnum(column: "deadline_rules.target_type", value: targetType)
        }
        let kindValue = try SQL.requiredString(row["kind"], column: "deadline_rules.kind")
        guard let kind = DeadlineRuleKind(rawValue: kindValue) else {
            throw LocalStoreDecodingError.invalidEnum(column: "deadline_rules.kind", value: kindValue)
        }

        self.init(
            id: id,
            target: target,
            kind: kind,
            customNotifyAt: try SQL.optionalDate(row["custom_notify_at"], column: "deadline_rules.custom_notify_at"),
            mutedAt: try SQL.optionalDate(row["muted_at"], column: "deadline_rules.muted_at"),
            lastNotifiedAt: try SQL.optionalDate(row["last_notified_at"], column: "deadline_rules.last_notified_at")
        )
    }
}

private enum SQL {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    static func optionalDate(_ value: Date?) -> String {
        guard let value else {
            return "NULL"
        }

        return "'\(escape(DeadlineDateParser.string(from: value)))'"
    }

    static func optionalDate(_ value: String?, column: String) throws -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }

        guard let date = DeadlineDateParser.date(from: value) else {
            throw LocalStoreDecodingError.invalidDate(column: column, value: value)
        }
        return date
    }

    static func requiredString(_ value: String?, column: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw LocalStoreDecodingError.missingRequiredColumn(column: column)
        }
        return value
    }

    static func requiredInt64(_ value: String?, column: String) throws -> Int64 {
        let required = try requiredString(value, column: column)
        guard let intValue = Int64(required) else {
            throw LocalStoreDecodingError.invalidInt64(column: column, value: required)
        }
        return intValue
    }
}
