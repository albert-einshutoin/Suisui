import Combine
import Foundation

@MainActor
public final class ReviewSessionViewModel: ObservableObject {
    @Published public private(set) var session: ReviewSession
    @Published public private(set) var isExecuting: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var validationIssuesByActionID: [String: [ToolInputValidationIssue]]

    private let executor: ActionExecutor
    private let auditLogger: (any AuditLogger)?
    private let permissionGate: ReviewPermissionGate

    public init(
        plan: ActionPlan,
        executor: ActionExecutor,
        auditLogger: (any AuditLogger)? = nil,
        permissionGate: ReviewPermissionGate = ReviewPermissionGate()
    ) {
        self.session = ReviewSession(plan: plan)
        self.executor = executor
        self.auditLogger = auditLogger
        self.permissionGate = permissionGate
        self.isExecuting = false
        self.errorMessage = nil
        self.validationIssuesByActionID = [:]
        refreshValidationIssues()
        try? record(action: "session.create", status: .started)
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
        try? record(action: isEnabled ? "action.enable" : "action.disable", status: .succeeded, actionID: actionID)
    }

    public func updateStringArgument(actionID: String, key: String, value: String) {
        session.updateStringArgument(id: actionID, key: key, value: value)
        refreshValidationIssues()
        try? record(action: "action.edit", status: .succeeded, actionID: actionID)
    }

    public func resetAction(actionID: String) {
        session.resetAction(id: actionID)
        refreshValidationIssues()
        try? record(action: "action.reset", status: .succeeded, actionID: actionID)
    }

    public func approve() throws {
        guard canApprove else {
            throw ReviewSessionError.approvalNotRequired
        }

        let token = ApprovalToken(id: UUID().uuidString, sessionID: session.id)
        try session.approve(token: token)
        try record(action: "session.approve", status: .succeeded)
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
            session = try executor.execute(session)
        } catch {
            errorMessage = String(describing: error)
            try? record(action: "session.execute", status: .failed)
            throw error
        }
    }

    public func cancel() {
        session.cancel()
        refreshValidationIssues()
        try? record(action: "session.cancel", status: .skipped)
    }

    private func refreshValidationIssues() {
        let permissionIssues = session.enabledItems.flatMap { permissionGate.validationIssues(for: $0.editedAction) }
        validationIssuesByActionID = Dictionary(
            grouping: executor.validationIssues(for: session) + permissionIssues,
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
}
