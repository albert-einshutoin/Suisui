import XCTest
@testable import SoloPMCore

final class DatabaseMigrationTests: XCTestCase {
    func testDatabaseLocationCanUseAbsoluteEnvironmentOverrideForRuntimeSmokeIsolation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-db-location-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = root.appendingPathComponent("nested/SoloPM-runtime-smoke.sqlite")
        defer { try? FileManager.default.removeItem(at: root) }

        let resolvedURL = try SoloPMAppDatabaseLocation.defaultDatabaseURL(
            createDirectory: true,
            environment: [SoloPMAppDatabaseLocation.databasePathOverrideEnvironmentKey: databaseURL.path]
        )

        XCTAssertEqual(resolvedURL, databaseURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.deletingLastPathComponent().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testDatabaseLocationRejectsRelativeEnvironmentOverride() throws {
        XCTAssertThrowsError(
            try SoloPMAppDatabaseLocation.defaultDatabaseURL(
                createDirectory: false,
                environment: [SoloPMAppDatabaseLocation.databasePathOverrideEnvironmentKey: "relative/SoloPM.sqlite"]
            )
        ) { error in
            guard case let DatabaseError.openFailed(message) = error else {
                XCTFail("Expected DatabaseError.openFailed, got \(error).")
                return
            }
            XCTAssertTrue(message.contains(SoloPMAppDatabaseLocation.databasePathOverrideEnvironmentKey))
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
}
