import XCTest
@testable import SuisuiCore

final class ToolRegistryTests: XCTestCase {
    func testRegistryRejectsDuplicateToolRegistration() throws {
        let tool = makeTool(name: .projectList, permissionLevel: .read)

        XCTAssertThrowsError(try ToolRegistry(tools: [tool, tool])) { error in
            XCTAssertEqual(error as? ToolExecutionError, .duplicateTool(.projectList))
        }
    }

    func testRegistryThrowsForUnknownTool() throws {
        let registry = ToolRegistry()

        XCTAssertThrowsError(try registry.tool(named: .projectList)) { error in
            XCTAssertEqual(error as? ToolExecutionError, .unknownTool(.projectList))
        }
    }

    func testRegistryValidationReportsUnavailableTool() throws {
        let registry = ToolRegistry()
        let issues = registry.validate(action: PlanAction(
            id: "task",
            tool: .taskCreate,
            arguments: ["title": .string("Draft")]
        ))

        XCTAssertEqual(issues, [
            ToolInputValidationIssue(
                actionID: "task",
                field: "tool",
                message: "Tool task.create is not available in the active registry."
            )
        ])
    }

    func testRegistryValidationRejectsFractionalIntegerFieldsBeforeExecution() throws {
        let registry = try ToolRegistry(tools: [
            makeTool(
                name: .taskUpdate,
                permissionLevel: .writeWithApproval,
                inputSchema: ToolInputSchema(required: ["id"], properties: ["id": "integer"])
            )
        ])

        let issues = registry.validate(action: PlanAction(
            id: "update",
            tool: .taskUpdate,
            arguments: ["id": .number(1.9)]
        ))

        XCTAssertEqual(issues, [
            ToolInputValidationIssue(
                actionID: "update",
                field: "id",
                message: "Argument 'id' must be integer for task.update."
            )
        ])
    }

    func testRegistryExportsSchemas() throws {
        let registry = try ToolRegistry(tools: [
            makeTool(name: .taskCreate, permissionLevel: .writeWithApproval),
            makeTool(name: .projectList, permissionLevel: .read)
        ])

        XCTAssertEqual(registry.schemaList.map(\.name), [.projectList, .taskCreate])
        XCTAssertEqual(registry.schemaList.first?.permissionLevel, .read)
    }

    func testRegistryCanRegisterToolsFromAnotherRegistry() throws {
        let target = try ToolRegistry(tools: [
            makeTool(name: .taskCreate, permissionLevel: .writeWithApproval)
        ])
        let source = try ToolRegistry(tools: [
            makeTool(name: .developmentReviewPullRequestGate, permissionLevel: .writeWithApproval),
            makeTool(name: .developmentMergePullRequest, permissionLevel: .writeWithApproval)
        ])

        try target.registerTools(from: source)

        XCTAssertTrue(target.contains(.taskCreate))
        XCTAssertTrue(target.contains(.developmentReviewPullRequestGate))
        XCTAssertTrue(target.contains(.developmentMergePullRequest))
    }

    func testRegistryRegisterToolsFromAnotherRegistryRejectsDuplicates() throws {
        let target = try ToolRegistry(tools: [
            makeTool(name: .taskCreate, permissionLevel: .writeWithApproval)
        ])
        let source = try ToolRegistry(tools: [
            makeTool(name: .taskCreate, permissionLevel: .writeWithApproval)
        ])

        XCTAssertThrowsError(try target.registerTools(from: source)) { error in
            XCTAssertEqual(error as? ToolExecutionError, .duplicateTool(.taskCreate))
        }
    }

    func testWriteToolRequiresApprovalToken() throws {
        let tool = makeTool(name: .taskCreate, permissionLevel: .writeWithApproval)

        XCTAssertThrowsError(try tool.execute(arguments: ["title": .string("Draft")], context: ToolExecutionContext(source: .developerTool))) { error in
            XCTAssertEqual(error as? ToolExecutionError, .approvalRequired(.taskCreate))
        }

        let result = try tool.execute(
            arguments: ["title": .string("Draft")],
            context: ToolExecutionContext(
                approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"),
                source: .developerTool
            )
        )

        XCTAssertEqual(result.status, .succeeded)
    }

    func testDangerousToolIsBlocked() throws {
        let tool = makeTool(name: .filesystemCreateMarkdownFile, permissionLevel: .dangerous)

        XCTAssertThrowsError(try tool.execute(
            arguments: ["path": .string("/tmp/a.md")],
            context: ToolExecutionContext(
                approvalToken: ApprovalToken(id: "approval-1", sessionID: "session-1"),
                source: .developerTool
            )
        )) { error in
            XCTAssertEqual(error as? ToolExecutionError, .dangerousToolBlocked(.filesystemCreateMarkdownFile))
        }
    }

    private func makeTool(
        name: ActionTool,
        permissionLevel: ToolPermissionLevel,
        inputSchema: ToolInputSchema? = nil
    ) -> StaticTool {
        StaticTool(
            name: name,
            description: name.rawValue,
            inputSchema: inputSchema ?? ToolInputSchema(required: name == .taskCreate ? ["title"] : []),
            permissionLevel: permissionLevel
        ) { _, _ in
            ToolResult(tool: name, status: .succeeded, summary: "ok")
        }
    }
}
