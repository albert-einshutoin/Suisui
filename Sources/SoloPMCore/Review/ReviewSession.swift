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

public enum ReviewActionFailureRecovery: String, Equatable, Sendable {
    case retryable
    case notRetryable
}

public struct ReviewActionItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var originalAction: PlanAction
    public var editedAction: PlanAction
    public var isEnabled: Bool
    public var executionStatus: ReviewActionExecutionStatus
    public var result: ToolResult?
    public var errorMessage: String?
    public var failureRecovery: ReviewActionFailureRecovery?

    public init(action: PlanAction, isEnabled: Bool = true) {
        self.id = action.id
        self.originalAction = action
        self.editedAction = action
        self.isEnabled = isEnabled
        self.executionStatus = .pending
        self.result = nil
        self.errorMessage = nil
        self.failureRecovery = nil
    }

    public func argumentDisplaySummary(maxFields: Int = 4, maxValueLength: Int = 96) -> ReviewActionArgumentSummary {
        editedAction.argumentDisplaySummary(maxFields: maxFields, maxValueLength: maxValueLength)
    }
}

public struct ReviewActionArgumentSummary: Equatable, Sendable {
    public var preview: String
    public var fullText: String
    public var isTruncated: Bool

    public init(preview: String, fullText: String, isTruncated: Bool) {
        self.preview = preview
        self.fullText = fullText
        self.isTruncated = isTruncated
    }
}

public extension PlanAction {
    func argumentDisplaySummary(maxFields: Int = 4, maxValueLength: Int = 96) -> ReviewActionArgumentSummary {
        guard !arguments.isEmpty else {
            return ReviewActionArgumentSummary(preview: "No arguments", fullText: "No arguments", isTruncated: false)
        }

        let fieldLimit = max(1, maxFields)
        let valueLimit = max(8, maxValueLength)
        let fields = arguments
            .sorted { lhs, rhs in
                let lhsRank = lhs.key.reviewDisplayPriority
                let rhsRank = rhs.key.reviewDisplayPriority
                if lhsRank == rhsRank {
                    return lhs.key < rhs.key
                }
                return lhsRank < rhsRank
            }
            .map { key, value in
                let fullValue = value.reviewDisplayValue.normalizedSingleLine
                let previewValue = fullValue.truncatedForReview(maxLength: valueLimit)
                return (
                    full: "\(key): \(fullValue)",
                    preview: "\(key): \(previewValue)",
                    truncated: fullValue != previewValue
                )
            }

        let visibleFields = fields.prefix(fieldLimit)
        let hiddenCount = fields.count - visibleFields.count
        var previewParts = visibleFields.map(\.preview)
        if hiddenCount > 0 {
            previewParts.append("+\(hiddenCount) more")
        }

        return ReviewActionArgumentSummary(
            preview: previewParts.joined(separator: ", "),
            fullText: fields.map(\.full).joined(separator: ", "),
            isTruncated: hiddenCount > 0 || fields.contains(where: \.truncated)
        )
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
        items[index].failureRecovery = nil
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
        items[index].failureRecovery = nil
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

    mutating func markAction(
        id: String,
        status: ReviewActionExecutionStatus,
        result: ToolResult? = nil,
        errorMessage: String? = nil,
        failureRecovery: ReviewActionFailureRecovery? = nil
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }

        items[index].executionStatus = status
        items[index].result = result
        items[index].errorMessage = errorMessage
        items[index].failureRecovery = failureRecovery
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

public struct ReviewPermissionGate: Equatable, Sendable {
    public var permissionSnapshot: PermissionSnapshot

    public init(permissionSnapshot: PermissionSnapshot = .empty) {
        self.permissionSnapshot = permissionSnapshot
    }

    public func validationIssues(for action: PlanAction) -> [ToolInputValidationIssue] {
        guard let permission = action.tool.requiredAppPermission else {
            return []
        }

        let status = permissionSnapshot.status(for: permission)
        guard PermissionDisplayPolicy.isActionDisabled(for: status) else {
            return []
        }

        return [
            ToolInputValidationIssue(
                actionID: action.id,
                field: "permission",
                message: "\(permission.displayName) permission is \(PermissionDisplayPolicy.label(for: status).lowercased()). Open Settings to restore access."
            )
        ]
    }
}

private extension ActionTool {
    var requiredAppPermission: AppPermission? {
        switch self.actionType {
        case .calendar:
            .calendar
        case .reminder:
            .reminders
        case .notification:
            .notifications
        case .filesystem:
            .fileAccess
        case .project, .task, .knowledgeFrame, .mailDraft, .developer:
            nil
        }
    }
}

private extension JSONValue {
    var reviewDisplayValue: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(value)
        case .bool(let value):
            value ? "true" : "false"
        case .object:
            "object"
        case .array:
            "list"
        case .null:
            "null"
        }
    }
}

private extension String {
    var reviewDisplayPriority: Int {
        switch self {
        case "title", "name", "summary":
            0
        case "projectID", "taskID", "dueAt", "scheduledAt", "priority", "status":
            1
        default:
            2
        }
    }

    var normalizedSingleLine: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func truncatedForReview(maxLength: Int) -> String {
        guard count > maxLength else {
            return self
        }

        return "\(prefix(maxLength))..."
    }
}

private extension AppPermission {
    var displayName: String {
        switch self {
        case .calendar:
            "Calendar"
        case .reminders:
            "Reminders"
        case .notifications:
            "Notifications"
        case .fileAccess:
            "File access"
        case .microphone:
            "Microphone"
        }
    }
}
