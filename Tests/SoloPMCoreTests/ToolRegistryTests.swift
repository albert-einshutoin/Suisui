import XCTest
@testable import SoloPMCore

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

    func testRegistryExportsSchemas() throws {
        let registry = try ToolRegistry(tools: [
            makeTool(name: .taskCreate, permissionLevel: .writeWithApproval),
            makeTool(name: .projectList, permissionLevel: .read)
        ])

        XCTAssertEqual(registry.schemaList.map(\.name), [.projectList, .taskCreate])
        XCTAssertEqual(registry.schemaList.first?.permissionLevel, .read)
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

    private func makeTool(name: ActionTool, permissionLevel: ToolPermissionLevel) -> StaticTool {
        StaticTool(
            name: name,
            description: name.rawValue,
            inputSchema: ToolInputSchema(required: name == .taskCreate ? ["title"] : []),
            permissionLevel: permissionLevel
        ) { _, _ in
            ToolResult(tool: name, status: .succeeded, summary: "ok")
        }
    }
}
