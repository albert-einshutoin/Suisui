import XCTest
@testable import SoloPMCore

final class AuditLoggerTests: XCTestCase {
    func testRedactingAuditLoggerRemovesSecretsFromMetadata() throws {
        let base = InMemoryAuditLogger()
        let logger = RedactingAuditLogger(base: base)

        try logger.record(
            AuditEvent(
                category: "secret",
                action: "save",
                status: .succeeded,
                metadata: [
                    "api_key": "sk-test-secret",
                    "Authorization": "Bearer token",
                    "note": "safe"
                ]
            )
        )

        let event = try XCTUnwrap(base.recordedEvents.first)
        XCTAssertEqual(event.metadata["api_key"], "[REDACTED]")
        XCTAssertEqual(event.metadata["Authorization"], "[REDACTED]")
        XCTAssertEqual(event.metadata["note"], "safe")
    }

    func testSQLiteAuditLoggerPersistsRedactedEvents() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        let logger = SQLiteAuditLogger(connection: connection)
        let redactingLogger = RedactingAuditLogger(base: logger)

        try redactingLogger.record(
            AuditEvent(
                timestamp: Date(timeIntervalSince1970: 1_789_000_000),
                category: "planning",
                action: "request.completed",
                status: .succeeded,
                metadata: [
                    "provider": "openai.responses",
                    "api_key": "sk-secret",
                    "summary": "Created task"
                ]
            )
        )

        let events = try logger.list()

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.category, "planning")
        XCTAssertEqual(events.first?.status, .succeeded)
        XCTAssertEqual(events.first?.metadata["provider"], "openai.responses")
        XCTAssertEqual(events.first?.metadata["api_key"], "[REDACTED]")
        XCTAssertEqual(events.first?.metadata["summary"], "Created task")
    }
}
