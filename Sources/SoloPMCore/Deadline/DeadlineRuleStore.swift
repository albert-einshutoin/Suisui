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

        return try connection.queryRows("SELECT * FROM deadline_rules ORDER BY id ASC;").compactMap(DeadlineRule.init(row:))
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
        ).compactMap(DeadlineRule.init(row:))
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
        guard let rule = try connection
            .queryRows("SELECT * FROM deadline_rules WHERE id = \(id) LIMIT 1;")
            .compactMap(DeadlineRule.init(row:))
            .first else {
            throw DatabaseError.stepFailed("Deadline rule \(id) was not found.")
        }

        return rule
    }
}

private extension DeadlineRule {
    init?(row: [String: String]) {
        guard let id = Int64(row["id"] ?? ""),
              let targetID = Int64(row["target_id"] ?? ""),
              let target = DeadlineRuleTarget(targetType: row["target_type"] ?? "", targetID: targetID),
              let kind = DeadlineRuleKind(rawValue: row["kind"] ?? "") else {
            return nil
        }

        self.init(
            id: id,
            target: target,
            kind: kind,
            customNotifyAt: SQL.optionalDate(row["custom_notify_at"]),
            mutedAt: SQL.optionalDate(row["muted_at"]),
            lastNotifiedAt: SQL.optionalDate(row["last_notified_at"])
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

    static func optionalDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else {
            return nil
        }

        return DeadlineDateParser.date(from: value)
    }
}
