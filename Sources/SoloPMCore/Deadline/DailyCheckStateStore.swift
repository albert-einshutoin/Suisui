import Foundation

public protocol DailyCheckStateStore: Sendable {
    func lastRunAt() throws -> Date?
    func recordRun(at date: Date) throws
}

public final class SQLiteDailyCheckStateStore: DailyCheckStateStore, @unchecked Sendable {
    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public func lastRunAt() throws -> Date? {
        lock.lock()
        defer { lock.unlock() }

        let value = try connection.queryStrings("SELECT last_run_at FROM daily_check_state WHERE id = 1 LIMIT 1;").first
        guard let value, !value.isEmpty else {
            return nil
        }

        return DeadlineDateParser.date(from: value)
    }

    public func recordRun(at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }

        try connection.execute(
            """
            INSERT INTO daily_check_state (id, last_run_at, updated_at)
            VALUES (1, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(id) DO UPDATE SET
              last_run_at = excluded.last_run_at,
              updated_at = CURRENT_TIMESTAMP;
            """,
            parameters: [.text(DeadlineDateParser.string(from: date))]
        )
    }
}
