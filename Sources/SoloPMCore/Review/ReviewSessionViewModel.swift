import Combine
import Foundation

@MainActor
public final class ReviewSessionViewModel: ObservableObject {
    @Published public private(set) var session: ReviewSession
    @Published public private(set) var isExecuting: Bool
    @Published public private(set) var errorMessage: String?

    private let executor: ActionExecutor
    private let auditLogger: (any AuditLogger)?

    public init(plan: ActionPlan, executor: ActionExecutor, auditLogger: (any AuditLogger)? = nil) {
        self.session = ReviewSession(plan: plan)
        self.executor = executor
        self.auditLogger = auditLogger
        self.isExecuting = false
        self.errorMessage = nil
        try? record(action: "session.create", status: .started)
    }

    public var canApprove: Bool {
        session.canApprove && !isExecuting && session.executionStatus != .canceled
    }

    public var canExecute: Bool {
        session.canExecute && !isExecuting && session.executionStatus != .canceled
    }

    public func setActionEnabled(actionID: String, isEnabled: Bool) {
        session.setActionEnabled(id: actionID, isEnabled)
        try? record(action: isEnabled ? "action.enable" : "action.disable", status: .succeeded, actionID: actionID)
    }

    public func updateStringArgument(actionID: String, key: String, value: String) {
        session.updateStringArgument(id: actionID, key: key, value: value)
        try? record(action: "action.edit", status: .succeeded, actionID: actionID)
    }

    public func resetAction(actionID: String) {
        session.resetAction(id: actionID)
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
        try? record(action: "session.cancel", status: .skipped)
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
