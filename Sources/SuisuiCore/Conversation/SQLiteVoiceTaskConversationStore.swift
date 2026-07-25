import CryptoKit
import Foundation

/// Store-issued proof that an excerpt belongs to a persisted, user-confirmed
/// conversation Turn. Only this SQLite-backed verifier can construct it, so an
/// arbitrary digest cannot become Task Context persistence authorization.
public struct TaskContextFactSourceEvidence: Equatable, Sendable {
    public let sessionID: UUID
    public let turnID: UUID
    public let excerptDigest: String
    let storeIdentifier: UUID

    fileprivate init(
        sessionID: UUID,
        turnID: UUID,
        excerptDigest: String,
        storeIdentifier: UUID
    ) {
        self.sessionID = sessionID
        self.turnID = turnID
        self.excerptDigest = excerptDigest
        self.storeIdentifier = storeIdentifier
    }
}

public final class SQLiteVoiceTaskConversationStore: VoiceTaskConversationStore, @unchecked Sendable {
    public static let maximumPageSize = 500

    private let connection: SQLiteConnection
    private let lock = NSLock()
    private let storeIdentifier = UUID()

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
            guard session.lastTurnAt == storedSession.lastTurnAt else {
                throw VoiceTaskConversationStoreError.turnCursorRequiresSaveTurn(session.id)
            }
            guard try projectExists(session.activeProjectID),
                  try taskExists(session.activeTaskID)
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
                    try Self.optionalTimeValue(storedSession.lastTurnAt),
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

    public func verifyFactSourceEvidence(
        sessionID: UUID,
        turnID: UUID,
        sourceExcerpt: String
    ) throws -> TaskContextFactSourceEvidence {
        lock.lock()
        defer { lock.unlock() }
        let excerpt = sourceExcerpt
        guard !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceTaskConversationStoreError.invalidFactSourceEvidence(turnID)
        }
        guard let row = try connection.materializedRows(
            """
            SELECT session_id, author, confirmed_text
            FROM voice_task_conversation_turns
            WHERE id = ?
            LIMIT 1;
            """,
            parameters: [.text(turnID.uuidString)]
        ).first else {
            throw VoiceTaskConversationStoreError.missingTurn(turnID)
        }
        guard try row.string("session_id") == sessionID.uuidString,
              try row.string("author") == VoiceTaskConversationTurnAuthor.user.rawValue,
              let confirmedText = try row.optionalString("confirmed_text"),
              confirmedText.contains(excerpt)
        else {
            throw VoiceTaskConversationStoreError.invalidFactSourceEvidence(turnID)
        }

        // Hash only the minimal confirmed excerpt. The raw transcript and the
        // confirmed sentence stay in the conversation store and never enter
        // the durable Task Context payload.
        let digest = SHA256.hash(data: Data(excerpt.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return TaskContextFactSourceEvidence(
            sessionID: sessionID,
            turnID: turnID,
            excerptDigest: digest,
            storeIdentifier: storeIdentifier
        )
    }

    public func retractFact(
        factID: UUID,
        at date: Date
    ) throws -> TaskContextFact {
        lock.lock()
        defer { lock.unlock() }
        return try connection.transaction {
            guard let persisted = try loadFactUnlocked(id: factID) else {
                throw VoiceTaskConversationStoreError.missingFact(factID)
            }
            guard let proposalID = persisted.supersedesFactID,
                  try factExists(proposalID)
            else {
                throw VoiceTaskConversationStoreError.missingFact(
                    persisted.supersedesFactID ?? factID
                )
            }
            let successorCount = try scalarCount(
                """
                SELECT COUNT(*)
                FROM task_context_facts
                WHERE supersedes_fact_id = ?;
                """,
                parameters: [.text(factID.uuidString)]
            )
            guard successorCount == 0 else {
                throw VoiceTaskConversationDomainError.incompatibleFactTransition
            }
            let policy = TaskContextFactPolicy()
            let authorized = try policy.reauthorizePersistedConfirmedFact(
                persisted,
                sourceStoreIdentifier: storeIdentifier
            )
            let retracted = try policy.retract(authorized, at: date)
            let write = try policy.persistenceWrite(for: retracted)
            try insertFact(write.fact)
            return retracted
        }
    }

    public func saveFact(_ write: TaskContextFactWrite) throws {
        lock.lock()
        defer { lock.unlock() }
        guard write.storeIdentifier == storeIdentifier else {
            throw VoiceTaskConversationStoreError.invalidFactSourceEvidence(
                write.fact.sourceTurnID
            )
        }
        try insertFact(write.fact)
    }

    public func saveSupersession(
        _ write: TaskContextFactSupersessionWrite
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard write.storeIdentifier == storeIdentifier else {
            throw VoiceTaskConversationStoreError.invalidFactSourceEvidence(
                write.corrected.sourceTurnID
            )
        }
        try connection.transaction {
            try insertFact(write.superseded)
            try insertFact(write.corrected)
        }
    }

    private func insertFact(_ fact: TaskContextFact) throws {
        if let supersededID = fact.supersedesFactID {
            guard try factExists(supersededID) else {
                throw VoiceTaskConversationStoreError.missingFact(supersededID)
            }
        }
        try requirePersistableFactEvidence(fact)

        let scope = scopeColumns(fact.scope)
        try connection.execute(
            """
            INSERT INTO task_context_facts (
                id,
                session_id,
                kind,
                scope_kind,
                scope_target_id,
                project_id,
                task_id,
                state,
                value,
                source_turn_id,
                source_excerpt_digest,
                confidence,
                author,
                supersedes_fact_id,
                expires_at,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                .text(fact.id.uuidString),
                .text(fact.sessionID.uuidString),
                .text(fact.kind.rawValue),
                .text(scope.kind),
                SQLiteValue(scope.stableTargetID),
                SQLiteValue(scope.projectID),
                SQLiteValue(scope.taskID),
                .text(fact.state.rawValue),
                .text(fact.value),
                .text(fact.sourceTurnID.uuidString),
                .text(fact.sourceExcerptDigest),
                .real(fact.confidence),
                .text(fact.author.rawValue),
                SQLiteValue(fact.supersedesFactID?.uuidString),
                try Self.optionalTimeValue(fact.expiresAt),
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
                operation_kind,
                reviewed_fingerprint,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            parameters: [
                .text(link.id.uuidString),
                .text(link.sessionID.uuidString),
                .text(link.sourceTurnID.uuidString),
                SQLiteValue(link.actionPlanID),
                SQLiteValue(link.assistantQueueItemID),
                SQLiteValue(link.taskID),
                SQLiteValue(link.executionReceiptID),
                .text(link.operation.rawValue),
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

    private func loadFactUnlocked(id: UUID) throws -> TaskContextFact? {
        guard let row = try connection.materializedRows(
            """
            SELECT
                id,
                session_id,
                kind,
                scope_kind,
                scope_target_id,
                state,
                value,
                source_turn_id,
                source_excerpt_digest,
                confidence,
                author,
                supersedes_fact_id,
                expires_at,
                created_at
            FROM task_context_facts
            WHERE id = ?
            LIMIT 1;
            """,
            parameters: [.text(id.uuidString)]
        ).first else {
            return nil
        }
        do {
            guard let storedID = UUID(uuidString: try row.string("id")),
                  let sessionID = UUID(uuidString: try row.string("session_id")),
                  let kind = TaskContextFactKind(rawValue: try row.string("kind")),
                  let state = TaskContextFactState(rawValue: try row.string("state")),
                  let sourceTurnID = UUID(
                    uuidString: try row.string("source_turn_id")
                  ),
                  let sourceDigest = try row.optionalString(
                    "source_excerpt_digest"
                  ),
                  let author = Self.factAuthor(
                    rawValue: try row.string("author")
                  )
            else {
                throw InvalidConversationRow()
            }
            let scopeTargetID = try row.optionalInt64("scope_target_id")
            let scope: TaskContextFactScope
            switch (try row.string("scope_kind"), scopeTargetID) {
            case ("project", let target?):
                scope = .project(target)
            case ("task", let target?):
                scope = .task(target)
            default:
                throw InvalidConversationRow()
            }
            let supersedesFactID = try row.optionalString(
                "supersedes_fact_id"
            ).flatMap(UUID.init(uuidString:))
            return try TaskContextFact(
                id: storedID,
                sessionID: sessionID,
                kind: kind,
                scope: scope,
                state: state,
                value: try row.string("value"),
                sourceTurnID: sourceTurnID,
                sourceExcerptDigest: sourceDigest,
                confidence: try row.double("confidence"),
                author: author,
                supersedesFactID: supersedesFactID,
                expiresAt: try Self.optionalDate(
                    from: row.optionalDouble("expires_at")
                ),
                createdAt: try Self.date(from: row.double("created_at"))
            )
        } catch {
            throw VoiceTaskConversationStoreError.corruptRow(
                entity: "task_context_fact",
                identifier: id.uuidString
            )
        }
    }

    private static func factAuthor(
        rawValue: String
    ) -> TaskContextFactAuthor? {
        switch rawValue {
        case TaskContextFactAuthor.userExplicit.rawValue:
            .userExplicit
        case TaskContextFactAuthor.providerInferred.rawValue:
            .providerInferred
        case TaskContextFactAuthor.deterministic.rawValue:
            .deterministic
        default:
            nil
        }
    }

    private func projectExists(_ id: Int64?) throws -> Bool {
        guard let id else {
            return true
        }
        return !(try connection.queryStrings(
            "SELECT id FROM projects WHERE id = ? LIMIT 1;",
            parameters: [.integer(id)]
        )).isEmpty
    }

    private func taskExists(_ id: Int64?) throws -> Bool {
        guard let id else {
            return true
        }
        return !(try connection.queryStrings(
            "SELECT id FROM tasks WHERE id = ? LIMIT 1;",
            parameters: [.integer(id)]
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

    private func requirePersistableFactEvidence(_ fact: TaskContextFact) throws {
        let storedSessionID = try connection.queryStrings(
            "SELECT session_id FROM voice_task_conversation_turns WHERE id = ? LIMIT 1;",
            parameters: [.text(fact.sourceTurnID.uuidString)]
        ).first
        if storedSessionID == fact.sessionID.uuidString {
            return
        }

        // Conversation retention may remove the source Turn while preserving
        // long-term Task Context. A later append-only transition is permitted
        // only when it carries the exact evidence tombstone of its persisted
        // predecessor; new evidence still requires a live confirmed Turn.
        guard let predecessorID = fact.supersedesFactID,
              let predecessor = try connection.materializedRows(
                """
                SELECT session_id, source_turn_id, source_excerpt_digest
                FROM task_context_facts
                WHERE id = ?
                LIMIT 1;
                """,
                parameters: [.text(predecessorID.uuidString)]
              ).first,
              try predecessor.string("session_id") == fact.sessionID.uuidString,
              try predecessor.string("source_turn_id") == fact.sourceTurnID.uuidString,
              try predecessor.string("source_excerpt_digest") == fact.sourceExcerptDigest
        else {
            throw VoiceTaskConversationStoreError.missingTurn(fact.sourceTurnID)
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
    ) -> (kind: String, stableTargetID: Int64?, projectID: Int64?, taskID: Int64?) {
        switch scope {
        case .session:
            ("session", nil, nil, nil)
        case .project(let id):
            ("project", id, id, nil)
        case .task(let id):
            ("task", id, nil, id)
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
