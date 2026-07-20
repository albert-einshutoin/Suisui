import XCTest
@testable import SuisuiCore

final class ActionPlanJSONSchemaValidatorTests: XCTestCase {
    func testValidFixturePassesSchemaValidation() throws {
        let issues = ActionPlanJSONSchemaValidator().validate(jsonData: try fixtureData(named: "valid-write"))

        XCTAssertTrue(issues.isEmpty)
    }

    func testSchemaRejectsUnknownRootProperty() {
        let data = Data(
            """
            {
              "id": "plan-1",
              "userInput": "Create a task",
              "summary": "Create task",
              "riskLevel": "write",
              "requiresApproval": true,
              "actions": [
                {
                  "id": "action-1",
                  "tool": "task.create"
                }
              ],
              "extra": true
            }
            """.utf8
        )

        let issues = ActionPlanJSONSchemaValidator().validate(jsonData: data)

        XCTAssertTrue(issues.contains { $0.path == "extra" })
    }

    func testSchemaRejectsEmptyActions() throws {
        let result = ActionPlanValidator().validate(jsonData: try fixtureData(named: "empty-actions"))

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.path == "actions" })
    }

    private func fixtureData(named name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/ActionPlans")
                ?? Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "ActionPlans")
                ?? Bundle.module.url(forResource: name, withExtension: "json")
        )

        return try Data(contentsOf: url)
    }
}
