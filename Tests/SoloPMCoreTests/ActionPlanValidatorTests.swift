import XCTest
@testable import SoloPMCore

final class ActionPlanValidatorTests: XCTestCase {
    func testWriteActionRequiresApproval() {
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

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.path == "requiresApproval" })
    }

    func testDangerActionIsRejected() {
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

        XCTAssertFalse(result.isValid)
        XCTAssertTrue(result.issues.contains { $0.message.contains("Dangerous") })
    }

    func testAmbiguousActionRequiresUserConfirmationWarning() {
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

        XCTAssertTrue(result.isValid)
        XCTAssertTrue(result.requiresUserConfirmation)
    }

    func testInvalidJSONIsBlocking() {
        let result = ActionPlanValidator().validate(jsonData: Data("{".utf8))

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.issues.first?.path, "$")
    }
}

