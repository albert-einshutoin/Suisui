import Foundation

/// Pure eligibility gate for opt-in auto-creation of a single low-risk task
/// from a validated voice plan. This implements the documented pricing/product
/// boundary: low-risk `task.create` may auto-create when the user opted in;
/// destructive or external writes always stay pending until approval.
public enum LowRiskAutoCreationPolicy {
    /// A plan qualifies only when automation is enabled in autoCreateLowRisk
    /// mode, validation passed, and the plan is exactly one taskCreate
    /// action with no user-confirmation requirement and risk at most write.
    public static func qualifies(
        plan: ActionPlan,
        validation: ActionPlanValidationResult,
        settings: TaskAutoExecutionSettings
    ) -> Bool {
        guard settings.isEnabled, settings.mode == .autoCreateLowRisk else {
            return false
        }
        guard validation.isValid else {
            return false
        }
        guard plan.actions.count == 1, let action = plan.actions.first else {
            return false
        }
        return action.tool == .taskCreate
            && action.riskLevel <= .write
            && !action.requiresUserConfirmation
            && plan.riskLevel <= .write
    }
}

/// Result of running a qualifying plan through the review execution pipeline
/// without a manual approval click. `taskID` is nil when the tool result did
/// not expose a created-task identifier; undo is only offered when it exists.
public struct LowRiskAutoCreationOutcome: Equatable, Sendable {
    public var taskID: Int64?
    public var taskTitle: String
    public var summaryMessage: String

    public init(taskID: Int64?, taskTitle: String, summaryMessage: String) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.summaryMessage = summaryMessage
    }
}

/// Published record of an auto-created task so the voice window can show a
/// "Task created" banner with a post-hoc undo affordance.
public struct AutoCreatedTaskRecord: Equatable, Sendable {
    public var taskID: Int64
    public var title: String

    public init(taskID: Int64, title: String) {
        self.taskID = taskID
        self.title = title
    }
}

public enum LowRiskAutoCreationError: Error, Equatable, Sendable {
    case executionFailed(String)
}
