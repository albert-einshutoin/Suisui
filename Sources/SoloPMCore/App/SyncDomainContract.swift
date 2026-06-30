import Foundation

public struct SyncDomainPayload: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var projects: [SyncProjectPayload]
    public var tasks: [SyncTaskPayload]
    public var conversations: [SyncConversationPayload]
    public var documents: [SyncDocumentPayload]
    public var actionPlans: [SyncActionPlanPayload]
    public var automationRequests: [SyncAutomationRequestPayload]
    public var harnessRuns: [SyncHarnessRunPayload]

    public init(
        schemaVersion: Int = 1,
        projects: [SyncProjectPayload],
        tasks: [SyncTaskPayload],
        conversations: [SyncConversationPayload] = [],
        documents: [SyncDocumentPayload] = [],
        actionPlans: [SyncActionPlanPayload] = [],
        automationRequests: [SyncAutomationRequestPayload] = [],
        harnessRuns: [SyncHarnessRunPayload] = []
    ) {
        self.schemaVersion = schemaVersion
        self.projects = projects
        self.tasks = tasks
        self.conversations = conversations
        self.documents = documents
        self.actionPlans = actionPlans
        self.automationRequests = automationRequests
        self.harnessRuns = harnessRuns
    }
}

public struct SyncProjectPayload: Codable, Equatable, Sendable {
    public var id: Int64
    public var title: String
    public var status: String
    public var priority: String?
    public var deadline: String?
    public var tags: [String]
    public var sourceCommand: String?

    public init(
        id: Int64,
        title: String,
        status: String,
        priority: String?,
        deadline: String?,
        tags: [String],
        sourceCommand: String?
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.deadline = deadline
        self.tags = tags
        self.sourceCommand = sourceCommand
    }
}

public struct SyncTaskPayload: Codable, Equatable, Sendable {
    public var id: Int64
    public var projectID: Int64?
    public var title: String
    public var detail: String
    public var status: String
    public var dueAt: String?
    public var priority: String?
    public var sourceCommand: String?
    public var auditMetadata: SyncTaskAuditMetadata

    public init(
        id: Int64,
        projectID: Int64?,
        title: String,
        detail: String,
        status: String,
        dueAt: String?,
        priority: String?,
        sourceCommand: String?,
        auditMetadata: SyncTaskAuditMetadata
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.detail = detail
        self.status = status
        self.dueAt = dueAt
        self.priority = priority
        self.sourceCommand = sourceCommand
        self.auditMetadata = auditMetadata
    }
}

public struct SyncTaskAuditMetadata: Codable, Equatable, Sendable {
    public var source: SyncMutationSource
    public var sourceCommand: String?

    public init(source: SyncMutationSource, sourceCommand: String?) {
        self.source = source
        self.sourceCommand = sourceCommand
    }
}

public enum SyncMutationSource: String, Codable, Equatable, Sendable {
    case localDatabase
    case conversation
    case hostedMCP
    case cloudRelay
}

public enum SyncTaskMutationOperation: String, Codable, Equatable, Sendable {
    case create
    case update
    case complete
    case moveProject
    case updateDueDate
}

public enum SyncApprovalState: String, Codable, Equatable, Sendable {
    case notRequired
    case pendingApproval
    case approved
    case rejected
}

public struct SyncTaskMutationPayload: Codable, Equatable, Sendable {
    public var taskID: Int64?
    public var operation: SyncTaskMutationOperation
    public var title: String?
    public var detail: String?
    public var status: String?
    public var projectID: Int64?
    public var dueAt: String?
    public var priority: String?
    public var source: SyncMutationSource
    public var approvalState: SyncApprovalState

    public init(
        taskID: Int64? = nil,
        operation: SyncTaskMutationOperation,
        title: String? = nil,
        detail: String? = nil,
        status: String? = nil,
        projectID: Int64? = nil,
        dueAt: String? = nil,
        priority: String? = nil,
        source: SyncMutationSource,
        approvalState: SyncApprovalState
    ) {
        self.taskID = taskID
        self.operation = operation
        self.title = title
        self.detail = detail
        self.status = status
        self.projectID = projectID
        self.dueAt = dueAt
        self.priority = priority
        self.source = source
        self.approvalState = approvalState
    }
}

public struct SyncConversationPayload: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var createdAt: String?

    public init(id: String, title: String, createdAt: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}

public struct SyncDocumentPayload: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var scope: String
    public var redactedSummary: String

    public init(id: String, title: String, scope: String, redactedSummary: String) {
        self.id = id
        self.title = title
        self.scope = scope
        self.redactedSummary = redactedSummary
    }
}

public struct SyncActionPlanPayload: Codable, Equatable, Sendable {
    public var id: String
    public var summary: String
    public var approvalState: SyncApprovalState

    public init(id: String, summary: String, approvalState: SyncApprovalState) {
        self.id = id
        self.summary = summary
        self.approvalState = approvalState
    }
}

public enum SyncDevelopmentPullRequestOperation: String, Codable, Equatable, Sendable {
    case reviewGate
    case merge
}

public struct SyncDevelopmentPullRequestPayload: Codable, Equatable, Sendable {
    public var projectID: Int64
    public var operation: SyncDevelopmentPullRequestOperation
    public var pullRequestURL: String
    public var branchName: String
    public var baseBranch: String

    public init(
        projectID: Int64,
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String
    ) {
        self.projectID = projectID
        self.operation = operation
        self.pullRequestURL = pullRequestURL
        self.branchName = branchName
        self.baseBranch = baseBranch
    }
}

public struct SyncAutomationRequestPayload: Codable, Equatable, Sendable {
    public var id: String
    public var source: SyncMutationSource
    public var approvalState: SyncApprovalState
    public var sourceClientID: String?
    public var toolName: String?
    public var redactedArgumentSummary: String
    public var taskMutation: SyncTaskMutationPayload?
    public var developmentPullRequest: SyncDevelopmentPullRequestPayload?

    public init(
        id: String,
        source: SyncMutationSource,
        approvalState: SyncApprovalState,
        sourceClientID: String? = nil,
        toolName: String? = nil,
        redactedArgumentSummary: String = "",
        taskMutation: SyncTaskMutationPayload? = nil,
        developmentPullRequest: SyncDevelopmentPullRequestPayload? = nil
    ) {
        self.id = id
        self.source = source
        self.approvalState = approvalState
        self.sourceClientID = sourceClientID
        self.toolName = toolName
        self.redactedArgumentSummary = redactedArgumentSummary
        self.taskMutation = taskMutation
        self.developmentPullRequest = developmentPullRequest
    }
}

public struct SyncHarnessRunPayload: Codable, Equatable, Sendable {
    public var id: String
    public var scenario: String
    public var status: String
    public var scenarioKind: String?
    public var trigger: String?
    public var failureReason: String?
    public var diffSummary: String?
    public var redactedLogCount: Int

    public init(
        id: String,
        scenario: String,
        status: String,
        scenarioKind: String? = nil,
        trigger: String? = nil,
        failureReason: String? = nil,
        diffSummary: String? = nil,
        redactedLogCount: Int = 0
    ) {
        self.id = id
        self.scenario = scenario
        self.status = status
        self.scenarioKind = scenarioKind
        self.trigger = trigger
        self.failureReason = failureReason
        self.diffSummary = diffSummary
        self.redactedLogCount = redactedLogCount
    }
}

public enum SyncDomainPayloadAdapter {
    public static func payload(projects: [ProjectRecord], tasks: [TaskRecord]) -> SyncDomainPayload {
        SyncDomainPayload(
            projects: projects.map(projectPayload),
            tasks: tasks.map(taskPayload)
        )
    }

    private static func projectPayload(_ project: ProjectRecord) -> SyncProjectPayload {
        SyncProjectPayload(
            id: project.id,
            title: project.title,
            status: project.status,
            priority: project.priority,
            deadline: project.deadline,
            tags: project.tags,
            sourceCommand: redacted(project.sourceCommand)
        )
    }

    private static func taskPayload(_ task: TaskRecord) -> SyncTaskPayload {
        let sourceCommand = redacted(task.sourceCommand)
        return SyncTaskPayload(
            id: task.id,
            projectID: task.projectID,
            title: task.title,
            detail: task.detail ?? "",
            status: task.status,
            dueAt: task.dueAt,
            priority: task.priority,
            sourceCommand: sourceCommand,
            auditMetadata: SyncTaskAuditMetadata(source: .localDatabase, sourceCommand: sourceCommand)
        )
    }

    private static func redacted(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        // Sync payloads may leave the local device, so user-originated commands are redacted here instead of relying only on downstream transport logging.
        return DeveloperSecretRedactor().redact(value).text
    }
}
