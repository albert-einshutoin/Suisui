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
    public fileprivate(set) var id: String
    public fileprivate(set) var originalAction: PlanAction
    public fileprivate(set) var editedAction: PlanAction
    public fileprivate(set) var isEnabled: Bool
    public fileprivate(set) var executionStatus: ReviewActionExecutionStatus
    public fileprivate(set) var result: ToolResult?
    public fileprivate(set) var errorMessage: String?
    public fileprivate(set) var failureRecovery: ReviewActionFailureRecovery?

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

    public func argumentDisplayFields() -> [ReviewActionField] {
        editedAction.argumentDisplayFields()
    }
}

/// One reviewable argument, split so the approval surface can render
/// "Due — Fri, Jul 10" instead of the raw `dueAt: 2026-07-10T09:00:00Z` that a
/// person is being asked to approve.
///
/// The label is a *localization key*, not final text: `SuisuiCore` has no
/// translation catalog, so the app layer resolves `labelKey` against the same
/// bundle it uses for every other status string.
public struct ReviewActionField: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// Free text the user is likely editing (title, summary, body).
        case text
        /// A stored ISO8601 or `yyyy-MM-dd` value the app layer must format.
        case timestamp
        /// An internal row id. Never the point of the review, so it sorts last
        /// and stays out of the compact preview.
        case identifier
        case flag
        case other
    }

    public var id: String { key }
    /// Raw argument key, kept so audit output and debugging stay traceable.
    public let key: String
    public let labelKey: String
    public let rawValue: String
    public let kind: Kind

    public init(key: String, labelKey: String, rawValue: String, kind: Kind) {
        self.key = key
        self.labelKey = labelKey
        self.rawValue = rawValue
        self.kind = kind
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

    /// Arguments as labelled fields, ordered the way a person reads a proposal:
    /// what it is, when it happens, then everything else, with internal ids
    /// last.
    func argumentDisplayFields() -> [ReviewActionField] {
        arguments
            .map { key, value in
                ReviewActionField(
                    key: key,
                    labelKey: key.reviewFieldLabelKey,
                    rawValue: value.reviewDisplayValue.normalizedSingleLine,
                    kind: value.reviewFieldKind(fallback: key.reviewFieldKind)
                )
            }
            .sorted { lhs, rhs in
                let lhsRank = lhs.key.reviewDisplayPriority
                let rhsRank = rhs.key.reviewDisplayPriority
                if lhsRank == rhsRank {
                    return lhs.key < rhs.key
                }
                return lhsRank < rhsRank
            }
    }
}

public enum ReviewSessionError: Error, Equatable, Sendable {
    case approvalBlocked(String)
    case approvalNotRequired
    case approvalRequired
    case approvalSessionMismatch
    case invalidApprovalValidity
    case actionNotFound(String)
}

public struct ReviewSession: Equatable, Sendable {
    public let id: String
    public let originalPlan: ActionPlan
    public private(set) var items: [ReviewActionItem]
    public private(set) var approvalState: ApprovalState
    public internal(set) var executionStatus: ReviewExecutionStatus
    public internal(set) var auditErrorMessage: String?
    public internal(set) var resolvedActionEvidence: [ResolvedActionEvidence]
    public let createdAt: Date
    public let executionPolicy: ActionExecutorFailurePolicy

    public init(
        id: String = UUID().uuidString,
        plan: ActionPlan,
        createdAt: Date = Date(),
        executionPolicy: ActionExecutorFailurePolicy = .stopOnFailure
    ) {
        let normalizedActions = ActionPlanDependencyNormalizer.makeReferencesExplicit(in: plan.actions)
        var normalizedPlan = plan
        normalizedPlan.actions = normalizedActions
        normalizedPlan.riskLevel = normalizedActions.map(\.riskLevel).max() ?? .read
        normalizedPlan.requiresApproval = normalizedActions.contains { $0.riskLevel >= .write }

        self.id = id
        self.originalPlan = normalizedPlan
        self.items = normalizedActions.map { ReviewActionItem(action: $0) }
        self.approvalState = Self.initialApprovalState(for: normalizedActions)
        self.executionStatus = .notStarted
        self.auditErrorMessage = nil
        self.resolvedActionEvidence = []
        self.createdAt = createdAt
        self.executionPolicy = executionPolicy
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

    public var approvalBinding: ApprovalPlanBinding {
        ApprovalPlanBinding(
            planID: originalPlan.id,
            items: items.map {
                ApprovalPlanItem(action: $0.editedAction, isEnabled: $0.isEnabled)
            },
            executionPolicy: executionPolicy
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

    @discardableResult
    public mutating func approve(
        approvalID: UUID = UUID(),
        issuedAt: Date = Date(),
        validity: TimeInterval = 300,
        nonce: UUID = UUID()
    ) throws -> ApprovedExecution {
        switch approvalState {
        case .pending:
            guard validity > 0 else {
                throw ReviewSessionError.invalidApprovalValidity
            }
            let binding = approvalBinding
            let approvedExecution = ApprovedExecution(
                approvalID: approvalID,
                sessionID: id,
                planID: binding.planID,
                canonicalPlanDigest: try binding.digest(),
                enabledActionIDs: binding.enabledActionIDs,
                issuedAt: issuedAt,
                expiresAt: issuedAt.addingTimeInterval(validity),
                nonce: nonce
            )
            approvalState = .approved(approvedExecution)
            return approvedExecution
        case .blocked(let reason):
            throw ReviewSessionError.approvalBlocked(reason)
        case .notRequired, .approved:
            throw ReviewSessionError.approvalNotRequired
        }
    }

    public mutating func requestFreshApproval() {
        guard case .approved = approvalState else {
            return
        }
        // A completed, failed, expired, or unknown attempt must never reuse its
        // sealed nonce. Preserve the reviewed plan, but return its approval gate
        // to the state derived from the currently enabled actions.
        refreshApprovalState()
    }

    /// Compatibility entry point for callers that provide approval identity.
    /// The caller's digest and plan fields are never trusted; this session
    /// recomputes and seals its current reviewed binding.
    public mutating func approve(token: ApprovalToken) throws {
        guard token.sessionID == id else {
            throw ReviewSessionError.approvalSessionMismatch
        }
        _ = try approve(
            approvalID: token.approvalID,
            issuedAt: token.issuedAt,
            validity: token.expiresAt.timeIntervalSince(token.issuedAt),
            nonce: token.nonce
        )
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
        // Editing changes the reviewed payload, so write approvals must be reissued before execution.
        approvalState = Self.initialApprovalState(for: enabledItems.map(\.editedAction))
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

private enum ActionPlanDependencyNormalizer {
    static func makeReferencesExplicit(in actions: [PlanAction]) -> [PlanAction] {
        var latestProjectCreateActionID: String?
        return actions.map { sourceAction in
            var action = sourceAction
            if let projectActionID = latestProjectCreateActionID {
                let reference = JSONValue.actionOutput(
                    ActionOutputReference(actionID: projectActionID, key: "projectId")
                )
                switch action.tool {
                case .taskCreate where action.arguments["projectId"] == nil:
                    action.arguments["projectId"] = reference
                case .taskBulkCreate:
                    action.arguments["tasks"] = explicitBulkTaskReferences(
                        action.arguments["tasks"],
                        reference: reference
                    )
                default:
                    break
                }
            }
            if action.tool == .projectCreate {
                latestProjectCreateActionID = action.id
            }
            return action
        }
    }

    private static func explicitBulkTaskReferences(
        _ value: JSONValue?,
        reference: JSONValue
    ) -> JSONValue? {
        guard case .array(let values)? = value else {
            return value
        }
        return .array(values.map { value in
            guard case .object(var object) = value else {
                return value
            }
            if object["projectId"] == nil {
                object["projectId"] = reference
            }
            return .object(object)
        })
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
    /// The value type is authoritative when it carries approval semantics.
    /// Boolean argument keys are open-ended across tools, so a key-only table
    /// can never classify every flag and would leak `true` / `false` into the
    /// human review surface.
    func reviewFieldKind(fallback: ReviewActionField.Kind) -> ReviewActionField.Kind {
        if case .bool = self {
            return .flag
        }
        return fallback
    }

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
        case .actionOutput(let reference):
            "output(\(reference.actionID).\(reference.key))"
        }
    }
}

private extension String {
    /// Normalizes the casing variants the planning schema uses (`projectID`,
    /// `projectId`, `project_id`) so one vocabulary entry covers all of them.
    var reviewFieldLookupKey: String {
        lowercased().replacingOccurrences(of: "_", with: "")
    }

    /// Maps a machine argument key to the words a person uses for it. Anything
    /// outside this vocabulary falls back to the raw key rather than inventing
    /// a label, so an unmapped argument is visibly unmapped instead of
    /// silently mislabelled.
    var reviewFieldLabelKey: String {
        switch reviewFieldLookupKey {
        case "title", "name": "Title"
        case "summary": "Summary"
        case "detail", "details", "notes", "body", "content", "message": "Details"
        case "dueat", "duedate", "due": "Due"
        case "startat", "starttime": "Starts"
        case "endat", "endtime": "Ends"
        case "scheduledat": "Scheduled"
        case "priority": "Priority"
        case "status": "Status"
        case "recurrence": "Repeats"
        case "projectid": "Project"
        case "taskid": "Task"
        case "calendarid": "Calendar"
        case "remindername", "listname": "List"
        case "path", "filepath": "File"
        case "directory", "directorypath": "Folder"
        case "recipient", "to": "To"
        case "subject": "Subject"
        case "url", "link": "Link"
        case "branch": "Branch"
        case "repository", "repositorypath": "Repository"
        default: self
        }
    }

    var reviewFieldKind: ReviewActionField.Kind {
        switch reviewFieldLookupKey {
        case "dueat", "duedate", "due", "startat", "starttime", "endat",
             "endtime", "scheduledat", "completedat", "remindat":
            .timestamp
        case "projectid", "taskid", "calendarid", "eventid", "id":
            .identifier
        case "title", "name", "summary", "detail", "details", "notes", "body",
             "content", "message", "subject":
            .text
        default:
            .other
        }
    }

    var reviewDisplayPriority: Int {
        switch reviewFieldLookupKey {
        case "title", "name", "summary":
            0
        case "dueat", "duedate", "due", "startat", "endat", "scheduledat",
             "priority", "status", "recurrence":
            1
        // Internal row ids answer "which record" but never "what will happen",
        // so they sort behind every human-meaningful field.
        case "projectid", "taskid", "calendarid", "eventid", "id":
            3
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
