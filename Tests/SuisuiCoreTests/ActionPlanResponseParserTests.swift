import XCTest
@testable import SuisuiCore

final class ActionPlanResponseParserTests: XCTestCase {
    func testParserReturnsValidatedPlan() {
        let rawContent = """
        {
          "id": "plan-1",
          "userInput": "Create a task",
          "summary": "Create task",
          "riskLevel": "write",
          "requiresApproval": true,
          "actions": [
            {
              "id": "action-1",
              "tool": "task.create",
              "arguments": {
                "title": "Draft outline"
              }
            }
          ]
        }
        """

        let response = ActionPlanResponseParser().parse(rawContent: rawContent, providerID: "fake")

        XCTAssertEqual(response.providerID, "fake")
        XCTAssertEqual(response.actionPlan?.summary, "Create task")
        XCTAssertTrue(response.validationResult.isValid)
    }

    func testParserReturnsBlockingResultForNonJSON() {
        let response = ActionPlanResponseParser().parse(rawContent: "not json", providerID: "fake")

        XCTAssertNil(response.actionPlan)
        XCTAssertFalse(response.validationResult.isValid)
        XCTAssertEqual(response.validationResult.issues.first?.path, "$")
    }

    func testParserRunsJSONSchemaValidationBeforeAcceptingPlan() {
        let rawContent = """
        {
          "id": "plan-1",
          "userInput": "Create a task",
          "summary": "Create task",
          "riskLevel": "write",
          "requiresApproval": true,
          "unexpected": true,
          "actions": [
            {
              "id": "action-1",
              "tool": "task.create",
              "arguments": {
                "title": "Draft outline"
              }
            }
          ]
        }
        """

        let response = ActionPlanResponseParser().parse(rawContent: rawContent, providerID: "fake")

        XCTAssertNil(response.actionPlan)
        XCTAssertFalse(response.validationResult.isValid)
        XCTAssertEqual(response.validationResult.issues.first?.path, "unexpected")
        XCTAssertEqual(response.validationResult.issues.first?.message, "Unknown property 'unexpected'.")
    }
}
