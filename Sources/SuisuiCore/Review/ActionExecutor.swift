import Foundation

public enum ActionExecutorFailurePolicy: String, Codable, Equatable, Sendable {
    case stopOnFailure
    case continueOnFailure
}

public enum ActionExecutorError: Error, Equatable, Sendable {
    case approvalRequired
    case approvalBlocked(String)
    case invalidApproval(ApprovedExecutionValidationError)
    case approvalReplayDetected(UUID)
    case noEnabledActions
    case validationFailed([ToolInputValidationIssue])
    case dependencyResolutionFailed(actionID: String, reference: ActionOutputReference)
    case invalidActionGraph(String)
}

public struct ActionExecutor: Sendable {
    private let registry: ToolRegistry
    private let auditLogger: (any AuditLogger)?
    private let redactor: DeveloperSecretRedactor
    private let replayStore: any ApprovalReplayStore

    public init(
        registry: ToolRegistry,
        auditLogger: (any AuditLogger)? = nil,
        redactor: DeveloperSecretRedactor = DeveloperSecretRedactor(),
        replayStore: any ApprovalReplayStore = ProcessLocalApprovalReplayStore()
    ) {
        self.registry = registry
        self.auditLogger = auditLogger
        self.redactor = redactor
        self.replayStore = replayStore
    }

    public func validationIssues(for session: ReviewSession) -> [ToolInputValidationIssue] {
        session.enabledItems.flatMap { registry.validate(action: $0.editedAction) }
    }

    public func execute(
        _ session: ReviewSession,
        now: Date = Date()
    ) throws -> ReviewSession {
        let approval = try preflight(session, now: now)
        if let approval {
            guard try replayStore.claim(approval, at: now) else {
                throw ActionExecutorError.approvalReplayDetected(approval.nonce)
            }
        }

        do {
            let executed = try executeClaimed(session, approval: approval, now: now)
            if let approval {
                try replayStore.finish(
                    nonce: approval.nonce,
                    state: executed.executionStatus == .completed ? .completed : .failed,
                    at: now
                )
            }
            return executed
        } catch {
            if let approval {
                try? replayStore.finish(nonce: approval.nonce, state: .unknown, at: now)
            }
            throw error
        }
    }

    private func executeClaimed(
        _ session: ReviewSession,
        approval: ApprovedExecution?,
        now: Date
    ) throws -> ReviewSession {

        var working = session
        working.executionStatus = .executing
        try recordReviewEvent(action: "execution.start", status: .started, session: working)

        var actionOutputs: [String: [String: JSONValue]] = [:]
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

            if working.executionPolicy == .stopOnFailure, hasFailure {
                working.markAction(id: item.id, status: .skipped)
                recordToolEventOrMarkAuditFailure(
                    tool: item.editedAction.tool,
                    status: .skipped,
                    actionID: item.id,
                    session: &working
                )
                continue
            }

            let action = item.editedAction
            working.markAction(id: item.id, status: .executing)

            do {
                let tool = try registry.tool(named: action.tool)
                let resolution = try resolve(
                    arguments: action.arguments,
                    actionID: action.id,
                    outputs: actionOutputs
                )
                let resolvedArguments = resolution.arguments
                let resolvedValidationIssues = tool.inputSchema.validate(
                    arguments: resolvedArguments,
                    tool: action.tool,
                    actionID: action.id
                )
                guard resolvedValidationIssues.isEmpty else {
                    throw ToolExecutionError.validationFailed(action.tool, issues: resolvedValidationIssues)
                }
                working.resolvedActionEvidence.append(
                    ResolvedActionEvidence(
                        actionID: action.id,
                        resolvedArgumentsDigest: try CanonicalJSONEncoder
                            .digest(.object(resolvedArguments))
                            .lowercaseHexString,
                        dependencies: resolution.dependencies
                    )
                )
                let authorization = try approval.map {
                    try ToolActionAuthorization(
                        approval: $0,
                        actionID: action.id,
                        tool: action.tool,
                        arguments: resolvedArguments
                    )
                }
                let result = try tool.execute(
                    arguments: resolvedArguments,
                    context: ToolExecutionContext(
                        authorization: authorization,
                        now: now,
                        source: .reviewUI,
                        executionID: approval?.nonce.uuidString ?? working.id,
                        reviewSessionID: working.id,
                        actionID: action.id,
                        idempotencyKey: try ToolExecutionContext.externalSideEffectIdempotencyKey(
                            reviewSessionID: working.id,
                            actionID: action.id,
                            tool: action.tool,
                            arguments: resolvedArguments
                        )
                    )
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

                if result.status == .succeeded {
                    actionOutputs[action.id] = result.output
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

    private func preflight(_ session: ReviewSession, now: Date) throws -> ApprovedExecution? {
        guard !session.enabledItems.isEmpty else {
            throw ActionExecutorError.noEnabledActions
        }

        try validateActionGraph(session)

        let validationIssues = validationIssues(for: session)
        guard validationIssues.isEmpty else {
            throw ActionExecutorError.validationFailed(validationIssues)
        }

        switch session.approvalState {
        case .blocked(let reason):
            throw ActionExecutorError.approvalBlocked(reason)
        case .pending:
            throw ActionExecutorError.approvalRequired
        case .approved(let approval):
            do {
                try approval.validate(
                    for: session.approvalBinding,
                    sessionID: session.id,
                    now: now
                )
            } catch let error as ApprovedExecutionValidationError {
                throw ActionExecutorError.invalidApproval(error)
            }
            return approval
        case .notRequired:
            return nil
        }
    }

    private func validateActionGraph(_ session: ReviewSession) throws {
        let actionIDs = session.items.map(\.id)
        guard Set(actionIDs).count == actionIDs.count else {
            throw ActionExecutorError.invalidActionGraph("Action IDs must be unique.")
        }
        let actionIndex = Dictionary(uniqueKeysWithValues: actionIDs.enumerated().map { ($0.element, $0.offset) })
        let enabledActionIDs = Set(session.enabledItems.map(\.id))

        for (consumerIndex, item) in session.items.enumerated() where item.isEnabled {
            for reference in actionOutputReferences(in: .object(item.editedAction.arguments)) {
                guard let sourceIndex = actionIndex[reference.actionID] else {
                    throw ActionExecutorError.invalidActionGraph(
                        "Action \(item.id) references missing action \(reference.actionID)."
                    )
                }
                guard sourceIndex < consumerIndex else {
                    throw ActionExecutorError.invalidActionGraph(
                        "Action \(item.id) references an action that does not precede it."
                    )
                }
                guard enabledActionIDs.contains(reference.actionID) else {
                    throw ActionExecutorError.invalidActionGraph(
                        "Action \(item.id) references disabled action \(reference.actionID)."
                    )
                }
            }
        }
    }

    private func actionOutputReferences(in value: JSONValue) -> [ActionOutputReference] {
        switch value {
        case .actionOutput(let reference):
            return [reference]
        case .object(let object):
            return object.keys.sorted().flatMap { key in
                object[key].map(actionOutputReferences(in:)) ?? []
            }
        case .array(let values):
            return values.flatMap(actionOutputReferences(in:))
        case .string, .number, .bool, .null:
            return []
        }
    }

    private func resolve(
        arguments: [String: JSONValue],
        actionID: String,
        outputs: [String: [String: JSONValue]]
    ) throws -> (
        arguments: [String: JSONValue],
        dependencies: [ActionDependencyResolutionEvidence]
    ) {
        var resolvedArguments: [String: JSONValue] = [:]
        var dependencies: [ActionDependencyResolutionEvidence] = []
        for key in arguments.keys.sorted() {
            guard let value = arguments[key] else {
                continue
            }
            let resolution = try resolve(
                value: value,
                path: key,
                actionID: actionID,
                outputs: outputs
            )
            resolvedArguments[key] = resolution.value
            dependencies.append(contentsOf: resolution.dependencies)
        }
        return (resolvedArguments, dependencies)
    }

    private func resolve(
        value: JSONValue,
        path: String,
        actionID: String,
        outputs: [String: [String: JSONValue]]
    ) throws -> (
        value: JSONValue,
        dependencies: [ActionDependencyResolutionEvidence]
    ) {
        switch value {
        case .actionOutput(let reference):
            guard let resolved = outputs[reference.actionID]?[reference.key] else {
                throw ActionExecutorError.dependencyResolutionFailed(
                    actionID: actionID,
                    reference: reference
                )
            }
            return (
                resolved,
                [
                    ActionDependencyResolutionEvidence(
                        argumentPath: path,
                        sourceActionID: reference.actionID,
                        outputKey: reference.key,
                        resolvedValueDigest: try CanonicalJSONEncoder
                            .digest(resolved)
                            .lowercaseHexString
                    )
                ]
            )
        case .object(let object):
            var resolvedObject: [String: JSONValue] = [:]
            var dependencies: [ActionDependencyResolutionEvidence] = []
            for key in object.keys.sorted() {
                guard let child = object[key] else {
                    continue
                }
                let resolution = try resolve(
                    value: child,
                    path: "\(path).\(key)",
                    actionID: actionID,
                    outputs: outputs
                )
                resolvedObject[key] = resolution.value
                dependencies.append(contentsOf: resolution.dependencies)
            }
            return (.object(resolvedObject), dependencies)
        case .array(let values):
            var resolvedValues: [JSONValue] = []
            var dependencies: [ActionDependencyResolutionEvidence] = []
            for (index, child) in values.enumerated() {
                let resolution = try resolve(
                    value: child,
                    path: "\(path)[\(index)]",
                    actionID: actionID,
                    outputs: outputs
                )
                resolvedValues.append(resolution.value)
                dependencies.append(contentsOf: resolution.dependencies)
            }
            return (.array(resolvedValues), dependencies)
        case .string, .number, .bool, .null:
            return (value, [])
        }
    }

    private static func failureRecovery(for error: Error) -> ReviewActionFailureRecovery {
        if error is ActionExecutorError {
            return .notRetryable
        }

        if let executionError = error as? ToolExecutionError {
            switch executionError {
            case .validationFailed,
                 .approvalRequired,
                 .approvalBindingInvalid,
                 .dangerousToolBlocked,
                 .sideEffectIdentityMissing,
                 .externalSideEffectInProgress,
                 .externalSideEffectRequiresReconciliation,
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
        case ToolExecutionError.approvalBindingInvalid(let tool):
            return "Approval no longer matches \(tool.rawValue). Review the action again."
        case ToolExecutionError.dangerousToolBlocked(let tool):
            return "Tool \(tool.rawValue) is blocked for safety."
        case ToolExecutionError.sideEffectIdentityMissing(let tool):
            return "Execution identity is missing for \(tool.rawValue). Review the action again."
        case ToolExecutionError.externalSideEffectInProgress(let tool, _):
            return "\(tool.rawValue) is already in progress. Wait for reconciliation before retrying."
        case ToolExecutionError.externalSideEffectRequiresReconciliation(let tool, _):
            return "\(tool.rawValue) may already have changed an external resource. Reconcile it before retrying."
        case ToolExecutionError.validationFailed(let tool, let message):
            return "Invalid arguments for \(tool.rawValue): \(redacted(message))"
        case ToolExecutionError.executionFailed(let tool, let message):
            return "\(tool.rawValue) failed: \(redacted(message))"
        default:
            return "Action failed. Review the action details and try again."
        }
    }
}
