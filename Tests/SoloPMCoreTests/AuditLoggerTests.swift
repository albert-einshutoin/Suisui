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
}

