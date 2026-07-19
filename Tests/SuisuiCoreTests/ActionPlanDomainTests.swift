import XCTest
@testable import SuisuiCore

final class ActionPlanDomainTests: XCTestCase {
    func testActionToolMapsToActionType() {
        XCTAssertEqual(ActionTool.projectCreate.actionType, .project)
        XCTAssertEqual(ActionTool.projectDelete.actionType, .project)
        XCTAssertEqual(ActionTool.taskCreate.actionType, .task)
        XCTAssertEqual(ActionTool.taskDelete.actionType, .task)
        XCTAssertEqual(ActionTool.calendarCreateEvent.actionType, .calendar)
        XCTAssertEqual(ActionTool.frameDelete.actionType, .knowledgeFrame)
        XCTAssertEqual(ActionTool.mailDraftCreateText.actionType, .mailDraft)
        XCTAssertEqual(ActionTool.gitStatus.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentPreparePullRequestWorkflow.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentCommitChanges.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentPushBranch.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentCreatePullRequest.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentReviewPullRequestGate.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentMergePullRequest.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentRepositoryListFiles.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentRepositoryReadFile.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentRepositoryCreateFile.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentRepositoryUpdateFile.actionType, .developer)
        XCTAssertEqual(ActionTool.developmentRunVerification.actionType, .developer)
    }

    func testLocalReadAndDeleteToolsUseExpectedRiskLevels() {
        XCTAssertEqual(ActionTool.taskGet.defaultRiskLevel, .read)
        XCTAssertEqual(ActionTool.projectDelete.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.taskDelete.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.frameDelete.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentPreparePullRequestWorkflow.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentCommitChanges.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentPushBranch.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentCreatePullRequest.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentReviewPullRequestGate.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentMergePullRequest.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentRepositoryListFiles.defaultRiskLevel, .read)
        XCTAssertEqual(ActionTool.developmentRepositoryReadFile.defaultRiskLevel, .read)
        XCTAssertEqual(ActionTool.developmentRepositoryCreateFile.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentRepositoryUpdateFile.defaultRiskLevel, .write)
        XCTAssertEqual(ActionTool.developmentRunVerification.defaultRiskLevel, .write)
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
