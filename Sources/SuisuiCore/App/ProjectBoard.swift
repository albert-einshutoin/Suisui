import Combine
import CryptoKit
import Foundation
import os

private let projectBoardRuntimeDiagnosticLogger = Logger(subsystem: "dev.suisui.app", category: "runtime")

private enum GoogleCalendarReadinessRefreshResult: Sendable {
    case success(GoogleCalendarRuntimeSyncStatus)
    case failure(String)
}

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

public struct TaskAutomationDocumentSourceReview: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var redactedSummary: String
    public var inclusionReason: String

    public init(id: String, title: String, redactedSummary: String, inclusionReason: String) {
        let redactor = DeveloperSecretRedactor()
        self.id = redactor.redact(id).text
        self.title = redactor.redact(title).text
        self.redactedSummary = redactor.redact(redactedSummary).text
        self.inclusionReason = redactor.redact(inclusionReason).text
    }
}

public struct TaskAutomationDocumentDeliverableReview: Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: DocumentAutomationOutputKind
    public var title: String
    public var suggestedPath: String
    public var sourceDocuments: [TaskAutomationDocumentSourceReview]
    public var rationale: String
    public var riskLevel: RiskLevel
    public var requiresApproval: Bool

    public init(
        kind: DocumentAutomationOutputKind,
        title: String,
        suggestedPath: String,
        sourceDocuments: [TaskAutomationDocumentSourceReview],
        rationale: String,
        riskLevel: RiskLevel,
        requiresApproval: Bool
    ) {
        let redactor = DeveloperSecretRedactor()
        self.kind = kind
        self.title = redactor.redact(title).text
        self.suggestedPath = redactor.redact(suggestedPath).text
        self.sourceDocuments = sourceDocuments
        self.rationale = redactor.redact(rationale).text
        self.riskLevel = riskLevel
        self.requiresApproval = requiresApproval
        self.id = [kind.rawValue, self.suggestedPath].joined(separator: ":")
    }
}

public enum ScheduleApplyResult: Equatable, Sendable {
    case approvalRequired
    case calendarNotConfigured
    case noDraft
    case applied(eventCount: Int)
    case failed(String)
}

public struct ProjectAssistantAnswer: Equatable, Sendable {
    public var projectID: Int64
    public var question: String
    public var message: String
    public var suggestedActionTitle: String
    public var requiresReview: Bool

    public init(projectID: Int64, question: String, message: String, suggestedActionTitle: String, requiresReview: Bool) {
        self.projectID = projectID
        self.question = question
        self.message = message
        self.suggestedActionTitle = suggestedActionTitle
        self.requiresReview = requiresReview
    }
}

public struct ProjectAssistantReviewDraft: Equatable, Sendable {
    public var projectID: Int64
    public var suggestedActionTitle: String
    public var summary: String

    public init(projectID: Int64, suggestedActionTitle: String, summary: String) {
        self.projectID = projectID
        self.suggestedActionTitle = suggestedActionTitle
        self.summary = summary
    }
}

public struct ProjectBoardSidebarMetrics: Equatable, Sendable {
    public var inboxCount: Int
    public var todayCount: Int
    public var catchUpCount: Int
    public var scheduleCount: Int
    public var doneCount: Int
    public var projectsCount: Int

    public init(
        inboxCount: Int,
        todayCount: Int,
        catchUpCount: Int,
        scheduleCount: Int,
        doneCount: Int,
        projectsCount: Int
    ) {
        self.inboxCount = inboxCount
        self.todayCount = todayCount
        self.catchUpCount = catchUpCount
        self.scheduleCount = scheduleCount
        self.doneCount = doneCount
        self.projectsCount = projectsCount
    }

    public static let empty = ProjectBoardSidebarMetrics(
        inboxCount: 0,
        todayCount: 0,
        catchUpCount: 0,
        scheduleCount: 0,
        doneCount: 0,
        projectsCount: 0
    )
}

public struct ProjectBoardScheduleReadModel: Equatable, Sendable {
    public var workloadOverview: DailyWorkloadOverview
    public var weeklyCockpit: WeeklyScheduleCockpit
    public var unscheduledTasks: [ProjectBoardTask]

    public init(
        workloadOverview: DailyWorkloadOverview,
        weeklyCockpit: WeeklyScheduleCockpit,
        unscheduledTasks: [ProjectBoardTask]
    ) {
        self.workloadOverview = workloadOverview
        self.weeklyCockpit = weeklyCockpit
        self.unscheduledTasks = unscheduledTasks
    }

    public static let empty = ProjectBoardScheduleReadModel(
        workloadOverview: DailyWorkloadOverview(days: [], unscheduledTasks: [], inboxUntriagedCount: 0),
        weeklyCockpit: WeeklyScheduleCockpit(
            days: [],
            unscheduledTasks: [],
            agendaDay: nil,
            focusForecast: WeeklyScheduleFocusForecast(
                state: .open,
                overloadedDayKeys: [],
                heavyDayKeys: [],
                reminderProposalCount: 0
            )
        ),
        unscheduledTasks: []
    )
}

public struct ProjectBoardDerivedReadModels: Equatable, Sendable {
    public var sidebarMetrics: ProjectBoardSidebarMetrics
    public var todayWorkflowSnapshot: TodayWorkflowSnapshot
    public var schedule: ProjectBoardScheduleReadModel
    public var doneAnalytics: DoneAnalyticsSummary
    public var missedTaskReview: MissedTaskReviewSummary
    public var projectPortfolioSummaries: [ProjectPortfolioSummary]
    public var builtAt: Date

    public init(
        sidebarMetrics: ProjectBoardSidebarMetrics,
        todayWorkflowSnapshot: TodayWorkflowSnapshot,
        schedule: ProjectBoardScheduleReadModel,
        doneAnalytics: DoneAnalyticsSummary,
        missedTaskReview: MissedTaskReviewSummary,
        projectPortfolioSummaries: [ProjectPortfolioSummary],
        builtAt: Date
    ) {
        self.sidebarMetrics = sidebarMetrics
        self.todayWorkflowSnapshot = todayWorkflowSnapshot
        self.schedule = schedule
        self.doneAnalytics = doneAnalytics
        self.missedTaskReview = missedTaskReview
        self.projectPortfolioSummaries = projectPortfolioSummaries
        self.builtAt = builtAt
    }

    public static let empty = ProjectBoardDerivedReadModels(
        sidebarMetrics: .empty,
        todayWorkflowSnapshot: TodayWorkflowSnapshot(
            plan: TodayWorkflowPlan(
                tasks: [],
                overdueCount: 0,
                dueTodayCount: 0,
                recommendedTask: nil,
                recommendationReason: "No open tasks due today.",
                timeBlocks: []
            ),
            assistantContext: TodayAssistantRailContext(
                source: .empty,
                task: nil,
                projectTitle: "Today",
                nextActionTitle: "No open tasks due today",
                nextActionReason: "Captured work remains in Inbox until it is scheduled or moved to a project.",
                nextBlockLabel: nil,
                notes: "",
                subtaskSummary: "No subtasks",
                reminderSummary: "No reminders"
            ),
            recommendationChips: []
        ),
        schedule: .empty,
        doneAnalytics: DoneAnalyticsSummary(
            completedTaskCount: 0,
            completedProjectCount: 0,
            completedTodayCount: 0,
            completedThisWeekCount: 0,
            streakDays: 0,
            recentTasks: [],
            localRuleInsight: "Done analytics uses local completed_at history; reopened tasks remain visible in completion history."
        ),
        missedTaskReview: .empty,
        projectPortfolioSummaries: [],
        builtAt: Date(timeIntervalSince1970: 0)
    )
}

public extension TodayWorkflowPlan {
    func primaryActionPresentation(commandText: String) -> TodayPrimaryActionPresentation {
        TodayPrimaryActionPresentation.make(
            recommendedTaskID: recommendedTask?.id,
            recommendedTaskTitle: recommendedTask?.title,
            commandText: commandText,
            taskCount: tasks.count
        )
    }
}

private struct ProjectBoardDerivedReadModelInputs {
    var nonArchivedProjects: [ProjectBoardProject]
    var committedActiveProjects: [ProjectBoardProject]
    var portfolioProjects: [ProjectBoardProject]
    var completedProjects: [ProjectBoardProject]
    var inboxProject: ProjectBoardProject?
    var inboxTasks: [ProjectBoardTask]
    var inboxUntriagedCount: Int
    var visibleNonArchivedTasks: [ProjectBoardTask]
    var nonArchivedTasks: [ProjectBoardTask]

    init(
        snapshot: ProjectBoardSnapshot,
        showsCompletedWorkflowTasks: Bool,
        inboxUntriagedCountOverride: Int? = nil
    ) {
        let nonArchivedProjects = snapshot.projects.filter { !$0.isArchived }
        let activeProjects = nonArchivedProjects.filter { !$0.isCompleted }
        let inboxProject = nonArchivedProjects.first(where: Self.isInboxProject)

        self.nonArchivedProjects = nonArchivedProjects
        // Inbox is intake, not committed work; Catch Up should not make raw captures
        // look like forgotten tasks before the user triages them into a project.
        self.committedActiveProjects = activeProjects.filter { !Self.isInboxProject($0) }
        self.portfolioProjects = nonArchivedProjects.filter { !Self.isInboxProject($0) }
        self.completedProjects = nonArchivedProjects.filter { $0.isCompleted && !Self.isInboxProject($0) }
        self.inboxProject = inboxProject
        self.inboxTasks = inboxProject?
            .tasks
            .filter { showsCompletedWorkflowTasks || $0.status != .done }
            .sorted { $0.id > $1.id } ?? []
        self.inboxUntriagedCount = inboxUntriagedCountOverride
            ?? inboxProject?.tasks.filter { $0.status != .done }.count
            ?? 0
        self.nonArchivedTasks = nonArchivedProjects.flatMap(\.tasks)
        // Rebuilds need several workflow projections. Flattening once keeps a
        // large local board from paying the same project/task traversal for
        // Today, Done, Catch Up, and sidebar counts during a single refresh.
        self.visibleNonArchivedTasks = self.nonArchivedTasks.filter { showsCompletedWorkflowTasks || $0.status != .done }
    }

    private static func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }
}

public enum TodaySnapshotInvalidationReason: String, Sendable {
    case storeReload
    case taskMutation
    case projectMutation
    case completedVisibilityChanged
    case dateBoundaryChanged
    case timezoneOrCalendarChanged
}

@MainActor
public final class ProjectBoardViewModel: ObservableObject {
    private static let doneAnalyticsHeatmapWindowDays = 28

    private enum ProjectBoardFailureRetryAction {
        case load
        case saveTask(taskID: Int64, draft: ProjectBoardTaskDraft)
        case createTask(ProjectBoardTaskDraft)
        case createProject(title: String)
        case updateProject(id: Int64, title: String)
        case completeProject(id: Int64)
        case archiveProject(id: Int64)
        case restoreProject(id: Int64)
        case deleteProject(id: Int64)
        case deleteTask(id: Int64)
        case moveTask(id: Int64, status: ProjectTaskStatus)
        case syncGoogleCalendar(approvalToken: String?)
    }

    @Published public private(set) var snapshot: ProjectBoardSnapshot
    @Published public private(set) var derivedReadModels: ProjectBoardDerivedReadModels
    @Published public var selectedProjectID: Int64?
    @Published public var selectedTaskID: Int64? {
        didSet {
            guard oldValue != selectedTaskID else { return }
            refreshTodayDerivedReadModelForSelectionChange()
        }
    }
    @Published public private(set) var showsArchivedProjects: Bool
    @Published public private(set) var showsCompletedWorkflowTasks: Bool
    @Published public private(set) var errorMessage: String? {
        didSet {
            guard !isSynchronizingFailure else { return }
            if let errorMessage {
                // Legacy operation sites still publish through errorMessage.
                // Classify them as recoverable saves and offer a safe reload;
                // origin-specific paths replace this immediately with richer context.
                let redactedMessage = LocalPathRedactor.redact(
                    UserFacingErrorMessageSanitizer.message(
                        from: errorMessage,
                        fallback: String(localized: "Project board unavailable")
                    )
                )
                if redactedMessage != errorMessage {
                    isSynchronizingFailure = true
                    self.errorMessage = redactedMessage
                    isSynchronizingFailure = false
                }
                failure = .saveFailed(redactedMessage)
                failureTaskID = nil
                failureRetryAction = .load
            } else {
                failure = nil
                failureTaskID = nil
                failureRetryAction = nil
            }
        }
    }
    // A successful mutation reload must not clear a provider failure that was
    // raised by that same reload. Keep the result separate from `failure`,
    // which may intentionally represent an earlier recoverable operation.
    private var didLastLoadFail = false
    @Published public private(set) var failure: ProjectBoardFailure?
    @Published public private(set) var integrationStatusMessage: String?
    @Published public private(set) var inboxClassificationFeedback: InboxClassificationFeedback?
    @Published public private(set) var inboxTriageErrorMessage: String?
    // Board-operation undo is deliberately separate from the Inbox
    // classification undo below: classification keeps its guided single-step
    // flow while this stack owns general task mutations (complete, status
    // move, edit, delete) for ⌘Z and the Edit-menu command.
    @Published public private(set) var boardOperationUndo: BoardOperationUndoStack
    @Published public private(set) var boardUndoFeedback: String?
    @Published public private(set) var inboxTriageFilter: InboxTriageFilter
    @Published public private(set) var todayCommandFeedback: String?
    @Published public private(set) var todayFocusTaskID: Int64? {
        didSet {
            guard oldValue != todayFocusTaskID else { return }
            refreshTodayDerivedReadModelForSelectionChange()
        }
    }
    @Published public private(set) var todayScheduleDraft: TodayScheduleDraft?
    @Published public private(set) var dailyPlanningReview: DailyPlanningReview?
    @Published public private(set) var scheduleDraft: ScheduleDraft?
    @Published public private(set) var scheduleApplyResult: ScheduleApplyResult?
    @Published public private(set) var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus
    @Published public private(set) var externalScheduleEvents: [ExternalScheduleEvent]
    @Published public private(set) var externalScheduleEventLoadState: ExternalScheduleEventLoadState
    @Published public private(set) var projectAssistantAnswer: ProjectAssistantAnswer?
    @Published public private(set) var projectAssistantReviewDraft: ProjectAssistantReviewDraft?
    @Published public private(set) var developmentAutomationReviewPlan: ActionPlan?
    @Published public private(set) var taskAutomationReviewDecision: TaskAutoExecutionDecision?
    @Published public private(set) var taskAutomationDocumentDeliverableReviews: [TaskAutomationDocumentDeliverableReview]
    @Published public private(set) var lastApprovedAutomationExecutionReceipt: ApprovedAutomationExecutionReceipt?
    @Published public private(set) var approvedAutomationExecutionReceipts: [ApprovedAutomationExecutionReceipt]
    @Published public private(set) var assistantQueueSnapshot: AssistantQueueSnapshot
    @Published public private(set) var assistantQueueViewFilter: AssistantQueueViewFilter
    @Published public private(set) var assistantQueueSort: AssistantQueueSort
    @Published public private(set) var assistantQueueSelectedItemIDs: Set<String>
    @Published public private(set) var isApprovingAllRescheduleSuggestions = false
    @Published public private(set) var executionReceiptHistorySnapshot: ExecutionReceiptHistorySnapshot
    @Published public private(set) var executionReceiptHistorySearchText: String
    @Published public private(set) var executionReceiptHistoryStatusFilter: ExecutionReceiptStatus?
    @Published public private(set) var executionReceiptHistoryReferenceKindFilter: ExecutionReceiptReferenceKind?
    @Published public private(set) var executionReceiptHistoryExportData: Data?
    @Published public private(set) var executionReceiptHistoryExportMessage: String?
    @Published public private(set) var executionUsageMeterSnapshot: ExecutionUsageMeterSnapshot

    private let store: any ProjectBoardStore
    private let inboxCaptureStore: (any InboxCaptureStore)?
    private let assistantQueueStore: (any AssistantQueueStore)?
    private var assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator?
    private let assistantQueueExecutionCoordinatorFactory: (() -> AssistantQueueExecutionCoordinator?)?
    private let executionReceiptStore: (any ExecutionReceiptStore)?
    private let missedTaskReviewStateStore: any MissedTaskReviewStateStore
    private let missedTaskFollowUpNotificationClient: (any NotificationClient)?
    private let externalTaskLinkStore: (any ExternalTaskLinkStore)?
    private let scheduleCalendarClient: (any CalendarClient)?
    private let externalScheduleEventSource: (any ExternalScheduleEventSource)?
    private var googleCalendarSync: (any GoogleCalendarRuntimeSyncing)?
    private let googleCalendarSyncFactory: (() -> (any GoogleCalendarRuntimeSyncing)?)?
    private let onChange: () -> Void
    private var lastInboxClassificationUndo: InboxClassificationUndo?
    private var boardUndoFeedbackClearTask: Task<Void, Never>?
    // Inbox rows render often during filtering and selection changes, so capture
    // metadata is cached at board load time instead of hitting SQLite from SwiftUI body rendering.
    private var inboxCaptureRecordsByTaskID: [Int64: [InboxCaptureRecord]]
    // Triage disposition is authoritative for Inbox filtering. Keeping it beside
    // the capture cache lets row rendering distinguish an explicitly accepted
    // Task from a raw, still-unprocessed capture without issuing store reads.
    private var inboxTriageRecordsByTaskID: [Int64: InboxTriageRecord]
    // Review Later visibility is a derived time boundary. Tests and the minute
    // UI refresh inject this value so filtering stays deterministic and pure.
    private var inboxVisibilityReferenceDate: Date?
    // Inspector receipt rows are cached as redacted read-model snapshots so
    // SwiftUI rendering never performs file I/O or holds raw receipt details.
    private var executionReceiptHistorySnapshotsByTaskID: [Int64: ExecutionReceiptHistorySnapshot]
    private var executionReceiptHistorySnapshotsByProjectID: [Int64: ExecutionReceiptHistorySnapshot]
    // Done/audit receipts can live in a large file-backed store. Project Board
    // startup defers those global reads until the Done workflow is actually
    // visible while still letting receipt writes refresh an already-open audit view.
    private var executionReceiptAuditSnapshotsLoaded: Bool
    // Selection changes only affect the Today rail context. Keeping the last
    // build context lets us refresh that slice without recomputing sidebar,
    // schedule, done, or portfolio read models for every row selection.
    private let readModelNow: () -> Date
    private let readModelCalendarProvider: () -> Calendar
    private var derivedReadModelReferenceDate: Date?
    private var derivedReadModelCalendar: Calendar
    // The preview is a derived value, not authoritative review state. The key
    // prevents SwiftUI re-evaluation and selection-only updates from rebuilding
    // the same review while still forcing a new value after board data changes.
    private var dailyPlanningReviewPreviewCache: DailyPlanningReviewPreviewCache
    // Keep this revision stable when an external change notification causes a
    // second load of the same snapshot; otherwise one mutation invalidates the
    // preview twice before SwiftUI has a chance to consume the first result.
    private(set) var todaySnapshotSourceRevision: UInt64
    // Keep this counter beside the cache so only real builder executions are
    // counted; SwiftUI body re-evaluation must not create diagnostic work.
    private(set) var dailyPlanningReviewPreviewBuildCount: Int
    private var taskAutomationSessionHistory: TaskAutoExecutionHistory
    private var hasLoadedBoardSnapshot: Bool
    private var failureRetryAction: ProjectBoardFailureRetryAction?
    private var failureTaskID: Int64?
    private var isSynchronizingFailure: Bool
    private let hasPreloadedGoogleCalendarSyncStatus: Bool
    private var googleCalendarReadinessRefreshRevision: UInt64
    private var externalScheduleEventRefreshRevision: UInt64
    private var externalScheduleEventInterval: DateInterval?
    private var googleCalendarReadinessNotificationObservation: AnyCancellable?

    public init(
        store: any ProjectBoardStore,
        inboxCaptureStore: (any InboxCaptureStore)? = nil,
        assistantQueueStore: (any AssistantQueueStore)? = nil,
        assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator? = nil,
        assistantQueueExecutionCoordinatorFactory: (() -> AssistantQueueExecutionCoordinator?)? = nil,
        executionReceiptStore: (any ExecutionReceiptStore)? = nil,
        missedTaskReviewStateStore: any MissedTaskReviewStateStore = VolatileMissedTaskReviewStateStore(),
        missedTaskFollowUpNotificationClient: (any NotificationClient)? = nil,
        externalTaskLinkStore: (any ExternalTaskLinkStore)? = nil,
        scheduleCalendarClient: (any CalendarClient)? = nil,
        externalScheduleEventSource: (any ExternalScheduleEventSource)? = nil,
        googleCalendarSync: (any GoogleCalendarRuntimeSyncing)? = nil,
        initialGoogleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus? = nil,
        googleCalendarSyncFactory: (() -> (any GoogleCalendarRuntimeSyncing)?)? = nil,
        readModelNow: @escaping () -> Date = { VisualEvidenceRuntimeContext.referenceDate() },
        readModelCalendar: @escaping () -> Calendar = { VisualEvidenceRuntimeContext.runtimeCalendar() },
        snapshot: ProjectBoardSnapshot = .empty,
        onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.inboxCaptureStore = inboxCaptureStore
        self.assistantQueueStore = assistantQueueStore
        self.assistantQueueExecutionCoordinator = assistantQueueExecutionCoordinator
        self.assistantQueueExecutionCoordinatorFactory = assistantQueueExecutionCoordinatorFactory
        self.executionReceiptStore = executionReceiptStore
        self.missedTaskReviewStateStore = missedTaskReviewStateStore
        self.missedTaskFollowUpNotificationClient = missedTaskFollowUpNotificationClient
        self.externalTaskLinkStore = externalTaskLinkStore
        self.scheduleCalendarClient = scheduleCalendarClient
        self.externalScheduleEventSource = externalScheduleEventSource
        self.googleCalendarSync = googleCalendarSync
        self.googleCalendarSyncFactory = googleCalendarSyncFactory
        self.readModelNow = readModelNow
        self.readModelCalendarProvider = readModelCalendar
        self.snapshot = snapshot
        self.derivedReadModels = .empty
        self.onChange = onChange
        self.selectedProjectID = snapshot.projects.first?.id
        self.showsArchivedProjects = false
        self.showsCompletedWorkflowTasks = false
        self.inboxTriageFilter = .unprocessed
        self.boardOperationUndo = BoardOperationUndoStack()
        self.boardUndoFeedback = nil
        self.todayCommandFeedback = nil
        self.inboxCaptureRecordsByTaskID = [:]
        self.inboxTriageRecordsByTaskID = [:]
        self.inboxVisibilityReferenceDate = nil
        self.todayFocusTaskID = nil
        self.todayScheduleDraft = nil
        self.dailyPlanningReview = nil
        self.scheduleDraft = nil
        self.scheduleApplyResult = nil
        self.googleCalendarSyncStatus = initialGoogleCalendarSyncStatus ?? .runtimeNotConfigured
        self.externalScheduleEvents = []
        self.externalScheduleEventLoadState = externalScheduleEventSource == nil ? .unavailable : .loading
        self.projectAssistantAnswer = nil
        self.projectAssistantReviewDraft = nil
        self.developmentAutomationReviewPlan = nil
        self.taskAutomationReviewDecision = nil
        self.taskAutomationDocumentDeliverableReviews = []
        self.lastApprovedAutomationExecutionReceipt = nil
        self.approvedAutomationExecutionReceipts = []
        self.assistantQueueSnapshot = .empty
        self.assistantQueueViewFilter = .needsAttention
        self.assistantQueueSort = .needsActionFirst
        self.assistantQueueSelectedItemIDs = []
        self.executionReceiptHistorySnapshot = .empty
        self.executionReceiptHistorySearchText = ""
        self.executionReceiptHistoryStatusFilter = nil
        self.executionReceiptHistoryReferenceKindFilter = nil
        self.executionReceiptHistoryExportData = nil
        self.executionReceiptHistoryExportMessage = nil
        self.executionUsageMeterSnapshot = .empty
        self.executionReceiptHistorySnapshotsByTaskID = [:]
        self.executionReceiptHistorySnapshotsByProjectID = [:]
        self.executionReceiptAuditSnapshotsLoaded = false
        self.derivedReadModelReferenceDate = nil
        self.derivedReadModelCalendar = readModelCalendar()
        self.dailyPlanningReviewPreviewCache = DailyPlanningReviewPreviewCache()
        self.todaySnapshotSourceRevision = 0
        self.dailyPlanningReviewPreviewBuildCount = 0
        self.taskAutomationSessionHistory = .empty
        self.failure = nil
        self.hasLoadedBoardSnapshot = !snapshot.projects.isEmpty
        self.failureRetryAction = nil
        self.failureTaskID = nil
        self.isSynchronizingFailure = false
        self.hasPreloadedGoogleCalendarSyncStatus = initialGoogleCalendarSyncStatus != nil
        self.googleCalendarReadinessRefreshRevision = 0
        self.externalScheduleEventRefreshRevision = 0
        self.externalScheduleEventInterval = nil
        self.googleCalendarReadinessNotificationObservation = NotificationCenter.default
            .publisher(for: .suisuiGoogleCalendarReadinessDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshGoogleCalendarSyncStatusOffMain()
                    self?.refreshExternalScheduleEvents(force: true)
                }
            }
    }

    /// Compatibility overload for integrations that predate the injected
    /// Calendar readiness snapshot. Such callers intentionally use the
    /// runtime-not-configured state until the normal off-main refresh runs.
    @_disfavoredOverload
    public convenience init(
        store: any ProjectBoardStore,
        inboxCaptureStore: (any InboxCaptureStore)? = nil,
        assistantQueueStore: (any AssistantQueueStore)? = nil,
        assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator? = nil,
        assistantQueueExecutionCoordinatorFactory: (() -> AssistantQueueExecutionCoordinator?)? = nil,
        executionReceiptStore: (any ExecutionReceiptStore)? = nil,
        missedTaskReviewStateStore: any MissedTaskReviewStateStore = VolatileMissedTaskReviewStateStore(),
        missedTaskFollowUpNotificationClient: (any NotificationClient)? = nil,
        externalTaskLinkStore: (any ExternalTaskLinkStore)? = nil,
        scheduleCalendarClient: (any CalendarClient)? = nil,
        externalScheduleEventSource: (any ExternalScheduleEventSource)? = nil,
        googleCalendarSync: (any GoogleCalendarRuntimeSyncing)? = nil,
        googleCalendarSyncFactory: (() -> (any GoogleCalendarRuntimeSyncing)?)? = nil,
        readModelNow: @escaping () -> Date = { VisualEvidenceRuntimeContext.referenceDate() },
        readModelCalendar: @escaping () -> Calendar = { VisualEvidenceRuntimeContext.runtimeCalendar() },
        snapshot: ProjectBoardSnapshot = .empty,
        onChange: @escaping () -> Void = {}
    ) {
        self.init(
            store: store,
            inboxCaptureStore: inboxCaptureStore,
            assistantQueueStore: assistantQueueStore,
            assistantQueueExecutionCoordinator: assistantQueueExecutionCoordinator,
            assistantQueueExecutionCoordinatorFactory: assistantQueueExecutionCoordinatorFactory,
            executionReceiptStore: executionReceiptStore,
            missedTaskReviewStateStore: missedTaskReviewStateStore,
            missedTaskFollowUpNotificationClient: missedTaskFollowUpNotificationClient,
            externalTaskLinkStore: externalTaskLinkStore,
            scheduleCalendarClient: scheduleCalendarClient,
            externalScheduleEventSource: externalScheduleEventSource,
            googleCalendarSync: googleCalendarSync,
            initialGoogleCalendarSyncStatus: nil,
            googleCalendarSyncFactory: googleCalendarSyncFactory,
            readModelNow: readModelNow,
            readModelCalendar: readModelCalendar,
            snapshot: snapshot,
            onChange: onChange
        )
    }

    public var fatalFailure: ProjectBoardFailure? {
        guard case .initialLoadFailed = failure else { return nil }
        return failure
    }

    public var errorPresentation: ProjectBoardErrorPresentation? {
        guard let failure else { return nil }
        let canRetry = canRetryCurrentFailure
        switch ProjectBoardErrorPresentation.classify(failure) {
        case .fatal(let message, _):
            return .fatal(message: message, canRetry: canRetry)
        case .inline(let message, _):
            return .inline(message: message, canRetry: canRetry)
        }
    }

    public var rootErrorPresentation: ProjectBoardErrorPresentation? {
        // The view model cannot prove that an inspector is effectively visible:
        // users can close it or compact resizing can hide it while selection remains.
        // Keep the route-wide fallback even when the inspector also shows its sticky error.
        return errorPresentation
    }

    public var failureActionLabel: String? {
        guard canRetryCurrentFailure else { return nil }
        switch failureRetryAction {
        case .load:
            return String(localized: "Reload")
        case .saveTask, .createTask, .createProject, .updateProject,
             .completeProject, .archiveProject, .restoreProject, .deleteProject,
             .deleteTask, .moveTask, .syncGoogleCalendar:
            return String(localized: "Retry")
        case nil:
            return nil
        }
    }

    public func taskSaveFailure(taskID: Int64) -> ProjectBoardFailure? {
        guard case .saveFailed = failure,
              case .saveTask(let failedTaskID, _) = failureRetryAction,
              failedTaskID == taskID,
              failureTaskID == taskID else {
            return nil
        }
        return failure
    }

    public func retryCurrentFailure() {
        guard canRetryCurrentFailure, let failureRetryAction else { return }
        // Clear only at an explicit retry boundary. Incidental store-change
        // reloads must not erase the recoverable context before the user sees it.
        clearFailure()
        switch failureRetryAction {
        case .load:
            load()
        case .saveTask(let taskID, let draft):
            selectedProjectID = draft.projectID
            selectedTaskID = taskID
            updateSelectedTask(
                title: draft.title,
                detail: draft.detail,
                status: draft.status,
                priority: draft.priority,
                dueAt: draft.dueAt,
                recurrence: draft.recurrence
            )
        case .createTask(let draft):
            _ = createTask(
                title: draft.title,
                detail: draft.detail,
                projectID: draft.projectID,
                status: draft.status,
                priority: draft.priority,
                dueAt: draft.dueAt
            )
        case .createProject(let title):
            _ = createProject(title: title)
        case .updateProject(let id, let title):
            selectedProjectID = id
            updateSelectedProject(title: title)
        case .completeProject(let id):
            selectedProjectID = id
            completeSelectedProject()
        case .archiveProject(let id):
            selectedProjectID = id
            archiveSelectedProject()
        case .restoreProject(let id):
            selectedProjectID = id
            restoreSelectedProject()
        case .deleteProject(let id):
            selectedProjectID = id
            deleteSelectedProject()
        case .deleteTask(let id):
            selectedTaskID = id
            deleteSelectedTask()
        case .moveTask(let id, let status):
            moveTask(id: id, to: status)
        case .syncGoogleCalendar(let approvalToken):
            _ = syncDueTasksToGoogleCalendar(approvalToken: approvalToken)
        }
    }

    private var canRetryCurrentFailure: Bool {
        guard let failureRetryAction else { return false }
        if case .saveTask(let taskID, _) = failureRetryAction {
            return snapshot.projects.flatMap(\.tasks).contains { $0.id == taskID }
        }
        return true
    }

    private func recordFailure(
        _ failure: ProjectBoardFailure,
        taskID: Int64? = nil,
        retryAction: ProjectBoardFailureRetryAction?
    ) {
        let redactedMessage = LocalPathRedactor.redact(
            UserFacingErrorMessageSanitizer.message(
                from: failure.message,
                fallback: String(localized: "Project board unavailable")
            )
        )
        // Context must exist before either @Published property emits. SwiftUI
        // derives banner placement and Retry from these non-published values.
        failureTaskID = taskID
        failureRetryAction = retryAction
        isSynchronizingFailure = true
        errorMessage = redactedMessage
        isSynchronizingFailure = false
        switch failure {
        case .initialLoadFailed:
            self.failure = .initialLoadFailed(redactedMessage)
        case .saveFailed:
            self.failure = .saveFailed(redactedMessage)
        case .providerFailed:
            self.failure = .providerFailed(redactedMessage)
        case .readinessCheckFailed:
            self.failure = .readinessCheckFailed(redactedMessage)
        }
    }

    private func clearFailure() {
        isSynchronizingFailure = true
        errorMessage = nil
        isSynchronizingFailure = false
        failure = nil
        failureTaskID = nil
        failureRetryAction = nil
    }

    private func clearErrorAfterSuccessfulLoad() {
        guard !didLastLoadFail else { return }
        errorMessage = nil
    }

    private func beginRecoverableOperation(taskID: Int64? = nil) {
        guard failure != nil else { return }
        guard failureTaskID == nil || failureTaskID == taskID else { return }
        clearFailure()
    }

    public var selectedProject: ProjectBoardProject? {
        snapshot.projects.first { $0.id == selectedProjectID } ?? snapshot.projects.first
    }

    public var selectedTask: ProjectBoardTask? {
        guard let selectedTaskID else {
            return nil
        }

        return task(id: selectedTaskID)
    }

    public var currentDailyPlanningReview: DailyPlanningReview? {
        // A voice/prepare/readout/action-draft review is authoritative user
        // intent. The derived value is only the passive default for Today.
        dailyPlanningReview ?? derivedReadModels.todayWorkflowSnapshot.dailyPlanningReviewPreview
    }

    private var resolvedAssistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator? {
        if let assistantQueueExecutionCoordinator {
            return assistantQueueExecutionCoordinator
        }
        guard let assistantQueueExecutionCoordinatorFactory else {
            return nil
        }
        // Queue execution wires local tools, audit logging, and file access. Keep
        // that graph out of Project Board launch and build it only for explicit
        // approval/execution actions.
        let coordinator = assistantQueueExecutionCoordinatorFactory()
        assistantQueueExecutionCoordinator = coordinator
        return coordinator
    }

    private var resolvedGoogleCalendarSync: (any GoogleCalendarRuntimeSyncing)? {
        if let googleCalendarSync {
            return googleCalendarSync
        }
        guard let googleCalendarSyncFactory else {
            return nil
        }
        // Google sync readiness may touch credentials. Defer construction until
        // board data has loaded so the app can publish a visible window first.
        let sync = googleCalendarSyncFactory()
        googleCalendarSync = sync
        return sync
    }

    public func developmentAutomationReadiness(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ProjectDevelopmentAutomationReadiness {
        let allowedFileOperations = Self.developmentAutomationAllowedFileOperations
        let reviewSteps = Self.developmentAutomationReviewSteps
        let lifecycleToolNames = Self.developmentAutomationLifecycleToolNames
        let approvalBoundaryLabel = Self.developmentAutomationApprovalBoundaryLabel
        let toolName = "development.pr_workflow.prepare"

        func blocked(_ reason: String) -> ProjectDevelopmentAutomationReadiness {
            ProjectDevelopmentAutomationReadiness(
                projectID: project.id,
                taskID: task?.id,
                isReady: false,
                statusLabel: "Needs setup",
                blockingReason: reason,
                workspaceDisplayName: project.workspaceDisplayName,
                branchNamePreview: nil,
                allowedFileOperations: allowedFileOperations,
                reviewSteps: reviewSteps,
                lifecycleToolNames: lifecycleToolNames,
                approvalBoundaryLabel: approvalBoundaryLabel,
                toolName: toolName
            )
        }

        guard !project.isArchived, !project.isCompleted else {
            return blocked("Restore the project before starting development automation.")
        }

        guard project.hasWorkspaceDirectory else {
            return blocked("Choose a project directory before starting development automation.")
        }
        guard project.hasWorkspaceBookmark else {
            return blocked("Choose the project directory again before starting branch automation.")
        }

        guard let task,
              task.projectID == project.id,
              task.status != .done,
              task.status != .blocked else {
            return blocked("Select an open development task before starting branch automation.")
        }

        let projectRecord = Self.developmentAutomationProjectRecord(from: project)
        let taskRecord = Self.developmentAutomationTaskRecord(from: task)

        // This preview deliberately reuses the write workflow's branch policy while avoiding
        // any git side effects; branch creation, push, PR creation, review, and merge stay approval-gated.
        let branchNamePreview = DevelopmentBranchNamePolicy.deterministicBranchName(
            project: projectRecord,
            task: taskRecord
        )

        return ProjectDevelopmentAutomationReadiness(
            projectID: project.id,
            taskID: task.id,
            isReady: true,
            statusLabel: "Ready for approval review",
            blockingReason: nil,
            workspaceDisplayName: project.workspaceDisplayName,
            branchNamePreview: branchNamePreview,
            allowedFileOperations: allowedFileOperations,
            reviewSteps: reviewSteps,
            lifecycleToolNames: lifecycleToolNames,
            approvalBoundaryLabel: approvalBoundaryLabel,
            toolName: toolName
        )
    }

    @discardableResult
    public func prepareDevelopmentAutomationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let plan = ActionPlan(
            id: "development-pr-prepare:\(project.id):\(task.id):\(Self.developmentAutomationPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName))",
            userInput: "Prepare a reviewable development branch for \(task.title).",
            summary: "Prepare reviewable branch \(branchName) for \(task.title).",
            actions: [
                PlanAction(
                    id: "development-pr-prepare",
                    tool: .developmentPreparePullRequestWorkflow,
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string(branchName)
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        // Store only the review plan, not an execution result. The actual git
        // branch operation remains behind ReviewSession approval and runtime
        // workspace validation so a stale bookmark cannot mutate the repo from this panel.
        developmentAutomationReviewPlan = plan
        integrationStatusMessage = "Development branch automation is ready for review."
        todayCommandFeedback = nil
        errorMessage = nil
        return plan
    }

    public func clearDevelopmentAutomationReviewPlan() {
        developmentAutomationReviewPlan = nil
    }

    @discardableResult
    public func enqueueDevelopmentAutomationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentAutomationReview(for: project, task: task) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentAutomationQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Queued development automation for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Development automation is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentRepositoryEditReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueRepositoryEditReview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Prepare the development branch before queueing repository edits.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let reviewedRelativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(relativePath)
            try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
            let redactor = DeveloperSecretRedactor()
            guard !DevelopmentRepositoryIndex.containsRepositoryCredential(
                contents,
                relativePath: reviewedRelativePath,
                redactor: redactor
            ) else {
                throw DevelopmentRepositoryFileError.secretLikeContent(
                    redactor.redact(contents).report.matchedPatternNames
                )
            }

            var arguments: [String: JSONValue] = [
                "projectId": .number(Double(project.id)),
                "taskId": .number(Double(task.id)),
                "branchName": .string(branchName),
                "relativePath": .string(reviewedRelativePath),
                "contents": .string(contents)
            ]
            let reviewedExpectedSHA256 = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines)
            if operation == .update {
                guard let reviewedExpectedSHA256, !reviewedExpectedSHA256.isEmpty else {
                    developmentAutomationReviewPlan = nil
                    todayCommandFeedback = String(localized: "Review the repository edit before queueing verification.")
                    errorMessage = String(localized: "Expected SHA is required before queueing a repository update.")
                    integrationStatusMessage = nil
                    return nil
                }
                arguments["expectedSHA256"] = .string(
                    try DevelopmentRepositoryFilePathPolicy.validatedExpectedSHA256(reviewedExpectedSHA256)
                )
            }

            let plan = ActionPlan(
                id: "development-repository-edit:\(project.id):\(task.id):\(Self.developmentRepositoryEditPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName, operation: operation, relativePath: reviewedRelativePath, contents: contents, expectedSHA256: reviewedExpectedSHA256))",
                userInput: "Review repository \(operation.rawValue) for \(task.title).",
                summary: "Review \(operation.rawValue) for \(reviewedRelativePath) on branch \(branchName) before verification. File contents stay redacted in receipts.",
                actions: [
                    PlanAction(
                        id: "development-repository-edit",
                        tool: operation.tool,
                        arguments: arguments,
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // This review captures the exact relative path and content intended for
            // the approved workspace. Execution still revalidates the bookmark and
            // path, so stale UI state cannot write outside the user-approved repo.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development repository edit review is prepared.")
            todayCommandFeedback = nil
            errorMessage = nil
            return plan
        } catch let error as DevelopmentRepositoryFileError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the repository edit before queueing verification.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the repository edit before queueing verification.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(String(describing: error))
            integrationStatusMessage = nil
            return nil
        }
    }

    public func developmentRepositoryEditPreview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> ProjectDevelopmentAutomationApprovalPreview? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let branchName = readiness.branchNamePreview else {
            return nil
        }

        do {
            let reviewedRelativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(relativePath)
            try DevelopmentRepositoryFilePathPolicy.validateTextContent(contents)
            // Keep edit review aligned with repository indexing and direct reads:
            // shared redaction stays conservative, while safe Swift source shapes
            // are reopened only by the source-aware repository credential policy.
            guard !DevelopmentRepositoryIndex.containsRepositoryCredential(
                contents,
                relativePath: reviewedRelativePath,
                redactor: DeveloperSecretRedactor()
            ) else {
                return nil
            }

            var rows = [
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "operation",
                    label: String(localized: "Operation"),
                    value: operation.title
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "relative-path",
                    label: String(localized: "Relative Path"),
                    value: Self.sanitizedDevelopmentAutomationReviewText(reviewedRelativePath)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "branch",
                    label: String(localized: "Branch"),
                    value: Self.sanitizedDevelopmentAutomationReviewText(branchName)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "content-summary",
                    label: String(localized: "Content"),
                    value: Self.developmentRepositoryEditContentSummary(contents)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "reviewed-change-scope",
                    label: String(localized: "Reviewed Change Scope"),
                    value: Self.developmentRepositoryEditReviewedLineSummary(contents)
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "reviewed-replacement",
                    label: String(localized: "Reviewed Replacement"),
                    value: Self.developmentRepositoryEditReviewedReplacementPreview(
                        operation: operation,
                        relativePath: reviewedRelativePath,
                        contents: contents
                    )
                ),
                ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "content-digest",
                    label: String(localized: "Content SHA-256"),
                    value: Self.developmentRepositoryEditContentDigest(contents)
                )
            ]

            if operation == .update {
                guard let reviewedExpectedSHA256 = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !reviewedExpectedSHA256.isEmpty else {
                    return nil
                }
                rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                    id: "expected-sha",
                    label: String(localized: "Expected SHA"),
                    value: String(try DevelopmentRepositoryFilePathPolicy.validatedExpectedSHA256(reviewedExpectedSHA256).prefix(12))
                ))
            }

            // Review previews must help users distinguish edits without leaking the
            // content into receipt-like surfaces; the raw text remains only in the
            // dedicated editor until the user queues the approval-gated action.
            return ProjectDevelopmentAutomationApprovalPreview(
                title: String(localized: "Repository Edit Preview"),
                rows: rows
            )
        } catch {
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentRepositoryEditReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentRepositoryEditReview(
            for: project,
            task: task,
            operation: operation,
            relativePath: relativePath,
            contents: contents,
            expectedSHA256: expectedSHA256
        ) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentRepositoryEditQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Queued development repository edit review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Development repository edit review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentVerificationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        commandID: String = "git.diff_check"
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueVerificationReview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Prepare the development branch before queueing verification.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let command = try DevelopmentVerificationCommandPolicy.validated(commandID: commandID)
            let plan = ActionPlan(
                id: "development-verification:\(project.id):\(task.id):\(Self.developmentVerificationPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName, commandID: command.id))",
                userInput: "Review local verification \(command.commandDisplay) for \(task.title).",
                summary: "Run \(command.commandDisplay) inside approved branch \(branchName) before commit, push, or pull request creation.",
                actions: [
                    PlanAction(
                        id: "development-verification",
                        tool: .developmentRunVerification,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(task.id)),
                            "branchName": .string(branchName),
                            "commandId": .string(command.id)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // Carry branchName in the reviewed arguments even though the tool only
            // executes projectId/commandId; receipts use it to resume the flow after relaunch.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development verification review is prepared.")
            todayCommandFeedback = nil
            errorMessage = nil
            return plan
        } catch let error as DevelopmentVerificationCommandError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Choose an approved verification command before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Choose an approved verification command before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(String(describing: error))
            integrationStatusMessage = nil
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentVerificationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        commandID: String = "git.diff_check"
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentVerificationReview(for: project, task: task, commandID: commandID) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentVerificationQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Queued development verification review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Development verification review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentCommitReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        relativePathsText: String,
        commitMessage: String
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueCommitReview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Run verification before queueing the commit review.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let relativePaths = try Self.validatedDevelopmentCommitRelativePaths(from: relativePathsText)
            let reviewedCommitMessage = try DevelopmentCommitGitCommandPolicy.validatedCommitMessage(
                commitMessage,
                redactor: DeveloperSecretRedactor()
            )
            let plan = ActionPlan(
                id: "development-commit:\(project.id):\(task.id):\(Self.developmentCommitPlanDigest(projectID: project.id, taskID: task.id, branchName: branchName, relativePaths: relativePaths, commitMessage: reviewedCommitMessage))",
                userInput: "Review local commit for \(task.title).",
                summary: "Commit \(relativePaths.joined(separator: ", ")) on branch \(branchName) after verification evidence. Push and pull request creation remain separate approvals.",
                actions: [
                    PlanAction(
                        id: "development-commit",
                        tool: .developmentCommitChanges,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(task.id)),
                            "branchName": .string(branchName),
                            "relativePaths": JSONValueFactory.strings(relativePaths),
                            "commitMessage": .string(reviewedCommitMessage)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // The commit gate records exactly the reviewed file list. The tool
            // re-reads each file and stages only this list so unrelated user edits
            // cannot be swept into the local commit.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development commit review is prepared.")
            todayCommandFeedback = nil
            errorMessage = nil
            return plan
        } catch let error as DevelopmentRepositoryFileError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the commit file paths before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return nil
        } catch let error as DevelopmentCommitWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the commit message and file paths before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the commit message and file paths before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(String(describing: error))
            integrationStatusMessage = nil
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentCommitReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        relativePathsText: String,
        commitMessage: String
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentCommitReview(
            for: project,
            task: task,
            relativePathsText: relativePathsText,
            commitMessage: commitMessage
        ) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentCommitQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Queued development commit review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Development commit review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func prepareDevelopmentPushReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ActionPlan? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueueBranchPushReview,
              let expectedHeadOID = progress.latestCommitOID else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Create the local commit before queueing the branch push.")
            integrationStatusMessage = nil
            return nil
        }

        let plan = ActionPlan(
            id: "development-pr-push:\(project.id):\(task.id):\(Self.developmentAutomationPlanDigest(projectID: project.id, taskID: task.id, branchName: "\(branchName):\(expectedHeadOID)"))",
            userInput: "Review development branch push \(branchName) for \(task.title).",
            summary: "Review branch \(branchName) push to origin for \(task.title). Execution rechecks the current branch, reviewed commit, clean workspace, and GitHub origin before push. Pull request creation requires a separate approval.",
            actions: [
                PlanAction(
                    id: "development-pr-push",
                    tool: .developmentPushBranch,
                    arguments: [
                        "projectId": .number(Double(project.id)),
                        "taskId": .number(Double(task.id)),
                        "branchName": .string(branchName),
                        "expectedHeadOID": .string(expectedHeadOID)
                    ],
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
        // Keep push separate from PR creation so a queued publish step cannot
        // silently escalate into a second external write after the user reviews
        // only the branch push boundary.
        developmentAutomationReviewPlan = plan
        integrationStatusMessage = "Development branch push review is prepared."
        todayCommandFeedback = nil
        errorMessage = nil
        return plan
    }

    @discardableResult
    public func enqueueDevelopmentPushReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentPushReview(for: project, task: task) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentAutomationPushQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Queued development branch push review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Development branch push review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    public func developmentPullRequestCreationDraft(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ProjectDevelopmentPullRequestCreationDraft? {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              let branchName = readiness.branchNamePreview else {
            return nil
        }

        let baseBranch = Self.defaultDevelopmentPullRequestBaseBranch
        return ProjectDevelopmentPullRequestCreationDraft(
            projectID: project.id,
            taskID: task.id,
            branchName: branchName,
            baseBranch: baseBranch,
            title: Self.developmentPullRequestTitle(project: project, task: task),
            body: Self.developmentPullRequestBody(
                project: project,
                task: task,
                branchName: branchName,
                baseBranch: baseBranch
            )
        )
    }

    @discardableResult
    public func prepareDevelopmentPullRequestCreationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        baseBranch: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) -> ActionPlan? {
        guard let draft = developmentPullRequestCreationDraft(for: project, task: task) else {
            let readiness = developmentAutomationReadiness(for: project, task: task)
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return nil
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        guard progress.canQueuePullRequestCreationReview,
              let expectedHeadOID = progress.latestCommitOID else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.nextApproval?.detail
                ?? String(localized: "Push the branch before queueing pull request creation.")
            integrationStatusMessage = nil
            return nil
        }

        do {
            let reviewedBaseBranch = try DevelopmentBranchNamePolicy.validated(
                (baseBranch ?? draft.baseBranch).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try DevelopmentGitHubPRCommandPolicy.validateBaseAndHead(
                baseBranch: reviewedBaseBranch,
                headBranch: draft.branchName
            )
            let reviewedTitle = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestTitle(
                title ?? draft.title,
                redactor: DeveloperSecretRedactor()
            )
            let reviewedBody = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestBody(
                body ?? draft.body,
                redactor: DeveloperSecretRedactor()
            )
            let reviewedExpectedHeadOID = try DevelopmentGitHubPRCommandPolicy.validatedHeadCommitOID(expectedHeadOID)

            let plan = ActionPlan(
                id: "development-pr-create:\(project.id):\(draft.taskID):\(Self.developmentPullRequestCreationPlanDigest(projectID: project.id, taskID: draft.taskID, branchName: draft.branchName, expectedHeadOID: reviewedExpectedHeadOID, baseBranch: reviewedBaseBranch, title: reviewedTitle, body: reviewedBody))",
                userInput: "Create a GitHub pull request for \(draft.branchName) after reviewing base branch, title, and body.",
                summary: "Create pull request from \(draft.branchName) at reviewed commit \(reviewedExpectedHeadOID) into \(reviewedBaseBranch). Base branch \(reviewedBaseBranch), title and body were reviewed before queueing. Execution rechecks the current branch, reviewed commit, clean workspace, and GitHub origin before creating the pull request.",
                actions: [
                    PlanAction(
                        id: "development-pr-create",
                        tool: .developmentCreatePullRequest,
                        arguments: [
                            "projectId": .number(Double(project.id)),
                            "taskId": .number(Double(draft.taskID)),
                            "branchName": .string(draft.branchName),
                            "expectedHeadOID": .string(reviewedExpectedHeadOID),
                            "baseBranch": .string(reviewedBaseBranch),
                            "title": .string(reviewedTitle),
                            "body": .string(reviewedBody)
                        ],
                        riskLevel: .write,
                        requiresUserConfirmation: true
                    )
                ],
                riskLevel: .write,
                requiresApproval: true
            )
            // PR creation is a second external write after push. Keeping a distinct
            // plan ID prevents an approved push queue item from being reused to create
            // a GitHub pull request with unreviewed base/title/body fields.
            developmentAutomationReviewPlan = plan
            integrationStatusMessage = String(localized: "Development pull request creation review is prepared.")
            todayCommandFeedback = nil
            errorMessage = nil
            return plan
        } catch let error as DevelopmentPRPublishWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request base branch, title, and body before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return nil
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request base branch, title, and body before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(String(describing: error))
            integrationStatusMessage = nil
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentPullRequestCreationReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        baseBranch: String? = nil,
        title: String? = nil,
        body: String? = nil
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }
        guard var plan = prepareDevelopmentPullRequestCreationReview(
            for: project,
            task: task,
            baseBranch: baseBranch,
            title: title,
            body: body
        ) else {
            return false
        }

        let validator = ActionPlanValidator()
        let validation = validator.validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        plan.userInput = Self.sanitizedDevelopmentAutomationReviewText(plan.userInput)
        plan.summary = Self.sanitizedDevelopmentAutomationReviewText(plan.summary)
        let persistedValidation = validator.validate(plan)
        guard persistedValidation.isValid else {
            errorMessage = String(localized: "Development automation generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: plan.userInput,
            interpretationSummary: plan.summary,
            reason: Self.developmentPullRequestCreationQueueReason(project: project),
            costPreview: .localOnly()
        )

        do {
            if try assistantQueueStore.insertIfAbsent(item) != nil {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Queued development pull request creation review for approval.")
                todayCommandFeedback = nil
                onChange()
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Development pull request creation review is already in Assistant Queue.")
            todayCommandFeedback = nil
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    public func developmentAutomationProgress(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?
    ) -> ProjectDevelopmentAutomationProgress {
        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let branchName = readiness.branchNamePreview else {
            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: readiness.branchNamePreview,
                receipts: [],
                queueHandoff: nil,
                blockingReason: readiness.blockingReason
            )
        }

        guard let executionReceiptStore else {
            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: branchName,
                receipts: [],
                queueHandoff: developmentAutomationQueueHandoff(
                    projectID: project.id,
                    taskID: task?.id,
                    branchName: branchName,
                    receipts: []
                ),
                blockingReason: String(localized: "Execution receipts are unavailable, so Suisui cannot confirm which development approval comes next.")
            )
        }

        do {
            let receipts = try executionReceiptStore.list(
                matching: ExecutionReceiptSearchFilter(
                    toolNames: Set(Self.developmentAutomationLifecycleToolNames),
                    visibleSurface: .projectDetail
                ),
                limit: 500
            ).filter { receipt in
                Self.developmentAutomationReceiptMatches(
                    receipt,
                    projectID: project.id,
                    branchName: branchName
                )
            }

            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: branchName,
                receipts: receipts,
                queueHandoff: developmentAutomationQueueHandoff(
                    projectID: project.id,
                    taskID: task?.id,
                    branchName: branchName,
                    receipts: receipts
                ),
                blockingReason: nil
            )
        } catch {
            return Self.developmentAutomationProgress(
                projectID: project.id,
                taskID: task?.id,
                branchName: branchName,
                receipts: [],
                queueHandoff: developmentAutomationQueueHandoff(
                    projectID: project.id,
                    taskID: task?.id,
                    branchName: branchName,
                    receipts: []
                ),
                blockingReason: String(localized: "Execution receipts could not be read, so Suisui cannot confirm which development approval comes next.")
            )
        }
    }

    private func developmentAutomationQueueHandoff(
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        receipts: [ExecutionReceipt]
    ) -> ProjectDevelopmentAutomationQueueHandoff? {
        guard let assistantQueueStore else {
            return nil
        }

        do {
            let expectedToolNames = Self.developmentAutomationExpectedQueueToolNames(receipts: receipts)
            guard !expectedToolNames.isEmpty else {
                return nil
            }
            let matchingItems = try assistantQueueStore.list(filter: .all(limit: 500)).filter { item in
                Self.isDevelopmentAutomationQueueHandoffState(item.state)
                    && Self.developmentAutomationQueueItemMatches(
                        item,
                        projectID: projectID,
                        taskID: taskID,
                        branchName: branchName,
                        expectedToolNames: expectedToolNames
                    )
            }
            guard !matchingItems.isEmpty else {
                return nil
            }

            // Keep the project panel as a projection of Assistant Queue state.
            // The queue row remains the review surface of record, while this
            // handoff prevents users from losing the pending approval in project context.
            let snapshot = AssistantQueueReadModel.snapshot(
                from: matchingItems,
                receipts: receipts,
                viewFilter: .all,
                sort: .needsActionFirst,
                allItemsForCounts: matchingItems
            )
            let selectedRow = snapshot.rows.first { row in
                assistantQueueSelectedItemIDs.contains(row.id)
            }
            return (selectedRow ?? snapshot.rows.first).map(Self.developmentAutomationQueueHandoff)
        } catch {
            return nil
        }
    }

    @discardableResult
    public func enqueueDevelopmentPullRequestLifecycleReview(
        for project: ProjectBoardProject,
        task: ProjectBoardTask?,
        operation: SyncDevelopmentPullRequestOperation
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        let readiness = developmentAutomationReadiness(for: project, task: task)
        guard readiness.isReady,
              let task,
              task.projectID == project.id else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = readiness.blockingReason
            integrationStatusMessage = nil
            return false
        }

        let progress = developmentAutomationProgress(for: project, task: task)
        let canQueue = operation == .reviewGate
            ? progress.canQueuePullRequestReviewGate
            : progress.canQueuePullRequestMergeGate
        guard canQueue,
              let rawPullRequestURL = progress.pullRequestURL,
              let rawBranchName = progress.branchName,
              let rawBaseBranch = progress.baseBranch else {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = progress.blockingReason
                ?? Self.developmentPullRequestLifecycleMissingEvidenceMessage(for: operation)
            integrationStatusMessage = nil
            return false
        }

        do {
            let redactor = DeveloperSecretRedactor()
            let pullRequestURL = try DevelopmentGitHubPRCommandPolicy.validatedPullRequestURL(
                rawPullRequestURL.trimmingCharacters(in: .whitespacesAndNewlines),
                redactor: redactor
            )
            let branchName = try DevelopmentPublishGitCommandPolicy.validatedPublishHeadBranch(
                rawBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let baseBranch = try DevelopmentBranchNamePolicy.validated(
                rawBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try DevelopmentGitHubPRCommandPolicy.validateBaseAndHead(
                baseBranch: baseBranch,
                headBranch: branchName
            )

            let request = SyncAutomationRequestPayload(
                id: Self.developmentPullRequestLifecycleRequestID(
                    projectID: project.id,
                    taskID: task.id,
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: baseBranch
                ),
                source: .localDatabase,
                approvalState: .pendingApproval,
                sourceClientID: "project-board",
                toolName: Self.developmentPullRequestLifecycleToolName(for: operation),
                redactedArgumentSummary: Self.developmentPullRequestLifecycleSummary(
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: baseBranch
                ),
                developmentPullRequest: SyncDevelopmentPullRequestPayload(
                    projectID: project.id,
                    taskID: task.id,
                    operation: operation,
                    pullRequestURL: pullRequestURL,
                    branchName: branchName,
                    baseBranch: baseBranch
                )
            )

            var item = AssistantQueueAdapter.makeItem(automationRequest: request)
            item.reviewReason = Self.developmentPullRequestLifecycleQueueReason(
                project: project,
                operation: operation
            )

            do {
                if try assistantQueueStore.insertIfAbsent(item) != nil {
                    focusAssistantQueueItem(id: item.id)
                    errorMessage = nil
                    integrationStatusMessage = Self.developmentPullRequestLifecycleQueuedMessage(for: operation)
                    todayCommandFeedback = nil
                    onChange()
                    return true
                }

                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = Self.developmentPullRequestLifecycleAlreadyQueuedMessage(for: operation)
                todayCommandFeedback = nil
                return true
            } catch {
                _ = refreshAssistantQueueSnapshot()
                errorMessage = AssistantQueueStoreError.userMessage(for: error)
                integrationStatusMessage = nil
                return false
            }
        } catch let error as DevelopmentPRPublishWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request execution receipt before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return false
        } catch let error as DevelopmentPRWorkflowError {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request execution receipt before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(error.userMessage)
            integrationStatusMessage = nil
            return false
        } catch {
            developmentAutomationReviewPlan = nil
            todayCommandFeedback = String(localized: "Review the pull request execution receipt before queueing.")
            errorMessage = Self.sanitizedDevelopmentAutomationReviewText(String(describing: error))
            integrationStatusMessage = nil
            return false
        }
    }

    private static func developmentAutomationProgress(
        projectID: Int64,
        taskID: Int64?,
        branchName: String?,
        receipts: [ExecutionReceipt],
        queueHandoff: ProjectDevelopmentAutomationQueueHandoff?,
        blockingReason: String?
    ) -> ProjectDevelopmentAutomationProgress {
        let prepareReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue,
            receipts: receipts
        )
        let repositoryCreateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryCreateFile.rawValue,
            receipts: receipts
        )
        let repositoryUpdateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryUpdateFile.rawValue,
            receipts: receipts
        )
        let repositoryEditReceipt = [repositoryCreateReceipt, repositoryUpdateReceipt]
            .compactMap { $0 }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let verificationReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRunVerification.rawValue,
            receipts: receipts
        )
        let commitReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCommitChanges.rawValue,
            receipts: receipts
        )
        let pushReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPushBranch.rawValue,
            receipts: receipts
        )
        let pullRequestReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCreatePullRequest.rawValue,
            receipts: receipts
        )
        let reviewReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            receipts: receipts
        )
        let mergeReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentMergePullRequest.rawValue,
            receipts: receipts
        )

        let successfulPrepareReceipt = prepareReceipt?.status == .succeeded ? prepareReceipt : nil
        let successfulRepositoryEditReceipt = repositoryEditReceipt?.status == .succeeded ? repositoryEditReceipt : nil
        let successfulVerificationReceipt = verificationReceipt?.status == .succeeded ? verificationReceipt : nil
        let successfulCommitReceipt = commitReceipt?.status == .succeeded ? commitReceipt : nil
        let successfulPushReceipt = pushReceipt?.status == .succeeded ? pushReceipt : nil
        let successfulPullRequestReceipt = pullRequestReceipt?.status == .succeeded ? pullRequestReceipt : nil
        let successfulReviewReceipt = reviewReceipt?.status == .succeeded ? reviewReceipt : nil
        let successfulMergeReceipt = mergeReceipt?.status == .succeeded ? mergeReceipt : nil
        let pullRequestURL = developmentAutomationReferenceID(
            kind: .pullRequest,
            receipts: [successfulPullRequestReceipt, successfulReviewReceipt, successfulMergeReceipt].compactMap { $0 }
        )
        let baseBranch = developmentAutomationReferenceID(
            kind: .developmentBaseBranch,
            receipts: [successfulPullRequestReceipt, successfulReviewReceipt, successfulMergeReceipt].compactMap { $0 }
        )
        let latestCommitOID = developmentAutomationReferenceID(
            kind: .developmentCommit,
            receipts: [
                successfulMergeReceipt,
                successfulReviewReceipt,
                successfulPullRequestReceipt,
                successfulPushReceipt,
                successfulCommitReceipt
            ].compactMap { $0 }
        )
        let hasLaterThanVerificationEvidence = successfulCommitReceipt != nil
            || successfulPushReceipt != nil
            || successfulPullRequestReceipt != nil
            || successfulReviewReceipt != nil
            || successfulMergeReceipt != nil
        let hasLaterThanRepositoryEditEvidence = successfulVerificationReceipt != nil
            || hasLaterThanVerificationEvidence
        let hasLaterThanCommitEvidence = successfulPushReceipt != nil
            || successfulPullRequestReceipt != nil
            || successfulReviewReceipt != nil
            || successfulMergeReceipt != nil
        let canQueueRepositoryEdit = successfulPrepareReceipt != nil
            && repositoryEditReceipt == nil
            && !hasLaterThanRepositoryEditEvidence
        let canQueueVerification = successfulPrepareReceipt != nil
            && successfulRepositoryEditReceipt != nil
            && verificationReceipt == nil
            && !hasLaterThanVerificationEvidence
        let canQueueCommit = successfulVerificationReceipt != nil
            && commitReceipt == nil
            && !hasLaterThanCommitEvidence
        let canQueuePush = successfulCommitReceipt != nil
            && pushReceipt == nil
            && successfulPullRequestReceipt == nil
            && successfulReviewReceipt == nil
            && successfulMergeReceipt == nil
        let canQueuePullRequestCreation = successfulPushReceipt != nil
            && pullRequestReceipt == nil
            && successfulReviewReceipt == nil
            && successfulMergeReceipt == nil
        let hasReviewEvidence = successfulReviewReceipt != nil
        let hasMergeEvidence = successfulMergeReceipt != nil
        let canQueueReview = successfulPullRequestReceipt != nil
            && pullRequestURL != nil
            && baseBranch != nil
            && !hasReviewEvidence
            && !hasMergeEvidence
        let canQueueMerge = hasReviewEvidence
            && pullRequestURL != nil
            && baseBranch != nil
            && !hasMergeEvidence
        let progressBlockingReason = blockingReason
            ?? developmentAutomationProgressBlockingReason(
                prepareReceipt: prepareReceipt,
                repositoryEditReceipt: repositoryEditReceipt,
                verificationReceipt: verificationReceipt,
                commitReceipt: commitReceipt,
                pushReceipt: pushReceipt,
                pullRequestReceipt: pullRequestReceipt,
                reviewReceipt: reviewReceipt,
                mergeReceipt: mergeReceipt,
                pullRequestURL: pullRequestURL,
                baseBranch: baseBranch
            )
        let nextApproval = developmentAutomationNextApproval(
            prepareReceipt: prepareReceipt,
            repositoryEditReceipt: repositoryEditReceipt,
            verificationReceipt: verificationReceipt,
            commitReceipt: commitReceipt,
            pushReceipt: pushReceipt,
            pullRequestReceipt: pullRequestReceipt,
            reviewReceipt: reviewReceipt,
            mergeReceipt: mergeReceipt,
            successfulPrepareReceipt: successfulPrepareReceipt,
            successfulRepositoryEditReceipt: successfulRepositoryEditReceipt,
            successfulVerificationReceipt: successfulVerificationReceipt,
            successfulCommitReceipt: successfulCommitReceipt,
            canQueueRepositoryEdit: canQueueRepositoryEdit,
            canQueueVerification: canQueueVerification,
            canQueueCommit: canQueueCommit,
            canQueuePush: canQueuePush,
            canQueuePullRequestCreation: canQueuePullRequestCreation,
            canQueueReview: canQueueReview,
            canQueueMerge: canQueueMerge,
            blockingReason: blockingReason
        )
        let approvalPreview = developmentAutomationApprovalPreview(
            branchName: branchName,
            latestCommitOID: latestCommitOID,
            pullRequestURL: pullRequestURL,
            baseBranch: baseBranch
        )

        return ProjectDevelopmentAutomationProgress(
            projectID: projectID,
            taskID: taskID,
            branchName: branchName,
            pullRequestURL: pullRequestURL,
            baseBranch: baseBranch,
            latestCommitOID: latestCommitOID,
            stages: [
                developmentAutomationProgressStage(
                    id: "branch-prepared",
                    title: String(localized: "Branch prepared"),
                    receipt: prepareReceipt
                ),
                developmentAutomationProgressStage(
                    id: "repository-edited",
                    title: String(localized: "Repository edit"),
                    receipt: repositoryEditReceipt,
                    readyWhenMissing: canQueueRepositoryEdit
                ),
                developmentAutomationProgressStage(
                    id: "verification-run",
                    title: String(localized: "Verification run"),
                    receipt: verificationReceipt,
                    readyWhenMissing: canQueueVerification
                ),
                developmentAutomationProgressStage(
                    id: "commit-created",
                    title: String(localized: "Commit created"),
                    receipt: commitReceipt,
                    readyWhenMissing: canQueueCommit
                ),
                developmentAutomationProgressStage(
                    id: "branch-pushed",
                    title: String(localized: "Branch pushed"),
                    receipt: pushReceipt,
                    readyWhenMissing: canQueuePush
                ),
                developmentAutomationProgressStage(
                    id: "pull-request-created",
                    title: String(localized: "Pull request created"),
                    receipt: pullRequestReceipt
                ),
                developmentAutomationProgressStage(
                    id: "pull-request-reviewed",
                    title: String(localized: "Pull request review gate"),
                    receipt: reviewReceipt,
                    readyWhenMissing: canQueueReview
                ),
                developmentAutomationProgressStage(
                    id: "pull-request-merged",
                    title: String(localized: "Pull request merge gate"),
                    receipt: mergeReceipt,
                    readyWhenMissing: canQueueMerge
                )
            ],
            canQueueRepositoryEditReview: canQueueRepositoryEdit,
            canQueueVerificationReview: canQueueVerification,
            canQueueCommitReview: canQueueCommit,
            canQueueBranchPushReview: canQueuePush,
            canQueuePullRequestCreationReview: canQueuePullRequestCreation,
            canQueuePullRequestReviewGate: canQueueReview,
            canQueuePullRequestMergeGate: canQueueMerge,
            blockingReason: progressBlockingReason,
            nextApproval: nextApproval,
            approvalPreview: approvalPreview,
            queueHandoff: queueHandoff
        )
    }

    private static func developmentAutomationApprovalPreview(
        branchName: String?,
        latestCommitOID: String?,
        pullRequestURL: String?,
        baseBranch: String?
    ) -> ProjectDevelopmentAutomationApprovalPreview? {
        var rows: [ProjectDevelopmentAutomationApprovalPreviewRow] = []
        if let branchName {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "branch",
                label: String(localized: "Branch"),
                value: sanitizedDevelopmentAutomationReviewText(branchName)
            ))
        }
        if let latestCommitOID {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "latest-commit",
                label: String(localized: "Latest Commit"),
                value: sanitizedDevelopmentAutomationReviewText(latestCommitOID)
            ))
        }
        if let pullRequestURL {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "pull-request",
                label: String(localized: "Pull Request"),
                value: sanitizedDevelopmentAutomationReviewText(pullRequestURL)
            ))
        }
        if let baseBranch {
            rows.append(ProjectDevelopmentAutomationApprovalPreviewRow(
                id: "base-branch",
                label: String(localized: "Base Branch"),
                value: sanitizedDevelopmentAutomationReviewText(baseBranch)
            ))
        }
        guard !rows.isEmpty else {
            return nil
        }
        return ProjectDevelopmentAutomationApprovalPreview(
            title: String(localized: "Approval Preview"),
            rows: rows
        )
    }

    private static func developmentAutomationNextApproval(
        prepareReceipt: ExecutionReceipt?,
        repositoryEditReceipt: ExecutionReceipt?,
        verificationReceipt: ExecutionReceipt?,
        commitReceipt: ExecutionReceipt?,
        pushReceipt: ExecutionReceipt?,
        pullRequestReceipt: ExecutionReceipt?,
        reviewReceipt: ExecutionReceipt?,
        mergeReceipt: ExecutionReceipt?,
        successfulPrepareReceipt: ExecutionReceipt?,
        successfulRepositoryEditReceipt: ExecutionReceipt?,
        successfulVerificationReceipt: ExecutionReceipt?,
        successfulCommitReceipt: ExecutionReceipt?,
        canQueueRepositoryEdit: Bool,
        canQueueVerification: Bool,
        canQueueCommit: Bool,
        canQueuePush: Bool,
        canQueuePullRequestCreation: Bool,
        canQueueReview: Bool,
        canQueueMerge: Bool,
        blockingReason: String?
    ) -> ProjectDevelopmentAutomationNextApproval? {
        // Resume guidance must come from persisted receipts, not transient UI state,
        // so a reopened project still points users toward review and merge instead of leaving PRs behind.
        if let blockingReason {
            return ProjectDevelopmentAutomationNextApproval(
                id: "setup-required",
                title: String(localized: "Resolve development automation setup"),
                detail: blockingReason
            )
        }

        if mergeReceipt?.status == .succeeded {
            return ProjectDevelopmentAutomationNextApproval(
                id: "lifecycle-complete",
                title: String(localized: "Pull request lifecycle complete"),
                detail: String(localized: "The merge receipt is complete; no PR lifecycle approval is pending.")
            )
        }

        if let failedApproval = failedDevelopmentAutomationNextApproval(
            prepareReceipt: prepareReceipt,
            repositoryEditReceipt: repositoryEditReceipt,
            verificationReceipt: verificationReceipt,
            commitReceipt: commitReceipt,
            pushReceipt: pushReceipt,
            pullRequestReceipt: pullRequestReceipt,
            reviewReceipt: reviewReceipt,
            mergeReceipt: mergeReceipt
        ) {
            return failedApproval
        }

        if canQueueMerge {
            return ProjectDevelopmentAutomationNextApproval(
                id: "pull-request-merge",
                title: String(localized: "Queue pull request merge gate"),
                detail: String(localized: "Use the review gate receipt to queue the final merge approval.")
            )
        }

        if canQueueReview {
            return ProjectDevelopmentAutomationNextApproval(
                id: "pull-request-review",
                title: String(localized: "Queue pull request review gate"),
                detail: String(localized: "Use the PR creation receipt to queue CI, thread, and mergeability checks before merge.")
            )
        }

        if canQueuePush {
            return ProjectDevelopmentAutomationNextApproval(
                id: "branch-push",
                title: String(localized: "Queue branch push review"),
                detail: String(localized: "Push is a separate external write approval after verification and commit evidence exists.")
            )
        }

        if canQueueCommit {
            return ProjectDevelopmentAutomationNextApproval(
                id: "commit-changes",
                title: String(localized: "Queue commit review"),
                detail: String(localized: "Use the verification receipt to review the exact file list and commit message before creating a local commit.")
            )
        }

        if canQueueVerification {
            return ProjectDevelopmentAutomationNextApproval(
                id: "verification-run",
                title: String(localized: "Queue verification review"),
                detail: String(localized: "Use the repository edit receipt to run a local verification command before commit or push.")
            )
        }

        if canQueueRepositoryEdit {
            return ProjectDevelopmentAutomationNextApproval(
                id: "repository-edit",
                title: String(localized: "Queue repository edit review"),
                detail: String(localized: "Review the scoped create or update file operation before verification runs.")
            )
        }

        if canQueuePullRequestCreation {
            return ProjectDevelopmentAutomationNextApproval(
                id: "pull-request-create",
                title: String(localized: "Queue pull request creation review"),
                detail: String(localized: "Review base branch, title, and body before queueing GitHub pull request creation.")
            )
        }

        if pushReceipt == nil, successfulPrepareReceipt != nil {
            if successfulRepositoryEditReceipt == nil {
                return ProjectDevelopmentAutomationNextApproval(
                    id: "repository-edit-pending",
                    title: String(localized: "Wait for repository edit receipt"),
                    detail: String(localized: "The branch is prepared; wait for repository edit evidence before queueing verification.")
                )
            }
            if successfulVerificationReceipt == nil {
                return ProjectDevelopmentAutomationNextApproval(
                    id: "verification-pending",
                    title: String(localized: "Wait for verification receipt"),
                    detail: String(localized: "The branch is prepared; wait for verification evidence before queueing commit or push.")
                )
            }
            if successfulCommitReceipt == nil {
                return ProjectDevelopmentAutomationNextApproval(
                    id: "commit-pending",
                    title: String(localized: "Wait for commit receipt"),
                    detail: String(localized: "Verification is complete; wait for local commit evidence before queueing push.")
                )
            }
            return ProjectDevelopmentAutomationNextApproval(
                id: "branch-push",
                title: String(localized: "Queue branch push review"),
                detail: String(localized: "Push is a separate external write approval after branch preparation evidence exists.")
            )
        }

        if prepareReceipt == nil {
            return ProjectDevelopmentAutomationNextApproval(
                id: "branch-prepare",
                title: String(localized: "Queue branch automation"),
                detail: String(localized: "Start with the Assistant Queue branch preparation approval before any git mutation runs.")
            )
        }

        return ProjectDevelopmentAutomationNextApproval(
            id: "receipt-pending",
            title: String(localized: "Wait for execution receipt"),
            detail: String(localized: "The current development approval is still waiting for execution evidence before the next approval can be queued.")
        )
    }

    private static func failedDevelopmentAutomationNextApproval(
        prepareReceipt: ExecutionReceipt?,
        repositoryEditReceipt: ExecutionReceipt?,
        verificationReceipt: ExecutionReceipt?,
        commitReceipt: ExecutionReceipt?,
        pushReceipt: ExecutionReceipt?,
        pullRequestReceipt: ExecutionReceipt?,
        reviewReceipt: ExecutionReceipt?,
        mergeReceipt: ExecutionReceipt?
    ) -> ProjectDevelopmentAutomationNextApproval? {
        let candidates: [(ExecutionReceipt?, String)] = [
            (mergeReceipt, String(localized: "Review failed pull request merge")),
            (reviewReceipt, String(localized: "Review failed pull request gate")),
            (pullRequestReceipt, String(localized: "Review failed pull request creation")),
            (pushReceipt, String(localized: "Review failed branch push")),
            (commitReceipt, String(localized: "Review failed commit")),
            (verificationReceipt, String(localized: "Review failed verification")),
            (repositoryEditReceipt, String(localized: "Review failed repository edit")),
            (prepareReceipt, String(localized: "Review failed branch preparation"))
        ]
        let failedReceipt: (id: String, title: String)? = candidates.compactMap { candidate -> (id: String, title: String)? in
            let (receipt, title) = candidate
            guard let receipt,
                  receipt.status == .failed || receipt.status == .canceled else {
                return nil
            }
            return (id: receipt.id, title: title)
        }.first

        guard let failedReceipt else {
            return nil
        }

        return ProjectDevelopmentAutomationNextApproval(
            id: "receipt-failed-\(failedReceipt.id)",
            title: failedReceipt.title,
            detail: String(localized: "Resolve the failed execution receipt before queueing the next development approval.")
        )
    }

    private static func developmentAutomationProgressStage(
        id: String,
        title: String,
        receipt: ExecutionReceipt?,
        readyWhenMissing: Bool = false
    ) -> ProjectDevelopmentAutomationProgressStage {
        let status: ProjectDevelopmentAutomationProgressStageStatus
        if let receipt {
            switch receipt.status {
            case .succeeded:
                status = .succeeded
            case .failed, .canceled:
                status = .failed
            case .running, .notStarted, .skipped:
                status = .waiting
            }
        } else {
            status = readyWhenMissing ? .ready : .waiting
        }

        return ProjectDevelopmentAutomationProgressStage(
            id: id,
            title: title,
            status: status,
            detail: receipt.map { summarizedDevelopmentAutomationReceipt($0) }
        )
    }

    private static func summarizedDevelopmentAutomationReceipt(_ receipt: ExecutionReceipt) -> String {
        let summary = sanitizedDevelopmentAutomationReviewText(receipt.outputSummary)
        guard summary.count > 180 else {
            return summary
        }
        return "\(summary.prefix(177))..."
    }

    private static func developmentAutomationQueueHandoff(
        from row: AssistantQueueReadModelRow
    ) -> ProjectDevelopmentAutomationQueueHandoff {
        ProjectDevelopmentAutomationQueueHandoff(
            id: row.id,
            state: row.state,
            stateLabel: row.stateLabel,
            title: row.title,
            reviewReason: row.reviewReason,
            capabilityLabels: row.capabilityLabels,
            latestReceiptStatusLabel: row.latestReceipt?.statusLabel,
            canApprove: row.canApprove,
            canRun: row.canRun
        )
    }

    private static func developmentAutomationExpectedQueueToolNames(
        receipts: [ExecutionReceipt]
    ) -> Set<String> {
        let prepareReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPreparePullRequestWorkflow.rawValue,
            receipts: receipts
        )
        let repositoryCreateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryCreateFile.rawValue,
            receipts: receipts
        )
        let repositoryUpdateReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRepositoryUpdateFile.rawValue,
            receipts: receipts
        )
        let repositoryEditReceipt = [repositoryCreateReceipt, repositoryUpdateReceipt]
            .compactMap { $0 }
            .sorted { $0.createdAt > $1.createdAt }
            .first
        let verificationReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentRunVerification.rawValue,
            receipts: receipts
        )
        let commitReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCommitChanges.rawValue,
            receipts: receipts
        )
        let pushReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentPushBranch.rawValue,
            receipts: receipts
        )
        let pullRequestReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentCreatePullRequest.rawValue,
            receipts: receipts
        )
        let reviewReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentReviewPullRequestGate.rawValue,
            receipts: receipts
        )
        let mergeReceipt = latestDevelopmentAutomationReceipt(
            toolName: ActionTool.developmentMergePullRequest.rawValue,
            receipts: receipts
        )

        if mergeReceipt?.status == .succeeded {
            return []
        }

        if let failedReceipt = [
            mergeReceipt,
            reviewReceipt,
            pullRequestReceipt,
            pushReceipt,
            commitReceipt,
            verificationReceipt,
            repositoryEditReceipt,
            prepareReceipt
        ].compactMap({ $0 }).first(where: { receipt in
            receipt.status == .failed || receipt.status == .canceled
        }) {
            return failedReceipt.primaryToolName.map { [$0] } ?? Set(failedReceipt.actions.map(\.toolName))
        }

        let successfulPrepareReceipt = prepareReceipt?.status == .succeeded ? prepareReceipt : nil
        let successfulRepositoryEditReceipt = repositoryEditReceipt?.status == .succeeded ? repositoryEditReceipt : nil
        let successfulVerificationReceipt = verificationReceipt?.status == .succeeded ? verificationReceipt : nil
        let successfulCommitReceipt = commitReceipt?.status == .succeeded ? commitReceipt : nil
        let successfulPushReceipt = pushReceipt?.status == .succeeded ? pushReceipt : nil
        let successfulPullRequestReceipt = pullRequestReceipt?.status == .succeeded ? pullRequestReceipt : nil
        let successfulReviewReceipt = reviewReceipt?.status == .succeeded ? reviewReceipt : nil

        if successfulPrepareReceipt == nil {
            return [ActionTool.developmentPreparePullRequestWorkflow.rawValue]
        }
        if successfulRepositoryEditReceipt == nil {
            return [
                ActionTool.developmentRepositoryCreateFile.rawValue,
                ActionTool.developmentRepositoryUpdateFile.rawValue
            ]
        }
        if successfulVerificationReceipt == nil {
            return [ActionTool.developmentRunVerification.rawValue]
        }
        if successfulCommitReceipt == nil {
            return [ActionTool.developmentCommitChanges.rawValue]
        }
        if successfulPushReceipt == nil {
            return [ActionTool.developmentPushBranch.rawValue]
        }
        if successfulPullRequestReceipt == nil {
            return [ActionTool.developmentCreatePullRequest.rawValue]
        }
        if successfulReviewReceipt == nil {
            return [ActionTool.developmentReviewPullRequestGate.rawValue]
        }
        return [ActionTool.developmentMergePullRequest.rawValue]
    }

    private static func developmentAutomationQueueItemMatches(
        _ item: AssistantQueueItem,
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        expectedToolNames: Set<String>
    ) -> Bool {
        switch item.payload {
        case .actionPlan(let plan):
            return developmentAutomationActionPlanMatches(
                plan,
                projectID: projectID,
                taskID: taskID,
                branchName: branchName,
                expectedToolNames: expectedToolNames
            )
        case .automationRequest(let request):
            return developmentAutomationRequestMatches(
                request,
                projectID: projectID,
                taskID: taskID,
                branchName: branchName,
                expectedToolNames: expectedToolNames
            )
        }
    }

    private static func isDevelopmentAutomationQueueHandoffState(_ state: AssistantQueueState) -> Bool {
        switch state {
        case .done, .rejected:
            return false
        case .captured, .interpreted, .drafted, .waitingReview, .approved, .running, .blocked, .failed, .deferred:
            return true
        }
    }

    private static func developmentAutomationActionPlanMatches(
        _ plan: ActionPlan,
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        expectedToolNames: Set<String>
    ) -> Bool {
        plan.actions.contains { action in
            expectedToolNames.contains(action.tool.rawValue)
                && jsonNumber(action.arguments["projectId"], equals: projectID)
                && jsonString(action.arguments["branchName"], equals: branchName)
                && taskID.map { jsonNumber(action.arguments["taskId"], equals: $0) } ?? true
        }
    }

    private static func developmentAutomationRequestMatches(
        _ request: SyncAutomationRequestPayload,
        projectID: Int64,
        taskID: Int64?,
        branchName: String,
        expectedToolNames: Set<String>
    ) -> Bool {
        guard let toolName = request.toolName,
              expectedToolNames.contains(toolName),
              let pullRequest = request.developmentPullRequest,
              pullRequest.projectID == projectID,
              pullRequest.branchName == branchName else {
            return false
        }
        guard let expectedTaskID = taskID,
              let requestTaskID = pullRequest.taskID else {
            return true
        }
        return requestTaskID == expectedTaskID
    }

    private static func jsonNumber(_ value: JSONValue?, equals expected: Int64) -> Bool {
        guard case .number(let number) = value else {
            return false
        }
        return number == Double(expected)
    }

    private static func jsonString(_ value: JSONValue?, equals expected: String) -> Bool {
        guard case .string(let string) = value else {
            return false
        }
        return string == expected
    }

    private static func latestDevelopmentAutomationReceipt(
        toolName: String,
        receipts: [ExecutionReceipt]
    ) -> ExecutionReceipt? {
        receipts.first { receipt in
            receipt.primaryToolName == toolName
                || receipt.actions.contains { $0.toolName == toolName }
        }
    }

    private static func developmentAutomationReferenceID(
        kind: ExecutionReceiptReferenceKind,
        receipts: [ExecutionReceipt]
    ) -> String? {
        receipts
            .lazy
            .flatMap(\.references)
            .first { $0.kind == kind }?
            .id
    }

    private static func developmentAutomationReceiptMatches(
        _ receipt: ExecutionReceipt,
        projectID: Int64,
        branchName: String
    ) -> Bool {
        let references = receipt.references
        return references.contains { $0.kind == .project && $0.id == String(projectID) }
            && references.contains { $0.kind == .developmentBranch && $0.id == branchName }
    }

    private static func developmentAutomationProgressBlockingReason(
        prepareReceipt: ExecutionReceipt?,
        repositoryEditReceipt: ExecutionReceipt?,
        verificationReceipt: ExecutionReceipt?,
        commitReceipt: ExecutionReceipt?,
        pushReceipt: ExecutionReceipt?,
        pullRequestReceipt: ExecutionReceipt?,
        reviewReceipt: ExecutionReceipt?,
        mergeReceipt: ExecutionReceipt?,
        pullRequestURL: String?,
        baseBranch: String?
    ) -> String? {
        if mergeReceipt?.status == .succeeded {
            return String(localized: "Pull request merge receipt is complete.")
        }
        if prepareReceipt == nil {
            return String(localized: "Queue branch preparation and wait for its execution receipt before verification.")
        }
        if prepareReceipt?.status == .failed || prepareReceipt?.status == .canceled {
            return String(localized: "Branch preparation failed. Review the execution receipt before queueing verification.")
        }
        let hasEvidenceAfterRepositoryEdit = verificationReceipt != nil
            || commitReceipt != nil
            || pushReceipt != nil
            || pullRequestReceipt != nil
            || reviewReceipt != nil
            || mergeReceipt != nil
        let hasEvidenceAfterVerification = commitReceipt != nil
            || pushReceipt != nil
            || pullRequestReceipt != nil
            || reviewReceipt != nil
            || mergeReceipt != nil
        let hasEvidenceAfterCommit = pushReceipt != nil
            || pullRequestReceipt != nil
            || reviewReceipt != nil
            || mergeReceipt != nil
        if repositoryEditReceipt == nil, !hasEvidenceAfterRepositoryEdit {
            return String(localized: "Queue a repository edit and wait for its execution receipt before verification.")
        }
        if repositoryEditReceipt?.status == .failed || repositoryEditReceipt?.status == .canceled {
            return String(localized: "Repository edit failed. Review the execution receipt before queueing verification.")
        }
        if verificationReceipt == nil, !hasEvidenceAfterVerification {
            return String(localized: "Run verification and wait for its execution receipt before commit.")
        }
        if verificationReceipt?.status == .failed || verificationReceipt?.status == .canceled {
            return String(localized: "Verification failed. Review the execution receipt before queueing commit.")
        }
        if commitReceipt == nil, !hasEvidenceAfterCommit {
            return String(localized: "Create the local commit and wait for its execution receipt before push.")
        }
        if commitReceipt?.status == .failed || commitReceipt?.status == .canceled {
            return String(localized: "Local commit failed. Review the execution receipt before queueing push.")
        }
        if pushReceipt == nil {
            return String(localized: "Push the branch and wait for its execution receipt before pull request creation.")
        }
        if pushReceipt?.status == .failed || pushReceipt?.status == .canceled {
            return String(localized: "Branch push failed. Review the execution receipt before queueing pull request creation.")
        }
        if pullRequestReceipt == nil {
            return String(localized: "Create the pull request and wait for its execution receipt before queueing review or merge.")
        }
        if pullRequestReceipt?.status == .failed || pullRequestReceipt?.status == .canceled {
            return String(localized: "Pull request creation failed. Review the execution receipt before queueing review or merge.")
        }
        if pullRequestURL == nil || baseBranch == nil {
            return String(localized: "Pull request receipt is missing URL or base branch evidence, so Suisui will not draft review or merge approval.")
        }
        if reviewReceipt?.status == .failed || reviewReceipt?.status == .canceled {
            return String(localized: "Pull request review gate failed. Resolve the receipt before queueing merge.")
        }
        if reviewReceipt == nil {
            return String(localized: "Pull request is ready for a review gate approval.")
        }
        return String(localized: "Pull request is ready for a merge gate approval.")
    }

    private static func developmentPullRequestLifecycleMissingEvidenceMessage(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "Create the pull request and wait for its receipt before queueing review.")
        case .merge:
            return String(localized: "Run the pull request review gate and wait for its receipt before queueing merge.")
        }
    }

    private func task(id: Int64) -> ProjectBoardTask? {
        snapshot.projects
            .flatMap(\.tasks)
            .first { $0.id == id }
    }

    private static let developmentAutomationAllowedFileOperations = ["create", "read", "update"]
    private static let defaultDevelopmentPullRequestBaseBranch = "main"

    private static let developmentAutomationLifecycleToolNames = [
        ActionTool.developmentPreparePullRequestWorkflow.rawValue,
        ActionTool.developmentRepositoryListFiles.rawValue,
        ActionTool.developmentRepositoryReadFile.rawValue,
        ActionTool.developmentRepositoryCreateFile.rawValue,
        ActionTool.developmentRepositoryUpdateFile.rawValue,
        ActionTool.developmentRunVerification.rawValue,
        ActionTool.developmentCommitChanges.rawValue,
        ActionTool.developmentPushBranch.rawValue,
        ActionTool.developmentCreatePullRequest.rawValue,
        ActionTool.developmentReviewPullRequestGate.rawValue,
        ActionTool.developmentMergePullRequest.rawValue
    ]

    private static let developmentAutomationApprovalBoundaryLabel = "Branch preparation starts here; file edits, verification, commit, push, pull request, review, and merge each stay behind explicit approval gates."

    private static func developmentAutomationQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development branch automation is ready for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentAutomationPushQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development branch push needs review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentVerificationQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development verification needs review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentRepositoryEditQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development repository edit needs review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentCommitQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development commit needs reviewed files and message for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentPullRequestCreationQueueReason(project: ProjectBoardProject) -> String {
        String(
            format: String(localized: "Development pull request creation needs base, title, and body review for %@."),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentPullRequestLifecycleQueueReason(
        project: ProjectBoardProject,
        operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        String(
            format: String(localized: "Development pull request %@ gate needs review for %@."),
            developmentPullRequestLifecycleOperationLabel(for: operation),
            sanitizedDevelopmentAutomationReviewText(project.title)
        )
    }

    private static func developmentPullRequestLifecycleQueuedMessage(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "Queued development pull request review gate for approval.")
        case .merge:
            return String(localized: "Queued development pull request merge gate for approval.")
        }
    }

    private static func developmentPullRequestLifecycleAlreadyQueuedMessage(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "Development pull request review gate is already in Assistant Queue.")
        case .merge:
            return String(localized: "Development pull request merge gate is already in Assistant Queue.")
        }
    }

    private static func developmentPullRequestLifecycleToolName(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return ActionTool.developmentReviewPullRequestGate.rawValue
        case .merge:
            return ActionTool.developmentMergePullRequest.rawValue
        }
    }

    private static func developmentPullRequestLifecycleOperationID(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return "review"
        case .merge:
            return "merge"
        }
    }

    private static func developmentPullRequestLifecycleOperationLabel(
        for operation: SyncDevelopmentPullRequestOperation
    ) -> String {
        switch operation {
        case .reviewGate:
            return String(localized: "review")
        case .merge:
            return String(localized: "merge")
        }
    }

    private static func developmentPullRequestLifecycleSummary(
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String
    ) -> String {
        let action: String
        switch operation {
        case .reviewGate:
            action = "Review CI, review decision, unresolved threads, and mergeability before merge approval."
        case .merge:
            action = "Merge only after the review gate passes and execution rechecks the approved head commit."
        }
        return sanitizedDevelopmentAutomationReviewText(
            "Project development PR \(developmentPullRequestLifecycleOperationID(for: operation)): \(pullRequestURL) head \(branchName) into \(baseBranch). \(action)"
        )
    }

    private static func developmentPullRequestTitle(
        project: ProjectBoardProject,
        task: ProjectBoardTask
    ) -> String {
        let taskTitle = sanitizedSingleLineDevelopmentAutomationText(task.title, fallback: "task \(task.id)")
        return truncatedPullRequestTitle("Suisui: \(taskTitle)")
    }

    private static func developmentPullRequestBody(
        project: ProjectBoardProject,
        task: ProjectBoardTask,
        branchName: String,
        baseBranch: String
    ) -> String {
        let projectTitle = sanitizedSingleLineDevelopmentAutomationText(project.title, fallback: "project \(project.id)")
        let taskTitle = sanitizedSingleLineDevelopmentAutomationText(task.title, fallback: "task \(task.id)")
        return """
        ## Summary
        - Prepare \(taskTitle) for \(projectTitle).

        ## Pull Request
        - Base branch: \(baseBranch)
        - Head branch: \(branchName)

        ## Review
        - Created from Suisui development automation after separate branch preparation, verification, commit, and push gates.
        - Review CI, code review, and merge readiness before merging.
        """
    }

    private static func sanitizedSingleLineDevelopmentAutomationText(_ text: String, fallback: String) -> String {
        let sanitized = sanitizedDevelopmentAutomationReviewText(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return sanitized.isEmpty ? fallback : sanitized
    }

    private static func truncatedPullRequestTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 200 else {
            return trimmed
        }
        return String(trimmed.prefix(197)) + "..."
    }

    private static func sanitizedDevelopmentAutomationReviewText(_ text: String) -> String {
        let redacted = ExecutionReceiptRedactor().redact(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !redacted.isEmpty else {
            return String(localized: "Development branch automation")
        }
        let maxLength = 500
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func developmentRepositoryEditLineCount(_ contents: String) -> Int {
        // Treat a final newline as file formatting, not an extra blank line, so
        // the preview matches how users normally describe source-file edits.
        let newlineCount = contents.reduce(into: 0) { count, character in
            if character.isNewline {
                count += 1
            }
        }
        return max(1, 1 + newlineCount - (contents.last?.isNewline == true ? 1 : 0))
    }

    private static func developmentRepositoryEditContentSummary(_ contents: String) -> String {
        let lineCount = developmentRepositoryEditLineCount(contents)
        let byteCount = contents.utf8.count
        if lineCount == 1 {
            return String(format: String(localized: "%d line / %d bytes"), lineCount, byteCount)
        }
        return String(format: String(localized: "%d lines / %d bytes"), lineCount, byteCount)
    }

    private static func developmentRepositoryEditReviewedLineSummary(_ contents: String) -> String {
        String(format: String(localized: "Reviewed replacement lines: %d"), developmentRepositoryEditLineCount(contents))
    }

    private static func developmentRepositoryEditReviewedReplacementPreview(
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String
    ) -> String {
        // Preview must not read the user's repository before approval, so avoid
        // add/delete counts that would imply Suisui compared against existing content.
        let sanitizedPath = sanitizedDevelopmentAutomationReviewText(relativePath)
        let lineCount = developmentRepositoryEditLineCount(contents)
        switch operation {
        case .create:
            return String(
                format: String(localized: "Create replacement: %@ (reviewed lines: %d)"),
                sanitizedPath,
                lineCount
            )
        case .update:
            return String(
                format: String(localized: "Update replacement: %@ (reviewed lines: %d)"),
                sanitizedPath,
                lineCount
            )
        }
    }

    private static func developmentRepositoryEditContentDigest(_ contents: String) -> String {
        let digest = SHA256.hash(data: Data(contents.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(12))
    }

    private static let developmentAutomationReviewSteps = [
        "Create a reviewable local branch inside the approved project directory.",
        "Use project-scoped create/read/update file operations; delete is not available.",
        "ReviewSession validates the saved project directory again before branch creation.",
        "Run verification before commit, push, or pull request creation.",
        "Require explicit approval before git push and GitHub pull request creation.",
        "Use review and merge gates before marking the pull request complete."
    ]

    private static func developmentAutomationProjectRecord(from project: ProjectBoardProject) -> ProjectRecord {
        ProjectRecord(
            id: project.id,
            title: project.title,
            status: project.status
        )
    }

    private static func developmentAutomationTaskRecord(from task: ProjectBoardTask) -> TaskRecord {
        TaskRecord(
            id: task.id,
            projectID: task.projectID,
            title: task.title,
            status: task.status.rawValue,
            dueAt: task.dueAt,
            completedAt: task.completedAt,
            priority: task.priority.rawValue,
            sourceCommand: nil,
            detail: task.detail,
            updatedAt: task.updatedAt
        )
    }

    private static func developmentAutomationPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String
    ) -> String {
        let input = "\(projectID):\(taskID):\(branchName)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func validatedDevelopmentCommitRelativePaths(from text: String) throws -> [String] {
        let rawPaths = text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawPaths.isEmpty else {
            throw DevelopmentCommitWorkflowError.noRelativePaths
        }

        var seen: Set<String> = []
        var relativePaths: [String] = []
        for rawPath in rawPaths {
            let relativePath = try DevelopmentRepositoryFilePathPolicy.validatedRelativePath(rawPath)
            guard seen.insert(relativePath).inserted else {
                continue
            }
            relativePaths.append(relativePath)
        }

        guard !relativePaths.isEmpty else {
            throw DevelopmentCommitWorkflowError.noRelativePaths
        }
        return relativePaths
    }

    private static func developmentVerificationPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        commandID: String
    ) -> String {
        developmentReviewedInputDigest([String(projectID), String(taskID), branchName, commandID])
    }

    private static func developmentRepositoryEditPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        operation: ProjectDevelopmentRepositoryEditOperation,
        relativePath: String,
        contents: String,
        expectedSHA256: String?
    ) -> String {
        developmentReviewedInputDigest(
            [String(projectID), String(taskID), branchName, operation.rawValue, relativePath, contents, expectedSHA256 ?? ""]
        )
    }

    private static func developmentCommitPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        relativePaths: [String],
        commitMessage: String
    ) -> String {
        developmentReviewedInputDigest([String(projectID), String(taskID), branchName, commitMessage] + relativePaths)
    }

    private static func developmentPullRequestCreationPlanDigest(
        projectID: Int64,
        taskID: Int64,
        branchName: String,
        expectedHeadOID: String,
        baseBranch: String,
        title: String,
        body: String
    ) -> String {
        // Approval identity must change when any reviewed PR field changes; otherwise
        // Assistant Queue's duplicate protection can preserve an approval for stale text.
        developmentReviewedInputDigest([String(projectID), String(taskID), branchName, expectedHeadOID, baseBranch, title, body])
    }

    private static func developmentReviewedInputDigest(_ parts: [String]) -> String {
        let input = parts
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func developmentPullRequestLifecycleRequestID(
        projectID: Int64,
        taskID: Int64,
        operation: SyncDevelopmentPullRequestOperation,
        pullRequestURL: String,
        branchName: String,
        baseBranch: String
    ) -> String {
        // Review and merge are separate approval surfaces. Include every reviewed
        // PR identity field so Assistant Queue cannot reuse approval after edits.
        let parts = [
            String(projectID),
            String(taskID),
            operation.rawValue,
            pullRequestURL,
            branchName,
            baseBranch
        ]
        let input = parts
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
        let digest = SHA256.hash(data: Data(input.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "project-development-pr-\(developmentPullRequestLifecycleOperationID(for: operation)):\(projectID):\(taskID):\(digest)"
    }

    public var canSyncGoogleCalendar: Bool {
        googleCalendarSyncStatus.canSync
    }

    public var googleCalendarSyncHelp: String {
        googleCalendarSyncStatus.detailLabel
    }

    public var selectedInboxCaptureRecords: [InboxCaptureRecord] {
        guard let selectedTaskID else {
            return []
        }

        return captureRecords(for: selectedTaskID, reportErrors: true)
    }

    @discardableResult
    public func updateSelectedInboxCaptureMemo(_ memo: String) -> InboxCaptureRecord? {
        guard let capture = selectedInboxCaptureRecords.first, let inboxCaptureStore else {
            errorMessage = "Inbox capture is no longer available."
            return nil
        }

        do {
            let updated = try inboxCaptureStore.updateMemo(id: capture.id, memo: memo)
            replaceCachedCapture(updated)
            let taskTitle = selectedTask?.title ?? "selected Inbox item"
            inboxClassificationFeedback = InboxClassificationFeedback(
                message: String(format: String(localized: "Saved note for \"%@\"."), taskTitle),
                systemImage: "note.text",
                canUndo: false
            )
            errorMessage = nil
            onChange()
            return updated
        } catch {
            errorMessage = InboxCaptureStoreError.userMessage(for: error)
            return nil
        }
    }

    public var filteredInboxTasks: [ProjectBoardTask] {
        inboxTasks.filter { task in
            matchesInboxTriageFilter(task, filter: inboxTriageFilter)
        }
    }

    public var inboxTasks: [ProjectBoardTask] {
        inboxProject?
            .tasks
            .filter { showsCompletedWorkflowTasks || $0.status != .done }
            .sorted { $0.id > $1.id } ?? []
    }

    public var completedInboxTaskCount: Int {
        inboxProject?.tasks.filter { $0.status == .done }.count ?? 0
    }

    public var inboxProject: ProjectBoardProject? {
        snapshot.projects
            .first { $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived }
    }

    public func inboxTriageCount(for filter: InboxTriageFilter) -> Int {
        return inboxTasks.filter { task in
            matchesInboxTriageFilter(task, filter: filter)
        }.count
    }

    /// Returns the product-facing category used by the reference Inbox tabs.
    /// The mapping is derived from cached capture metadata so rendering the
    /// list does not perform a store read for every row.
    public func inboxReferenceCategory(for task: ProjectBoardTask) -> InboxReferenceCategory {
        let captures = captureRecords(for: task.id)
        let interpretation = captures
            .compactMap(\.interpretationSummary)
            .joined(separator: " ")
        let searchableText = [task.title, task.detail, interpretation]
            .joined(separator: " ")
            .lowercased()

        if Self.inboxNotificationKeywords.contains(where: searchableText.contains) {
            return .notification
        }
        if !interpretation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .proposal
        }
        return .task
    }

    public func inboxReferenceTasks(
        for filter: InboxReferenceFilter,
        unprocessedOnly: Bool = false,
        at referenceDate: Date? = nil
    ) -> [ProjectBoardTask] {
        let effectiveReferenceDate = referenceDate ?? inboxVisibilityReferenceDate ?? readModelNow()
        return inboxTasks.filter { task in
            guard !unprocessedOnly || isInboxUnprocessed(task, at: effectiveReferenceDate) else {
                return false
            }
            guard filter != .all else {
                return true
            }
            return inboxReferenceCategory(for: task) == filter.category
        }
    }

    public func inboxReferenceCount(for filter: InboxReferenceFilter) -> Int {
        inboxReferenceTasks(for: filter).count
    }

    private static let inboxNotificationKeywords = [
        "notification", "alert", "お知らせ", "通知", "アラート"
    ]

    public func inboxTriageSummary(for task: ProjectBoardTask) -> InboxTriageSummary {
        let captures = captureRecords(for: task.id)
        guard let capture = captures.first else {
            return InboxTriageSummary(
                sourceLabel: "Manual",
                // Disposition is rendered by the dedicated triage badge. The
                // source summary must stay about how the item arrived, or a
                // processed manual task appears contradictory as "Unprocessed".
                interpretationLabel: "Manual",
                systemImage: "square.and.pencil",
                tintName: "secondary",
                accessibilityValue: "Source: Manual, Interpretation: Manual"
            )
        }

        if capture.transcriptionStatus == .failed {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript failed",
                systemImage: "waveform.badge.exclamationmark",
                tintName: "red",
                accessibilityValue: "Source: Voice, Interpretation: Transcript failed"
            )
        }

        if capture.transcriptionStatus == .pending {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript pending",
                systemImage: "waveform",
                tintName: "secondary",
                accessibilityValue: "Source: Voice, Interpretation: Transcript pending"
            )
        }

        guard capture.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return InboxTriageSummary(
                sourceLabel: "Voice",
                interpretationLabel: "Transcript ready",
                systemImage: "waveform",
                tintName: "blue",
                accessibilityValue: "Source: Voice, Interpretation: Transcript ready"
            )
        }

        let confidence = Self.inboxInterpretationConfidence(from: capture.memo)
        let confidenceValue = confidence.map { ", Confidence: \($0)" } ?? ""
        return InboxTriageSummary(
            sourceLabel: "Voice",
            interpretationLabel: "AI interpreted",
            systemImage: "sparkles",
            tintName: "blue",
            accessibilityValue: "Source: Voice, Interpretation: AI interpreted\(confidenceValue)"
        )
    }

    public func inboxTriageRecord(for task: ProjectBoardTask) -> InboxTriageRecord? {
        inboxTriageRecordsByTaskID[task.id]
    }

    public func setInboxTriageFilter(_ filter: InboxTriageFilter) {
        refreshInboxCaptureCacheForInbox()
        inboxTriageFilter = filter
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    /// Re-evaluates deferred Inbox items against a caller-provided local time.
    /// The UI invokes this on its minute boundary while tests inject exact
    /// values, avoiding sleeps and global clock overrides in business logic.
    public func refreshInboxReviewAvailability(at referenceDate: Date = Date()) {
        inboxVisibilityReferenceDate = referenceDate
        refreshDerivedReadModels(on: referenceDate, calendar: readModelCalendarProvider())
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    public func ensureSelectedInboxTaskIsVisible() {
        refreshInboxCaptureCacheForInbox()
        // Inbox actions and voice metadata are contextual; auto-selecting the
        // first visible item prevents a loaded Inbox from presenting disabled
        // classification controls with available work hidden in the list.
        ensureSelectedTaskIsVisibleInInboxFilter()
    }

    public func todayTasks(on referenceDate: Date = Date(), calendar: Calendar = .current) -> [ProjectBoardTask] {
        todayTasks(
            on: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func todayTasks(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> [ProjectBoardTask] {
        guard let endOfToday = calendar.dateInterval(of: .day, for: referenceDate)?.end else {
            return []
        }

        return inputs.visibleNonArchivedTasks
            .filter { task in
                dueDate(for: task.dueAt, calendar: calendar).map { $0 < endOfToday } == true
            }
            .sorted { lhs, rhs in
                switch (dueDate(for: lhs.dueAt, calendar: calendar), dueDate(for: rhs.dueAt, calendar: calendar)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.id > rhs.id
                    }
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id > rhs.id
                }
            }
    }

    public func unscheduledScheduleTasks() -> [ProjectBoardTask] {
        let draftedTaskIDs = Set(scheduleDraft?.timeBlocks.map(\.task.id) ?? [])
        return unscheduledScheduleTasks(
            excludingTaskIDs: draftedTaskIDs,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func unscheduledScheduleTasks(excludingTaskIDs excludedTaskIDs: Set<Int64>) -> [ProjectBoardTask] {
        unscheduledScheduleTasks(
            excludingTaskIDs: excludedTaskIDs,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func unscheduledScheduleTasks(
        excludingTaskIDs excludedTaskIDs: Set<Int64>,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> [ProjectBoardTask] {
        inputs.committedActiveProjects
            .flatMap(\.tasks)
            .filter { task in
                task.status != .done && task.dueAt == nil && !excludedTaskIDs.contains(task.id)
            }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank < rhs.priority.sortRank
                }
                return lhs.id > rhs.id
            }
    }

    public func dailyWorkloadOverview(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current,
        visibleDayCount: Int = 7
    ) -> DailyWorkloadOverview {
        dailyWorkloadOverview(
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: visibleDayCount,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks,
                inboxUntriagedCountOverride: inboxUnprocessedCount(at: referenceDate)
            )
        )
    }

    private func dailyWorkloadOverview(
        around referenceDate: Date,
        calendar: Calendar,
        visibleDayCount: Int = 7,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> DailyWorkloadOverview {
        DailyWorkloadDashboardBuilder.overview(
            committedProjects: inputs.committedActiveProjects,
            inboxUntriagedCount: inputs.inboxUntriagedCount,
            around: referenceDate,
            calendar: calendar,
            visibleDayCount: visibleDayCount
        )
    }

    public func weeklyScheduleCockpit(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> WeeklyScheduleCockpit {
        let workload = dailyWorkloadOverview(around: referenceDate, calendar: calendar)
        return WeeklyScheduleCockpitBuilder.cockpit(
            from: snapshot,
            workload: workload,
            scheduleDraft: scheduleDraft,
            around: referenceDate,
            calendar: calendar
        )
    }

    private func weeklyScheduleCockpit(
        around referenceDate: Date,
        calendar: Calendar,
        workload: DailyWorkloadOverview,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> WeeklyScheduleCockpit {
        WeeklyScheduleCockpitBuilder.cockpit(
            projectTitles: Dictionary(uniqueKeysWithValues: inputs.nonArchivedProjects.map { ($0.id, $0.title) }),
            completionHistoryTasks: inputs.committedActiveProjects.flatMap(\.tasks),
            workload: workload,
            scheduleDraft: scheduleDraft,
            around: referenceDate,
            calendar: calendar
        )
    }

    public func refreshDerivedReadModels() {
        rebuildDerivedReadModels(on: readModelNow(), calendar: readModelCalendarProvider())
    }

    public func refreshDerivedReadModels(on referenceDate: Date, calendar: Calendar = .current) {
        rebuildDerivedReadModels(on: referenceDate, calendar: calendar)
    }

    public func invalidateTodayWorkflowSnapshot(_ reason: TodaySnapshotInvalidationReason) {
        // A revision is cheaper and safer than attempting to diff every task:
        // all store mutations already pass through load(), while the day key
        // separately handles midnight, DST, timezone, and calendar changes.
        todaySnapshotSourceRevision &+= 1
        dailyPlanningReviewPreviewCache.invalidate()
    }

    public func refreshScheduleReadModel() {
        rebuildScheduleReadModel(around: readModelNow(), calendar: readModelCalendarProvider())
        refreshExternalScheduleEvents()
    }

    public func refreshScheduleReadModel(around referenceDate: Date, calendar: Calendar = .current) {
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        refreshExternalScheduleEvents(around: referenceDate, calendar: calendar)
    }

    public func refreshExternalScheduleEvents(
        around referenceDate: Date? = nil,
        calendar: Calendar? = nil,
        force: Bool = false
    ) {
        guard let externalScheduleEventSource else {
            externalScheduleEvents = []
            externalScheduleEventLoadState = .unavailable
            externalScheduleEventInterval = nil
            return
        }
        let resolvedCalendar = calendar ?? derivedReadModelCalendar
        let resolvedDate = referenceDate ?? derivedReadModelReferenceDate ?? readModelNow()
        guard let interval = resolvedCalendar.dateInterval(of: .weekOfYear, for: resolvedDate) else {
            externalScheduleEvents = []
            externalScheduleEventLoadState = .failed
            return
        }
        if force == false,
           interval == externalScheduleEventInterval,
           (externalScheduleEventLoadState == .loaded || externalScheduleEventLoadState == .loading) {
            return
        }

        externalScheduleEventRefreshRevision &+= 1
        let refreshRevision = externalScheduleEventRefreshRevision
        externalScheduleEventInterval = interval
        externalScheduleEventLoadState = .loading

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try externalScheduleEventSource.listEvents(in: interval) }
            }.value
            guard let self, self.externalScheduleEventRefreshRevision == refreshRevision else { return }
            switch result {
            case let .success(events):
                self.externalScheduleEvents = events.sorted { $0.startAt < $1.startAt }
                self.externalScheduleEventLoadState = .loaded
            case .failure:
                // Calendar contents and provider errors remain transient and are never persisted or logged.
                self.externalScheduleEvents = []
                self.externalScheduleEventLoadState = .failed
            }
        }
    }

    private func rebuildDerivedReadModels(on referenceDate: Date, calendar: Calendar) {
        let inputs = ProjectBoardDerivedReadModelInputs(
            snapshot: snapshot,
            showsCompletedWorkflowTasks: showsCompletedWorkflowTasks,
            inboxUntriagedCountOverride: inboxUnprocessedCount(at: referenceDate)
        )
        let todayPlan = todayPlan(on: referenceDate, calendar: calendar, inputs: inputs)
        let workloadOverview = dailyWorkloadOverview(
            around: referenceDate,
            calendar: calendar,
            inputs: inputs
        )
        let planningDayKey = PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        let dailyPlanningReviewPreview = makeCachedDailyPlanningReviewPreview(
            plan: todayPlan,
            workload: workloadOverview,
            referenceDate: referenceDate,
            calendar: calendar,
            planningDayKey: planningDayKey
        )
        let todayWorkflowSnapshot = todayWorkflowSnapshot(
            from: todayPlan,
            on: referenceDate,
            calendar: calendar,
            planningDayKey: planningDayKey,
            dailyPlanningReviewPreview: dailyPlanningReviewPreview
        )
        let scheduleReadModel = makeScheduleReadModel(
            around: referenceDate,
            calendar: calendar,
            workloadOverview: workloadOverview,
            inputs: inputs
        )
        let doneAnalytics = doneAnalytics(on: referenceDate, calendar: calendar, inputs: inputs)
        let portfolioSummaries = projectPortfolioSummaries(on: referenceDate, calendar: calendar, inputs: inputs)
        let missedReview = missedTaskReview(on: referenceDate, calendar: calendar, inputs: inputs)

        derivedReadModelReferenceDate = referenceDate
        derivedReadModelCalendar = calendar

        // SwiftUI body rendering reads this compact model so repeated sidebar and
        // workflow updates do not rescan every project/task or refresh local stores.
        derivedReadModels = ProjectBoardDerivedReadModels(
            sidebarMetrics: ProjectBoardSidebarMetrics(
                inboxCount: inputs.inboxUntriagedCount,
                todayCount: todayWorkflowSnapshot.plan.tasks.count,
                catchUpCount: missedReview.newlyMissedCount,
                scheduleCount: scheduleReadModel.unscheduledTasks.count,
                doneCount: doneAnalytics.completedTaskCount,
                projectsCount: portfolioSummaries.count
            ),
            todayWorkflowSnapshot: todayWorkflowSnapshot,
            schedule: scheduleReadModel,
            doneAnalytics: doneAnalytics,
            missedTaskReview: missedReview,
            projectPortfolioSummaries: portfolioSummaries,
            builtAt: referenceDate
        )
    }

    private func rebuildScheduleReadModel(around referenceDate: Date, calendar: Calendar) {
        var nextReadModels = derivedReadModels
        let scheduleReadModel = makeScheduleReadModel(around: referenceDate, calendar: calendar)
        nextReadModels.schedule = scheduleReadModel
        nextReadModels.sidebarMetrics.scheduleCount = scheduleReadModel.unscheduledTasks.count
        derivedReadModels = nextReadModels
    }

    private func makeScheduleReadModel(
        around referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ProjectBoardScheduleReadModel {
        makeScheduleReadModel(
            around: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func makeScheduleReadModel(
        around referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> ProjectBoardScheduleReadModel {
        let workloadOverview = dailyWorkloadOverview(around: referenceDate, calendar: calendar, inputs: inputs)
        return makeScheduleReadModel(
            around: referenceDate,
            calendar: calendar,
            workloadOverview: workloadOverview,
            inputs: inputs
        )
    }

    private func makeScheduleReadModel(
        around referenceDate: Date,
        calendar: Calendar,
        workloadOverview: DailyWorkloadOverview,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> ProjectBoardScheduleReadModel {
        let weeklyCockpit = weeklyScheduleCockpit(
            around: referenceDate,
            calendar: calendar,
            workload: workloadOverview,
            inputs: inputs
        )
        let draftedTaskIDs = Set(scheduleDraft?.timeBlocks.map(\.task.id) ?? [])
        return ProjectBoardScheduleReadModel(
            workloadOverview: workloadOverview,
            weeklyCockpit: weeklyCockpit,
            unscheduledTasks: unscheduledScheduleTasks(excludingTaskIDs: draftedTaskIDs, inputs: inputs)
        )
    }

    private func refreshMissedTaskReviewReadModel(on referenceDate: Date? = nil) {
        let resolvedReferenceDate = referenceDate ?? derivedReadModelReferenceDate ?? readModelNow()
        let inputs = ProjectBoardDerivedReadModelInputs(
            snapshot: snapshot,
            showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
        )
        let summary = missedTaskReview(
            on: resolvedReferenceDate,
            calendar: derivedReadModelCalendar,
            inputs: inputs
        )
        var nextReadModels = derivedReadModels
        nextReadModels.missedTaskReview = summary
        nextReadModels.sidebarMetrics.catchUpCount = summary.newlyMissedCount
        nextReadModels.builtAt = resolvedReferenceDate
        derivedReadModels = nextReadModels
        derivedReadModelReferenceDate = resolvedReferenceDate
    }

    private func refreshTodayDerivedReadModelForSelectionChange() {
        guard let referenceDate = derivedReadModelReferenceDate else {
            return
        }

        // Selection and focus only change the assistant rail. Reusing the
        // existing plan, preview, and chips avoids flattening every project and
        // rebuilding the time-based review for each row selection on MainActor.
        var nextReadModels = derivedReadModels
        nextReadModels.todayWorkflowSnapshot.assistantContext = todayAssistantRailContext(
            plan: nextReadModels.todayWorkflowSnapshot.plan,
            referenceDate: referenceDate,
            calendar: derivedReadModelCalendar
        )
        derivedReadModels = nextReadModels
    }

    private func makeCachedDailyPlanningReviewPreview(
        plan: TodayWorkflowPlan,
        workload: DailyWorkloadOverview,
        referenceDate: Date,
        calendar: Calendar,
        planningDayKey: PlanningDayKey
    ) -> DailyPlanningReview {
        let cacheKey = DailyPlanningReviewPreviewCacheKey(
            planningDayKey: planningDayKey,
            sourceRevision: todaySnapshotSourceRevision,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return dailyPlanningReviewPreviewCache.review(for: cacheKey) {
            // Cache at the derived-model boundary: task/project mutations and
            // date/calendar changes rebuild it, while rendering and selection
            // changes reuse the immutable value without doing board work.
            self.dailyPlanningReviewPreviewBuildCount += 1
            projectBoardRuntimeDiagnosticLogger.notice(
                "suisui.dailyPlanningPreview.buildCount=\(self.dailyPlanningReviewPreviewBuildCount, privacy: .public) temporalKey=\(cacheKey.runtimeDiagnosticTemporalKey, privacy: .public)"
            )
            return DailyPlanningReviewBuilder.review(
                transcript: "Today daily planning review",
                plan: plan,
                workload: workload,
                referenceDate: referenceDate,
                calendar: calendar
            )
        }
    }

    public func todayPlan(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayWorkflowPlan {
        let tasks = todayTasks(on: referenceDate, calendar: calendar)
        return todayPlan(from: tasks, on: referenceDate, calendar: calendar)
    }

    private func todayPlan(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> TodayWorkflowPlan {
        let tasks = todayTasks(on: referenceDate, calendar: calendar, inputs: inputs)
        return todayPlan(from: tasks, on: referenceDate, calendar: calendar)
    }

    private func todayPlan(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> TodayWorkflowPlan {
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let dayStart = dayInterval?.start ?? referenceDate
        let overdueCount = tasks.filter { task in
            dueDate(for: task.dueAt, calendar: calendar).map { $0 < dayStart } == true
        }.count
        let dueTodayCount = tasks.filter { task in
            guard let dayInterval, let dueDate = dueDate(for: task.dueAt, calendar: calendar) else {
                return false
            }
            return dueDate >= dayInterval.start && dueDate < dayInterval.end
        }.count
        let recommendedTask = recommendedTodayTask(from: tasks, on: referenceDate, calendar: calendar)

        return TodayWorkflowPlan(
            tasks: tasks,
            overdueCount: overdueCount,
            dueTodayCount: dueTodayCount,
            recommendedTask: recommendedTask,
            recommendationReason: recommendationReason(for: recommendedTask, on: referenceDate, calendar: calendar),
            timeBlocks: timeBlocks(for: orderedTimeBlockTasks(tasks, recommendedTask: recommendedTask), startingAt: referenceDate, calendar: calendar)
        )
    }

    public func todayWorkflowSnapshot(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayWorkflowSnapshot {
        let plan = todayPlan(on: referenceDate, calendar: calendar)
        return todayWorkflowSnapshot(
            from: plan,
            on: referenceDate,
            calendar: calendar,
            planningDayKey: PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        )
    }

    private func todayWorkflowSnapshot(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> TodayWorkflowSnapshot {
        let plan = todayPlan(on: referenceDate, calendar: calendar, inputs: inputs)
        return todayWorkflowSnapshot(
            from: plan,
            on: referenceDate,
            calendar: calendar,
            planningDayKey: PlanningDayKey(referenceDate: referenceDate, calendar: calendar)
        )
    }

    private func todayWorkflowSnapshot(
        from plan: TodayWorkflowPlan,
        on referenceDate: Date,
        calendar: Calendar,
        planningDayKey: PlanningDayKey,
        dailyPlanningReviewPreview: DailyPlanningReview? = nil
    ) -> TodayWorkflowSnapshot {
        return TodayWorkflowSnapshot(
            plan: plan,
            assistantContext: todayAssistantRailContext(
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            recommendationChips: todayRecommendationChips(
                from: plan.tasks,
                on: referenceDate,
                calendar: calendar
            ),
            planningDayKey: planningDayKey,
            dailyPlanningReviewPreview: dailyPlanningReviewPreview
        )
    }

    public func makeDailyPlanningReview(
        transcript: String,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningReview {
        DailyPlanningReviewBuilder.review(
            transcript: transcript,
            plan: todayPlan(on: referenceDate, calendar: calendar),
            workload: dailyWorkloadOverview(around: referenceDate, calendar: calendar),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    @discardableResult
    public func prepareDailyPlanningReview(
        transcript: String,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DailyPlanningReview {
        let review = makeDailyPlanningReview(
            transcript: transcript,
            on: referenceDate,
            calendar: calendar
        )
        dailyPlanningReview = review
        todayCommandFeedback = String(localized: "Prepared daily planning review.")
        return review
    }

    @discardableResult
    public func ingestAssistantQueueAutomationRequests(from payload: SyncDomainPayload) -> Bool {
        ingestAssistantQueueAutomationRequests(payload.automationRequests)
    }

    @discardableResult
    public func ingestAssistantQueueAutomationRequests(
        _ requests: [SyncAutomationRequestPayload]
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        guard !requests.isEmpty else {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = nil
            integrationStatusMessage = String(localized: "No remote automation requests to queue.")
            return true
        }

        var queuedItemIDs: [String] = []
        var existingItemIDs: [String] = []
        do {
            for request in requests {
                let item = Self.reviewableAutomationRequestItem(for: request)
                if try assistantQueueStore.insertIfAbsent(item) != nil {
                    queuedItemIDs.append(item.id)
                } else {
                    existingItemIDs.append(item.id)
                }
            }

            if let focusedID = queuedItemIDs.first ?? existingItemIDs.first {
                focusAssistantQueueItem(id: focusedID)
            } else {
                _ = refreshAssistantQueueSnapshot()
            }
            errorMessage = nil
            integrationStatusMessage = Self.automationRequestIngestMessage(
                queuedCount: queuedItemIDs.count,
                existingCount: existingItemIDs.count
            )
            if !queuedItemIDs.isEmpty {
                onChange()
            }
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private static func reviewableAutomationRequestItem(
        for request: SyncAutomationRequestPayload
    ) -> AssistantQueueItem {
        var item = AssistantQueueAdapter.makeItem(automationRequest: sanitizedAutomationRequest(request))
        guard item.state != .rejected,
              AssistantQueueExecutableActionPlanFactory.actionPlan(for: item.payload) == nil else {
            return item
        }

        item.state = .blocked
        item.blockingReason = String(localized: "Remote automation request is missing executable task or development PR details.")
        return item
    }

    private static func sanitizedAutomationRequest(
        _ request: SyncAutomationRequestPayload
    ) -> SyncAutomationRequestPayload {
        var sanitized = request
        sanitized.id = sanitizedAutomationRequestID(for: request)
        sanitized.sourceClientID = sanitizedAutomationMetadata(request.sourceClientID, maxLength: 160)
        sanitized.toolName = sanitizedAutomationMetadata(request.toolName, maxLength: 160)
        sanitized.redactedArgumentSummary = sanitizedAutomationMetadata(
            request.redactedArgumentSummary,
            maxLength: 1_200
        )
        if var pullRequest = sanitized.developmentPullRequest {
            pullRequest.pullRequestURL = sanitizedAutomationMetadata(pullRequest.pullRequestURL, maxLength: 500)
            pullRequest.branchName = sanitizedAutomationMetadata(pullRequest.branchName, maxLength: 240)
            pullRequest.baseBranch = sanitizedAutomationMetadata(pullRequest.baseBranch, maxLength: 240)
            sanitized.developmentPullRequest = pullRequest
        }
        return sanitized
    }

    private static func sanitizedAutomationRequestID(
        for request: SyncAutomationRequestPayload
    ) -> String {
        // Remote request IDs can originate outside the Mac trust boundary. Hashing
        // keeps replay identity stable without persisting secrets or unbounded IDs.
        let digestInput = "\(request.source.rawValue):\(request.id.trimmingCharacters(in: .whitespacesAndNewlines))"
        let digest = SHA256.hash(data: Data(digestInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "remote-\(digest.prefix(24))"
    }

    private static func sanitizedAutomationMetadata(
        _ value: String?,
        maxLength: Int
    ) -> String? {
        guard let value else {
            return nil
        }

        let sanitized = sanitizedAutomationMetadata(value, maxLength: maxLength)
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func sanitizedAutomationMetadata(
        _ value: String,
        maxLength: Int
    ) -> String {
        let redacted = DeveloperSecretRedactor()
            .redact(value.trimmingCharacters(in: .whitespacesAndNewlines))
            .text
        let localPathRedacted = LocalPathRedactor.redact(redacted)
        guard localPathRedacted.count > maxLength else {
            return localPathRedacted
        }
        return "\(localPathRedacted.prefix(maxLength))..."
    }

    private static func automationRequestIngestMessage(
        queuedCount: Int,
        existingCount: Int
    ) -> String {
        if queuedCount == 1, existingCount == 0 {
            return String(localized: "Queued 1 remote automation request for review.")
        }
        if queuedCount > 1, existingCount == 0 {
            return String(localized: "Queued \(queuedCount) remote automation requests for review.")
        }
        if queuedCount == 0, existingCount == 1 {
            return String(localized: "Remote automation request is already in Assistant Queue.")
        }
        if queuedCount == 0, existingCount > 1 {
            return String(localized: "Remote automation requests are already in Assistant Queue.")
        }
        return String(localized: "Queued \(queuedCount) remote automation requests for review; \(existingCount) were already in Assistant Queue.")
    }

    @discardableResult
    public func enqueueDoneFollowUpDraft(
        for taskID: Int64,
        sourceTranscript: String = "Done follow-up draft",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        guard let task = task(id: taskID),
              let draft = DoneFollowUpActionDraftBuilder.makeDraft(
                task: task,
                projectTitle: projectTitle(for: task),
                referenceDate: referenceDate,
                calendar: calendar
              ) else {
            errorMessage = String(localized: "Select a completed task before queuing a Done follow-up.")
            integrationStatusMessage = nil
            return false
        }

        let validation = ActionPlanValidator().validate(draft.actionPlan)
        guard validation.isValid else {
            errorMessage = String(localized: "Done follow-up generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: draft.actionPlan,
            sourceTranscript: Self.sanitizedDoneFollowUpSourceTranscript(sourceTranscript),
            interpretationSummary: String(localized: "Done follow-up draft"),
            reason: draft.queueReason,
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Done follow-up draft is already in Assistant Queue.")
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Queued Done follow-up draft for approval.")
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func enqueueDailyPlanningActionDraft(
        kind: DailyPlanningActionDraftKind,
        transcript: String = "Today daily planning review",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        // An explicit action request owns its transcript/date/calendar. Only a
        // previously prepared review may override those arguments; the passive
        // Today preview must never silently become an action input.
        let review = dailyPlanningReview
            ?? makeDailyPlanningReview(
                transcript: transcript,
                on: referenceDate,
                calendar: calendar
            )
        dailyPlanningReview = review

        guard let recommendedTaskID = review.recommendedTaskID,
              let recommendedTask = task(id: recommendedTaskID),
              let draft = DailyPlanningActionDraftBuilder.makeDraft(
                kind: kind,
                review: review,
                task: recommendedTask,
                referenceDate: referenceDate,
                calendar: calendar
              ) else {
            errorMessage = String(localized: "Daily Planning Review has no recommended task to queue.")
            integrationStatusMessage = nil
            return false
        }

        let validation = ActionPlanValidator().validate(draft.actionPlan)
        guard validation.isValid else {
            errorMessage = String(localized: "Daily Planning Review generated an invalid action plan.")
            integrationStatusMessage = nil
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: draft.actionPlan,
            sourceTranscript: Self.sanitizedDailyPlanningSourceTranscript(review.sourceTranscript),
            interpretationSummary: review.headline,
            reason: draft.queueReason,
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Daily Planning Review action is already in Assistant Queue.")
                todayCommandFeedback = integrationStatusMessage
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Queued Daily Planning Review action for approval.")
            todayCommandFeedback = integrationStatusMessage
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func enqueueTodayReminderDraft(
        for taskID: Int64,
        sourceTranscript: String = "Today reminder draft",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        enqueueReminderDraft(
            for: taskID,
            sourceTranscript: sourceTranscript,
            on: referenceDate,
            calendar: calendar,
            planIDPrefix: "today-reminder",
            actionIDPrefix: "today-reminder-task",
            userInput: "Queue Today reminder for approval",
            summary: "Today reminder draft for 1 task.",
            interpretationSummary: String(localized: "Today reminder draft"),
            reviewReason: Self.todayReminderQueueReason(taskCount: 1),
            queuedMessage: String(localized: "Queued Today reminder draft for approval."),
            alreadyQueuedMessage: String(localized: "Today reminder draft is already in Assistant Queue."),
            missingTaskMessage: String(localized: "Select an existing Today task before queuing a reminder."),
            fallbackTranscript: String(localized: "Today reminder draft")
        )
    }

    @discardableResult
    public func enqueueScheduleReminderDraft(
        for taskID: Int64,
        sourceTranscript: String = "Schedule smart reminder draft",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        enqueueReminderDraft(
            for: taskID,
            sourceTranscript: sourceTranscript,
            on: referenceDate,
            calendar: calendar,
            planIDPrefix: "schedule-reminder",
            actionIDPrefix: "schedule-reminder-task",
            userInput: "Queue Schedule reminder for approval",
            summary: "Schedule reminder draft for 1 task.",
            interpretationSummary: String(localized: "Schedule reminder draft"),
            reviewReason: Self.scheduleReminderQueueReason(taskCount: 1),
            queuedMessage: String(localized: "Queued Schedule reminder draft for approval."),
            alreadyQueuedMessage: String(localized: "Schedule reminder draft is already in Assistant Queue."),
            missingTaskMessage: String(localized: "Select an existing Schedule task before queuing a reminder."),
            fallbackTranscript: String(localized: "Schedule reminder draft")
        )
    }

    @discardableResult
    private func enqueueReminderDraft(
        for taskID: Int64,
        sourceTranscript: String,
        on referenceDate: Date,
        calendar: Calendar,
        planIDPrefix: String,
        actionIDPrefix: String,
        userInput: String,
        summary: String,
        interpretationSummary: String,
        reviewReason: String,
        queuedMessage: String,
        alreadyQueuedMessage: String,
        missingTaskMessage: String,
        fallbackTranscript: String
    ) -> Bool {
        // Reminders leave Suisui's local task store. Queueing an executable plan
        // keeps the write auditable and approval-gated before EventKit is touched.
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        guard let task = task(id: taskID) else {
            errorMessage = missingTaskMessage
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let plan = makeReminderActionPlan(
            for: task,
            referenceDate: referenceDate,
            calendar: calendar,
            planIDPrefix: planIDPrefix,
            actionIDPrefix: actionIDPrefix,
            userInput: userInput,
            summary: summary
        )
        let validation = ActionPlanValidator().validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Reminder draft generated an invalid action plan.")
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: Self.sanitizedReminderSourceTranscript(sourceTranscript, fallback: fallbackTranscript),
            interpretationSummary: interpretationSummary,
            reason: reviewReason,
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = alreadyQueuedMessage
                todayCommandFeedback = integrationStatusMessage
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = queuedMessage
            todayCommandFeedback = integrationStatusMessage
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func enqueueScheduleDraftCalendarApply(
        sourceTranscript: String = "Schedule draft Calendar apply",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        // Schedule drafts are generated by Suisui, but Calendar writes cross the
        // user's app boundary. Queueing the executable ActionPlan keeps the
        // generated work reviewable before any external event is created.
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return false
        }

        guard let draft = scheduleDraft else {
            errorMessage = String(localized: "Create a schedule draft before queuing Calendar apply.")
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let candidates = scheduleDraftWriteCandidates(for: draft)
        guard !candidates.isEmpty else {
            errorMessage = String(localized: "Schedule draft has no calendar-ready time blocks to queue.")
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let plan = makeScheduleDraftCalendarApplyActionPlan(
            candidates: candidates,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let validation = ActionPlanValidator().validate(plan)
        guard validation.isValid else {
            errorMessage = String(localized: "Schedule draft generated an invalid Calendar action plan.")
            integrationStatusMessage = nil
            todayCommandFeedback = errorMessage
            return false
        }

        let item = AssistantQueueAdapter.makeItem(
            actionPlan: plan,
            sourceTranscript: Self.sanitizedScheduleDraftSourceTranscript(sourceTranscript),
            interpretationSummary: String(localized: "Schedule draft Calendar apply"),
            reason: Self.scheduleDraftQueueReason(candidateCount: candidates.count),
            costPreview: .localOnly()
        )

        do {
            guard try assistantQueueStore.insertIfAbsent(item) != nil else {
                focusAssistantQueueItem(id: item.id)
                errorMessage = nil
                integrationStatusMessage = String(localized: "Schedule draft Calendar apply is already in Assistant Queue.")
                todayCommandFeedback = integrationStatusMessage
                return true
            }

            focusAssistantQueueItem(id: item.id)
            errorMessage = nil
            integrationStatusMessage = String(localized: "Queued Schedule draft Calendar apply for approval.")
            todayCommandFeedback = integrationStatusMessage
            onChange()
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    public func playDailyPlanningReviewReadout(
        using previewer: any TextToSpeechPreviewing,
        languageCode: String,
        voiceID: String,
        transcript: String = "Today daily planning review",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        await playDailyPlanningReviewReadout(
            using: previewer,
            languageCode: languageCode,
            voiceID: voiceID,
            provider: .localKokoro,
            transcript: transcript,
            on: referenceDate,
            calendar: calendar
        )
    }

    @discardableResult
    public func playDailyPlanningReviewReadout(
        using previewer: any TextToSpeechPreviewing,
        languageCode: String,
        voiceID: String,
        provider: TTSProvider,
        transcript: String = "Today daily planning review",
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async -> Bool {
        // Readout callers with explicit inputs must receive a review built from
        // those inputs unless the user already prepared an explicit review.
        let review = dailyPlanningReview
            ?? makeDailyPlanningReview(
                transcript: transcript,
                on: referenceDate,
                calendar: calendar
            )
        dailyPlanningReview = review

        let request = DailyPlanningReviewReadoutBuilder.makeRequest(
            review: review,
            languageCode: languageCode,
            voiceID: voiceID,
            provider: provider
        )

        do {
            try await previewer.playPreview(request)
            integrationStatusMessage = nil
            todayCommandFeedback = String(localized: "Read daily planning review aloud.")
            return true
        } catch {
            integrationStatusMessage = nil
            todayCommandFeedback = Self.dailyPlanningReadoutFailureMessage(for: error)
            return false
        }
    }

    public func todayAssistantRailContext(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayAssistantRailContext {
        todayAssistantRailContext(
            plan: todayPlan(on: referenceDate, calendar: calendar),
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    private func todayAssistantRailContext(
        plan: TodayWorkflowPlan,
        referenceDate: Date,
        calendar: Calendar
    ) -> TodayAssistantRailContext {
        // Keep explicit focus ahead of selection so the rail reflects the user's active work.
        if let todayFocusTaskID,
           let focusedTask = plan.tasks.first(where: { $0.id == todayFocusTaskID && $0.status != .done }) {
            return todayAssistantRailContext(
                source: .focused,
                task: focusedTask,
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar,
                nextActionTitle: String(localized: "Resume focused task"),
                nextActionReason: String(localized: "This task is already in focus.")
            )
        }

        if let selectedTask = selectedTask,
           plan.tasks.contains(where: { $0.id == selectedTask.id }) {
            return todayAssistantRailContext(
                source: .selected,
                task: selectedTask,
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar,
                nextActionTitle: String(localized: "Review selected task"),
                nextActionReason: String(localized: "You selected this Today task for review.")
            )
        }

        if let recommendedTask = plan.recommendedTask {
            return todayAssistantRailContext(
                source: .recommended,
                task: recommendedTask,
                plan: plan,
                referenceDate: referenceDate,
                calendar: calendar,
                nextActionTitle: String(localized: "Start recommended task"),
                nextActionReason: plan.recommendationReason
            )
        }

        return TodayAssistantRailContext(
            source: .empty,
            task: nil,
            projectTitle: String(localized: "No project selected"),
            nextActionTitle: String(localized: "Capture the next task"),
            nextActionReason: plan.recommendationReason,
            nextBlockLabel: nil,
            notes: String(localized: "Add a Today command or schedule Inbox work to create a focus path."),
            // Subtasks remain local command drafts. Reminder writes now cross an
            // app boundary, so the rail points users to Assistant Queue review.
            subtaskSummary: String(localized: "Subtask capture is staged through the Today command."),
            reminderSummary: String(localized: "Reminder drafts queue for approval before external writes.")
        )
    }

    @discardableResult
    public func submitTodayCommand(_ rawTitle: String) -> ProjectBoardTask? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            todayCommandFeedback = String(localized: "Today command needs a title.")
            return nil
        }

        let task = createInboxTask(title: title)
        if task != nil {
            todayCommandFeedback = String(format: String(localized: "Added \"%@\" to Inbox."), title)
        }
        return task
    }

    /// Records a local break suggestion for the Today review surface. This is
    /// deliberately feedback-only: it does not create a task or write to any
    /// Calendar/Reminder provider from a recommendation card.
    public func suggestTodayBreak() {
        todayCommandFeedback = String(localized: "Take a short break before the next task.")
    }

    public func todayRecommendationChips(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [TodayRecommendationChip] {
        todayRecommendationChips(
            from: todayTasks(on: referenceDate, calendar: calendar),
            on: referenceDate,
            calendar: calendar
        )
    }

    private func todayRecommendationChips(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [TodayRecommendationChip] {
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        var usedTaskIDs = Set<Int64>()

        func firstTask(
            matching predicate: (ProjectBoardTask) -> Bool
        ) -> ProjectBoardTask? {
            for task in tasks {
                guard !usedTaskIDs.contains(task.id), predicate(task) else {
                    continue
                }
                return task
            }
            return nil
        }

        var chips: [TodayRecommendationChip] = []
        if let task = firstTask(matching: { $0.status == .blocked }) {
            usedTaskIDs.insert(task.id)
            chips.append(TodayRecommendationChip(
                kind: .blocker,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "Resolve blocker"),
                systemImage: "exclamationmark.triangle",
                reason: String(format: String(localized: "%@ is blocking today's plan."), task.title)
            ))
        }
        if let task = firstTask(matching: { dueDate(for: $0.dueAt, calendar: calendar).map { $0 < dayStart } == true }) {
            usedTaskIDs.insert(task.id)
            chips.append(TodayRecommendationChip(
                kind: .overdue,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "Clear overdue"),
                systemImage: "clock.badge.exclamationmark",
                reason: String(format: String(localized: "%@ is overdue."), task.title)
            ))
        }
        if let task = firstTask(matching: { $0.priority == .high }) {
            chips.append(TodayRecommendationChip(
                kind: .highPriority,
                taskID: task.id,
                taskTitle: task.title,
                title: String(localized: "High priority"),
                systemImage: "flag.fill",
                reason: String(format: String(localized: "%@ is high priority."), task.title)
            ))
        }

        return chips
    }

    public func missedTaskReview(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current,
        staleAfterDays: Int = 7
    ) -> MissedTaskReviewSummary {
        missedTaskReview(
            on: referenceDate,
            calendar: calendar,
            staleAfterDays: staleAfterDays,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func missedTaskReview(
        on referenceDate: Date,
        calendar: Calendar,
        staleAfterDays: Int = 7,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> MissedTaskReviewSummary {
        guard let dayInterval = calendar.dateInterval(of: .day, for: referenceDate) else {
            return .empty
        }

        let staleCutoff = calendar.date(byAdding: .day, value: -max(staleAfterDays, 1), to: dayInterval.start) ?? dayInterval.start
        var didFailToLoadReviewState = false
        let items = inputs.committedActiveProjects
            .flatMap { project in
                project.tasks.compactMap { task -> MissedTaskReviewItem? in
                    guard task.status != .done else {
                        return nil
                    }

                    let reasons = missedTaskReasons(
                        for: task,
                        dayInterval: dayInterval,
                        staleCutoff: staleCutoff
                    )
                    guard !reasons.isEmpty else {
                        return nil
                    }

                    let reviewState = missedTaskReviewState(
                        taskID: task.id,
                        referenceDate: referenceDate,
                        calendar: calendar,
                        didFail: &didFailToLoadReviewState
                    )
                    return MissedTaskReviewItem(
                        task: task,
                        projectTitle: project.title,
                        reasons: reasons,
                        lastReviewedAt: reviewState.lastReviewedAt,
                        isNewlyMissed: reviewState.isNewlyMissed
                    )
                }
            }
            .sorted(by: sortMissedTaskReviewItems)

        let immediateQueue = items
            .filter { $0.isNewlyMissed && isImmediateMissedTask($0) }
            .sorted(by: sortMissedTaskReviewItems)

        return MissedTaskReviewSummary(
            items: items,
            immediateQueue: immediateQueue,
            overdueCount: items.filter { $0.reasons.contains(.overdue) }.count,
            dueTodayCount: items.filter { $0.reasons.contains(.dueToday) }.count,
            blockedCount: items.filter { $0.reasons.contains(.blocked) }.count,
            unscheduledCount: items.filter { $0.reasons.contains(.unscheduled) }.count,
            staleCount: items.filter { $0.reasons.contains(.stale) }.count,
            newlyMissedCount: immediateQueue.count,
            stateErrorMessage: didFailToLoadReviewState ? String(localized: "Missed task review state could not be loaded.") : nil
        )
    }

    @discardableResult
    public func scheduleMissedTaskDailyFollowUp(
        settings: AppSettings,
        dateProvider: any DateProvider = SystemDateProvider(),
        calendar: Calendar? = nil
    ) -> MissedTaskDailyFollowUpResult? {
        guard let missedTaskFollowUpNotificationClient else {
            return nil
        }

        let normalizedSettings = settings.normalizedForRuntime
        let reviewCalendar = calendar ?? Self.reviewCalendar(timeZoneIdentifier: normalizedSettings.timeZoneIdentifier)
        let summary = missedTaskReview(on: dateProvider.now, calendar: reviewCalendar)
        let result = MissedTaskDailyFollowUpScheduler(
            stateStore: missedTaskReviewStateStore,
            notificationClient: missedTaskFollowUpNotificationClient,
            dateProvider: dateProvider,
            settings: normalizedSettings
        )
        .scheduleIfNeeded(summary: summary)

        if let assistantQueueStore {
            // Best-effort assistant suggestion: overdue/stalled tasks gain a
            // one-tap "reschedule to tomorrow" item in the Assistant Queue.
            _ = MissedTaskRescheduleSuggestionPlanner(
                queueStore: assistantQueueStore,
                dateProvider: dateProvider,
                settings: normalizedSettings
            ).enqueueSuggestions(for: summary)
        }

        if result.status == .failed {
            integrationStatusMessage = result.message
        }
        return result
    }

    public func completeMissedTask(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()
        do {
            _ = try store.moveTask(id: taskID, to: .done)
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            load()
            recordStatusMoveUndo(
                previousTasks: [task],
                to: .done,
                taskIDsBeforeMutation: taskIDsBeforeMutation
            )
            selectedProjectID = task.projectID
            selectedTaskID = taskID
            todayCommandFeedback = String(format: String(localized: "Completed \"%@\" from missed review."), task.title)
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func rescheduleMissedTaskForToday(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        do {
            let updatedTask = try store.updateTask(
                id: taskID,
                ProjectBoardTaskDraft(
                    projectID: task.projectID,
                    title: task.title,
                    detail: task.detail,
                    status: .planned,
                    priority: task.priority,
                    dueAt: ISO8601DateFormatter().string(from: referenceDate),
                    recurrence: task.recurrence
                )
            )
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            load()
            selectedProjectID = updatedTask.projectID
            selectedTaskID = updatedTask.id
            todayCommandFeedback = String(format: String(localized: "Rescheduled \"%@\" for today."), task.title)
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func deferMissedTaskForLater(id taskID: Int64, referenceDate: Date = Date()) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        do {
            // Deferring from Catch Up is review-state only: it removes the item
            // from today's recovery queue without hiding or mutating the task.
            try missedTaskReviewStateStore.markReviewed(taskID: taskID, at: referenceDate)
            refreshMissedTaskReviewReadModel(on: referenceDate)
            selectedProjectID = task.projectID
            selectedTaskID = task.id
            todayCommandFeedback = String(format: String(localized: "Deferred \"%@\" from today's missed queue."), task.title)
            errorMessage = nil
            onChange()
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func startFocus(taskID: Int64) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            errorMessage = "Task is no longer available."
            return
        }

        // Focus is intentionally local UI state. It must not move task status or
        // write Calendar/Reminder records before the user reviews a schedule.
        todayFocusTaskID = task.id
        selectedProjectID = task.projectID
        selectedTaskID = task.id
        todayCommandFeedback = String(format: String(localized: "Focused on \"%@\"."), task.title)
        errorMessage = nil
    }

    public func startFocusOnRecommendedTask(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard let task = todayPlan(on: referenceDate, calendar: calendar).recommendedTask else {
            todayCommandFeedback = String(localized: "No focus task is available.")
            return
        }
        startFocus(taskID: task.id)
    }

    @discardableResult
    public func prepareTaskAutomationReview(
        settings: TaskAutoExecutionSettings,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        let history = sessionAutomationHistory(for: referenceDate, calendar: calendar)
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )

        // Preparing a local review candidate must not spend the LLM API budget.
        // The session ledger is charged only after a provider request is
        // successfully assembled, so opening the review UI cannot exhaust the
        // user's configured daily automation allowance.
        taskAutomationSessionHistory = history
        return decision
    }

    @discardableResult
    public func prepareTaskAutomationReview(
        settings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TaskAutoExecutionDecision {
        // Whole-board automation must reuse the deterministic planner before
        // any provider request so cadence, lookahead, trigger, and LLM budget
        // settings cannot be bypassed by a UI or future scheduled entry point.
        let decision = TaskAutoExecutionPlanner().makeDecision(
            snapshot: snapshot,
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )

        guard decision.status == .readyForReview else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = decision.reason
            return decision
        }

        taskAutomationReviewDecision = decision
        taskAutomationDocumentDeliverableReviews = []
        if let firstTask = decision.selectedTasks.first {
            selectedProjectID = firstTask.projectID
            selectedTaskID = firstTask.id
        }
        todayCommandFeedback = String(
            format: String(localized: "Prepared review-only automation for %d tasks."),
            decision.selectedTasks.count
        )
        integrationStatusMessage = String(
            format: String(localized: "Prepared review-only automation for %d tasks."),
            decision.selectedTasks.count
        )
        errorMessage = nil
        return decision
    }

    public func makeTaskAutomationPlanningRequest(
        settings: TaskAutoExecutionSettings,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft] = []
    ) throws -> PlanningRequest {
        let history = sessionAutomationHistory(for: referenceDate, calendar: calendar)
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let request = try buildTaskAutomationPlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
        let documentDeliverableReviews = documentDeliverableReviews(from: documentDeliverableDrafts)
        try persistDocumentDeliverableStartReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        )
        taskAutomationDocumentDeliverableReviews = documentDeliverableReviews
        if let receiptPersistenceMessage = saveTaskAutomationDocumentDeliverableReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        ) {
            errorMessage = receiptPersistenceMessage
        }

        // The session budget is charged only after the provider request is
        // successfully assembled. Throttled or invalid review attempts still
        // update feedback but do not consume the daily LLM review allowance.
        taskAutomationSessionHistory = TaskAutoExecutionHistory(
            lastRunAt: referenceDate,
            llmCallsToday: history.llmCallsToday + 1
        )
        return request
    }

    public func makeTaskAutomationPlanningRequest(
        settings: TaskAutoExecutionSettings,
        history: TaskAutoExecutionHistory,
        trigger: TaskAutoExecutionTrigger = .manual,
        referenceDate: Date = Date(),
        calendar: Calendar = .current,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft] = []
    ) throws -> PlanningRequest {
        let decision = prepareTaskAutomationReview(
            settings: settings,
            history: history,
            trigger: trigger,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let request = try buildTaskAutomationPlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
        let documentDeliverableReviews = documentDeliverableReviews(from: documentDeliverableDrafts)
        try persistDocumentDeliverableStartReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        )
        taskAutomationDocumentDeliverableReviews = documentDeliverableReviews
        if let receiptPersistenceMessage = saveTaskAutomationDocumentDeliverableReceipt(
            documentDeliverableReviews,
            selectedTasks: decision.selectedTasks
        ) {
            errorMessage = receiptPersistenceMessage
        }
        return request
    }

    private func buildTaskAutomationPlanningRequest(
        decision: TaskAutoExecutionDecision,
        settings: TaskAutoExecutionSettings,
        referenceDate: Date,
        timeZoneIdentifier: String,
        documentDeliverableDrafts: [DocumentAutomationDeliverableDraft]
    ) throws -> PlanningRequest {
        try TaskAutoExecutionPlanningRequestBuilder().makePlanningRequest(
            decision: decision,
            settings: settings,
            referenceDate: referenceDate,
            timeZoneIdentifier: timeZoneIdentifier,
            documentDeliverableDrafts: documentDeliverableDrafts
        )
    }

    private func sessionAutomationHistory(
        for referenceDate: Date,
        calendar: Calendar
    ) -> TaskAutoExecutionHistory {
        guard let lastRunAt = taskAutomationSessionHistory.lastRunAt,
              calendar.isDate(lastRunAt, inSameDayAs: referenceDate) else {
            return TaskAutoExecutionHistory(lastRunAt: taskAutomationSessionHistory.lastRunAt, llmCallsToday: 0)
        }
        return taskAutomationSessionHistory
    }

    public func prepareAutomationReviewForSelectedTask() {
        guard let selectedTask else {
            todayCommandFeedback = String(localized: "Select a task before reviewing automation.")
            return
        }
        guard isEligibleForTaskAutomation(selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Only open unblocked tasks can be reviewed for automation.")
            return
        }

        taskAutomationReviewDecision = TaskAutoExecutionDecision(
            status: .readyForReview,
            selectedTasks: [selectedTask],
            reason: String(localized: "Selected task is ready for review-only automation."),
            llmCallBudgetRemaining: 1,
            requiresUserApproval: true,
            allowsDirectExecution: false
        )
        taskAutomationDocumentDeliverableReviews = []
        integrationStatusMessage = String(format: String(localized: "Prepared review-only automation for \"%@\"."), selectedTask.title)
        errorMessage = nil
    }

    public func runApprovedAutomationForSelectedTask() {
        guard let selectedTask else {
            todayCommandFeedback = String(localized: "Select a task before running automation.")
            return
        }
        guard let reviewDecision = taskAutomationReviewDecision,
              let reviewedTask = reviewDecision.selectedTasks.first(where: { $0.id == selectedTask.id }) else {
            todayCommandFeedback = String(localized: "Review the automation plan before running it.")
            return
        }
        guard isEligibleForTaskAutomation(selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Task automation stopped because the task is blocked or complete.")
            return
        }
        guard matchesReviewedAutomationTask(reviewedTask, current: selectedTask) else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            todayCommandFeedback = String(localized: "Review the automation plan again because the task changed after review.")
            return
        }
        let executionReceipt = ApprovedAutomationExecutionReceipt(
            task: selectedTask,
            statusAfter: .inProgress,
            reviewReason: reviewDecision.reason
        )
        guard executionReceiptStore != nil else {
            _ = markExecutionReceiptStorageUnavailable()
            return
        }
        guard let assistantQueueStore else {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = String(localized: "Assistant Queue is unavailable in this build.")
            integrationStatusMessage = nil
            return
        }
        guard resolvedAssistantQueueExecutionCoordinator != nil else {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = String(localized: "Assistant Queue execution is unavailable in this build.")
            integrationStatusMessage = nil
            return
        }
        do {
            var item = AssistantQueueAdapter.makeItem(
                actionPlan: approvedAutomationActionPlan(
                    for: selectedTask,
                    reviewReason: reviewDecision.reason
                ),
                sourceTranscript: String(localized: "Run approved local task automation."),
                interpretationSummary: String(localized: "Move reviewed task into active work."),
                reason: reviewDecision.reason,
                costPreview: .localOnly()
            )
            // Keep the queue entry non-actionable until the durable start
            // receipt exists. The queue and receipt stores cannot participate
            // in one transaction, so publishing waitingReview first could
            // expose work that has no auditable execution reservation.
            item.state = .blocked
            item.blockingReason = String(localized: "Execution receipt reservation must complete before this automation can be reviewed.")
            guard let inserted = try assistantQueueStore.insertIfAbsent(item) else {
                _ = refreshAssistantQueueSnapshot()
                errorMessage = String(localized: "This reviewed automation is already in Assistant Queue. Review the existing item before running it.")
                integrationStatusMessage = nil
                return
            }
            guard persistApprovedAIWorkStartReceipt(
                ExecutionReceiptFactory.makeApprovedAutomationReceipt(
                    executionReceipt,
                    runID: "approved-automation-start:\(UUID().uuidString)",
                    approvalID: nil,
                    status: .running,
                    createdAt: Date()
                )
            ) == nil else {
                _ = refreshAssistantQueueSnapshot()
                return
            }
            guard let insertedMutationRevision = inserted.mutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            let reviewable = try assistantQueueStore.transition(id: inserted.id) { current in
                guard current.mutationRevision == insertedMutationRevision else {
                    throw AssistantQueueStaleReviewError()
                }
                // This is a publication barrier rather than a user transition:
                // only the successful receipt reservation may expose review
                // controls for this previously blocked provisional item.
                var updated = current
                updated.state = .waitingReview
                updated.blockingReason = nil
                updated.approval = nil
                return updated
            }
            guard let reviewableMutationRevision = reviewable.mutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            let approved = try assistantQueueStore.transition(id: reviewable.id) { current in
                guard current.mutationRevision == reviewableMutationRevision else {
                    throw AssistantQueueStaleReviewError()
                }
                return try AssistantQueueStateMachine.approve(
                    current,
                    reviewerID: "local-user"
                )
            }
            guard let approvedMutationRevision = approved.mutationRevision else {
                throw AssistantQueueStaleReviewError()
            }
            guard runAssistantQueueItem(
                id: approved.id,
                expectedMutationRevision: approvedMutationRevision
            ) else {
                return
            }
            load()
            selectedProjectID = selectedTask.projectID
            selectedTaskID = selectedTask.id
            let receipt = executionReceipt
            lastApprovedAutomationExecutionReceipt = receipt
            approvedAutomationExecutionReceipts.append(receipt)
            let receiptPersistenceMessage = saveApprovedAutomationExecutionReceipt(receipt)
            // Approved automation is still local and review-gated, but it must
            // leave a visible content-execution trail so a status move cannot
            // masquerade as executing the reviewed task body.
            todayCommandFeedback = String(format: String(localized: "Executed approved automation for \"%@\"."), selectedTask.title)
            integrationStatusMessage = String(format: String(localized: "Executed approved automation for \"%@\"."), selectedTask.title)
            errorMessage = receiptPersistenceMessage
            retainUnexecutedReviewedTasks(from: reviewDecision, excludingTaskID: selectedTask.id)
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before running automation."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
        }
    }

    private func saveApprovedAutomationExecutionReceipt(_ receipt: ApprovedAutomationExecutionReceipt) -> String? {
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return Self.executionReceiptStorageUnavailableMessage()
        }

        let commonReceipt = ExecutionReceiptFactory.makeApprovedAutomationReceipt(
            receipt,
            runID: "approved-automation-run:\(UUID().uuidString)",
            approvalID: nil,
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(commonReceipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            return String(localized: "Approved automation ran, but the execution receipt could not be saved.")
        }
    }

    private func saveScheduleDraftApplyReceipt(
        writeCandidates: [ScheduleDraftApplyWriteCandidate],
        unscheduledTaskCount: Int,
        createdEvents: [ScheduleDraftApplyCreatedEvent],
        approvalID: String?,
        status: ExecutionReceiptStatus,
        errorSummary: String? = nil
    ) -> String? {
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return Self.executionReceiptStorageUnavailableMessage()
        }

        let projectTitlesByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
        let receipt = ExecutionReceiptFactory.makeScheduleDraftApplyReceipt(
            writeCandidates: writeCandidates,
            unscheduledTaskCount: unscheduledTaskCount,
            createdEvents: createdEvents,
            projectTitlesByID: projectTitlesByID,
            runID: "schedule-draft-apply-run:\(UUID().uuidString)",
            approvalID: approvalID,
            status: status,
            errorSummary: errorSummary,
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            if status == .failed {
                return String(localized: "Calendar apply failed, and the execution receipt could not be saved.")
            }
            if status == .skipped {
                return String(localized: "Schedule apply was skipped, and the execution receipt could not be saved.")
            }
            return String(localized: "Schedule applied to Calendar, but the execution receipt could not be saved.")
        }
    }

    private func saveTaskAutomationDocumentDeliverableReceipt(
        _ deliverables: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask]
    ) -> String? {
        guard !deliverables.isEmpty else {
            return nil
        }
        guard let executionReceiptStore else {
            refreshExecutionReceiptHistorySnapshot()
            return Self.executionReceiptStorageUnavailableMessage()
        }

        let receipt = ExecutionReceiptFactory.makeDocumentDeliverableReceipt(
            deliverables: deliverables,
            selectedTasks: selectedTasks,
            runID: "document-deliverable-run:\(UUID().uuidString)",
            createdAt: Date()
        )
        do {
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            refreshExecutionReceiptHistorySnapshot()
            return String(localized: "Document deliverable drafts were prepared, but the execution receipt could not be saved.")
        }
    }

    private static func scheduleDraftApplyApprovalID() -> String {
        "schedule-draft-apply-approval:\(UUID().uuidString)"
    }

    private static func executionReceiptStorageUnavailableMessage() -> String {
        String(localized: "Execution receipt storage is unavailable. Fix receipt storage before running approved AI work.")
    }

    private func markExecutionReceiptStorageUnavailable() -> String {
        let message = Self.executionReceiptStorageUnavailableMessage()
        refreshExecutionReceiptHistorySnapshot()
        // Approved AI work must never complete without durable receipt storage;
        // otherwise the user cannot audit what was read, changed, sent, or billed.
        todayCommandFeedback = message
        integrationStatusMessage = message
        errorMessage = message
        return message
    }

    private func persistApprovedAIWorkStartReceipt(_ receipt: ExecutionReceipt) -> String? {
        guard let executionReceiptStore else {
            return markExecutionReceiptStorageUnavailable()
        }
        do {
            // This reservation is intentionally persisted before any approved
            // write or review-evidence exposure so receipt storage failures
            // cannot leave unauditable AI work behind.
            try executionReceiptStore.save(receipt)
            refreshExecutionReceiptHistorySnapshot()
            return nil
        } catch {
            return markExecutionReceiptStorageUnavailable()
        }
    }

    private func persistDocumentDeliverableStartReceipt(
        _ documentDeliverableReviews: [TaskAutomationDocumentDeliverableReview],
        selectedTasks: [ProjectBoardTask]
    ) throws {
        guard !documentDeliverableReviews.isEmpty else {
            return
        }
        let receipt = ExecutionReceiptFactory.makeDocumentDeliverableReceipt(
            deliverables: documentDeliverableReviews,
            selectedTasks: selectedTasks,
            runID: "document-deliverable-start:\(UUID().uuidString)",
            status: .running,
            createdAt: Date()
        )
        guard persistApprovedAIWorkStartReceipt(receipt) == nil else {
            taskAutomationDocumentDeliverableReviews = []
            throw TaskAutoExecutionPlanningRequestError.executionReceiptStoreUnavailable
        }
    }

    private func scheduleDraftWriteCandidates(for draft: ScheduleDraft) -> [ScheduleDraftApplyWriteCandidate] {
        draft.timeBlocks.compactMap(ScheduleDraftApplyWriteCandidate.init(block:))
    }

    private func makeReminderActionPlan(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar,
        planIDPrefix: String,
        actionIDPrefix: String,
        userInput: String,
        summary: String
    ) -> ActionPlan {
        var arguments: [String: JSONValue] = [
            "title": .string(Self.reminderTitle(for: task)),
            "taskId": .number(Double(task.id)),
            "projectId": .number(Double(task.projectID))
        ]
        if let dueAt = Self.trimmedOptional(task.dueAt) {
            arguments["dueAt"] = .string(dueAt)
        }

        return ActionPlan(
            id: Self.reminderPlanID(
                for: task,
                referenceDate: referenceDate,
                calendar: calendar,
                prefix: planIDPrefix
            ),
            userInput: userInput,
            summary: summary,
            actions: [
                PlanAction(
                    id: "\(actionIDPrefix)-\(task.id)",
                    tool: .remindersCreate,
                    arguments: arguments,
                    riskLevel: .write
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func reminderTitle(for task: ProjectBoardTask) -> String {
        String(format: String(localized: "Reminder for %@"), task.title)
    }

    private static func reminderPlanID(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar,
        prefix: String
    ) -> String {
        let dayKey = reminderDayKey(referenceDate: referenceDate, calendar: calendar)
        let contentDigest = reminderContentDigest(for: task)
        return "\(prefix):\(dayKey):\(contentDigest):task:\(task.id)"
    }

    private static func reminderContentDigest(for task: ProjectBoardTask) -> String {
        let content = [
            String(task.id),
            String(task.projectID),
            task.title,
            trimmedOptional(task.dueAt) ?? ""
        ].joined(separator: "|")
        // The Queue identity must change when the reminder write changes, but
        // exposing task titles in IDs would leak user work into logs and URLs.
        let digest = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    private static func reminderDayKey(referenceDate: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: referenceDate)
    }

    private static func todayReminderQueueReason(taskCount: Int) -> String {
        if taskCount == 1 {
            return String(localized: "Today assistant suggested a Reminders draft for 1 task.")
        }
        return String(format: String(localized: "Today assistant suggested Reminders drafts for %d tasks."), taskCount)
    }

    private static func scheduleReminderQueueReason(taskCount: Int) -> String {
        if taskCount == 1 {
            return String(localized: "Schedule assistant suggested a Reminders draft for 1 task.")
        }
        return String(format: String(localized: "Schedule assistant suggested Reminders drafts for %d tasks."), taskCount)
    }

    private static func sanitizedDoneFollowUpSourceTranscript(_ sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = ExecutionReceiptRedactor().redact(trimmed)
        let fallback = String(localized: "Done follow-up draft")
        guard !redacted.isEmpty else {
            return fallback
        }
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func sanitizedReminderSourceTranscript(_ sourceTranscript: String, fallback: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = DeveloperSecretRedactor().redact(trimmed).text
        guard !redacted.isEmpty else {
            return fallback
        }
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func sanitizedDailyPlanningSourceTranscript(_ sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = ExecutionReceiptRedactor().redact(trimmed)
        let fallback = String(localized: "Today daily planning review")
        guard !redacted.isEmpty else {
            return fallback
        }
        // Daily planning transcripts are durable Queue audit context, so keep
        // enough intent for review while avoiding secret/path retention.
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func makeScheduleDraftCalendarApplyActionPlan(
        candidates: [ScheduleDraftApplyWriteCandidate],
        referenceDate: Date,
        calendar: Calendar
    ) -> ActionPlan {
        ActionPlan(
            id: Self.scheduleDraftCalendarApplyPlanID(
                candidates: candidates,
                referenceDate: referenceDate,
                calendar: calendar
            ),
            userInput: "Queue reviewed Schedule draft for Calendar apply",
            summary: Self.scheduleDraftCalendarApplySummary(candidateCount: candidates.count),
            actions: candidates.enumerated().compactMap { offset, candidate in
                guard let durationMinutes = Self.scheduleDraftDurationMinutes(for: candidate) else {
                    return nil
                }
                return PlanAction(
                    id: "calendar-work-block-\(offset + 1)-task-\(candidate.taskID)",
                    tool: .calendarCreateWorkBlock,
                    arguments: [
                        "title": .string(candidate.taskTitle),
                        "startAt": .string(candidate.startAt),
                        "durationMinutes": .number(Double(durationMinutes)),
                        "notes": .string(String(localized: "Created from a reviewed Suisui schedule draft.")),
                        "taskId": .number(Double(candidate.taskID)),
                        "projectId": .number(Double(candidate.projectID))
                    ],
                    riskLevel: .write
                )
            },
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func scheduleDraftCalendarApplyPlanID(
        candidates: [ScheduleDraftApplyWriteCandidate],
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let dayKey = scheduleDraftDayKey(referenceDate: referenceDate, calendar: calendar)
        let contentDigest = scheduleDraftContentDigest(candidates: candidates)
        let taskSegment = candidates.map { String($0.taskID) }.joined(separator: "-")
        let suffix = taskSegment.isEmpty ? "empty" : taskSegment
        return "schedule-draft-calendar-apply:\(dayKey):\(contentDigest):task:\(suffix)"
    }

    private static func scheduleDraftContentDigest(candidates: [ScheduleDraftApplyWriteCandidate]) -> String {
        let content = candidates.map { candidate in
            [
                String(candidate.taskID),
                String(candidate.projectID),
                candidate.taskTitle,
                candidate.startAt,
                candidate.endAt
            ].joined(separator: "|")
        }.joined(separator: "\n")
        // The Queue item ID must change when the reviewed Calendar write changes,
        // but it must not leak task titles. A short SHA-256 prefix keeps identity
        // stable for duplicate detection while preventing stale payload reuse.
        let digest = SHA256.hash(data: Data(content.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(16))
    }

    private static func scheduleDraftDayKey(referenceDate: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: referenceDate)
    }

    private static func scheduleDraftCalendarApplySummary(candidateCount: Int) -> String {
        if candidateCount == 1 {
            return "Schedule draft Calendar apply for 1 work block."
        }
        return "Schedule draft Calendar apply for \(candidateCount) work blocks."
    }

    private static func scheduleDraftQueueReason(candidateCount: Int) -> String {
        if candidateCount == 1 {
            return "Schedule draft suggested 1 Calendar work block."
        }
        return "Schedule draft suggested \(candidateCount) Calendar work blocks."
    }

    private static func sanitizedScheduleDraftSourceTranscript(_ sourceTranscript: String) -> String {
        let trimmed = sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let redacted = DeveloperSecretRedactor().redact(trimmed).text
        let fallback = String(localized: "Schedule draft Calendar apply")
        guard !redacted.isEmpty else {
            return fallback
        }
        let maxLength = 300
        guard redacted.count > maxLength else {
            return redacted
        }
        return "\(redacted.prefix(maxLength))..."
    }

    private static func scheduleDraftDurationMinutes(for candidate: ScheduleDraftApplyWriteCandidate) -> Int64? {
        guard let start = ISO8601DateFormatter().date(from: candidate.startAt),
              let end = ISO8601DateFormatter().date(from: candidate.endAt) else {
            return nil
        }
        let minutes = Int64(end.timeIntervalSince(start) / 60)
        guard minutes > 0 else {
            return nil
        }
        // Calendar tool execution derives endAt from durationMinutes. Persisting a
        // duration instead of a second endAt keeps the queued approval surface
        // aligned with the executable tool contract.
        return minutes
    }

    private func isEligibleForTaskAutomation(_ task: ProjectBoardTask) -> Bool {
        task.status != .blocked && task.status != .done
    }

    private func approvedAutomationExecutionDetail(for task: ProjectBoardTask) -> String {
        let marker = "Suisui approved automation execution"
        let note = "\(marker): Run approved plan moved this task into active work after reviewing its current title, detail, priority, and due date."
        let trimmedDetail = task.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.contains(marker) else {
            return task.detail
        }
        guard !trimmedDetail.isEmpty else {
            return note
        }
        return "\(trimmedDetail)\n\n\(note)"
    }

    private func approvedAutomationActionPlan(
        for task: ProjectBoardTask,
        reviewReason: String
    ) -> ActionPlan {
        var arguments: [String: JSONValue] = [
            "id": .number(Double(task.id)),
            "title": .string(task.title),
            "detail": .string(approvedAutomationExecutionDetail(for: task)),
            "projectId": .number(Double(task.projectID)),
            "status": .string(ProjectTaskStatus.inProgress.rawValue),
            "priority": .string(task.priority.rawValue)
        ]
        if let dueAt = task.dueAt {
            arguments["dueAt"] = .string(dueAt)
        }

        return ActionPlan(
            id: "approved-task-automation:\(task.id):\(Self.approvedAutomationPlanDigest(task: task, reviewReason: reviewReason))",
            userInput: "Run reviewed task automation for \(task.title).",
            summary: "Move reviewed task \(task.title) into active work after explicit approval.",
            actions: [
                PlanAction(
                    id: "approved-task-automation:update:\(task.id)",
                    tool: .taskUpdate,
                    arguments: arguments,
                    riskLevel: .write,
                    requiresUserConfirmation: true
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )
    }

    private static func approvedAutomationPlanDigest(
        task: ProjectBoardTask,
        reviewReason: String
    ) -> String {
        let input = [
            String(task.id),
            String(task.projectID),
            task.title,
            task.detail,
            task.status.rawValue,
            task.priority.rawValue,
            task.dueAt ?? "",
            reviewReason
        ].joined(separator: "\u{1f}")
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    private func retainUnexecutedReviewedTasks(
        from reviewDecision: TaskAutoExecutionDecision,
        excludingTaskID executedTaskID: Int64
    ) {
        let remainingTasks = reviewDecision.selectedTasks.filter { $0.id != executedTaskID }
        guard !remainingTasks.isEmpty else {
            taskAutomationReviewDecision = nil
            taskAutomationDocumentDeliverableReviews = []
            return
        }
        // A configured review can contain several priority/due-date selected
        // tasks. Keep the still-unexecuted snapshots so one approved task run
        // cannot erase the user's review queue or hide missing execution
        // receipts for the rest of the batch.
        taskAutomationReviewDecision = TaskAutoExecutionDecision(
            status: reviewDecision.status,
            selectedTasks: remainingTasks,
            reason: reviewDecision.reason,
            llmCallBudgetRemaining: reviewDecision.llmCallBudgetRemaining,
            requiresUserApproval: reviewDecision.requiresUserApproval,
            allowsDirectExecution: reviewDecision.allowsDirectExecution
        )
    }

    private func documentDeliverableReviews(
        from drafts: [DocumentAutomationDeliverableDraft]
    ) -> [TaskAutomationDocumentDeliverableReview] {
        // Keep the review UI bound to the same approval-gated draft set that
        // enters provider planning. Rendering only redacted previews lets users
        // audit source evidence without exposing raw document bodies in the UI.
        return TaskAutomationDocumentDeliverableReviewPolicy()
            .reviewableDeliverables(from: drafts)
            .map { deliverable in
                let draft = deliverable.draft
                return TaskAutomationDocumentDeliverableReview(
                    kind: draft.kind,
                    title: draft.title,
                    suggestedPath: draft.suggestedPath,
                    sourceDocuments: deliverable.sourceDocuments.map {
                        TaskAutomationDocumentSourceReview(
                            id: $0.id,
                            title: $0.title,
                            redactedSummary: $0.redactedSummary,
                            inclusionReason: $0.inclusionReason
                        )
                    },
                    rationale: draft.rationale,
                    riskLevel: draft.riskLevel,
                    requiresApproval: draft.requiresApproval
                )
            }
    }

    private func matchesReviewedAutomationTask(_ reviewedTask: ProjectBoardTask, current: ProjectBoardTask) -> Bool {
        // The LLM plan is based on a point-in-time task snapshot. Requiring the
        // same content and scheduling fields keeps a reviewed plan from being
        // reused after the user edits the work it was meant to describe.
        reviewedTask.id == current.id
            && reviewedTask.projectID == current.projectID
            && reviewedTask.title == current.title
            && reviewedTask.detail == current.detail
            && reviewedTask.status == current.status
            && reviewedTask.priority == current.priority
            && reviewedTask.dueAt == current.dueAt
    }

    @discardableResult
    public func prepareTodayScheduleDraft(
        prioritizing taskID: Int64? = nil,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> TodayScheduleDraft {
        let plan = todayPlan(on: referenceDate, calendar: calendar)
        let timeBlocks = prioritizedTodayTimeBlocks(
            plan: plan,
            taskID: taskID,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let draft = TodayScheduleDraft(timeBlocks: timeBlocks)
        todayScheduleDraft = draft
        todayCommandFeedback = String(format: String(localized: "Prepared %d time blocks for schedule review."), draft.timeBlocks.count)
        return draft
    }

    @discardableResult
    public func prepareScheduleDraft(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> ScheduleDraft {
        let todayDraft = prepareTodayScheduleDraft(on: referenceDate, calendar: calendar)
        let draft = ScheduleDraft(
            timeBlocks: todayDraft.timeBlocks,
            unscheduledTasks: unscheduledScheduleTasks(excludingTaskIDs: [])
        )
        scheduleDraft = draft
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        scheduleApplyResult = nil
        todayCommandFeedback = String(
            format: String(localized: "Prepared schedule draft with %d time blocks and %d unscheduled tasks."),
            draft.timeBlocks.count,
            draft.unscheduledTasks.count
        )
        return draft
    }

    @discardableResult
    public func addUnscheduledTaskToScheduleDraft(
        taskID: Int64,
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let task = unscheduledScheduleTasks(excludingTaskIDs: []).first(where: { $0.id == taskID }) else {
            errorMessage = String(localized: "Select an unscheduled task before adding it to the draft.")
            todayCommandFeedback = errorMessage
            return false
        }

        var draft = scheduleDraftForAddingUnscheduledTask(on: referenceDate, calendar: calendar)
        if draft.timeBlocks.contains(where: { $0.task.id == taskID }) {
            todayCommandFeedback = String(localized: "Unscheduled task is already in the schedule draft.")
            errorMessage = nil
            return true
        }

        guard let block = scheduleDraftTimeBlock(
            for: task,
            existingBlocks: draft.timeBlocks,
            referenceDate: referenceDate,
            calendar: calendar
        ) else {
            errorMessage = String(localized: "Schedule draft could not add the unscheduled task.")
            todayCommandFeedback = errorMessage
            return false
        }

        // This is a local review artifact, not task scheduling. The task keeps
        // its nil due date until the user separately approves Calendar/app writes.
        draft.timeBlocks.append(block)
        draft.unscheduledTasks.removeAll { $0.id == taskID }
        scheduleDraft = draft
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        scheduleApplyResult = nil
        errorMessage = nil
        todayCommandFeedback = String(format: String(localized: "Added \"%@\" to the local schedule draft."), task.title)
        return true
    }

    @discardableResult
    public func placeTaskInScheduleDraft(
        taskID: Int64,
        startAt: Date,
        endAt: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard endAt > startAt else {
            errorMessage = String(localized: "End time must be later than start time.")
            todayCommandFeedback = errorMessage
            return false
        }
        guard let task = snapshot.projects
            .filter({ !$0.isArchived && !$0.isCompleted })
            .flatMap(\.tasks)
            .first(where: { $0.id == taskID && $0.status != .done }) else {
            errorMessage = String(localized: "Select an active task before placing it on the schedule.")
            todayCommandFeedback = errorMessage
            return false
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = calendar.timeZone
        let labelFormatter = DateFormatter()
        labelFormatter.calendar = calendar
        labelFormatter.locale = Locale(identifier: "en_US_POSIX")
        labelFormatter.timeZone = calendar.timeZone
        labelFormatter.dateFormat = "HH:mm"
        let block = TodayTimeBlock(
            label: "\(labelFormatter.string(from: startAt))-\(labelFormatter.string(from: endAt))",
            task: task,
            startAt: isoFormatter.string(from: startAt),
            endAt: isoFormatter.string(from: endAt)
        )

        var draft = scheduleDraft ?? ScheduleDraft(
            timeBlocks: [],
            unscheduledTasks: unscheduledScheduleTasks(excludingTaskIDs: [])
        )
        if let visibleWeek = calendar.dateInterval(of: .weekOfYear, for: startAt) {
            draft.timeBlocks.removeAll { existing in
                guard let rawStartAt = existing.startAt,
                      let existingStart = isoFormatter.date(from: rawStartAt) else {
                    return true
                }
                return !visibleWeek.contains(existingStart)
            }
        }
        draft.timeBlocks.removeAll { $0.task.id == taskID }
        draft.timeBlocks.append(block)
        draft.timeBlocks.sort { lhs, rhs in
            guard let lhsStart = lhs.startAt.flatMap({ isoFormatter.date(from: $0) }),
                  let rhsStart = rhs.startAt.flatMap({ isoFormatter.date(from: $0) }) else {
                return lhs.task.id < rhs.task.id
            }
            return lhsStart == rhsStart ? lhs.task.id < rhs.task.id : lhsStart < rhsStart
        }
        draft.unscheduledTasks = unscheduledScheduleTasks(
            excludingTaskIDs: Set(draft.timeBlocks.map(\.task.id))
        )
        scheduleDraft = draft
        rebuildScheduleReadModel(around: startAt, calendar: calendar)
        scheduleApplyResult = nil
        errorMessage = nil
        todayCommandFeedback = String(format: String(localized: "Placed \"%@\" in the local schedule draft."), task.title)
        return true
    }

    @discardableResult
    public func removeTaskFromScheduleDraft(
        taskID: Int64,
        around referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard var draft = scheduleDraft,
              draft.timeBlocks.contains(where: { $0.task.id == taskID }) else {
            errorMessage = String(localized: "Task is not in the schedule draft.")
            todayCommandFeedback = errorMessage
            return false
        }

        draft.timeBlocks.removeAll { $0.task.id == taskID }
        draft.unscheduledTasks = unscheduledScheduleTasks(
            excludingTaskIDs: Set(draft.timeBlocks.map(\.task.id))
        )
        scheduleDraft = draft
        rebuildScheduleReadModel(around: referenceDate, calendar: calendar)
        scheduleApplyResult = nil
        errorMessage = nil
        todayCommandFeedback = String(localized: "Removed task from the local schedule draft.")
        return true
    }

    private func scheduleDraftForAddingUnscheduledTask(
        on referenceDate: Date,
        calendar: Calendar
    ) -> ScheduleDraft {
        guard let draft = scheduleDraft else {
            return prepareScheduleDraft(on: referenceDate, calendar: calendar)
        }
        guard scheduleDraft(draft, isAlignedWith: referenceDate, calendar: calendar) else {
            // A Schedule draft is approval payload. Regenerating stale day-local
            // blocks prevents a visible-day Add action from queuing old Calendar writes.
            return prepareScheduleDraft(on: referenceDate, calendar: calendar)
        }
        return draft
    }

    private func scheduleDraft(
        _ draft: ScheduleDraft,
        isAlignedWith referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        guard !draft.timeBlocks.isEmpty else {
            return true
        }
        let formatter = ISO8601DateFormatter()
        let referenceDayKey = Self.scheduleDraftDayKey(referenceDate: referenceDate, calendar: calendar)
        return draft.timeBlocks.allSatisfy { block in
            guard let rawStartAt = block.startAt,
                  let start = formatter.date(from: rawStartAt) else {
                return false
            }
            return Self.scheduleDraftDayKey(referenceDate: start, calendar: calendar) == referenceDayKey
        }
    }

    @discardableResult
    public func applyScheduleDraftToCalendar(approvalToken: String?) -> ScheduleApplyResult {
        guard approvalToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            scheduleApplyResult = .approvalRequired
            todayCommandFeedback = String(localized: "Schedule review approval is required before Calendar write.")
            return .approvalRequired
        }
        let executionApprovalID = Self.scheduleDraftApplyApprovalID()
        guard let draft = scheduleDraft else {
            scheduleApplyResult = .noDraft
            todayCommandFeedback = String(localized: "Create a schedule draft before applying to Calendar.")
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: [],
                unscheduledTaskCount: 0,
                createdEvents: [],
                approvalID: executionApprovalID,
                status: .skipped
            )
            return .noDraft
        }
        let writeCandidates = scheduleDraftWriteCandidates(for: draft)
        guard let scheduleCalendarClient else {
            scheduleApplyResult = .calendarNotConfigured
            todayCommandFeedback = String(localized: "Calendar is not configured. No external write was performed.")
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: [],
                approvalID: executionApprovalID,
                status: .skipped
            )
            return .calendarNotConfigured
        }
        let projectTitlesByID = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.title) })
        if let receiptStorageMessage = persistApprovedAIWorkStartReceipt(
            ExecutionReceiptFactory.makeScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: [],
                projectTitlesByID: projectTitlesByID,
                runID: "schedule-draft-apply-start:\(UUID().uuidString)",
                approvalID: executionApprovalID,
                status: .running,
                createdAt: Date()
            )
        ) {
            let result = ScheduleApplyResult.failed(receiptStorageMessage)
            scheduleApplyResult = result
            return result
        }

        var createdEvents: [ScheduleDraftApplyCreatedEvent] = []
        do {
            for candidate in writeCandidates {
                let event = try scheduleCalendarClient.createEvent(CalendarEventDraft(
                    title: candidate.taskTitle,
                    startAt: candidate.startAt,
                    endAt: candidate.endAt,
                    notes: String(localized: "Created from a reviewed Suisui schedule draft.")
                ))
                createdEvents.append(ScheduleDraftApplyCreatedEvent(candidate: candidate, record: event))
            }
            let result = ScheduleApplyResult.applied(eventCount: createdEvents.count)
            scheduleApplyResult = result
            todayCommandFeedback = String(format: String(localized: "Applied %d Calendar events."), createdEvents.count)
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: createdEvents,
                approvalID: executionApprovalID,
                status: .succeeded
            )
            return result
        } catch {
            let message = Self.userFacingMessage(for: error)
            let result = ScheduleApplyResult.failed(message)
            scheduleApplyResult = result
            todayCommandFeedback = String(localized: "Calendar apply failed.")
            // The Calendar client does not expose rollback, so preserve partial
            // write evidence in a failed receipt instead of hiding the attempt.
            errorMessage = saveScheduleDraftApplyReceipt(
                writeCandidates: writeCandidates,
                unscheduledTaskCount: draft.unscheduledTasks.count,
                createdEvents: createdEvents,
                approvalID: executionApprovalID,
                status: .failed,
                errorSummary: message
            )
            return result
        }
    }

    public func refreshGoogleCalendarSyncStatus(now: Date = Date()) {
        // A synchronous user/approval refresh is newer than any detached
        // readiness read already in flight, so invalidate it before publishing.
        googleCalendarReadinessRefreshRevision &+= 1
        guard let googleCalendarSync = resolvedGoogleCalendarSync else {
            googleCalendarSyncStatus = .runtimeNotConfigured
            return
        }

        do {
            googleCalendarSyncStatus = try googleCalendarSync.status(now: now)
        } catch {
            let message = Self.userFacingMessage(
                for: error,
                fallback: String(localized: "Google Calendar sync status is unavailable.")
            )
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .failed(message: message)
            )
            recordFailure(.readinessCheckFailed(message), retryAction: .load)
        }
    }

    /// Settings changes can require SQLite or Keychain-backed readiness reads.
    /// Keep that work away from Today rendering and publish only the completed
    /// status on the MainActor, ignoring older overlapping refreshes.
    public func refreshGoogleCalendarSyncStatusOffMain(
        now: Date = VisualEvidenceRuntimeContext.referenceDate()
    ) {
        guard let googleCalendarSync = resolvedGoogleCalendarSync else {
            googleCalendarSyncStatus = .runtimeNotConfigured
            return
        }
        googleCalendarReadinessRefreshRevision &+= 1
        let refreshRevision = googleCalendarReadinessRefreshRevision
        let fallback = String(localized: "Google Calendar sync status is unavailable.")

        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .utility) {
                do {
                    return GoogleCalendarReadinessRefreshResult.success(
                        try googleCalendarSync.status(now: now)
                    )
                } catch {
                    return .failure(
                        UserFacingErrorMessageSanitizer.message(from: error, fallback: fallback)
                    )
                }
            }.value
            guard let self, self.googleCalendarReadinessRefreshRevision == refreshRevision else {
                return
            }
            switch result {
            case let .success(status):
                self.googleCalendarSyncStatus = status
            case let .failure(message):
                self.googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                    plan: self.googleCalendarSyncStatus.plan,
                    state: .failed(message: message)
                )
                self.recordFailure(.readinessCheckFailed(message), retryAction: .load)
            }
        }
    }

    @discardableResult
    public func syncDueTasksToGoogleCalendar(approvalToken: String?) -> GoogleCalendarTaskSyncResult? {
        beginRecoverableOperation()
        refreshGoogleCalendarSyncStatus()
        guard let googleCalendarSync = resolvedGoogleCalendarSync else {
            recordFailure(
                .providerFailed(GoogleCalendarRuntimeSyncStatus.runtimeNotConfigured.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        }
        guard googleCalendarSyncStatus.canSync else {
            recordFailure(
                .readinessCheckFailed(googleCalendarSyncStatus.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        }
        guard let approvalToken,
              !approvalToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            recordFailure(
                .readinessCheckFailed(String(localized: "Google Calendar sync requires approval before writing events.")),
                retryAction: nil
            )
            return nil
        }

        do {
            let approval = ApprovalToken(
                id: approvalToken,
                sessionID: "project-board-google-calendar-sync"
            )
            let context = ToolExecutionContext(
                authorization: try ToolActionAuthorization(
                    approval: approval,
                    actionID: "standalone",
                    tool: .calendarCreateEvent,
                    arguments: [:]
                ),
                source: .reviewUI
            )
            let result = try googleCalendarSync.syncDueTasks(context: context)
            integrationStatusMessage = Self.googleCalendarSyncStatusMessage(for: result)
            errorMessage = nil
            refreshGoogleCalendarSyncStatus()
            onChange()
            return result
        } catch GoogleCalendarRuntimeSyncError.approvalRequired {
            recordFailure(
                .readinessCheckFailed(String(localized: "Google Calendar sync requires approval before writing events.")),
                retryAction: nil
            )
            return nil
        } catch GoogleCalendarRuntimeSyncError.notReady(let state) {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(plan: googleCalendarSyncStatus.plan, state: state)
            recordFailure(
                .readinessCheckFailed(googleCalendarSyncStatus.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        } catch SyncServiceError.upgradeRequired(let requiredPlan) {
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .upgradeRequired(requiredPlan: requiredPlan)
            )
            recordFailure(
                .readinessCheckFailed(googleCalendarSyncStatus.detailLabel),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        } catch {
            let message = Self.userFacingMessage(
                for: error,
                fallback: String(localized: "Google Calendar sync failed.")
            )
            googleCalendarSyncStatus = GoogleCalendarRuntimeSyncStatus(
                plan: googleCalendarSyncStatus.plan,
                state: .failed(message: message)
            )
            recordFailure(
                .providerFailed(message),
                retryAction: .syncGoogleCalendar(approvalToken: approvalToken)
            )
            return nil
        }
    }

    public func projectPortfolioSummaries(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectPortfolioSummary] {
        projectPortfolioSummaries(
            on: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func projectPortfolioSummaries(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> [ProjectPortfolioSummary] {
        inputs.portfolioProjects
            .map { projectPortfolioSummary(for: $0, on: referenceDate, calendar: calendar) }
            .sorted { lhs, rhs in
                if lhs.health.sortRank != rhs.health.sortRank {
                    return lhs.health.sortRank < rhs.health.sortRank
                }
                if lhs.overdueTaskCount != rhs.overdueTaskCount {
                    return lhs.overdueTaskCount > rhs.overdueTaskCount
                }
                return lhs.projectID > rhs.projectID
            }
    }

    public func doneAnalytics(
        on referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DoneAnalyticsSummary {
        doneAnalytics(
            on: referenceDate,
            calendar: calendar,
            inputs: ProjectBoardDerivedReadModelInputs(
                snapshot: snapshot,
                showsCompletedWorkflowTasks: showsCompletedWorkflowTasks
            )
        )
    }

    private func doneAnalytics(
        on referenceDate: Date,
        calendar: Calendar,
        inputs: ProjectBoardDerivedReadModelInputs
    ) -> DoneAnalyticsSummary {
        let completedProjects = inputs.completedProjects
        // Reopened tasks keep their completedAt timestamp so Done analytics can preserve actual completion history.
        let historyTasks = inputs.nonArchivedTasks.filter { task in task.completedAt != nil || task.status == .done }
        let dayInterval = calendar.dateInterval(of: .day, for: referenceDate)
        let rollingWeekStart = calendar.date(byAdding: .day, value: -6, to: dayInterval?.start ?? referenceDate) ?? referenceDate
        let completedTodayCount = historyTasks.filter { task in
            guard let dayInterval, let completedDate = completedDate(for: task) else {
                return false
            }
            return completedDate >= dayInterval.start && completedDate < dayInterval.end
        }.count
        let completedThisWeekCount = historyTasks.filter { task in
            guard let completedDate = completedDate(for: task) else {
                return false
            }
            return completedDate >= rollingWeekStart && completedDate <= referenceDate
        }.count
        let completedDates = historyTasks.compactMap(completedDate(for:))
        let completedCountsByDayStart = completedDates.reduce(into: [Date: Int]()) { partialResult, completedDate in
            guard let dayStart = calendar.dateInterval(of: .day, for: completedDate)?.start else {
                return
            }
            partialResult[dayStart, default: 0] += 1
        }
        let completedDayStarts = Set(completedCountsByDayStart.keys)
        let completionHeatmapBuckets = Self.doneAnalyticsHeatmapBuckets(
            from: completedCountsByDayStart,
            on: referenceDate,
            calendar: calendar
        )
        let bestWeekdaySummary = Self.doneAnalyticsBestWeekdaySummary(
            from: completedDates,
            calendar: calendar
        )
        let bestHourSummary = Self.doneAnalyticsBestHourSummary(
            from: completedDates,
            calendar: calendar
        )
        let streakDays = Self.doneStreakDays(
            from: completedDayStarts,
            on: referenceDate,
            calendar: calendar
        )
        let recentTasks = historyTasks
            .sorted { lhs, rhs in
                switch (completedDate(for: lhs), completedDate(for: rhs)) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate == rhsDate {
                        return lhs.id > rhs.id
                    }
                    return lhsDate > rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.id > rhs.id
                }
            }

        let focusHours = Self.doneFocusHours(tasks: historyTasks)
        let onTimeRate = Self.doneOnTimeRate(tasks: historyTasks, calendar: calendar)
        let weeklyTrendBuckets = Self.doneWeeklyTrendBuckets(
            from: completedCountsByDayStart,
            on: referenceDate,
            calendar: calendar
        )

        return DoneAnalyticsSummary(
            completedTaskCount: historyTasks.count,
            completedProjectCount: completedProjects.count,
            completedTodayCount: completedTodayCount,
            completedThisWeekCount: completedThisWeekCount,
            streakDays: streakDays,
            focusHours: focusHours,
            onTimeRate: onTimeRate,
            weeklyTrendBuckets: weeklyTrendBuckets,
            completionHeatmapBuckets: completionHeatmapBuckets,
            bestWeekdaySummary: bestWeekdaySummary,
            bestHourSummary: bestHourSummary,
            recentTasks: Array(recentTasks.prefix(12)),
            localRuleInsight: "Done analytics uses local completed_at history; reopened tasks remain visible in completion history."
        )
    }

    @discardableResult
    public func openProjectFromPortfolioCard(projectID: Int64) -> Bool {
        guard snapshot.projects.contains(where: { $0.id == projectID && !$0.isArchived }) else {
            errorMessage = "Project is no longer available."
            return false
        }

        selectedProjectID = projectID
        selectedTaskID = nil
        errorMessage = nil
        return true
    }

    public func projectTitle(for task: ProjectBoardTask) -> String {
        snapshot.projects.first { $0.id == task.projectID }?.title ?? "Unknown Project"
    }

    public var isEmptyProjectStateVisible: Bool {
        fatalFailure == nil && selectedProject == nil
    }

    public func load() {
        load(invalidationReason: nil)
    }

    private func load(invalidationReason: TodaySnapshotInvalidationReason?) {
        didLastLoadFail = false
        let failureAtLoadStart = failure
        do {
            let loadedSnapshot = try store.loadSnapshot(includeArchived: showsArchivedProjects)
            let snapshotChanged = loadedSnapshot != snapshot
            let captureCacheErrorMessage = refreshInboxCaptureCache(for: loadedSnapshot)
            let previousTriageRecords = inboxTriageRecordsByTaskID
            let triageCacheErrorMessage = refreshInboxTriageCache(for: loadedSnapshot)
            let triageCacheChanged = previousTriageRecords != inboxTriageRecordsByTaskID
            let assistantQueueErrorMessage = refreshAssistantQueueSnapshot()
            resetScopedExecutionReceiptHistorySnapshots()
            snapshot = loadedSnapshot
            if executionReceiptAuditSnapshotsLoaded {
                refreshExecutionReceiptAuditSnapshots()
            }
            if selectedProjectID == nil || !snapshot.projects.contains(where: { $0.id == selectedProjectID }) {
                selectedProjectID = snapshot.projects.first?.id
            }
            if selectedTaskID != nil, selectedTask == nil {
                self.selectedTaskID = nil
            }
            // Production injects a preloaded readiness status before the
            // window is visible, while older/test initializers do not. Keep
            // the former zero-read on first load and asynchronously hydrate
            // only the latter; neither path performs I/O from SwiftUI render.
            if hasLoadedBoardSnapshot || !hasPreloadedGoogleCalendarSyncStatus {
                refreshGoogleCalendarSyncStatusOffMain()
            }
            if snapshotChanged || triageCacheChanged || invalidationReason != nil || derivedReadModelReferenceDate == nil {
                // A mutation followed by its own board-change notification can
                // load the same snapshot twice. Rebuild only on the first load
                // so one logical mutation advances the preview revision once.
                invalidateTodayWorkflowSnapshot(invalidationReason ?? .storeReload)
                if let referenceDate = derivedReadModelReferenceDate {
                    rebuildDerivedReadModels(on: referenceDate, calendar: derivedReadModelCalendar)
                } else {
                    rebuildDerivedReadModels(on: readModelNow(), calendar: readModelCalendarProvider())
                }
            }
            hasLoadedBoardSnapshot = true
            if let recoverableMessage = assistantQueueErrorMessage
                ?? captureCacheErrorMessage
                ?? triageCacheErrorMessage {
                didLastLoadFail = true
                recordFailure(.providerFailed(recoverableMessage), retryAction: .load)
            } else if failure == nil && failureAtLoadStart == nil {
                clearFailure()
            }
        } catch {
            didLastLoadFail = true
            let message = Self.userFacingMessage(for: error)
            if hasLoadedBoardSnapshot {
                recordFailure(.saveFailed(message), retryAction: .load)
            } else {
                recordFailure(.initialLoadFailed(message), retryAction: .load)
            }
        }
    }

    private func refreshExecutionReceiptHistorySnapshot() {
        resetScopedExecutionReceiptHistorySnapshots()
        guard executionReceiptAuditSnapshotsLoaded else {
            return
        }
        refreshExecutionReceiptAuditSnapshots()
    }

    public func refreshExecutionReceiptAuditSnapshotsIfNeeded() {
        guard !executionReceiptAuditSnapshotsLoaded else {
            return
        }
        refreshExecutionReceiptAuditSnapshots()
    }

    public func refreshExecutionReceiptAuditSnapshots() {
        executionReceiptAuditSnapshotsLoaded = true
        refreshExecutionReceiptHistorySnapshot(for: snapshot)
    }

    private func resetScopedExecutionReceiptHistorySnapshots() {
        executionReceiptHistorySnapshotsByTaskID = [:]
        executionReceiptHistorySnapshotsByProjectID = [:]
    }

    public func setExecutionReceiptHistorySearchText(_ text: String) {
        guard executionReceiptHistorySearchText != text else {
            return
        }
        executionReceiptHistorySearchText = text
        clearExecutionReceiptHistoryExport()
        executionReceiptAuditSnapshotsLoaded = true
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func setExecutionReceiptHistoryStatusFilter(_ status: ExecutionReceiptStatus?) {
        guard executionReceiptHistoryStatusFilter != status else {
            return
        }
        executionReceiptHistoryStatusFilter = status
        clearExecutionReceiptHistoryExport()
        executionReceiptAuditSnapshotsLoaded = true
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func setExecutionReceiptHistoryReferenceKindFilter(_ referenceKind: ExecutionReceiptReferenceKind?) {
        guard executionReceiptHistoryReferenceKindFilter != referenceKind else {
            return
        }
        executionReceiptHistoryReferenceKindFilter = referenceKind
        clearExecutionReceiptHistoryExport()
        executionReceiptAuditSnapshotsLoaded = true
        refreshGlobalExecutionReceiptHistorySnapshot()
    }

    public func prepareExecutionReceiptHistoryExport(exportedAt: Date = Date()) {
        do {
            if !executionReceiptAuditSnapshotsLoaded {
                refreshExecutionReceiptAuditSnapshots()
            }
            let data = try ExecutionReceiptHistoryExporter.exportJSON(
                snapshot: executionReceiptHistorySnapshot,
                exportedAt: exportedAt
            )
            executionReceiptHistoryExportData = data
            executionReceiptHistoryExportMessage = exportPreparedMessage(rowCount: executionReceiptHistorySnapshot.rows.count)
        } catch {
            executionReceiptHistoryExportData = nil
            executionReceiptHistoryExportMessage = String(localized: "Receipt export could not be prepared.")
        }
    }

    public func recordExecutionReceiptHistoryExportCompleted() {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = String(localized: "Saved redacted receipt export JSON.")
    }

    public func recordExecutionReceiptHistoryFileFailure(_ error: Error) {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = String(localized: "Receipt export could not be saved.")
    }

    private func clearExecutionReceiptHistoryExport() {
        executionReceiptHistoryExportData = nil
        executionReceiptHistoryExportMessage = nil
    }

    private func executionReceiptHistoryFilter() -> ExecutionReceiptSearchFilter {
        ExecutionReceiptSearchFilter(
            query: executionReceiptHistorySearchText,
            statuses: executionReceiptHistoryStatusFilter.map { Set([$0]) } ?? [],
            referenceKinds: executionReceiptHistoryReferenceKindFilter.map { Set([$0]) } ?? [],
            visibleSurface: .auditLog
        )
    }

    private func exportPreparedMessage(rowCount: Int) -> String {
        if rowCount == 1 {
            return String(format: String(localized: "Prepared %d redacted receipt export row."), rowCount)
        }
        return String(format: String(localized: "Prepared %d redacted receipt export rows."), rowCount)
    }

    private func refreshGlobalExecutionReceiptHistorySnapshot() {
        executionReceiptAuditSnapshotsLoaded = true
        guard let executionReceiptStore else {
            executionReceiptHistorySnapshot = .empty
            return
        }

        do {
            executionReceiptHistorySnapshot = try globalExecutionReceiptHistorySnapshot(store: executionReceiptStore)
        } catch {
            executionReceiptHistorySnapshot = ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
        }
    }

    private func globalExecutionReceiptHistorySnapshot(
        store: any ExecutionReceiptStore
    ) throws -> ExecutionReceiptHistorySnapshot {
        let receipts = try store.list(matching: executionReceiptHistoryFilter(), limit: 100)
        return ExecutionReceiptHistoryReadModel.snapshot(
            from: receipts,
            limit: 10
        )
    }

    private func refreshExecutionReceiptHistorySnapshot(for snapshot: ProjectBoardSnapshot) {
        guard let executionReceiptStore else {
            executionReceiptHistorySnapshot = .empty
            executionUsageMeterSnapshot = ExecutionUsageMeterSnapshot(
                unavailableMessage: String(localized: "Execution usage meter is unavailable")
            )
            executionReceiptHistorySnapshotsByTaskID = [:]
            executionReceiptHistorySnapshotsByProjectID = [:]
            return
        }

        do {
            executionReceiptHistorySnapshot = try globalExecutionReceiptHistorySnapshot(store: executionReceiptStore)
            executionUsageMeterSnapshot = try executionUsageMeterSnapshot(store: executionReceiptStore)
            resetScopedExecutionReceiptHistorySnapshots()
        } catch {
            resetScopedExecutionReceiptHistorySnapshots()
            executionReceiptHistorySnapshot = ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
            executionUsageMeterSnapshot = ExecutionUsageMeterSnapshot(
                unavailableMessage: String(localized: "Execution usage meter is unavailable")
            )
        }
    }

    private func executionUsageMeterSnapshot(
        store: any ExecutionReceiptStore
    ) throws -> ExecutionUsageMeterSnapshot {
        let receiptLimit = 500
        let receipts = try store.list(
            matching: ExecutionReceiptSearchFilter(visibleSurface: .auditLog),
            limit: receiptLimit
        )
        return ExecutionUsageMeterReadModel.snapshot(
            from: receipts,
            scopeLabel: String(format: String(localized: "Recent audit receipts (UTC buckets, up to %d receipts)"), receiptLimit)
        )
    }

    public func executionReceiptHistorySnapshot(forTaskID taskID: Int64) -> ExecutionReceiptHistorySnapshot {
        if let cached = executionReceiptHistorySnapshotsByTaskID[taskID] {
            return cached
        }

        let snapshot = scopedExecutionReceiptSnapshot(
            referenceKind: .task,
            referenceID: String(taskID),
            visibleSurface: .taskDetail
        )
        executionReceiptHistorySnapshotsByTaskID[taskID] = snapshot
        return snapshot
    }

    public func executionReceiptHistorySnapshot(forProjectID projectID: Int64) -> ExecutionReceiptHistorySnapshot {
        if let cached = executionReceiptHistorySnapshotsByProjectID[projectID] {
            return cached
        }

        let snapshot = scopedExecutionReceiptSnapshot(
            referenceKind: .project,
            referenceID: String(projectID),
            visibleSurface: .projectDetail
        )
        executionReceiptHistorySnapshotsByProjectID[projectID] = snapshot
        return snapshot
    }

    private func scopedExecutionReceiptSnapshot(
        referenceKind: ExecutionReceiptReferenceKind,
        referenceID: String,
        visibleSurface: ExecutionReceiptSurface
    ) -> ExecutionReceiptHistorySnapshot {
        guard let executionReceiptStore else {
            return ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: executionReceiptHistorySnapshot.unavailableMessage
            )
        }

        do {
            // Detail receipts are needed only for the currently opened inspector.
            // Loading every task and project scope during Project Board startup
            // creates N+1 file reads on DMG launches with large local histories.
            let receipts = try executionReceiptStore.list(
                referenceKind: referenceKind,
                referenceID: referenceID,
                visibleSurface: visibleSurface,
                limit: 5
            )
            return ExecutionReceiptHistoryReadModel.snapshot(from: receipts, limit: 5)
        } catch {
            return ExecutionReceiptHistorySnapshot(
                rows: [],
                unavailableMessage: String(localized: "Execution receipts are unavailable.")
            )
        }
    }

    private func refreshAssistantQueueSnapshot() -> String? {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            return nil
        }

        do {
            // Project Board owns the central task cockpit, so it reads a compact
            // queue snapshot instead of querying local stores from SwiftUI views.
            // Receipts are outcome-only metadata; queue state remains the source of truth.
            // Counts come from state aggregates so terminal queue history cannot
            // hide older review work behind the row fetch limit.
            var receiptErrorMessage: String?
            let receipts: [ExecutionReceipt]
            do {
                receipts = try executionReceiptStore?.list(
                    matching: ExecutionReceiptSearchFilter(visibleSurface: .assistantQueue),
                    limit: 100
                ) ?? []
            } catch {
                receipts = []
                receiptErrorMessage = assistantQueueReceiptUnavailableMessage
            }
            assistantQueueSnapshot = try assistantQueueStore.readModelSnapshot(
                filter: assistantQueueViewFilter.storeFilter(limit: 100),
                receipts: receipts,
                viewFilter: assistantQueueViewFilter,
                sort: assistantQueueSort
            )
            pruneAssistantQueueSelectionToVisibleRows()
            return receiptErrorMessage
        } catch {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            return AssistantQueueStoreError.userMessage(for: error)
        }
    }

    public func setAssistantQueueViewFilter(_ filter: AssistantQueueViewFilter) {
        guard assistantQueueViewFilter != filter else {
            return
        }
        assistantQueueViewFilter = filter
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
    }

    public func setAssistantQueueSort(_ sort: AssistantQueueSort) {
        guard assistantQueueSort != sort else {
            return
        }
        assistantQueueSort = sort
        _ = refreshAssistantQueueSnapshot()
    }

    private func focusAssistantQueueItem(id: String) {
        assistantQueueViewFilter = .needsAttention
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
        if setAssistantQueueSelection(id: id, selected: true) {
            return
        }

        assistantQueueViewFilter = .all
        assistantQueueSelectedItemIDs = []
        _ = refreshAssistantQueueSnapshot()
        _ = setAssistantQueueSelection(id: id, selected: true)
    }

    @discardableResult
    public func toggleAssistantQueueSelection(id: String) -> Bool {
        setAssistantQueueSelection(
            id: id,
            selected: !assistantQueueSelectedItemIDs.contains(id)
        )
    }

    @discardableResult
    public func setAssistantQueueSelection(id: String, selected: Bool) -> Bool {
        guard let row = assistantQueueSnapshot.rows.first(where: { $0.id == id }) else {
            return false
        }
        if selected {
            guard (row.canDefer || row.canReject), row.mutationRevision != nil else {
                // Batch review actions cannot cancel running work or rewrite a
                // terminal outcome. Missing revisions also fail closed because
                // the batch must compare the exact state the reviewer saw.
                assistantQueueSelectedItemIDs.remove(id)
                return false
            }
            assistantQueueSelectedItemIDs.insert(id)
        } else {
            assistantQueueSelectedItemIDs.remove(id)
        }
        return true
    }

    private var assistantQueueItemUnavailableMessage: String {
        String(localized: "Assistant Queue item is no longer available.")
    }

    private var assistantQueueReceiptUnavailableMessage: String {
        String(localized: "Assistant Queue execution receipts are unavailable. Queue state is still shown.")
    }

    @discardableResult
    public func focusAssistantQueueExecutionHandoff(id: String) -> Bool {
        let itemID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !itemID.isEmpty else {
            errorMessage = assistantQueueItemUnavailableMessage
            integrationStatusMessage = nil
            return false
        }

        // Voice handoff targets already-approved work. Force the narrow
        // runnable filter so stale persisted filters such as Done or Deferred
        // do not hide the item the user just approved.
        assistantQueueViewFilter = .approved
        assistantQueueSelectedItemIDs = []
        let approvedRefreshMessage = refreshAssistantQueueSnapshot()
        if setAssistantQueueSelection(id: itemID, selected: true) {
            errorMessage = nil
            integrationStatusMessage = nil
            return true
        }
        if let approvedRefreshMessage,
           approvedRefreshMessage != assistantQueueReceiptUnavailableMessage {
            errorMessage = approvedRefreshMessage
            integrationStatusMessage = nil
            return false
        }

        assistantQueueViewFilter = .all
        assistantQueueSelectedItemIDs = []
        let allRefreshMessage = refreshAssistantQueueSnapshot()
        if setAssistantQueueSelection(id: itemID, selected: true) {
            errorMessage = nil
            integrationStatusMessage = nil
            return true
        }
        if let allRefreshMessage,
           allRefreshMessage != assistantQueueReceiptUnavailableMessage {
            errorMessage = allRefreshMessage
            integrationStatusMessage = nil
            return false
        }

        errorMessage = assistantQueueItemUnavailableMessage
        integrationStatusMessage = nil
        return false
    }

    @discardableResult
    public func deferSelectedAssistantQueueItems() -> Bool {
        transitionSelectedAssistantQueueItems(
            eligible: \.canDefer,
            emptyMessage: String(localized: "No selected Assistant Queue items can be deferred."),
            invalidSelectionMessage: String(localized: "Every selected Assistant Queue item must support Defer."),
            successMessage: { count in
                String(format: String(localized: "Deferred %d Assistant Queue items."), count)
            }
        ) { item in
            try AssistantQueueStateMachine.deferForReview(item)
        }
    }

    @discardableResult
    public func rejectSelectedAssistantQueueItems() -> Bool {
        transitionSelectedAssistantQueueItems(
            eligible: \.canReject,
            emptyMessage: String(localized: "No selected Assistant Queue items can be rejected."),
            invalidSelectionMessage: String(localized: "Every selected Assistant Queue item must support Reject."),
            successMessage: { count in
                String(format: String(localized: "Rejected %d Assistant Queue items."), count)
            }
        ) { item in
            try AssistantQueueStateMachine.rejectForReview(item)
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use approveAssistantQueueItem(id:expectedMutationRevision:).")
    public func approveAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func approveAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            try AssistantQueueStateMachine.approve(item, reviewerID: "local-user")
        }
    }

    /// Missed-task reschedule suggestions still waiting for review in the
    /// currently visible Assistant Queue rows, in display order.
    public var openRescheduleSuggestionIDs: [String] {
        assistantQueueSnapshot.rows
            .filter { row in
                row.id.hasPrefix(MissedTaskRescheduleSuggestionPlanner.itemIDPrefix)
                    && row.state == .waitingReview
            }
            .map(\.id)
    }

    /// Approves every open reschedule suggestion through the same single-item
    /// approval path so audit granularity stays per-item. Stops at the first
    /// failure: the failed and remaining suggestions stay `waitingReview` and
    /// the per-item error surface keeps the failure message.
    @discardableResult
    public func approveAllRescheduleSuggestions() -> Int {
        let suggestionIDs = openRescheduleSuggestionIDs
        guard !suggestionIDs.isEmpty, !isApprovingAllRescheduleSuggestions else {
            return 0
        }

        isApprovingAllRescheduleSuggestions = true
        defer { isApprovingAllRescheduleSuggestions = false }

        var approvedCount = 0
        for suggestionID in suggestionIDs {
            guard let expectedRevision = assistantQueueSnapshot.rows
                .first(where: { $0.id == suggestionID })?
                .mutationRevision,
                approveAssistantQueueItem(
                    id: suggestionID,
                    expectedMutationRevision: expectedRevision
                ) else {
                // approveAssistantQueueItem already refreshed the snapshot and
                // published the per-item error message.
                return approvedCount
            }
            approvedCount += 1
        }

        integrationStatusMessage = String(
            format: String(localized: "Approved %d reschedule suggestions."),
            approvedCount
        )
        return approvedCount
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use deferAssistantQueueItem(id:expectedMutationRevision:).")
    public func deferAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func deferAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            try AssistantQueueStateMachine.deferForReview(item)
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use rejectAssistantQueueItem(id:expectedMutationRevision:).")
    public func rejectAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func rejectAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision
        ) { item in
            try AssistantQueueStateMachine.rejectForReview(item)
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use editAssistantQueueItem(id:expectedMutationRevision:reviewReason:redactedSummary:).")
    public func editAssistantQueueItem(
        id: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func editAssistantQueueItem(
        id: String,
        expectedMutationRevision: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        editVersionedAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision,
            reviewReason: reviewReason,
            redactedSummary: redactedSummary
        )
    }

    private func editVersionedAssistantQueueItem(
        id: String,
        expectedMutationRevision: String,
        reviewReason: String,
        redactedSummary: String
    ) -> Bool {
        transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision,
            successMessage: "Updated Assistant Queue review details.",
            preserveVisibleItemOnStale: true
        ) { item in
            return try AssistantQueueStateMachine.editReviewDetails(
                item,
                reviewReason: reviewReason,
                redactedSummary: redactedSummary
            )
        }
    }

    private func failClosedUnversionedAssistantQueueMutation() -> Bool {
        // Legacy callers cannot prove which review state the user saw. Refresh
        // for recovery guidance, but never infer a token and mutate current data.
        _ = refreshAssistantQueueSnapshot()
        errorMessage = AssistantQueueMutationFailure.unversionedUserMessage
        integrationStatusMessage = nil
        return false
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use retryAssistantQueueItem(id:expectedMutationRevision:).")
    public func retryAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func retryAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        let reopened = transitionAssistantQueueItem(
            id: id,
            expectedMutationRevision: expectedMutationRevision,
            successMessage: "Reopened Assistant Queue item for review."
        ) { item in
            try AssistantQueueStateMachine.reopenFailedForReview(item)
        }
        guard reopened else {
            return false
        }
        do {
            try resolvedAssistantQueueExecutionCoordinator?
                .recordConversationRetryIfNeeded(id: id)
            return true
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = Self.assistantQueueExecutionMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    @discardableResult
    @available(*, deprecated, message: "This overload fails closed. Use runAssistantQueueItem(id:expectedMutationRevision:).")
    public func runAssistantQueueItem(id: String) -> Bool {
        failClosedUnversionedAssistantQueueMutation()
    }

    @discardableResult
    public func runAssistantQueueItem(
        id: String,
        expectedMutationRevision: String
    ) -> Bool {
        guard let assistantQueueExecutionCoordinator = resolvedAssistantQueueExecutionCoordinator else {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Assistant Queue execution is unavailable in this build."
            integrationStatusMessage = nil
            return false
        }

        do {
            let result = try assistantQueueExecutionCoordinator.execute(
                id: id,
                expectedMutationRevision: expectedMutationRevision
            )
            _ = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot()
            if result.item.state == .done {
                errorMessage = nil
                integrationStatusMessage = "Executed Assistant Queue item."
                onChange()
                return true
            }
            errorMessage = "Assistant Queue execution failed. Review the receipt before retrying."
            integrationStatusMessage = nil
            onChange()
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            refreshExecutionReceiptHistorySnapshot()
            errorMessage = Self.assistantQueueExecutionMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private func transitionAssistantQueueItem(
        id: String,
        expectedMutationRevision: String? = nil,
        successMessage: String? = nil,
        preserveVisibleItemOnStale: Bool = false,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            errorMessage = "Assistant Queue is unavailable in this build."
            return false
        }

        do {
            _ = try assistantQueueStore.transition(id: id) { current in
                if let expectedMutationRevision,
                   current.mutationRevision != expectedMutationRevision {
                    throw AssistantQueueStaleReviewError()
                }
                return try transform(current)
            }
            _ = refreshAssistantQueueSnapshot()
            errorMessage = nil
            integrationStatusMessage = successMessage
            onChange()
            return true
        } catch AssistantQueueTransitionError.blockedItemCannotBeApproved {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Blocked Assistant Queue items cannot be approved."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.dangerousPayloadCannotBeApproved {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Dangerous action plans cannot be approved from Assistant Queue."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.costPreviewRequiredBeforeApproval {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Review the cost preview before approving this Assistant Queue item."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.managedCostCapExceeded {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "This managed cost preview exceeds the configured cap. Adjust the request before approving."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.terminalItemCannotTransition {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Assistant Queue item was already reviewed."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.retryRequiresFailedRunnablePayload {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Only failed runnable Assistant Queue items can be retried."
            integrationStatusMessage = nil
            return false
        } catch AssistantQueueTransitionError.editRequiresReviewableItem {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Only reviewable Assistant Queue items can be edited."
            integrationStatusMessage = nil
            return false
        } catch is AssistantQueueReviewActionUnavailableError {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "This Assistant Queue item cannot be changed by that review action in its current state."
            integrationStatusMessage = nil
            return false
        } catch is AssistantQueueStaleReviewError {
            if preserveVisibleItemOnStale {
                // A stale edit may have moved outside the active filter. Reveal
                // all states before refresh so SwiftUI preserves the row identity,
                // local draft, and focus until the reviewer reloads or cancels.
                assistantQueueViewFilter = .all
            }
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueMutationFailure.staleUserMessage
            integrationStatusMessage = nil
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private func transitionSelectedAssistantQueueItems(
        eligible: KeyPath<AssistantQueueReadModelRow, Bool>,
        emptyMessage: String,
        invalidSelectionMessage: String,
        successMessage: (Int) -> String,
        _ transform: (AssistantQueueItem) throws -> AssistantQueueItem
    ) -> Bool {
        guard let assistantQueueStore else {
            assistantQueueSnapshot = .empty
            assistantQueueSelectedItemIDs = []
            errorMessage = "Assistant Queue is unavailable in this build."
            return false
        }

        let selectedRows = assistantQueueSnapshot.rows.filter {
            assistantQueueSelectedItemIDs.contains($0.id)
        }
        guard !selectedRows.isEmpty else {
            errorMessage = emptyMessage
            integrationStatusMessage = nil
            return false
        }
        guard selectedRows.count == assistantQueueSelectedItemIDs.count,
              selectedRows.allSatisfy({ $0[keyPath: eligible] }),
              selectedRows.allSatisfy({ $0.mutationRevision != nil }) else {
            errorMessage = invalidSelectionMessage
            integrationStatusMessage = nil
            return false
        }
        let eligibleIDs = selectedRows.map(\.id)
        let expectedRevisions = Dictionary(
            uniqueKeysWithValues: selectedRows.compactMap { row in
                row.mutationRevision.map { (row.id, $0) }
            }
        )

        guard let atomicStore = assistantQueueStore as? any AtomicAssistantQueueStore else {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "Batch Assistant Queue actions require an atomic queue store."
            integrationStatusMessage = nil
            return false
        }

        do {
            _ = try atomicStore.transitionAll(
                ids: eligibleIDs,
                expectedRevisions: expectedRevisions,
                transform
            )
            assistantQueueSelectedItemIDs = []
            _ = refreshAssistantQueueSnapshot()
            errorMessage = nil
            integrationStatusMessage = successMessage(eligibleIDs.count)
            onChange()
            return true
        } catch is AssistantQueueReviewActionUnavailableError {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = "This Assistant Queue item cannot be changed by that review action in its current state."
            integrationStatusMessage = nil
            return false
        } catch is AssistantQueueStaleReviewError {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueMutationFailure.staleUserMessage
            integrationStatusMessage = nil
            return false
        } catch {
            _ = refreshAssistantQueueSnapshot()
            errorMessage = AssistantQueueStoreError.userMessage(for: error)
            integrationStatusMessage = nil
            return false
        }
    }

    private func pruneAssistantQueueSelectionToVisibleRows() {
        let batchSelectableIDs = Set(
            assistantQueueSnapshot.rows
                .filter { row in
                    (row.canDefer || row.canReject) && row.mutationRevision != nil
                }
                .map(\.id)
        )
        assistantQueueSelectedItemIDs.formIntersection(batchSelectableIDs)
    }

    private static func assistantQueueExecutionMessage(for error: Error) -> String {
        switch error {
        case is AssistantQueueStaleReviewError:
            return "This Assistant Queue item changed. Review the latest details before running it."
        case let error as AssistantQueueConversationLinkRequiresReviewError:
            return UserFacingErrorMessageSanitizer.message(
                from: error.reason,
                fallback: "Review this conversation action again."
            )
        case let error as AssistantQueueConversationLinkUnavailableError:
            return UserFacingErrorMessageSanitizer.message(
                from: error.reason,
                fallback: "Conversation execution evidence is unavailable."
            )
        case let error as AssistantQueueConversationLinkPersistenceError:
            return error.queueStateMarkedFailed
                ? "Conversation execution evidence could not be saved. Create a new reviewed plan before retrying."
                : "Conversation execution evidence and queue recovery could not be saved. Check local storage before retrying."
        case AssistantQueueExecutionError.unsupportedPayload:
            return "This Assistant Queue item cannot run from Project Board yet."
        case AssistantQueueExecutionError.receiptPersistenceFailed(let queueStateMarkedFailed):
            if queueStateMarkedFailed {
                return "Assistant Queue execution finished, but the execution receipt could not be saved. Fix receipt storage before retrying."
            }
            return "Assistant Queue execution finished, but receipt storage and queue state update both failed. Check local data storage before retrying."
        case AssistantQueueExecutionError.managedUsageLedgerPersistenceFailed(let queueStateMarkedFailed):
            if queueStateMarkedFailed {
                return "Assistant Queue execution finished, but managed AI usage could not be saved. Fix billing ledger storage before retrying."
            }
            return "Assistant Queue execution finished, but managed AI usage and queue state update both failed. Check local billing storage before retrying."
        case AssistantQueueExecutionError.managedUsageCapCheckFailed(let queueStateMarkedFailed):
            if queueStateMarkedFailed {
                return "Managed AI usage caps could not be checked. Fix billing ledger storage before retrying."
            }
            return "Managed AI usage caps could not be checked, and the queue state could not be updated. Check local billing storage before retrying."
        case AssistantQueueExecutionError.managedUsageCapExceeded(let projection, _):
            return projection.blockingReason
        case AssistantQueueTransitionError.approvalRequiredBeforeRunning:
            return "Approve this Assistant Queue item before running it."
        case AssistantQueueTransitionError.costPreviewRequiredBeforeApproval,
             AssistantQueueTransitionError.costPreviewRequiredBeforeRunning:
            return "Review the cost preview before running this Assistant Queue item."
        case AssistantQueueTransitionError.managedCostCapExceeded:
            return "This managed cost preview exceeds the configured cap. Adjust the request before running."
        case AssistantQueueTransitionError.approvedPayloadChanged:
            return "Review this Assistant Queue item again because it changed after approval."
        case AssistantQueueTransitionError.runningRequiredBeforeCompletion:
            return "Assistant Queue execution is not in a runnable state."
        case AssistantQueueTransitionError.blockedItemCannotBeApproved,
             AssistantQueueTransitionError.dangerousPayloadCannotBeApproved:
            return "Dangerous Assistant Queue items cannot be executed."
        case AssistantQueueTransitionError.terminalItemCannotTransition:
            return "Assistant Queue item was already reviewed."
        case AssistantQueueTransitionError.editRequiresReviewableItem:
            return "Only reviewable Assistant Queue items can be edited."
        default:
            return "Assistant Queue execution could not be completed."
        }
    }

    private static func dailyPlanningReadoutFailureMessage(for error: Error) -> String {
        let rawMessage: String
        if let error = error as? TTSProviderError {
            rawMessage = error.userMessage
        } else if let error = error as? SpeechAudioPlaybackError {
            rawMessage = error.userMessage
        } else {
            rawMessage = UserFacingErrorMessageSanitizer.message(from: error)
        }
        let redactedSecrets = UserFacingErrorMessageSanitizer.message(
            from: rawMessage,
            fallback: "Playback failed."
        )
        return String(
            format: String(localized: "Daily Planning readout failed. %@"),
            LocalPathRedactor.redact(redactedSecrets)
        )
    }

    private static func reviewCalendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    private static func userFacingMessage(for error: Error) -> String {
        userFacingMessage(for: error, fallback: String(localized: "Project board unavailable"))
    }

    private static func userFacingMessage(for error: Error, fallback: String) -> String {
        if let databaseError = error as? DatabaseError {
            let message: String
            switch databaseError {
            case .openFailed(let detail), .executeFailed(let detail),
                 .prepareFailed(let detail), .stepFailed(let detail),
                 .missingColumn(let detail):
                message = detail
            case .busyTimeout(let operation):
                message = "The local database stayed busy during \(operation). Try again."
            case .duplicateColumnName(let column):
                message = "The local database query returned duplicate column \(column)."
            case .invalidColumnValue(let column, let value):
                message = "\(column) contains invalid value \(value)."
            case .nestedTransaction:
                message = "A nested local database transaction was rejected."
            }
            return UserFacingErrorMessageSanitizer.message(from: message, fallback: fallback)
        }
        guard let decodingError = error as? LocalStoreDecodingError else {
            return UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: fallback
            )
        }

        return repairGuidance(for: decodingError)
    }

    private static func repairGuidance(for error: LocalStoreDecodingError) -> String {
        let action = "Restore from backup or repair the local database, then reopen Suisui."
        switch error {
        case .invalidStringArray(let column):
            return "Local board data needs repair: \(column) contains invalid list JSON. \(action)"
        case .invalidDoubleArray(let column):
            return "Local board data needs repair: \(column) contains invalid numeric vector JSON. \(action)"
        case .invalidStringMap(let column):
            return "Local board data needs repair: \(column) contains invalid key-value JSON. \(action)"
        case .inconsistentDimensions(let column, let expected, let actual):
            return "Local board data needs repair: \(column) has \(actual) values, expected \(expected). \(action)"
        case .missingRequiredColumn(let column):
            return "Local board data needs repair: \(column) is missing. \(action)"
        case .invalidInt64(let column, let value):
            return "Local board data needs repair: \(column) contains invalid integer value \(quotedDisplayValue(value)). \(action)"
        case .invalidEnum(let column, let value):
            return "Local board data needs repair: \(column) contains unsupported value \(quotedDisplayValue(value)). \(action)"
        case .invalidDate(let column, let value):
            return "Local board data needs repair: \(column) contains invalid date value \(quotedDisplayValue(value)). \(action)"
        }
    }

    private static func quotedDisplayValue(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let maxVisibleCharacters = 80
        guard normalized.count > maxVisibleCharacters else {
            return "\"\(normalized)\""
        }
        return "\"\(String(normalized.prefix(maxVisibleCharacters)))...\""
    }

    public func setShowsArchivedProjects(_ isShown: Bool) {
        showsArchivedProjects = isShown
        load()
    }

    public func setShowsCompletedWorkflowTasks(_ isShown: Bool) {
        guard showsCompletedWorkflowTasks != isShown else {
            return
        }
        showsCompletedWorkflowTasks = isShown
        load(invalidationReason: .completedVisibilityChanged)
    }

    public func exportTaskInteropJSON(exportedAt: Date = Date()) -> Data? {
        do {
            let data = try TaskInteropExportService(store: store).exportJSON(exportedAt: exportedAt)
            integrationStatusMessage = "Prepared task export JSON."
            errorMessage = nil
            return data
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func importTaskInteropJSON(_ data: Data) -> ExternalTaskImportResult? {
        guard let externalTaskLinkStore else {
            errorMessage = "Task import is unavailable in this build."
            return nil
        }

        do {
            let document = try TaskInteropDocument.decode(data)
            let result = try TaskInteropDocumentImportService(
                store: store,
                linkStore: externalTaskLinkStore
            ).importDocument(document)
            load()
            integrationStatusMessage = Self.importStatusMessage(for: result)
            clearErrorAfterSuccessfulLoad()
            onChange()
            return result
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: "Task import failed. Choose a Suisui task JSON export."
            )
            return nil
        }
    }

    public func recordTaskInteropFileFailure(_ error: Error) {
        errorMessage = Self.userFacingMessage(
            for: error,
            fallback: "Task import/export failed."
        )
    }

    public func recordTaskInteropExportCompleted() {
        integrationStatusMessage = String(localized: "Exported task JSON.")
        errorMessage = nil
    }

    private static func importStatusMessage(for result: ExternalTaskImportResult) -> String {
        let taskLabel = String(
            format: String(localized: result.createdTaskCount == 1 ? "%d task" : "%d tasks"),
            result.createdTaskCount
        )
        if result.skippedDuplicateCount > 0 {
            let skippedLabel = String(
                format: String(localized: result.skippedDuplicateCount == 1 ? "%d duplicate" : "%d duplicates"),
                result.skippedDuplicateCount
            )
            return String(
                format: String(localized: "Imported %@ from JSON. Skipped %@."),
                taskLabel,
                skippedLabel
            )
        }
        return String(format: String(localized: "Imported %@ from JSON."), taskLabel)
    }

    private static func googleCalendarSyncStatusMessage(for result: GoogleCalendarTaskSyncResult) -> String {
        let createdLabel = String(
            format: String(localized: result.createdEventCount == 1 ? "%d Google Calendar event" : "%d Google Calendar events"),
            result.createdEventCount
        )
        var sentences = [
            String(format: String(localized: "Created %@."), createdLabel)
        ]

        if result.skippedAlreadyLinkedCount > 0 {
            let skippedLabel = String(
                format: String(localized: result.skippedAlreadyLinkedCount == 1 ? "%d already-linked task" : "%d already-linked tasks"),
                result.skippedAlreadyLinkedCount
            )
            sentences.append(String(format: String(localized: "Skipped %@."), skippedLabel))
        }

        if result.deferredDueToRunLimitCount > 0 {
            let deferredLabel = String(
                format: String(localized: result.deferredDueToRunLimitCount == 1 ? "%d due task" : "%d due tasks"),
                result.deferredDueToRunLimitCount
            )
            sentences.append(String(format: String(localized: "Deferred %@."), deferredLabel))
        }

        if result.failedRetryableCount > 0 {
            let retryableLabel = String(
                format: String(localized: result.failedRetryableCount == 1 ? "%d retryable task" : "%d retryable tasks"),
                result.failedRetryableCount
            )
            sentences.append(String(format: String(localized: "Rate-limited %@."), retryableLabel))
        }

        if result.failedNonRetryableCount > 0 {
            let failedLabel = String(
                format: String(localized: result.failedNonRetryableCount == 1 ? "%d task" : "%d tasks"),
                result.failedNonRetryableCount
            )
            sentences.append(String(format: String(localized: "Failed %@."), failedLabel))
        }

        if result.hasMoreWork {
            sentences.append(String(localized: "More due tasks remain; run sync again after approval."))
        }

        return sentences.joined(separator: " ")
    }

    @discardableResult
    public func createTask(
        title: String,
        detail: String = "",
        projectID: Int64? = nil,
        status: ProjectTaskStatus = .backlog,
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask? {
        beginRecoverableOperation()
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return nil
        }

        let draft = ProjectBoardTaskDraft(
            projectID: targetProjectID,
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueAt
        )
        do {
            let task = try store.createTask(draft)
            selectedProjectID = targetProjectID
            selectedTaskID = task.id
            load()
            selectedTaskID = task.id
            onChange()
            return task
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordFailure(
                .saveFailed(String(localized: "Restore the project before adding tasks.")),
                retryAction: .createTask(draft)
            )
            return nil
        } catch ProjectBoardStoreError.emptyTitle {
            recordFailure(.saveFailed(String(localized: "Task title is required.")), retryAction: .createTask(draft))
            return nil
        } catch {
            recordFailure(.saveFailed(Self.userFacingMessage(for: error)), retryAction: .createTask(draft))
            return nil
        }
    }

    @discardableResult
    public func createInboxTask(
        title: String,
        detail: String = "",
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) -> ProjectBoardTask? {
        var resolvedTitle = title
        var resolvedDueAt = dueAt
        if dueAt == nil {
            let parsed = QuickAddDueDateParser.parse(title)
            if let parsedDueAt = parsed.dueAt {
                resolvedTitle = parsed.title
                resolvedDueAt = DeadlineDateParser.string(from: parsedDueAt)
            }
        }

        if detail.isEmpty, priority == .medium, resolvedDueAt == nil {
            do {
                let task = try store.createInboxTask(title: resolvedTitle)
                selectedProjectID = task.projectID
                selectedTaskID = task.id
                load()
                selectedProjectID = task.projectID
                selectedTaskID = task.id
                clearErrorAfterSuccessfulLoad()
                onChange()
                return task
            } catch ProjectBoardStoreError.emptyTitle {
                errorMessage = "Task title is required."
                return nil
            } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
                errorMessage = "Restore the project before adding tasks."
                return nil
            } catch {
                errorMessage = Self.userFacingMessage(for: error)
                return nil
            }
        }

        do {
            let liveSnapshot = try store.loadSnapshot(includeArchived: false)
            snapshot = liveSnapshot
            let inboxProject: ProjectBoardProject
            if let activeInbox = liveSnapshot.projects.first(where: {
                $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived
            }) {
                inboxProject = activeInbox
            } else {
                inboxProject = try store.createProject(title: "Inbox")
            }
            let task = try store.createTask(ProjectBoardTaskDraft(
                projectID: inboxProject.id,
                title: resolvedTitle,
                detail: detail,
                status: .backlog,
                priority: priority,
                dueAt: resolvedDueAt
            ))
            selectedProjectID = inboxProject.id
            selectedTaskID = task.id
            load()
            selectedProjectID = inboxProject.id
            selectedTaskID = task.id
            clearErrorAfterSuccessfulLoad()
            onChange()
            return task
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
            return nil
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before adding tasks."
            return nil
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
            return nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func createProject(title: String = "Untitled Project") -> ProjectBoardProject? {
        beginRecoverableOperation()
        do {
            let project = try store.createProject(title: title)
            load()
            selectedProjectID = project.id
            selectedTaskID = nil
            onChange()
            return project
        } catch ProjectBoardStoreError.emptyProjectTitle {
            recordFailure(
                .saveFailed(String(localized: "Project title is required.")),
                retryAction: .createProject(title: title)
            )
            return nil
        } catch {
            recordFailure(.saveFailed(Self.userFacingMessage(for: error)), retryAction: .createProject(title: title))
            return nil
        }
    }

    public func updateSelectedProject(title: String) {
        guard let selectedProjectID else {
            return
        }
        beginRecoverableOperation()

        do {
            _ = try store.updateProject(id: selectedProjectID, title: title)
            load()
            self.selectedProjectID = selectedProjectID
            onChange()
        } catch ProjectBoardStoreError.emptyProjectTitle {
            recordFailure(
                .saveFailed(String(localized: "Project title is required.")),
                retryAction: .updateProject(id: selectedProjectID, title: title)
            )
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                retryAction: .updateProject(id: selectedProjectID, title: title)
            )
        }
    }

    @discardableResult
    public func assignProjectWorkspacePath(_ path: String, bookmarkData: Data? = nil, projectID: Int64? = nil) -> Bool {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return false
        }

        do {
            _ = try store.setProjectWorkspacePath(id: targetProjectID, path: path, bookmarkData: bookmarkData)
            load()
            selectedProjectID = targetProjectID
            selectedTaskID = nil
            clearErrorAfterSuccessfulLoad()
            onChange()
            return true
        } catch ProjectBoardStoreError.nonAbsoluteWorkspacePath {
            errorMessage = "Project directory must be an absolute local path."
            return false
        } catch ProjectBoardStoreError.missingWorkspaceBookmark {
            errorMessage = "Project directory permission could not be saved. Choose the directory again."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func clearProjectWorkspacePath(projectID: Int64? = nil) -> Bool {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return false
        }

        do {
            _ = try store.setProjectWorkspacePath(id: targetProjectID, path: nil, bookmarkData: nil)
            load()
            selectedProjectID = targetProjectID
            selectedTaskID = nil
            clearErrorAfterSuccessfulLoad()
            onChange()
            return true
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func reportProjectWorkspaceSelectionFailure() {
        errorMessage = "Project directory permission could not be saved. Choose the directory again."
    }

    public func completeSelectedProject() {
        guard let selectedProjectID else {
            return
        }
        beginRecoverableOperation()

        do {
            _ = try store.completeProject(id: selectedProjectID)
            load()
            self.selectedProjectID = selectedProjectID
            onChange()
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                retryAction: .completeProject(id: selectedProjectID)
            )
        }
    }

    public func archiveSelectedProject() {
        guard let selectedProjectID else {
            return
        }
        beginRecoverableOperation()

        do {
            _ = try store.archiveProject(id: selectedProjectID)
            self.selectedProjectID = nil
            selectedTaskID = nil
            load()
            onChange()
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                retryAction: .archiveProject(id: selectedProjectID)
            )
        }
    }

    public func restoreSelectedProject() {
        guard let selectedProjectID else {
            return
        }
        beginRecoverableOperation()

        do {
            _ = try store.restoreProject(id: selectedProjectID)
            load()
            self.selectedProjectID = selectedProjectID
            onChange()
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                retryAction: .restoreProject(id: selectedProjectID)
            )
        }
    }

    public func deleteSelectedProject() {
        guard let selectedProjectID else {
            return
        }
        beginRecoverableOperation()

        do {
            try store.deleteProject(id: selectedProjectID)
            self.selectedProjectID = nil
            selectedTaskID = nil
            load()
            onChange()
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                retryAction: .deleteProject(id: selectedProjectID)
            )
        }
    }

    public func updateSelectedTask(
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueAt: String?,
        recurrence: String? = nil
    ) {
        guard let selectedTask else {
            return
        }
        beginRecoverableOperation(taskID: selectedTask.id)

        let draft = ProjectBoardTaskDraft(
            projectID: selectedTask.projectID,
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueAt,
            recurrence: recurrence
        )
        let isCompletionTransition = status == .done && selectedTask.status != .done
        let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()

        do {
            _ = try store.updateTask(id: selectedTask.id, draft)
            load()
            if isCompletionTransition {
                // Inspector saves that flip a task to done are completions and
                // must undo like one: reopen and remove an untouched
                // regenerated occurrence in the same undo step.
                let regenerated = regeneratedTasksAfterMutation(notIn: taskIDsBeforeMutation)
                boardOperationUndo.push(.undoCompletion(snapshot: selectedTask, regenerated: regenerated.first))
            } else if draft != selectedTask.classificationDraft {
                boardOperationUndo.push(.revertFields(snapshot: selectedTask))
            }
            selectedTaskID = selectedTask.id
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordFailure(
                .saveFailed(String(localized: "Restore the project before editing tasks.")),
                taskID: selectedTask.id,
                retryAction: .saveTask(taskID: selectedTask.id, draft: draft)
            )
        } catch ProjectBoardStoreError.emptyTitle {
            recordFailure(
                .saveFailed(String(localized: "Task title is required.")),
                taskID: selectedTask.id,
                retryAction: .saveTask(taskID: selectedTask.id, draft: draft)
            )
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                taskID: selectedTask.id,
                retryAction: .saveTask(taskID: selectedTask.id, draft: draft)
            )
        }
    }

    public func updateSelectedTask(
        title: String,
        detail: String,
        status: ProjectTaskStatus,
        priority: ProjectTaskPriority,
        dueDate: Date?,
        recurrence: String? = nil
    ) {
        updateSelectedTask(
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueDate.map(DeadlineDateParser.string(from:)),
            recurrence: recurrence
        )
    }

    public func markSelectedTaskAsTask() {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .makeTask,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Kept \"%@\" as a task."), selectedTask.title),
                systemImage: "checkmark.circle",
                canUndo: true
            )
        )
    }

    public func convertSelectedTaskToProject() {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .makeProject,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Created project \"%@\"."), selectedTask.title),
                systemImage: "folder.badge.plus",
                canUndo: true
            )
        )
    }

    public func scheduleSelectedTaskForToday(referenceDate: Date = Date()) {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .scheduleToday,
            referenceDate: referenceDate,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Scheduled \"%@\" for today."), selectedTask.title),
                systemImage: "calendar.badge.plus",
                canUndo: true
            )
        )
    }

    public func deferSelectedTaskForLater(referenceDate: Date = Date()) {
        guard let selectedTask else {
            return
        }

        performSelectedInboxTriage(
            action: .reviewLater,
            referenceDate: referenceDate,
            feedback: InboxClassificationFeedback(
                message: String(format: String(localized: "Deferred \"%@\" for later review."), selectedTask.title),
                systemImage: "clock",
                canUndo: true
            )
        )
    }

    @discardableResult
    public func applyInboxVoiceTriageCommand(
        _ command: InboxVoiceTriageCommand,
        referenceDate: Date = Date()
    ) -> Bool {
        switch command.action {
        case .selectNext:
            return selectNextInboxTaskFromVoiceTriage()
        case .undo:
            guard lastInboxClassificationUndo != nil else {
                errorMessage = "There is no Inbox voice triage action to undo."
                return false
            }
            undoLastInboxClassification()
            return errorMessage == nil
        case .scheduleToday:
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            scheduleSelectedTaskForToday(referenceDate: referenceDate)
            return snapshot.projects.flatMap(\.tasks).first { $0.id == selectedTask.id }?.dueAt != selectedTask.dueAt
                && errorMessage == nil
        case .reviewLater:
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            deferSelectedTaskForLater(referenceDate: referenceDate)
            let record = inboxTriageRecordsByTaskID[selectedTask.id]
            return record?.disposition == .reviewLater && errorMessage == nil
        case .complete:
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            performSelectedInboxTriage(
                action: .complete,
                feedback: InboxClassificationFeedback(
                    message: String(format: String(localized: "Completed \"%@\"."), selectedTask.title),
                    systemImage: "checkmark.circle.fill",
                    canUndo: true
                )
            )
            return snapshot.projects.flatMap(\.tasks).first { $0.id == selectedTask.id }?.status == .done
                && errorMessage == nil
        case .setPriority(let priority):
            guard let selectedTask = selectedInboxTaskForVoiceTriage() else {
                return false
            }
            applyInboxTaskUpdate(
                originalTask: selectedTask,
                draft: ProjectBoardTaskDraft(
                    projectID: selectedTask.projectID,
                    title: selectedTask.title,
                    detail: selectedTask.detail,
                    status: selectedTask.status,
                    priority: priority,
                    dueAt: selectedTask.dueAt,
                    recurrence: selectedTask.recurrence
                ),
                feedback: InboxClassificationFeedback(
                    message: String(format: String(localized: "Set \"%@\" to %@ priority."), selectedTask.title, priority.label),
                    systemImage: "flag",
                    canUndo: true
                )
            )
            return snapshot.projects.flatMap(\.tasks).first { $0.id == selectedTask.id }?.priority == priority
                && errorMessage == nil
        }
    }

    public func undoLastInboxClassification() {
        guard let undo = lastInboxClassificationUndo else {
            return
        }

        do {
            let restoredTask: ProjectBoardTask
            switch undo {
            case .restoreMutation(let mutation, let regenerated):
                restoredTask = try undoInboxTriageOperation(
                    mutation: mutation,
                    regenerated: regenerated
                )
            case .restoreTask(let originalTask):
                restoredTask = try store.updateTask(id: originalTask.id, originalTask.classificationDraft)
            case .restoreTaskAndDeleteProject(let originalTask, let createdProjectID):
                let recreatedTask = try store.createTask(originalTask.classificationDraft)
                // Project conversion deletes the original Inbox task with its
                // project. Move capture metadata first so voice memos keep their
                // transcript and retry state across Undo.
                _ = try inboxCaptureStore?.relinkCaptures(fromTaskID: originalTask.id, toTaskID: recreatedTask.id)
                do {
                    try store.deleteProject(id: createdProjectID)
                } catch {
                    try? store.deleteTask(id: recreatedTask.id)
                    throw error
                }
                restoredTask = recreatedTask
            }
            load()
            refreshDerivedReadModels(
                on: inboxVisibilityReferenceDate ?? readModelNow(),
                calendar: readModelCalendarProvider()
            )
            selectedProjectID = restoredTask.projectID
            selectedTaskID = restoredTask.id
            inboxClassificationFeedback = nil
            lastInboxClassificationUndo = nil
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before undoing the classification."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public var canUndoBoardOperation: Bool {
        !boardOperationUndo.isEmpty
    }

    /// Applies the most recent board-operation undo entry (⌘Z / Edit menu).
    ///
    /// Undo only calls existing store APIs and never re-runs completion side
    /// effects, so reverting a recurrence completion cannot regenerate another
    /// occurrence. The applied entry is removed only on success; a failed undo
    /// keeps the stack intact so the user can retry after fixing the cause.
    public func undoLastBoardOperation() {
        guard let entry = boardOperationUndo.last else {
            return
        }

        do {
            let feedbackMessage: String
            var restoredSelection: (projectID: Int64, taskID: Int64)?
            switch entry {
            case .restoreTask(let snapshot):
                let restored = try restoreDeletedTask(
                    snapshot: snapshot,
                    triageRecord: nil,
                    captures: []
                )
                restoredSelection = (restored.projectID, restored.id)
                feedbackMessage = String(localized: "Undo: restored the deleted task.")
            case .restoreTaskWithCaptures(let snapshot, let captures):
                let restored = try restoreDeletedTask(
                    snapshot: snapshot,
                    triageRecord: nil,
                    captures: captures
                )
                restoredSelection = (restored.projectID, restored.id)
                feedbackMessage = String(localized: "Undo: restored the deleted task and voice memo.")
            case .restoreInboxTask(let snapshot, let triageRecord, let captures):
                let restored = try restoreDeletedTask(
                    snapshot: snapshot,
                    triageRecord: triageRecord,
                    captures: captures
                )
                restoredSelection = (restored.projectID, restored.id)
                feedbackMessage = captures.isEmpty
                    ? String(localized: "Undo: restored the deleted task.")
                    : String(localized: "Undo: restored the deleted task and voice memo.")
            case .revertStatus(let snapshot):
                let reverted = try store.applyTaskUndoSnapshot(snapshot)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: moved the task back.")
            case .revertFields(let snapshot):
                let reverted = try store.applyTaskUndoSnapshot(snapshot)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: restored the task details.")
            case .undoCompletion(let snapshot, let regenerated):
                let reverted = try undoCompletionOperation(snapshot: snapshot, regenerated: regenerated)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: reopened the completed task.")
            case .revertInboxTriage(let mutation, let regenerated):
                let reverted = try undoInboxTriageOperation(mutation: mutation, regenerated: regenerated)
                restoredSelection = (reverted.projectID, reverted.id)
                feedbackMessage = String(localized: "Undo: restored the Inbox item.")
            case .revertStatusBatch(let snapshots, let regenerated):
                for regeneratedTask in regenerated where isRegeneratedTaskUntouched(regeneratedTask) {
                    try store.deleteTask(id: regeneratedTask.id)
                }
                for snapshot in snapshots {
                    _ = try store.applyTaskUndoSnapshot(snapshot)
                }
                restoredSelection = snapshots.last.map { ($0.projectID, $0.id) }
                feedbackMessage = String(format: String(localized: "Undo: moved %d tasks back."), snapshots.count)
            }
            boardOperationUndo.pop()
            load()
            if let restoredSelection {
                selectedProjectID = restoredSelection.projectID
                selectedTaskID = restoredSelection.taskID
            }
            showBoardUndoFeedback(feedbackMessage)
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before undoing this change."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func restoreDeletedTask(
        snapshot: ProjectBoardTask,
        triageRecord: InboxTriageRecord?,
        captures: [InboxCaptureRecord]
    ) throws -> ProjectBoardTask {
        if let atomicStore = store as? any ProjectBoardDeleteUndoRestoring,
           triageRecord != nil || !captures.isEmpty {
            return try atomicStore.restoreDeletedTask(
                from: snapshot,
                triageRecord: triageRecord,
                captures: captures
            )
        }

        // Test doubles and non-SQLite integrations keep the additive fallback;
        // production SQLite uses the capability above because compensation
        // cannot provide an atomic retry guarantee after a storage failure.
        let restored: ProjectBoardTask
        if let triageRecord {
            restored = try store.undoInboxTriage(InboxTriageMutation(
                originalTask: snapshot,
                originalRecord: triageRecord,
                updatedTask: snapshot
            ))
        } else {
            restored = try store.restoreTask(from: snapshot)
        }
        var restoredCaptureIDs: [Int64] = []
        do {
            if !captures.isEmpty {
                guard let inboxCaptureStore else {
                    throw InboxCaptureStoreError.linkedTaskMissing
                }
                for capture in captures {
                    let restoredCapture = try inboxCaptureStore.createVoiceCapture(InboxVoiceCaptureDraft(
                        taskID: restored.id,
                        audioFilePath: capture.audioFilePath,
                        durationSeconds: capture.durationSeconds,
                        transcript: capture.transcript,
                        interpretationSummary: capture.interpretationSummary,
                        memo: capture.memo,
                        classificationStatus: capture.classificationStatus,
                        transcriptionStatus: capture.transcriptionStatus,
                        createdAt: capture.createdAt
                    ))
                    restoredCaptureIDs.append(restoredCapture.id)
                }
            }
            return restored
        } catch {
            // The recreated task has a new ID. Roll back every dependent row
            // so a failed capture restore can be retried as one Undo. Triage
            // restoration already shares the store's task transaction.
            for captureID in restoredCaptureIDs {
                try? inboxCaptureStore?.delete(id: captureID)
            }
            try? store.deleteTask(id: restored.id)
            throw error
        }
    }

    private func undoCompletionOperation(
        snapshot: ProjectBoardTask,
        regenerated: ProjectBoardTask?
    ) throws -> ProjectBoardTask {
        guard let regenerated, isRegeneratedTaskUntouched(regenerated) else {
            // Rule: when the regenerated next occurrence was already edited,
            // moved, or completed by the user (or no longer exists), keep it
            // and only restore the original task's previous open state.
            return try store.applyTaskUndoSnapshot(snapshot)
        }
        try store.deleteTask(id: regenerated.id)
        do {
            return try store.applyTaskUndoSnapshot(snapshot)
        } catch {
            // Keep the undo all-or-nothing in effect: if the original cannot
            // be restored, put the regenerated occurrence back instead of
            // leaving the recurrence chain half-applied.
            _ = try? store.restoreTask(from: regenerated)
            throw error
        }
    }

    private func undoInboxTriageOperation(
        mutation: InboxTriageMutation,
        regenerated: ProjectBoardTask?
    ) throws -> ProjectBoardTask {
        let shouldRestoreRegenerated = regenerated.map(isRegeneratedTaskUntouched) == true
        if let regenerated, shouldRestoreRegenerated {
            try store.deleteTask(id: regenerated.id)
        }
        do {
            return try store.undoInboxTriage(mutation)
        } catch {
            // Keep the undo retryable and restore a deleted recurrence if the
            // disposition/task transaction cannot be applied.
            if let regenerated, shouldRestoreRegenerated {
                _ = try? store.restoreTask(from: regenerated)
            }
            throw error
        }
    }

    private func isRegeneratedTaskUntouched(_ regenerated: ProjectBoardTask) -> Bool {
        snapshot.projects.flatMap(\.tasks).first { $0.id == regenerated.id } == regenerated
    }

    private func visibleTaskIDsForUndoDiff() -> Set<Int64> {
        Set(snapshot.projects.flatMap(\.tasks).map(\.id))
    }

    /// Tasks that appeared during the last mutation. Completion-driven
    /// recurrence is the only insert a status move can perform, so an ID diff
    /// against the pre-mutation snapshot identifies regenerated occurrences
    /// without changing the store's transactional completion entry points.
    private func regeneratedTasksAfterMutation(notIn taskIDsBeforeMutation: Set<Int64>) -> [ProjectBoardTask] {
        snapshot.projects.flatMap(\.tasks).filter { !taskIDsBeforeMutation.contains($0.id) }
    }

    /// Shared undo recording for every status-move path (keyboard, card
    /// controls, Today completion toggle, and single or multi drag & drop).
    /// Must run after `load()` so the regenerated-occurrence diff sees the
    /// post-mutation snapshot.
    private func recordStatusMoveUndo(
        previousTasks: [ProjectBoardTask],
        to status: ProjectTaskStatus,
        taskIDsBeforeMutation: Set<Int64>
    ) {
        let changedTasks = previousTasks.filter { $0.status != status }
        guard !changedTasks.isEmpty else {
            return
        }
        let regenerated = regeneratedTasksAfterMutation(notIn: taskIDsBeforeMutation)
        if changedTasks.count == 1, let original = changedTasks.first {
            if status == .done {
                boardOperationUndo.push(.undoCompletion(snapshot: original, regenerated: regenerated.first))
            } else {
                boardOperationUndo.push(.revertStatus(snapshot: original))
            }
        } else {
            boardOperationUndo.push(.revertStatusBatch(snapshots: changedTasks, regenerated: regenerated))
        }
    }

    private static let boardUndoFeedbackDismissDelay: Duration = .seconds(3)

    private func showBoardUndoFeedback(_ message: String) {
        boardUndoFeedbackClearTask?.cancel()
        boardUndoFeedback = message
        boardUndoFeedbackClearTask = Task { [weak self] in
            try? await Task.sleep(for: Self.boardUndoFeedbackDismissDelay)
            guard !Task.isCancelled else {
                return
            }
            self?.boardUndoFeedback = nil
        }
    }

    public func moveSelectedTask(to status: ProjectTaskStatus) {
        guard let selectedTask else {
            return
        }

        moveTask(id: selectedTask.id, to: status)
    }

    public func moveTask(id: Int64, to status: ProjectTaskStatus) {
        beginRecoverableOperation(taskID: id)
        let previousTask = snapshot.projects.flatMap(\.tasks).first { $0.id == id }
        let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()
        do {
            let task = try store.moveTask(id: id, to: status)
            selectedProjectID = task.projectID
            load()
            if let previousTask {
                recordStatusMoveUndo(
                    previousTasks: [previousTask],
                    to: status,
                    taskIDsBeforeMutation: taskIDsBeforeMutation
                )
            }
            selectedProjectID = task.projectID
            selectedTaskID = id
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            recordFailure(
                .saveFailed(String(localized: "Restore the project before moving tasks.")),
                taskID: id,
                retryAction: .moveTask(id: id, status: status)
            )
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                taskID: id,
                retryAction: .moveTask(id: id, status: status)
            )
        }
    }

    public func toggleTaskCompletion(id: Int64) {
        guard let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == id }) else {
            errorMessage = "Task is no longer available."
            return
        }

        let previousProjectID = selectedProjectID
        let previousTaskID = selectedTaskID
        let targetStatus: ProjectTaskStatus = task.status == .done ? .planned : .done
        let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()

        do {
            if inboxProject?.id == task.projectID {
                let mutation = try store.performInboxTriage(
                    taskID: id,
                    action: targetStatus == .done ? .complete : .reopen,
                    referenceDate: readModelNow(),
                    calendar: readModelCalendarProvider()
                )
                load()
                boardOperationUndo.push(
                    .revertInboxTriage(
                        mutation: mutation,
                        regenerated: regeneratedTasksAfterMutation(notIn: taskIDsBeforeMutation).first
                    )
                )
            } else {
                _ = try store.moveTask(id: id, to: targetStatus)
                load()
                recordStatusMoveUndo(
                    previousTasks: [task],
                    to: targetStatus,
                    taskIDsBeforeMutation: taskIDsBeforeMutation
                )
            }
            selectedProjectID = previousProjectID
            selectedTaskID = previousTaskID
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    public func reopenCompletedTask(id: Int64) {
        if let task = snapshot.projects.flatMap(\.tasks).first(where: { $0.id == id }),
           inboxProject?.id == task.projectID {
            toggleTaskCompletion(id: id)
            return
        }
        moveTask(id: id, to: .planned)
    }

    @discardableResult
    public func moveDroppedTasks(ids rawIDs: [String], to status: ProjectTaskStatus) -> Bool {
        guard !rawIDs.isEmpty else {
            return false
        }

        var taskIDs: [Int64] = []
        for rawID in rawIDs {
            guard let taskID = Int64(rawID) else {
                errorMessage = "Could not move task: invalid drag payload."
                return false
            }
            taskIDs.append(taskID)
        }

        return moveDroppedTasks(ids: taskIDs, to: status)
    }

    @discardableResult
    public func moveDroppedTasks(ids taskIDs: [Int64], to status: ProjectTaskStatus) -> Bool {
        guard !taskIDs.isEmpty else {
            return false
        }

        let visibleTasks = snapshot.projects.flatMap(\.tasks)
        let visibleTaskIDs = Set(visibleTasks.map(\.id))
        guard taskIDs.allSatisfy({ visibleTaskIDs.contains($0) }) else {
            errorMessage = "Could not move task: task is no longer available."
            return false
        }
        let tasksByID = Dictionary(uniqueKeysWithValues: visibleTasks.map { ($0.id, $0) })
        let previousTasks = taskIDs.compactMap { tasksByID[$0] }

        do {
            let movedTasks = try store.moveTasks(ids: taskIDs, to: status)
            load()
            recordStatusMoveUndo(
                previousTasks: previousTasks,
                to: status,
                taskIDsBeforeMutation: visibleTaskIDs
            )
            if let lastMovedTask = movedTasks.last {
                selectedProjectID = lastMovedTask.projectID
                selectedTaskID = lastMovedTask.id
            }
            onChange()
            return true
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func moveDroppedTasks(ids rawIDs: [String], toProjectID projectID: Int64) -> Bool {
        guard !rawIDs.isEmpty else {
            return false
        }

        var taskIDs: [Int64] = []
        for rawID in rawIDs {
            guard let taskID = Int64(rawID) else {
                errorMessage = "Could not move task: invalid drag payload."
                return false
            }
            taskIDs.append(taskID)
        }

        return moveDroppedTasks(ids: taskIDs, toProjectID: projectID)
    }

    @discardableResult
    public func moveDroppedTasks(ids taskIDs: [Int64], toProjectID projectID: Int64) -> Bool {
        guard !taskIDs.isEmpty else {
            return false
        }
        guard snapshot.projects.contains(where: { $0.id == projectID }) else {
            errorMessage = "Could not move task: project is no longer available."
            return false
        }
        let visibleTaskIDs = Set(snapshot.projects.flatMap(\.tasks).map(\.id))
        guard taskIDs.allSatisfy({ visibleTaskIDs.contains($0) }) else {
            errorMessage = "Could not move task: task is no longer available."
            return false
        }

        do {
            let movedTasks = try store.moveTasks(ids: taskIDs, toProjectID: projectID)
            load()
            selectedProjectID = projectID
            selectedTaskID = movedTasks.last?.id
            integrationStatusMessage = movedTasks.count == 1
                ? String(localized: "Moved task to project.")
                : String(format: String(localized: "Moved %d tasks to project."), movedTasks.count)
            clearErrorAfterSuccessfulLoad()
            onChange()
            return true
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before moving tasks."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    public func deleteSelectedTask() {
        guard let selectedTaskID else {
            return
        }
        beginRecoverableOperation(taskID: selectedTaskID)

        let deletedTask = selectedTask
        let deletedCaptures: [InboxCaptureRecord]
        let deletedTriageRecord: InboxTriageRecord?
        do {
            deletedCaptures = try inboxCaptureStore?.list(taskID: selectedTaskID) ?? []
            deletedTriageRecord = try store.loadInboxTriageRecords(taskIDs: [selectedTaskID])[selectedTaskID]
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                taskID: selectedTaskID,
                retryAction: .deleteTask(id: selectedTaskID)
            )
            return
        }
        do {
            try store.deleteTask(id: selectedTaskID)
            if let deletedTask {
                if let deletedTriageRecord {
                    boardOperationUndo.push(.restoreInboxTask(
                        snapshot: deletedTask,
                        triageRecord: deletedTriageRecord,
                        captures: deletedCaptures
                    ))
                } else if deletedCaptures.isEmpty {
                    boardOperationUndo.push(.restoreTask(snapshot: deletedTask))
                } else {
                    boardOperationUndo.push(.restoreTaskWithCaptures(
                        snapshot: deletedTask,
                        captures: deletedCaptures
                    ))
                }
            }
            self.selectedTaskID = nil
            load()
            onChange()
        } catch {
            recordFailure(
                .saveFailed(Self.userFacingMessage(for: error)),
                taskID: selectedTaskID,
                retryAction: .deleteTask(id: selectedTaskID)
            )
        }
    }

    @discardableResult
    public func createProjectArtifact(expectedPath: String, projectID: Int64? = nil) -> ProjectBoardArtifact? {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return nil
        }

        do {
            let artifact = try store.createProjectArtifact(projectID: targetProjectID, expectedPath: expectedPath)
            load()
            selectedProjectID = targetProjectID
            clearErrorAfterSuccessfulLoad()
            onChange()
            return artifact
        } catch ProjectBoardStoreError.emptyArtifactPath {
            errorMessage = "Artifact path is required."
            return nil
        } catch ProjectBoardStoreError.nonAbsoluteArtifactPath {
            errorMessage = "Use an absolute artifact path."
            return nil
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptArtifacts {
            errorMessage = "Restore the project before linking artifacts."
            return nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func deleteProjectArtifact(id: Int64, projectID: Int64? = nil) -> Bool {
        do {
            try store.deleteProjectArtifact(id: id)
            let targetProjectID = projectID ?? selectedProjectID
            load()
            selectedProjectID = targetProjectID
            clearErrorAfterSuccessfulLoad()
            onChange()
            return true
        } catch ArtifactStoreError.notFound {
            errorMessage = "Artifact link is no longer available."
            return false
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return false
        }
    }

    @discardableResult
    public func createProjectMilestone(title: String, dueAt: String? = nil, projectID: Int64? = nil) -> ProjectBoardMilestone? {
        guard let targetProjectID = projectID ?? selectedProject?.id else {
            errorMessage = "Project is required."
            return nil
        }

        do {
            let milestone = try store.createProjectMilestone(projectID: targetProjectID, title: title, dueAt: dueAt)
            load()
            selectedProjectID = targetProjectID
            clearErrorAfterSuccessfulLoad()
            onChange()
            return milestone
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Milestone title is required."
            return nil
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func completeProjectMilestone(id: Int64, projectID: Int64? = nil) -> ProjectBoardMilestone? {
        guard let milestone = snapshot.projects.flatMap(\.milestones).first(where: { $0.id == id }) else {
            errorMessage = "Milestone is no longer available."
            return nil
        }

        do {
            let updated = try store.updateProjectMilestone(
                id: id,
                title: milestone.title,
                dueAt: milestone.dueAt,
                isCompleted: true
            )
            load()
            selectedProjectID = projectID ?? milestone.projectID
            clearErrorAfterSuccessfulLoad()
            onChange()
            return updated
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
            return nil
        }
    }

    @discardableResult
    public func answerProjectAssistantQuestion(_ rawQuestion: String, projectID: Int64? = nil) -> ProjectAssistantAnswer? {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            errorMessage = "Assistant question is required."
            return nil
        }
        guard let project = project(for: projectID) else {
            errorMessage = "Project is required."
            return nil
        }

        let task = project.tasks.first { $0.status == .blocked }
            ?? project.tasks.first { $0.status != .done && $0.priority == .high }
            ?? project.tasks.filter { $0.status != .done }.sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") }.first
        let milestone = project.milestones.filter { !$0.isCompleted }.sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") }.first
        let actionTitle = task?.status == .blocked
            ? String(localized: "Review unblock plan")
            : String(localized: "Review next action")
        let answer = ProjectAssistantAnswer(
            projectID: project.id,
            question: question,
            message: localAssistantMessage(project: project, task: task, milestone: milestone),
            suggestedActionTitle: actionTitle,
            requiresReview: true
        )
        projectAssistantAnswer = answer
        projectAssistantReviewDraft = nil
        errorMessage = nil
        return answer
    }

    @discardableResult
    public func prepareProjectAssistantSuggestedActionForReview(projectID: Int64? = nil) -> Bool {
        guard let answer = projectAssistantAnswer,
              let project = project(for: projectID ?? answer.projectID) else {
            errorMessage = "Ask the project assistant before preparing review."
            return false
        }

        // Assistant suggestions stay approval-first. This records the proposed
        // next step for a Review flow instead of mutating tasks immediately.
        projectAssistantReviewDraft = ProjectAssistantReviewDraft(
            projectID: project.id,
            suggestedActionTitle: answer.suggestedActionTitle,
            summary: answer.message
        )
        selectedProjectID = project.id
        selectedTaskID = nil
        errorMessage = nil
        return true
    }

    private func project(for projectID: Int64?) -> ProjectBoardProject? {
        if let projectID {
            return snapshot.projects.first { $0.id == projectID }
        }
        return selectedProject
    }

    private func localAssistantMessage(
        project: ProjectBoardProject,
        task: ProjectBoardTask?,
        milestone: ProjectBoardMilestone?
    ) -> String {
        if let task, let milestone {
            return String(
                format: String(localized: "Start with %@, then check milestone %@."),
                task.title,
                milestone.title
            )
        }
        if let task {
            return String(format: String(localized: "Start with %@."), task.title)
        }
        if let milestone {
            return String(format: String(localized: "Next milestone is %@."), milestone.title)
        }
        return String(localized: "No open tasks or milestones need attention.")
    }

    private func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) {
        do {
            let updatedTask = try store.updateTask(id: id, draft)
            load()
            selectedProjectID = updatedTask.projectID
            selectedTaskID = updatedTask.id
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func performSelectedInboxTriage(
        action: InboxTriageAction,
        referenceDate: Date? = nil,
        feedback: InboxClassificationFeedback
    ) {
        guard let selectedTask else {
            return
        }

        do {
            let taskIDsBeforeMutation = visibleTaskIDsForUndoDiff()
            let mutation = try store.performInboxTriage(
                taskID: selectedTask.id,
                action: action,
                referenceDate: referenceDate ?? readModelNow(),
                calendar: readModelCalendarProvider()
            )
            let shouldAdvanceInboxSelection = inboxProject?.id == selectedTask.projectID
            load()
            refreshDerivedReadModels(
                on: inboxVisibilityReferenceDate ?? readModelNow(),
                calendar: readModelCalendarProvider()
            )
            let regenerated = regeneratedTasksAfterMutation(notIn: taskIDsBeforeMutation).first
            selectedProjectID = mutation.updatedTask.projectID
            selectedTaskID = mutation.updatedTask.id

            if shouldAdvanceInboxSelection,
               let nextInboxTask = filteredInboxTasks.first(where: { $0.id != selectedTask.id }) {
                selectedProjectID = nextInboxTask.projectID
                selectedTaskID = nextInboxTask.id
            }

            inboxClassificationFeedback = feedback
            lastInboxClassificationUndo = .restoreMutation(
                mutation: mutation,
                regenerated: regenerated
            )
            clearErrorAfterSuccessfulLoad()
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyProjectTitle {
            errorMessage = "Project title is required."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(
                for: error,
                fallback: String(localized: "Inbox triage update failed.")
            )
        }
    }

    private func applyInboxTaskUpdate(
        originalTask: ProjectBoardTask,
        draft: ProjectBoardTaskDraft,
        feedback: InboxClassificationFeedback
    ) {
        do {
            let updatedTask = try store.updateTask(id: originalTask.id, draft)
            finishInboxClassification(
                originalTask: originalTask,
                fallbackTask: updatedTask,
                feedback: feedback,
                undo: .restoreTask(originalTask: originalTask)
            )
            onChange()
        } catch ProjectBoardStoreError.archivedProjectCannotAcceptTasks {
            errorMessage = "Restore the project before editing tasks."
        } catch ProjectBoardStoreError.emptyTitle {
            errorMessage = "Task title is required."
        } catch {
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func finishInboxClassification(
        originalTask: ProjectBoardTask,
        fallbackTask: ProjectBoardTask,
        feedback: InboxClassificationFeedback,
        undo: InboxClassificationUndo
    ) {
        let shouldAdvanceInboxSelection = inboxProject?.id == originalTask.projectID
        load()
        selectedProjectID = fallbackTask.projectID
        selectedTaskID = fallbackTask.id

        if shouldAdvanceInboxSelection, let nextInboxTask = filteredInboxTasks.first(where: { $0.id != originalTask.id }) {
            selectedProjectID = nextInboxTask.projectID
            selectedTaskID = nextInboxTask.id
        }

        inboxClassificationFeedback = feedback
        lastInboxClassificationUndo = undo
        clearErrorAfterSuccessfulLoad()
    }

    private func ensureSelectedTaskIsVisibleInInboxFilter() {
        let visibleTasks = filteredInboxTasks
        guard let selectedTaskID else {
            if let first = visibleTasks.first {
                selectedProjectID = first.projectID
                self.selectedTaskID = first.id
            }
            return
        }

        guard !visibleTasks.contains(where: { $0.id == selectedTaskID }) else {
            return
        }

        selectedProjectID = visibleTasks.first?.projectID ?? inboxProject?.id
        self.selectedTaskID = visibleTasks.first?.id
    }

    private func selectedInboxTaskForVoiceTriage() -> ProjectBoardTask? {
        guard let selectedTask,
              inboxProject?.id == selectedTask.projectID,
              filteredInboxTasks.contains(where: { $0.id == selectedTask.id }) else {
            errorMessage = "Select an Inbox item before using voice triage."
            return nil
        }
        return selectedTask
    }

    private func selectNextInboxTaskFromVoiceTriage() -> Bool {
        let visibleTasks = filteredInboxTasks
        guard let selectedTaskID,
              let currentIndex = visibleTasks.firstIndex(where: { $0.id == selectedTaskID }) else {
            errorMessage = "Select an Inbox item before using voice triage."
            return false
        }

        let nextIndex = visibleTasks.index(after: currentIndex)
        guard nextIndex < visibleTasks.endIndex else {
            errorMessage = "There is no next Inbox item."
            return false
        }

        let nextTask = visibleTasks[nextIndex]
        // Voice triage changes only local UI selection here. It deliberately
        // avoids store writes so "next" cannot accidentally mutate task data.
        selectedProjectID = nextTask.projectID
        self.selectedTaskID = nextTask.id
        inboxClassificationFeedback = InboxClassificationFeedback(
            message: String(format: String(localized: "Selected \"%@\"."), nextTask.title),
            systemImage: "arrow.down.circle",
            canUndo: false
        )
        errorMessage = nil
        return true
    }

    private func matchesInboxTriageFilter(_ task: ProjectBoardTask, filter: InboxTriageFilter) -> Bool {
        guard filter != .all else {
            return true
        }

        let captures = captureRecords(for: task.id)
        switch filter {
        case .all:
            return true
        case .voice:
            return captures.contains { $0.sourceKind == .voiceMemo }
        case .aiSuggested:
            return captures.contains {
                $0.transcriptionStatus == .succeeded
                    && $0.interpretationSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        case .manual:
            return captures.isEmpty
        case .unprocessed:
            return isInboxUnprocessed(task, at: inboxVisibilityReferenceDate ?? readModelNow())
        }
    }

    private func isInboxUnprocessed(_ task: ProjectBoardTask, at referenceDate: Date) -> Bool {
        guard task.status != .done else {
            return false
        }

        let legacyDisposition: InboxTriageDisposition = task.dueAt == nil ? .unprocessed : .scheduled
        switch inboxTriageRecordsByTaskID[task.id]?.disposition ?? legacyDisposition {
        case .unprocessed:
            return true
        case .reviewLater:
            guard let rawReviewAt = inboxTriageRecordsByTaskID[task.id]?.reviewAt,
                  let reviewAt = ISO8601DateFormatter().date(from: rawReviewAt) else {
                // Corrupt deferred metadata must not silently hide captured work.
                return true
            }
            return reviewAt <= referenceDate
        case .task, .scheduled, .project:
            return false
        }
    }

    private func inboxUnprocessedCount(at referenceDate: Date) -> Int {
        inboxTasks.reduce(into: 0) { count, task in
            if isInboxUnprocessed(task, at: referenceDate) {
                count += 1
            }
        }
    }

    private func captureRecords(for taskID: Int64, reportErrors: Bool = false) -> [InboxCaptureRecord] {
        if let records = inboxCaptureRecordsByTaskID[taskID] {
            return records
        }
        guard let inboxCaptureStore else {
            // Older test/runtime surfaces can instantiate the board without
            // capture metadata. Treat those items as manual captures so the
            // Inbox remains usable instead of hiding work behind a missing store.
            return []
        }

        do {
            let records = try inboxCaptureStore.list(taskID: taskID)
            inboxCaptureRecordsByTaskID[taskID] = records
            return records
        } catch {
            if reportErrors {
                errorMessage = InboxCaptureStoreError.userMessage(for: error)
            }
            return []
        }
    }

    private func refreshInboxCaptureCache(for snapshot: ProjectBoardSnapshot) -> String? {
        guard let inboxCaptureStore else {
            inboxCaptureRecordsByTaskID = [:]
            return nil
        }

        let taskIDs = Self.inboxTaskIDs(in: snapshot)
        do {
            inboxCaptureRecordsByTaskID = try inboxCaptureStore.list(taskIDs: taskIDs)
            return nil
        } catch {
            inboxCaptureRecordsByTaskID = Dictionary(uniqueKeysWithValues: taskIDs.map { ($0, [InboxCaptureRecord]()) })
            return InboxCaptureStoreError.userMessage(for: error)
        }
    }

    private func refreshInboxCaptureCacheForInbox() {
        if let errorMessage = refreshInboxCaptureCache(for: snapshot) {
            self.errorMessage = errorMessage
        }
    }

    private func refreshInboxTriageCache(for snapshot: ProjectBoardSnapshot) -> String? {
        let taskIDs = Self.inboxTaskIDs(in: snapshot)
        guard !taskIDs.isEmpty else {
            inboxTriageRecordsByTaskID = [:]
            inboxTriageErrorMessage = nil
            return nil
        }
        do {
            inboxTriageRecordsByTaskID = try store.loadInboxTriageRecords(taskIDs: taskIDs)
            inboxTriageErrorMessage = nil
            return nil
        } catch {
            // Missing or temporarily unavailable metadata must not hide Inbox
            // rows. The filter derives a conservative legacy disposition from
            // each task until the next successful load.
            inboxTriageRecordsByTaskID = [:]
            let message = Self.userFacingMessage(
                for: error,
                fallback: String(localized: "Inbox triage state unavailable.")
            )
            inboxTriageErrorMessage = message
            return message
        }
    }

    private static func inboxTaskIDs(in snapshot: ProjectBoardSnapshot) -> Set<Int64> {
        guard let inboxProject = snapshot.projects.first(where: {
            $0.title.caseInsensitiveCompare("Inbox") == .orderedSame && !$0.isArchived
        }) else {
            return []
        }
        return Set(inboxProject.tasks.map(\.id))
    }

    private func replaceCachedCapture(_ updated: InboxCaptureRecord) {
        var records = inboxCaptureRecordsByTaskID[updated.taskID] ?? []
        if let index = records.firstIndex(where: { $0.id == updated.id }) {
            records[index] = updated
        } else {
            records.insert(updated, at: 0)
        }
        inboxCaptureRecordsByTaskID[updated.taskID] = records.sorted { $0.id > $1.id }
    }

    private static func inboxInterpretationConfidence(from memo: String?) -> String? {
        guard let memo else {
            return nil
        }
        let prefix = "Confidence:"
        guard let range = memo.range(of: prefix, options: [.caseInsensitive]) else {
            return nil
        }
        let value = memo[range.upperBound...]
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        return value?.isEmpty == false ? value : nil
    }

    private func dueDate(for rawDueAt: String?, calendar: Calendar? = nil) -> Date? {
        guard let rawDueAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawDueAt) {
            return date
        }

        let formatter = DateFormatter()
        var parsingCalendar = Calendar(identifier: .gregorian)
        parsingCalendar.timeZone = calendar?.timeZone ?? TimeZone(secondsFromGMT: 0)!
        formatter.calendar = parsingCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = parsingCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawDueAt)
    }

    private func updatedDate(for rawUpdatedAt: String?) -> Date? {
        guard let rawUpdatedAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawUpdatedAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: rawUpdatedAt) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawUpdatedAt)
    }

    private func missedTaskReasons(
        for task: ProjectBoardTask,
        dayInterval: DateInterval,
        staleCutoff: Date
    ) -> [MissedTaskReviewReason] {
        var reasons: [MissedTaskReviewReason] = []
        let taskDueDate = dueDate(for: task.dueAt)
        if taskDueDate.map({ $0 < dayInterval.start }) == true {
            reasons.append(.overdue)
        } else if let taskDueDate, taskDueDate >= dayInterval.start && taskDueDate < dayInterval.end {
            reasons.append(.dueToday)
        }
        if task.status == .blocked {
            reasons.append(.blocked)
        }
        if task.dueAt == nil {
            reasons.append(.unscheduled)
        }
        if updatedDate(for: task.updatedAt).map({ $0 < staleCutoff }) == true {
            reasons.append(.stale)
        }
        return reasons
    }

    private func missedTaskReviewState(
        taskID: Int64,
        referenceDate: Date,
        calendar: Calendar,
        didFail: inout Bool
    ) -> (lastReviewedAt: Date?, isNewlyMissed: Bool) {
        do {
            let lastReviewedAt = try missedTaskReviewStateStore.lastReviewedAt(taskID: taskID)
            return (
                lastReviewedAt,
                lastReviewedAt.map { !calendar.isDate($0, inSameDayAs: referenceDate) } ?? true
            )
        } catch {
            // Review state failures use a conservative fallback so a corrupted
            // local store cannot re-queue tasks the user already acknowledged.
            didFail = true
            return (nil, false)
        }
    }

    private func isImmediateMissedTask(_ item: MissedTaskReviewItem) -> Bool {
        item.reasons.contains(.overdue)
            || item.reasons.contains(.blocked)
            || item.reasons.contains(.unscheduled)
            || item.reasons.contains(.stale)
    }

    private func sortMissedTaskReviewItems(_ lhs: MissedTaskReviewItem, _ rhs: MissedTaskReviewItem) -> Bool {
        let lhsRank = missedTaskQueueRank(lhs)
        let rhsRank = missedTaskQueueRank(rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }
        if lhs.task.priority.sortRank != rhs.task.priority.sortRank {
            return lhs.task.priority.sortRank < rhs.task.priority.sortRank
        }
        let lhsDueDate = dueDate(for: lhs.task.dueAt) ?? .distantFuture
        let rhsDueDate = dueDate(for: rhs.task.dueAt) ?? .distantFuture
        if lhsDueDate != rhsDueDate {
            return lhsDueDate < rhsDueDate
        }
        return lhs.task.id > rhs.task.id
    }

    private func missedTaskQueueRank(_ item: MissedTaskReviewItem) -> Int {
        if item.reasons.contains(.overdue) {
            return 0
        }
        if item.reasons.contains(.blocked) {
            return 1
        }
        if item.reasons.contains(.stale) {
            return 2
        }
        if item.reasons.contains(.unscheduled) {
            return 3
        }
        return 4
    }

    private func completedDate(for task: ProjectBoardTask) -> Date? {
        guard let rawCompletedAt = task.completedAt else {
            return nil
        }

        if let date = ISO8601DateFormatter().date(from: rawCompletedAt) {
            return date
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: rawCompletedAt) {
            return date
        }
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: rawCompletedAt)
    }

    private static func doneAnalyticsHeatmapBuckets(
        from completedCountsByDayStart: [Date: Int],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [DoneAnalyticsDayBucket] {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start,
              let firstDay = calendar.date(byAdding: .day, value: -(doneAnalyticsHeatmapWindowDays - 1), to: referenceDayStart) else {
            return []
        }

        return (0..<doneAnalyticsHeatmapWindowDays).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            return DoneAnalyticsDayBucket(
                dayKey: doneAnalyticsDayKey(for: day, calendar: calendar),
                completedCount: completedCountsByDayStart[day, default: 0]
            )
        }
    }

    private static func doneAnalyticsBestWeekdaySummary(
        from completedDates: [Date],
        calendar: Calendar
    ) -> DoneAnalyticsBestWeekdaySummary {
        let counts = completedDates.reduce(into: [Int: Int]()) { partialResult, date in
            partialResult[calendar.component(.weekday, from: date), default: 0] += 1
        }
        guard let bestWeekday = counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return .empty
        }

        return DoneAnalyticsBestWeekdaySummary(weekday: bestWeekday.key, completedCount: bestWeekday.value)
    }

    private static func doneAnalyticsBestHourSummary(
        from completedDates: [Date],
        calendar: Calendar
    ) -> DoneAnalyticsBestHourSummary {
        let counts = completedDates.reduce(into: [Int: Int]()) { partialResult, date in
            partialResult[calendar.component(.hour, from: date), default: 0] += 1
        }
        guard let bestHour = counts.max(by: { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }) else {
            return .empty
        }

        return DoneAnalyticsBestHourSummary(
            hour: bestHour.key,
            timeOfDay: doneAnalyticsTimeOfDay(for: bestHour.key),
            completedCount: bestHour.value
        )
    }

    private static func doneAnalyticsDayKey(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func doneAnalyticsTimeOfDay(for hour: Int) -> DoneAnalyticsTimeOfDay {
        switch hour {
        case 5..<12:
            return .morning
        case 12..<17:
            return .afternoon
        case 17..<21:
            return .evening
        default:
            return .night
        }
    }

    private static func doneFocusHours(tasks: [ProjectBoardTask]) -> Double {
        // Approximate focus hours: 1.5h per completed task as a local heuristic
        // until actual focus session duration tracking is available.
        Double(tasks.count) * 1.5
    }

    private static func doneOnTimeRate(tasks: [ProjectBoardTask], calendar: Calendar) -> Double? {
        let tasksWithDue = tasks.filter { $0.dueAt != nil && $0.completedAt != nil }
        guard !tasksWithDue.isEmpty else { return nil }
        let onTime = tasksWithDue.filter { task in
            guard let dueAt = task.dueAt,
                  let dueParsed = SuisuiTimestampDisplay.parse(dueAt),
                  let completedAt = task.completedAt,
                  let completedDate = SuisuiTimestampDisplay.parse(completedAt)?.date else {
                return false
            }
            let dueDeadline: Date
            if dueParsed.includesTime {
                dueDeadline = dueParsed.date
            } else {
                dueDeadline = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: dueParsed.date)) ?? dueParsed.date
            }
            return completedDate < dueDeadline
        }
        return Double(onTime.count) / Double(tasksWithDue.count)
    }

    private static func doneWeeklyTrendBuckets(
        from completedCountsByDayStart: [Date: Int],
        on referenceDate: Date,
        calendar: Calendar
    ) -> [DoneAnalyticsWeekBucket] {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start else {
            return []
        }
        return (0..<4).reversed().compactMap { weekOffset -> DoneAnalyticsWeekBucket? in
            guard let weekEnd = calendar.date(byAdding: .day, value: -(weekOffset * 7), to: referenceDayStart),
                  let weekStart = calendar.date(byAdding: .day, value: -6, to: weekEnd) else {
                return nil
            }
            let count = (0..<7).reduce(0) { total, dayOffset in
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                    return total
                }
                return total + completedCountsByDayStart[day, default: 0]
            }
            let weekNumber = 4 - weekOffset
            return DoneAnalyticsWeekBucket(
                weekLabel: "\(weekNumber)\(String(localized: "week suffix"))",
                completedCount: count
            )
        }
    }

    private static func doneStreakDays(
        from completedDayStarts: Set<Date>,
        on referenceDate: Date,
        calendar: Calendar
    ) -> Int {
        guard let referenceDayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start else {
            return 0
        }

        var streak = 0
        var cursor = referenceDayStart
        while completedDayStarts.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }

    private func projectPortfolioSummary(
        for project: ProjectBoardProject,
        on referenceDate: Date,
        calendar: Calendar
    ) -> ProjectPortfolioSummary {
        let tasks = project.tasks
        let openTasks = tasks.filter { $0.status != .done }
        let doneTaskCount = tasks.count - openTasks.count
        let blockedTaskCount = openTasks.filter { $0.status == .blocked }.count
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let overdueTasks = openTasks.filter { task in
            dueDate(for: task.dueAt).map { $0 < dayStart } == true
        }
        let nextDueTask = openTasks
            .filter { dueDate(for: $0.dueAt) != nil }
            .sorted { lhs, rhs in
                let lhsDate = dueDate(for: lhs.dueAt) ?? .distantFuture
                let rhsDate = dueDate(for: rhs.dueAt) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.id > rhs.id
                }
                return lhsDate < rhsDate
            }
            .first
        let nextActionTask = openTasks
            .sorted { lhs, rhs in
                if lhs.status == .blocked && rhs.status != .blocked {
                    return true
                }
                if lhs.status != .blocked && rhs.status == .blocked {
                    return false
                }
                let lhsDate = dueDate(for: lhs.dueAt) ?? .distantFuture
                let rhsDate = dueDate(for: rhs.dueAt) ?? .distantFuture
                if lhsDate == rhsDate {
                    return lhs.id > rhs.id
                }
                return lhsDate < rhsDate
            }
            .first
        let progress = tasks.isEmpty ? 0 : Double(doneTaskCount) / Double(tasks.count)
        let health = projectPortfolioHealth(
            project: project,
            openTaskCount: openTasks.count,
            blockedTaskCount: blockedTaskCount,
            overdueTaskCount: overdueTasks.count,
            progress: progress
        )

        return ProjectPortfolioSummary(
            projectID: project.id,
            title: project.title,
            status: project.status,
            progress: progress,
            openTaskCount: openTasks.count,
            doneTaskCount: doneTaskCount,
            blockedTaskCount: blockedTaskCount,
            overdueTaskCount: overdueTasks.count,
            nextDueAt: nextDueTask?.dueAt,
            recentTaskID: tasks.map(\.id).max(),
            nextActionTitle: nextActionTask?.title ?? "No open tasks",
            health: health,
            riskReason: projectPortfolioRiskReason(
                health: health,
                blockedTaskCount: blockedTaskCount,
                overdueTaskCount: overdueTasks.count,
                progress: progress
            ),
            // The portfolio view must be explainable and work offline; keep this
            // deterministic instead of routing health through an LLM.
            localHealthRuleDescription: "Local Health prioritizes blocked tasks, then overdue work, then open task progress."
        )
    }

    private func projectPortfolioHealth(
        project: ProjectBoardProject,
        openTaskCount: Int,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double
    ) -> ProjectPortfolioHealth {
        if project.isCompleted || (openTaskCount == 0 && progress > 0) {
            return .completed
        }
        if blockedTaskCount > 0 || overdueTaskCount > 0 {
            return .atRisk
        }
        if progress < 0.25 && openTaskCount > 0 {
            return .attention
        }
        return .onTrack
    }

    private func projectPortfolioRiskReason(
        health: ProjectPortfolioHealth,
        blockedTaskCount: Int,
        overdueTaskCount: Int,
        progress: Double
    ) -> String {
        var reasons: [String] = []
        if blockedTaskCount > 0 {
            reasons.append("\(blockedTaskCount) blocked")
        }
        if overdueTaskCount > 0 {
            reasons.append("\(overdueTaskCount) overdue")
        }
        if !reasons.isEmpty {
            return reasons.joined(separator: ", ")
        }
        switch health {
        case .completed:
            return "All tracked tasks are done."
        case .attention:
            return "Progress is below 25% with open work."
        case .onTrack:
            return "No blocked or overdue open tasks."
        case .atRisk:
            return "Local risk rule detected schedule pressure."
        }
    }

    private func isInboxProject(_ project: ProjectBoardProject) -> Bool {
        project.title.caseInsensitiveCompare("Inbox") == .orderedSame
    }

    private func recommendedTodayTask(
        from tasks: [ProjectBoardTask],
        on referenceDate: Date,
        calendar: Calendar
    ) -> ProjectBoardTask? {
        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let overdueTasks = tasks.filter { task in
            dueDate(for: task.dueAt, calendar: calendar).map { $0 < dayStart } == true
        }
        if let highPriorityOverdue = overdueTasks.first(where: { $0.priority == .high }) {
            return highPriorityOverdue
        }
        if let overdueTask = overdueTasks.first {
            return overdueTask
        }
        if let highPriorityTask = tasks.first(where: { $0.priority == .high }) {
            return highPriorityTask
        }
        return tasks.first
    }

    private func recommendationReason(
        for task: ProjectBoardTask?,
        on referenceDate: Date,
        calendar: Calendar
    ) -> String {
        guard let task else {
            return "No due work is scheduled for today."
        }

        let dayStart = calendar.dateInterval(of: .day, for: referenceDate)?.start ?? referenceDate
        let isOverdue = dueDate(for: task.dueAt, calendar: calendar).map { $0 < dayStart } == true
        if isOverdue && task.priority == .high {
            return "Overdue high-priority work should be cleared first."
        }
        if isOverdue {
            return "Overdue work should be cleared before new tasks."
        }
        if task.priority == .high {
            return "High-priority work is the best first task."
        }
        return "Earliest due task keeps today on track."
    }

    private func todayAssistantRailContext(
        source: TodayAssistantRailSource,
        task: ProjectBoardTask,
        plan: TodayWorkflowPlan,
        referenceDate: Date,
        calendar: Calendar,
        nextActionTitle: String,
        nextActionReason: String
    ) -> TodayAssistantRailContext {
        TodayAssistantRailContext(
            source: source,
            task: task,
            projectTitle: projectTitle(for: task),
            nextActionTitle: nextActionTitle,
            nextActionReason: nextActionReason,
            nextBlockLabel: plan.timeBlocks.first { $0.task.id == task.id }?.label,
            notes: task.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "No notes yet.")
                : task.detail,
            // The rail is read-only: it derives progress from the local board snapshot and
            // reminder safety from Assistant Queue, so opening Today never mutates external apps.
            subtaskSummary: todayTaskProgressSummary(plan: plan, referenceDate: referenceDate, calendar: calendar),
            reminderSummary: todayReminderDraftSummary(for: task, referenceDate: referenceDate, calendar: calendar)
        )
    }

    private func todayTaskProgressSummary(
        plan: TodayWorkflowPlan,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        let openCount = plan.tasks.filter { $0.status != .done }.count
        let completedCount = completedTodayTaskCount(referenceDate: referenceDate, calendar: calendar)

        switch (openCount, completedCount) {
        case (0, 0):
            return String(localized: "No open Today tasks.")
        case (let open, 0):
            let format = open == 1
                ? String(localized: "%d open Today task.")
                : String(localized: "%d open Today tasks.")
            return String(format: format, open)
        case (0, let completed):
            let format = completed == 1
                ? String(localized: "%d task done today.")
                : String(localized: "%d tasks done today.")
            return String(format: format, completed)
        case (let open, let completed):
            let format = open == 1
                ? String(localized: "%d open Today task, %d done today.")
                : String(localized: "%d open Today tasks, %d done today.")
            return String(format: format, open, completed)
        }
    }

    private func completedTodayTaskCount(referenceDate: Date, calendar: Calendar) -> Int {
        guard let dayInterval = calendar.dateInterval(of: .day, for: referenceDate) else {
            return 0
        }

        return snapshot.projects
            .filter { !$0.isArchived }
            .flatMap(\.tasks)
            .filter { task in
                guard task.status == .done else {
                    return false
                }
                guard let completedDate = completedDate(for: task) else {
                    return false
                }
                return completedDate >= dayInterval.start && completedDate < dayInterval.end
            }
            .count
    }

    private func todayReminderDraftSummary(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar
    ) -> String {
        guard let state = todayReminderDraftState(for: task, referenceDate: referenceDate, calendar: calendar) else {
            return String(localized: "No Today reminder draft queued.")
        }

        switch state {
        case .captured, .interpreted, .drafted, .waitingReview:
            return String(localized: "Reminder draft is waiting for approval.")
        case .approved, .running:
            return String(localized: "Reminder draft is approved.")
        case .blocked:
            return String(localized: "Reminder draft needs attention.")
        case .failed:
            return String(localized: "Reminder draft failed and needs review.")
        case .deferred:
            return String(localized: "Reminder draft is deferred.")
        case .done:
            return String(localized: "Reminder draft was completed.")
        case .rejected:
            return String(localized: "Reminder draft was rejected.")
        }
    }

    private func todayReminderDraftState(
        for task: ProjectBoardTask,
        referenceDate: Date,
        calendar: Calendar
    ) -> AssistantQueueState? {
        let planID = Self.reminderPlanID(
            for: task,
            referenceDate: referenceDate,
            calendar: calendar,
            prefix: "today-reminder"
        )
        let itemID = "action-plan:\(planID)"

        // Match the exact current-day/content queue item. The visible queue snapshot
        // is filter-limited, so completed/deferred/rejected drafts may not be present.
        if let assistantQueueStore {
            do {
                return try assistantQueueStore.get(id: itemID).state
            } catch AssistantQueueStoreError.notFound {
                return nil
            } catch {
                return assistantQueueSnapshot.rows.first { $0.id == itemID }?.state
            }
        }

        return assistantQueueSnapshot.rows.first { $0.id == itemID }?.state
    }

    private func prioritizedTodayTimeBlocks(
        plan: TodayWorkflowPlan,
        taskID: Int64?,
        referenceDate: Date,
        calendar: Calendar
    ) -> [TodayTimeBlock] {
        guard let taskID,
              let task = plan.tasks.first(where: { $0.id == taskID }) else {
            return plan.timeBlocks
        }

        // The rail action is an explicit user choice, so the draft must include
        // that task even when the normal recommendation order would place it later.
        return timeBlocks(
            for: orderedTimeBlockTasks(plan.tasks, recommendedTask: task),
            startingAt: referenceDate,
            calendar: calendar
        )
    }

    private func orderedTimeBlockTasks(
        _ tasks: [ProjectBoardTask],
        recommendedTask: ProjectBoardTask?
    ) -> [ProjectBoardTask] {
        guard let recommendedTask else {
            return tasks
        }

        return [recommendedTask] + tasks.filter { $0.id != recommendedTask.id }
    }

    private func timeBlocks(
        for tasks: [ProjectBoardTask],
        startingAt referenceDate: Date,
        calendar: Calendar
    ) -> [TodayTimeBlock] {
        let firstBlockStart = roundedTimeBlockStart(from: referenceDate, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.timeZone = calendar.timeZone

        return tasks.prefix(4).enumerated().compactMap { offset, task in
            guard let start = calendar.date(byAdding: .minute, value: offset * 30, to: firstBlockStart),
                  let end = calendar.date(byAdding: .minute, value: 30, to: start) else {
                return nil
            }
            return TodayTimeBlock(
                label: "\(formatter.string(from: start))-\(formatter.string(from: end))",
                task: task,
                startAt: isoFormatter.string(from: start),
                endAt: isoFormatter.string(from: end)
            )
        }
    }

    private func scheduleDraftTimeBlock(
        for task: ProjectBoardTask,
        existingBlocks: [TodayTimeBlock],
        referenceDate: Date,
        calendar: Calendar
    ) -> TodayTimeBlock? {
        let isoFormatter = ISO8601DateFormatter()
        let nextStart = existingBlocks.last?.endAt.flatMap { isoFormatter.date(from: $0) }
            ?? calendar.date(
                byAdding: .minute,
                value: existingBlocks.count * 30,
                to: roundedTimeBlockStart(from: referenceDate, calendar: calendar)
            )
            ?? referenceDate
        return timeBlocks(
            for: [task],
            startingAt: nextStart,
            calendar: calendar
        ).first
    }

    private func roundedTimeBlockStart(from referenceDate: Date, calendar: Calendar) -> Date {
        DailyPlanningReviewRefreshSchedule.roundedTimeBlockStart(
            from: referenceDate,
            calendar: calendar
        )
    }
}

private enum InboxClassificationUndo {
    case restoreMutation(mutation: InboxTriageMutation, regenerated: ProjectBoardTask?)
    case restoreTask(originalTask: ProjectBoardTask)
    case restoreTaskAndDeleteProject(originalTask: ProjectBoardTask, createdProjectID: Int64)
}

private extension ProjectPortfolioHealth {
    var sortRank: Int {
        switch self {
        case .atRisk:
            0
        case .attention:
            1
        case .onTrack:
            2
        case .completed:
            3
        }
    }
}

private extension ProjectTaskPriority {
    var sortRank: Int {
        switch self {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
    }
}

private extension ProjectBoardTask {
    var classificationDraft: ProjectBoardTaskDraft {
        ProjectBoardTaskDraft(
            projectID: projectID,
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueAt: dueAt,
            recurrence: recurrence
        )
    }
}
