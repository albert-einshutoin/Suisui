import SuisuiCore
import Dispatch
import os
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum ProjectBoardWindowMetrics {
    // The primary window must keep one stable content contract across sidebar
    // destinations; otherwise SwiftUI can re-fit the window when Inbox/Today
    // switch between compact and rail-heavy workflow surfaces.
    static let defaultWidth: CGFloat = 1_180
    static let defaultHeight: CGFloat = 760
    static let minWidth: CGFloat = 960
    static let minHeight: CGFloat = 572
}

enum ProjectBoardLayoutMetrics {
    // Project Board keeps these metrics local because the split-view header,
    // Kanban columns, inspector, and inline composer are tuned as one surface.
    // Keeping the numbers named makes UI review catch accidental magic values
    // without forcing a premature app-wide design system abstraction.
    // Sidebar bounds keep every fixed destination label ("Assistant Queue" is
    // the widest at ~105pt for 15 characters of 13pt SF Pro, plus ~24pt icon
    // column, 8pt gap, and a ~16pt count badge ≈ 185pt with row insets)
    // readable without truncation at the 1024pt canonical window width. The
    // native split chrome contributes another 20pt, so the ideal must stay at
    // 200pt to keep the shared header and 300pt inspector inside that viewport.
    static let sidebarColumnMinWidth: CGFloat = 180
    static let sidebarColumnIdealWidth: CGFloat = 200
    // NavigationSplitView otherwise gives the detail column a large implicit
    // minimum. With the compact inspector open, that floor prevents the product
    // from reaching its supported 1024pt compact window width.
    static let detailColumnMinWidth: CGFloat = 440
    static let detailColumnIdealWidth: CGFloat = 700
    static let terminalPanelMinHeight: CGFloat = 220
    static let terminalPanelIdealHeight: CGFloat = 280
    static let terminalPanelMaxHeight: CGFloat = 360
    static let portfolioCardMinHeight: CGFloat = 230
    static let overviewPanelMinHeight: CGFloat = 170
    static let displayModePickerWidth: CGFloat = 252
    // 204pt columns keep two full Kanban columns reachable beside the compact
    // inspector at the 1024pt canonical window width: 2 x (204 + 20 padding)
    // + 12 spacing = 460pt fits the ~466pt board viewport there.
    static let boardColumnWidth: CGFloat = 204
    static let emptyColumnMinHeight: CGFloat = 82
    static let inlinePriorityPickerWidth: CGFloat = 112
    static let taskStatusRailWidth: CGFloat = 4
    static let taskStatusRailHeight: CGFloat = 44
    static let taskMetadataChipMinWidth: CGFloat = 64
    static let taskMetadataChipMinHeight: CGFloat = 24
}

private struct DevelopmentAutomationReviewSheet: Identifiable {
    let id: String
    let viewModel: ReviewSessionViewModel
}

private struct ProjectBoardDestinationPersistenceSuppression: Equatable {
    let destination: ProjectBoardSidebarDestination?
}

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel: ProjectBoardViewModel
    @ObservedObject private var sceneCoordinator: ProjectBoardSceneCoordinator
    private let sceneID: UUID
    private let restoresPrimaryPresentationState: Bool
    private let taskAutomationSettings: () -> TaskAutoExecutionSettings
    private let appSettings: () -> AppSettings
    private let smartListStore: (any SmartListStore)?
    private let commandPaletteContentSearch: CommandPaletteContentSearch?
    private let developmentAutomationReviewSession: (ActionPlan) -> ReviewSessionViewModel
    @AppStorage(ProjectBoardSelectionPersistence.storageKey) private var initialRouteRawValue = ProjectBoardSelectionPersistence.defaultRawValue
    @SceneStorage(ProjectBoardScenePersistence.routeStorageKey) private var currentSceneRouteRawValue = ""
    @SceneStorage("projectBoard.userRequestedInspector") private var userRequestedInspector = false
    @SceneStorage("projectBoard.sidebarHidden") private var storedSidebarHidden = false
    @AppStorage("projectBoard.primary.userRequestedInspector") private var primaryUserRequestedInspector = false
    @AppStorage("projectBoard.primary.sidebarHidden") private var primarySidebarHidden = false
    @State private var displayMode: ProjectBoardDisplayMode = .board
    @State private var selectedDestination: ProjectBoardSidebarDestination? = .today
    @State private var projectBoardWindowWidth: CGFloat = 0
    @State private var allowsCompactInspectorPresentation = false
    @State private var isCompactInspectorSheetPresented = false
    @State private var projectInspectorDevelopmentContext = ProjectInspectorDevelopmentContext()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var toolbarLayoutRefreshToken = 0
    @State private var isTerminalPanelPresented = false
    @State private var isExportingTaskInterop = false
    @State private var isImportingTaskInterop = false
    @State private var isGoogleCalendarSyncApprovalPresented = false
    @State private var developmentAutomationReviewSheet: DevelopmentAutomationReviewSheet?
    @State private var taskInteropExportDocument = TaskInteropFileDocument(data: Data())
    @State private var isCommandPaletteVisible = false
    @State private var selectedSmartListID: String?
    @State private var savedSmartLists: [SmartList] = []
    @State private var isPresentingSmartListEditor = false
    @State private var transientBoardRoute: BoardRoute?
    @State private var catchUpFocusRevision = 0
    @State private var consumedCatchUpFocusRevision = 0
    @State private var activeBoardRouteFocus: BoardRouteFocus?
    @State private var pendingDestinationPersistenceSuppression: ProjectBoardDestinationPersistenceSuppression?
    // Palette content hits reveal their task after the destination switch
    // settles, because applySelectedDestination clears task selection.
    @State private var pendingCommandPaletteRevealTaskID: Int64?

    init(
        viewModel: ProjectBoardViewModel,
        sceneID: UUID,
        restoresPrimaryPresentationState: Bool,
        sceneCoordinator: ProjectBoardSceneCoordinator = .shared,
        taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings = { .default },
        appSettings: @escaping () -> AppSettings = { .default },
        smartListStore: (any SmartListStore)? = AppRuntimeFactory.makeSmartListStoreIfAvailable(),
        commandPaletteContentSearch: CommandPaletteContentSearch? = CommandPaletteContentSearchFactory.makeIfAvailable(),
        developmentAutomationReviewSession: @escaping (ActionPlan) -> ReviewSessionViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _sceneCoordinator = ObservedObject(wrappedValue: sceneCoordinator)
        self.sceneID = sceneID
        self.restoresPrimaryPresentationState = restoresPrimaryPresentationState
        self.taskAutomationSettings = taskAutomationSettings
        self.appSettings = appSettings
        self.smartListStore = smartListStore
        self.commandPaletteContentSearch = commandPaletteContentSearch
        self.developmentAutomationReviewSession = developmentAutomationReviewSession
    }

    var body: some View {
        let sidebarMetrics = viewModel.derivedReadModels.sidebarMetrics
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectBoardSidebarView(
                route: boardRouteBinding,
                counts: ProjectBoardSidebarCounts(
                    today: sidebarMetrics.todayCount,
                    inbox: sidebarMetrics.inboxCount,
                    projects: sidebarMetrics.projectsCount,
                    review: viewModel.assistantQueueSnapshot.needsAttentionCount
                )
            )
            .id(toolbarLayoutRefreshToken)
            .projectBoardSynchronizedColumnBounds()
            .navigationSplitViewColumnWidth(min: ProjectBoardLayoutMetrics.sidebarColumnMinWidth, ideal: ProjectBoardLayoutMetrics.sidebarColumnIdealWidth)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if case .fatal(let message, let canRetry) = viewModel.errorPresentation {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                "Project Board Unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(message)
                            )
                            if canRetry {
                                Button("Retry") {
                                    viewModel.retryCurrentFailure()
                                }
                                .accessibilityIdentifier("project-board-load-retry")
                            }
                        }
                    } else {
                        routedProjectBoardContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if case .inline(let message, _) = viewModel.rootErrorPresentation {
                    Divider()
                    HStack(spacing: 10) {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(SuisuiTone.danger.color)
                            .accessibilityIdentifier("project-board-inline-error")
                        Spacer(minLength: 8)
                        if let actionLabel = viewModel.failureActionLabel {
                            Button(actionLabel, systemImage: "arrow.clockwise") {
                                viewModel.retryCurrentFailure()
                            }
                            .controlSize(.small)
                            .accessibilityIdentifier("project-board-inline-error-retry")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }

                if isTerminalPanelPresented && projectBoardToolbarContext.showsDeveloperTerminal {
                    Divider()
                    EmbeddedTerminalPanel(
                        workingDirectory: terminalWorkingDirectory,
                        isPresented: $isTerminalPanelPresented
                    )
                    .frame(
                        minHeight: ProjectBoardLayoutMetrics.terminalPanelMinHeight,
                        idealHeight: ProjectBoardLayoutMetrics.terminalPanelIdealHeight,
                        maxHeight: ProjectBoardLayoutMetrics.terminalPanelMaxHeight
                    )
                }
            }
            .id(toolbarLayoutRefreshToken)
            .projectBoardSynchronizedColumnBounds()
            .navigationSplitViewColumnWidth(
                min: ProjectBoardLayoutMetrics.detailColumnMinWidth,
                ideal: ProjectBoardLayoutMetrics.detailColumnIdealWidth
            )
        }
        .frame(
            minHeight: ProjectBoardWindowMetrics.minHeight,
            alignment: .topLeading
        )
        .inspector(isPresented: wideInspectorBinding) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        }
        .sheet(isPresented: $isCompactInspectorSheetPresented, onDismiss: {
            // A user-dismissed compact sheet must clear the persisted intent.
            // During a compact-to-wide resize, the width is already wide and
            // the same intent is preserved for the native inspector instead.
            if usesCompactInspectorPresentation {
                dismissInspector()
            }
        }) {
            NavigationStack {
                inspectorContent
                    .frame(minWidth: 360, minHeight: 480)
            }
            .onChange(of: inspectorSelectionContext) { previousSelection, selection in
                if isCompactInspectorSheetPresented,
                   selection == .none || (previousSelection == .task && selection != .task) {
                    // Deleting a selected task otherwise swaps the modal to
                    // its parent project, while deleting a project leaves an
                    // EmptyView. Close either compact flow so the user returns
                    // to the board action they just completed.
                    dismissInspector()
                }
            }
        }
        .navigationTitle("Suisui")
        // The Edit-menu board undo command targets the key Project Board
        // window through this focused scene value; text-field undo keeps the
        // standard responder-chain Undo item.
        .focusedSceneValue(\.projectBoardUndo, ProjectBoardUndoCommandAction(viewModel: viewModel))
        .toolbar {
            ProjectBoardToolbarContent(
                context: projectBoardToolbarContext,
                sidebarToggleHelp: sidebarToggleHelp,
                undoFeedback: viewModel.boardUndoFeedback,
                isInspectorPresented: isInspectorEffectivelyPresented,
                canSyncGoogleCalendar: viewModel.canSyncGoogleCalendar,
                googleCalendarSyncHelp: viewModel.googleCalendarSyncHelp,
                onToggleSidebar: toggleSidebarVisibility,
                onOpenSearch: { isCommandPaletteVisible = true },
                onOpenVoiceCommand: { openWindow(id: "voice-capture") },
                onToggleInspector: toggleInspectorPresentation,
                onExportTasks: beginTaskInteropExport,
                onImportTasks: { isImportingTaskInterop = true },
                onRequestGoogleCalendarSync: { isGoogleCalendarSyncApprovalPresented = true },
                onReviewTaskAutomation: {
                    // Preparing the deterministic review decision does not
                    // consume LLM budget; reveal the selected task inspector
                    // so the toolbar action always lands on reviewable output.
                    let decision = viewModel.prepareTaskAutomationReview(settings: taskAutomationSettings())
                    if decision.status == .readyForReview,
                       let taskID = decision.selectedTasks.first?.id {
                        openTaskInspector(taskID)
                    }
                },
                onToggleTerminal: { isTerminalPanelPresented.toggle() }
            )
        }
        .toolbar(removing: .sidebarToggle)
        .background(
            ProjectBoardToolbarLayoutBridge(
                columnVisibility: columnVisibility,
                onToolbarLayoutChanged: refreshProjectBoardColumnsAfterToolbarDisplayModeChange,
                onWindowWidthChanged: updateProjectBoardWindowWidth
            )
        )
        .task {
            sceneCoordinator.register(sceneID: sceneID)
            restorePrimaryPresentationStateIfNeeded()
            columnVisibility = storedSidebarHidden ? .detailOnly : .all
            LaunchPerformanceSignposts.measureFirstBoardLoadOnce {
                viewModel.load()
            }
            LaunchPerformanceMilestones.record("command-ready")
            viewModel.scheduleMissedTaskDailyFollowUp(settings: appSettings())
            reloadSavedSmartLists()
            restoreSelectedDestinationIfNeeded()
            consumePendingSceneOpenRequests()
            LaunchPerformanceMilestones.record("today-ready")
        }
        .onDisappear {
            sceneCoordinator.unregister(sceneID: sceneID)
        }
        .modifier(ProjectBoardTodayRefreshLifecycleModifier {
            viewModel.refreshDerivedReadModels()
        })
        .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange)) { _ in
            viewModel.load()
            viewModel.scheduleMissedTaskDailyFollowUp(settings: appSettings())
            restoreSelectedDestinationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiVoiceDailyPlanningReviewRequested)) { notification in
            handleVoiceDailyPlanningReviewRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiVoiceInboxTriageRequested)) { notification in
            handleVoiceInboxTriageRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiAssistantQueueRequested)) { notification in
            handleAssistantQueueOpenRequest(notification)
        }
        .onChange(of: sceneCoordinator.deliveryRevision) { _, _ in
            consumePendingSceneOpenRequests()
        }
        .onChange(of: restoresPrimaryPresentationState) { _, restoresPrimary in
            if restoresPrimary {
                restorePrimaryPresentationStateIfNeeded()
                columnVisibility = storedSidebarHidden ? .detailOnly : .all
            }
        }
        .onChange(of: selectedDestination) { _, destination in
            allowsCompactInspectorPresentation = false
            if destination != nil {
                selectedSmartListID = nil
            }
            if let suppression = pendingDestinationPersistenceSuppression,
               suppression.destination == destination {
                pendingDestinationPersistenceSuppression = nil
            } else {
                // A stale suppression can remain when programmatic A -> B -> A
                // changes coalesce without onChange. A later user destination
                // differs, clears it here, and persists normally.
                pendingDestinationPersistenceSuppression = nil
                if let destination,
                   ProjectBoardSelectionPersistence.environmentOverrideRawValue != nil {
                    transientBoardRoute = validatedRoute(typedRoute(for: destination))
                } else {
                    persistSelectedDestination(destination)
                }
            }
            applySelectedDestination(destination)
            // Destination changes intentionally clear normal user selection; the
            // env-only override is reapplied so deterministic release evidence
            // can open Inbox with a seeded capture selected.
            applySelectedTaskOverrideIfNeeded()
            applyPendingCommandPaletteRevealIfNeeded()
        }
        .fileExporter(
            isPresented: $isExportingTaskInterop,
            document: taskInteropExportDocument,
            contentType: .json,
            defaultFilename: taskInteropDefaultExportFilename
        ) { result in
            switch result {
            case .success:
                viewModel.recordTaskInteropExportCompleted()
            case .failure(let error):
                viewModel.recordTaskInteropFileFailure(error)
            }
        }
        .fileImporter(
            isPresented: $isImportingTaskInterop,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleTaskInteropImport(result)
        }
        .confirmationDialog(
            "Sync due tasks to Google Calendar?",
            isPresented: $isGoogleCalendarSyncApprovalPresented,
            titleVisibility: .visible
        ) {
            Button("Approve Google Calendar Sync") {
                approveGoogleCalendarSync()
            }
            .accessibilityIdentifier("project-board-google-calendar-sync-approval-confirm")

            Button("Cancel", role: .cancel) {
                isGoogleCalendarSyncApprovalPresented = false
            }
            .accessibilityIdentifier("project-board-google-calendar-sync-approval-cancel")
        } message: {
            Text("Suisui will create Google Calendar events for due, unfinished tasks. Existing linked tasks are skipped.")
        }
        .sheet(item: $developmentAutomationReviewSheet) { sheet in
            ActionReviewPanel(viewModel: sheet.viewModel) {
                viewModel.clearDevelopmentAutomationReviewPlan()
                developmentAutomationReviewSheet = nil
            }
            .padding(16)
            .frame(minWidth: 520, minHeight: 360)
            .accessibilityIdentifier("project-development-automation-review-sheet")
        }
        .sheet(isPresented: $isPresentingSmartListEditor) {
            SmartListEditorSheet(
                onSave: { smartList in
                    saveSmartList(smartList)
                    isPresentingSmartListEditor = false
                },
                onCancel: { isPresentingSmartListEditor = false }
            )
        }
        .background(
            ProjectBoardKeyboardShortcutBridge(
                openCommandPalette: { isCommandPaletteVisible = true },
                selectDestination: {
                    boardRouteBinding.wrappedValue = .primary($0)
                }
            )
        )
        .overlay {
            ZStack {
                if isCommandPaletteVisible {
                    CommandPaletteView(
                        projects: commandPaletteProjects,
                        smartLists: commandPaletteSmartLists,
                        contentSearch: commandPaletteContentSearch,
                        onExecute: executeCommandPaletteAction,
                        onDismiss: { isCommandPaletteVisible = false }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            // Brief fade/scale on palette open and close; Reduce Motion makes
            // the palette appear and disappear instantly instead.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isCommandPaletteVisible)
        }
    }

    private var commandPaletteProjects: [(id: Int64, title: String, isArchived: Bool)] {
        sidebarProjects.map { project in
            (id: project.id, title: project.title, isArchived: project.isArchived)
        }
    }

    private var commandPaletteSmartLists: [(id: String, name: String)] {
        allSmartLists.map { smartList in
            (id: smartList.id, name: smartList.isPreset ? localizedDisplay(smartList.name) : smartList.name)
        }
    }

    /// Typed scene state is the rendering source of truth. The legacy
    /// destination remains only as a compatibility facade for commands and
    /// feature bridges that have not migrated to `BoardRoute` yet.
    private var currentBoardRouteResolution: ProjectBoardRouteResolution {
        if let transientBoardRoute {
            return ProjectBoardRouteResolution(
                route: validatedRoute(transientBoardRoute),
                focus: nil
            )
        }
        let availableProjectIDs = Set(viewModel.snapshot.projects.map(\.id))
        if let override = ProjectBoardSelectionPersistence.environmentOverrideRawValue {
            let resolution = ProjectBoardRouteCodec.resolution(
                from: override,
                availableProjectIDs: availableProjectIDs
            )
            return ProjectBoardRouteResolution(
                route: validatedRoute(resolution.route),
                focus: resolution.focus
            )
        }
        if !currentSceneRouteRawValue.isEmpty {
            let resolution = ProjectBoardRouteCodec.resolution(
                from: currentSceneRouteRawValue,
                availableProjectIDs: availableProjectIDs
            )
            return ProjectBoardRouteResolution(
                route: validatedRoute(resolution.route),
                focus: resolution.focus
            )
        }
        let resolution = ProjectBoardScenePersistence.restoredResolution(
                sceneRawValue: currentSceneRouteRawValue,
                initialRawValue: initialRouteRawValue,
                availableProjectIDs: availableProjectIDs
            )
        return ProjectBoardRouteResolution(
            route: validatedRoute(resolution.route),
            focus: resolution.focus
        )
    }

    private var currentBoardRoute: BoardRoute {
        currentBoardRouteResolution.route
    }

    private var boardRouteBinding: Binding<BoardRoute> {
        Binding(
            get: { currentBoardRoute },
            set: { navigateWithinScene(to: $0) }
        )
    }

    private func navigateWithinScene(
        to route: BoardRoute,
        focus: BoardRouteFocus? = nil,
        updateInitialRoute: Bool = true
    ) {
        let route = validatedRoute(route)
        if ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil {
            persistRoute(route, updateInitialRoute: updateInitialRoute)
        } else {
            // Deterministic evidence overrides must remain process-local: they
            // may still exercise navigation, but never rewrite SceneStorage or
            // the next-window AppStorage preference.
            transientBoardRoute = route
        }
        if let focus {
            applyRouteFocus(focus)
        } else {
            cancelRouteFocus()
        }
        applyRouteToLegacyUI(route)
    }

    @ViewBuilder
    private var routedProjectBoardContent: some View {
        switch currentBoardRoute {
        case .primary(.today):
            TodayWorkflowView(
                viewModel: viewModel,
                selectTodayTask: selectTodayTask,
                openInspectorForTodayRailTask: openInspectorForTodayRailTask,
                playDailyPlanningReadout: playDailyPlanningReadoutFromSettings,
                initiallyExpandsCatchUp: activeBoardRouteFocus == .catchUp
                    || currentBoardRouteResolution.focus == .catchUp,
                catchUpFocusRevision: catchUpFocusRevision > consumedCatchUpFocusRevision
                    ? catchUpFocusRevision
                    : nil,
                onCatchUpFocusConsumed: { revision in
                    guard activeBoardRouteFocus == .catchUp,
                          catchUpFocusRevision == revision else {
                        return false
                    }
                    consumedCatchUpFocusRevision = revision
                    activeBoardRouteFocus = nil
                    return true
                }
            )
        case .primary(.inbox):
            InboxWorkflowView(viewModel: viewModel, selectInboxTask: selectInboxTask)
        case .primary(.projects), .project, .smartList:
            ProjectBoardProjectsHubView(
                route: boardRouteBinding,
                projects: sidebarProjects,
                smartLists: allSmartLists,
                showsArchivedProjects: viewModel.showsArchivedProjects,
                onCreateProject: createAndOpenProject,
                onCreateSmartList: { isPresentingSmartListEditor = true },
                onDeleteSmartList: deleteSmartList,
                onToggleArchivedProjects: {
                    viewModel.setShowsArchivedProjects(!viewModel.showsArchivedProjects)
                },
                onMoveDroppedTasks: { rawIDs, projectID in
                    viewModel.moveDroppedTasks(ids: rawIDs, toProjectID: projectID)
                }
            ) {
                projectsHubContent
            }
        case .primary(.review), .review:
            ProjectBoardReviewHubView(
                route: boardRouteBinding,
                assistantQueueCount: viewModel.assistantQueueSnapshot.needsAttentionCount
            ) {
                reviewHubContent
            }
        }
    }

    @ViewBuilder
    private var projectsHubContent: some View {
        switch currentBoardRoute {
        case .primary(.projects):
            ProjectsPortfolioOverview(viewModel: viewModel) { projectID in
                if viewModel.openProjectFromPortfolioCard(projectID: projectID) {
                    navigateWithinScene(to: .project(projectID))
                }
            }
        case .project(let projectID):
            if let project = viewModel.snapshot.projects.first(where: { $0.id == projectID }) {
                ProjectBoardDetail(
                    project: project,
                    displayMode: $displayMode,
                    viewModel: viewModel,
                    onOpenProjectInspector: openProjectInspector,
                    onOpenTaskInspector: openTaskInspector
                )
            } else if viewModel.isEmptyProjectStateVisible {
                ContentUnavailableView("No Projects", systemImage: "folder")
            } else {
                ContentUnavailableView("Project Not Found", systemImage: "folder.badge.questionmark")
            }
        case .smartList(let smartListID):
            if let smartList = allSmartLists.first(where: { $0.id == smartListID }) {
                SmartListWorkflowView(
                    smartList: smartList,
                    viewModel: viewModel,
                    timeZoneIdentifier: appSettings().timeZoneIdentifier
                )
            } else {
                ContentUnavailableView("Smart List Not Found", systemImage: "line.3.horizontal.decrease.circle")
            }
        case .primary, .review:
            EmptyView()
        }
    }

    @ViewBuilder
    private var reviewHubContent: some View {
        switch currentBoardRoute {
        case .primary(.review):
            ContentUnavailableView(
                "Review",
                systemImage: "checklist",
                description: Text("Choose Schedule, Completed, Automation Activity, or Assistant Queue.")
            )
            .accessibilityIdentifier("review-hub-overview")
        case .review(.schedule):
            ScheduleWorkflowView(viewModel: viewModel)
        case .review(.completed):
            DoneWorkflowView(viewModel: viewModel, appSettings: appSettings())
        case .review(.automationActivity):
            ProjectWorkflowAutomationActivityView(
                viewModel: viewModel,
                appSettings: appSettings()
            )
        case .review(.assistantQueue):
            AssistantQueueWorkflowView(viewModel: viewModel)
        case .primary, .project, .smartList:
            EmptyView()
        }
    }

    private func createAndOpenProject() {
        guard let project = viewModel.createProject() else {
            return
        }
        navigateWithinScene(to: .project(project.id))
    }

    private func executeCommandPaletteAction(_ kind: CommandPaletteActionKind) {
        switch kind {
        case .createInboxTask(let title):
            viewModel.createInboxTask(title: title)
            navigateWithinScene(to: .primary(.inbox))
        case .openDestination(let destination):
            if destination == .catchUp {
                navigateWithinScene(to: .primary(.today), focus: .catchUp)
            } else {
                navigateWithinScene(to: typedRoute(for: destination))
            }
        case .openProject(let projectID, _):
            navigateWithinScene(to: .project(projectID))
        case .openSmartList(let smartListID, _):
            if let smartList = allSmartLists.first(where: { $0.id == smartListID }) {
                selectSmartList(smartList)
            }
        case .openVoiceCommandWindow:
            openWindow(id: "voice-capture")
        case .openSettingsWindow:
            openSettings()
        case .revealTask(let taskID, let projectID, _):
            revealTaskFromCommandPalette(taskID: taskID, projectID: projectID)
        case .openKnowledgeFrame:
            // Knowledge frames have no browsing surface (and no owning
            // project) yet, so a knowledge hit only closes the palette after
            // showing its matched snippet.
            break
        }
        isCommandPaletteVisible = false
    }

    /// Switches to the destination that owns the task (its project, or Inbox
    /// for unfiled tasks) and defers the actual selection until
    /// applySelectedDestination has run, because that handler clears
    /// `selectedTaskID` on every destination change.
    private func revealTaskFromCommandPalette(taskID: Int64, projectID: Int64?) {
        let target: ProjectBoardSidebarDestination = projectID.map { .project($0) } ?? .inbox
        pendingCommandPaletteRevealTaskID = taskID
        if selectedDestination == target {
            // onChange(of: selectedDestination) will not fire again.
            applyPendingCommandPaletteRevealIfNeeded()
        } else {
            selectedDestination = target
        }
    }

    private func applyPendingCommandPaletteRevealIfNeeded() {
        guard let taskID = pendingCommandPaletteRevealTaskID else {
            return
        }
        pendingCommandPaletteRevealTaskID = nil
        if case .project(let projectID) = selectedDestination {
            viewModel.selectedProjectID = projectID
        }
        viewModel.selectedTaskID = taskID
    }

    private var allSmartLists: [SmartList] {
        SmartList.presets + savedSmartLists
    }

    private var selectedSmartList: SmartList? {
        guard let selectedSmartListID else {
            return nil
        }
        return allSmartLists.first { $0.id == selectedSmartListID }
    }

    private func selectSmartList(_ smartList: SmartList) {
        selectedSmartListID = smartList.id
        viewModel.selectedTaskID = nil
        allowsCompactInspectorPresentation = false
        // Smart lists overlay the detail without extending the contract-pinned
        // destination enum; clearing the destination keeps exactly one of the
        // two selection sources active at a time.
        selectedDestination = nil
        if ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil {
            persistRoute(.smartList(smartList.id))
        } else {
            transientBoardRoute = .smartList(smartList.id)
        }
    }

    private func reloadSavedSmartLists() {
        savedSmartLists = (try? smartListStore?.list()) ?? []
    }

    private func saveSmartList(_ smartList: SmartList) {
        try? smartListStore?.save(smartList)
        reloadSavedSmartLists()
        if savedSmartLists.contains(where: { $0.id == smartList.id }) || SmartList.presets.contains(where: { $0.id == smartList.id }) {
            selectSmartList(smartList)
        }
    }

    private func deleteSmartList(_ smartList: SmartList) {
        guard !smartList.isPreset else {
            return
        }
        try? smartListStore?.delete(id: smartList.id)
        reloadSavedSmartLists()
        if selectedSmartListID == smartList.id {
            selectedSmartListID = nil
            selectedDestination = .today
        }
    }

    private var isInspectorEffectivelyPresented: Bool {
        InspectorPresentationPolicy.shouldPresent(
            windowWidth: Double(projectBoardWindowWidth),
            route: currentBoardRoute,
            selection: inspectorSelectionContext,
            userRequested: userRequestedInspector,
            allowsCompactPresentation: allowsCompactInspectorPresentation
        )
    }

    private var usesCompactInspectorPresentation: Bool {
        projectBoardWindowWidth < InspectorPresentationPolicy.wideMinimumWidth
    }

    private var wideInspectorBinding: Binding<Bool> {
        Binding(
            get: {
                isInspectorEffectivelyPresented
                    && !usesCompactInspectorPresentation
            },
            set: { isPresented in
                if isPresented {
                    requestInspectorPresentation()
                } else if !usesCompactInspectorPresentation {
                    // SwiftUI also writes `false` to the inactive native
                    // presenter. Only the wide presenter may clear the shared
                    // scene intent while the window is actually wide.
                    dismissInspector()
                }
            }
        )
    }

    @ViewBuilder
    private var inspectorContent: some View {
        Group {
            if let task = viewModel.selectedTask {
                TaskInspectorView(
                    task: task,
                    viewModel: viewModel,
                    onClose: dismissInspector
                )
            } else if let project = selectedProjectForInspector {
                ProjectInspectorView(
                    project: project,
                    viewModel: viewModel,
                    developmentTaskID: projectInspectorDevelopmentContext.taskID,
                    onReviewDevelopmentAutomation: presentDevelopmentAutomationReview,
                    onClose: dismissInspector
                )
            } else {
                EmptyView()
            }
        }
    }

    private var inspectorSelectionContext: InspectorSelectionContext {
        if viewModel.selectedTask != nil {
            return .task
        }
        if selectedProjectForInspector != nil {
            return .project
        }
        return .none
    }

    private func requestInspectorPresentation() {
        userRequestedInspector = true
        persistPrimaryPresentationStateIfNeeded()
        allowsCompactInspectorPresentation = true
        if usesCompactInspectorPresentation {
            // Drive the compact sheet with dedicated state. A computed binding
            // can be reset by SwiftUI while its sibling inspector presenter is
            // inactive, making an explicit Edit action appear to do nothing.
            isCompactInspectorSheetPresented = true
        }
    }

    private func openProjectInspector() {
        // Project and task details are mutually exclusive inspector surfaces,
        // but development automation still needs the task the user was acting
        // on. Preserve only that context before changing the rendered surface.
        projectInspectorDevelopmentContext.handle(
            .openProject(taskID: viewModel.selectedTaskID)
        )
        viewModel.selectedTaskID = nil
        requestInspectorPresentation()
    }

    private func openTaskInspector(_ taskID: Int64) {
        projectInspectorDevelopmentContext.handle(.openTaskInspector)
        viewModel.selectedTaskID = taskID
        requestInspectorPresentation()
    }

    private func updateProjectBoardWindowWidth(_ width: CGFloat) {
        let intent = InspectorPresentationPolicy.intentAfterResize(
            previousWindowWidth: Double(projectBoardWindowWidth),
            currentWindowWidth: Double(width),
            intent: InspectorPresentationIntent(
                userRequested: userRequestedInspector,
                allowsCompactPresentation: allowsCompactInspectorPresentation
            )
        )
        projectBoardWindowWidth = width
        userRequestedInspector = intent.userRequested
        persistPrimaryPresentationStateIfNeeded()
        allowsCompactInspectorPresentation = intent.allowsCompactPresentation
        if usesCompactInspectorPresentation {
            isCompactInspectorSheetPresented = isInspectorEffectivelyPresented
        } else {
            isCompactInspectorSheetPresented = false
        }
    }

    private func dismissInspector() {
        projectInspectorDevelopmentContext.handle(.dismissInspector)
        isCompactInspectorSheetPresented = false
        userRequestedInspector = false
        persistPrimaryPresentationStateIfNeeded()
        allowsCompactInspectorPresentation = false
    }

    private var sidebarToggleHelp: String {
        columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar"
    }

    private func presentDevelopmentAutomationReview(_ plan: ActionPlan) {
        developmentAutomationReviewSheet = DevelopmentAutomationReviewSheet(
            id: plan.id,
            viewModel: developmentAutomationReviewSession(plan)
        )
    }

    private func toggleSidebarVisibility() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            storedSidebarHidden = columnVisibility == .detailOnly
            persistPrimaryPresentationStateIfNeeded()
            refreshProjectBoardColumnsAfterToolbarDisplayModeChange()
        }
    }

    private func restorePrimaryPresentationStateIfNeeded() {
        guard restoresPrimaryPresentationState else { return }
        // SceneStorage keeps simultaneous windows isolated. OS window
        // restoration is deliberately disabled, so a primary-only copy carries
        // safe presentation preferences across a completely fresh launch.
        userRequestedInspector = primaryUserRequestedInspector
        storedSidebarHidden = primarySidebarHidden
    }

    private func persistPrimaryPresentationStateIfNeeded() {
        guard restoresPrimaryPresentationState else { return }
        primaryUserRequestedInspector = userRequestedInspector
        primarySidebarHidden = storedSidebarHidden
    }

    private func refreshProjectBoardColumnsAfterToolbarDisplayModeChange() {
        toolbarLayoutRefreshToken += 1
    }

    private var selectedProjectForInspector: ProjectBoardProject? {
        guard case .project(let projectID) = selectedDestination else {
            return nil
        }
        return viewModel.snapshot.projects.first { $0.id == projectID }
    }

    private var sidebarProjects: [ProjectBoardProject] {
        viewModel.snapshot.projects.filter { $0.id != viewModel.inboxProject?.id }
    }

    private var activeSidebarProjects: [ProjectBoardProject] {
        sidebarProjects.filter { !$0.isCompleted && !$0.isArchived }
    }

    private var completedSidebarProjects: [ProjectBoardProject] {
        sidebarProjects.filter { $0.isCompleted && !$0.isArchived }
    }

    private var archivedSidebarProjects: [ProjectBoardProject] {
        sidebarProjects.filter(\.isArchived)
    }

    private var isDeveloperModeEnabled: Bool {
        appSettings().isDeveloperModeEnabled
    }

    private var projectBoardToolbarContext: ProjectBoardToolbarContext {
        ProjectBoardToolbarContext(
            routeKind: projectBoardToolbarRouteKind,
            isDeveloperModeEnabled: isDeveloperModeEnabled,
            hasInspectorSelection: inspectorSelectionContext != .none
        )
    }

    private var projectBoardToolbarRouteKind: ProjectBoardToolbarContext.RouteKind {
        switch currentBoardRoute {
        case .primary(.today):
            .today
        case .primary(.inbox):
            .inbox
        case .primary(.projects):
            .projects
        case .primary(.review), .review:
            .review
        case .project:
            .project
        case .smartList:
            .smartList
        }
    }

    private func toggleInspectorPresentation() {
        if isInspectorEffectivelyPresented {
            dismissInspector()
        } else {
            requestInspectorPresentation()
        }
    }

    private var terminalWorkingDirectory: URL {
        if let workspacePath = appSettings().defaultWorkspacePath?.trimmingCharacters(in: .whitespacesAndNewlines),
           workspacePath.hasPrefix("/") {
            return URL(fileURLWithPath: workspacePath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private func restoreSelectedDestinationIfNeeded() {
        // A smart list selection intentionally leaves the destination nil, so a
        // data-change reload must not clobber it by restoring the persisted
        // destination underneath the visible smart list.
        guard selectedSmartListID == nil else {
            return
        }
        let availableProjectIDs = Set(viewModel.snapshot.projects.map(\.id))
        let resolution: ProjectBoardRouteResolution
        if let override = ProjectBoardSelectionPersistence.environmentOverrideRawValue {
            resolution = ProjectBoardRouteCodec.resolution(
                from: override,
                availableProjectIDs: availableProjectIDs
            )
            let route = validatedRoute(resolution.route)
            transientBoardRoute = route
            applyRouteFocus(resolution.focus)
            applyRouteToLegacyUI(route)
            applySelectedTaskOverrideIfNeeded()
            return
        } else {
            resolution = ProjectBoardScenePersistence.restoredResolution(
                sceneRawValue: currentSceneRouteRawValue,
                initialRawValue: initialRouteRawValue,
                availableProjectIDs: availableProjectIDs
            )
        }
        let validatedRoute = validatedRoute(resolution.route)
        applyRouteFocus(resolution.focus)
        persistRoute(validatedRoute, updateInitialRoute: false)
        applyRouteToLegacyUI(validatedRoute)
        applySelectedTaskOverrideIfNeeded()
    }

    private func applyRouteFocus(_ focus: BoardRouteFocus?) {
        guard focus == .catchUp else {
            return
        }
        // The revision is view-local state, so a migrated deep link can expand
        // Catch Up exactly once without leaking presentation state to another
        // Project Board window.
        activeBoardRouteFocus = focus
        catchUpFocusRevision += 1
    }

    private func cancelRouteFocus() {
        activeBoardRouteFocus = nil
        consumedCatchUpFocusRevision = catchUpFocusRevision
    }

    private func persistSelectedDestination(_ destination: ProjectBoardSidebarDestination?) {
        guard ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil else {
            return
        }
        guard let destination else {
            return
        }
        persistRoute(typedRoute(for: destination))
    }

    private func persistRoute(_ route: BoardRoute, updateInitialRoute: Bool = true) {
        guard ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil else {
            return
        }
        let rawValue = ProjectBoardRouteCodec.rawValue(for: route)
        currentSceneRouteRawValue = rawValue
        if updateInitialRoute {
            // This preference seeds only future windows. Existing windows never
            // restore from it once their own SceneStorage route is present.
            initialRouteRawValue = rawValue
        }
    }

    private func typedRoute(for destination: ProjectBoardSidebarDestination) -> BoardRoute {
        switch destination {
        case .inbox:
            .primary(.inbox)
        case .assistantQueue:
            .review(.assistantQueue)
        case .today, .catchUp:
            .primary(.today)
        case .schedule:
            .review(.schedule)
        case .done:
            .review(.completed)
        case .projects:
            .primary(.projects)
        case .project(let projectID):
            .project(projectID)
        }
    }

    private func validatedRoute(_ route: BoardRoute) -> BoardRoute {
        switch route {
        case .project(let projectID):
            return viewModel.snapshot.projects.contains(where: { $0.id == projectID })
                ? route
                : .primary(.today)
        case .smartList(let smartListID):
            return allSmartLists.contains(where: { $0.id == smartListID })
                ? route
                : .primary(.today)
        case .primary, .review:
            return route
        }
    }

    private func applyRouteToLegacyUI(_ route: BoardRoute) {
        let destination: ProjectBoardSidebarDestination?
        let smartListID: String?
        switch route {
        case .primary(.today):
            destination = .today
            smartListID = nil
        case .primary(.inbox):
            destination = .inbox
            smartListID = nil
        case .primary(.projects):
            destination = .projects
            smartListID = nil
        case .primary(.review):
            // The compatibility facade has no Review overview case. Assistant
            // Queue preserves the legacy non-project selection semantics while
            // the typed route remains the rendering source of truth.
            destination = .assistantQueue
            smartListID = nil
        case .project(let projectID):
            destination = .project(projectID)
            smartListID = nil
        case .smartList(let routeSmartListID):
            destination = nil
            smartListID = routeSmartListID
        case .review(.schedule):
            destination = .schedule
            smartListID = nil
        case .review(.completed):
            destination = .done
            smartListID = nil
        case .review(.automationActivity), .review(.assistantQueue):
            destination = .assistantQueue
            smartListID = nil
        }
        selectedSmartListID = smartListID
        applyLegacyDestinationWithinScene(destination)
    }

    private func applyLegacyDestinationWithinScene(
        _ destination: ProjectBoardSidebarDestination?
    ) {
        if selectedDestination != destination {
            // SwiftUI invokes onChange after this mutation. Keep suppression
            // pending until that callback consumes it; resetting here would
            // let targeted payload routing overwrite the new-window default.
            pendingDestinationPersistenceSuppression = ProjectBoardDestinationPersistenceSuppression(
                destination: destination
            )
            selectedDestination = destination
        }
        applySelectedDestination(destination)
    }

    private func consumePendingSceneOpenRequests() {
        while let request = sceneCoordinator.consumeNext(for: sceneID) {
            applySceneOpenRequest(request)
        }
    }

    private func applySceneOpenRequest(_ request: ProjectBoardOpenRequest) {
        let route = validatedRoute(request.route)
        if ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil {
            persistRoute(
                route,
                updateInitialRoute: ProjectBoardScenePersistence.shouldUpdateInitialRoute(for: request)
            )
        } else {
            transientBoardRoute = route
        }
        applyRouteToLegacyUI(route)

        // Payload bridges retain only feature-specific data. Navigation and ID
        // ownership are consumed once here by the shared scene coordinator.
        switch route {
        case .primary(.inbox):
            consumePendingVoiceInboxTriageRequestIfNeeded(id: request.id)
        case .primary(.today):
            consumePendingVoiceDailyPlanningReviewRequestIfNeeded(id: request.id)
        case .review(.assistantQueue):
            consumePendingVoiceDailyPlanningReviewRequestIfNeeded(id: request.id)
            consumePendingAssistantQueueRequestIfNeeded(id: request.id)
        case .primary, .project, .smartList, .review:
            break
        }
        // Acknowledge only after route state and any feature payload are
        // applied. Follow-up focus work can now wait on this exact request ID.
        sceneCoordinator.acknowledgeApplied(requestID: request.id)
    }

    private func applySelectedDestination(_ destination: ProjectBoardSidebarDestination?) {
        projectInspectorDevelopmentContext.handle(.destinationChanged)
        switch destination {
        case .project(let projectID):
            viewModel.selectedProjectID = projectID
            viewModel.selectedTaskID = nil
        case .inbox, .assistantQueue, .today, .catchUp, .schedule, .done, .projects, .none:
            viewModel.selectedTaskID = nil
        }
    }

    private func consumePendingVoiceDailyPlanningReviewRequestIfNeeded(id: UUID) {
        guard let request = SuisuiVoiceDailyPlanningReviewBridge.consumePendingRequest(id: id) else {
            return
        }
        handleVoiceDailyPlanningReviewRequest(
            sourceTranscript: normalizedVoiceDailyPlanningReviewTranscript(request.sourceTranscript),
            actionDraftKind: request.actionDraftKind
        )
    }

    private func consumePendingVoiceInboxTriageRequestIfNeeded(id: UUID) {
        guard let request = SuisuiVoiceInboxTriageBridge.consumePendingRequest(id: id) else {
            return
        }
        handleVoiceInboxTriageRequest(request: request)
    }

    private func consumePendingAssistantQueueRequestIfNeeded(id: UUID) {
        guard let request = SuisuiAssistantQueueBridge.consumePendingOpen(id: id) else {
            return
        }
        handleAssistantQueueOpenRequest(request: request)
    }

    private func handleVoiceDailyPlanningReviewRequest(_ notification: Notification) {
        guard let request = notification.userInfo?[SuisuiVoiceDailyPlanningReviewBridge.requestUserInfoKey]
            as? SuisuiVoiceDailyPlanningReviewBridge.Request,
              let openRequest = sceneCoordinator.consume(requestID: request.id, for: sceneID) else {
            return
        }
        applySceneOpenRequest(openRequest)
    }

    private func normalizedVoiceDailyPlanningReviewTranscript(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Today daily planning review") : trimmed
    }

    private func handleVoiceDailyPlanningReviewRequest(
        sourceTranscript: String,
        actionDraftKind: DailyPlanningActionDraftKind? = nil
    ) {
        viewModel.load()
        _ = viewModel.prepareDailyPlanningReview(transcript: sourceTranscript)
        let summary = viewModel.derivedReadModels.missedTaskReview
        if let actionDraftKind {
            // Voice-triggered planning actions still become Assistant Queue
            // drafts so Today review can suggest writes without mutating tasks
            // before explicit user approval.
            let queued = viewModel.enqueueDailyPlanningActionDraft(
                kind: actionDraftKind,
                transcript: sourceTranscript
            )
            if queued {
                navigateWithinScene(
                    to: .review(.assistantQueue),
                    updateInitialRoute: false
                )
            } else {
                navigateToTodayForDailyPlanning(summary: summary)
            }
        } else {
            navigateToTodayForDailyPlanning(summary: summary)
        }
        playDailyPlanningReadoutFromSettings()
    }

    private func navigateToTodayForDailyPlanning(summary: MissedTaskReviewSummary) {
        navigateWithinScene(
            to: .primary(.today),
            focus: summary.newlyMissedCount > 0 ? .catchUp : nil,
            updateInitialRoute: false
        )
    }

    private func playDailyPlanningReadoutFromSettings() {
        Task {
            let settings = appSettings().normalizedForRuntime
            _ = await viewModel.playDailyPlanningReviewReadout(
                using: AppTextToSpeechRuntimeFactory.makePreviewer(
                    settings: settings,
                    temporaryDirectoryPrefix: "suisui-daily-planning-readout",
                    outputFilename: "readout.wav"
                ),
                languageCode: settings.ttsLanguageCode,
                voiceID: settings.ttsVoiceID
            )
        }
    }

    private func handleVoiceInboxTriageRequest(_ notification: Notification) {
        guard let request = notification.userInfo?[SuisuiVoiceInboxTriageBridge.requestUserInfoKey]
            as? SuisuiVoiceInboxTriageBridge.Request,
              let openRequest = sceneCoordinator.consume(requestID: request.id, for: sceneID) else {
            return
        }
        applySceneOpenRequest(openRequest)
    }

    private func handleVoiceInboxTriageRequest(request: SuisuiVoiceInboxTriageBridge.Request) {
        viewModel.load()
        openInboxForVoiceTriage()
        _ = viewModel.applyInboxVoiceTriageCommand(request.command)
    }

    private func openInboxForVoiceTriage() {
        if selectedDestination != .inbox {
            applyLegacyDestinationWithinScene(.inbox)
        }
        allowsCompactInspectorPresentation = false
    }

    private func handleAssistantQueueOpenRequest(_ notification: Notification) {
        guard let request = notification.userInfo?[SuisuiAssistantQueueBridge.requestUserInfoKey]
            as? SuisuiAssistantQueueBridge.Request,
              let openRequest = sceneCoordinator.consume(requestID: request.id, for: sceneID) else {
            return
        }
        applySceneOpenRequest(openRequest)
    }

    private func handleAssistantQueueOpenRequest(request: SuisuiAssistantQueueBridge.Request) {
        viewModel.load()
        applyLegacyDestinationWithinScene(.assistantQueue)
        _ = viewModel.focusAssistantQueueExecutionHandoff(id: request.itemID)
    }

    private func applySelectedTaskOverrideIfNeeded() {
        guard let taskID = ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID,
              let task = viewModel.snapshot.projects.flatMap(\.tasks).first(where: { $0.id == taskID }) else {
            return
        }
        // The override is env-only because release evidence needs deterministic
        // first selection without changing the user's persisted Project Board state.
        viewModel.selectedProjectID = task.projectID
        viewModel.selectedTaskID = task.id
        // Inbox and Today own their review details in persistent workflow rails;
        // opening the broader inspector here would hide the seeded evidence state.
        allowsCompactInspectorPresentation = false
    }

    private func selectTodayTask(_ task: ProjectBoardTask) {
        // Today row selection feeds the persistent assistant rail first. The
        // inspector still opens explicitly from the rail Edit action.
        viewModel.selectedTaskID = task.id
    }

    private func selectInboxTask(_ task: ProjectBoardTask) {
        // Inbox triage keeps consecutive voice captures in the workflow rail so
        // users can classify them without the broader edit inspector taking focus.
        viewModel.selectedTaskID = task.id
    }

    private func openInspectorForTodayRailTask(_ taskID: Int64) {
        viewModel.selectedTaskID = taskID
        guard viewModel.selectedTask != nil else {
            return
        }

        requestInspectorPresentation()
    }

    private var taskInteropDefaultExportFilename: String {
        "suisui-tasks-\(Self.exportDateFormatter.string(from: Date())).json"
    }

    private func beginTaskInteropExport() {
        guard let data = viewModel.exportTaskInteropJSON() else {
            return
        }
        taskInteropExportDocument = TaskInteropFileDocument(data: data)
        isExportingTaskInterop = true
    }

    private func approveGoogleCalendarSync() {
        isGoogleCalendarSyncApprovalPresented = false
        _ = viewModel.syncDueTasksToGoogleCalendar(approvalToken: UUID().uuidString)
    }

    private func handleTaskInteropImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else {
                return
            }
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            _ = viewModel.importTaskInteropJSON(data)
        } catch {
            viewModel.recordTaskInteropFileFailure(error)
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private struct ProjectBoardSynchronizedColumnBounds: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private extension View {
    func projectBoardSynchronizedColumnBounds() -> some View {
        modifier(ProjectBoardSynchronizedColumnBounds())
    }
}

private struct ProjectBoardTodayRefreshLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var boundaryRefreshTask: Task<Void, Never>?
    let refresh: () -> Void

    func body(content: Content) -> some View {
        // Keep time-driven refreshes outside ProjectBoardView's already-large
        // modifier chain so Swift can type-check the view while the live app
        // still crosses day, timezone, locale, and activation boundaries.
        content
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
                refreshAndRescheduleBoundary()
            }
            .onAppear {
                scheduleBoundaryRefreshIfActive()
            }
            .onDisappear {
                cancelBoundaryRefresh()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    cancelBoundaryRefresh()
                    return
                }
                refreshAndRescheduleBoundary()
            }
    }

    private func refreshAndRescheduleBoundary() {
        guard scenePhase == .active else {
            return
        }
        refresh()
        scheduleBoundaryRefreshIfActive()
    }

    private func scheduleBoundaryRefreshIfActive() {
        cancelBoundaryRefresh()
        guard scenePhase == .active else {
            return
        }

        let boundary = DailyPlanningReviewRefreshSchedule.nextStrictBoundary(
            after: Date(),
            calendar: .current
        )
        let nanoseconds = UInt64(max(boundary.timeIntervalSinceNow, 0) * 1_000_000_000)
        boundaryRefreshTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, scenePhase == .active else {
                return
            }

            refresh()
            scheduleBoundaryRefreshIfActive()
        }
    }

    private func cancelBoundaryRefresh() {
        boundaryRefreshTask?.cancel()
        boundaryRefreshTask = nil
    }
}

#if canImport(AppKit)
private struct ProjectBoardToolbarLayoutBridge: NSViewRepresentable {
    let columnVisibility: NavigationSplitViewVisibility
    let onToolbarLayoutChanged: () -> Void
    let onWindowWidthChanged: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProjectBoardToolbarLayoutBridgeView(frame: .zero)
        view.onToolbarLayoutChanged = onToolbarLayoutChanged
        view.onWindowWidthChanged = onWindowWidthChanged
        view.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = columnVisibility
        guard let view = nsView as? ProjectBoardToolbarLayoutBridgeView else {
            return
        }

        view.onToolbarLayoutChanged = onToolbarLayoutChanged
        view.onWindowWidthChanged = onWindowWidthChanged
        view.installToolbarDisplayModeObservationIfNeeded()
        view.installToolbarDisplayModeMenuPruningIfNeeded()
        view.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)
    }
}

private final class ProjectBoardToolbarLayoutBridgeView: NSView {
    var onToolbarLayoutChanged: (() -> Void)?
    var onWindowWidthChanged: ((CGFloat) -> Void)?
    private let runtimeDiagnosticLogger = Logger(subsystem: "dev.suisui.app", category: "runtime")
    private weak var observedToolbar: NSToolbar?
    private var toolbarDisplayModeObservation: NSKeyValueObservation?
    private var isToolbarDisplayModeMenuPruningInstalled = false
    private var observedToolbarDisplayMode: NSToolbar.DisplayMode?
    private var isPerformingToolbarLayoutPass = false
    private var toolbarLayoutReconcileDepth = 0
    private var toolbarLayoutMaxDepth = 0
    private var didScheduleInitialToolbarLayoutStabilization = false
    private var observedWindowWidth: CGFloat?
    private var reportedContentLayoutSize: NSSize?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        enforceProjectBoardWindowMinimumSize()
        reportWindowWidthIfChanged()
        installToolbarDisplayModeObservationIfNeeded()
        installToolbarDisplayModeMenuPruningIfNeeded()
        reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: true)
        scheduleInitialProjectBoardToolbarLayoutStabilizationIfNeeded()
    }

    override func layout() {
        super.layout()
        enforceProjectBoardWindowMinimumSize()
        reportWindowWidthIfChanged()
        reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)
    }

    private func reportWindowWidthIfChanged() {
        guard let width = window?.frame.width, width != observedWindowWidth else {
            return
        }
        observedWindowWidth = width
        onWindowWidthChanged?(width)
    }

    private func enforceProjectBoardWindowMinimumSize() {
        guard let window else {
            return
        }

        // AX-driven resizes can bypass SwiftUI's content fitting constraint.
        // The product contract is expressed in content coordinates; titlebar
        // and toolbar height vary per window and must not consume the usable
        // 960x572 board area.
        let minimumContentSize = NSSize(
            width: ProjectBoardWindowMetrics.minWidth,
            height: ProjectBoardWindowMetrics.minHeight
        )
        if window.contentMinSize != minimumContentSize {
            window.contentMinSize = minimumContentSize
        }

        let minimumFrameSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: minimumContentSize)
        ).size
        if window.minSize != minimumFrameSize {
            window.minSize = minimumFrameSize
        }

        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let constrainedContentSize = NSSize(
            width: max(currentContentRect.width, minimumContentSize.width),
            height: max(currentContentRect.height, minimumContentSize.height)
        )
        guard constrainedContentSize != currentContentRect.size else {
            reportContentLayoutSizeIfRequested(window)
            return
        }

        var constrainedFrame = window.frameRect(
            forContentRect: NSRect(origin: currentContentRect.origin, size: constrainedContentSize)
        )
        // Growing upward preserves the titlebar position and avoids moving a
        // window under the pointer while toolbar reconciliation is re-entered.
        constrainedFrame.origin.x = window.frame.minX
        constrainedFrame.origin.y = window.frame.maxY - constrainedFrame.height
        window.setFrame(constrainedFrame, display: true)
        reportContentLayoutSizeIfRequested(window)
    }

    private func reportContentLayoutSizeIfRequested(_ window: NSWindow) {
        guard let rawPath = ProcessInfo.processInfo.environment[
            "SUISUI_LAYOUT_STABILITY_WINDOW_CONTENT_SIZE_PATH"
        ], rawPath.isEmpty == false else {
            return
        }

        let contentLayoutSize = window.contentLayoutRect.size
        guard contentLayoutSize != reportedContentLayoutSize else {
            return
        }
        reportedContentLayoutSize = contentLayoutSize

        // Runtime layout evidence needs the usable content size after titlebar
        // and toolbar subtraction. Production runs do no file I/O because the
        // opt-in evidence path is absent.
        let payload = "\(Int(contentLayoutSize.width.rounded())) \(Int(contentLayoutSize.height.rounded()))\n"
        try? payload.write(
            toFile: rawPath,
            atomically: true,
            encoding: .utf8
        )
    }

    @discardableResult
    private func removeNativeSidebarToggle(in toolbar: NSToolbar) -> Bool {
        let removalIndexes = ProjectBoardToolbarLayoutPolicy.nativeSidebarRemovalIndexes(
            in: toolbar.projectBoardLayoutItems
        )
        guard removalIndexes.isEmpty == false else {
            return false
        }

        // Keep toolbar display modes user-adaptive; only remove the native
        // sidebar item and tracking separator that visually drift in this
        // SwiftUI-hosted split view.
        for index in removalIndexes.reversed() {
            toolbar.removeItem(at: index)
        }
        return true
    }

    func installToolbarDisplayModeObservationIfNeeded() {
        guard let toolbar = window?.toolbar,
              observedToolbar !== toolbar else {
            return
        }

        _ = enforceProjectBoardSupportedToolbarDisplayMode(toolbar)
        toolbarDisplayModeObservation?.invalidate()
        observedToolbar = toolbar
        observedToolbarDisplayMode = toolbar.displayMode
        toolbarDisplayModeObservation = toolbar.observe(\.displayMode, options: [.new]) { [weak self] _, _ in
            guard let self else {
                return
            }

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.reconcileToolbarDisplayModeChange()
                }
            } else {
                DispatchQueue.main.async {
                    self.reconcileToolbarDisplayModeChange()
                }
            }
        }
    }

    private func scheduleInitialProjectBoardToolbarLayoutStabilizationIfNeeded() {
        guard didScheduleInitialToolbarLayoutStabilization == false else {
            return
        }

        didScheduleInitialToolbarLayoutStabilization = true
        for delay in [0.05, 0.25, 0.75] {
            // layout-attachment-delay: initial AppKit toolbar attachment gap.
            // SwiftUI can attach the bridge before NSToolbar items exist; this
            // bounded startup sampling is the only delayed correction allowed
            // by ADR 0009, and user-triggered display-mode/sidebar changes
            // mutate the toolbar synchronously without forcing a full view-tree layout.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)
            }
        }
    }

    private func reconcileToolbarDisplayModeChange() {
        guard let toolbar = observedToolbar ?? window?.toolbar,
              observedToolbarDisplayMode != toolbar.displayMode else {
            return
        }

        _ = enforceProjectBoardSupportedToolbarDisplayMode(toolbar)
        observedToolbarDisplayMode = toolbar.displayMode
        reconcileProjectBoardToolbarLayout(
            allowRetryIfToolbarMissing: false,
            notifyColumnsWhenToolbarAlreadyStable: true
        )
    }

    @discardableResult
    private func enforceProjectBoardSupportedToolbarDisplayMode(_ toolbar: NSToolbar) -> Bool {
        let supportedDisplayMode = projectBoardSupportedToolbarDisplayMode(for: toolbar.displayMode)
        guard toolbar.displayMode != supportedDisplayMode else {
            return false
        }

        toolbar.displayMode = supportedDisplayMode
        return true
    }

    private func projectBoardSupportedToolbarDisplayMode(for displayMode: NSToolbar.DisplayMode) -> NSToolbar.DisplayMode {
        switch displayMode {
        case .iconAndLabel:
            return .iconAndLabel
        case .iconOnly:
            return .iconOnly
        case .labelOnly, .default:
            // Text-only toolbar buttons collapse the icon anchors that the
            // Project Board header uses for stable scan order. Prefer the
            // full label mode when AppKit asks for an unsupported display mode.
            return .iconAndLabel
        @unknown default:
            return .iconAndLabel
        }
    }

    func installToolbarDisplayModeMenuPruningIfNeeded() {
        guard isToolbarDisplayModeMenuPruningInstalled == false else {
            return
        }

        isToolbarDisplayModeMenuPruningInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(projectBoardToolbarMenuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    @objc private func projectBoardToolbarMenuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              window != nil else {
            return
        }

        pruneUnsupportedProjectBoardToolbarDisplayModeItems(from: menu)
    }

    private func pruneUnsupportedProjectBoardToolbarDisplayModeItems(from menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                pruneUnsupportedProjectBoardToolbarDisplayModeItems(from: submenu)
            }
        }

        guard isProjectBoardToolbarDisplayModeMenu(menu) else {
            return
        }

        let unsupportedTitles = Set(["Text Only", "テキストのみ"])
        for item in menu.items.reversed() where unsupportedTitles.contains(item.title) {
            // AppKit builds toolbar display-mode menus lazily and does not
            // expose a public allowed-display-modes API. Remove only the
            // unsupported text-only item so users keep the two stable modes.
            menu.removeItem(item)
        }
    }

    private func isProjectBoardToolbarDisplayModeMenu(_ menu: NSMenu) -> Bool {
        let itemTitles = Set(menu.items.map(\.title))
        let hasIconAndTextMode = itemTitles.contains("Icon and Text") || itemTitles.contains("アイコンとテキスト")
        let hasIconOnlyMode = itemTitles.contains("Icon Only") || itemTitles.contains("アイコンのみ")
        return hasIconAndTextMode && hasIconOnlyMode
    }

    func reconcileProjectBoardToolbarLayout(
        allowRetryIfToolbarMissing: Bool,
        notifyColumnsWhenToolbarAlreadyStable: Bool = false
    ) {
        enforceProjectBoardWindowMinimumSize()
        // Record re-entry before the existing boolean guard returns. This keeps
        // nested attempts observable without allowing nested toolbar mutation.
        toolbarLayoutReconcileDepth += 1
        toolbarLayoutMaxDepth = max(toolbarLayoutMaxDepth, toolbarLayoutReconcileDepth)
        runtimeDiagnosticLogger.notice(
            "suisui.toolbar.layout.maxDepth=\(self.toolbarLayoutMaxDepth, privacy: .public)"
        )
        defer { toolbarLayoutReconcileDepth -= 1 }

        guard isPerformingToolbarLayoutPass == false else {
            return
        }

        guard toolbarLayoutReconcileDepth == 1 else {
            return
        }

        guard let toolbar = window?.toolbar else {
            if allowRetryIfToolbarMissing {
                retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts: 6)
            }
            return
        }

        isPerformingToolbarLayoutPass = true
        defer { isPerformingToolbarLayoutPass = false }

        var didMutateToolbar = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            if window?.titleVisibility != .hidden {
                window?.titleVisibility = .hidden
                didMutateToolbar = true
            }
            if toolbar.centeredItemIdentifier != nil {
                toolbar.centeredItemIdentifier = nil
                didMutateToolbar = true
            }
            didMutateToolbar = enforceProjectBoardSupportedToolbarDisplayMode(toolbar) || didMutateToolbar
            didMutateToolbar = removeNativeSidebarToggle(in: toolbar) || didMutateToolbar
        }

        if didMutateToolbar {
            markProjectBoardWindowLayoutDirty()
        }

        if didMutateToolbar || notifyColumnsWhenToolbarAlreadyStable {
            // NSToolbar display-mode changes come from AppKit context menus,
            // outside SwiftUI state. Bump SwiftUI state only when the toolbar
            // actually changed; forcing contentView layout here recursively
            // size-fits the whole Project Board and stalls packaged app launch.
            onToolbarLayoutChanged?()
        }
    }

    private func markProjectBoardWindowLayoutDirty() {
        window?.contentView?.needsLayout = true
        window?.contentView?.needsDisplay = true
    }

    private func retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts: Int) {
        guard remainingAttempts > 0 else {
            return
        }

        // SwiftUI may attach the NSToolbar after the representable enters the
        // window, and its toolbar items can arrive shortly after the toolbar
        // itself. Retry only for that initial attachment gap; user-triggered
        // display-mode/sidebar changes run synchronously once the toolbar exists.
        // layout-attachment-delay: initial AppKit toolbar attachment gap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else {
                return
            }

            self.reconcileProjectBoardToolbarLayout(allowRetryIfToolbarMissing: false)
            if self.window?.toolbar == nil {
                self.retrySynchronousProjectBoardToolbarLayoutPass(remainingAttempts: remainingAttempts - 1)
            }
        }
    }

}

private extension NSToolbar {
    var projectBoardLayoutItems: [ProjectBoardToolbarLayoutPolicy.Item] {
        items.map(\.projectBoardLayoutItem)
    }
}

private extension NSToolbarItem {
    var projectBoardLayoutItem: ProjectBoardToolbarLayoutPolicy.Item {
        ProjectBoardToolbarLayoutPolicy.Item(
            identifierRawValue: itemIdentifier.rawValue,
            label: label,
            paletteLabel: paletteLabel,
            toolTip: toolTip,
            accessibilityIdentifier: view?.accessibilityIdentifier(),
            isNativeToggleAction: action == #selector(NSSplitViewController.toggleSidebar(_:))
        )
    }
}
#else
private struct ProjectBoardToolbarLayoutBridge: View {
    let columnVisibility: NavigationSplitViewVisibility
    let onToolbarLayoutChanged: () -> Void
    let onWindowWidthChanged: (CGFloat) -> Void

    var body: some View {
        EmptyView()
    }
}
#endif

/// Focused-scene handle for the board-operation undo stack. Equality tracks the
/// owning view model and undo availability so SwiftUI refreshes the Edit-menu
/// item exactly when the stack flips between empty and undoable.
struct ProjectBoardUndoCommandAction: Equatable {
    let canUndo: Bool
    private let viewModelID: ObjectIdentifier
    private let perform: @MainActor () -> Void

    @MainActor
    init(viewModel: ProjectBoardViewModel) {
        canUndo = viewModel.canUndoBoardOperation
        viewModelID = ObjectIdentifier(viewModel)
        perform = { viewModel.undoLastBoardOperation() }
    }

    @MainActor
    func callAsFunction() {
        perform()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModelID == rhs.viewModelID && lhs.canUndo == rhs.canUndo
    }
}

private struct ProjectBoardUndoFocusedValueKey: FocusedValueKey {
    typealias Value = ProjectBoardUndoCommandAction
}

extension FocusedValues {
    var projectBoardUndo: ProjectBoardUndoCommandAction? {
        get { self[ProjectBoardUndoFocusedValueKey.self] }
        set { self[ProjectBoardUndoFocusedValueKey.self] = newValue }
    }
}

/// Edit-menu entry for the board-operation undo stack. The ⌘Z key itself is
/// handled by the focused Kanban container (so text fields keep the standard
/// text Undo); this command adds the discoverable menu affordance and stays
/// enabled only while the key Project Board window has an undoable operation.
struct SuisuiProjectBoardUndoCommands: Commands {
    @FocusedValue(\.projectBoardUndo) private var projectBoardUndo

    var body: some Commands {
        CommandGroup(after: .undoRedo) {
            Button {
                projectBoardUndo?()
            } label: {
                Label("Undo Board Operation", systemImage: "arrow.uturn.backward")
            }
            .disabled(projectBoardUndo?.canUndo != true)
            .help("Undo the last board task change")
            .accessibilityIdentifier("project-board-undo-command")
            .accessibilityHint("Reverts the most recent task completion, move, edit, or delete on the Project Board.")
        }
    }
}

extension Notification.Name {
    // .suisuiProjectBoardDidChange moved to SuisuiCore (FirstRunOnboarding.swift)
    // so core store writers can post it without duplicating the raw name.
    static let suisuiVoiceDailyPlanningReviewRequested = Notification.Name("dev.suisui.voiceDailyPlanningReviewRequested")
    static let suisuiVoiceInboxTriageRequested = Notification.Name("dev.suisui.voiceInboxTriageRequested")
    static let suisuiAssistantQueueRequested = Notification.Name("dev.suisui.assistantQueueRequested")
}

@MainActor
enum SuisuiAssistantQueueBridge {
    struct Request: Equatable {
        var id: UUID
        var itemID: String
    }

    static let requestUserInfoKey = "request"
    private static var pendingRequests = ProjectBoardRequestPayloadStore<Request>()

    static func storePendingOpen(itemID: String?) -> Request? {
        guard let itemID = itemID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !itemID.isEmpty else {
            return nil
        }
        let request = Request(id: UUID(), itemID: itemID)
        return pendingRequests.store(request, id: request.id) ? request : nil
    }

    static func consumePendingOpen(id: UUID) -> Request? {
        pendingRequests.consume(id: id)
    }

    static func discardPendingOpen(id: UUID) {
        pendingRequests.discard(id: id)
    }
}

@MainActor
enum SuisuiVoiceDailyPlanningReviewBridge {
    struct Request: Equatable {
        var id: UUID
        var sourceTranscript: String
        var actionDraftKind: DailyPlanningActionDraftKind?
    }

    static let requestUserInfoKey = "request"
    private static var pendingRequests = ProjectBoardRequestPayloadStore<Request>()

    static func storePendingRequest(_ request: VoiceDailyPlanningReviewRequest) -> Request? {
        let bridgeRequest = Request(
            id: request.id,
            sourceTranscript: normalized(request.sourceTranscript),
            actionDraftKind: request.requestedActionDraftKind
        )
        return pendingRequests.store(bridgeRequest, id: bridgeRequest.id) ? bridgeRequest : nil
    }

    static func consumePendingRequest(id: UUID) -> Request? {
        pendingRequests.consume(id: id)
    }

    static func discardPendingRequest(id: UUID) {
        pendingRequests.discard(id: id)
    }

    private static func normalized(_ sourceTranscript: String) -> String {
        sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
enum SuisuiVoiceInboxTriageBridge {
    struct Request: Equatable {
        var id: UUID
        var command: InboxVoiceTriageCommand
    }

    static let requestUserInfoKey = "request"
    private static var pendingRequests = ProjectBoardRequestPayloadStore<Request>()

    static func storePendingRequest(_ request: VoiceInboxTriageRequest) -> Request? {
        let bridgeRequest = Request(id: request.id, command: request.command)
        return pendingRequests.store(bridgeRequest, id: bridgeRequest.id) ? bridgeRequest : nil
    }

    static func consumePendingRequest(id: UUID) -> Request? {
        pendingRequests.consume(id: id)
    }

    static func discardPendingRequest(id: UUID) {
        pendingRequests.discard(id: id)
    }
}

private struct TaskInteropFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ProjectBoardDisplayMode: String, CaseIterable, Identifiable {
    case overview
    case board
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview:
            "Overview"
        case .board:
            "Board"
        case .list:
            "List"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .board:
            "rectangle.3.group"
        case .list:
            "list.bullet"
        }
    }
}

private struct ProjectSidebarRow: View {
    let project: ProjectBoardProject
    let onSelect: () -> Void
    let onMoveDroppedTasks: ([String]) -> Bool
    @State private var isDropTargeted = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(project.title)
                Text(project.isArchived ? localizedDisplay("Archived") : localizedTaskCount(project.taskCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.accessibilitySidebarLabel)
        .accessibilityHint("Selects this project. Drop task cards here to move them into this project.")
        .accessibilityIdentifier("project-sidebar-row-\(project.id)")
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityAction(.default, onSelect)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(isDropTargeted ? project.sidebarDropTint.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isDropTargeted ? project.sidebarDropTint.opacity(0.6) : Color.clear, lineWidth: 1)
        }
        .dropDestination(for: String.self) { rawIDs, _ in
            onMoveDroppedTasks(rawIDs)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private var systemImage: String {
        if project.isArchived {
            return "archivebox"
        }
        return project.isCompleted ? "checkmark.circle" : "folder"
    }

    private var iconColor: Color {
        if project.isArchived {
            return .secondary
        }
        return project.isCompleted ? .green : .secondary
    }
}

private extension ProjectBoardProject {
    var accessibilitySidebarLabel: String {
        let state = localizedDisplay(isArchived ? "Archived" : isCompleted ? "Completed" : "Active")
        let taskLabel = localizedTaskCount(taskCount)
        return "\(title), \(state), \(taskLabel)"
    }

    var sidebarDropTint: Color {
        if isArchived {
            return .secondary
        }
        return isCompleted ? .green : .blue
    }
}

extension ProjectTaskPriority {
    var color: Color {
        switch self {
        case .low:
            .secondary
        case .medium:
            .orange
        case .high:
            .red
        }
    }
}

extension ProjectTaskStatus {
    var tint: Color {
        switch self {
        case .backlog:
            .secondary
        case .planned:
            .blue
        case .inProgress:
            .purple
        case .blocked:
            .orange
        case .done:
            .green
        }
    }

    var systemImage: String {
        switch self {
        case .backlog:
            "tray"
        case .planned:
            "calendar.badge.clock"
        case .inProgress:
            "arrow.triangle.2.circlepath"
        case .blocked:
            "exclamationmark.octagon"
        case .done:
            "checkmark.circle"
        }
    }

    var previousStatus: ProjectTaskStatus? {
        guard let index = Self.allCases.firstIndex(of: self), index > Self.allCases.startIndex else {
            return nil
        }
        return Self.allCases[Self.allCases.index(before: index)]
    }

    var nextStatus: ProjectTaskStatus? {
        guard let index = Self.allCases.firstIndex(of: self) else {
            return nil
        }
        let nextIndex = Self.allCases.index(after: index)
        guard nextIndex < Self.allCases.endIndex else {
            return nil
        }
        return Self.allCases[nextIndex]
    }
}

/// Non-rendering commands for shortcuts that must stay available regardless of
/// sidebar focus. Explicit buttons keep every route statically auditable while
/// isolating their generic types from the already-large board view body.
private struct ProjectBoardKeyboardShortcutBridge: View {
    let openCommandPalette: () -> Void
    let selectDestination: (BoardPrimaryDestination) -> Void

    var body: some View {
        ZStack {
            Button("", action: openCommandPalette)
                .keyboardShortcut("k", modifiers: [.command])
            Button("") { selectDestination(.today) }
                .keyboardShortcut("1", modifiers: [.command])
            Button("") { selectDestination(.inbox) }
                .keyboardShortcut("2", modifiers: [.command])
            Button("") { selectDestination(.projects) }
                .keyboardShortcut("3", modifiers: [.command])
            Button("") { selectDestination(.review) }
                .keyboardShortcut("4", modifiers: [.command])
        }
        .hidden()
        .accessibilityHidden(true)
    }
}

extension ProjectPortfolioHealth {
    var tint: Color {
        switch self {
        case .onTrack:
            .green
        case .attention:
            .orange
        case .atRisk:
            .red
        case .completed:
            .blue
        }
    }

    var systemImage: String {
        switch self {
        case .onTrack:
            "checkmark.seal"
        case .attention:
            "exclamationmark.circle"
        case .atRisk:
            "exclamationmark.triangle"
        case .completed:
            "checkmark.circle"
        }
    }
}

extension ArtifactCreatedState {
    var label: String {
        switch self {
        case .expected:
            "Expected"
        case .created:
            "Created"
        case .missing:
            "Missing"
        }
    }

    var systemImage: String {
        switch self {
        case .expected:
            "doc.badge.clock"
        case .created:
            "doc.text.fill"
        case .missing:
            "doc.badge.exclamationmark"
        }
    }

    var tint: Color {
        switch self {
        case .expected:
            .blue
        case .created:
            .green
        case .missing:
            .orange
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
