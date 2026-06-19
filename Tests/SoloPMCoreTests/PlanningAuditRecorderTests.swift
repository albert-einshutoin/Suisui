import XCTest
@testable import SoloPMCore

final class PlanningAuditRecorderTests: XCTestCase {
    func testPlanningAuditRecordsStartedAndCompletedEvents() throws {
        let logger = InMemoryAuditLogger()
        let recorder = PlanningAuditRecorder(logger: RedactingAuditLogger(base: logger))
        let response = PlanningResponse(
            providerID: "fake",
            rawContent: "{}",
            actionPlan: ActionPlan(
                id: "plan-1",
                userInput: "Create a task",
                summary: "Create task",
                actions: [PlanAction(id: "action-1", tool: .taskCreate)],
                riskLevel: .write,
                requiresApproval: true
            ),
            validationResult: ActionPlanValidationResult(issues: [])
        )

        try recorder.recordStarted(input: "Create a task with sk-secret", providerID: "fake")
        try recorder.recordCompleted(response: response)

        XCTAssertEqual(logger.recordedEvents.map(\.status), [.started, .succeeded])
        XCTAssertEqual(logger.recordedEvents.first?.metadata["provider"], "fake")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["plan_id"], "plan-1")
        XCTAssertEqual(logger.recordedEvents.first?.metadata["input_summary"], "[REDACTED]")
    }

    func testPlanningAuditRecorderRedactsFailureErrorBeforeLoggerBoundary() throws {
        let logger = InMemoryAuditLogger()
        let recorder = PlanningAuditRecorder(logger: logger)
        let secret = "sk-" + "planningAuditSecret123"

        try recorder.recordFailed(
            input: "Create a task",
            providerID: "openai",
            error: PlanningAuditSecretError(message: "provider failed token=\(secret)&request_id=planning-audit-1")
        )

        XCTAssertEqual(
            logger.recordedEvents.first?.metadata["error"],
            "provider failed token=[REDACTED_SECRET]&request_id=planning-audit-1"
        )
        XCTAssertFalse(logger.recordedEvents.first?.metadata["error"]?.contains(secret) ?? true)
    }
}

private struct PlanningAuditSecretError: Error, CustomStringConvertible {
    var message: String

    var description: String {
        message
    }
}
