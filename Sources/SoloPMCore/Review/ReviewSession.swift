import Foundation

public enum ApprovalState: Equatable, Sendable {
    case notRequired
    case pending
    case approved(ApprovalToken)
    case blocked(String)
}

public enum ReviewExecutionStatus: Equatable, Sendable {
    case notStarted
    case executing
    case completed
    case failed
    case canceled
}

public enum ReviewActionExecutionStatus: Equatable, Sendable {
    case pending
    case executing
    case succeeded
    case failed
    case skipped
}

public struct ReviewActionItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var originalAction: PlanAction
    public var editedAction: PlanAction
    public var isEnabled: Bool
    public var executionStatus: ReviewActionExecutionStatus
    public var result: ToolResult?
    public var errorMessage: String?

    public init(action: PlanAction, isEnabled: Bool = true) {
        self.id = action.id
        self.originalAction = action
        self.editedAction = action
        self.isEnabled = isEnabled
        self.executionStatus = .pending
        self.result = nil
        self.errorMessage = nil
    }
}

public enum ReviewSessionError: Error, Equatable, Sendable {
    case approvalBlocked(String)
    case approvalNotRequired
    case approvalRequired
    case actionNotFound(String)
}

public struct ReviewSession: Equatable, Sendable {
    public var id: String
    public var originalPlan: ActionPlan
    public var items: [ReviewActionItem]
    public var approvalState: ApprovalState
    public var executionStatus: ReviewExecutionStatus
    public var createdAt: Date

    public init(id: String = UUID().uuidString, plan: ActionPlan, createdAt: Date = Date()) {
        self.id = id
        self.originalPlan = plan
        self.items = plan.actions.map { ReviewActionItem(action: $0) }
        self.approvalState = Self.initialApprovalState(for: plan.actions)
        self.executionStatus = .notStarted
        self.createdAt = createdAt
    }

    public var enabledItems: [ReviewActionItem] {
        items.filter(\.isEnabled)
    }

    public var requiresApproval: Bool {
        items.contains { $0.isEnabled && $0.editedAction.riskLevel >= .write }
    }

    public var approvalToken: ApprovalToken? {
        guard case .approved(let token) = approvalState else {
            return nil
        }
        return token
    }

    public var canApprove: Bool {
        approvalState == .pending
    }

    public var canExecute: Bool {
        guard !enabledItems.isEmpty else {
            return false
        }

        switch approvalState {
        case .notRequired, .approved:
            return true
        case .pending, .blocked:
            return false
        }
    }

    public var editedPlan: ActionPlan {
        let actions = items.map(\.editedAction)
        return ActionPlan(
            id: originalPlan.id,
            userInput: originalPlan.userInput,
            summary: originalPlan.summary,
            actions: actions,
            riskLevel: actions.map(\.riskLevel).max() ?? .read,
            requiresApproval: actions.contains { $0.riskLevel >= .write }
        )
    }

    public mutating func setActionEnabled(id: String, _ isEnabled: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].isEnabled = isEnabled
        refreshApprovalState()
    }

    public mutating func editActionArguments(id: String, arguments: [String: JSONValue]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].editedAction.arguments = arguments
        items[index].executionStatus = .pending
        items[index].result = nil
        items[index].errorMessage = nil
        refreshApprovalState()
    }

    public mutating func updateStringArgument(id: String, key: String, value: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].editedAction.arguments[key] = .string(value)
        items[index].executionStatus = .pending
        items[index].result = nil
        items[index].errorMessage = nil
        refreshApprovalState()
    }

    public mutating func resetAction(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].editedAction = items[index].originalAction
        items[index].executionStatus = .pending
        items[index].result = nil
        items[index].errorMessage = nil
        refreshApprovalState()
    }

    public mutating func approve(token: ApprovalToken) throws {
        switch approvalState {
        case .pending:
            approvalState = .approved(token)
        case .blocked(let reason):
            throw ReviewSessionError.approvalBlocked(reason)
        case .notRequired, .approved:
            throw ReviewSessionError.approvalNotRequired
        }
    }

    public mutating func cancel() {
        executionStatus = .canceled
    }

    mutating func markAction(id: String, status: ReviewActionExecutionStatus, result: ToolResult? = nil, errorMessage: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].executionStatus = status
        items[index].result = result
        items[index].errorMessage = errorMessage
    }

    private mutating func refreshApprovalState() {
        let next = Self.initialApprovalState(for: enabledItems.map(\.editedAction))
        switch (approvalState, next) {
        case (.approved, .pending):
            return
        default:
            approvalState = next
        }
    }

    private static func initialApprovalState(for actions: [PlanAction]) -> ApprovalState {
        if actions.contains(where: { $0.riskLevel == .danger }) {
            return .blocked("Dangerous actions cannot be executed.")
        }

        if actions.contains(where: { $0.riskLevel >= .write }) {
            return .pending
        }

        return .notRequired
    }
}
