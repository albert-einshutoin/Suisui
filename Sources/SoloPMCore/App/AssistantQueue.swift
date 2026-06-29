import Foundation

public enum AssistantQueueState: String, Codable, Equatable, Sendable {
    case captured
    case interpreted
    case drafted
    case waitingReview
    case approved
    case running
    case blocked
    case done
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
}

public struct AssistantQueueApprovalRecord: Codable, Equatable, Sendable {
    public var reviewerID: String
    public var note: String?
    public var reviewedContentFingerprint: String

    public init(
        reviewerID: String,
        note: String? = nil,
        reviewedContentFingerprint: String
    ) {
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
        blockingReason: String? = nil
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
    }
}

public enum AssistantQueueTransitionError: Error, Equatable, Sendable {
    case blockedItemCannotBeApproved
    case dangerousPayloadCannotBeApproved
    case approvalRequiredBeforeRunning
    case approvedPayloadChanged
    case terminalItemCannotTransition
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
        guard !item.containsDangerousPayload else {
            throw AssistantQueueTransitionError.dangerousPayloadCannotBeApproved
        }
        guard item.state != .done, item.state != .rejected else {
            throw AssistantQueueTransitionError.terminalItemCannotTransition
        }

        var approved = item
        approved.state = .approved
        // Queue approval records user intent only. Execution must still go
        // through ReviewSession/ActionExecutor so tool-level approval tokens
        // are minted at the existing execution gate, never here.
        approved.approval = AssistantQueueApprovalRecord(
            reviewerID: reviewerID,
            note: note,
            reviewedContentFingerprint: approved.contentFingerprint
        )
        return approved
    }

    public static func startRunning(_ item: AssistantQueueItem) throws -> AssistantQueueItem {
        guard item.state == .approved else {
            throw AssistantQueueTransitionError.approvalRequiredBeforeRunning
        }
        guard item.approval?.reviewedContentFingerprint == item.contentFingerprint else {
            throw AssistantQueueTransitionError.approvedPayloadChanged
        }

        var running = item
        running.state = .running
        return running
    }

    public static func reject(_ item: AssistantQueueItem) -> AssistantQueueItem {
        var rejected = item
        rejected.state = .rejected
        rejected.approval = nil
        return rejected
    }

    public static func deferItem(_ item: AssistantQueueItem) -> AssistantQueueItem {
        var deferred = item
        deferred.state = .deferred
        return deferred
    }

    public static func markEdited(_ item: AssistantQueueItem, reason: String) -> AssistantQueueItem {
        var edited = item
        edited.state = .waitingReview
        // Any post-approval edit changes the reviewed surface, so the queue
        // must drop approval and ask the user to review the edited item again.
        edited.approval = nil
        edited.reviewReason = reason
        return edited
    }
}

public enum AssistantQueueAdapter {
    public static func makeItem(
        actionPlan: ActionPlan,
        sourceTranscript: String?,
        interpretationSummary: String?,
        reason: String
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
            blockingReason: isDangerous ? "Dangerous action plans cannot be approved from Assistant Queue." : nil
        )
    }

    public static func makeItem(automationRequest: SyncAutomationRequestPayload) -> AssistantQueueItem {
        AssistantQueueItem(
            id: "automation-request:\(automationRequest.id)",
            state: state(for: automationRequest),
            payload: .automationRequest(automationRequest),
            riskLevel: .write,
            sourceTranscript: nil,
            interpretationSummary: automationRequest.toolName,
            reviewReason: reviewReason(for: automationRequest),
            redactedSummary: automationRequest.redactedArgumentSummary,
            requiredCapabilities: [.connectedMacRequired, .providerExecutionApproval]
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
}

private extension AssistantQueueItem {
    var contentFingerprint: String {
        [
            id,
            riskLevel.rawValue,
            redactedSummary,
            String(describing: payload),
            requiredCapabilities.map(String.init(describing:)).joined(separator: "|")
        ].joined(separator: "::")
    }

    var containsDangerousPayload: Bool {
        if riskLevel == .danger {
            return true
        }

        switch payload {
        case .actionPlan(let plan):
            return plan.riskLevel == .danger || plan.actions.contains { $0.riskLevel == .danger }
        case .automationRequest:
            return false
        }
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
