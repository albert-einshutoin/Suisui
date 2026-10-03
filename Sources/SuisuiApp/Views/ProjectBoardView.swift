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
    // switch between compact and rail-heavy workflow surfaces. Widths come from
    // CockpitLayoutPolicy so launch / minimum / visual 1024 stay one ladder.
    static let defaultWidth = CGFloat(CockpitLayoutPolicy.defaultLaunchWindowWidth)
    static let defaultHeight: CGFloat = 760
    static let minWidth = CGFloat(CockpitLayoutPolicy.minimumWindowWidth)
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
    // Native NavigationSplitView otherwise expands the ideal width to roughly
    // 294pt on a 1448pt window. Capping it at the 240pt reference width keeps
    // the Today rail visible without making destination labels truncate.
    static let sidebarColumnMinWidth: CGFloat = 220
    static let sidebarColumnIdealWidth: CGFloat = 240
    static let sidebarColumnMaxWidth: CGFloat = 240
    // NavigationSplitView otherwise gives the detail column a large implicit
    // minimum. With the compact inspector open, that floor prevents the product
    // from reaching its supported 1024pt compact window width.
    static let detailColumnMinWidth: CGFloat = 440
    // Prefer the 1024pt detail remainder (≈784) so cockpit split rails and the
    // Today continuous rail stay beside primary content instead of clipping.
    static let detailColumnIdealWidth: CGFloat = 784
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

struct ProjectBoardMissedTaskFollowUpDateProvider: DateProvider {
    private let visualEvidenceReferenceDate: Date?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        visualEvidenceReferenceDate = VisualEvidenceRuntimeContext(
            environment: environment
        )?.referenceInstant
    }

    var now: Date {
        // Production launches retain the real system clock. Only the complete
        // visual-evidence context pins missed-task suggestions, preventing a
        // hosted run's weekday from rewriting deterministic queue content.
        visualEvidenceReferenceDate ?? SystemDateProvider().now
    }
}

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var settingsViewModel: AppSettingsViewModel
    @ObservedObject private var shortcutSettingsViewModel: ShortcutSettingsViewModel
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
    @AppStorage(SuisuiAppearancePreference.storageKey) private var appearancePreference: SuisuiAppearancePreference = .system
    @AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system
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
    @State private var knowledgePreview: KnowledgeFramePreview?
    @State private var selectedSmartListID: String?
    @State private var savedSmartLists: [SmartList] = []
    @State private var isPresentingSmartListEditor = false
    @State private var transientBoardRoute: BoardRoute?
    @State private var requestsInboxQuickAddFocus = false
    @State private var catchUpFocusRevision = 0
    @State private var consumedCatchUpFocusRevision = 0
    @State private var activeBoardRouteFocus: BoardRouteFocus?
    @State private var pendingDestinationPersistenceSuppression: ProjectBoardDestinationPersistenceSuppression?
    // Palette content hits reveal their task after the destination switch
    // settles, because applySelectedDestination clears task selection.
    @State private var pendingCommandPaletteRevealTaskID: Int64?

    init(
        viewModel: ProjectBoardViewModel,
        settingsViewModel: AppSettingsViewModel,
        shortcutSettingsViewModel: ShortcutSettingsViewModel,
        sceneID: UUID,
        restoresPrimaryPresentationState: Bool,
        sceneCoordinator: ProjectBoardSceneCoordinator = .shared,
        taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings = { .default },
        appSettings: @escaping () -> AppSettings = { .default },
        smartListStore: (any SmartListStore)? = AppRuntimeFactory.makeSmartListStoreIfAvailable(),
        commandPaletteContentSearch: CommandPaletteContentSearch? = CommandPaletteContentSearchFactory.make(),
        developmentAutomationReviewSession: @escaping (ActionPlan) -> ReviewSessionViewModel
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _settingsViewModel = ObservedObject(wrappedValue: settingsViewModel)
        _shortcutSettingsViewModel = ObservedObject(wrappedValue: shortcutSettingsViewModel)
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
        projectBoardOverlayChrome
    }

    @ViewBuilder
    private var projectBoardNavigationShell: some View {
        let sidebarMetrics = viewModel.derivedReadModels.sidebarMetrics
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectBoardSidebarView(
                route: boardRouteBinding,
                counts: ProjectBoardSidebarCounts(
                    today: sidebarMetrics.todayCount,
                    inbox: sidebarMetrics.inboxCount,
                    projects: sidebarMetrics.projectsCount,
                    schedule: sidebarMetrics.scheduleCount,
                    completed: sidebarMetrics.doneCount
                ),
                profileDisplayName: appSettings().normalizedForRuntime.profileDisplayName ?? "",
                planLabel: nil,
                onOpenSearch: { isCommandPaletteVisible = true },
                onAddTask: beginInboxQuickAddFromSidebar,
                onAddByVoice: openVoiceCommandFromBoardContext,
                onBlockTime: prepareScheduleDraftFromSidebar,
                onImportTasks: { isImportingTaskInterop = true }
            )
            .id(toolbarLayoutRefreshToken)
            .projectBoardSynchronizedColumnBounds()
            .navigationSplitViewColumnWidth(
                min: ProjectBoardLayoutMetrics.sidebarColumnMinWidth,
                ideal: ProjectBoardLayoutMetrics.sidebarColumnIdealWidth,
                max: ProjectBoardLayoutMetrics.sidebarColumnMaxWidth
            )
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
        .environment(\.cockpitAuthoritativeContentWidth, cockpitAuthoritativeContentWidth)
        .inspector(isPresented: wideInspectorBinding) {
            inspectorContent
                .inspectorColumnWidth(min: 240, ideal: 280, max: 420)
        }
    }

    @MainActor
    private func bootstrapProjectBoard() async {
        sceneCoordinator.register(sceneID: sceneID)
        restorePrimaryPresentationStateIfNeeded()
        columnVisibility = storedSidebarHidden ? .detailOnly : .all
        LaunchPerformanceSignposts.measureFirstBoardLoadOnce {
            viewModel.load()
        }
        LaunchPerformanceMilestones.record("command-ready")
        NotificationCenter.default.post(name: .suisuiProjectBoardCommandReady, object: nil)
        viewModel.scheduleMissedTaskDailyFollowUp(
            settings: appSettings(),
            dateProvider: ProjectBoardMissedTaskFollowUpDateProvider()
        )
        reloadSavedSmartLists()
        restoreSelectedDestinationIfNeeded()
        consumePendingSceneOpenRequests()
        LaunchPerformanceMilestones.record("today-ready")
    }

    private var projectBoardOverlayChrome: some View {
        projectBoardAttachmentChrome
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

    private var projectBoardAttachmentChrome: some View {
        projectBoardLifecycleChrome
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
            .sheet(item: $knowledgePreview) { preview in
                KnowledgeFramePreviewView(preview: preview)
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
    }

    private var projectBoardLifecycleChrome: some View {
        projectBoardToolbarChrome
            .task {
                await bootstrapProjectBoard()
            }
            .onDisappear {
                sceneCoordinator.unregister(sceneID: sceneID)
            }
            .modifier(ProjectBoardTodayRefreshLifecycleModifier {
                viewModel.refreshDerivedReadModels()
            })
            .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange)) { notification in
                let didReload = viewModel.reloadAfterChange(from: notification.object as? UUID)
                // Re-evaluate follow-up after every change, including one from
                // this scene: missed work can first appear later in the day.
                viewModel.scheduleMissedTaskDailyFollowUp(
                    settings: appSettings(),
                    dateProvider: ProjectBoardMissedTaskFollowUpDateProvider()
                )
                guard didReload else { return }
                restoreSelectedDestinationIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardShortcutRequested)) { notification in
                guard let request = notification.object as? ProjectBoardShortcutRequest,
                      request.sceneID == sceneID else {
                    return
                }
                switch request.action {
                case .commandPalette:
                    isCommandPaletteVisible = true
                case let .route(route):
                    if route == .voiceCommand {
                        openVoiceCommandFromBoardContext()
                    } else {
                        boardRouteBinding.wrappedValue = route
                    }
                }
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
            .onChange(of: selectedDestination) { previousDestination, destination in
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
                applySelectedDestination(
                    destination,
                    previousDestination: previousDestination
                )
                // Destination changes intentionally clear normal user selection; the
                // env-only override is reapplied so deterministic release evidence
                // can open Inbox with a seeded capture selected.
                applySelectedTaskOverrideIfNeeded()
                applyPendingCommandPaletteRevealIfNeeded()
            }
    }

    private var projectBoardToolbarChrome: some View {
        projectBoardNavigationShell
            .onReceive(NotificationCenter.default.publisher(for: .suisuiOpenBoardSettings)) { _ in
                navigateWithinScene(to: .settings)
            }
            .onReceive(NotificationCenter.default.publisher(for: .suisuiOpenBoardVoiceCommand)) { _ in
                openVoiceCommandFromBoardContext()
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
            // The Inbox reference surface owns its sort/filter controls in the
            // content header; hiding the global command toolbar keeps that review
            // surface aligned with the compact reference composition.
            .toolbar(
                selectedDestination == .inbox ? .hidden : .automatic,
                for: .windowToolbar
            )
            .background(
                ProjectBoardToolbarLayoutBridge(
                    columnVisibility: columnVisibility,
                    onToolbarLayoutChanged: refreshProjectBoardColumnsAfterToolbarDisplayModeChange,
                    onWindowWidthChanged: updateProjectBoardWindowWidth
                )
            )
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
        if route == .voiceCommand {
            storeVoiceConversationScopeFromBoardContext()
        }
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
        if route == .voiceCommand {
            NotificationCenter.default.post(
                name: .suisuiVoiceConversationScopeRequested,
                object: nil
            )
        }
    }

    @ViewBuilder
    private var routedProjectBoardContent: some View {
        let todaySettings = appSettings().normalizedForRuntime
        switch currentBoardRoute {
        case .review(.schedule):
            ScheduleWorkflowView(viewModel: viewModel)
        case .primary(.today), .primary(.inbox), .primary(.projects), .primary(.review),
             .project, .smartList, .review(.completed), .review(.assistantQueue),
             .review(.automationActivity):
            ProjectBoardWorkHubView(
                route: boardRouteBinding,
                smartLists: allSmartLists,
                assistantQueueCount: viewModel.assistantQueueSnapshot.needsAttentionCount,
                onCreateSmartList: { isPresentingSmartListEditor = true },
                onDeleteSmartList: deleteSmartList
            ) {
                workHubContent(todaySettings: todaySettings)
            }
        case .settings:
            embeddedSettingsWorkspace
        case .voiceCommand:
            embeddedVoiceWorkspace
        }
    }

    @ViewBuilder
    private func workHubContent(todaySettings: AppSettings) -> some View {
        switch currentBoardRoute {
        case .primary(.today):
            TodayWorkflowView(
                viewModel: viewModel,
                selectTodayTask: selectTodayTask,
                openInspectorForTodayRailTask: openInspectorForTodayRailTask,
                playDailyPlanningReadout: playDailyPlanningReadoutFromSettings,
                dashboardDisplayName: todaySettings.profileDisplayName ?? "",
                dashboardDailyCapacityMinutes: todaySettings.dailyWorkCapacityMinutes,
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
                },
                prefersContinuousRail: todayPrefersContinuousRail
            )
        case .primary(.inbox):
            InboxWorkflowView(
                viewModel: viewModel,
                selectInboxTask: selectInboxTask,
                requestsQuickAddFocus: requestsInboxQuickAddFocus,
                onQuickAddFocusConsumed: {
                    requestsInboxQuickAddFocus = false
                }
            )
        case .primary(.projects), .project:
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
        case .review(.completed):
            DoneWorkflowView(viewModel: viewModel, appSettings: appSettings())
        case .review(.automationActivity):
            ProjectWorkflowAutomationActivityView(viewModel: viewModel, appSettings: appSettings())
        case .review(.assistantQueue), .primary(.review):
            AssistantQueueWorkflowView(viewModel: viewModel)
        case .review(.schedule), .settings, .voiceCommand:
            EmptyView()
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
        case .primary, .review, .settings, .voiceCommand:
            EmptyView()
        }
    }

    private var embeddedSettingsWorkspace: some View {
        SuisuiSettingsWorkspace(
            settingsViewModel: settingsViewModel,
            shortcutSettingsViewModel: shortcutSettingsViewModel,
            appearancePreference: $appearancePreference,
            languagePreference: $languagePreference
        )
    }

    private var embeddedVoiceWorkspace: some View {
        VoiceCaptureWorkspaceHost()
    }

    private func openVoiceCommandFromBoardContext() {
        navigateWithinScene(to: .voiceCommand)
    }

    private func storeVoiceConversationScopeFromBoardContext() {
        let task = viewModel.selectedTask
        let projectID = task?.projectID ?? viewModel.selectedProject?.id
        let project = viewModel.snapshot.projects.first { $0.id == projectID }
        SuisuiVoiceConversationScopeBridge.store(
            .init(
                projectID: projectID,
                projectName: project?.title,
                taskID: task?.id,
                taskName: task?.title
            )
        )
    }

    private func beginInboxQuickAddFromSidebar() {
        requestsInboxQuickAddFocus = true
        navigateWithinScene(to: .primary(.inbox))
    }

    private func prepareScheduleDraftFromSidebar() {
        navigateWithinScene(to: .review(.schedule))
        _ = viewModel.prepareScheduleDraft(on: VisualEvidenceRuntimeContext.referenceDate())
    }

    private func createAndOpenProject() {
        guard let project = viewModel.createProject() else {
            return
        }
        navigateWithinScene(to: .project(project.id))
    }

    private func executeCommandPaletteAction(_ kind: CommandPaletteActionKind) {
        switch kind {
        case .createInboxTask(let draft):
            viewModel.createInboxTask(draft)
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
            openVoiceCommandFromBoardContext()
        case .openSettingsWindow:
            navigateWithinScene(to: .settings)
        case .revealTask(let taskID, let projectID, _):
            revealTaskFromCommandPalette(taskID: taskID, projectID: projectID)
        case .openKnowledgeFrame(let id, let name, let content):
            knowledgePreview = KnowledgeFramePreview(id: id, name: name, content: content)
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

    /// AppKit window width is authoritative for every cockpit desk; GeometryReader
    /// can under-report NavigationSplitView detail width and incorrectly stack
    /// secondary rails below the fold at 1024×676. Visual evidence always pins
    /// that contract, so publish the standard content width instead of a still-zero
    /// or mid-resize window width.
    private var cockpitAuthoritativeContentWidth: Double? {
        if VisualEvidenceRuntimeContext() != nil {
            return CockpitLayoutPolicy.standardContentWidth
        }
        guard projectBoardWindowWidth > 0 else {
            return nil
        }
        if columnVisibility == .detailOnly {
            return Double(projectBoardWindowWidth)
        }
        return CockpitLayoutPolicy.contentWidth(
            forWindowWidth: Double(projectBoardWindowWidth)
        )
    }

    private var todayPrefersContinuousRail: Bool? {
        guard let contentWidth = cockpitAuthoritativeContentWidth else {
            return nil
        }
        return CockpitLayoutPolicy.presentsSplitRail(contentWidth: contentWidth)
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
        guard restoresPrimaryPresentationState,
              !isPresentationPersistenceDisabled else { return }
        // SceneStorage keeps simultaneous windows isolated. OS window
        // restoration is deliberately disabled, so a primary-only copy carries
        // safe presentation preferences across a completely fresh launch.
        userRequestedInspector = primaryUserRequestedInspector
        storedSidebarHidden = primarySidebarHidden
    }

    private func persistPrimaryPresentationStateIfNeeded() {
        guard restoresPrimaryPresentationState,
              !isPresentationPersistenceDisabled else { return }
        primaryUserRequestedInspector = userRequestedInspector
        primarySidebarHidden = storedSidebarHidden
    }

    private var isPresentationPersistenceDisabled: Bool {
        // Evidence launches must not inherit or overwrite the developer's
        // real sidebar/inspector preference through AppStorage.
        ProcessInfo.processInfo.environment[
            "SUISUI_DISABLE_PROJECT_BOARD_PRESENTATION_PERSISTENCE"
        ] == "1"
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
        case .settings:
            .settings
        case .voiceCommand:
            .voiceCommand
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
        if VoiceEvidenceLaunch.shouldOpenOnLaunch {
            let route = BoardRoute.voiceCommand
            transientBoardRoute = route
            applyRouteToLegacyUI(route)
            applySelectedTaskOverrideIfNeeded()
            return
        }
        if SettingsEvidenceLaunch.shouldOpenOnLaunch {
            let route = BoardRoute.settings
            transientBoardRoute = route
            applyRouteToLegacyUI(route)
            applySelectedTaskOverrideIfNeeded()
            return
        }
        if ProjectBoardSelectionPersistence.environmentOverrideRawValue != nil,
           let transientBoardRoute {
            // Evidence launches may navigate within the same owned process.
            // Data-change notifications reload the board, but must not reset a
            // currently visible typed route back to the launch override.
            let route = validatedRoute(transientBoardRoute)
            self.transientBoardRoute = route
            applyRouteToLegacyUI(route)
            applySelectedTaskOverrideIfNeeded()
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
        case .primary(.review):
            return .review(.assistantQueue)
        case .project(let projectID):
            return viewModel.snapshot.projects.contains(where: { $0.id == projectID })
                ? route
                : .primary(.today)
        case .smartList(let smartListID):
            return allSmartLists.contains(where: { $0.id == smartListID })
                ? route
                : .primary(.today)
        case .primary, .review, .settings, .voiceCommand:
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
        case .settings, .voiceCommand:
            destination = nil
            smartListID = nil
        }
        selectedSmartListID = smartListID
        applyLegacyDestinationWithinScene(destination)
    }

    private func applyLegacyDestinationWithinScene(
        _ destination: ProjectBoardSidebarDestination?
    ) {
        let previousDestination = selectedDestination
        if previousDestination != destination {
            // SwiftUI invokes onChange after this mutation. Keep suppression
            // pending until that callback consumes it; resetting here would
            // let targeted payload routing overwrite the new-window default.
            pendingDestinationPersistenceSuppression = ProjectBoardDestinationPersistenceSuppression(
                destination: destination
            )
            selectedDestination = destination
        }
        applySelectedDestination(
            destination,
            previousDestination: previousDestination
        )
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
        case .primary, .project, .smartList, .review, .settings, .voiceCommand:
            break
        }
        // Acknowledge only after route state and any feature payload are
        // applied. Follow-up focus work can now wait on this exact request ID.
        sceneCoordinator.acknowledgeApplied(requestID: request.id)
    }

    private func applySelectedDestination(
        _ destination: ProjectBoardSidebarDestination?,
        previousDestination: ProjectBoardSidebarDestination?
    ) {
        // Data reloads may reapply the same scene destination. Only real
        // navigation invalidates the task context shown in the inspector.
        if previousDestination != destination {
            projectInspectorDevelopmentContext.handle(.destinationChanged)
        }
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
                voiceID: settings.selectedTTSVoiceID,
                provider: settings.ttsProvider
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
