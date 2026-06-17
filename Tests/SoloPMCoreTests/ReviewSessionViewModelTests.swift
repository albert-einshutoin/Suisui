import XCTest
@testable import SoloPMCore

@MainActor
final class ReviewSessionViewModelTests: XCTestCase {
    func testApproveEditAndExecuteSession() throws {
        let logger = InMemoryAuditLogger()
        let registry = try ToolRegistry(tools: [
            StaticTool(name: .taskCreate, description: "create", inputSchema: ToolInputSchema(required: ["title"]), permissionLevel: .writeWithApproval) { _, context in
                XCTAssertNotNil(context.approvalToken)
                return ToolResult(tool: .taskCreate, status: .succeeded, summary: "created", rollbackMetadata: ["taskId": .number(1)])
            }
        ])
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "task", tool: .taskCreate, arguments: ["title": .string("Draft")])
            ]),
            executor: ActionExecutor(registry: registry, auditLogger: logger),
            auditLogger: logger
        )

        viewModel.updateStringArgument(actionID: "task", key: "title", value: "Review")
        try viewModel.approve()
        try viewModel.execute()

        XCTAssertEqual(viewModel.session.items.first?.editedAction.arguments["title"], .string("Review"))
        XCTAssertEqual(viewModel.session.executionStatus, .completed)
        XCTAssertEqual(viewModel.session.items.first?.result?.rollbackMetadata["taskId"], .number(1))
        XCTAssertTrue(logger.recordedEvents.contains { $0.action == "session.approve" })
    }

    func testCancelSessionRecordsAuditEventAndDisablesExecution() throws {
        let logger = InMemoryAuditLogger()
        let registry = try ToolRegistry()
        let viewModel = ReviewSessionViewModel(
            plan: ActionPlan.reviewViewModelFixture(actions: [
                PlanAction(id: "read", tool: .projectList)
            ]),
            executor: ActionExecutor(registry: registry),
            auditLogger: logger
        )

        viewModel.cancel()

        XCTAssertEqual(viewModel.session.executionStatus, .canceled)
        XCTAssertFalse(viewModel.canExecute)
        XCTAssertTrue(logger.recordedEvents.contains { $0.action == "session.cancel" })
    }
}

private extension ActionPlan {
    static func reviewViewModelFixture(actions: [PlanAction]) -> ActionPlan {
        ActionPlan(
            id: "plan-review-vm",
            userInput: "Review fixture",
            summary: "Review fixture",
            actions: actions,
            riskLevel: actions.map(\.riskLevel).max() ?? .read,
            requiresApproval: actions.contains { $0.riskLevel >= .write }
        )
    }
}
