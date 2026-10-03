import Combine
import CryptoKit
import Foundation
import os

let projectBoardRuntimeDiagnosticLogger = Logger(subsystem: "dev.suisui.app", category: "runtime")

enum GoogleCalendarReadinessRefreshResult: Sendable {
    case success(GoogleCalendarRuntimeSyncStatus)
    case failure(String)
}

@MainActor
public final class ProjectBoardViewModel: ObservableObject {
    enum ProjectBoardFailureRetryAction {
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

    @Published public internal(set) var snapshot: ProjectBoardSnapshot
    @Published public internal(set) var derivedReadModels: ProjectBoardDerivedReadModels
    @Published public var selectedProjectID: Int64?
    @Published public var selectedTaskID: Int64? {
        didSet {
            guard oldValue != selectedTaskID else { return }
            refreshTodayDerivedReadModelForSelectionChange()
        }
    }
    @Published public internal(set) var showsArchivedProjects: Bool
    @Published public internal(set) var showsCompletedWorkflowTasks: Bool
    public var errorMessage: String? { failure?.message }
    // A successful mutation reload must not clear a provider failure that was
    // raised by that same reload. Keep the result separate from `failure`,
    // which may intentionally represent an earlier recoverable operation.
    private var didLastLoadFail = false
    @Published public private(set) var failure: ProjectBoardFailure?
    @Published public internal(set) var integrationStatusMessage: String?
    @Published public internal(set) var inboxClassificationFeedback: InboxClassificationFeedback?
    @Published public internal(set) var inboxTriageErrorMessage: String?
    // Board-operation undo is deliberately separate from the Inbox
    // classification undo below: classification keeps its guided single-step
    // flow while this stack owns general task mutations (complete, status
    // move, edit, delete) for ⌘Z and the Edit-menu command.
    @Published public internal(set) var boardOperationUndo: BoardOperationUndoStack
    @Published public internal(set) var boardUndoFeedback: String?
    @Published public internal(set) var inboxTriageFilter: InboxTriageFilter
    @Published public internal(set) var todayCommandFeedback: String?
    @Published public internal(set) var todayFocusTaskID: Int64? {
        didSet {
            guard oldValue != todayFocusTaskID else { return }
            refreshTodayDerivedReadModelForSelectionChange()
        }
    }
    @Published public internal(set) var todayScheduleDraft: TodayScheduleDraft?
    @Published public internal(set) var dailyPlanningReview: DailyPlanningReview?
    @Published public internal(set) var scheduleDraft: ScheduleDraft?
    @Published public internal(set) var scheduleApplyResult: ScheduleApplyResult?
    @Published public internal(set) var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus
    @Published public internal(set) var externalScheduleEvents: [ExternalScheduleEvent]
    @Published public internal(set) var externalScheduleEventLoadState: ExternalScheduleEventLoadState
    @Published public internal(set) var projectAssistantAnswer: ProjectAssistantAnswer?
    @Published public internal(set) var projectAssistantReviewDraft: ProjectAssistantReviewDraft?
    @Published public internal(set) var developmentAutomationReviewPlan: ActionPlan?
    @Published public internal(set) var taskAutomationReviewDecision: TaskAutoExecutionDecision?
    @Published public internal(set) var taskAutomationDocumentDeliverableReviews: [TaskAutomationDocumentDeliverableReview]
    @Published public internal(set) var lastApprovedAutomationExecutionReceipt: ApprovedAutomationExecutionReceipt?
    @Published public internal(set) var approvedAutomationExecutionReceipts: [ApprovedAutomationExecutionReceipt]
    @Published public internal(set) var assistantQueueSnapshot: AssistantQueueSnapshot
    @Published public internal(set) var assistantQueueViewFilter: AssistantQueueViewFilter
    @Published public internal(set) var assistantQueueSort: AssistantQueueSort
    @Published public internal(set) var assistantQueueSelectedItemIDs: Set<String>
    @Published public internal(set) var isApprovingAllRescheduleSuggestions = false
    @Published public internal(set) var executionReceiptHistorySnapshot: ExecutionReceiptHistorySnapshot
    @Published public internal(set) var executionReceiptHistorySearchText: String
    @Published public internal(set) var executionReceiptHistoryStatusFilter: ExecutionReceiptStatus?
    @Published public internal(set) var executionReceiptHistoryReferenceKindFilter: ExecutionReceiptReferenceKind?
    @Published public internal(set) var executionReceiptHistoryExportData: Data?
    @Published public internal(set) var executionReceiptHistoryExportMessage: String?
    @Published public internal(set) var executionUsageMeterSnapshot: ExecutionUsageMeterSnapshot

    let store: any ProjectBoardStore
    let inboxCaptureStore: (any InboxCaptureStore)?
    let assistantQueueStore: (any AssistantQueueStore)?
    var assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator?
    private let assistantQueueExecutionCoordinatorFactory: (() -> AssistantQueueExecutionCoordinator?)?
    let executionReceiptStore: (any ExecutionReceiptStore)?
    let publicAlphaMeasurement: PublicAlphaRuntimeMeasurement?
    let missedTaskReviewStateStore: any MissedTaskReviewStateStore
    let missedTaskFollowUpNotificationClient: (any NotificationClient)?
    let externalTaskLinkStore: (any ExternalTaskLinkStore)?
    let scheduleCalendarClient: (any CalendarClient)?
    let externalScheduleEventSource: (any ExternalScheduleEventSource)?
    var googleCalendarSync: (any GoogleCalendarRuntimeSyncing)?
    private let googleCalendarSyncFactory: (() -> (any GoogleCalendarRuntimeSyncing)?)?
    public let changeSourceID: UUID
    let onChange: () -> Void
    var lastInboxClassificationUndo: InboxClassificationUndo?
    var boardUndoFeedbackClearTask: Task<Void, Never>?
    // Inbox rows render often during filtering and selection changes, so capture
    // metadata is cached at board load time instead of hitting SQLite from SwiftUI body rendering.
    var inboxCaptureRecordsByTaskID: [Int64: [InboxCaptureRecord]]
    // Triage disposition is authoritative for Inbox filtering. Keeping it beside
    // the capture cache lets row rendering distinguish an explicitly accepted
    // Task from a raw, still-unprocessed capture without issuing store reads.
    var inboxTriageRecordsByTaskID: [Int64: InboxTriageRecord]
    // Review Later visibility is a derived time boundary. Tests and the minute
    // UI refresh inject this value so filtering stays deterministic and pure.
    var inboxVisibilityReferenceDate: Date?
    // Inspector receipt rows are cached as redacted read-model snapshots so
    // SwiftUI rendering never performs file I/O or holds raw receipt details.
    var executionReceiptHistorySnapshotsByTaskID: [Int64: ExecutionReceiptHistorySnapshot]
    var executionReceiptHistorySnapshotsByProjectID: [Int64: ExecutionReceiptHistorySnapshot]
    // Done/audit receipts can live in a large file-backed store. Project Board
    // startup defers those global reads until the Done workflow is actually
    // visible while still letting receipt writes refresh an already-open audit view.
    var executionReceiptAuditSnapshotsLoaded: Bool
    // Selection changes only affect the Today rail context. Keeping the last
    // build context lets us refresh that slice without recomputing sidebar,
    // schedule, done, or portfolio read models for every row selection.
    let readModelNow: () -> Date
    let readModelCalendarProvider: () -> Calendar
    var derivedReadModelReferenceDate: Date?
    var derivedReadModelCalendar: Calendar
    // The preview is a derived value, not authoritative review state. The key
    // prevents SwiftUI re-evaluation and selection-only updates from rebuilding
    // the same review while still forcing a new value after board data changes.
    var dailyPlanningReviewPreviewCache: DailyPlanningReviewPreviewCache
    // Keep this revision stable when an external change notification causes a
    // second load of the same snapshot; otherwise one mutation invalidates the
    // preview twice before SwiftUI has a chance to consume the first result.
    var todaySnapshotSourceRevision: UInt64
    // Keep this counter beside the cache so only real builder executions are
    // counted; SwiftUI body re-evaluation must not create diagnostic work.
    var dailyPlanningReviewPreviewBuildCount: Int
    var taskAutomationSessionHistory: TaskAutoExecutionHistory
    private var hasLoadedBoardSnapshot: Bool
    private var failureRetryAction: ProjectBoardFailureRetryAction?
    private var failureTaskID: Int64?
    private let hasPreloadedGoogleCalendarSyncStatus: Bool
    var googleCalendarReadinessRefreshRevision: UInt64
    var externalScheduleEventRefreshRevision: UInt64
    var externalScheduleEventInterval: DateInterval?
    private var googleCalendarReadinessNotificationObservation: AnyCancellable?

    public init(
        store: any ProjectBoardStore,
        inboxCaptureStore: (any InboxCaptureStore)? = nil,
        assistantQueueStore: (any AssistantQueueStore)? = nil,
        assistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator? = nil,
        assistantQueueExecutionCoordinatorFactory: (() -> AssistantQueueExecutionCoordinator?)? = nil,
        executionReceiptStore: (any ExecutionReceiptStore)? = nil,
        publicAlphaMeasurement: PublicAlphaRuntimeMeasurement? = nil,
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
        changeSourceID: UUID = UUID(),
        onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.inboxCaptureStore = inboxCaptureStore
        self.assistantQueueStore = assistantQueueStore
        self.assistantQueueExecutionCoordinator = assistantQueueExecutionCoordinator
        self.assistantQueueExecutionCoordinatorFactory = assistantQueueExecutionCoordinatorFactory
        self.executionReceiptStore = executionReceiptStore
        self.publicAlphaMeasurement = publicAlphaMeasurement
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
        self.changeSourceID = changeSourceID
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
            load(invalidationReason: .storeReload)
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

    func recordFailure(
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
        // Context must exist before the published failure emits. SwiftUI
        // derives banner placement and Retry from these non-published values.
        failureTaskID = taskID
        failureRetryAction = retryAction
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

    /// All operation failures enter the typed, redacted failure state.
    func recordOperationFailure(_ message: String?) {
        guard let message else { clearFailure(); return }
        recordFailure(.saveFailed(message), retryAction: .load)
    }

    func recordProviderFailure(_ message: String) {
        // A successful task write cannot erase an unavailable derived state
        // discovered while rebuilding the read models for that same load.
        didLastLoadFail = true
        recordFailure(.providerFailed(message), retryAction: .load)
    }

    private func clearFailure() {
        failureTaskID = nil
        failureRetryAction = nil
        failure = nil
    }

    func clearErrorAfterSuccessfulLoad() {
        guard !didLastLoadFail else { return }
        recordOperationFailure(nil)
    }

    func beginRecoverableOperation(taskID: Int64? = nil) {
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

    var resolvedAssistantQueueExecutionCoordinator: AssistantQueueExecutionCoordinator? {
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

    var resolvedGoogleCalendarSync: (any GoogleCalendarRuntimeSyncing)? {
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


    @discardableResult
    public func openProjectFromPortfolioCard(projectID: Int64) -> Bool {
        guard snapshot.projects.contains(where: { $0.id == projectID && !$0.isArchived }) else {
            recordOperationFailure("Project is no longer available.")
            return false
        }

        selectedProjectID = projectID
        selectedTaskID = nil
        recordOperationFailure(nil)
        return true
    }

    public func projectTitle(for task: ProjectBoardTask) -> String {
        snapshot.projects.first { $0.id == task.projectID }?.title ?? "Unknown Project"
    }

    public var isEmptyProjectStateVisible: Bool {
        fatalFailure == nil && selectedProject == nil
    }

    /// Skip only a successful originating reload. A change notification also
    /// recovers stale data/read models when the post-write reload failed.
    @discardableResult
    public func reloadAfterChange(from sourceID: UUID?) -> Bool {
        guard sourceID != changeSourceID || didLastLoadFail else { return false }
        load(invalidationReason: didLastLoadFail ? .storeReload : nil)
        return true
    }

    public func load() {
        load(invalidationReason: nil)
    }

    func load(invalidationReason: TodaySnapshotInvalidationReason?) {
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
            let message = LocalWorkspaceFailureMessage.message(for: error)
            if hasLoadedBoardSnapshot {
                recordFailure(.saveFailed(message), retryAction: .load)
            } else {
                recordFailure(.initialLoadFailed(message), retryAction: .load)
            }
        }
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
}

enum InboxClassificationUndo {
    case restoreMutation(mutation: InboxTriageMutation, regenerated: ProjectBoardTask?)
    case restoreTask(originalTask: ProjectBoardTask)
    case restoreTaskAndDeleteProject(originalTask: ProjectBoardTask, createdProjectID: Int64)
}

extension ProjectBoardTask {
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
