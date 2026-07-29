import CryptoKit
import Foundation

public enum AssistantQueueState: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case captured
    case interpreted
    case drafted
    case waitingReview
    case approved
    case running
    case blocked
    case done
    case failed
    case rejected
    case deferred
}

public enum AssistantQueuePayload: Codable, Equatable, Sendable {
    case actionPlan(ActionPlan)
    case automationRequest(SyncAutomationRequestPayload)
}

public enum AssistantQueueRequiredCapability: Codable, Equatable, Sendable {
    case tool(ActionTool)
    case appPermission(AppPermission)
    case connectedMacRequired
    case providerExecutionApproval
    case externalMCP(serverID: String, toolName: String)
    case externalConnector(serviceID: String, action: String)
}

public struct AssistantQueueApprovalRecord: Codable, Equatable, Sendable {
    public var approvalID: String?
    public var reviewerID: String
    public var note: String?
    public var reviewedContentFingerprint: String

    public init(
        approvalID: String? = UUID().uuidString,
        reviewerID: String,
        note: String? = nil,
        reviewedContentFingerprint: String
    ) {
        self.approvalID = approvalID
        self.reviewerID = reviewerID
        self.note = note
        self.reviewedContentFingerprint = reviewedContentFingerprint
    }

    public var executionTokenID: String? {
        nil
    }
}

public struct AssistantQueueItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var state: AssistantQueueState
    public private(set) var payload: AssistantQueuePayload
    public private(set) var riskLevel: RiskLevel
    public var sourceTranscript: String?
    public var interpretationSummary: String?
    public var reviewReason: String
    public var redactedSummary: String
    public private(set) var requiredCapabilities: [AssistantQueueRequiredCapability]
    public var approval: AssistantQueueApprovalRecord?
    public var blockingReason: String?
    public var costPreview: AssistantQueueCostPreview?

    public init(
        id: String,
        state: AssistantQueueState,
        payload: AssistantQueuePayload,
        riskLevel: RiskLevel,
        sourceTranscript: String?,
        interpretationSummary: String?,
        reviewReason: String,
        redactedSummary: String,
        requiredCapabilities: [AssistantQueueRequiredCapability],
        approval: AssistantQueueApprovalRecord? = nil,
        blockingReason: String? = nil,
        costPreview: AssistantQueueCostPreview? = nil
    ) {
        self.id = id
        self.state = state
        self.payload = payload
        self.riskLevel = riskLevel
        self.sourceTranscript = sourceTranscript
        self.interpretationSummary = interpretationSummary
        self.reviewReason = reviewReason
        self.redactedSummary = redactedSummary
        self.requiredCapabilities = requiredCapabilities
        self.approval = approval
        self.blockingReason = blockingReason
        self.costPreview = costPreview
    }
}

public enum AssistantQueueTransitionError: Error, Equatable, Sendable {
    case blockedItemCannotBeApproved
    case dangerousPayloadCannotBeApproved
    case costPreviewRequiredBeforeApproval
    case costPreviewRequiredBeforeRunning
    case managedCostCapExceeded
    case approvalRequiredBeforeRunning
    case approvedPayloadChanged
    case runningRequiredBeforeCompletion
    case terminalItemCannotTransition
    case retryRequiresFailedRunnablePayload
    case editRequiresReviewableItem
}

// A struct keeps review-only failures out of the public transition enum, so
// adding another review failure cannot break exhaustive client switches.
public struct AssistantQueueReviewActionUnavailableError: Error, Equatable, Sendable {
    public init() {}
}
public struct AssistantQueueStaleReviewError: Error, Equatable, Sendable {
    public init() {}
}

enum AssistantQueueMutationFailure {
    static let staleUserMessage =
        "This Assistant Queue item changed elsewhere. Review the latest version before acting."
    static let unversionedUserMessage =
        "This Assistant Queue action needs the latest revision. Reload the queue and try again."
}

public enum AssistantQueueStateMachine {
    public static func approve(
        _ item: AssistantQueueItem,
        reviewerID: String,
        note: String? = nil
    ) throws -> AssistantQueueItem {
        guard item.state != .blocked else {
            throw AssistantQueueTransitionError.blockedItemCannotBeApproved
        }
        guard item.state != .running else {
            throw AssistantQueueReviewActionUnavailableError()
        }
        guard !item.containsDangerousPayload else {
            throw AssistantQueueTransitionError.dangerousPayloadCannotBeApproved
        }
        guard item.state != .done, item.state != .failed, item.state != .rejected else {
            throw AssistantQueueTransitionError.terminalItemCannotTransition
        }
        guard let costPreview = item.costPreview else {
            throw AssistantQueueTransitionError.costPreviewRequiredBeforeApproval
        }
        guard costPreview.allowsApprovalAndRun else {
            throw AssistantQueueTransitionError.managedCostCapExceeded
        }

        var approved = item
        approved.state = .approved
        guard let reviewedContentFingerprint = approved.contentFingerprint else {
            throw AssistantQueueReviewActionUnavailableError()
        }
        // Queue approval records user intent only. Execution must still go
        // through ReviewSession/ActionExecutor so tool-level approval tokens
        // are minted at the existing execution gate, never here.
        approved.approval = AssistantQueueApprovalRecord(
            reviewerID: reviewerID,
            note: note,
            reviewedContentFingerprint: reviewedContentFingerprint
        )
        return approved
    }

    public static func startRunning(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard item.state == .approved else {
            throw AssistantQueueTransitionError.approvalRequiredBeforeRunning
        }
        guard let costPreview = item.costPreview else {
            throw AssistantQueueTransitionError.costPreviewRequiredBeforeRunning
        }
        guard costPreview.allowsApprovalAndRun else {
            throw AssistantQueueTransitionError.managedCostCapExceeded
        }
        guard let currentContentFingerprint = item.contentFingerprint,
              item.approval?.reviewedContentFingerprint == currentContentFingerprint else {
            throw AssistantQueueTransitionError.approvedPayloadChanged
        }

        var running = item
        running.state = .running
        return running
    }

    public static func hasCurrentApproval(_ item: AssistantQueueItem) -> Bool {
        guard let currentContentFingerprint = item.contentFingerprint else {
            return false
        }
        return item.approval?.reviewedContentFingerprint == currentContentFingerprint
    }

    public static func markDone(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard item.state == .running else {
            throw AssistantQueueTransitionError.runningRequiredBeforeCompletion
        }

        var done = item
        done.state = .done
        done.blockingReason = nil
        return done
    }

    public static func markFailed(_ item: AssistantQueueItem, reason: String) throws -> AssistantQueueItem {
        guard item.state == .running else {
            throw AssistantQueueTransitionError.runningRequiredBeforeCompletion
        }

        var failed = item
        failed.state = .failed
        failed.blockingReason = reason
        return failed
    }

    public static func markExecutionBlocked(_ item: AssistantQueueItem, reason: String) throws -> AssistantQueueItem {
        guard item.state == .approved || item.state == .running else {
            throw AssistantQueueTransitionError.approvalRequiredBeforeRunning
        }

        var failed = item
        failed.state = .failed
        failed.blockingReason = reason
        return failed
    }

    public static func reopenFailedForReview(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard item.state == .failed,
              AssistantQueueExecutableActionPlanFactory.actionPlan(for: item.payload) != nil else {
            throw AssistantQueueTransitionError.retryRequiresFailedRunnablePayload
        }
        guard !item.containsDangerousPayload else {
            throw AssistantQueueTransitionError.dangerousPayloadCannotBeApproved
        }

        var retry = item
        retry.state = .waitingReview
        // Failed execution must not reuse the prior approval intent. Reopening
        // returns the item to human review so the execution gate mints a fresh token.
        retry.approval = nil
        retry.blockingReason = nil
        retry.reviewReason = "Retry after failed execution. Review this Assistant Queue item before running it again."
        return retry
    }

    public static func reject(_ item: AssistantQueueItem) -> AssistantQueueItem {
        // Keep the original public API source-compatible for SuisuiCore clients.
        // Invalid review actions return the untouched value rather than corrupting
        // in-flight state; app paths use rejectForReview to surface the error.
        (try? rejectForReview(item)) ?? item
    }

    public static func rejectForReview(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard canReject(item.state) else {
            throw AssistantQueueReviewActionUnavailableError()
        }

        var rejected = item
        rejected.state = .rejected
        rejected.approval = nil
        return rejected
    }

    public static func deferItem(_ item: AssistantQueueItem) -> AssistantQueueItem {
        // Preserve the established nonthrowing API while failing closed for
        // running and immutable states. Interactive callers use deferForReview.
        (try? deferForReview(item)) ?? item
    }

    public static func deferForReview(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard canDefer(item.state) else {
            throw AssistantQueueReviewActionUnavailableError()
        }

        var deferred = item
        deferred.state = .deferred
        return deferred
    }

    static func canDefer(_ state: AssistantQueueState) -> Bool {
        switch state {
        case .captured, .interpreted, .drafted, .waitingReview, .approved:
            return true
        case .running, .blocked, .done, .failed, .rejected, .deferred:
            return false
        }
    }

    static func canReject(_ state: AssistantQueueState) -> Bool {
        switch state {
        case .captured, .interpreted, .drafted, .waitingReview, .approved, .blocked, .deferred:
            return true
        case .running, .done, .failed, .rejected:
            // A queue-state mutation cannot cancel in-flight execution. Rejecting
            // here would let side effects finish without a valid done/failed path.
            return false
        }
    }

    public static func markEdited(_ item: AssistantQueueItem, reason: String) throws -> AssistantQueueItem {
        try editReviewDetails(item, reviewReason: reason, redactedSummary: item.redactedSummary)
    }

    public static func editReviewDetails(
        _ item: AssistantQueueItem,
        reviewReason: String,
        redactedSummary: String
    ) throws -> AssistantQueueItem {
        guard item.isEditableForReview else {
            throw AssistantQueueTransitionError.editRequiresReviewableItem
        }
        let redactor = ExecutionReceiptRedactor()
        let sanitizedReason = redactor.redact(reviewReason).trimmingCharacters(in: .whitespacesAndNewlines)
        // This edit field is the review surface of record, not a receipt preview,
        // so keep the caller's full summary while still redacting secrets and paths.
        let summaryRedactionLimit = max(redactedSummary.count, 1_200)
        let sanitizedSummary = redactor.redact(redactedSummary, maxLength: summaryRedactionLimit)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var edited = item
        edited.state = .waitingReview
        // Any post-approval edit changes the reviewed surface, so the queue
        // must drop approval and ask the user to review the edited item again.
        edited.approval = nil
        edited.reviewReason = sanitizedReason.isEmpty ? "Edited Assistant Queue item requires review." : sanitizedReason
        edited.redactedSummary = sanitizedSummary.isEmpty ? item.redactedSummary : sanitizedSummary
        return edited
    }
}

public enum AssistantQueueAdapter {
    public static func makeItem(
        actionPlan: ActionPlan,
        sourceTranscript: String?,
        interpretationSummary: String?,
        reason: String,
        costPreview: AssistantQueueCostPreview = .localOnly()
    ) -> AssistantQueueItem {
        let risk = maxRiskLevel(for: actionPlan)
        let isDangerous = risk == .danger
        return AssistantQueueItem(
            id: "action-plan:\(actionPlan.id)",
            state: isDangerous ? .blocked : .waitingReview,
            payload: .actionPlan(actionPlan),
            riskLevel: risk,
            sourceTranscript: sourceTranscript,
            interpretationSummary: interpretationSummary,
            reviewReason: reason,
            redactedSummary: DeveloperSecretRedactor().redact(actionPlan.summary).text,
            requiredCapabilities: requiredCapabilities(for: actionPlan, riskLevel: risk),
            blockingReason: isDangerous ? "Dangerous action plans cannot be approved from Assistant Queue." : nil,
            costPreview: costPreview
        )
    }

    public static func makeItem(
        automationRequest: SyncAutomationRequestPayload,
        costPreview: AssistantQueueCostPreview = .localOnly(note: "Local Mac execution preview only. No Suisui managed charge before run.")
    ) -> AssistantQueueItem {
        let actionPlan = AssistantQueueExecutableActionPlanFactory.actionPlan(for: .automationRequest(automationRequest))
        return AssistantQueueItem(
            id: "automation-request:\(automationRequest.id)",
            state: state(for: automationRequest),
            payload: .automationRequest(automationRequest),
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: automationRequest.toolName,
            reviewReason: reviewReason(for: automationRequest),
            redactedSummary: AssistantQueueExecutableActionPlanFactory.reviewSummary(for: automationRequest),
            requiredCapabilities: requiredCapabilities(for: actionPlan),
            costPreview: costPreview
        )
    }

    public static func makeConnectorSendGateItem(
        serviceID: String,
        serviceDisplayName: String,
        redactedSourceTranscript: String,
        redactedArgumentSummary: String,
        routeSummary: String,
        requestIDProvider: () -> String = { "connector-send:\(UUID().uuidString)" }
    ) -> AssistantQueueItem {
        let normalizedServiceID = normalizedConnectorIdentifier(serviceID, fallback: "external")
        let displayName = normalizedConnectorDisplayName(serviceDisplayName, fallback: normalizedServiceID.capitalized)
        let sanitizedSummary = sanitizedReviewText(
            redactedArgumentSummary,
            fallback: "\(displayName) connector send requested."
        )
        let request = SyncAutomationRequestPayload(
            id: requestIDProvider(),
            source: .conversation,
            approvalState: .pendingApproval,
            sourceClientID: "voice",
            toolName: "connector.send",
            redactedArgumentSummary: sanitizedSummary
        )
        // Connector sends are write-capable side effects, but no authenticated
        // connector runtime exists yet. Store the request as a blocked,
        // non-executable automation payload so review history shows what was
        // requested while ActionExecutor has no plan to run.
        return AssistantQueueItem(
            id: "automation-request:\(request.id)",
            state: .blocked,
            payload: .automationRequest(request),
            riskLevel: .write,
            sourceTranscript: sanitizedReviewText(redactedSourceTranscript, fallback: nil),
            interpretationSummary: sanitizedReviewText(routeSummary, fallback: "Route as connector.send_gate without sending."),
            reviewReason: "\(displayName) connector send requires an authenticated connector and explicit send approval.",
            redactedSummary: sanitizedSummary,
            requiredCapabilities: [
                .externalConnector(serviceID: normalizedServiceID, action: "message.send"),
                .providerExecutionApproval
            ],
            blockingReason: "\(displayName) connector send is not configured. Create a reviewed draft instead; no external message was sent.",
            costPreview: .localOnly(note: "Blocked connector send gate. No external message is sent and no Suisui managed charge is incurred.")
        )
    }

    private static func maxRiskLevel(for actionPlan: ActionPlan) -> RiskLevel {
        actionPlan.actions.map(\.riskLevel).max().map { max($0, actionPlan.riskLevel) } ?? actionPlan.riskLevel
    }

    private static func requiredCapabilities(
        for actionPlan: ActionPlan,
        riskLevel: RiskLevel
    ) -> [AssistantQueueRequiredCapability] {
        var capabilities = actionPlan.actions.map { AssistantQueueRequiredCapability.tool($0.tool) }
        capabilities.append(contentsOf: actionPlan.actions.compactMap { action in
            action.tool.requiredAssistantQueueAppPermission.map(AssistantQueueRequiredCapability.appPermission)
        })
        if actionPlan.requiresApproval || riskLevel >= .write {
            capabilities.append(.providerExecutionApproval)
        }
        return unique(capabilities)
    }

    private static func requiredCapabilities(for actionPlan: ActionPlan?) -> [AssistantQueueRequiredCapability] {
        guard let actionPlan else {
            return [.connectedMacRequired, .providerExecutionApproval]
        }
        return unique([.connectedMacRequired] + requiredCapabilities(for: actionPlan, riskLevel: maxRiskLevel(for: actionPlan)))
    }

    private static func state(for request: SyncAutomationRequestPayload) -> AssistantQueueState {
        switch request.approvalState {
        case .rejected:
            return .rejected
        default:
            return .waitingReview
        }
    }

    private static func reviewReason(for request: SyncAutomationRequestPayload) -> String {
        switch request.approvalState {
        case .pendingApproval:
            return "Remote automation request is pending approval."
        case .approved:
            return "Remote automation request was approved but still requires local execution gate."
        case .rejected:
            return "Remote automation request was rejected."
        case .notRequired:
            return "Remote automation request must enter Assistant Queue before execution."
        }
    }

    private static func unique(
        _ capabilities: [AssistantQueueRequiredCapability]
    ) -> [AssistantQueueRequiredCapability] {
        var result: [AssistantQueueRequiredCapability] = []
        for capability in capabilities where !result.contains(capability) {
            result.append(capability)
        }
        return result
    }

    private static func normalizedConnectorIdentifier(_ value: String, fallback: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_-")
        let normalized = value
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { allowed.contains($0) }
        return normalized.isEmpty ? fallback : normalized
    }

    private static func normalizedConnectorDisplayName(_ value: String, fallback: String) -> String {
        let trimmed = DeveloperSecretRedactor().redact(value).text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? fallback : trimmed
        guard displayName.count > 80 else {
            return displayName
        }
        return String(displayName.prefix(80))
    }

    private static func sanitizedReviewText(_ value: String, fallback: String?) -> String {
        let redacted = ExecutionReceiptRedactor().redact(value, maxLength: 1_200)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if redacted.isEmpty, let fallback {
            return fallback
        }
        return redacted
    }
}

extension AssistantQueueItem {
    /// An opaque comparison token for optimistic queue mutations.
    ///
    /// Treat this value as opaque: compare it only for equality with the token
    /// presented to a reviewer. Custom stores may copy it into their read-model
    /// rows, but must recompute it from the current item instead of persisting it.
    public var mutationRevision: String? {
        AssistantQueueMutationRevision.make(item: self)
    }

    var contentFingerprint: String? {
        guard let payloadJSON = AssistantQueueMutationRevision.canonicalJSONString(payload),
              let capabilitiesJSON = AssistantQueueMutationRevision.canonicalJSONString(
                  requiredCapabilities
              ) else {
            return nil
        }
        let costPreviewJSON: String?
        if let costPreview {
            guard let encodedCostPreview = AssistantQueueMutationRevision.canonicalJSONString(
                costPreview
            ) else {
                return nil
            }
            costPreviewJSON = encodedCostPreview
        } else {
            costPreviewJSON = nil
        }
        // Approval records must never persist raw prompts or action arguments. The
        // outer digest keeps canonical payload and cost-preview bytes out of the
        // approval record while preserving drift detection across process restarts.
        return AssistantQueueMutationRevision.canonicalDigest([
            id,
            riskLevel.rawValue,
            redactedSummary,
            payloadJSON,
            capabilitiesJSON,
            costPreviewJSON
        ])
    }
}

enum AssistantQueueMutationRevision {
    static func make(item: AssistantQueueItem) -> String? {
        guard let payloadJSON = canonicalJSONString(item.payload),
              let capabilitiesJSON = canonicalJSONString(item.requiredCapabilities) else {
            return nil
        }
        let approvalJSON: String?
        if let approval = item.approval {
            guard let encodedApproval = canonicalJSONString(approval) else {
                return nil
            }
            approvalJSON = encodedApproval
        } else {
            approvalJSON = nil
        }
        let costPreviewJSON: String?
        if let costPreview = item.costPreview {
            guard let encodedCostPreview = canonicalJSONString(costPreview) else {
                return nil
            }
            costPreviewJSON = encodedCostPreview
        } else {
            costPreviewJSON = nil
        }
        return makeStored(
            id: item.id,
            payloadKind: payloadKind(for: item.payload),
            payloadJSON: payloadJSON,
            state: item.state.rawValue,
            riskLevel: item.riskLevel.rawValue,
            sourceTranscript: item.sourceTranscript,
            interpretationSummary: item.interpretationSummary,
            reviewReason: item.reviewReason,
            redactedSummary: item.redactedSummary,
            requiredCapabilitiesJSON: capabilitiesJSON,
            approvalJSON: approvalJSON,
            blockingReason: item.blockingReason,
            costPreviewJSON: costPreviewJSON
        )
    }

    static func canonicalJSONString<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)).map { String(decoding: $0, as: UTF8.self) }
    }

    static func makeStored(
        id: String,
        payloadKind: String,
        payloadJSON: String,
        state: String,
        riskLevel: String,
        sourceTranscript: String?,
        interpretationSummary: String?,
        reviewReason: String,
        redactedSummary: String,
        requiredCapabilitiesJSON: String,
        approvalJSON: String?,
        blockingReason: String?,
        costPreviewJSON: String?
    ) -> String {
        canonicalDigest([
            id,
            payloadKind,
            payloadJSON,
            state,
            riskLevel,
            sourceTranscript,
            interpretationSummary,
            reviewReason,
            redactedSummary,
            requiredCapabilitiesJSON,
            approvalJSON,
            blockingReason,
            costPreviewJSON
        ])
    }

    static func canonicalDigest(_ components: [String?]) -> String {
        // Length-prefix every component and encode nil separately. Delimiter
        // concatenation is ambiguous when identifiers or review text itself
        // contains delimiters. Approval fingerprints and CAS revisions share
        // this framing so both review boundaries reject structural collisions.
        let canonical = components.map { component -> String in
            guard let component else {
                return "-1:"
            }
            return "\(component.utf8.count):\(component)"
        }.joined()
        return AssistantQueueDigest.sha256(canonical)
    }

    private static func payloadKind(for payload: AssistantQueuePayload) -> String {
        switch payload {
        case .actionPlan:
            return "action_plan"
        case .automationRequest:
            return "automation_request"
        }
    }
}

extension AssistantQueueItem {
    var containsDangerousPayload: Bool {
        if riskLevel == .danger {
            return true
        }

        switch payload {
        case .actionPlan(let plan):
            return plan.containsDangerousAction
        case .automationRequest:
            // Automation requests are transport payloads; re-derive the
            // executable plan so connector-originated requests cannot bypass the
            // same danger gate that protects native action plans.
            return AssistantQueueExecutableActionPlanFactory.actionPlan(for: payload)?.containsDangerousAction ?? false
        }
    }
}

private extension ActionPlan {
    var containsDangerousAction: Bool {
        riskLevel == .danger || actions.contains { $0.riskLevel == .danger }
    }
}

extension AssistantQueueItem {
    var isEditableForReview: Bool {
        switch state {
        case .captured, .interpreted, .drafted, .waitingReview, .approved, .deferred:
            return riskLevel != .danger
        case .blocked, .running, .done, .failed, .rejected:
            return false
        }
    }
}

private enum AssistantQueueDigest {
    static func sha256<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return sha256(data)
    }

    static func sha256(_ value: String) -> String {
        sha256(Data(value.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

private extension ActionTool {
    var requiredAssistantQueueAppPermission: AppPermission? {
        switch actionType {
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
