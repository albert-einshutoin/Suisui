import XCTest
@testable import SuisuiCore

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
                    "api_key": "redacted-test-key",
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

    func testRedactingAuditLoggerRemovesSecretsFromSerializedArguments() throws {
        let base = InMemoryAuditLogger()
        let logger = RedactingAuditLogger(base: base)

        try logger.record(
            AuditEvent(
                category: "tools",
                action: "task.create",
                status: .failed,
                metadata: [
                    "arguments": "apiKey=string(\"redacted-test-key\"),title=string(\"Secret task\")"
                ]
            )
        )

        let event = try XCTUnwrap(base.recordedEvents.first)
        XCTAssertEqual(event.metadata["arguments"], "[REDACTED]")
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
                    "api_key": "redacted-test-key",
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

    func testSQLiteAuditLoggerRejectsCorruptedStatusInsteadOfClassifyingAsFailed() throws {
        let connection = try migratedConnection()
        let logger = SQLiteAuditLogger(connection: connection)
        try logger.record(AuditEvent(category: "planning", action: "request.completed", status: .succeeded))

        try connection.execute("UPDATE audit_logs SET status = 'paused';")

        XCTAssertThrowsError(try logger.list()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidEnum(column: "audit_logs.status", value: "paused"))
        }
    }

    func testSQLiteAuditLoggerRejectsCorruptedTimestampInsteadOfUsingEpoch() throws {
        let connection = try migratedConnection()
        let logger = SQLiteAuditLogger(connection: connection)
        try logger.record(AuditEvent(category: "planning", action: "request.completed", status: .succeeded))

        try connection.execute("UPDATE audit_logs SET timestamp = 'not-a-date';")

        XCTAssertThrowsError(try logger.list()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidDate(column: "audit_logs.timestamp", value: "not-a-date"))
        }
    }

    func testSQLiteAuditLoggerRejectsCorruptedMetadataInsteadOfDroppingIt() throws {
        let connection = try migratedConnection()
        let logger = SQLiteAuditLogger(connection: connection)
        try logger.record(
            AuditEvent(
                category: "planning",
                action: "request.completed",
                status: .succeeded,
                metadata: ["provider": "openai.responses"]
            )
        )

        try connection.execute("UPDATE audit_logs SET metadata_json = 'not-json';")

        XCTAssertThrowsError(try logger.list()) { error in
            XCTAssertEqual(error as? LocalStoreDecodingError, .invalidStringMap(column: "audit_logs.metadata_json"))
        }
    }

    private func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }
}
