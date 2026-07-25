import Foundation

public final class SQLiteVoiceTaskConversationStore: VoiceTaskConversationStore, @unchecked Sendable {
    public static let maximumPageSize = 500

    private let connection: SQLiteConnection
    private let lock = NSLock()

    public init(connection: SQLiteConnection) {
        self.connection = connection
    }

    public convenience init(
        path: String,
        migrations: [DatabaseMigration] = CoreMigrations.current
    ) throws {
        let connection = try SQLiteConnection(path: path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrations)
        self.init(connection: connection)
    }

    public func createSession(_ session: VoiceTaskConversationSession) throws {
        lock.lock()
        defer { lock.unlock() }
        guard session.lastTurnAt == nil else {
            throw VoiceTaskConversationStoreError.nonEmptyNewSession(session.id)
        }

        try connection.execute(
            """
            INSERT INTO voice_task_conversation_sessions (
                id,
                state,
                title,
                entry_point,
                active_project_id,
                active_task_id,
                resume_summary,
                created_at,
                updated_at,
                last_turn_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: try sessionParameters(session)
        )
    }

    public func updateSession(
        _ session: VoiceTaskConversationSession,
        expectedUpdatedAt: Date
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        try connection.transaction {
            guard let storedSession = try loadSessionUnlocked(id: session.id) else {
                throw VoiceTaskConversationStoreError.missingSession(session.id)
            }
            let expectedTime = try Self.timeValue(expectedUpdatedAt)
            guard storedSession.updatedAt == expectedUpdatedAt,
                  session.updatedAt > expectedUpdatedAt
            else {
                throw VoiceTaskConversationStoreError.staleSession(session.id)
            }
            // The compare-and-swap predicate is part of the write, not only the
            // preceding read. This keeps a later writer from accepting a stale
            // whole-session snapshot and silently reverting another mutation.
            try connection.execute(
                """
                UPDATE voice_task_conversation_sessions
                SET state = ?,
                    title = ?,
                    active_project_id = ?,
                    active_task_id = ?,
                    resume_summary = ?,
                    updated_at = ?,
                    last_turn_at = ?
                WHERE id = ? AND updated_at = ?;
                """,
                parameters: [
                    .text(session.state.rawValue),
                    .text(session.title),
                    SQLiteValue(session.activeProjectID),
                    SQLiteValue(session.activeTaskID),
                    SQLiteValue(session.resumeSummary),
                    .real(try Self.timeValue(session.updatedAt)),
                    try Self.optionalTimeValue(session.lastTurnAt),
                    .text(session.id.uuidString),
                    .real(expectedTime),
                ]
            )
        }
    }

    public func loadSession(id: UUID) throws -> VoiceTaskConversationSession? {
        lock.lock()
        defer { lock.unlock() }
        return try loadSessionUnlocked(id: id)
    }

    public func saveTurn(_ turn: VoiceTaskConversationTurn) throws {
        lock.lock()
        defer { lock.unlock() }

        // A Turn and the Session resume cursor are one logical write. Keeping
        // them in one transaction prevents restart from exposing a Turn that
        // the Session metadata claims never happened.
        try connection.transaction {
            guard var session = try loadSessionUnlocked(id: turn.sessionID) else {
                throw VoiceTaskConversationStoreError.missingSession(turn.sessionID)
            }
            try session.recordTurn(at: turn.createdAt)
            try connection.execute(
                """
                INSERT INTO voice_task_conversation_turns (
                    id,
                    session_id,
                    author,
                    raw_transcript,
                    confirmed_text,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?);
                """,
                parameters: [
                    .text(turn.id.uuidString),
                    .text(turn.sessionID.uuidString),
                    .text(turn.author.rawValue),
                    SQLiteValue(turn.rawTranscript),
                    SQLiteValue(turn.userConfirmedText),
                    .real(try Self.timeValue(turn.createdAt)),
                ]
            )
            try connection.execute(
                """
                UPDATE voice_task_conversation_sessions
                SET updated_at = ?, last_turn_at = ?
                WHERE id = ?;
                """,
                parameters: [
                    .real(try Self.timeValue(session.updatedAt)),
                    .real(try Self.timeValue(requiredLastTurnDate(session))),
                    .text(session.id.uuidString),
                ]
            )
        }
    }

    public func listTurns(
        sessionID: UUID,
        before: Date?,
        limit: Int
    ) throws -> [VoiceTaskConversationTurn] {
        lock.lock()
        defer { lock.unlock() }
        try requireValidLimit(limit)
        guard try sessionExists(sessionID) else {
            throw VoiceTaskConversationStoreError.missingSession(sessionID)
        }

        let rows: [SQLiteMaterializedRow]
        if let before {
            rows = try connection.materializedRows(
                """
                SELECT id, session_id, author, raw_transcript, confirmed_text, created_at
                FROM voice_task_conversation_turns
                WHERE session_id = ? AND created_at < ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?;
                """,
                parameters: [
                    .text(sessionID.uuidString),
                    .real(try Self.timeValue(before)),
                    .integer(Int64(limit)),
                ]
            )
        } else {
            rows = try connection.materializedRows(
                """
                SELECT id, session_id, author, raw_transcript, confirmed_text, created_at
                FROM voice_task_conversation_turns
                WHERE session_id = ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?;
                """,
                parameters: [
                    .text(sessionID.uuidString),
                    .integer(Int64(limit)),
                ]
            )
        }
        return try rows.map(decodeTurn)
    }

    public func listTurnPage(
        sessionID: UUID,
        before: VoiceTaskConversationTurnCursor?,
        limit: Int
    ) throws -> VoiceTaskConversationTurnPage {
        lock.lock()
        defer { lock.unlock() }
        try requireValidLimit(limit)
        guard try sessionExists(sessionID) else {
            throw VoiceTaskConversationStoreError.missingSession(sessionID)
        }

        // The UUID tie-breaker is required because speech Turns can share a
        // timestamp. A Date-only cursor would silently drop equal-time rows at
        // a page boundary.
        let requestedRows = limit + 1
        let rows: [SQLiteMaterializedRow]
        if let before {
            let cursorDate = try Self.timeValue(before.createdAt)
            rows = try connection.materializedRows(
                """
                SELECT id, session_id, author, raw_transcript, confirmed_text, created_at
                FROM voice_task_conversation_turns
                WHERE session_id = ?
                  AND (
                    created_at < ?
                    OR (created_at = ? AND id < ?)
                  )
                ORDER BY created_at DESC, id DESC
                LIMIT ?;
                """,
                parameters: [
                    .text(sessionID.uuidString),
                    .real(cursorDate),
                    .real(cursorDate),
                    .text(before.turnID.uuidString),
                    .integer(Int64(requestedRows)),
                ]
            )
        } else {
            rows = try connection.materializedRows(
                """
                SELECT id, session_id, author, raw_transcript, confirmed_text, created_at
                FROM voice_task_conversation_turns
                WHERE session_id = ?
                ORDER BY created_at DESC, id DESC
                LIMIT ?;
                """,
                parameters: [
                    .text(sessionID.uuidString),
                    .integer(Int64(requestedRows)),
                ]
            )
        }

        let decoded = try rows.map(decodeTurn)
        let hasMore = decoded.count > limit
        let turns = Array(decoded.prefix(limit))
        let nextCursor = hasMore ? turns.last.map {
            VoiceTaskConversationTurnCursor(createdAt: $0.createdAt, turnID: $0.id)
        } : nil
        return VoiceTaskConversationTurnPage(turns: turns, nextCursor: nextCursor)
    }

    public func saveReference(_ reference: ConversationReference) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTurn(reference.sourceTurnID, in: reference.sessionID)

        let target = targetColumns(reference.target)
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_references (
                id,
                session_id,
                source_turn_id,
                target_kind,
                target_integer_id,
                target_text_id,
                ordinal,
                ordering_fingerprint,
                expires_at,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                .text(reference.id.uuidString),
                .text(reference.sessionID.uuidString),
                .text(reference.sourceTurnID.uuidString),
                .text(target.kind),
                SQLiteValue(target.integerID),
                SQLiteValue(target.textID),
                .integer(Int64(reference.ordinal)),
                .text(reference.orderingFingerprint),
                .real(try Self.timeValue(reference.expiresAt)),
                .real(try Self.timeValue(reference.createdAt)),
            ]
        )
    }

    public func saveFact(_ fact: TaskContextFact) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTurn(fact.sourceTurnID, in: fact.sessionID)
        if let supersededID = fact.supersedesFactID {
            guard try factExists(supersededID) else {
                throw VoiceTaskConversationStoreError.missingFact(supersededID)
            }
        }

        let scope = scopeColumns(fact.scope)
        try connection.execute(
            """
            INSERT INTO task_context_facts (
                id,
                session_id,
                kind,
                scope_kind,
                project_id,
                task_id,
                state,
                value,
                source_turn_id,
                confidence,
                author,
                supersedes_fact_id,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                .text(fact.id.uuidString),
                .text(fact.sessionID.uuidString),
                .text(fact.kind.rawValue),
                .text(scope.kind),
                SQLiteValue(scope.projectID),
                SQLiteValue(scope.taskID),
                .text(fact.state.rawValue),
                .text(fact.value),
                .text(fact.sourceTurnID.uuidString),
                .real(fact.confidence),
                .text(fact.author.rawValue),
                SQLiteValue(fact.supersedesFactID?.uuidString),
                .real(try Self.timeValue(fact.createdAt)),
            ]
        )
    }

    public func saveActionLink(_ link: ConversationActionLink) throws {
        lock.lock()
        defer { lock.unlock() }
        try requireTurn(link.sourceTurnID, in: link.sessionID)

        try connection.execute(
            """
            INSERT INTO conversation_action_links (
                id,
                session_id,
                source_turn_id,
                action_plan_id,
                assistant_queue_item_id,
                task_id,
                execution_receipt_id,
                reviewed_fingerprint,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                .text(link.id.uuidString),
                .text(link.sessionID.uuidString),
                .text(link.sourceTurnID.uuidString),
                SQLiteValue(link.actionPlanID),
                SQLiteValue(link.assistantQueueItemID),
                SQLiteValue(link.taskID),
                SQLiteValue(link.executionReceiptID),
                .text(link.reviewedFingerprint),
                .real(try Self.timeValue(link.createdAt)),
            ]
        )
    }

    public func deleteSession(
        id: UUID,
        scope: VoiceTaskConversationDeleteScope
    ) throws -> VoiceTaskConversationDeleteResult {
        lock.lock()
        defer { lock.unlock() }
        guard try sessionExists(id) else {
            throw VoiceTaskConversationStoreError.missingSession(id)
        }

        switch scope {
        case .rawTranscripts:
            let count = try connection.transaction {
                let count = try scalarCount(
                    """
                    SELECT COUNT(*)
                    FROM voice_task_conversation_turns
                    WHERE session_id = ? AND raw_transcript IS NOT NULL;
                    """,
                    parameters: [.text(id.uuidString)]
                )
                try connection.execute(
                    """
                    UPDATE voice_task_conversation_turns
                    SET raw_transcript = NULL
                    WHERE session_id = ?;
                    """,
                    parameters: [.text(id.uuidString)]
                )
                return count
            }
            return VoiceTaskConversationDeleteResult(rawTranscriptsDeleted: count)

        case .conversation:
            let deletedCounts = try connection.transaction {
                let turns = try scalarCount(
                    "SELECT COUNT(*) FROM voice_task_conversation_turns WHERE session_id = ?;",
                    parameters: [.text(id.uuidString)]
                )
                let references = try scalarCount(
                    "SELECT COUNT(*) FROM voice_task_conversation_references WHERE session_id = ?;",
                    parameters: [.text(id.uuidString)]
                )
                let actionLinks = try scalarCount(
                    "SELECT COUNT(*) FROM conversation_action_links WHERE session_id = ?;",
                    parameters: [.text(id.uuidString)]
                )
                try connection.execute(
                    "DELETE FROM voice_task_conversation_sessions WHERE id = ?;",
                    parameters: [.text(id.uuidString)]
                )
                return (turns, references, actionLinks)
            }
            return VoiceTaskConversationDeleteResult(
                sessionsDeleted: 1,
                turnsDeleted: deletedCounts.0,
                referencesDeleted: deletedCounts.1,
                actionLinksDeleted: deletedCounts.2
            )
        }
    }

    private func loadSessionUnlocked(id: UUID) throws -> VoiceTaskConversationSession? {
        let row = try connection.materializedRows(
            """
            SELECT
                id,
                state,
                title,
                entry_point,
                active_project_id,
                active_task_id,
                resume_summary,
                created_at,
                updated_at,
                last_turn_at
            FROM voice_task_conversation_sessions
            WHERE id = ?
            LIMIT 1;
            """,
            parameters: [.text(id.uuidString)]
        ).first
        guard let row else {
            return nil
        }
        return try decodeSession(row)
    }

    private func decodeSession(_ row: SQLiteMaterializedRow) throws -> VoiceTaskConversationSession {
        let identifier = (try? row.string("id")) ?? "unknown"
        do {
            guard let id = UUID(uuidString: try row.string("id")),
                  let state = VoiceTaskConversationSessionState(rawValue: try row.string("state")),
                  let entryPoint = VoiceTaskConversationEntryPoint(rawValue: try row.string("entry_point"))
            else {
                throw InvalidConversationRow()
            }
            return try VoiceTaskConversationSession(
                restoringID: id,
                state: state,
                title: row.string("title"),
                entryPoint: entryPoint,
                activeProjectID: row.optionalInt64("active_project_id"),
                activeTaskID: row.optionalInt64("active_task_id"),
                resumeSummary: row.optionalString("resume_summary"),
                createdAt: try Self.date(from: row.double("created_at")),
                updatedAt: try Self.date(from: row.double("updated_at")),
                lastTurnAt: try Self.optionalDate(from: row.optionalDouble("last_turn_at"))
            )
        } catch {
            throw VoiceTaskConversationStoreError.corruptRow(
                entity: "session",
                identifier: identifier
            )
        }
    }

    private func decodeTurn(_ row: SQLiteMaterializedRow) throws -> VoiceTaskConversationTurn {
        let identifier = (try? row.string("id")) ?? "unknown"
        do {
            guard let id = UUID(uuidString: try row.string("id")),
                  let sessionID = UUID(uuidString: try row.string("session_id")),
                  let author = VoiceTaskConversationTurnAuthor(rawValue: try row.string("author"))
            else {
                throw InvalidConversationRow()
            }
            return try VoiceTaskConversationTurn(
                id: id,
                sessionID: sessionID,
                author: author,
                rawTranscript: row.optionalString("raw_transcript"),
                userConfirmedText: row.optionalString("confirmed_text"),
                createdAt: try Self.date(from: row.double("created_at"))
            )
        } catch {
            throw VoiceTaskConversationStoreError.corruptRow(
                entity: "turn",
                identifier: identifier
            )
        }
    }

    private func sessionParameters(
        _ session: VoiceTaskConversationSession
    ) throws -> [SQLiteValue] {
        [
            .text(session.id.uuidString),
            .text(session.state.rawValue),
            .text(session.title),
            .text(session.entryPoint.rawValue),
            SQLiteValue(session.activeProjectID),
            SQLiteValue(session.activeTaskID),
            SQLiteValue(session.resumeSummary),
            .real(try Self.timeValue(session.createdAt)),
            .real(try Self.timeValue(session.updatedAt)),
            try Self.optionalTimeValue(session.lastTurnAt),
        ]
    }

    private func requireValidLimit(_ limit: Int) throws {
        guard (1 ... Self.maximumPageSize).contains(limit) else {
            throw VoiceTaskConversationStoreError.invalidLimit
        }
    }

    private func sessionExists(_ id: UUID) throws -> Bool {
        !(try connection.queryStrings(
            "SELECT id FROM voice_task_conversation_sessions WHERE id = ? LIMIT 1;",
            parameters: [.text(id.uuidString)]
        )).isEmpty
    }

    private func factExists(_ id: UUID) throws -> Bool {
        !(try connection.queryStrings(
            "SELECT id FROM task_context_facts WHERE id = ? LIMIT 1;",
            parameters: [.text(id.uuidString)]
        )).isEmpty
    }

    private func requireTurn(_ turnID: UUID, in sessionID: UUID) throws {
        let storedSessionID = try connection.queryStrings(
            "SELECT session_id FROM voice_task_conversation_turns WHERE id = ? LIMIT 1;",
            parameters: [.text(turnID.uuidString)]
        ).first
        guard let storedSessionID else {
            throw VoiceTaskConversationStoreError.missingTurn(turnID)
        }
        guard storedSessionID == sessionID.uuidString else {
            throw VoiceTaskConversationStoreError.missingTurn(turnID)
        }
    }

    private func scalarCount(
        _ sql: String,
        parameters: [SQLiteValue]
    ) throws -> Int {
        Int(try connection.queryStrings(sql, parameters: parameters).first ?? "0") ?? 0
    }

    private func targetColumns(
        _ target: ConversationStableTargetID
    ) -> (kind: String, integerID: Int64?, textID: String?) {
        switch target {
        case .project(let id):
            ("project", id, nil)
        case .task(let id):
            ("task", id, nil)
        case .actionPlan(let id):
            ("action_plan", nil, id)
        case .assistantQueueItem(let id):
            ("assistant_queue_item", nil, id)
        case .executionReceipt(let id):
            ("execution_receipt", nil, id)
        }
    }

    private func scopeColumns(
        _ scope: TaskContextFactScope
    ) -> (kind: String, projectID: Int64?, taskID: Int64?) {
        switch scope {
        case .session:
            ("session", nil, nil)
        case .project(let id):
            ("project", id, nil)
        case .task(let id):
            ("task", nil, id)
        }
    }

    private static func timeValue(_ date: Date) throws -> Double {
        let value = date.timeIntervalSinceReferenceDate
        guard value.isFinite else {
            throw VoiceTaskConversationStoreError.invalidDate
        }
        return value
    }

    private static func optionalTimeValue(_ date: Date?) throws -> SQLiteValue {
        guard let date else {
            return .null
        }
        return .real(try timeValue(date))
    }

    private static func date(from value: Double) throws -> Date {
        guard value.isFinite else {
            throw VoiceTaskConversationStoreError.invalidDate
        }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    private static func optionalDate(from value: Double?) throws -> Date? {
        guard let value else {
            return nil
        }
        return try date(from: value)
    }

    private func requiredLastTurnDate(_ session: VoiceTaskConversationSession) throws -> Date {
        guard let lastTurnAt = session.lastTurnAt else {
            throw VoiceTaskConversationStoreError.corruptRow(
                entity: "session",
                identifier: session.id.uuidString
            )
        }
        return lastTurnAt
    }
}

private struct InvalidConversationRow: Error {}
