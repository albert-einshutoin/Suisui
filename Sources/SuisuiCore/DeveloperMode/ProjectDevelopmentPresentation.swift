import Foundation

public struct ProjectDevelopmentAutomationReadiness: Equatable, Sendable {
    public var projectID: Int64
    public var taskID: Int64?
    public var isReady: Bool
    public var statusLabel: String
    public var blockingReason: String?
    public var workspaceDisplayName: String?
    public var branchNamePreview: String?
    public var allowedFileOperations: [String]
    public var reviewSteps: [String]
    public var lifecycleToolNames: [String]
    public var approvalBoundaryLabel: String
    public var toolName: String

    public init(
        projectID: Int64,
        taskID: Int64?,
        isReady: Bool,
        statusLabel: String,
        blockingReason: String?,
        workspaceDisplayName: String?,
        branchNamePreview: String?,
        allowedFileOperations: [String],
        reviewSteps: [String],
        lifecycleToolNames: [String],
        approvalBoundaryLabel: String,
        toolName: String
    ) {
        self.projectID = projectID
        self.taskID = taskID
        self.isReady = isReady
        self.statusLabel = statusLabel
        self.blockingReason = blockingReason
        self.workspaceDisplayName = workspaceDisplayName
        self.branchNamePreview = branchNamePreview
        self.allowedFileOperations = allowedFileOperations
        self.reviewSteps = reviewSteps
        self.lifecycleToolNames = lifecycleToolNames
        self.approvalBoundaryLabel = approvalBoundaryLabel
        self.toolName = toolName
    }
}

public struct ProjectDevelopmentPullRequestCreationDraft: Equatable, Sendable {
    public var projectID: Int64
    public var taskID: Int64
    public var branchName: String
    public var baseBranch: String
    public var title: String
    public var body: String

    public init(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        baseBranch: String,
        title: String,
        body: String
    ) {
        self.projectID = projectID
        self.taskID = taskID
        self.branchName = branchName
        self.baseBranch = baseBranch
        self.title = title
        self.body = body
    }
}

public enum ProjectDevelopmentRepositoryEditOperation: String, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    case create
    case update

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .create:
            return String(localized: "Create project file")
        case .update:
            return String(localized: "Update project file")
        }
    }

    public var tool: ActionTool {
        switch self {
        case .create:
            return .developmentRepositoryCreateFile
        case .update:
            return .developmentRepositoryUpdateFile
        }
    }
}

public enum ProjectDevelopmentAutomationProgressStageStatus: String, Equatable, Sendable {
    case waiting
    case ready
    case succeeded
    case failed

    public var label: String {
        switch self {
        case .waiting:
            return String(localized: "Waiting")
        case .ready:
            return String(localized: "Ready")
        case .succeeded:
            return String(localized: "Done")
        case .failed:
            return String(localized: "Failed")
        }
    }
}

public struct ProjectDevelopmentAutomationProgressStage: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var status: ProjectDevelopmentAutomationProgressStageStatus
    public var detail: String?

    public init(
        id: String,
        title: String,
        status: ProjectDevelopmentAutomationProgressStageStatus,
        detail: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

public struct ProjectDevelopmentAutomationNextApproval: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct ProjectDevelopmentAutomationQueueHandoff: Identifiable, Equatable, Sendable {
    public var id: String
    public var state: AssistantQueueState
    public var stateLabel: String
    public var title: String
    public var reviewReason: String
    public var capabilityLabels: [String]
    public var latestReceiptStatusLabel: String?
    public var canApprove: Bool
    public var canRun: Bool

    public init(
        id: String,
        state: AssistantQueueState,
        stateLabel: String,
        title: String,
        reviewReason: String,
        capabilityLabels: [String],
        latestReceiptStatusLabel: String?,
        canApprove: Bool,
        canRun: Bool
    ) {
        self.id = id
        self.state = state
        self.stateLabel = stateLabel
        self.title = title
        self.reviewReason = reviewReason
        self.capabilityLabels = capabilityLabels
        self.latestReceiptStatusLabel = latestReceiptStatusLabel
        self.canApprove = canApprove
        self.canRun = canRun
    }
}

public struct ProjectDevelopmentAutomationApprovalPreviewRow: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var value: String

    public init(id: String, label: String, value: String) {
        self.id = id
        self.label = label
        self.value = value
    }
}

public struct ProjectDevelopmentAutomationApprovalPreview: Equatable, Sendable {
    public var title: String
    public var rows: [ProjectDevelopmentAutomationApprovalPreviewRow]

    public init(title: String, rows: [ProjectDevelopmentAutomationApprovalPreviewRow]) {
        self.title = title
        self.rows = rows
    }
}

public struct ProjectDevelopmentAutomationProgress: Equatable, Sendable {
    public var projectID: Int64
    public var taskID: Int64?
    public var branchName: String?
    public var pullRequestURL: String?
    public var baseBranch: String?
    public var latestCommitOID: String?
    public var stages: [ProjectDevelopmentAutomationProgressStage]
    public var canQueueRepositoryEditReview: Bool
    public var canQueueVerificationReview: Bool
    public var canQueueCommitReview: Bool
    public var canQueueBranchPushReview: Bool
    public var canQueuePullRequestCreationReview: Bool
    public var canQueuePullRequestReviewGate: Bool
    public var canQueuePullRequestMergeGate: Bool
    public var blockingReason: String?
    public var nextApproval: ProjectDevelopmentAutomationNextApproval?
    public var approvalPreview: ProjectDevelopmentAutomationApprovalPreview?
    public var queueHandoff: ProjectDevelopmentAutomationQueueHandoff?

    public init(
        projectID: Int64,
        taskID: Int64?,
        branchName: String?,
        pullRequestURL: String?,
        baseBranch: String?,
        latestCommitOID: String?,
        stages: [ProjectDevelopmentAutomationProgressStage],
        canQueueRepositoryEditReview: Bool = false,
        canQueueVerificationReview: Bool,
        canQueueCommitReview: Bool,
        canQueueBranchPushReview: Bool,
        canQueuePullRequestCreationReview: Bool,
        canQueuePullRequestReviewGate: Bool,
        canQueuePullRequestMergeGate: Bool,
        blockingReason: String?,
        nextApproval: ProjectDevelopmentAutomationNextApproval?,
        approvalPreview: ProjectDevelopmentAutomationApprovalPreview? = nil,
        queueHandoff: ProjectDevelopmentAutomationQueueHandoff? = nil
    ) {
        self.projectID = projectID
        self.taskID = taskID
        self.branchName = branchName
        self.pullRequestURL = pullRequestURL
        self.baseBranch = baseBranch
        self.latestCommitOID = latestCommitOID
        self.stages = stages
        self.canQueueRepositoryEditReview = canQueueRepositoryEditReview
        self.canQueueVerificationReview = canQueueVerificationReview
        self.canQueueCommitReview = canQueueCommitReview
        self.canQueueBranchPushReview = canQueueBranchPushReview
        self.canQueuePullRequestCreationReview = canQueuePullRequestCreationReview
        self.canQueuePullRequestReviewGate = canQueuePullRequestReviewGate
        self.canQueuePullRequestMergeGate = canQueuePullRequestMergeGate
        self.blockingReason = blockingReason
        self.nextApproval = nextApproval
        self.approvalPreview = approvalPreview
        self.queueHandoff = queueHandoff
    }
}
