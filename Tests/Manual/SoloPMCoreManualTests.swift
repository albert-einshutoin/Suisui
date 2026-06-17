import Darwin
import Foundation
import SoloPMCore

@main
struct ManualTestRunner {
    static func main() throws {
        var suite = ManualTestSuite()

        try suite.testDefaultSettingsAreValid()
        try suite.testInvalidTimeZoneProducesValidationIssue()
        try suite.testInMemorySecretStoreSavesReplacesAndDeletesValues()
        try suite.testPhase0MigrationsAreIdempotent()
        try suite.testRedactingAuditLoggerRemovesSecretsFromMetadata()
        try suite.testEmptySummaryLabelsAreStable()

        suite.finish()
    }
}

private struct ManualTestSuite {
    private var failures: [String] = []

    mutating func testDefaultSettingsAreValid() throws {
        expect(AppSettings.default.validate().isEmpty, "Default settings should be valid.")
    }

    mutating func testInvalidTimeZoneProducesValidationIssue() throws {
        let settings = AppSettings(timeZoneIdentifier: "Invalid/Timezone")
        expectEqual(settings.validate().first?.field, "timeZoneIdentifier", "Invalid timezone should be reported.")
    }

    mutating func testInMemorySecretStoreSavesReplacesAndDeletesValues() throws {
        let store = InMemorySecretStore()
        let key = SecretKey.openAIAPIKey

        try expect(try store.read(key) == nil, "Missing secret should return nil.")
        try store.save("first", for: key)
        expectEqual(try store.read(key), "first", "Secret should be saved.")
        try store.save("second", for: key)
        expectEqual(try store.read(key), "second", "Secret should be replaced.")
        try store.delete(key)
        try expect(try store.read(key) == nil, "Deleted secret should return nil.")
    }

    mutating func testPhase0MigrationsAreIdempotent() throws {
        let database = try SQLiteDatabaseClient(path: ":memory:")

        try database.migrate(CoreMigrations.phase0)
        try database.migrate(CoreMigrations.phase0)

        expectEqual(try database.appliedMigrationIDs(), ["0001_create_settings_and_audit_logs"], "Migration should be recorded once.")
        try expect(try database.tableExists("settings"), "settings table should exist.")
        try expect(try database.tableExists("audit_logs"), "audit_logs table should exist.")
    }

    mutating func testRedactingAuditLoggerRemovesSecretsFromMetadata() throws {
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

        let event = base.recordedEvents[0]
        expectEqual(event.metadata["api_key"], "[REDACTED]", "API key should be redacted.")
        expectEqual(event.metadata["Authorization"], "[REDACTED]", "Authorization header should be redacted.")
        expectEqual(event.metadata["note"], "safe", "Safe metadata should remain.")
    }

    mutating func testEmptySummaryLabelsAreStable() throws {
        let viewModel = MenuBarSummaryViewModel()

        expectEqual(viewModel.todayLabel, "0 tasks today", "Today label should be stable.")
        expectEqual(viewModel.overdueLabel, "0 overdue", "Overdue label should be stable.")
        expectEqual(viewModel.thisWeekLabel, "0 due this week", "This week label should be stable.")
        expect(!viewModel.hasRecentProjects, "Empty summary should not have recent projects.")
    }

    mutating func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !condition() {
            failures.append(message)
        }
    }

    mutating func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            failures.append("\(message) Expected \(expected), got \(actual).")
        }
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("Manual SoloPMCore tests passed.")
            exit(0)
        }

        for failure in failures {
            fputs("Test failure: \(failure)\n", stderr)
        }
        exit(1)
    }
}
