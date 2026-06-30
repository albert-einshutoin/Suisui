import XCTest
@testable import SoloPMCore

final class PlanningPromptBuilderTests: XCTestCase {
    func testPromptContainsCurrentDateTimezoneToolsAndUserInput() throws {
        let request = PlanningRequest(
            userInput: "Create a task for next Friday",
            currentDate: Date(timeIntervalSince1970: 1_783_200_000),
            timeZoneIdentifier: "Asia/Tokyo",
            availableTools: [.taskCreate, .projectCreate],
            knowledgeFrameCandidates: []
        )

        let prompt = try PlanningPromptBuilder.loadDefault().buildPrompt(for: request)

        XCTAssertTrue(prompt.user.contains("Time zone: Asia/Tokyo"))
        XCTAssertTrue(prompt.user.contains("project.create"))
        XCTAssertTrue(prompt.user.contains("task.create"))
        XCTAssertTrue(prompt.user.contains("Create a task for next Friday"))
    }

    func testPromptForbidsDangerousOperations() throws {
        let prompt = try PlanningPromptBuilder.loadDefault().buildPrompt(
            for: PlanningRequest(userInput: "Delete this file")
        )

        XCTAssertTrue(prompt.system.contains("Dangerous operations are forbidden"))
        XCTAssertTrue(prompt.system.contains("Git push"))
        XCTAssertTrue(prompt.system.contains("file delete"))
    }

    func testPromptContainsActionPlanSchemaContract() {
        let schema = """
        {
          "type": "object",
          "additionalProperties": false,
          "required": ["id", "actions"]
        }
        """

        let prompt = PlanningPromptBuilder(actionPlanSchema: schema).buildPrompt(
            for: PlanningRequest(userInput: "Create a task")
        )

        XCTAssertTrue(prompt.system.contains("ActionPlan JSON Schema"))
        XCTAssertTrue(prompt.system.contains("\"additionalProperties\": false"))
        XCTAssertTrue(prompt.system.contains("\"required\": [\"id\", \"actions\"]"))
    }

    func testDefaultPromptUsesPackagedActionPlanSchema() throws {
        let prompt = try PlanningPromptBuilder.loadDefault().buildPrompt(
            for: PlanningRequest(userInput: "Create a task")
        )

        XCTAssertTrue(prompt.system.contains("solopm.dev"))
        XCTAssertTrue(prompt.system.contains("SoloPM ActionPlan"))
        XCTAssertTrue(prompt.system.contains("\"$defs\""))
    }

    func testPromptSchemaToolEnumIsScopedToAvailableTools() throws {
        let prompt = try PlanningPromptBuilder.loadDefault().buildPrompt(
            for: PlanningRequest(
                userInput: "Create a task",
                availableTools: [.taskCreate]
            )
        )

        XCTAssertTrue(prompt.system.contains("\"task.create\""))
        XCTAssertFalse(prompt.system.contains("development.pr_workflow.commit"))
        XCTAssertFalse(prompt.system.contains("git.status"))
    }

    func testPromptSchemaIncludesDeveloperToolsOnlyWhenAvailable() throws {
        let prompt = try PlanningPromptBuilder.loadDefault().buildPrompt(
            for: PlanningRequest(
                userInput: "Commit these changes",
                availableTools: ActionTool.developerModePlanningTools
            )
        )

        XCTAssertTrue(prompt.system.contains("development.pr_workflow.commit"))
        XCTAssertTrue(prompt.system.contains("git.status"))
        XCTAssertFalse(prompt.system.contains("\"task.create\""))
    }
}
