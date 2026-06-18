import XCTest
@testable import SoloPMCore

final class ActionPlanDomainTests: XCTestCase {
    func testActionToolMapsToActionType() {
        XCTAssertEqual(ActionTool.projectCreate.actionType, .project)
        XCTAssertEqual(ActionTool.taskCreate.actionType, .task)
        XCTAssertEqual(ActionTool.taskDelete.actionType, .task)
        XCTAssertEqual(ActionTool.calendarCreateEvent.actionType, .calendar)
        XCTAssertEqual(ActionTool.frameDelete.actionType, .knowledgeFrame)
        XCTAssertEqual(ActionTool.mailDraftCreateText.actionType, .mailDraft)
        XCTAssertEqual(ActionTool.gitStatus.actionType, .developer)
    }

    func testLocalReadAndDeleteToolsUseExpectedRiskLevels() {
        XCTAssertEqual(ActionTool.taskGet.defaultRiskLevel, .read)
        XCTAssertEqual(ActionTool.taskDelete.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.frameDelete.defaultRiskLevel, .write)
    }

    func testApprovalRequirementUsesHighestActionRisk() {
        let plan = ActionPlan(
            id: "plan-1",
            userInput: "Create project and task",
            summary: "Create work",
            actions: [
                PlanAction(id: "action-1", tool: .projectList),
                PlanAction(id: "action-2", tool: .taskCreate)
            ],
            riskLevel: .write,
            requiresApproval: true
        )

        XCTAssertEqual(plan.approvalRequirement, .explicitApproval)
    }

    func testDateExpressionSeparatesRawAndResolvedDate() {
        let date = Date(timeIntervalSince1970: 1_783_200_000)
        let expression = DateExpression(rawValue: "next Friday", resolvedDate: date, timeZoneIdentifier: "Asia/Tokyo")

        XCTAssertEqual(expression.rawValue, "next Friday")
        XCTAssertEqual(expression.resolvedDate, date)
        XCTAssertEqual(expression.timeZoneIdentifier, "Asia/Tokyo")
    }
}
