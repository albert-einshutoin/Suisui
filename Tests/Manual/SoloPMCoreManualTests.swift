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
        try suite.testWriteActionRequiresApproval()
        try suite.testDangerActionIsRejected()
        try suite.testAmbiguousActionRequiresUserConfirmationWarning()
        try suite.testInvalidActionPlanJSONIsBlocking()
        try suite.testPlanningPromptContainsContext()
        try suite.testPlanningPromptForbidsDangerousOperations()

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

    mutating func testWriteActionRequiresApproval() throws {
        let plan = ActionPlan(
            id: "plan-1",
            userInput: "Create a task",
            summary: "Create task",
            actions: [
                PlanAction(id: "action-1", tool: .taskCreate)
            ],
            riskLevel: .write,
            requiresApproval: false
        )

        let result = ActionPlanValidator().validate(plan)

        expect(!result.isValid, "Write action without approval should be invalid.")
        expect(result.issues.contains { $0.path == "requiresApproval" }, "Approval issue should be reported.")
    }

    mutating func testDangerActionIsRejected() throws {
        let plan = ActionPlan(
            id: "plan-1",
            userInput: "Delete file",
            summary: "Delete file",
            actions: [
                PlanAction(id: "action-1", tool: .filesystemCreateMarkdownFile, riskLevel: .danger)
            ],
            riskLevel: .danger,
            requiresApproval: true
        )

        let result = ActionPlanValidator().validate(plan)

        expect(!result.isValid, "Danger action should be invalid.")
        expect(result.issues.contains { $0.message.contains("Dangerous") }, "Danger issue should be reported.")
    }

    mutating func testAmbiguousActionRequiresUserConfirmationWarning() throws {
        let plan = ActionPlan(
            id: "plan-1",
            userInput: "Next Friday",
            summary: "Create task",
            actions: [
                PlanAction(id: "action-1", tool: .taskCreate, requiresUserConfirmation: true)
            ],
            riskLevel: .write,
            requiresApproval: true
        )

        let result = ActionPlanValidator().validate(plan)

        expect(result.isValid, "Ambiguous action should remain executable after review.")
        expect(result.requiresUserConfirmation, "Ambiguous action should require user confirmation.")
    }

    mutating func testInvalidActionPlanJSONIsBlocking() throws {
        let result = ActionPlanValidator().validate(jsonData: Data("{".utf8))

        expect(!result.isValid, "Invalid JSON should be blocking.")
        expectEqual(result.issues.first?.path, "$", "Invalid JSON should point to document root.")
    }

    mutating func testPlanningPromptContainsContext() throws {
        let request = PlanningRequest(
            userInput: "Create a task for next Friday",
            currentDate: Date(timeIntervalSince1970: 1_783_200_000),
            timeZoneIdentifier: "Asia/Tokyo",
            availableTools: [.taskCreate, .projectCreate],
            knowledgeFrameCandidates: []
        )

        let prompt = PlanningPromptBuilder().buildPrompt(for: request)

        expect(prompt.user.contains("Time zone: Asia/Tokyo"), "Prompt should include timezone.")
        expect(prompt.user.contains("project.create"), "Prompt should include project.create.")
        expect(prompt.user.contains("task.create"), "Prompt should include task.create.")
        expect(prompt.user.contains("Create a task for next Friday"), "Prompt should include user input.")
    }

    mutating func testPlanningPromptForbidsDangerousOperations() throws {
        let prompt = PlanningPromptBuilder().buildPrompt(
            for: PlanningRequest(userInput: "Delete this file")
        )

        expect(prompt.system.contains("Dangerous operations are forbidden"), "Prompt should forbid dangerous operations.")
        expect(prompt.system.contains("Git push"), "Prompt should mention Git push as forbidden.")
        expect(prompt.system.contains("file delete"), "Prompt should mention file delete as forbidden.")
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
