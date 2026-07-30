import Foundation

public enum VoiceTaskConversationOrchestrationStateStoreError:
    Error,
    Equatable,
    Sendable
{
    case corruptState(UUID)
}

/// Durable checkpoint for an in-progress clarification.
///
/// The encoded value is a typed orchestration state rather than an ad-hoc
/// transcript cache. Keeping the original intent and clarification trail in
/// one SQLite upsert makes restart recovery atomic and prevents a later answer
/// from being applied to a different command.
public final class SQLiteVoiceTaskConversationOrchestrationStateStore:
    VoiceTaskConversationOrchestrationStateStore,
    @unchecked Sendable
{
    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: @Sendable () -> Date

    public init(
        connection: SQLiteConnection,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.connection = connection
        self.now = now
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    public convenience init(
        path: String,
        migrations: [DatabaseMigration] = CoreMigrations.current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrations
        )
        self.init(connection: connection, now: now)
    }

    public func load(
        sessionID: UUID
    ) throws -> VoiceTaskConversationOrchestrationState? {
        lock.lock()
        defer { lock.unlock() }
        let rows = try connection.queryRows(
            """
            SELECT payload
            FROM voice_task_conversation_orchestration_states
            WHERE session_id = ?
            LIMIT 1;
            """,
            parameters: [.text(sessionID.uuidString)]
        )
        guard let row = rows.first else {
            return nil
        }
        guard case .blob(let payload) = try row.cell("payload"),
              let state = try? decoder.decode(
                  VoiceTaskConversationOrchestrationState.self,
                  from: payload
              ),
              state.sessionID == sessionID
        else {
            throw VoiceTaskConversationOrchestrationStateStoreError
                .corruptState(sessionID)
        }
        return state
    }

    public func save(
        _ state: VoiceTaskConversationOrchestrationState
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        let payload = try encoder.encode(state)
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_orchestration_states (
                session_id,
                payload,
                updated_at
            )
            VALUES (?, ?, ?)
            ON CONFLICT(session_id) DO UPDATE SET
                payload = excluded.payload,
                updated_at = excluded.updated_at;
            """,
            parameters: [
                .text(state.sessionID.uuidString),
                .blob(payload),
                .real(now().timeIntervalSince1970),
            ]
        )
    }

    public func remove(sessionID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try connection.execute(
            """
            DELETE FROM voice_task_conversation_orchestration_states
            WHERE session_id = ?;
            """,
            parameters: [.text(sessionID.uuidString)]
        )
    }
}
