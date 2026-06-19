import Combine
import Foundation

@MainActor
public final class ReviewSessionViewModel: ObservableObject {
    @Published public private(set) var session: ReviewSession
    @Published public private(set) var isExecuting: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var auditErrorMessage: String?
    @Published public private(set) var validationIssuesByActionID: [String: [ToolInputValidationIssue]]

    private let executor: ActionExecutor
    private let auditLogger: (any AuditLogger)?
    private let permissionGate: ReviewPermissionGate
    private let runtimeValidationMessage: String?

    public init(
        plan: ActionPlan,
        executor: ActionExecutor,
        auditLogger: (any AuditLogger)? = nil,
        permissionGate: ReviewPermissionGate = ReviewPermissionGate(),
        runtimeValidationMessage: String? = nil
    ) {
        self.session = ReviewSession(plan: plan)
        self.executor = executor
        self.auditLogger = auditLogger
        self.permissionGate = permissionGate
        self.runtimeValidationMessage = runtimeValidationMessage
        self.isExecuting = false
        self.errorMessage = runtimeValidationMessage
        self.auditErrorMessage = nil
        self.validationIssuesByActionID = [:]
        refreshValidationIssues()
        recordAudit(action: "session.create", status: .started)
    }

    public var canApprove: Bool {
        session.canApprove && !isExecuting && session.executionStatus != .canceled
    }

    public var canExecute: Bool {
        session.canExecute && validationIssuesByActionID.isEmpty && !isExecuting && session.executionStatus != .canceled
    }

    public func validationIssues(for actionID: String) -> [ToolInputValidationIssue] {
        validationIssuesByActionID[actionID] ?? []
    }

    public func setActionEnabled(actionID: String, isEnabled: Bool) {
        session.setActionEnabled(id: actionID, isEnabled)
        refreshValidationIssues()
        recordAudit(action: isEnabled ? "action.enable" : "action.disable", status: .succeeded, actionID: actionID)
    }

    public func updateStringArgument(actionID: String, key: String, value: String) {
        session.updateStringArgument(id: actionID, key: key, value: value)
        refreshValidationIssues()
        recordAudit(action: "action.edit", status: .succeeded, actionID: actionID)
    }

    public func resetAction(actionID: String) {
        session.resetAction(id: actionID)
        refreshValidationIssues()
        recordAudit(action: "action.reset", status: .succeeded, actionID: actionID)
    }

    public func approve() throws {
        guard canApprove else {
            throw ReviewSessionError.approvalNotRequired
        }

        let token = ApprovalToken(id: UUID().uuidString, sessionID: session.id)
        try session.approve(token: token)
        recordAudit(action: "session.approve", status: .succeeded)
    }

    @discardableResult
    public func approveOrReportError() -> Bool {
        do {
            try approve()
            return true
        } catch {
            errorMessage = Self.userFacingErrorMessage(for: error)
            return false
        }
    }

    public func execute() throws {
        guard canExecute else {
            if !validationIssuesByActionID.isEmpty {
                throw ActionExecutorError.validationFailed(validationIssuesByActionID.values.flatMap { $0 })
            }
            throw ReviewSessionError.approvalRequired
        }

        isExecuting = true
        errorMessage = nil
        defer { isExecuting = false }

        do {
            let executedSession = try executor.execute(session)
            session = executedSession
            if let auditErrorMessage = executedSession.auditErrorMessage {
                self.auditErrorMessage = auditErrorMessage
            }
        } catch {
            errorMessage = Self.userFacingErrorMessage(for: error)
            recordAudit(action: "session.execute", status: .failed)
            throw error
        }
    }

    @discardableResult
    public func executeOrReportError() -> Bool {
        do {
            try execute()
            return true
        } catch {
            errorMessage = Self.userFacingErrorMessage(for: error)
            return false
        }
    }

    public func cancel() {
        session.cancel()
        refreshValidationIssues()
        recordAudit(action: "session.cancel", status: .skipped)
    }

    private func refreshValidationIssues() {
        let permissionIssues = session.enabledItems.flatMap { permissionGate.validationIssues(for: $0.editedAction) }
        let runtimeIssues = session.enabledItems.compactMap { item -> ToolInputValidationIssue? in
            guard let runtimeValidationMessage else {
                return nil
            }
            return ToolInputValidationIssue(
                actionID: item.id,
                field: "runtime",
                message: runtimeValidationMessage
            )
        }
        validationIssuesByActionID = Dictionary(
            grouping: executor.validationIssues(for: session) + permissionIssues + runtimeIssues,
            by: { $0.actionID ?? "" }
        ).filter { !$0.key.isEmpty }
    }

    private func record(action: String, status: AuditStatus, actionID: String? = nil) throws {
        var metadata = [
            "session_id": session.id,
            "plan_id": session.originalPlan.id,
            "execution_status": String(describing: session.executionStatus)
        ]
        if let actionID {
            metadata["action_id"] = actionID
        }

        try auditLogger?.record(AuditEvent(category: "review", action: action, status: status, metadata: metadata))
    }

    private func recordAudit(action: String, status: AuditStatus, actionID: String? = nil) {
        do {
            try record(action: action, status: status, actionID: actionID)
        } catch {
            auditErrorMessage = "Review audit log could not be saved."
        }
    }

    private static func userFacingErrorMessage(for error: Error) -> String {
        switch error {
        case ReviewSessionError.approvalNotRequired:
            return "This action plan does not require approval."
        case ReviewSessionError.approvalRequired, ActionExecutorError.approvalRequired:
            return "Approve this action plan before executing it."
        case ReviewSessionError.approvalBlocked(let reason), ActionExecutorError.approvalBlocked(let reason):
            return "Approval is blocked: \(reason)"
        case ReviewSessionError.actionNotFound:
            return "The selected action is no longer available."
        case ActionExecutorError.noEnabledActions:
            return "Enable at least one action before executing it."
        case ActionExecutorError.validationFailed:
            return "Fix the highlighted action issues before executing."
        default:
            return "Review execution could not be completed."
        }
    }
}
