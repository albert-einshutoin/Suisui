import Foundation
import XCTest
@testable import SuisuiCore

final class VoiceTaskConversationStoreTests: XCTestCase {
    func testFreshDatabaseMigrationCreatesConversationTablesAndIndexes() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let tables = Set(
            try connection.queryStrings(
                """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                  AND name IN (
                    'voice_task_conversation_sessions',
                    'voice_task_conversation_turns',
                    'voice_task_conversation_references',
                    'task_context_facts',
                    'conversation_action_links'
                  );
                """
            )
        )
        XCTAssertEqual(
            tables,
            [
                "voice_task_conversation_sessions",
                "voice_task_conversation_turns",
                "voice_task_conversation_references",
                "task_context_facts",
                "conversation_action_links",
            ]
        )

        let indexes = Set(
            try connection.queryStrings(
                """
                SELECT name
                FROM sqlite_master
                WHERE type = 'index'
                  AND name LIKE 'idx_voice_task_conversation_%'
                ORDER BY name;
                """
            )
        )
        XCTAssertTrue(indexes.contains("idx_voice_task_conversation_turns_page"))
        XCTAssertTrue(indexes.contains("idx_voice_task_conversation_references_expiry"))
        XCTAssertTrue(indexes.contains("idx_voice_task_conversation_action_links_turn"))
    }

    func testStorePersistsSessionAndTurnsAcrossDatabaseReopen() throws {
        let fixture = try TemporaryConversationDatabase()
        defer { fixture.remove() }
        let session = makeSession()
        let firstTurn = try makeTurn(
            sessionID: session.id,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_001)
        )

        do {
            let store = try SQLiteVoiceTaskConversationStore(path: fixture.databaseURL.path)
            try store.createSession(session)
            try store.saveTurn(firstTurn)
        }

        let reopenedStore = try SQLiteVoiceTaskConversationStore(path: fixture.databaseURL.path)
        XCTAssertEqual(try reopenedStore.loadSession(id: session.id), sessionWithRecordedTurn(session, at: firstTurn.createdAt))
        XCTAssertEqual(try reopenedStore.listTurns(sessionID: session.id, before: nil, limit: 10), [firstTurn])
    }

    func testCreatingSessionWithExistingTurnCursorFailsClosed() throws {
        let (connection, store) = try makeStore()
        var session = makeSession()
        try session.recordTurn(at: Date(timeIntervalSince1970: 1_800_000_001))

        XCTAssertThrowsError(try store.createSession(session)) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .nonEmptyNewSession(session.id)
            )
        }
        XCTAssertEqual(
            try connection.queryStrings("SELECT id FROM voice_task_conversation_sessions;"),
            []
        )
    }

    func testTurnAtCurrentSessionTimestampStillAdvancesPersistedVersion() throws {
        let (_, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turn = try makeTurn(sessionID: session.id, createdAt: session.updatedAt)

        try store.saveTurn(turn)

        let restored = try XCTUnwrap(store.loadSession(id: session.id))
        XCTAssertEqual(restored.lastTurnAt, turn.createdAt)
        XCTAssertGreaterThan(restored.updatedAt, session.updatedAt)
    }

    func testUpdatingSessionPersistsLifecycleState() throws {
        let (connection, store) = try makeStore()
        var session = makeSession()
        try store.createSession(session)
        let expectedUpdatedAt = session.updatedAt
        try session.pause(at: Date(timeIntervalSince1970: 1_800_000_010))

        try store.updateSession(session, expectedUpdatedAt: expectedUpdatedAt)

        XCTAssertEqual(try store.loadSession(id: session.id), session)
        XCTAssertEqual(
            try connection.queryStrings("SELECT state FROM voice_task_conversation_sessions;"),
            ["paused"]
        )
    }

    func testUpdatingRetainedSessionAfterTurnFailsOptimisticLock() throws {
        let (_, store) = try makeStore()
        var retainedSession = makeSession()
        try store.createSession(retainedSession)
        let expectedUpdatedAt = retainedSession.updatedAt
        let turn = try makeTurn(
            sessionID: retainedSession.id,
            createdAt: Date(timeIntervalSince1970: 1_800_000_010)
        )
        try store.saveTurn(turn)
        try retainedSession.updateTitle(
            "Renamed after turn",
            at: Date(timeIntervalSince1970: 1_800_000_020)
        )

        XCTAssertThrowsError(
            try store.updateSession(retainedSession, expectedUpdatedAt: expectedUpdatedAt)
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .staleSession(retainedSession.id)
            )
        }
        XCTAssertEqual(try store.loadSession(id: retainedSession.id)?.lastTurnAt, turn.createdAt)
    }

    func testLaterMutationFromStaleSnapshotCannotUndoPausedState() throws {
        let (_, store) = try makeStore()
        let baseSession = makeSession()
        try store.createSession(baseSession)
        var pausedSession = baseSession
        try pausedSession.pause(at: Date(timeIntervalSince1970: 1_800_000_010))
        try store.updateSession(
            pausedSession,
            expectedUpdatedAt: baseSession.updatedAt
        )
        var staleSession = baseSession
        try staleSession.updateTitle(
            "Stale rename",
            at: Date(timeIntervalSince1970: 1_800_000_020)
        )

        XCTAssertThrowsError(
            try store.updateSession(staleSession, expectedUpdatedAt: baseSession.updatedAt)
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .staleSession(baseSession.id)
            )
        }
        let restored = try XCTUnwrap(store.loadSession(id: baseSession.id))
        XCTAssertEqual(restored.state, .paused)
        XCTAssertEqual(restored.title, baseSession.title)
    }

    func testSessionUpdateRequiresVersionTimestampToAdvance() throws {
        let (_, store) = try makeStore()
        var session = makeSession()
        try store.createSession(session)
        let originalTitle = session.title
        try session.updateTitle("Same-version rename", at: session.updatedAt)

        XCTAssertThrowsError(
            try store.updateSession(session, expectedUpdatedAt: session.updatedAt)
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .staleSession(session.id)
            )
        }
        XCTAssertEqual(try store.loadSession(id: session.id)?.title, originalTitle)
    }

    func testSessionUpdateCannotPersistTurnCursorWithoutTurnRow() throws {
        let (_, store) = try makeStore()
        var session = makeSession()
        try store.createSession(session)
        let expectedUpdatedAt = session.updatedAt
        try session.recordTurn(at: Date(timeIntervalSince1970: 1_800_000_001))

        XCTAssertThrowsError(
            try store.updateSession(session, expectedUpdatedAt: expectedUpdatedAt)
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .turnCursorRequiresSaveTurn(session.id)
            )
        }
        XCTAssertNil(try store.loadSession(id: session.id)?.lastTurnAt)
        XCTAssertEqual(
            try store.listTurns(sessionID: session.id, before: nil, limit: 10),
            []
        )
    }

    func testSavingTurnForMissingSessionFailsClosed() throws {
        let (_, store) = try makeStore()
        let missingSessionID = UUID()
        let turn = try makeTurn(sessionID: missingSessionID)

        XCTAssertThrowsError(try store.saveTurn(turn)) { error in
            XCTAssertEqual(error as? VoiceTaskConversationStoreError, .missingSession(missingSessionID))
        }
    }

    func testCorruptedSessionStateReturnsRepairError() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        try connection.execute("PRAGMA ignore_check_constraints = ON;")
        try connection.execute(
            "UPDATE voice_task_conversation_sessions SET state = 'future_state' WHERE id = ?;",
            parameters: [.text(session.id.uuidString)]
        )

        XCTAssertThrowsError(try store.loadSession(id: session.id)) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .corruptRow(entity: "session", identifier: session.id.uuidString)
            )
        }
    }

    func testSaveTurnRollsBackInsertWhenSessionTimestampUpdateFails() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        try connection.execute(
            """
            CREATE TRIGGER reject_conversation_session_update
            BEFORE UPDATE ON voice_task_conversation_sessions
            BEGIN
                SELECT RAISE(ABORT, 'injected session update failure');
            END;
            """
        )

        XCTAssertThrowsError(try store.saveTurn(try makeTurn(sessionID: session.id)))
        XCTAssertEqual(
            try connection.queryStrings("SELECT id FROM voice_task_conversation_turns;"),
            []
        )
    }

    func testCompositeCursorPagesTurnsWithIdenticalTimestampsWithoutLoss() throws {
        let (_, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_020)
        let turns = try [
            makeTurn(
                sessionID: session.id,
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                createdAt: timestamp
            ),
            makeTurn(
                sessionID: session.id,
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                createdAt: timestamp
            ),
            makeTurn(
                sessionID: session.id,
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                createdAt: timestamp
            ),
        ]
        try turns.forEach(store.saveTurn)

        let firstPage = try store.listTurnPage(sessionID: session.id, before: nil, limit: 2)
        let secondPage = try store.listTurnPage(
            sessionID: session.id,
            before: try XCTUnwrap(firstPage.nextCursor),
            limit: 2
        )

        XCTAssertEqual(firstPage.turns.map(\.id), [turns[2].id, turns[1].id])
        XCTAssertEqual(secondPage.turns.map(\.id), [turns[0].id])
        XCTAssertNil(secondPage.nextCursor)
    }

    func testSubmillisecondTimestampsRoundTripAndKeepChronologicalOrder() throws {
        let (_, store) = try makeStore()
        let session = VoiceTaskConversationSession(
            id: UUID(),
            title: "Precise timeline",
            entryPoint: .voiceCommand,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000.123_456_7)
        )
        try store.createSession(session)
        let earlier = try makeTurn(
            sessionID: session.id,
            id: UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_001.123_1)
        )
        let later = try makeTurn(
            sessionID: session.id,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_800_000_001.123_9)
        )
        try store.saveTurn(earlier)
        try store.saveTurn(later)

        XCTAssertEqual(try store.loadSession(id: session.id)?.createdAt, session.createdAt)
        XCTAssertEqual(
            try store.listTurns(sessionID: session.id, before: nil, limit: 10).map(\.id),
            [later.id, earlier.id]
        )
    }

    func testDateCursorListsStableDescendingTurnsBeforeBoundary() throws {
        let (_, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turns = try (1 ... 3).map { offset in
            try makeTurn(
                sessionID: session.id,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset))
            )
        }
        try turns.forEach(store.saveTurn)

        let page = try store.listTurns(
            sessionID: session.id,
            before: Date(timeIntervalSince1970: 1_800_000_003),
            limit: 10
        )

        XCTAssertEqual(page.map(\.createdAt), [turns[1].createdAt, turns[0].createdAt])
    }

    func testNonPositivePageLimitFailsClosed() throws {
        let (_, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)

        XCTAssertThrowsError(try store.listTurns(sessionID: session.id, before: nil, limit: 0)) { error in
            XCTAssertEqual(error as? VoiceTaskConversationStoreError, .invalidLimit)
        }
    }

    func testNonFiniteSessionDateFailsBeforeSQLiteWrite() throws {
        let (connection, store) = try makeStore()
        let session = VoiceTaskConversationSession(
            title: "Invalid clock",
            entryPoint: .voiceCommand,
            createdAt: Date(timeIntervalSinceReferenceDate: .infinity)
        )

        XCTAssertThrowsError(try store.createSession(session)) { error in
            XCTAssertEqual(error as? VoiceTaskConversationStoreError, .invalidDate)
        }
        XCTAssertEqual(
            try connection.queryStrings("SELECT id FROM voice_task_conversation_sessions;"),
            []
        )
    }

    func testStorePersistsReferenceFactAndActionLinkInNormalizedTables() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turn = try makeTurn(sessionID: session.id)
        try store.saveTurn(turn)
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, created_at, updated_at)
            VALUES (41, 'Release', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            INSERT INTO tasks (id, project_id, title, status, created_at, updated_at)
            VALUES (42, 41, 'Sign build', 'planned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            """
        )
        let reference = try ConversationReference(
            sessionID: session.id,
            target: .task(42),
            sourceTurnID: turn.id,
            ordinal: 2,
            orderingFingerprint: "ordered-candidates-v1",
            expiresAt: turn.createdAt.addingTimeInterval(3_600),
            createdAt: turn.createdAt
        )
        let factHistory = try policyConfirmationHistory(
            TaskContextFact(
            sessionID: session.id,
            kind: .constraint,
            scope: .task(42),
            state: .proposed,
            value: "Ship after signing",
            sourceTurnID: turn.id,
            sourceExcerptDigest: String(repeating: "a", count: 64),
            confidence: 1,
            author: .userExplicit,
            expiresAt: turn.createdAt.addingTimeInterval(3_600),
            createdAt: turn.createdAt
            )
        )
        let fact = factHistory.confirmed
        let actionLink = try ConversationActionLink(
            sessionID: session.id,
            sourceTurnID: turn.id,
            actionPlanID: "plan-1",
            assistantQueueItemID: "queue-1",
            taskID: 42,
            executionReceiptID: "receipt-1",
            operation: .taskCreated,
            reviewedFingerprint: "reviewed-v1",
            createdAt: turn.createdAt
        )

        try store.saveReference(reference)
        try store.saveFact(
            try TaskContextFactPolicy().persistenceWrite(for: factHistory.proposed)
        )
        try store.saveFact(
            try TaskContextFactPolicy().persistenceWrite(for: fact)
        )
        try store.saveActionLink(actionLink)

        XCTAssertEqual(try connection.queryStrings("SELECT target_kind FROM voice_task_conversation_references;"), ["task"])
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT scope_kind FROM task_context_facts WHERE state = 'confirmed';"
            ),
            ["task"]
        )
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT source_excerpt_digest FROM task_context_facts WHERE state = 'confirmed';"
            ),
            [String(repeating: "a", count: 64)]
        )
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT expires_at FROM task_context_facts WHERE state = 'confirmed';"
            ),
            [String(turn.createdAt.addingTimeInterval(3_600).timeIntervalSinceReferenceDate)]
        )
        XCTAssertEqual(try connection.queryStrings("SELECT action_plan_id FROM conversation_action_links;"), ["plan-1"])
        XCTAssertEqual(
            try connection.queryStrings("SELECT operation_kind FROM conversation_action_links;"),
            ["task_created"]
        )
    }

    func testDeletingTaskPreservesFactScopeAndTaskOnlyActionLinkIdentifiers() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turn = try makeTurn(sessionID: session.id)
        try store.saveTurn(turn)
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, created_at, updated_at)
            VALUES (61, 'Stable scope', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            INSERT INTO tasks (id, project_id, title, status, created_at, updated_at)
            VALUES (62, 61, 'Delete target', 'planned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            """
        )
        let factHistory = try policyConfirmationHistory(
            TaskContextFact(
            sessionID: session.id,
            kind: .constraint,
            scope: .task(62),
            state: .proposed,
            value: "Keep provenance",
            sourceTurnID: turn.id,
            sourceExcerptDigest: String(repeating: "b", count: 64),
            confidence: 1,
            author: .userExplicit,
            createdAt: turn.createdAt
            )
        )
        let fact = factHistory.confirmed
        let link = try ConversationActionLink(
            sessionID: session.id,
            sourceTurnID: turn.id,
            taskID: 62,
            reviewedFingerprint: "stable-task-link",
            createdAt: turn.createdAt
        )
        try store.saveFact(
            try TaskContextFactPolicy().persistenceWrite(for: factHistory.proposed)
        )
        try store.saveFact(
            try TaskContextFactPolicy().persistenceWrite(for: fact)
        )
        try store.saveActionLink(link)

        try connection.execute("DELETE FROM tasks WHERE id = 62;")

        let factRow = try XCTUnwrap(
            try connection.materializedRows(
                """
                SELECT scope_kind, scope_target_id, task_id
                FROM task_context_facts
                WHERE id = ?;
                """,
                parameters: [.text(fact.id.uuidString)]
            ).first
        )
        XCTAssertEqual(try factRow.string("scope_kind"), "task")
        XCTAssertEqual(try factRow.int64("scope_target_id"), 62)
        XCTAssertNil(try factRow.optionalInt64("task_id"))
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT task_id FROM conversation_action_links WHERE id = ?;",
                parameters: [.text(link.id.uuidString)]
            ),
            ["62"]
        )
    }

    func testDeletedActiveTaskCannotBeRestoredByRetainedSessionSnapshot() throws {
        let (connection, store) = try makeStore()
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, created_at, updated_at)
            VALUES (71, 'Active context', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            INSERT INTO tasks (id, project_id, title, status, created_at, updated_at)
            VALUES (72, 71, 'Removed context', 'planned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            """
        )
        var retainedSession = VoiceTaskConversationSession(
            title: "Scoped session",
            entryPoint: .taskInspector,
            activeProjectID: 71,
            activeTaskID: 72,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.createSession(retainedSession)
        let expectedUpdatedAt = retainedSession.updatedAt
        try connection.execute("DELETE FROM tasks WHERE id = 72;")
        try retainedSession.updateTitle(
            "Must not restore deleted task",
            at: Date(timeIntervalSince1970: 1_800_000_001)
        )

        XCTAssertThrowsError(
            try store.updateSession(retainedSession, expectedUpdatedAt: expectedUpdatedAt)
        ) { error in
            XCTAssertEqual(
                error as? VoiceTaskConversationStoreError,
                .staleSession(retainedSession.id)
            )
        }
        XCTAssertNil(try store.loadSession(id: retainedSession.id)?.activeTaskID)
    }

    func testRawTranscriptDeletionDoesNotDeleteConfirmedTextOrSession() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turn = try VoiceTaskConversationTurn(
            sessionID: session.id,
            author: .user,
            rawTranscript: "raw recognition",
            userConfirmedText: "confirmed task",
            createdAt: Date(timeIntervalSince1970: 1_800_000_030)
        )
        try store.saveTurn(turn)

        let result = try store.deleteSession(id: session.id, scope: .rawTranscripts)

        XCTAssertEqual(result.rawTranscriptsDeleted, 1)
        XCTAssertEqual(result.sessionsDeleted, 0)
        XCTAssertEqual(
            try connection.queryStrings("SELECT confirmed_text FROM voice_task_conversation_turns;"),
            ["confirmed task"]
        )
        XCTAssertEqual(try store.loadSession(id: session.id)?.id, session.id)
    }

    func testSessionDeletionCascadesConversationRowsButPreservesFactAndTask() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turn = try makeTurn(sessionID: session.id)
        try store.saveTurn(turn)
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, created_at, updated_at)
            VALUES (51, 'Release', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            INSERT INTO tasks (id, project_id, title, status, created_at, updated_at)
            VALUES (52, 51, 'Notarize', 'planned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            """
        )
        try store.saveReference(
            ConversationReference(
                sessionID: session.id,
                target: .task(52),
                sourceTurnID: turn.id,
                ordinal: 0,
                orderingFingerprint: "ordering",
                expiresAt: turn.createdAt.addingTimeInterval(60),
                createdAt: turn.createdAt
            )
        )
        let factHistory = try policyConfirmationHistory(
            TaskContextFact(
            sessionID: session.id,
            kind: .goal,
            scope: .task(52),
            state: .proposed,
            value: "Release safely",
            sourceTurnID: turn.id,
            sourceExcerptDigest: String(repeating: "c", count: 64),
            confidence: 1,
            author: .userExplicit,
            createdAt: turn.createdAt
            )
        )
        let fact = factHistory.confirmed
        try store.saveFact(
            try TaskContextFactPolicy().persistenceWrite(for: factHistory.proposed)
        )
        try store.saveFact(
            try TaskContextFactPolicy().persistenceWrite(for: fact)
        )
        try store.saveActionLink(
            ConversationActionLink(
                sessionID: session.id,
                sourceTurnID: turn.id,
                taskID: 52,
                reviewedFingerprint: "reviewed",
                createdAt: turn.createdAt
            )
        )

        let result = try store.deleteSession(id: session.id, scope: .conversation)

        XCTAssertEqual(result.sessionsDeleted, 1)
        XCTAssertEqual(result.turnsDeleted, 1)
        XCTAssertEqual(result.referencesDeleted, 1)
        XCTAssertEqual(result.actionLinksDeleted, 1)
        XCTAssertEqual(try connection.queryStrings("SELECT id FROM tasks WHERE id = 52;"), ["52"])
        XCTAssertEqual(
            try connection.queryStrings("SELECT id FROM task_context_facts WHERE id = ?;", parameters: [.text(fact.id.uuidString)]),
            [fact.id.uuidString]
        )
        XCTAssertEqual(
            try connection.materializedRows(
                "SELECT source_turn_id FROM task_context_facts WHERE id = ?;",
                parameters: [.text(fact.id.uuidString)]
            ).first?.cells["source_turn_id"],
            .null
        )
    }

    func testSupersessionWriteRollsBackBothFactsWhenCorrectedInsertFails() throws {
        let (connection, store) = try makeStore()
        let session = makeSession()
        try store.createSession(session)
        let turn = try makeTurn(sessionID: session.id)
        try store.saveTurn(turn)
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, created_at, updated_at)
            VALUES (41, 'Release', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            INSERT INTO tasks (id, project_id, title, status, created_at, updated_at)
            VALUES (42, 41, 'Launch', 'planned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            """
        )
        let oldHistory = try policyConfirmationHistory(
            TaskContextFact(
                sessionID: session.id,
                kind: .constraint,
                scope: .task(42),
                state: .proposed,
                value: "Launch Thursday",
                sourceTurnID: turn.id,
                sourceExcerptDigest: String(repeating: "d", count: 64),
                confidence: 1,
                author: .userExplicit,
                createdAt: turn.createdAt
            )
        )
        let policy = TaskContextFactPolicy()
        try store.saveFact(try policy.persistenceWrite(for: oldHistory.proposed))
        try store.saveFact(try policy.persistenceWrite(for: oldHistory.confirmed))

        let replacementCandidate = TaskContextFactCandidate(
            sessionID: session.id,
            kind: .constraint,
            scope: .task(42),
            scopeAssessment: .unique,
            value: "Launch Friday",
            sourceTurnID: turn.id,
            sourceExcerptDigest: String(repeating: "e", count: 64),
            confidence: 1,
            author: .userExplicit,
            conflictingConfirmedFactIDs: [oldHistory.confirmed.id],
            contentCategory: .taskContext,
            createdAt: turn.createdAt.addingTimeInterval(1)
        )
        guard case let .requireConfirmation(replacement, _) = policy.evaluate(
            replacementCandidate
        ) else {
            return XCTFail("Expected conflicting replacement to require confirmation.")
        }
        try store.saveFact(try policy.persistenceWrite(for: replacement))
        let correction = try policy.supersede(
            oldHistory.confirmed,
            with: replacement,
            at: turn.createdAt.addingTimeInterval(2)
        )
        let batch = try policy.persistenceSupersessionWrite(
            superseded: correction.0,
            corrected: correction.1
        )
        try connection.execute(
            """
            CREATE TRIGGER fail_corrected_fact
            BEFORE INSERT ON task_context_facts
            WHEN NEW.id = '\(correction.1.id.uuidString)'
            BEGIN
                SELECT RAISE(ABORT, 'forced corrected insert failure');
            END;
            """
        )

        XCTAssertThrowsError(try store.saveSupersession(batch))
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT id FROM task_context_facts WHERE id IN (?, ?);",
                parameters: [
                    .text(correction.0.id.uuidString),
                    .text(correction.1.id.uuidString),
                ]
            ),
            []
        )

        try connection.execute("DROP TRIGGER fail_corrected_fact;")
        try store.saveSupersession(batch)
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT COUNT(*) FROM task_context_facts WHERE id IN (?, ?);",
                parameters: [
                    .text(correction.0.id.uuidString),
                    .text(correction.1.id.uuidString),
                ]
            ),
            ["2"]
        )
    }

    private func makeStore() throws -> (SQLiteConnection, SQLiteVoiceTaskConversationStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return (connection, SQLiteVoiceTaskConversationStore(connection: connection))
    }

    private func makeSession() -> VoiceTaskConversationSession {
        VoiceTaskConversationSession(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            title: "Release preparation",
            entryPoint: .voiceCommand,
            activeProjectID: nil,
            activeTaskID: nil,
            resumeSummary: "Review signing",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeTurn(
        sessionID: UUID,
        id: UUID = UUID(),
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_001)
    ) throws -> VoiceTaskConversationTurn {
        try VoiceTaskConversationTurn(
            id: id,
            sessionID: sessionID,
            author: .user,
            rawTranscript: "sign it",
            userConfirmedText: "Sign the release",
            createdAt: createdAt
        )
    }

    private func policyConfirmationHistory(
        _ proposed: TaskContextFact
    ) throws -> (proposed: TaskContextFact, confirmed: TaskContextFact) {
        let policy = TaskContextFactPolicy()
        let candidate = TaskContextFactCandidate(
            sessionID: proposed.sessionID,
            kind: proposed.kind,
            scope: proposed.scope,
            scopeAssessment: .unique,
            value: proposed.value,
            sourceTurnID: proposed.sourceTurnID,
            sourceExcerptDigest: proposed.sourceExcerptDigest,
            confidence: proposed.confidence,
            author: proposed.author,
            conflictingConfirmedFactIDs: [],
            contentCategory: .taskContext,
            createdAt: proposed.createdAt,
            expiresAt: proposed.expiresAt
        )
        let authorized = try policy.reauthorize(proposed, from: candidate)
        let confirmed = try policy.confirm(authorized, at: proposed.createdAt)
        return (authorized, confirmed)
    }

    private func sessionWithRecordedTurn(
        _ session: VoiceTaskConversationSession,
        at date: Date
    ) -> VoiceTaskConversationSession {
        var session = session
        try! session.recordTurn(at: date)
        return session
    }
}

private struct TemporaryConversationDatabase {
    let root: URL
    let databaseURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-conversation-store-\(UUID().uuidString)", isDirectory: true)
        databaseURL = root.appendingPathComponent("Suisui.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
