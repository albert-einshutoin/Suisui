import XCTest
@testable import SoloPMCore

final class SoloPMHarnessTests: XCTestCase {
    func testScenarioCatalogCoversPhase13AutomationSurfaces() throws {
        let catalog = SoloPMHarnessScenario.templateCatalog()
        XCTAssertEqual(
            Set(catalog.map(\.kind)),
            [
                .providerPromptRegression,
                .taskMutationFlow,
                .documentScopedAutomation,
                .mcpCompatibility
            ]
        )

        let taskMutation = try XCTUnwrap(catalog.first { $0.kind == .taskMutationFlow })
        XCTAssertEqual(
            taskMutation.expectedMutations.map(\.operation),
            [.create, .update, .complete, .updateDueDate, .moveProject]
        )
        XCTAssertTrue(taskMutation.assertions.contains(.approvalBoundary))
        XCTAssertTrue(taskMutation.assertions.contains(.auditLogRecorded))
        XCTAssertTrue(taskMutation.requiredCapabilities.contains(.taskMutation))

        let encoded = try JSONEncoder().encode(taskMutation)
        let decoded = try JSONDecoder().decode(SoloPMHarnessScenario.self, from: encoded)
        XCTAssertEqual(decoded, taskMutation)
    }

    func testLocalAndCloudTriggeredRunsShareResultEnvelopeShape() {
        let scenario = SoloPMHarnessScenario.templateCatalog()[0]
        let step = SoloPMHarnessStepResult(
            id: "provider-plan",
            status: .passed,
            expected: "task.create action",
            actual: "task.create action",
            failureReason: nil,
            durationMilliseconds: 42
        )

        let local = SoloPMHarnessRun.completed(
            id: "run-local",
            scenario: scenario,
            trigger: .local,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [step],
            logs: [SoloPMHarnessLogEntry(level: .info, message: "provider smoke passed")]
        )
        let cloud = SoloPMHarnessRun.completed(
            id: "run-cloud",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [step],
            logs: [SoloPMHarnessLogEntry(level: .info, message: "provider smoke passed")]
        )

        XCTAssertEqual(local.resultEnvelope.shape, cloud.resultEnvelope.shape)
        XCTAssertEqual(local.resultEnvelope.schemaVersion, 1)
        XCTAssertEqual(cloud.resultEnvelope.schemaVersion, 1)
        XCTAssertEqual(local.status, .passed)
        XCTAssertEqual(cloud.status, .passed)
    }

    func testHistoryStorePersistsDiffFailureReasonAndRedactedLogs() throws {
        let rawCredential = "sk-" + "proj-redacted123456"
        let scenario = SoloPMHarnessScenario(
            id: "mcp-compatibility-smoke",
            name: "MCP compatibility smoke",
            kind: .mcpCompatibility,
            requiredCapabilities: [.mcpToolCall],
            expectedMutations: [],
            assertions: [.redactedLogs, .resultDiffRecorded]
        )
        let failedStep = SoloPMHarnessStepResult(
            id: "call-task-create",
            status: .failed,
            expected: "tool call succeeds",
            actual: "401 credential \(rawCredential)",
            failureReason: "MCP server rejected the request",
            durationMilliseconds: 130
        )
        let run = SoloPMHarnessRun.completed(
            id: "run-failed",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [failedStep],
            logs: [
                SoloPMHarnessLogEntry(level: .error, message: "credential \(rawCredential) failed")
            ]
        )

        var store = RedactingSoloPMHarnessRunStore()
        try store.save(run, plan: .pro)
        let saved = try XCTUnwrap(store.runs.first)

        XCTAssertEqual(saved.status, .failed)
        XCTAssertEqual(saved.diff?.expected, "tool call succeeds")
        XCTAssertEqual(saved.diff?.actual, "401 credential [REDACTED_SECRET]")
        XCTAssertEqual(saved.failureReason, "MCP server rejected the request")
        XCTAssertEqual(saved.redactedLogs[0].message, "credential [REDACTED_SECRET] failed")
    }

    func testHarnessRunMapsToSyncPayloadWithoutRawLogs() {
        let scenario = SoloPMHarnessScenario.templateCatalog()[1]
        let run = SoloPMHarnessRun.completed(
            id: "run-sync",
            scenario: scenario,
            trigger: .cloudTriggered,
            startedAt: "2026-06-21T06:00:00Z",
            finishedAt: "2026-06-21T06:00:01Z",
            steps: [
                SoloPMHarnessStepResult(
                    id: "mutation",
                    status: .failed,
                    expected: "status=in_progress",
                    actual: "status=blocked",
                    failureReason: "Unexpected status",
                    durationMilliseconds: 55
                )
            ],
            logs: [SoloPMHarnessLogEntry(level: .error, message: "raw provider details")]
        )

        XCTAssertEqual(
            run.syncPayload,
            SyncHarnessRunPayload(
                id: "run-sync",
                scenario: "task-mutation-flow",
                status: "failed",
                scenarioKind: "taskMutationFlow",
                trigger: "cloudTriggered",
                failureReason: "Unexpected status",
                diffSummary: "mutation: status=in_progress -> status=blocked",
                redactedLogCount: 1
            )
        )
    }

    func testRetentionPolicySeparatesSyncAndProHistoryStorage() {
        let syncPolicy = SoloPMHarnessRetentionPolicy.policy(for: .sync)
        XCTAssertEqual(syncPolicy.requiredFeature, .harnessHistory)
        XCTAssertEqual(syncPolicy.historyStorage, .disabled)
        XCTAssertEqual(syncPolicy.maxRuns, 0)
        XCTAssertEqual(syncPolicy.retentionDays, 0)

        let proPolicy = SoloPMHarnessRetentionPolicy.policy(for: .pro)
        XCTAssertEqual(proPolicy.historyStorage, .cloudBacked)
        XCTAssertEqual(proPolicy.maxRuns, 250)
        XCTAssertEqual(proPolicy.retentionDays, 30)

        let founderPolicy = SoloPMHarnessRetentionPolicy.policy(for: .founder)
        XCTAssertEqual(founderPolicy.historyStorage, .extendedCloudBacked)
        XCTAssertGreaterThan(founderPolicy.maxRuns, proPolicy.maxRuns)
        XCTAssertGreaterThan(founderPolicy.retentionDays, proPolicy.retentionDays)
    }
}
