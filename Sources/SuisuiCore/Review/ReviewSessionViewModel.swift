import Combine
import Foundation

@MainActor
public final class ReviewSessionViewModel: ObservableObject {
    @Published public private(set) var session: ReviewSession
    @Published public private(set) var isExecuting: Bool
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var auditErrorMessage: String?
    @Published public private(set) var executionReceiptErrorMessage: String?
    @Published public private(set) var executionReceipts: [ExecutionReceipt]
    @Published public private(set) var validationIssuesByActionID: [String: [ToolInputValidationIssue]]

    private let executor: ActionExecutor
    private let auditLogger: (any AuditLogger)?
    private let executionReceiptStore: (any ExecutionReceiptStore)?
    private let permissionGate: ReviewPermissionGate
    private let runtimeValidationMessage: String?

    public init(
        plan: ActionPlan,
        executor: ActionExecutor,
        auditLogger: (any AuditLogger)? = nil,
        executionReceiptStore: (any ExecutionReceiptStore)? = nil,
        permissionGate: ReviewPermissionGate = ReviewPermissionGate(),
        runtimeValidationMessage: String? = nil
    ) {
        self.session = ReviewSession(plan: plan)
        self.executor = executor
        self.auditLogger = auditLogger
        self.executionReceiptStore = executionReceiptStore
        self.permissionGate = permissionGate
        self.runtimeValidationMessage = runtimeValidationMessage
        self.isExecuting = false
        self.errorMessage = runtimeValidationMessage
        self.auditErrorMessage = nil
        self.executionReceiptErrorMessage = nil
        self.executionReceipts = (try? executionReceiptStore?.list(limit: 100)) ?? []
        self.validationIssuesByActionID = [:]
        refreshValidationIssues()
        recordAudit(action: "session.create", status: .started)
    }

    public var lastExecutionReceipt: ExecutionReceipt? {
        executionReceipts.first
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

        try session.approve()
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
        let startedAt = Date()
        defer { isExecuting = false }

        do {
            let executedSession = try executor.execute(session)
            session = executedSession
            if let auditErrorMessage = executedSession.auditErrorMessage {
                self.auditErrorMessage = auditErrorMessage
            }
            recordExecutionReceipt(for: executedSession, startedAt: startedAt, finishedAt: Date())
            session.requestFreshApproval()
        } catch {
            errorMessage = Self.userFacingErrorMessage(for: error)
            recordAudit(action: "session.execute", status: .failed)
            var failedSession = session
            failedSession.executionStatus = .failed
            recordExecutionReceipt(for: failedSession, startedAt: startedAt, finishedAt: Date())
            // Preflight rejection and unknown execution failures can both leave
            // the sealed approval unusable. Require an explicit fresh approval
            // instead of trapping the user behind the consumed/expired nonce.
            session.requestFreshApproval()
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
        let now = Date()
        recordExecutionReceipt(for: session, startedAt: nil, finishedAt: now)
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

    private func recordReceiptAudit(receipt: ExecutionReceipt, status: AuditStatus) {
        do {
            try auditLogger?.record(AuditEvent(
                category: "receipt",
                action: "execution.receipt.create",
                status: status,
                metadata: [
                    "receipt_id": receipt.id,
                    "run_id": receipt.runID,
                    "receipt_status": receipt.status.rawValue,
                    "session_id": session.id,
                    "plan_id": session.originalPlan.id
                ]
            ))
        } catch {
            auditErrorMessage = "Review audit log could not be saved."
        }
    }

    private func recordExecutionReceipt(
        for session: ReviewSession,
        startedAt: Date?,
        finishedAt: Date?
    ) {
        let receipt = ExecutionReceiptFactory.makeReviewReceipt(
            session: session,
            runID: "review-run:\(session.id):\(UUID().uuidString)",
            model: nil,
            usage: .unknown,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
        do {
            try executionReceiptStore?.save(receipt)
            executionReceipts = (try executionReceiptStore?.list(limit: 100)) ?? [receipt] + executionReceipts
            recordReceiptAudit(receipt: receipt, status: .succeeded)
        } catch {
            executionReceiptErrorMessage = "Execution receipt could not be saved."
            executionReceipts = [receipt] + executionReceipts
            recordReceiptAudit(receipt: receipt, status: .failed)
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
        case ActionExecutorError.invalidApproval:
            return "This approval is no longer valid. Review and approve the plan again."
        case ActionExecutorError.approvalReplayDetected:
            return "This approval was already used. Review and approve the plan again."
        case ActionExecutorError.dependencyResolutionFailed,
             ActionExecutorError.invalidActionGraph:
            return "The approved action dependencies are invalid. Review the plan again."
        default:
            return "Review execution could not be completed."
        }
    }
}
