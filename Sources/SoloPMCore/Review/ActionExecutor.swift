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
    private let redactor: DeveloperSecretRedactor

    public init(
        registry: ToolRegistry,
        auditLogger: (any AuditLogger)? = nil,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor()
    ) {
        self.registry = registry
        self.auditLogger = auditLogger
        self.redactor = redactor
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
                recordToolEventOrMarkAuditFailure(
                    tool: item.editedAction.tool,
                    status: .skipped,
                    actionID: item.id,
                    session: &working
                )
                continue
            }

            if failurePolicy == .stopOnFailure, hasFailure {
                working.markAction(id: item.id, status: .skipped)
                recordToolEventOrMarkAuditFailure(
                    tool: item.editedAction.tool,
                    status: .skipped,
                    actionID: item.id,
                    session: &working
                )
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
                let actionStatus = Self.actionExecutionStatus(for: result.status)
                if result.status == .failed {
                    hasFailure = true
                }
                working.markAction(
                    id: item.id,
                    status: actionStatus,
                    result: result,
                    errorMessage: result.status == .failed ? redacted(result.summary) : nil,
                    failureRecovery: result.status == .failed ? .retryable : nil
                )
                recordToolEventOrMarkAuditFailure(
                    tool: action.tool,
                    status: Self.auditStatus(for: result.status),
                    actionID: item.id,
                    result: result,
                    session: &working
                )

                if result.status == .succeeded, action.tool == .projectCreate, let projectID = result.output["projectId"] {
                    latestProjectID = projectID
                }
            } catch {
                hasFailure = true
                working.markAction(
                    id: item.id,
                    status: .failed,
                    errorMessage: userFacingToolErrorMessage(for: error),
                    failureRecovery: Self.failureRecovery(for: error)
                )
                recordToolEventOrMarkAuditFailure(
                    tool: action.tool,
                    status: .failed,
                    actionID: item.id,
                    error: error,
                    session: &working
                )
            }
        }

        working.executionStatus = hasFailure ? .failed : .completed
        recordReviewEventOrMarkAuditFailure(
            action: "execution.complete",
            status: hasFailure ? .failed : .succeeded,
            session: &working
        )
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

    private static func actionExecutionStatus(for status: ToolExecutionStatus) -> ReviewActionExecutionStatus {
        switch status {
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .skipped:
            return .skipped
        }
    }

    private static func auditStatus(for status: ToolExecutionStatus) -> AuditStatus {
        switch status {
        case .succeeded:
            return .succeeded
        case .failed:
            return .failed
        case .skipped:
            return .skipped
        }
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
            metadata["summary"] = redacted(result.summary)
        }
        if let error {
            metadata["error"] = redacted(String(describing: error))
        }

        try auditLogger?.record(AuditEvent(category: "tool", action: tool.rawValue, status: status, metadata: metadata))
    }

    private func redacted(_ value: String) -> String {
        redactor.redact(value).text
    }

    private func recordReviewEventOrMarkAuditFailure(
        action: String,
        status: AuditStatus,
        session: inout ReviewSession
    ) {
        do {
            try recordReviewEvent(action: action, status: status, session: session)
        } catch {
            session.auditErrorMessage = "Action audit log could not be saved."
        }
    }

    private func recordToolEventOrMarkAuditFailure(
        tool: ActionTool,
        status: AuditStatus,
        actionID: String,
        result: ToolResult? = nil,
        error: Error? = nil,
        session: inout ReviewSession
    ) {
        do {
            try recordToolEvent(tool: tool, status: status, actionID: actionID, result: result, error: error)
        } catch {
            session.auditErrorMessage = "Action audit log could not be saved."
        }
    }

    private func userFacingToolErrorMessage(for error: Error) -> String {
        switch error {
        case ToolExecutionError.duplicateTool(let tool):
            return "Tool \(tool.rawValue) is registered more than once."
        case ToolExecutionError.unknownTool(let tool):
            return "Tool \(tool.rawValue) is not available."
        case ToolExecutionError.approvalRequired(let tool):
            return "Approval is required before running \(tool.rawValue)."
        case ToolExecutionError.dangerousToolBlocked(let tool):
            return "Tool \(tool.rawValue) is blocked for safety."
        case ToolExecutionError.validationFailed(let tool, let message):
            return "Invalid arguments for \(tool.rawValue): \(redacted(message))"
        case ToolExecutionError.executionFailed(let tool, let message):
            return "\(tool.rawValue) failed: \(redacted(message))"
        default:
            return "Action failed. Review the action details and try again."
        }
    }
}
