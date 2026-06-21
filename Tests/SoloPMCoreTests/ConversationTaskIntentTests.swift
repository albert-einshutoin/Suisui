import XCTest
@testable import SoloPMCore

final class ConversationTaskIntentTests: XCTestCase {
    func testPhase13FixturesCoverConversationTaskOperations() {
        let fixtures = ConversationTaskIntent.phase13Fixtures

        XCTAssertEqual(Set(fixtures.map(\.operation)), Set(ConversationTaskOperation.allCases))
        XCTAssertTrue(fixtures.contains { $0.utterance == "タスクを列挙して" })
        XCTAssertTrue(fixtures.contains { $0.utterance == "これを進行中にして" })
        XCTAssertTrue(fixtures.contains { $0.utterance == "明日までにして" })
    }

    func testFixturesBuildProviderIndependentActionPlansThatPassValidation() {
        for fixture in ConversationTaskIntent.phase13Fixtures {
            let plan = fixture.actionPlan(id: "plan-\(fixture.operation.rawValue)", actionID: "action-1")
            let result = ActionPlanValidator().validate(plan)

            XCTAssertTrue(result.isValid, "Expected \(fixture.operation) fixture to be valid: \(result.issues)")
            XCTAssertEqual(plan.actions.first?.tool, fixture.tool)
            XCTAssertEqual(plan.requiresApproval, fixture.riskLevel >= .write)
            XCTAssertEqual(plan.riskLevel, fixture.riskLevel)
            if fixture.riskLevel == .read {
                XCTAssertEqual(plan.approvalRequirement, .none)
            } else {
                XCTAssertEqual(plan.approvalRequirement, .explicitApproval)
            }
        }
    }

    func testStatusMoveProjectAndDueDateFixturesUseTaskUpdateArguments() throws {
        let fixtures = Dictionary(uniqueKeysWithValues: ConversationTaskIntent.phase13Fixtures.map { ($0.operation, $0) })

        let status = try XCTUnwrap(fixtures[.updateStatus])
        XCTAssertEqual(status.tool, .taskUpdate)
        XCTAssertEqual(status.arguments["id"], .number(101))
        XCTAssertEqual(status.arguments["status"], .string("in_progress"))

        let move = try XCTUnwrap(fixtures[.moveProject])
        XCTAssertEqual(move.tool, .taskUpdate)
        XCTAssertEqual(move.arguments["id"], .number(101))
        XCTAssertEqual(move.arguments["projectId"], .number(42))

        let dueDate = try XCTUnwrap(fixtures[.updateDueDate])
        XCTAssertEqual(dueDate.tool, .taskUpdate)
        XCTAssertEqual(dueDate.arguments["id"], .number(101))
        XCTAssertEqual(dueDate.arguments["dueAt"], .string("2026-06-22"))
    }

    func testConversationTaskListAndStatusUpdateExecutionWritesAuditLog() throws {
        let logger = InMemoryAuditLogger()
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskList, description: "list", inputSchema: ToolInputSchema(), permissionLevel: .read) { _, _ in
                ToolResult(tool: .taskList, status: .succeeded, summary: "1 task")
            },
            StaticTool(
                name: .taskUpdate,
                description: "update",
                inputSchema: ToolInputSchema(required: ["id"], properties: ["id": "integer", "status": "string"]),
                permissionLevel: .writeWithApproval
            ) { _, _ in
                ToolResult(tool: .taskUpdate, status: .succeeded, summary: "Updated task")
            }
        ])
        let fixtures = Dictionary(uniqueKeysWithValues: ConversationTaskIntent.phase13Fixtures.map { ($0.operation, $0) })
        let listIntent = try XCTUnwrap(fixtures[.list])
        let statusIntent = try XCTUnwrap(fixtures[.updateStatus])
        let plan = ActionPlan(
            id: "conversation-task-plan",
            userInput: "\(listIntent.utterance)\n\(statusIntent.utterance)",
            summary: "List tasks and update status",
            actions: [
                PlanAction(id: "list", tool: listIntent.tool, arguments: listIntent.arguments),
                PlanAction(id: "status", tool: statusIntent.tool, arguments: statusIntent.arguments)
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        var session = ReviewSession(plan: plan)
        try session.approve(token: ApprovalToken(id: "approval-1", sessionID: session.id))

        _ = try ActionExecutor(registry: registry, auditLogger: logger).execute(session)

        XCTAssertTrue(logger.recordedEvents.contains {
            $0.category == "tool" && $0.action == "task.list" && $0.status == .succeeded && $0.metadata["action_id"] == "list"
        })
        XCTAssertTrue(logger.recordedEvents.contains {
            $0.category == "tool" && $0.action == "task.update" && $0.status == .succeeded && $0.metadata["action_id"] == "status"
        })
    }
}
