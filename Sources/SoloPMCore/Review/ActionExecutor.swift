import Foundation

public enum ActionExecutorFailurePolicy: Equatable, Sendable {
    case stopOnFailure
    case continueOnFailure
}

public enum ActionExecutorError: Error, Equatable, Sendable {
    case approvalRequired
    case approvalBlocked(String)
    case noEnabledActions
    case validationFailed([ToolInputValidationIssue])
}

public struct ActionExecutor: Sendable {
    private let registry: ToolRegistry
    private let auditLogger: (any AuditLogger)?

    public init(registry: ToolRegistry, auditLogger: (any AuditLogger)? = nil) {
        self.registry = registry
        self.auditLogger = auditLogger
    }

    public func validationIssues(for session: ReviewSession) -> [ToolInputValidationIssue] {
        session.enabledItems.flatMap { registry.validate(action: $0.editedAction) }
    }

    public func execute(
        _ session: ReviewSession,
        failurePolicy: ActionExecutorFailurePolicy = .stopOnFailure,
        now: Date = Date()
    ) throws -> ReviewSession {
        try preflight(session)

        var working = session
        working.executionStatus = .executing
        try recordReviewEvent(action: "execution.start", status: .started, session: working)

        var latestProjectID: JSONValue?
        var hasFailure = false

        for item in working.items {
            guard item.isEnabled else {
                working.markAction(id: item.id, status: .skipped)
                try recordToolEvent(tool: item.editedAction.tool, status: .skipped, actionID: item.id)
                continue
            }

            if failurePolicy == .stopOnFailure, hasFailure {
                working.markAction(id: item.id, status: .skipped)
                try recordToolEvent(tool: item.editedAction.tool, status: .skipped, actionID: item.id)
                continue
            }

            var action = item.editedAction
            injectDependencies(into: &action, latestProjectID: latestProjectID)
            working.markAction(id: item.id, status: .executing)

            do {
                let tool = try registry.tool(named: action.tool)
                let result = try tool.execute(
                    arguments: action.arguments,
                    context: ToolExecutionContext(approvalToken: working.approvalToken, now: now, source: .reviewUI)
                )
                working.markAction(id: item.id, status: .succeeded, result: result)
                try recordToolEvent(tool: action.tool, status: .succeeded, actionID: item.id, result: result)

                if action.tool == .projectCreate, let projectID = result.output["projectId"] {
                    latestProjectID = projectID
                }
            } catch {
                hasFailure = true
                working.markAction(
                    id: item.id,
                    status: .failed,
                    errorMessage: String(describing: error),
                    failureRecovery: Self.failureRecovery(for: error)
                )
                try recordToolEvent(tool: action.tool, status: .failed, actionID: item.id, error: error)
            }
        }

        working.executionStatus = hasFailure ? .failed : .completed
        try recordReviewEvent(action: "execution.complete", status: hasFailure ? .failed : .succeeded, session: working)
        return working
    }

    private func preflight(_ session: ReviewSession) throws {
        guard !session.enabledItems.isEmpty else {
            throw ActionExecutorError.noEnabledActions
        }

        let validationIssues = validationIssues(for: session)
        guard validationIssues.isEmpty else {
            throw ActionExecutorError.validationFailed(validationIssues)
        }

        switch session.approvalState {
        case .blocked(let reason):
            throw ActionExecutorError.approvalBlocked(reason)
        case .pending:
            throw ActionExecutorError.approvalRequired
        case .approved, .notRequired:
            return
        }
    }

    private func injectDependencies(into action: inout PlanAction, latestProjectID: JSONValue?) {
        guard let latestProjectID else {
            return
        }

        switch action.tool {
        case .taskCreate:
            if action.arguments["projectId"] == nil {
                action.arguments["projectId"] = latestProjectID
            }
        case .taskBulkCreate:
            guard case .array(let values)? = action.arguments["tasks"] else {
                return
            }
            action.arguments["tasks"] = .array(values.map { value in
                guard case .object(var object) = value else {
                    return value
                }
                if object["projectId"] == nil {
                    object["projectId"] = latestProjectID
                }
                return .object(object)
            })
        default:
            return
        }
    }

    private static func failureRecovery(for error: Error) -> ReviewActionFailureRecovery {
        if let executionError = error as? ToolExecutionError {
            switch executionError {
            case .validationFailed,
                 .approvalRequired,
                 .dangerousToolBlocked,
                 .unknownTool,
                 .duplicateTool:
                return .notRetryable
            case .executionFailed(_, let message):
                return message.localizedCaseInsensitiveContains("permission")
                    ? .notRetryable
                    : .retryable
            }
        }

        let message = String(describing: error)
        return message.localizedCaseInsensitiveContains("permission") ? .notRetryable : .retryable
    }

    private func recordReviewEvent(action: String, status: AuditStatus, session: ReviewSession) throws {
        try auditLogger?.record(
            AuditEvent(
                category: "review",
                action: action,
                status: status,
                metadata: [
                    "session_id": session.id,
                    "plan_id": session.originalPlan.id,
                    "execution_status": String(describing: session.executionStatus)
                ]
            )
        )
    }

    private func recordToolEvent(
        tool: ActionTool,
        status: AuditStatus,
        actionID: String,
        result: ToolResult? = nil,
        error: Error? = nil
    ) throws {
        var metadata = [
            "action_id": actionID,
            "tool": tool.rawValue
        ]
        if let result {
            metadata["summary"] = result.summary
        }
        if let error {
            metadata["error"] = String(describing: error)
        }

        try auditLogger?.record(AuditEvent(category: "tool", action: tool.rawValue, status: status, metadata: metadata))
    }
}
