import Foundation
@testable import SoloPMCore

enum ToolRegistryTestFactory {
    static func inMemoryPhase2MVP(
        workspaceRoot: URL,
        auditLogger: (any AuditLogger)? = nil
    ) throws -> ToolRegistry {
        let connection = try SQLiteConnection(path: ":memory:")
        try migrate(connection: connection, migrations: CoreMigrations.phase2)

        return try ToolRegistry.phase2MVP(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection),
            notificationClient: InMemoryNotificationClient(),
            calendarClient: InMemoryCalendarClient(),
            reminderClient: InMemoryReminderClient(),
            fileAccessClient: LocalFileAccessClient(workspaceRoot: workspaceRoot),
            mailDraftClient: InMemoryMailDraftClient(),
            notificationRequestStore: SQLiteNotificationRequestStore(connection: connection),
            calendarLinkStore: SQLiteCalendarLinkStore(connection: connection),
            reminderLinkStore: SQLiteReminderLinkStore(connection: connection),
            auditLogger: auditLogger
        )
    }

    private static func migrate(connection: SQLiteConnection, migrations: [DatabaseMigration]) throws {
        try connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id TEXT PRIMARY KEY NOT NULL,
                applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            );
            """
        )
        let alreadyApplied = Set(try connection.queryStrings("SELECT id FROM schema_migrations ORDER BY id;"))
        for migration in migrations where !alreadyApplied.contains(migration.id) {
            try connection.execute("BEGIN;")
            do {
                try migration.apply(connection)
                try connection.execute("INSERT INTO schema_migrations (id) VALUES ('\(escape(migration.id))');")
                try connection.execute("COMMIT;")
            } catch {
                try? connection.execute("ROLLBACK;")
                throw error
            }
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
