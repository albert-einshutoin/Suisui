import Foundation

public enum ConversationTaskOperation: String, CaseIterable, Codable, Equatable, Sendable {
    case list
    case create
    case updateStatus
    case complete
    case moveProject
    case updateDueDate
}

public struct ConversationTaskIntent: Codable, Equatable, Sendable {
    public var utterance: String
    public var operation: ConversationTaskOperation
    public var tool: ActionTool
    public var arguments: [String: JSONValue]
    public var summary: String
    public var riskLevel: RiskLevel

    public init(
        utterance: String,
        operation: ConversationTaskOperation,
        tool: ActionTool,
        arguments: [String: JSONValue],
        summary: String,
        riskLevel: RiskLevel? = nil
    ) {
        self.utterance = utterance
        self.operation = operation
        self.tool = tool
        self.arguments = arguments
        self.summary = summary
        self.riskLevel = riskLevel ?? tool.defaultRiskLevel
    }

    public func actionPlan(id: String, actionID: String) -> ActionPlan {
        ActionPlan(
            id: id,
            userInput: utterance,
            summary: summary,
            actions: [
                PlanAction(
                    id: actionID,
                    tool: tool,
                    arguments: arguments,
                    riskLevel: riskLevel
                )
            ],
            riskLevel: riskLevel,
            requiresApproval: riskLevel >= .write
        )
    }
}

public extension ConversationTaskIntent {
    static let phase13Fixtures: [ConversationTaskIntent] = [
        ConversationTaskIntent(
            utterance: "タスクを列挙して",
            operation: .list,
            tool: .taskList,
            arguments: [:],
            summary: "List current tasks"
        ),
        ConversationTaskIntent(
            utterance: "リリースメモのタスクを作成して",
            operation: .create,
            tool: .taskCreate,
            arguments: [
                "title": .string("リリースメモを作成"),
                "sourceCommand": .string("リリースメモのタスクを作成して")
            ],
            summary: "Create a release notes task"
        ),
        ConversationTaskIntent(
            utterance: "これを進行中にして",
            operation: .updateStatus,
            tool: .taskUpdate,
            arguments: [
                "id": .number(101),
                "status": .string("in_progress")
            ],
            summary: "Move task to in progress"
        ),
        ConversationTaskIntent(
            utterance: "このタスクを完了にして",
            operation: .complete,
            tool: .taskComplete,
            arguments: [
                "id": .number(101)
            ],
            summary: "Complete task"
        ),
        ConversationTaskIntent(
            utterance: "このタスクをLaunchプロジェクトに入れて",
            operation: .moveProject,
            tool: .taskUpdate,
            arguments: [
                "id": .number(101),
                "projectId": .number(42)
            ],
            summary: "Move task into a project"
        ),
        ConversationTaskIntent(
            utterance: "明日までにして",
            operation: .updateDueDate,
            tool: .taskUpdate,
            arguments: [
                "id": .number(101),
                "dueAt": .string("2026-06-22")
            ],
            summary: "Set task due date"
        )
    ]
}
