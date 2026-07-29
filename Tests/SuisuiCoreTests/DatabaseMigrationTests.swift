import Darwin
import XCTest
@testable import SuisuiCore

final class DatabaseMigrationTests: XCTestCase {
    func testOrchestrationStateMigrationCreatesDurableCheckpointTable() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeOrchestration = Array(
            CoreMigrations.current.prefix {
                $0.id != "0030_create_voice_conversation_orchestration_state"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeOrchestration
        )
        XCTAssertFalse(
            try connection.tableExists(
                "voice_task_conversation_orchestration_states"
            )
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        XCTAssertTrue(
            try connection.tableExists(
                "voice_task_conversation_orchestration_states"
            )
        )
        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT id FROM schema_migrations
                WHERE id = '0030_create_voice_conversation_orchestration_state';
                """
            ),
            ["0030_create_voice_conversation_orchestration_state"]
        )
    }

    func testOrchestrationStateRetentionMigrationPreservesValidRowsDropsOrphansAndAddsCascade()
        throws
    {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeRetention = Array(
            CoreMigrations.current.prefix {
                $0.id != "0032_cascade_orchestration_state_retention"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeRetention
        )
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_sessions (
                id, state, title, entry_point, created_at, updated_at
            )
            VALUES (
                'valid-session', 'active', 'Session', 'voice_command', 1, 1
            );
            INSERT INTO voice_task_conversation_orchestration_states (
                session_id, payload, updated_at
            )
            VALUES
                ('valid-session', X'01', 1),
                ('orphan-session', X'02', 2);
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT session_id
                FROM voice_task_conversation_orchestration_states
                ORDER BY session_id;
                """
            ),
            ["valid-session"]
        )
        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT "table" || ':' || "from" || ':' || "to" || ':' || on_delete
                FROM pragma_foreign_key_list(
                    'voice_task_conversation_orchestration_states'
                );
                """
            ),
            [
                "voice_task_conversation_sessions:session_id:id:CASCADE"
            ]
        )
    }

    func testActionLinkExpansionMigrationPreservesLegacyRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeExpansion = Array(
            CoreMigrations.current.prefix {
                $0.id != "0031_expand_conversation_action_links"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeExpansion
        )
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_sessions (
                id, state, title, entry_point, created_at, updated_at
            )
            VALUES ('session-1', 'active', 'Session', 'voice_command', 1, 1);
            INSERT INTO voice_task_conversation_turns (
                id, session_id, author, confirmed_text, created_at
            )
            VALUES ('turn-1', 'session-1', 'user', 'Create task', 1);
            INSERT INTO conversation_action_links (
                id, session_id, source_turn_id, action_plan_id,
                reviewed_fingerprint, created_at
            )
            VALUES (
                'link-1', 'session-1', 'turn-1', 'plan-1',
                'reviewed', 1
            );
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        let row = try XCTUnwrap(
            connection.queryRows(
                """
                SELECT
                    action_statuses_json,
                    task_snapshot_fingerprint,
                    retry_of_action_link_id
                FROM conversation_action_links
                WHERE id = 'link-1';
                """
            ).first
        )
        XCTAssertEqual(try row.string("action_statuses_json"), "[]")
        XCTAssertNil(try row.optionalString("task_snapshot_fingerprint"))
        XCTAssertNil(try row.optionalString("retry_of_action_link_id"))
    }

    func testReviewedTaskSnapshotBindingMigrationPreservesLegacyRows()
        throws
    {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeSnapshotBinding = Array(
            CoreMigrations.current.prefix {
                $0.id != "0033_bind_all_reviewed_task_snapshots"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeSnapshotBinding
        )
        try connection.execute(
            """
            INSERT INTO tasks (id, title, status)
            VALUES (41, 'Legacy task', 'planned');
            INSERT INTO voice_task_conversation_sessions (
                id, state, title, entry_point, created_at, updated_at
            )
            VALUES ('session-1', 'active', 'Session', 'voice_command', 1, 1);
            INSERT INTO voice_task_conversation_turns (
                id, session_id, author, confirmed_text, created_at
            )
            VALUES ('turn-1', 'session-1', 'user', 'Update task', 1);
            INSERT INTO conversation_action_links (
                id, session_id, source_turn_id, action_plan_id,
                task_id, reviewed_fingerprint,
                task_snapshot_fingerprint, created_at
            )
            VALUES (
                'link-1', 'session-1', 'turn-1', 'plan-1',
                41, 'reviewed', 'legacy-task-fingerprint', 1
            );
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT mutation_revision FROM tasks WHERE id = 41;"
            ),
            ["0"]
        )
        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT task_snapshots_json
                FROM conversation_action_links
                WHERE id = 'link-1';
                """
            ),
            ["[]"]
        )
        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT id FROM schema_migrations
                WHERE id = '0033_bind_all_reviewed_task_snapshots';
                """
            ),
            ["0033_bind_all_reviewed_task_snapshots"]
        )
    }

    func testConversationMigrationUpgradesDatabaseAt0024AndPreservesExistingTasks() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeConversation = Array(
            CoreMigrations.current.prefix {
                $0.id != "0025_create_voice_task_conversations"
            }
        )
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrationsBeforeConversation)
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, created_at, updated_at)
            VALUES (901, 'Existing project', 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            INSERT INTO tasks (id, project_id, title, status, created_at, updated_at)
            VALUES (902, 901, 'Existing task', 'planned', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
            """
        )

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertEqual(
            try connection.queryStrings("SELECT title FROM tasks WHERE id = 902;"),
            ["Existing task"]
        )
        XCTAssertTrue(try connection.tableExists("voice_task_conversation_sessions"))
    }

    func testConversationMigrationIsIdempotent() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertEqual(
            try connection.queryStrings(
                """
                SELECT id
                FROM schema_migrations
                WHERE id = '0025_create_voice_task_conversations';
                """
            ),
            ["0025_create_voice_task_conversations"]
        )
    }

    func testActionLinkOperationMigrationPreservesExistingLinksAsUnspecified() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeOperationKind = Array(
            CoreMigrations.current.prefix {
                $0.id != "0026_add_conversation_action_link_operation"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeOperationKind
        )
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_sessions (
                id, state, title, entry_point, created_at, updated_at
            )
            VALUES ('session-1', 'active', 'Session', 'voice_command', 1, 1);
            INSERT INTO voice_task_conversation_turns (
                id, session_id, author, confirmed_text, created_at
            )
            VALUES ('turn-1', 'session-1', 'user', 'Create task', 1);
            INSERT INTO conversation_action_links (
                id, session_id, source_turn_id, task_id,
                reviewed_fingerprint, created_at
            )
            VALUES ('link-1', 'session-1', 'turn-1', 1, 'reviewed', 1);
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT operation_kind FROM conversation_action_links WHERE id = 'link-1';"
            ),
            ["unspecified"]
        )
    }

    func testTaskContextFactPolicyMigrationPreservesLegacyFactsAndAddsEvidenceSchema() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeFactPolicy = Array(
            CoreMigrations.current.prefix {
                $0.id != "0027_add_task_context_fact_policy"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeFactPolicy
        )
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_sessions (
                id, state, title, entry_point, created_at, updated_at
            )
            VALUES ('session-1', 'active', 'Session', 'voice_command', 1, 1);
            INSERT INTO voice_task_conversation_turns (
                id, session_id, author, confirmed_text, created_at
            )
            VALUES ('turn-1', 'session-1', 'user', 'Remember release', 1);
            INSERT INTO task_context_facts (
                id, session_id, kind, scope_kind, state, value,
                source_turn_id, confidence, author, created_at
            )
            VALUES (
                'fact-1', 'session-1', 'goal', 'session', 'confirmed',
                'Legacy release goal', 'turn-1', 1, 'system_derived', 1
            );
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        let legacy = try XCTUnwrap(
            try connection.materializedRows(
                """
                SELECT value, author, source_excerpt_digest, expires_at
                FROM task_context_facts
                WHERE id = 'fact-1';
                """
            ).first
        )
        XCTAssertEqual(try legacy.string("value"), "Legacy release goal")
        XCTAssertEqual(try legacy.string("author"), "deterministic")
        XCTAssertNil(try legacy.optionalString("source_excerpt_digest"))
        XCTAssertNil(try legacy.optionalDouble("expires_at"))

        try connection.execute(
            """
            INSERT INTO task_context_facts (
                id, session_id, kind, scope_kind, scope_target_id, state, value,
                source_turn_id, source_excerpt_digest, confidence, author,
                expires_at, created_at
            )
            VALUES (
                'fact-2', 'session-1', 'acceptance_criterion', 'task', 42,
                'rejected', 'Signed artifact exists', 'turn-1',
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                1, 'deterministic', 100, 2
            );
            """
        )
        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT kind || ':' || state FROM task_context_facts WHERE id = 'fact-2';"
            ),
            ["acceptance_criterion:rejected"]
        )
    }

    func testTaskContextEvidenceTombstoneMigrationPreservesTurnIdentifierAfterConversationDeletion() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsThroughFactPolicy = Array(
            CoreMigrations.current.prefix {
                $0.id != "0028_preserve_task_context_fact_evidence_tombstones"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsThroughFactPolicy
        )
        try connection.execute(
            """
            INSERT INTO voice_task_conversation_sessions (
                id, state, title, entry_point, created_at, updated_at
            )
            VALUES ('session-tombstone', 'active', 'Session', 'voice_command', 1, 1);
            INSERT INTO voice_task_conversation_turns (
                id, session_id, author, confirmed_text, created_at
            )
            VALUES (
                'turn-tombstone', 'session-tombstone', 'user',
                'Confirmed evidence', 1
            );
            INSERT INTO task_context_facts (
                id, session_id, kind, scope_kind, scope_target_id, state, value,
                source_turn_id, source_excerpt_digest, confidence, author, created_at
            )
            VALUES (
                'fact-tombstone', 'session-tombstone', 'goal', 'task', 42,
                'confirmed', 'Ship safely', 'turn-tombstone',
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
                1, 'user_explicit', 1
            );
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )
        try connection.execute(
            "DELETE FROM voice_task_conversation_sessions WHERE id = 'session-tombstone';"
        )

        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT source_turn_id FROM task_context_facts WHERE id = 'fact-tombstone';"
            ),
            ["turn-tombstone"]
        )
    }

    func testTaskContextSuccessorLookupMigrationAddsIndex() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeSuccessorIndex = Array(
            CoreMigrations.current.prefix {
                $0.id != "0029_index_task_context_fact_successors"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeSuccessorIndex
        )
        XCTAssertFalse(
            Set(
                try connection.queryRows(
                    "PRAGMA index_list(task_context_facts);"
                ).compactMap { $0["name"] }
            ).contains("idx_task_context_facts_supersedes")
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        XCTAssertTrue(
            Set(
                try connection.queryRows(
                    "PRAGMA index_list(task_context_facts);"
                ).compactMap { $0["name"] }
            ).contains("idx_task_context_facts_supersedes")
        )
    }

    func testTaskContextSuccessorLookupMigrationRejectsLegacyForkedHistory() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeSuccessorIndex = Array(
            CoreMigrations.current.prefix {
                $0.id != "0029_index_task_context_fact_successors"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeSuccessorIndex
        )
        try connection.execute(
            """
            INSERT INTO task_context_facts (
                id, session_id, kind, scope_kind, scope_target_id, state,
                value, source_turn_id, source_excerpt_digest, confidence,
                author, supersedes_fact_id, created_at
            )
            VALUES
                ('legacy-parent', 'session', 'constraint', 'task', 42, 'confirmed',
                 'Original', 'turn', NULL, 1.0, 'user_explicit', NULL, 1.0),
                ('legacy-branch-a', 'session', 'constraint', 'task', 42, 'confirmed',
                 'Branch A', 'turn', NULL, 1.0, 'user_explicit', 'legacy-parent', 2.0),
                ('legacy-branch-b', 'session', 'constraint', 'task', 42, 'confirmed',
                 'Branch B', 'turn', NULL, 1.0, 'user_explicit', 'legacy-parent', 3.0);
            """
        )

        XCTAssertThrowsError(
            try SQLiteMigrationRunner.migrate(
                connection: connection,
                migrations: CoreMigrations.current
            )
        )
        XCTAssertFalse(
            try connection.queryStrings(
                "SELECT id FROM schema_migrations WHERE id = '0029_index_task_context_fact_successors';"
            ).contains("0029_index_task_context_fact_successors")
        )
    }

    func testTaskContextSuccessorLookupMigrationAcceptsAtomicCorrectionPair() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeSuccessorIndex = Array(
            CoreMigrations.current.prefix {
                $0.id != "0029_index_task_context_fact_successors"
            }
        )
        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: migrationsBeforeSuccessorIndex
        )
        try connection.execute(
            """
            INSERT INTO task_context_facts (
                id, session_id, kind, scope_kind, scope_target_id, state,
                value, source_turn_id, source_excerpt_digest, confidence,
                author, supersedes_fact_id, created_at
            )
            VALUES
                ('correction-parent', 'session', 'constraint', 'task', 42, 'confirmed',
                 'Original', 'turn', NULL, 1.0, 'user_explicit', NULL, 1.0),
                ('correction-marker', 'session', 'constraint', 'task', 42, 'superseded',
                 'Original', 'turn', NULL, 1.0, 'user_explicit', 'correction-parent', 2.0),
                ('correction-value', 'session', 'constraint', 'task', 42, 'confirmed',
                 'Corrected', 'replacement-turn', NULL, 1.0, 'user_explicit',
                 'correction-parent', 2.0);
            """
        )

        try SQLiteMigrationRunner.migrate(
            connection: connection,
            migrations: CoreMigrations.current
        )

        XCTAssertEqual(
            try connection.queryStrings(
                "SELECT id FROM schema_migrations WHERE id = '0029_index_task_context_fact_successors';"
            ),
            ["0029_index_task_context_fact_successors"]
        )
    }

    func testApprovalReplayStoreRejectsNonceAfterDatabaseReopen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-approval-replay-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let approval = ApprovedExecution(
            approvalID: UUID(),
            sessionID: "session-1",
            planID: "plan-1",
            canonicalPlanDigest: Data(repeating: 7, count: 32),
            enabledActionIDs: ["task"],
            issuedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_300),
            nonce: UUID()
        )

        do {
            let connection = try SQLiteConnection(path: databaseURL.path)
            try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
            let store = SQLiteApprovalReplayStore(connection: connection)
            XCTAssertTrue(try store.claim(approval, at: approval.issuedAt))
            try store.finish(nonce: approval.nonce, state: .completed, at: approval.issuedAt)
        }

        let reopenedConnection = try SQLiteConnection(path: databaseURL.path)
        try SQLiteMigrationRunner.migrate(connection: reopenedConnection, migrations: CoreMigrations.current)
        let reopenedStore = SQLiteApprovalReplayStore(connection: reopenedConnection)

        XCTAssertFalse(try reopenedStore.claim(approval, at: approval.issuedAt))
        XCTAssertEqual(try reopenedStore.state(for: approval.nonce), .completed)
    }

    func testDatabaseLocationCanUseAbsoluteEnvironmentOverrideForRuntimeSmokeIsolation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-db-location-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("nested/Suisui-runtime-smoke.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let resolvedURL = try SuisuiAppDatabaseLocation.defaultDatabaseURL(
            createDirectory: true,
            environment: [SuisuiAppDatabaseLocation.databasePathOverrideEnvironmentKey: databaseURL.path]
        )

        XCTAssertEqual(resolvedURL, databaseURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testDatabaseLocationRejectsRelativeEnvironmentOverride() throws {
        XCTAssertThrowsError(
            try SuisuiAppDatabaseLocation.defaultDatabaseURL(
                createDirectory: false,
                environment: [SuisuiAppDatabaseLocation.databasePathOverrideEnvironmentKey: "relative/Suisui.sqlite"]
            )
        ) { error in
            guard case let DatabaseError.openFailed(message) = error else {
                XCTFail("Expected DatabaseError.openFailed, got \(error).")
                return
            }
            XCTAssertTrue(message.contains(SuisuiAppDatabaseLocation.databasePathOverrideEnvironmentKey))
            XCTAssertTrue(message.contains("absolute"))
        }
    }

    func testSQLiteConnectionEnforcesForeignKeyConstraints() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute(
            """
            CREATE TABLE parent_records (
                id INTEGER PRIMARY KEY NOT NULL
            );
            CREATE TABLE child_records (
                id INTEGER PRIMARY KEY NOT NULL,
                parent_id INTEGER NOT NULL,
                FOREIGN KEY(parent_id) REFERENCES parent_records(id)
            );
            """
        )

        XCTAssertThrowsError(
            try connection.execute("INSERT INTO child_records (id, parent_id) VALUES (1, 404);")
        ) { error in
            guard case let DatabaseError.executeFailed(message) = error else {
                XCTFail("Expected SQLite foreign key enforcement, got \(error).")
                return
            }
            XCTAssertTrue(message.localizedCaseInsensitiveContains("foreign key"))
        }
    }

    func testSQLiteConnectionMaterializedRowsDecodeRequestedColumns() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute(
            """
            CREATE TABLE typed_rows (
                id INTEGER PRIMARY KEY NOT NULL,
                title TEXT NOT NULL,
                optional_note TEXT,
                payload BLOB
            );
            INSERT INTO typed_rows (id, title, optional_note, payload)
            VALUES (42, 'Launch', NULL, X'73616665');
            """
        )

        let rows = try connection.materializedRows(
            "SELECT id, title, optional_note, payload FROM typed_rows;"
        ).map { row in
            (
                id: try row.int64("id"),
                title: try row.string("title"),
                note: try row.optionalString("optional_note"),
                payload: try row.data("payload")
            )
        }

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 42)
        XCTAssertEqual(rows.first?.title, "Launch")
        XCTAssertNil(rows.first?.note)
        XCTAssertEqual(rows.first?.payload, Data("safe".utf8))
    }

    func testSQLiteConnectionMaterializedRowsFailOnMissingColumn() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute("CREATE TABLE typed_rows (id INTEGER PRIMARY KEY NOT NULL); INSERT INTO typed_rows (id) VALUES (1);")

        let row = try XCTUnwrap(connection.materializedRows("SELECT id FROM typed_rows;").first)
        XCTAssertThrowsError(try row.string("title")) { error in
            XCTAssertEqual(error as? DatabaseError, .missingColumn("title"))
        }
    }

    func testSQLiteConnectionMaterializedRowsPreserveCellTypesAndEmbeddedNUL() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let text = "prefix\u{0}suffix"

        let row = try XCTUnwrap(
            connection.materializedRows(
                """
                SELECT
                    NULL AS null_value,
                    '' AS empty_text,
                    ? AS nul_text,
                    X'' AS empty_blob,
                    42 AS integer_value,
                    1.5 AS real_value,
                    1 AS bool_value,
                    '2026-07-24T00:00:00Z' AS date_value;
                """,
                parameters: [.text(text)]
            ).first
        )

        XCTAssertEqual(try row.cell("null_value"), .null)
        XCTAssertEqual(try row.cell("empty_text"), .text(""))
        XCTAssertEqual(try row.cell("nul_text"), .text(text))
        XCTAssertEqual(try row.cell("empty_blob"), .blob(Data()))
        XCTAssertEqual(try row.cell("integer_value"), .integer(42))
        XCTAssertEqual(try row.cell("real_value"), .real(1.5))
        XCTAssertTrue(try row.bool("bool_value"))
        let dateFormatter = ISO8601DateFormatter()
        XCTAssertEqual(
            try row.date("date_value", using: dateFormatter.date(from:)),
            dateFormatter.date(from: "2026-07-24T00:00:00Z")
        )
        XCTAssertNil(row["null_value"])
        XCTAssertEqual(row["empty_text"], "")
    }

    func testSQLiteConnectionMaterializedRowsRejectStorageClassMismatch() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        let row = try XCTUnwrap(connection.materializedRows("SELECT '42' AS value;").first)
        XCTAssertThrowsError(try row.int64("value")) { error in
            XCTAssertEqual(
                error as? DatabaseError,
                .invalidColumnValue(column: "value", value: "text")
            )
        }
    }

    func testSQLiteConnectionRejectsDuplicateColumnAliases() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        XCTAssertThrowsError(
            try connection.materializedRows("SELECT 1 AS value, 2 AS value;")
        ) { error in
            XCTAssertEqual(error as? DatabaseError, .duplicateColumnName("value"))
        }
    }

    func testSQLitePointerBackedRowDecoderDoesNotExist() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Sources/SuisuiCore/Database/SQLiteDatabaseClient.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("struct SQLiteRow"))
        XCTAssertFalse(source.contains("func query<T>"))
        XCTAssertTrue(source.contains("public struct SQLiteMaterializedRow"))
    }

    func testSQLiteConnectionConfiguresWritableFilePragmas() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-sqlite-pragmas-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let connection = try SQLiteConnection(path: databaseURL.path)

        XCTAssertEqual(try connection.queryStrings("PRAGMA foreign_keys;"), ["1"])
        XCTAssertEqual(try connection.queryStrings("PRAGMA journal_mode;"), ["wal"])
        XCTAssertEqual(
            try connection.queryStrings("PRAGMA busy_timeout;"),
            [String(SQLiteConnection.busyTimeoutMilliseconds)]
        )
        XCTAssertEqual(try connection.queryStrings("PRAGMA synchronous;"), ["1"])
        XCTAssertEqual(try connection.queryStrings("PRAGMA temp_store;"), ["2"])
        XCTAssertEqual(
            try connection.queryStrings("PRAGMA wal_autocheckpoint;"),
            [String(SQLiteConnection.walAutoCheckpointPages)]
        )
    }

    func testSQLiteConnectionSecureFileOpenValidatesBeforeUsingMemoryJournal() throws {
        let root = URL(
            fileURLWithPath: "/private/tmp/suisui-secure-sqlite-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        XCTAssertTrue(FileManager.default.createFile(atPath: databaseURL.path, contents: Data()))
        let descriptor = open(databaseURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var validationCount = 0

        let connection = try SQLiteConnection(
            secureFileDescriptor: descriptor,
            secureFileValidation: {
                validationCount += 1
                XCTAssertEqual(
                    try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber,
                    0
                )
            }
        )
        try connection.execute("CREATE TABLE secure_fixture (id INTEGER PRIMARY KEY);")

        XCTAssertEqual(validationCount, 1)
        XCTAssertEqual(try connection.queryStrings("PRAGMA journal_mode;"), ["memory"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-shm"))
    }

    func testSQLiteConnectionSecureFileDescriptorFailsClosedAcrossPathSwap() throws {
        let root = URL(
            fileURLWithPath: "/private/tmp/suisui-secure-sqlite-swap-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        let displacedURL = root.appendingPathComponent("displaced.sqlite")
        let replacementURL = root.appendingPathComponent("replacement.sqlite")
        XCTAssertTrue(FileManager.default.createFile(atPath: databaseURL.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: replacementURL.path, contents: Data()))
        let descriptor = open(databaseURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }

        enum ExpectedValidationError: Error {
            case pathIdentityChanged
        }

        XCTAssertThrowsError(
            try SQLiteConnection(
                secureFileDescriptor: descriptor,
                secureFileValidation: {
                    try FileManager.default.moveItem(at: databaseURL, to: displacedURL)
                    try FileManager.default.moveItem(at: replacementURL, to: databaseURL)
                    throw ExpectedValidationError.pathIdentityChanged
                }
            )
        ) { error in
            XCTAssertTrue(error is ExpectedValidationError)
        }
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: databaseURL.path)[.size] as? NSNumber,
            0
        )
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: displacedURL.path)[.size] as? NSNumber,
            0
        )
    }

    func testSQLiteConnectionOwnsOpenedFileAfterCallerDescriptorIsClosedAndReused() throws {
        let root = URL(
            fileURLWithPath: "/private/tmp/suisui-secure-sqlite-fd-reuse-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        let reuseURL = root.appendingPathComponent("descriptor-reuse.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: databaseURL.path, contents: Data()))
        XCTAssertTrue(FileManager.default.createFile(atPath: reuseURL.path, contents: Data()))
        let descriptor = open(databaseURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)

        let connection = try SQLiteConnection(
            secureFileDescriptor: descriptor,
            secureFileValidation: {}
        )
        XCTAssertEqual(close(descriptor), 0)
        let reusedDescriptor = open(reuseURL.path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        XCTAssertEqual(reusedDescriptor, descriptor, "the test must exercise immediate descriptor-number reuse")
        defer { close(reusedDescriptor) }

        try connection.execute("CREATE TABLE secure_fixture (id INTEGER PRIMARY KEY);")
        try connection.execute("INSERT INTO secure_fixture (id) VALUES (1);")

        XCTAssertEqual(try connection.queryStrings("SELECT id FROM secure_fixture;"), ["1"])
        XCTAssertEqual(try Data(contentsOf: reuseURL), Data())
    }

    func testSQLiteConnectionSerializesConcurrentTransactions() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute("CREATE TABLE counter (value INTEGER NOT NULL); INSERT INTO counter VALUES (0);")
        let errors = LockedDatabaseErrors()

        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            do {
                try connection.transaction {
                    try connection.execute("UPDATE counter SET value = value + 1;")
                    let value = try connection.queryStrings("SELECT value FROM counter;")
                    guard value.count == 1 else {
                        throw DatabaseError.stepFailed("Concurrent read returned an unexpected row count.")
                    }
                }
            } catch {
                errors.append(error)
            }
        }

        XCTAssertTrue(errors.values.isEmpty, "Unexpected transaction errors: \(errors.values)")
        XCTAssertEqual(try connection.queryStrings("SELECT value FROM counter;"), ["1000"])
    }

    func testSQLiteConnectionRollsBackTransactionWhenOperationThrows() throws {
        enum ExpectedFailure: Error {
            case stop
        }

        let metrics = LockedDatabaseMetrics()
        let connection = try SQLiteConnection(path: ":memory:") { metric in
            metrics.append(metric)
        }
        try connection.execute("CREATE TABLE events (value TEXT NOT NULL);")

        XCTAssertThrowsError(
            try connection.transaction {
                try connection.execute("INSERT INTO events VALUES ('partial');")
                throw ExpectedFailure.stop
            }
        ) { error in
            XCTAssertTrue(error is ExpectedFailure)
        }
        XCTAssertEqual(try connection.queryStrings("SELECT value FROM events;"), [])
        XCTAssertTrue(
            metrics.values.contains {
                $0.kind == .rollback
                    && $0.operation == "transaction"
                    && $0.category == "operation_failed"
            }
        )
    }

    func testSQLiteConnectionKeepsOtherWritesOutsideTransactionBoundary() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try connection.execute("CREATE TABLE events (id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT NOT NULL);")
        let firstWriteCompleted = DispatchSemaphore(value: 0)
        let finishTransaction = DispatchSemaphore(value: 0)
        let competingWriteStarted = DispatchSemaphore(value: 0)
        let group = DispatchGroup()
        let errors = LockedDatabaseErrors()

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                try connection.transaction {
                    try connection.execute("INSERT INTO events (label) VALUES ('transaction-first');")
                    firstWriteCompleted.signal()
                    finishTransaction.wait()
                    try connection.execute("INSERT INTO events (label) VALUES ('transaction-second');")
                }
            } catch {
                errors.append(error)
            }
        }
        firstWriteCompleted.wait()

        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            competingWriteStarted.signal()
            do {
                try connection.execute("INSERT INTO events (label) VALUES ('competing');")
            } catch {
                errors.append(error)
            }
        }
        competingWriteStarted.wait()
        Thread.sleep(forTimeInterval: 0.01)
        finishTransaction.signal()
        group.wait()

        XCTAssertTrue(errors.values.isEmpty, "Unexpected transaction errors: \(errors.values)")
        XCTAssertEqual(
            try connection.queryStrings("SELECT label FROM events ORDER BY id;"),
            ["transaction-first", "transaction-second", "competing"]
        )
    }

    func testSQLiteConnectionRejectsNestedTransactions() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        XCTAssertThrowsError(
            try connection.transaction {
                try connection.transaction {}
            }
        ) { error in
            XCTAssertEqual(error as? DatabaseError, .nestedTransaction)
        }
    }

    func testSQLiteConnectionBusyTimeoutRecoversFromBriefExternalWriter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-sqlite-busy-recovery-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lockingConnection = try SQLiteConnection(path: databaseURL.path)
        let writingConnection = try SQLiteConnection(path: databaseURL.path)
        try lockingConnection.execute("CREATE TABLE events (value TEXT NOT NULL);")
        try lockingConnection.execute("BEGIN IMMEDIATE;")
        let errors = LockedDatabaseErrors()
        let finished = expectation(description: "writer recovers before timeout")

        DispatchQueue.global().async {
            defer { finished.fulfill() }
            do {
                try writingConnection.execute("INSERT INTO events VALUES ('written');")
            } catch {
                errors.append(error)
            }
        }
        Thread.sleep(forTimeInterval: 0.05)
        try lockingConnection.execute("COMMIT;")
        wait(for: [finished], timeout: 2)

        XCTAssertTrue(errors.values.isEmpty, "Unexpected busy errors: \(errors.values)")
        XCTAssertEqual(try lockingConnection.queryStrings("SELECT value FROM events;"), ["written"])
    }

    func testSQLiteConnectionClassifiesBusyTimeout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("suisui-sqlite-busy-timeout-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("Suisui.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let lockingConnection = try SQLiteConnection(path: databaseURL.path)
        let writingConnection = try SQLiteConnection(path: databaseURL.path)
        try lockingConnection.execute("CREATE TABLE events (value TEXT NOT NULL);")
        try lockingConnection.execute("BEGIN IMMEDIATE;")

        XCTAssertThrowsError(
            try writingConnection.execute("INSERT INTO events VALUES ('blocked');")
        ) { error in
            guard case DatabaseError.busyTimeout = error else {
                return XCTFail("Expected classified busy timeout, got \(error).")
            }
        }
        try lockingConnection.execute("ROLLBACK;")
    }

    func testSQLiteDatabaseWorkerCancellationRollsBackTransaction() async throws {
        let metrics = LockedDatabaseMetrics()
        let connection = try SQLiteConnection(path: ":memory:") { metric in
            metrics.append(metric)
        }
        let worker = SQLiteDatabaseWorker(connection: connection)
        try await worker.run { connection in
            try connection.execute("CREATE TABLE events (value TEXT NOT NULL);")
        }
        let writeStarted = expectation(description: "transaction inserted before cancellation")
        let finishOperation = DispatchSemaphore(value: 0)
        let task = Task {
            try await worker.transaction { connection in
                try connection.execute("INSERT INTO events VALUES ('partial');")
                writeStarted.fulfill()
                finishOperation.wait()
            }
        }

        await fulfillment(of: [writeStarted], timeout: 1)
        task.cancel()
        finishOperation.signal()
        do {
            try await task.value
            XCTFail("Cancelled database transaction must not commit.")
        } catch is CancellationError {
            // Expected: the worker checks cancellation before COMMIT.
        }

        let values = try await worker.run { connection in
            try connection.queryStrings("SELECT value FROM events;")
        }
        XCTAssertEqual(values, [])
        XCTAssertTrue(
            metrics.values.contains {
                $0.kind == .rollback
                    && $0.operation == "transaction"
                    && $0.category == "cancelled"
            }
        )
        XCTAssertTrue(metrics.values.contains { $0.kind == .lockWait })
        XCTAssertTrue(metrics.values.contains { $0.kind == .operationDuration })
        XCTAssertFalse(metrics.values.contains { $0.operation.contains("INSERT") })
    }

    func testPhase0MigrationsAreIdempotent() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.phase0)
        try database.migrate(CoreMigrations.phase0)

        XCTAssertEqual(
            try database.appliedMigrationIDs(),
            ["0001_create_settings_and_audit_logs"]
        )
        XCTAssertTrue(try database.tableExists("settings"))
        XCTAssertTrue(try database.tableExists("audit_logs"))
    }

    func testPhase2MigrationsCreateSystemToolTrackingTables() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.phase2)

        XCTAssertTrue(try database.tableExists("notification_requests"))
        XCTAssertTrue(try database.tableExists("calendar_links"))
        XCTAssertTrue(try database.tableExists("reminder_links"))
        XCTAssertTrue(try database.appliedMigrationIDs().contains("0002b_create_system_tool_state"))
    }

    func testCurrentMigrationsUpgradeExistingTaskTableWithDetailColumn() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let taskColumns = try connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
        let appliedMigrationIDs = try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;")

        XCTAssertTrue(taskColumns.contains("detail"))
        XCTAssertTrue(appliedMigrationIDs.contains("0007_add_task_detail"))
    }

    func testProjectBoardMigrationFixtureUpgradesLegacyTaskShapeToCurrentSnapshot() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let fixtureURL = try XCTUnwrap(Bundle.module.url(
            forResource: "phase2-project-board",
            withExtension: "sql"
        ))
        let fixtureSQL = try String(contentsOf: fixtureURL, encoding: .utf8)

        try connection.execute(fixtureSQL)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let taskColumns = try connection.queryRows("PRAGMA table_info(tasks);").compactMap { $0["name"] }
        let snapshot = try SQLiteProjectBoardStore(connection: connection).loadSnapshot()
        let project = try XCTUnwrap(snapshot.projects.first { $0.title == "Legacy Launch" })
        let plannedTask = try XCTUnwrap(project.columns.first { $0.status == .planned }?.tasks.first)
        let doneTask = try XCTUnwrap(project.columns.first { $0.status == .done }?.tasks.first)

        XCTAssertTrue(taskColumns.contains("detail"))
        XCTAssertTrue(taskColumns.contains("completed_at"))
        XCTAssertEqual(plannedTask.detail, "")
        XCTAssertEqual(doneTask.title, "Legacy completed task")
        XCTAssertNotNil(doneTask.completedAt)
        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0012_add_task_completed_at"))
    }

    func testCurrentMigrationsCreateMCPRegistrationTable() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.current)

        XCTAssertTrue(try database.tableExists("mcp_server_registrations"))
        XCTAssertTrue(try database.appliedMigrationIDs().contains("0008_create_mcp_server_registrations"))
    }

    func testCurrentMigrationsCreateExternalTaskLinkTableForIdempotentImports() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertTrue(try connection.tableExists("external_task_links"))
        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0009_create_external_task_links"))

        let columns = try connection.queryRows("PRAGMA table_info(external_task_links);").compactMap { $0["name"] }
        XCTAssertTrue(columns.contains("provider_id"))
        XCTAssertTrue(columns.contains("external_id"))
        XCTAssertTrue(columns.contains("task_id"))

        try connection.execute(
            """
            INSERT INTO projects (id, title, status) VALUES (1, 'Imported', 'active');
            INSERT INTO tasks (id, project_id, title, status) VALUES (1, 1, 'Task', 'backlog');
            INSERT INTO external_task_links (provider_id, external_id, task_id, project_id, title)
            VALUES ('todoist', 'external-1', 1, 1, 'Task');
            """
        )

        XCTAssertThrowsError(
            try connection.execute(
                """
                INSERT INTO external_task_links (provider_id, external_id, task_id, project_id, title)
                VALUES ('todoist', 'external-1', 1, 1, 'Task duplicate');
                """
            )
        )
    }

    func testCurrentMigrationsAddProjectWorkspaceBookmarkForLocalDirectoryScope() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase2)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let projectColumns = try connection.queryRows("PRAGMA table_info(projects);").compactMap { $0["name"] }

        XCTAssertTrue(projectColumns.contains("workspace_path"))
        XCTAssertTrue(projectColumns.contains("workspace_bookmark"))
        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0014_add_project_workspace_bookmark"))
    }

    func testCurrentMigrationsCreateAssistantQueueItemsTable() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertTrue(try connection.tableExists("assistant_queue_items"))
        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0015_create_assistant_queue_items"))
        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0016_add_assistant_queue_cost_preview"))

        let columns = Set(try connection.queryRows("PRAGMA table_info(assistant_queue_items);").compactMap { $0["name"] })
        XCTAssertTrue(columns.contains("id"))
        XCTAssertTrue(columns.contains("state"))
        XCTAssertTrue(columns.contains("risk_level"))
        XCTAssertTrue(columns.contains("payload_kind"))
        XCTAssertTrue(columns.contains("payload_json"))
        XCTAssertTrue(columns.contains("redacted_summary"))
        XCTAssertTrue(columns.contains("review_reason"))
        XCTAssertTrue(columns.contains("required_capabilities_json"))
        XCTAssertTrue(columns.contains("approval_json"))
        XCTAssertTrue(columns.contains("cost_preview_json"))
        XCTAssertTrue(columns.contains("created_at"))
        XCTAssertTrue(columns.contains("updated_at"))

        let indexes = Set(try connection.queryRows("PRAGMA index_list(assistant_queue_items);").compactMap { $0["name"] })
        XCTAssertTrue(indexes.contains("idx_assistant_queue_items_state_updated_at"))
        XCTAssertTrue(indexes.contains("idx_assistant_queue_items_payload_kind"))
    }

    func testCurrentMigrationsCreateManagedAIUsageLedgerTable() throws {
        let connection = try SQLiteConnection(path: ":memory:")

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertTrue(try connection.tableExists("managed_ai_usage_ledger"))
        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0018_create_managed_ai_usage_ledger"))

        let columns = Set(try connection.queryRows("PRAGMA table_info(managed_ai_usage_ledger);").compactMap { $0["name"] })
        XCTAssertTrue(columns.contains("source_receipt_digest"))
        XCTAssertTrue(columns.contains("assistant_queue_item_digest"))
        XCTAssertTrue(columns.contains("billing_mode"))
        XCTAssertTrue(columns.contains("provider"))
        XCTAssertTrue(columns.contains("model_name"))
        XCTAssertTrue(columns.contains("input_tokens"))
        XCTAssertTrue(columns.contains("output_tokens"))
        XCTAssertTrue(columns.contains("cost_cents"))
        XCTAssertTrue(columns.contains("currency_code"))
        XCTAssertTrue(columns.contains("usage_state"))
        XCTAssertTrue(columns.contains("occurred_at"))

        let indexRows = try connection.queryRows("PRAGMA index_list(managed_ai_usage_ledger);")
        let indexes = Set(indexRows.compactMap { $0["name"] })
        XCTAssertTrue(indexes.contains("idx_managed_ai_usage_ledger_occurred_at"))
        XCTAssertTrue(indexes.contains("idx_managed_ai_usage_ledger_queue_digest"))
        XCTAssertEqual(
            indexRows.first { $0["name"] == "idx_managed_ai_usage_ledger_queue_digest" }?["unique"],
            "1"
        )
    }

    func testCurrentMigrationsAddWorkManagementReadModelIndexesWithoutRewritingRows() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsBeforeReadModelIndexes = Array(
            CoreMigrations.current.prefix { $0.id != "0019_add_work_management_read_model_indexes" }
        )

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrationsBeforeReadModelIndexes)
        try connection.execute(
            """
            INSERT INTO projects (id, title, status, tags_json) VALUES (1, 'Large board', 'active', '[]');
            INSERT INTO tasks (
                id,
                project_id,
                title,
                status,
                detail,
                due_at,
                completed_at,
                priority,
                source_command
            )
            VALUES (
                1,
                1,
                'Keep launch responsive',
                'completed',
                'Preserve this detail through index migration.',
                '2026-06-19T09:00:00Z',
                '2026-06-19T17:00:00Z',
                'high',
                'migration-test'
            );
            INSERT INTO artifacts (
                id,
                project_id,
                task_id,
                workspace_path,
                expected_path,
                created_state,
                last_modified_at
            )
            VALUES (
                1,
                1,
                1,
                '/tmp/suisui',
                '/tmp/suisui/launch.md',
                'created',
                '2026-06-19T17:30:00Z'
            );
            INSERT INTO project_milestones (id, project_id, title, due_at, is_completed)
            VALUES (1, 1, 'Ship large board', '2026-06-20T09:00:00Z', 0);
            """
        )

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        XCTAssertTrue(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;").contains("0019_add_work_management_read_model_indexes"))
        XCTAssertEqual(try connection.queryStrings("SELECT title FROM projects WHERE id = 1;"), ["Large board"])
        XCTAssertEqual(try connection.queryStrings("SELECT detail FROM tasks WHERE id = 1;"), ["Preserve this detail through index migration."])
        XCTAssertEqual(try connection.queryStrings("SELECT expected_path FROM artifacts WHERE id = 1;"), ["/tmp/suisui/launch.md"])
        XCTAssertEqual(try connection.queryStrings("SELECT title FROM project_milestones WHERE id = 1;"), ["Ship large board"])

        XCTAssertTrue(try indexNames(on: "tasks", connection: connection).isSuperset(of: [
            "idx_tasks_project_id",
            "idx_tasks_status_due_at",
            "idx_tasks_due_at_status",
            "idx_tasks_project_status",
            "idx_tasks_completed_at"
        ]))
        XCTAssertTrue(try indexNames(on: "projects", connection: connection).contains("idx_projects_status"))
        XCTAssertTrue(try indexNames(on: "artifacts", connection: connection).isSuperset(of: [
            "idx_artifacts_project_task",
            "idx_artifacts_task_project"
        ]))
        XCTAssertTrue(try indexNames(on: "project_milestones", connection: connection).contains("idx_project_milestones_project_due_sort"))
    }

    func testAssistantQueueCostPreviewMigrationKeepsExistingRowsReadable() throws {
        func sql(_ value: String) -> String {
            value.replacingOccurrences(of: "'", with: "''")
        }

        let connection = try SQLiteConnection(path: ":memory:")
        let migrationsThroughAssistantQueue = Array(
            CoreMigrations.current.prefix { $0.id != "0016_add_assistant_queue_cost_preview" }
        )
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: migrationsThroughAssistantQueue)

        let oldItem = AssistantQueueAdapter.makeItem(
            actionPlan: ActionPlan(
                id: "legacy-plan",
                userInput: "Create legacy task",
                summary: "Create legacy task",
                actions: [PlanAction(id: "legacy-action", tool: .taskCreate, riskLevel: .write)],
                riskLevel: .write,
                requiresApproval: true
            ),
            sourceTranscript: "Create legacy task",
            interpretationSummary: "Task creation",
            reason: "Needs review."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payloadJSON = String(decoding: try encoder.encode(oldItem.payload), as: UTF8.self)
        let capabilitiesJSON = String(decoding: try encoder.encode(oldItem.requiredCapabilities), as: UTF8.self)
        let approvalJSON = String(
            decoding: try encoder.encode(AssistantQueueApprovalRecord(
                reviewerID: "legacy-user",
                reviewedContentFingerprint: "legacy-reviewed-content"
            )),
            as: UTF8.self
        )
        try connection.execute(
            """
            INSERT INTO assistant_queue_items (
                id,
                schema_version,
                payload_kind,
                payload_json,
                state,
                risk_level,
                source_transcript,
                interpretation_summary,
                review_reason,
                redacted_summary,
                required_capabilities_json,
                approval_json,
                blocking_reason,
                created_at,
                updated_at
            )
            VALUES (
                'legacy-queue-item',
                1,
                'action_plan',
                '\(sql(payloadJSON))',
                'waitingReview',
                'write',
                'Create legacy task',
                'Task creation',
                'Needs review.',
                'Create legacy task',
                '\(sql(capabilitiesJSON))',
                NULL,
                NULL,
                '2026-07-01T00:00:00Z',
                '2026-07-01T00:00:00Z'
            );

            INSERT INTO assistant_queue_items (
                id,
                schema_version,
                payload_kind,
                payload_json,
                state,
                risk_level,
                source_transcript,
                interpretation_summary,
                review_reason,
                redacted_summary,
                required_capabilities_json,
                approval_json,
                blocking_reason,
                created_at,
                updated_at
            )
            VALUES (
                'legacy-approved-queue-item',
                1,
                'action_plan',
                '\(sql(payloadJSON))',
                'approved',
                'write',
                'Create approved legacy task',
                'Task creation',
                'Approved before cost preview.',
                'Create approved legacy task',
                '\(sql(capabilitiesJSON))',
                '\(sql(approvalJSON))',
                NULL,
                '2026-07-01T00:00:00Z',
                '2026-07-01T00:00:00Z'
            );
            """
        )

        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)

        let columns = Set(try connection.queryRows("PRAGMA table_info(assistant_queue_items);").compactMap { $0["name"] })
        XCTAssertTrue(columns.contains("cost_preview_json"))
        let store = SQLiteAssistantQueueStore(connection: connection)
        let migrated = try store.get(id: "legacy-queue-item")
        XCTAssertEqual(migrated.costPreview?.billingMode, .localOnly)
        XCTAssertTrue(AssistantQueueReadModel.snapshot(from: [migrated]).rows.first?.canApprove ?? false)

        let migratedApproved = try store.get(id: "legacy-approved-queue-item")
        XCTAssertEqual(migratedApproved.state, .waitingReview)
        XCTAssertNil(migratedApproved.approval)
        XCTAssertEqual(migratedApproved.costPreview?.billingMode, .localOnly)
        XCTAssertEqual(
            migratedApproved.reviewReason,
            "Cost preview was added during migration. Review this item again before running."
        )
    }

    private func indexNames(on table: String, connection: SQLiteConnection) throws -> Set<String> {
        Set(try connection.queryRows("PRAGMA index_list(\(table));").compactMap { $0["name"] })
    }
}

private final class LockedDatabaseErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Error] = []

    var values: [Error] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ error: Error) {
        lock.lock()
        storage.append(error)
        lock.unlock()
    }
}

private final class LockedDatabaseMetrics: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SQLiteDatabaseMetric] = []

    var values: [SQLiteDatabaseMetric] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ metric: SQLiteDatabaseMetric) {
        lock.lock()
        storage.append(metric)
        lock.unlock()
    }
}
