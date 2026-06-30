import SoloPMCore
import Dispatch
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

private enum ProjectBoardLayoutMetrics {
    // Project Board keeps these metrics local because the split-view header,
    // Kanban columns, inspector, and inline composer are tuned as one surface.
    // Keeping the numbers named makes UI review catch accidental magic values
    // without forcing a premature app-wide design system abstraction.
    static let headerHeight: CGFloat = 44
    static let terminalPanelMinHeight: CGFloat = 220
    static let terminalPanelIdealHeight: CGFloat = 280
    static let terminalPanelMaxHeight: CGFloat = 360
    static let portfolioCardMinHeight: CGFloat = 230
    static let overviewPanelMinHeight: CGFloat = 170
    static let displayModePickerWidth: CGFloat = 252
    static let boardColumnWidth: CGFloat = 244
    static let emptyColumnMinHeight: CGFloat = 82
    static let inlinePriorityPickerWidth: CGFloat = 112
    static let taskMetadataChipMinWidth: CGFloat = 64
    static let taskMetadataChipMinHeight: CGFloat = 24
    static let taskStatusRailWidth: CGFloat = 4
    static let taskStatusRailHeight: CGFloat = 44
}

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: ProjectBoardViewModel
    private let taskAutomationSettings: () -> TaskAutoExecutionSettings
    @AppStorage(ProjectBoardSelectionPersistence.storageKey) private var persistedSelectedDestinationRawValue = ProjectBoardSelectionPersistence.defaultRawValue
    @State private var displayMode: ProjectBoardDisplayMode = .board
    @State private var selectedDestination: ProjectBoardSidebarDestination? = .today
    @State private var isInspectorPresented = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var toolbarLayoutRefreshToken = 0
    @State private var isTerminalPanelPresented = false
    @State private var isExportingTaskInterop = false
    @State private var isImportingTaskInterop = false
    @State private var taskInteropExportDocument = TaskInteropFileDocument(data: Data())

    init(
        viewModel: ProjectBoardViewModel,
        taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings = { .default }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.taskAutomationSettings = taskAutomationSettings
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $selectedDestination) {
                    Section {
                        ProjectBoardSidebarDestinationRow(destination: .inbox, count: viewModel.inboxTasks.count)
                            .tag(ProjectBoardSidebarDestination.inbox)
                        ProjectBoardSidebarDestinationRow(destination: .today, count: viewModel.todayTasks().count)
                            .tag(ProjectBoardSidebarDestination.today)
                        ProjectBoardSidebarDestinationRow(destination: .catchUp, count: viewModel.missedTaskReview().newlyMissedCount)
                            .tag(ProjectBoardSidebarDestination.catchUp)
                        ProjectBoardSidebarDestinationRow(destination: .schedule, count: viewModel.unscheduledScheduleTasks().count)
                            .tag(ProjectBoardSidebarDestination.schedule)
                        ProjectBoardSidebarDestinationRow(destination: .done, count: viewModel.doneAnalytics().completedTaskCount)
                            .tag(ProjectBoardSidebarDestination.done)
                    }

                    Section("Projects") {
                        ProjectBoardSidebarDestinationRow(
                            destination: .projects,
                            count: viewModel.projectPortfolioSummaries().count
                        )
                        .tag(ProjectBoardSidebarDestination.projects)

                        ForEach(activeSidebarProjects) { project in
                            ProjectSidebarRow(
                                project: project,
                                onSelect: { selectedDestination = .project(project.id) },
                                onMoveDroppedTasks: { rawIDs in
                                    viewModel.moveDroppedTasks(ids: rawIDs, toProjectID: project.id)
                                }
                            )
                            .tag(ProjectBoardSidebarDestination.project(project.id))
                        }
                    }

                    if !completedSidebarProjects.isEmpty {
                        Section("Completed") {
                            ForEach(completedSidebarProjects) { project in
                                ProjectSidebarRow(
                                    project: project,
                                    onSelect: { selectedDestination = .project(project.id) },
                                    onMoveDroppedTasks: { rawIDs in
                                        viewModel.moveDroppedTasks(ids: rawIDs, toProjectID: project.id)
                                    }
                                )
                                .tag(ProjectBoardSidebarDestination.project(project.id))
                            }
                        }
                    }

                    if viewModel.showsArchivedProjects {
                        Section("Archived") {
                            ForEach(archivedSidebarProjects) { project in
                                ProjectSidebarRow(
                                    project: project,
                                    onSelect: { selectedDestination = .project(project.id) },
                                    onMoveDroppedTasks: { rawIDs in
                                        viewModel.moveDroppedTasks(ids: rawIDs, toProjectID: project.id)
                                    }
                                )
                                .tag(ProjectBoardSidebarDestination.project(project.id))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("project-board-sidebar")
                .accessibilityLabel("Project navigation")
                .accessibilityHint("Select Inbox, Today, or a project before moving to the board detail.")

                Divider()

                Button {
                    viewModel.setShowsArchivedProjects(!viewModel.showsArchivedProjects)
                } label: {
                    Label(
                        "Show Archived",
                        systemImage: viewModel.showsArchivedProjects ? "checkmark.square" : "square"
                    )
                }
                .buttonStyle(.borderless)
                .help("Show archived projects")
                .accessibilityIdentifier("project-board-show-archived")
                .accessibilityLabel("Show archived projects")
                .accessibilityValue(viewModel.showsArchivedProjects ? "On" : "Off")
                .accessibilityHint("Shows archived projects in the sidebar without deleting local data.")
                .padding(.horizontal, 10)
                .padding(.top, 8)

                Button {
                    if let project = viewModel.createProject() {
                        selectedDestination = .project(project.id)
                    }
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add a project")
                .accessibilityIdentifier("project-board-add-project")
                .accessibilityLabel("Add Project")
                .accessibilityHint("Creates a new local project and selects it.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .id(toolbarLayoutRefreshToken)
            .projectBoardSynchronizedColumnBounds()
        } detail: {
            VStack(spacing: 0) {
                projectBoardHeaderBar
                Divider()

                Group {
                    if let errorMessage = viewModel.errorMessage {
                        ContentUnavailableView(
                            "Project Board Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else {
                        switch selectedDestination ?? .today {
                        case .inbox:
                            InboxWorkflowView(viewModel: viewModel)
                        case .today:
                            TodayWorkflowView(
                                viewModel: viewModel,
                                selectTodayTask: selectTodayTask,
                                openInspectorForTodayRailTask: openInspectorForTodayRailTask
                            )
                        case .catchUp:
                            CatchUpWorkflowView(viewModel: viewModel)
                        case .schedule:
                            ScheduleWorkflowView(viewModel: viewModel)
                        case .done:
                            DoneWorkflowView(viewModel: viewModel)
                        case .projects:
                            ProjectsPortfolioOverview(viewModel: viewModel) { projectID in
                                if viewModel.openProjectFromPortfolioCard(projectID: projectID) {
                                    selectedDestination = .project(projectID)
                                }
                            }
                        case .project(let projectID):
                            if let project = viewModel.snapshot.projects.first(where: { $0.id == projectID }) {
                                ProjectBoardDetail(
                                    project: project,
                                    displayMode: $displayMode,
                                    viewModel: viewModel
                                )
                            } else if viewModel.isEmptyProjectStateVisible {
                                ContentUnavailableView("No Projects", systemImage: "folder")
                            } else {
                                ContentUnavailableView("Project Not Found", systemImage: "folder.badge.questionmark")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isTerminalPanelPresented {
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
            .inspector(isPresented: inspectorBinding) {
                Group {
                    if let task = viewModel.selectedTask {
                        TaskInspectorView(
                            task: task,
                            viewModel: viewModel,
                            onClose: { inspectorBinding.wrappedValue = false }
                        )
                    } else if let project = selectedProjectForInspector {
                        ProjectInspectorView(
                            project: project,
                            viewModel: viewModel,
                            onClose: { inspectorBinding.wrappedValue = false }
                        )
                    } else {
                        EmptyView()
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .navigationTitle("SoloPM")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    toggleSidebarVisibility()
                } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help(sidebarToggleHelp)
                .accessibilityIdentifier("project-board-sidebar-toggle")
                .accessibilityLabel(sidebarToggleHelp)
            }
        }
        .toolbar(removing: .sidebarToggle)
        .background(
            ProjectBoardToolbarLayoutBridge(
                columnVisibility: columnVisibility,
                onToolbarLayoutChanged: refreshProjectBoardColumnsAfterToolbarDisplayModeChange
            )
        )
        .task {
            viewModel.load()
            restoreSelectedDestinationIfNeeded()
            consumePendingVoiceDailyPlanningReviewRequestIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
            viewModel.load()
            restoreSelectedDestinationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMVoiceDailyPlanningReviewRequested)) { notification in
            handleVoiceDailyPlanningReviewRequest(notification)
        }
        .onChange(of: selectedDestination) { _, destination in
            persistSelectedDestination(destination)
            applySelectedDestination(destination)
            // Destination changes intentionally clear normal user selection; the
            // env-only override is reapplied so deterministic release evidence
            // can open Inbox with a seeded capture selected.
            applySelectedTaskOverrideIfNeeded()
        }
        .onChange(of: viewModel.selectedTaskID) { _, selectedTaskID in
            if selectedTaskID != nil && selectedDestination != .today {
                isInspectorPresented = true
            }
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
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { isInspectorPresented && (viewModel.selectedTask != nil || selectedProjectForInspector != nil) },
            set: { isPresented in
                isInspectorPresented = isPresented
                if !isPresented {
                    viewModel.selectedTaskID = nil
                }
            }
        )
    }

    private var sidebarToggleHelp: String {
        columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar"
    }

    private var projectBoardHeaderBar: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 16)

            Menu {
                Button {
                    beginTaskInteropExport()
                } label: {
                    Label("Export Tasks", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("project-board-export-tasks")

                Button {
                    isImportingTaskInterop = true
                } label: {
                    Label("Import Tasks", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("project-board-import-tasks")

                Divider()

                Button {
                    viewModel.recordTaskInteropFileFailure(ProjectBoardIntegrationUnavailableError.googleCalendarOAuthNotConfigured)
                } label: {
                    Label("Google Calendar Sync", systemImage: "calendar.badge.plus")
                }
                .disabled(true)
                .help("Google Calendar sync requires Pro and OAuth authorization.")
            } label: {
                Label("Integrations", systemImage: "arrow.left.arrow.right")
                    .labelStyle(.titleAndIcon)
            }
            .help("Import, export, and sync task data")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Integrations")
            .accessibilityIdentifier("project-board-integrations-menu")

            Button {
                viewModel.prepareTaskAutomationReview(settings: taskAutomationSettings())
            } label: {
                Label("Review Task Automation", systemImage: "sparkles")
                    .labelStyle(.titleAndIcon)
            }
            .help("Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Review Task Automation")
            .accessibilityIdentifier("project-board-task-auto-execution-review")
            .accessibilityHint("Prepares review-only task automation from the configured priority, due-date, cadence, and daily budget settings.")

            Button {
                openWindow(id: "voice-capture")
            } label: {
                Label("Voice Command", systemImage: "mic")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Voice Command")
            .accessibilityIdentifier("project-board-voice-command")

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
            }
            .help("Open Settings")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("project-board-settings-link")

            Button {
                isTerminalPanelPresented.toggle()
            } label: {
                Label("Terminal", systemImage: "terminal")
                    .labelStyle(.titleAndIcon)
            }
            .keyboardShortcut("`", modifiers: [.control])
            .help("Terminal")
            .accessibilityLabel("Terminal")
            .accessibilityIdentifier("project-board-terminal-toggle")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .frame(
            maxWidth: .infinity,
            minHeight: ProjectBoardLayoutMetrics.headerHeight,
            maxHeight: ProjectBoardLayoutMetrics.headerHeight,
            alignment: .trailing
        )
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-header-bar")
    }

    private func toggleSidebarVisibility() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            refreshProjectBoardColumnsAfterToolbarDisplayModeChange()
        }
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

    private var terminalWorkingDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private func restoreSelectedDestinationIfNeeded() {
        let rawValue = ProjectBoardSelectionPersistence.environmentOverrideRawValue
            ?? persistedSelectedDestinationRawValue
        let destination = ProjectBoardSelectionPersistence.destination(
            from: rawValue,
            availableProjects: viewModel.snapshot.projects
        )
        selectedDestination = destination
        persistSelectedDestination(destination)
        applySelectedDestination(destination)
        applySelectedTaskOverrideIfNeeded()
    }

    private func persistSelectedDestination(_ destination: ProjectBoardSidebarDestination?) {
        guard ProjectBoardSelectionPersistence.environmentOverrideRawValue == nil else {
            return
        }
        guard let destination else {
            return
        }
        persistedSelectedDestinationRawValue = ProjectBoardSelectionPersistence.rawValue(for: destination)
    }

    private func applySelectedDestination(_ destination: ProjectBoardSidebarDestination?) {
        switch destination {
        case .project(let projectID):
            viewModel.selectedProjectID = projectID
            viewModel.selectedTaskID = nil
            isInspectorPresented = true
        case .inbox, .today, .catchUp, .schedule, .done, .projects, .none:
            viewModel.selectedTaskID = nil
            isInspectorPresented = false
        }
    }

    private func consumePendingVoiceDailyPlanningReviewRequestIfNeeded() {
        guard let transcript = SoloPMVoiceDailyPlanningReviewBridge.consumePendingSourceTranscript() else {
            return
        }
        handleVoiceDailyPlanningReviewRequest(sourceTranscript: transcript)
    }

    private func handleVoiceDailyPlanningReviewRequest(_ notification: Notification) {
        let transcript = SoloPMVoiceDailyPlanningReviewBridge.consumePendingSourceTranscript()
            ?? SoloPMVoiceDailyPlanningReviewBridge.sourceTranscript(from: notification)
        let sourceTranscript: String
        if let transcript, !transcript.isEmpty {
            sourceTranscript = transcript
        } else {
            sourceTranscript = String(localized: "Today daily planning review")
        }
        handleVoiceDailyPlanningReviewRequest(sourceTranscript: sourceTranscript)
    }

    private func handleVoiceDailyPlanningReviewRequest(sourceTranscript: String) {
        viewModel.load()
        _ = viewModel.prepareDailyPlanningReview(transcript: sourceTranscript)
        let summary = viewModel.missedTaskReview()
        selectedDestination = summary.newlyMissedCount > 0 ? .catchUp : .today
        persistSelectedDestination(selectedDestination)
        applySelectedDestination(selectedDestination)
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
        isInspectorPresented = true
    }

    private func selectTodayTask(_ task: ProjectBoardTask) {
        // Today row selection feeds the persistent assistant rail first. The
        // inspector still opens explicitly from the rail Edit action.
        viewModel.selectedTaskID = task.id
        isInspectorPresented = false
    }

    private func openInspectorForTodayRailTask(_ taskID: Int64) {
        viewModel.selectedTaskID = taskID
        guard viewModel.selectedTask != nil else {
            return
        }

        isInspectorPresented = true
    }

    private var taskInteropDefaultExportFilename: String {
        "solopm-tasks-\(Self.exportDateFormatter.string(from: Date())).json"
    }

    private func beginTaskInteropExport() {
        guard let data = viewModel.exportTaskInteropJSON() else {
            return
        }
        taskInteropExportDocument = TaskInteropFileDocument(data: data)
        isExportingTaskInterop = true
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

#if canImport(AppKit)
private struct ProjectBoardToolbarLayoutBridge: NSViewRepresentable {
    let columnVisibility: NavigationSplitViewVisibility
    let onToolbarLayoutChanged: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProjectBoardToolbarLayoutBridgeView(frame: .zero)
        view.onToolbarLayoutChanged = onToolbarLayoutChanged
        view.performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: true)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        _ = columnVisibility
        guard let view = nsView as? ProjectBoardToolbarLayoutBridgeView else {
            return
        }

        view.onToolbarLayoutChanged = onToolbarLayoutChanged
        view.installToolbarDisplayModeObservationIfNeeded()
        view.installToolbarDisplayModeMenuPruningIfNeeded()
        view.performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: true)
    }
}

private final class ProjectBoardToolbarLayoutBridgeView: NSView {
    var onToolbarLayoutChanged: (() -> Void)?
    private weak var observedToolbar: NSToolbar?
    private var toolbarDisplayModeObservation: NSKeyValueObservation?
    private var isToolbarDisplayModeMenuPruningInstalled = false
    private var observedToolbarDisplayMode: NSToolbar.DisplayMode?
    private var isPerformingToolbarLayoutPass = false
    private var didScheduleInitialToolbarLayoutStabilization = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        installToolbarDisplayModeObservationIfNeeded()
        installToolbarDisplayModeMenuPruningIfNeeded()
        performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: true)
        scheduleInitialProjectBoardToolbarLayoutStabilizationIfNeeded()
    }

    override func layout() {
        super.layout()
        performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: false)
    }

    private func removeNativeSidebarToggle(in toolbar: NSToolbar) {
        let removalIndexes = ProjectBoardToolbarLayoutPolicy.nativeSidebarRemovalIndexes(
            in: toolbar.projectBoardLayoutItems
        )

        // Keep toolbar display modes user-adaptive; only remove the native
        // sidebar item and tracking separator that visually drift in this
        // SwiftUI-hosted split view.
        for index in removalIndexes.reversed() {
            toolbar.removeItem(at: index)
        }
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
                    self.reconcileToolbarDisplayModeChangeSynchronously()
                }
            } else {
                DispatchQueue.main.async {
                    self.reconcileToolbarDisplayModeChangeSynchronously()
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
            // by ADR 0009, and user-triggered display-mode/sidebar changes run synchronously.
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: false)
            }
        }
    }

    private func reconcileToolbarDisplayModeChangeSynchronously() {
        guard let toolbar = observedToolbar ?? window?.toolbar,
              observedToolbarDisplayMode != toolbar.displayMode else {
            return
        }

        _ = enforceProjectBoardSupportedToolbarDisplayMode(toolbar)
        observedToolbarDisplayMode = toolbar.displayMode
        performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: false)
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

    func performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: Bool) {
        guard isPerformingToolbarLayoutPass == false else {
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

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            window?.titleVisibility = .hidden
            toolbar.centeredItemIdentifier = nil
            _ = enforceProjectBoardSupportedToolbarDisplayMode(toolbar)
            removeNativeSidebarToggle(in: toolbar)
            flushProjectBoardWindowLayout()
        }

        // NSToolbar display-mode changes come from AppKit context menus, outside
        // SwiftUI state. Mark the host dirty and bump SwiftUI state so the
        // sidebar and detail columns recalculate their bounds together.
        onToolbarLayoutChanged?()
    }

    private func flushProjectBoardWindowLayout() {
        window?.contentView?.needsLayout = true
        window?.contentView?.layoutSubtreeIfNeeded()
        window?.contentView?.needsDisplay = true
        window?.displayIfNeeded()
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

            self.performSynchronousProjectBoardToolbarLayoutPass(allowRetryIfToolbarMissing: false)
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

    var body: some View {
        EmptyView()
    }
}
#endif

extension Notification.Name {
    static let soloPMProjectBoardDidChange = Notification.Name("dev.solopm.projectBoardDidChange")
    static let soloPMVoiceDailyPlanningReviewRequested = Notification.Name("dev.solopm.voiceDailyPlanningReviewRequested")
}

@MainActor
enum SoloPMVoiceDailyPlanningReviewBridge {
    static let sourceTranscriptUserInfoKey = "sourceTranscript"
    private static var pendingSourceTranscript: String?

    static func storePendingSourceTranscript(_ sourceTranscript: String) {
        pendingSourceTranscript = normalized(sourceTranscript)
    }

    static func consumePendingSourceTranscript() -> String? {
        defer { pendingSourceTranscript = nil }
        return pendingSourceTranscript
    }

    static func sourceTranscript(from notification: Notification) -> String? {
        guard let value = notification.userInfo?[sourceTranscriptUserInfoKey] as? String else {
            return nil
        }
        return normalized(value)
    }

    private static func normalized(_ sourceTranscript: String) -> String {
        sourceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ProjectBoardIntegrationUnavailableError: Error {
    case googleCalendarOAuthNotConfigured
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

private enum ProjectBoardDisplayMode: String, CaseIterable, Identifiable {
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

private enum ProjectPortfolioFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case overdue
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .active:
            "Active"
        case .overdue:
            "Overdue"
        case .completed:
            "Completed"
        }
    }
}

private enum ProjectPortfolioSort: String, CaseIterable, Identifiable {
    case risk
    case progress
    case due

    var id: String { rawValue }

    var title: String {
        switch self {
        case .risk:
            "Risk"
        case .progress:
            "Progress"
        case .due:
            "Next Due"
        }
    }
}

private struct ProjectsPortfolioOverview: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onOpenProject: (Int64) -> Void
    @State private var filter: ProjectPortfolioFilter = .all
    @State private var sort: ProjectPortfolioSort = .risk

    private var summaries: [ProjectPortfolioSummary] {
        sorted(filtered(viewModel.projectPortfolioSummaries()))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    ProjectPortfolioHeader(
                        title: "Projects",
                        subtitle: String(format: String(localized: "%d projects compared"), summaries.count),
                        systemImage: "folder.circle"
                    )
                    Spacer(minLength: 12)
                    controls
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProjectPortfolioHeader(
                        title: "Projects",
                        subtitle: String(format: String(localized: "%d projects compared"), summaries.count),
                        systemImage: "folder.circle"
                    )
                    controls
                }
            }

            if summaries.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Create a project to compare progress, risk, and next due work.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(summaries) { summary in
                            ProjectPortfolioCard(summary: summary) {
                                onOpenProject(summary.projectID)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-portfolio-overview")
        .accessibilityLabel("Projects portfolio overview")
        .accessibilityHint("Compares local project progress, risk, due dates, and next actions.")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Project Filter", selection: $filter) {
                ForEach(ProjectPortfolioFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.title)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .accessibilityIdentifier("projects-portfolio-filter")

            Menu {
                Picker("Sort Projects", selection: $sort) {
                    ForEach(ProjectPortfolioSort.allCases) { sort in
                        Text(LocalizedStringKey(sort.title)).tag(sort)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort projects")
            .accessibilityIdentifier("projects-portfolio-sort")
        }
    }

    private func filtered(_ summaries: [ProjectPortfolioSummary]) -> [ProjectPortfolioSummary] {
        summaries.filter { summary in
            switch filter {
            case .all:
                return true
            case .active:
                return summary.health != .completed
            case .overdue:
                return summary.overdueTaskCount > 0
            case .completed:
                return summary.health == .completed
            }
        }
    }

    private func sorted(_ summaries: [ProjectPortfolioSummary]) -> [ProjectPortfolioSummary] {
        switch sort {
        case .risk:
            return summaries
        case .progress:
            return summaries.sorted {
                if $0.progress == $1.progress {
                    return $0.projectID > $1.projectID
                }
                return $0.progress < $1.progress
            }
        case .due:
            return summaries.sorted {
                ($0.nextDueAt ?? "9999-12-31") < ($1.nextDueAt ?? "9999-12-31")
            }
        }
    }
}

private struct ProjectPortfolioHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .font(.title2)
        }
    }
}

private struct ProjectPortfolioCard: View {
    let summary: ProjectPortfolioSummary
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(summary.title)
                    Label(localizedHealthTitle, systemImage: summary.health.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.health.tint)
                }
                Spacer(minLength: 8)
                Text(percentLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            ProgressView(value: summary.progress)
                .tint(summary.health.tint)
                .accessibilityLabel("Project progress")
                .accessibilityValue(percentLabel)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 6) {
                metric("Open", value: summary.openTaskCount, systemImage: "tray")
                metric("Done", value: summary.doneTaskCount, systemImage: "checkmark.circle")
                metric("Blocked", value: summary.blockedTaskCount, systemImage: "exclamationmark.octagon")
                metric("Overdue", value: summary.overdueTaskCount, systemImage: "clock.badge.exclamationmark")
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(summary.nextDueAt ?? String(localized: "No due date"), systemImage: "calendar")
                Label(localizedRiskReason, systemImage: "heart.text.square")
                Label(summary.nextActionTitle, systemImage: "arrow.right.circle")
                Label(localizedHealthRuleDescription, systemImage: "checklist")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpen) {
                Label("Open Project", systemImage: "arrow.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open project detail")
            .accessibilityIdentifier("projects-portfolio-open-\(summary.projectID)")
            .accessibilityHint("Opens the selected project detail without changing task status.")
        }
        .padding(12)
        .frame(minHeight: ProjectBoardLayoutMetrics.portfolioCardMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(summary.health.tint.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-portfolio-card-\(summary.projectID)")
        .accessibilityLabel(String(format: String(localized: "Project %@"), summary.title))
        .accessibilityValue("\(localizedHealthTitle), \(percentLabel), \(localizedRiskReason)")
    }

    private var percentLabel: String {
        "\(Int((summary.progress * 100).rounded()))%"
    }

    private var localizedHealthTitle: String {
        String(localized: String.LocalizationValue(summary.health.title))
    }

    private var localizedHealthRuleDescription: String {
        String(localized: String.LocalizationValue(summary.localHealthRuleDescription))
    }

    private var localizedRiskReason: String {
        var reasons: [String] = []
        if summary.blockedTaskCount > 0 {
            reasons.append(String(format: String(localized: "%d blocked"), summary.blockedTaskCount))
        }
        if summary.overdueTaskCount > 0 {
            reasons.append(String(format: String(localized: "%d overdue"), summary.overdueTaskCount))
        }
        if !reasons.isEmpty {
            return reasons.joined(separator: ", ")
        }
        switch summary.health {
        case .completed:
            return String(localized: "All tracked tasks are done.")
        case .attention:
            return String(localized: "Progress is below 25% with open work.")
        case .onTrack:
            return String(localized: "No blocked or overdue open tasks.")
        case .atRisk:
            return String(localized: "Local risk rule detected schedule pressure.")
        }
    }

    private func metric(_ title: String, value: Int, systemImage: String) -> some View {
        Label {
            Text("\(value) \(String(localized: String.LocalizationValue(title)))")
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct ProjectBoardDetail: View {
    let project: ProjectBoardProject
    @Binding var displayMode: ProjectBoardDisplayMode
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var composingStatus: ProjectTaskStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    ProjectHeaderSummary(project: project)

                    Spacer(minLength: 12)

                    ProjectHeaderActions(
                        project: project,
                        displayMode: $displayMode,
                        onAddTask: { startComposingTask() }
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProjectHeaderSummary(project: project)

                    ProjectHeaderActions(
                        project: project,
                        displayMode: $displayMode,
                        onAddTask: { startComposingTask() }
                    )
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let integrationStatusMessage = viewModel.integrationStatusMessage {
                Label(integrationStatusMessage, systemImage: "arrow.left.arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("project-board-integration-status")
            }

            if project.isArchived {
                ArchivedProjectReadOnlyState()
            } else {
                switch displayMode {
                case .overview:
                    ProjectDetailOverview(
                        project: project,
                        viewModel: viewModel,
                        onAddTask: { startComposingTask() }
                    )
                case .board:
                    ProjectKanbanBoard(
                        project: project,
                        composingStatus: $composingStatus,
                        viewModel: viewModel
                    )
                case .list:
                    ProjectTaskList(project: project, viewModel: viewModel)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-detail")
        .accessibilityLabel("Project board for \(project.title)")
        .accessibilityHint("Review project tasks, open a task card, then use the inspector for edits.")
        .onChange(of: project.isArchived) { _, isArchived in
            if isArchived {
                composingStatus = nil
                viewModel.selectedTaskID = nil
            }
        }
    }

    private func startComposingTask(status: ProjectTaskStatus = .backlog) {
        displayMode = .board
        composingStatus = status
    }
}

private struct ArchivedProjectReadOnlyState: View {
    var body: some View {
        ContentUnavailableView(
            "Archived Project",
            systemImage: "archivebox",
            description: Text("Restore this project to edit tasks or include it in active deadline summaries.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProjectDetailOverview: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onAddTask: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProjectProgressOverview(project: project)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ProjectTaskSnapshotSection(project: project, viewModel: viewModel, onAddTask: onAddTask)
                    ProjectMilestoneSection(project: project, viewModel: viewModel)
                    ProjectArtifactSection(project: project, viewModel: viewModel)
                    ProjectTimelineSection(project: project)
                    ProjectAssistantPanel(project: project, viewModel: viewModel)
                    ProjectLocalSuggestionPanel(project: project, viewModel: viewModel)
                }
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.visible)
    }
}

private struct ProjectProgressOverview: View {
    let project: ProjectBoardProject

    private var completedCount: Int {
        project.tasks.filter { $0.status == .done }.count
    }

    private var openCount: Int {
        project.tasks.filter { $0.status != .done }.count
    }

    private var blockedCount: Int {
        project.tasks.filter { $0.status == .blocked }.count
    }

    private var progress: Double {
        guard project.taskCount > 0 else {
            return 0
        }
        return Double(completedCount) / Double(project.taskCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label("Progress", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    metricBadges
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    metricBadges
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var metricBadges: some View {
        ProjectMetricBadge(label: "Open", value: openCount, tint: .blue)
        ProjectMetricBadge(label: "Done", value: completedCount, tint: .green)
        ProjectMetricBadge(label: "Blocked", value: blockedCount, tint: .orange)
        ProjectMetricBadge(label: "Milestones", value: project.milestones.count, tint: .teal)
        ProjectMetricBadge(label: "Artifacts", value: project.artifacts.count, tint: .purple)
    }
}

private struct ProjectMetricBadge: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
            Text(LocalizedStringKey(label))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 72, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectTaskSnapshotSection: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onAddTask: () -> Void

    private var openTasks: [ProjectBoardTask] {
        project.tasks
            .filter { $0.status != .done }
            .sorted { lhs, rhs in
                switch (lhs.dueAt, rhs.dueAt) {
                case let (lhsDue?, rhsDue?) where lhsDue != rhsDue:
                    return lhsDue < rhsDue
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.id > rhs.id
                }
            }
    }

    var body: some View {
        ProjectOverviewPanel(title: "Tasks", systemImage: "checklist") {
            if openTasks.isEmpty {
                Text("No open tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(openTasks.prefix(5)) { task in
                    Button {
                        viewModel.selectedTaskID = task.id
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: task.status.systemImage)
                                .foregroundStyle(task.status.tint)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Text(task.dueLabel ?? localizedDisplay(task.status.title))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Label {
                                Text(LocalizedStringKey(task.priority.label))
                            } icon: {
                                Image(systemName: "flag")
                            }
                                .labelStyle(.iconOnly)
                                .foregroundStyle(task.priority.color)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(task.title)
                    .accessibilityIdentifier("project-overview-task-open-\(task.id)")
                    .accessibilityLabel("Open task \(task.title)")
                    .accessibilityHint("Opens the task inspector from the project overview.")
                }
            }

            Button(action: onAddTask) {
                Label("Add Task", systemImage: "plus")
            }
            .controlSize(.small)
            .help("Add task to \(project.title)")
            .accessibilityIdentifier("project-overview-add-task")
            .accessibilityLabel("Add task to \(project.title)")
            .accessibilityHint("Opens the inline composer for a new local task.")
        }
    }
}

private struct ProjectMilestoneSection: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var milestoneTitle = ""
    @State private var milestoneDueAt = ""

    var body: some View {
        ProjectOverviewPanel(title: "Milestones", systemImage: "flag.checkered") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    milestoneTitleField
                    milestoneDueField
                    addButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    milestoneTitleField
                    milestoneDueField
                    addButton
                }
            }

            if project.milestones.isEmpty {
                Text("No milestones yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(project.milestones.prefix(4)) { milestone in
                    HStack(spacing: 8) {
                        Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "flag")
                            .foregroundStyle(milestone.isCompleted ? .green : .teal)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(milestone.dueAt ?? String(localized: "No due date"))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            _ = viewModel.completeProjectMilestone(id: milestone.id, projectID: project.id)
                        } label: {
                            Label("Complete milestone", systemImage: "checkmark.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(project.isArchived || milestone.isCompleted)
                        .help("Complete milestone")
                        .accessibilityIdentifier("project-milestone-complete-\(milestone.id)")
                        .accessibilityLabel("Complete milestone \(milestone.title)")
                        .accessibilityHint("Marks this local project milestone as complete.")
                    }
                }
            }
        }
    }

    private func addMilestone() {
        guard viewModel.createProjectMilestone(
            title: milestoneTitle,
            dueAt: milestoneDueAt,
            projectID: project.id
        ) != nil else {
            return
        }
        milestoneTitle = ""
        milestoneDueAt = ""
    }

    private var milestoneTitleField: some View {
        TextField("Milestone title", text: $milestoneTitle)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(addMilestone)
            .accessibilityIdentifier("project-milestone-title")
            .accessibilityLabel("Milestone title")
            .accessibilityHint("Enter a local milestone title for this project.")
    }

    private var milestoneDueField: some View {
        TextField("Due date", text: $milestoneDueAt)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(addMilestone)
            .accessibilityIdentifier("project-milestone-due")
            .accessibilityLabel("Milestone due date")
            .accessibilityHint("Optional local milestone due date.")
    }

    private var addButton: some View {
        Button(action: addMilestone) {
            Label("Add Milestone", systemImage: "plus")
        }
        .controlSize(.small)
        .disabled(project.isArchived || milestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("project-milestone-add")
        .accessibilityHint("Adds a local milestone without creating a task.")
    }
}

private struct ProjectArtifactSection: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var artifactPath = ""

    var body: some View {
        ProjectOverviewPanel(title: "Artifacts", systemImage: "doc.text") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    artifactPathField
                    trackArtifactButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    artifactPathField
                    trackArtifactButton
                }
            }

            if project.artifacts.isEmpty {
                Text("No tracked artifacts linked to this project")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(project.artifacts.prefix(4)) { artifact in
                    HStack(spacing: 8) {
                        Image(systemName: artifact.createdState.systemImage)
                            .foregroundStyle(artifact.createdState.tint)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: artifact.expectedPath).lastPathComponent)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(artifact.expectedPath)
                            Text(LocalizedStringKey(artifact.createdState.label))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        artifactRemoveButton(for: artifact)
                    }
                }
            }
        }
    }

    private func trackArtifact() {
        guard viewModel.createProjectArtifact(expectedPath: artifactPath, projectID: project.id) != nil else {
            return
        }
        artifactPath = ""
    }

    private var artifactPathField: some View {
        TextField("Expected artifact path", text: $artifactPath)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(trackArtifact)
            .accessibilityIdentifier("project-artifact-path")
            .accessibilityLabel("Track artifact path")
            .accessibilityHint("Enter an absolute local path to track as an expected project artifact.")
    }

    private var trackArtifactButton: some View {
        Button(action: trackArtifact) {
            Label("Track Artifact", systemImage: "link.badge.plus")
        }
        .controlSize(.small)
        .disabled(project.isArchived || artifactPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("project-artifact-track")
        .accessibilityLabel("Track artifact link")
        .accessibilityHint("Adds an expected artifact link to the selected project in the local SoloPM database.")
    }

    private func artifactRemoveButton(for artifact: ProjectBoardArtifact) -> some View {
        Button {
            _ = viewModel.deleteProjectArtifact(id: artifact.id, projectID: project.id)
        } label: {
            Label("Remove artifact link", systemImage: "xmark.circle")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .disabled(project.isArchived)
        .help("Remove artifact link without deleting the local file")
        .accessibilityIdentifier("project-artifact-remove-\(artifact.id)")
        .accessibilityLabel("Remove artifact link")
        .accessibilityHint("Removes this local SoloPM artifact link without deleting the file.")
    }
}

private struct ProjectTimelineSection: View {
    let project: ProjectBoardProject

    private var timelineItems: [ProjectTimelineItem] {
        let taskItems = project.tasks
            .compactMap { task -> ProjectTimelineItem? in
                guard let dueAt = task.dueAt else {
                    return nil
                }
                return .task(task, dueAt: dueAt)
            }
        let milestoneItems = project.milestones
            .compactMap { milestone -> ProjectTimelineItem? in
                guard let dueAt = milestone.dueAt else {
                    return nil
                }
                return .milestone(milestone, dueAt: dueAt)
            }
        return (taskItems + milestoneItems).sorted { lhs, rhs in
            if lhs.dueAt == rhs.dueAt {
                return lhs.id < rhs.id
            }
            return lhs.dueAt < rhs.dueAt
        }
    }

    var body: some View {
        ProjectOverviewPanel(title: "Timeline", systemImage: "calendar") {
            if timelineItems.isEmpty {
                Text("No due dates yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(timelineItems.prefix(5)) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.tint)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(item.dueAt)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(item.title)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Project timeline item \(item.title)")
                    .accessibilityValue(item.dueAt)
                }
            }
        }
    }
}

private enum ProjectTimelineItem: Identifiable {
    case task(ProjectBoardTask, dueAt: String)
    case milestone(ProjectBoardMilestone, dueAt: String)

    var id: String {
        switch self {
        case .task(let task, _):
            "task-\(task.id)"
        case .milestone(let milestone, _):
            "milestone-\(milestone.id)"
        }
    }

    var title: String {
        switch self {
        case .task(let task, _):
            task.title
        case .milestone(let milestone, _):
            milestone.title
        }
    }

    var dueAt: String {
        switch self {
        case .task(_, let dueAt), .milestone(_, let dueAt):
            dueAt
        }
    }

    var tint: Color {
        switch self {
        case .task(let task, _):
            task.status.tint
        case .milestone(let milestone, _):
            milestone.isCompleted ? .green : .teal
        }
    }
}

private struct ProjectAssistantPanel: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var question = ""

    var body: some View {
        ProjectOverviewPanel(title: "Assistant", systemImage: "bubble.left.and.text.bubble.right") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    questionField
                    askButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    questionField
                    askButton
                }
            }

            if let answer = viewModel.projectAssistantAnswer, answer.projectID == project.id {
                Text(answer.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project-assistant-answer")

                HStack(spacing: 8) {
                    Label(answer.suggestedActionTitle, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button {
                        _ = viewModel.prepareProjectAssistantSuggestedActionForReview(projectID: project.id)
                    } label: {
                        Label("Review Action", systemImage: "doc.text.magnifyingglass")
                    }
                    .controlSize(.small)
                    .help("Prepare suggested action for review")
                    .accessibilityIdentifier("project-assistant-review-action")
                    .accessibilityHint("Prepares the local assistant suggestion for review without writing task status.")
                }
            } else {
                Text("Ask for a local next step without contacting an external LLM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let draft = viewModel.projectAssistantReviewDraft, draft.projectID == project.id {
                Label(draft.suggestedActionTitle, systemImage: "doc.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("project-assistant-review-draft")
            }
        }
    }

    private func ask() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        _ = viewModel.answerProjectAssistantQuestion(trimmed, projectID: project.id)
    }

    private var questionField: some View {
        TextField("Ask about this project", text: $question)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(ask)
            .accessibilityIdentifier("project-assistant-question")
            .accessibilityLabel("Project assistant question")
            .accessibilityHint("Asks the local project assistant for a next step without external LLM execution.")
    }

    private var askButton: some View {
        Button(action: ask) {
            Label("Ask", systemImage: "paperplane")
        }
        .controlSize(.small)
        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("project-assistant-ask")
        .accessibilityHint("Generates a local assistant answer for this project.")
    }
}

private struct ProjectLocalSuggestionPanel: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var suggestedTask: ProjectBoardTask? {
        project.tasks.first { $0.status == .blocked }
            ?? project.tasks.first { $0.status != .done && $0.priority == .high }
            ?? project.tasks.filter { $0.status != .done }.sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") }.first
    }

    var body: some View {
        ProjectOverviewPanel(title: "Local Suggestions", systemImage: "sparkles") {
            if let suggestedTask {
                Text(suggestionText(for: suggestedTask))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    Button {
                        viewModel.selectedTaskID = suggestedTask.id
                    } label: {
                        Label("Open Task", systemImage: "sidebar.right")
                    }
                    .controlSize(.small)
                    .help("Open the suggested task")
                    .accessibilityIdentifier("project-local-suggestion-open-task")
                    .accessibilityHint("Opens the suggested task in the inspector.")

                    if suggestedTask.status == .blocked {
                        Button {
                            _ = viewModel.answerProjectAssistantQuestion("Review blocked task", projectID: project.id)
                            _ = viewModel.prepareProjectAssistantSuggestedActionForReview(projectID: project.id)
                        } label: {
                            Label("Review Action", systemImage: "doc.text.magnifyingglass")
                        }
                        .controlSize(.small)
                        .help("Prepare suggested action for review")
                        .accessibilityIdentifier("project-local-suggestion-review-action")
                        .accessibilityHint("Prepares the suggested blocked task action for review without writing task status.")
                    }
                }
            } else {
                Text("No open work needs attention.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func suggestionText(for task: ProjectBoardTask) -> String {
        if task.status == .blocked {
            return localizedDisplay("%@ is blocked. Resolve it before adding more work.", task.title)
        }
        if task.priority == .high {
            return localizedDisplay("%@ is high priority. Make it the next focused task.", task.title)
        }
        if let dueAt = task.dueAt {
            return localizedDisplay("%@ is the next due task at %@.", task.title, dueAt)
        }
        return localizedDisplay("Continue with %@.", task.title)
    }
}

private struct ProjectOverviewPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: ProjectBoardLayoutMetrics.overviewPanelMinHeight, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectHeaderSummary: View {
    let project: ProjectBoardProject

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(project.title)

                HStack(spacing: 8) {
                    Text(project.subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)

                    if project.isCompleted {
                        Label("Completed", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .lineLimit(1)
                    }
                }
            }
        } icon: {
            Image(systemName: project.isArchived ? "archivebox" : "folder")
                .foregroundStyle(project.isCompleted ? .green : .secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.title)
        .accessibilityValue(project.subtitle)
        .accessibilitySortPriority(3)
    }
}

private struct ProjectHeaderActions: View {
    let project: ProjectBoardProject
    @Binding var displayMode: ProjectBoardDisplayMode
    let onAddTask: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                viewPicker
                addTaskButton
            }

            VStack(alignment: .leading, spacing: 8) {
                viewPicker
                addTaskButton
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project view actions")
        .accessibilitySortPriority(1)
    }

    private var viewPicker: some View {
        Picker("View", selection: $displayMode) {
            ForEach(ProjectBoardDisplayMode.allCases) { mode in
                Label {
                    Text(LocalizedStringKey(mode.label))
                } icon: {
                    Image(systemName: mode.systemImage)
                }
                .tag(mode)
                .accessibilityIdentifier("project-display-mode-\(mode.rawValue)")
                .accessibilityLabel(LocalizedStringKey(mode.label))
            }
        }
        .pickerStyle(.segmented)
        .frame(width: ProjectBoardLayoutMetrics.displayModePickerWidth)
    }

    private var addTaskButton: some View {
        Button(action: onAddTask) {
            Label("Add Task", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(project.isArchived)
        .help("Add task to \(project.title)")
        .accessibilityIdentifier("project-header-add-task")
        .accessibilityLabel("Add task to \(project.title)")
        .accessibilityHint("Opens the inline composer for a new local task.")
    }
}

private struct ProjectKanbanBoard: View {
    let project: ProjectBoardProject
    @Binding var composingStatus: ProjectTaskStatus?
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(project.columns) { column in
                    BoardColumnView(
                        column: column,
                        isComposing: composingStatus == column.status,
                        selectedTaskID: viewModel.selectedTaskID,
                        onStartComposing: { composingStatus = column.status },
                        onCancelComposing: { composingStatus = nil },
                        onCreateTask: { title, detail, priority, dueAt in
                            viewModel.createTask(
                                title: title,
                                detail: detail,
                                projectID: project.id,
                                status: column.status,
                                priority: priority,
                                dueAt: dueAt
                            )
                            composingStatus = nil
                        },
                        onSelectTask: { viewModel.selectedTaskID = $0 },
                        onMoveTask: { taskID, status in
                            viewModel.moveTask(id: taskID, to: status)
                        },
                        onMoveDroppedTasks: { rawIDs, status in
                            viewModel.moveDroppedTasks(ids: rawIDs, to: status)
                        }
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .defaultScrollAnchor(.topLeading)
        .scrollIndicators(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-kanban-board")
        .accessibilityLabel("Kanban board for \(project.title)")
        .accessibilityHint("Open a task card, use status controls, or move tasks between columns.")
        .accessibilitySortPriority(2)
    }
}

private struct BoardColumnView: View {
    let column: ProjectBoardColumn
    let isComposing: Bool
    let selectedTaskID: Int64?
    let onStartComposing: () -> Void
    let onCancelComposing: () -> Void
    let onCreateTask: (String, String, ProjectTaskPriority, String?) -> Void
    let onSelectTask: (Int64) -> Void
    let onMoveTask: (Int64, ProjectTaskStatus) -> Void
    let onMoveDroppedTasks: ([String], ProjectTaskStatus) -> Bool

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label {
                    Text(LocalizedStringKey(column.title))
                } icon: {
                    Image(systemName: column.status.systemImage)
                }
                    .font(.headline)
                    .foregroundStyle(column.status.tint)
                Spacer()
                StatusCountBadge(count: column.tasks.count, tint: column.status.tint)
                Button(action: onStartComposing) {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Add task to \(column.title)")
                .accessibilityLabel("Add task to \(column.title)")
            }

            if isDropTargeted {
                Label("Drop to move to \(column.title)", systemImage: "arrow.down.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(column.status.tint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(column.status.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            if isComposing {
                InlineTaskComposer(
                    status: column.status,
                    onCancel: onCancelComposing,
                    onCreate: onCreateTask
                )
            }

            if column.tasks.isEmpty && !isComposing {
                Button(action: onStartComposing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(column.status.tint)
                        Text("No tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: ProjectBoardLayoutMetrics.emptyColumnMinHeight, alignment: .topLeading)
                    .padding(10)
                    .background(column.status.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(column.status.tint.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .buttonStyle(.plain)
                .help("Add task to \(column.title)")
                .accessibilityLabel("Add task to empty \(column.title) column")
            } else {
                ForEach(column.tasks) { task in
                    taskRow(task)
                }
            }
        }
        .frame(width: ProjectBoardLayoutMetrics.boardColumnWidth, alignment: .topLeading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? column.status.tint.opacity(0.72) : Color.secondary.opacity(0.14), lineWidth: isDropTargeted ? 1.5 : 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { rawIDs, _ in
            onMoveDroppedTasks(rawIDs, column.status)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private func taskRow(_ task: ProjectBoardTask) -> some View {
        BoardTaskCard(
            task: task,
            isSelected: selectedTaskID == task.id,
            onSelect: { onSelectTask(task.id) },
            onMoveStatus: { status in onMoveTask(task.id, status) }
        )
        .draggable(String(task.id)) {
            BoardTaskDragPreview(task: task)
        }
        .dropDestination(for: String.self) { rawIDs, _ in
            onMoveDroppedTasks(rawIDs, column.status)
        }
        .contextMenu {
            taskContextMenu(for: task)
        }
    }

    @ViewBuilder
    private func taskContextMenu(for task: ProjectBoardTask) -> some View {
        Button {
            onSelectTask(task.id)
        } label: {
            Label("Open Details", systemImage: "sidebar.right")
        }

        Menu {
            ForEach(ProjectTaskStatus.allCases.filter { $0 != task.status }) { status in
                Button {
                    onMoveTask(task.id, status)
                } label: {
                    Label {
                        Text(LocalizedStringKey(status.title))
                    } icon: {
                        Image(systemName: status.systemImage)
                    }
                }
            }
        } label: {
            Label("Move To", systemImage: "arrow.right.arrow.left")
        }
    }
}

private struct StatusCountBadge: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel("\(count) tasks")
    }
}

private struct InlineTaskComposer: View {
    let status: ProjectTaskStatus
    let onCancel: () -> Void
    let onCreate: (String, String, ProjectTaskPriority, String?) -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var priority: ProjectTaskPriority = .medium
    @State private var dueAt = ""
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($isTitleFocused)
                .onSubmit(submit)
                .accessibilityIdentifier("inline-task-title")
                .accessibilityHint("Enter the task name before creating it in the local SoloPM database.")

            TextField("Detail", text: $detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)
                .accessibilityIdentifier("inline-task-detail")
                .accessibilityHint("Optionally describe the task context.")

            HStack {
                Picker("Priority", selection: $priority) {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Text(LocalizedStringKey(priority.label)).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: ProjectBoardLayoutMetrics.inlinePriorityPickerWidth)
                .accessibilityIdentifier("inline-task-priority")
                .accessibilityHint("Sets the initial task priority.")

                TextField("Due", text: $dueAt)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("inline-task-due")
                    .accessibilityHint("Optionally enter a due date for the new local task.")
            }

            HStack {
                Button(action: submit) {
                    Label("Add", systemImage: "checkmark")
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Creates the task in the local SoloPM database")
                .accessibilityIdentifier("inline-task-create")
                .accessibilityHint("Creates the task in the local SoloPM database.")

                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                }
                .keyboardShortcut(.escape, modifiers: [])
                .help("Cancels task creation and returns focus to the board column")
                .accessibilityIdentifier("inline-task-cancel")
                .accessibilityHint("Cancels task creation and returns focus to the board column.")
            }
            .font(.caption)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
        .onAppear {
            isTitleFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inline-task-composer-\(status.rawValue)")
        .accessibilityLabel("New task in \(status.title)")
        .accessibilityHint("Create a local task in the \(status.title) column without leaving the board.")
    }

    private func submit() {
        onCreate(
            title,
            detail,
            priority,
            dueAt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        )
    }
}

private struct BoardTaskCard: View {
    let task: ProjectBoardTask
    let isSelected: Bool
    let onSelect: () -> Void
    let onMoveStatus: (ProjectTaskStatus) -> Void
    @State private var isPointerHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                TaskCardSelectableSummary(task: task, isPointerHovered: isPointerHovered)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open task \(task.title)")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint("Opens task details in the inspector. Task inspector fields can then be edited without dragging.")
            .accessibilityIdentifier("task-card-open-details")
            .accessibilitySortPriority(2)

            TaskStatusMoveControls(task: task, onMove: onMoveStatus)
                .accessibilityIdentifier("task-status-move-controls")
                .accessibilitySortPriority(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(task.status.tint.opacity(isSelected || isPointerHovered ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected || isPointerHovered ? task.status.tint.opacity(0.7) : Color.secondary.opacity(0.16))
        }
        .shadow(color: Color.black.opacity(isPointerHovered ? 0.10 : 0.04), radius: isPointerHovered ? 12 : 8, x: 0, y: isPointerHovered ? 4 : 2)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isPointerHovered = $0 }
        .animation(.snappy(duration: 0.16), value: isPointerHovered)
        .accessibilityElement(children: .contain)
    }

    private var accessibilityValueText: String {
        var values = [
            "Status: \(task.status.title)",
            "Priority: \(task.priority.label)"
        ]
        if let dueLabel = task.dueLabel {
            values.append("Due: \(dueLabel)")
        }
        return values.joined(separator: ", ")
    }
}

private struct TaskCardSelectableSummary: View {
    let task: ProjectBoardTask
    let isPointerHovered: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TaskStatusAccentRail(tint: task.status.tint)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(task.title)

                    Spacer(minLength: 6)

                    TaskDragAffordance(tint: task.status.tint, isPointerHovered: isPointerHovered)
                }

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .help(task.detail)
                }

                TaskCardMetadataStrip(task: task)
            }
        }
    }
}

private struct TaskDragAffordance: View {
    let tint: Color
    let isPointerHovered: Bool

    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.caption)
            .foregroundStyle(tint)
            .frame(width: 24, height: 24)
            .background(tint.opacity(isPointerHovered ? 0.18 : 0.10), in: Circle())
            .help("Drag to another status column")
            .accessibilityHidden(true)
    }
}

private struct TaskStatusAccentRail: View {
    let tint: Color

    var body: some View {
        Capsule()
            .fill(tint.opacity(0.92))
            .frame(width: ProjectBoardLayoutMetrics.taskStatusRailWidth)
            .frame(height: ProjectBoardLayoutMetrics.taskStatusRailHeight)
            .accessibilityHidden(true)
    }
}

private struct BoardTaskDragPreview: View {
    let task: ProjectBoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: task.status.systemImage)
                    .foregroundStyle(task.status.tint)

                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            HStack(spacing: 8) {
                Label {
                    Text(LocalizedStringKey(task.status.title))
                } icon: {
                    Image(systemName: "arrow.right.arrow.left")
                }
                    .foregroundStyle(task.status.tint)
                Label {
                    Text(LocalizedStringKey(task.priority.label))
                } icon: {
                    Image(systemName: "flag")
                }
                    .foregroundStyle(task.priority.color)
            }
            .font(.caption)
            .lineLimit(1)
        }
        .padding(10)
        .frame(width: 220, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(task.status.tint.opacity(0.36))
        }
        .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 4)
    }
}

private struct TaskStatusMoveControls: View {
    let task: ProjectBoardTask
    let onMove: (ProjectTaskStatus) -> Void

    var body: some View {
        HStack(spacing: 6) {
            statusMoveButton(
                title: "Move to previous status",
                systemImage: "chevron.left",
                targetStatus: task.status.previousStatus
            )

            Text(LocalizedStringKey(task.status.title))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 76)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .help(LocalizedStringKey(task.status.title))
                .accessibilityLabel("Current status: \(task.status.title)")

            statusMoveButton(
                title: "Move to next status",
                systemImage: "chevron.right",
                targetStatus: task.status.nextStatus
            )
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Status controls for \(task.title)")
        .accessibilityHint("Moves the task between board columns.")
    }

    private func statusMoveButton(title: String, systemImage: String, targetStatus: ProjectTaskStatus?) -> some View {
        Button {
            guard let targetStatus else {
                return
            }
            onMove(targetStatus)
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .controlSize(.small)
        .disabled(targetStatus == nil)
        .help(targetStatus.map { "\(title): \($0.title)" } ?? title)
        .accessibilityIdentifier(targetStatus.map { "task-status-move-\($0.rawValue)-\(task.id)" } ?? "task-status-move-disabled-\(task.id)")
        .accessibilityLabel(targetStatus.map { "\(title) to \($0.title)" } ?? title)
        .accessibilityHint("Changes \(task.title) status.")
    }
}

private struct TaskCardMetadataStrip: View {
    let task: ProjectBoardTask

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 72), spacing: 6)]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                metadataChips
            }

            LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 6) {
                metadataChips
            }
        }
        .font(.caption2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task metadata")
        .accessibilityValue("\(task.status.title), \(task.priority.label), \(dueValue)")
        .accessibilityIdentifier("task-card-metadata-strip")
    }

    @ViewBuilder
    private var metadataChips: some View {
        TaskMetadataChip(
            value: task.status.title,
            systemImage: task.status.systemImage,
            tint: task.status.tint
        )

        TaskMetadataChip(
            value: task.priority.label,
            systemImage: "flag",
            tint: task.priority.color
        )

        TaskMetadataChip(
            value: dueValue,
            systemImage: "calendar",
            tint: task.dueLabel == nil ? .secondary : .blue
        )
    }

    private var dueValue: String {
        task.dueLabel ?? "No due date"
    }
}

private struct TaskMetadataChip: View {
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(value)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.82)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: 12)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(
            minWidth: ProjectBoardLayoutMetrics.taskMetadataChipMinWidth,
            maxWidth: .infinity,
            minHeight: ProjectBoardLayoutMetrics.taskMetadataChipMinHeight,
            alignment: .leading
        )
        .background(tint.opacity(0.10), in: Capsule())
        .help(value)
    }
}

private struct ProjectTaskList: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        Table(project.tasks, selection: $viewModel.selectedTaskID) {
            TableColumn("Task") { task in
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(task.title)
                    if !task.detail.isEmpty {
                        Text(task.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(task.detail)
                    }
                }
            }

            TableColumn("Status") { task in
                Label {
                    Text(LocalizedStringKey(task.status.title))
                } icon: {
                    Image(systemName: task.status.systemImage)
                }
            }

            TableColumn("Priority") { task in
                Label {
                    Text(LocalizedStringKey(task.priority.label))
                } icon: {
                    Image(systemName: "flag")
                }
                    .foregroundStyle(task.priority.color)
            }

            TableColumn("Due") { task in
                Text(task.dueLabel ?? "")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("project-task-list")
        .accessibilityLabel("Project task list")
        .accessibilityHint("Lists the selected project's current tasks before creating, editing, executing, or deleting task content.")
    }
}

private struct InspectorCloseHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    let closeTitle: LocalizedStringKey
    let closeHelp: String
    let closeAccessibilityIdentifier: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 12)

            InspectorCloseButton(
                closeTitle: closeTitle,
                closeHelp: closeHelp,
                accessibilityIdentifier: closeAccessibilityIdentifier,
                onClose: onClose
            )
        }
    }
}

private struct InspectorCloseButton: View {
    let closeTitle: LocalizedStringKey
    let closeHelp: String
    let accessibilityIdentifier: String
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Label(closeTitle, systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .keyboardShortcut(.escape, modifiers: [])
        .help(closeHelp)
        .accessibilityLabel(closeTitle)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ProjectInspectorView: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onClose: () -> Void

    @State private var title: String
    @State private var isConfirmingArchive = false
    @State private var isConfirmingDelete = false

    init(project: ProjectBoardProject, viewModel: ProjectBoardViewModel, onClose: @escaping () -> Void) {
        self.project = project
        self.viewModel = viewModel
        self.onClose = onClose
        _title = State(initialValue: project.title)
    }

    var body: some View {
        Form {
            Section {
                InspectorCloseHeader(
                    title: "Project Details",
                    systemImage: "folder",
                    closeTitle: "Close Project Details",
                    closeHelp: String(localized: "Close Project Details"),
                    closeAccessibilityIdentifier: "project-inspector-close",
                    onClose: onClose
                )
            }

            Section("Summary") {
                ProjectInspectorMetadataSummary(project: project)
            }

            Section("Edit") {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("project-inspector-title")
                LabeledContent("Status", value: project.status.capitalized)
                LabeledContent("Tasks", value: project.subtitle)
                LabeledContent("Artifacts", value: "\(project.artifacts.count)")
            }

            Section("Project Directory") {
                LabeledContent("Current", value: project.workspaceDisplayName ?? "Not set")
                    .accessibilityIdentifier("project-workspace-current")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        chooseProjectDirectoryButton
                        clearProjectDirectoryButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        chooseProjectDirectoryButton
                        clearProjectDirectoryButton
                    }
                }
            }

            Section("Save") {
                Button {
                    viewModel.updateSelectedProject(title: title)
                } label: {
                    Label("Save Project", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == project.title)
                .keyboardShortcut("s", modifiers: [.command])
                .help("Saves edits to the selected project in the local SoloPM database")
                .accessibilityIdentifier("project-inspector-save")
                .accessibilityHint("Saves edits to the selected project in the local SoloPM database.")
            }

            Section("Suggestion") {
                ProjectInspectorSuggestionSection(project: project, viewModel: viewModel)
            }

            Section("Actions") {
                if project.isArchived {
                    Button {
                        viewModel.restoreSelectedProject()
                    } label: {
                        Label("Restore Project", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Restores the selected project to active views in the local SoloPM database")
                    .accessibilityIdentifier("project-inspector-restore")
                    .accessibilityHint("Restores the selected project to active views in the local SoloPM database.")
                } else {
                    Button {
                        viewModel.completeSelectedProject()
                    } label: {
                        Label("Complete Project", systemImage: "checkmark.seal")
                    }
                    .disabled(project.isCompleted)
                    .help("Completes the selected project in the local SoloPM database")
                    .accessibilityIdentifier("project-inspector-complete")
                    .accessibilityHint("Completes the selected project in the local SoloPM database.")
                }
            }

            Section("Danger Zone") {
                if isConfirmingArchive {
                    InspectorDestructiveConfirmation(
                        title: "Archive this project?",
                        message: "This hides the project from the active board and deadline summaries. Existing local tasks are kept in the SoloPM database.",
                        confirmTitle: "Archive Project",
                        confirmSystemImage: "archivebox",
                        accessibilityIdentifier: "project-inspector-archive-confirmation",
                        confirmAction: archiveSelectedProjectAfterConfirmationDismissal,
                        cancelAction: { isConfirmingArchive = false }
                    )
                } else if !project.isArchived {
                    Button(role: .destructive) {
                        isConfirmingDelete = false
                        isConfirmingArchive = true
                    } label: {
                        Label("Archive Project", systemImage: "archivebox")
                    }
                    .help("Archives the selected project after confirmation")
                    .accessibilityIdentifier("project-inspector-archive")
                    .accessibilityHint("Archives the selected project after confirmation.")
                }

                if isConfirmingDelete {
                    InspectorDestructiveConfirmation(
                        title: "Delete this project?",
                        message: "This permanently removes the project, its local tasks, deadline rules, artifact links, calendar links, and reminder links from SoloPM.",
                        confirmTitle: "Delete Project",
                        confirmSystemImage: "trash",
                        accessibilityIdentifier: "project-inspector-delete-confirmation",
                        confirmAction: deleteSelectedProjectAfterConfirmationDismissal,
                        cancelAction: { isConfirmingDelete = false }
                    )
                } else {
                    Button(role: .destructive) {
                        isConfirmingArchive = false
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .help("Deletes the selected project after confirmation")
                    .accessibilityIdentifier("project-inspector-delete")
                    .accessibilityHint("Deletes the selected project after confirmation.")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-inspector")
        .accessibilityLabel("Project inspector for \(project.title)")
        .accessibilityHint("Edit, save, archive, restore, or delete the selected project.")
        .onAppear {
            refreshFields(from: project)
        }
        .onChange(of: project) { _, newProject in
            refreshFields(from: newProject)
        }
    }

    private func refreshFields(from project: ProjectBoardProject) {
        title = project.title
    }

    private var chooseProjectDirectoryButton: some View {
        Button {
            chooseProjectDirectory()
        } label: {
            Label("Choose Directory", systemImage: "folder.badge.plus")
        }
        .disabled(project.isArchived)
        .help("Choose the local folder SoloPM can use for this project")
        .accessibilityIdentifier("project-workspace-choose")
        .accessibilityHint("Opens a folder picker and stores the selected project directory locally.")
    }

    private var clearProjectDirectoryButton: some View {
        Button {
            _ = viewModel.clearProjectWorkspacePath(projectID: project.id)
        } label: {
            Label("Clear Directory", systemImage: "xmark.circle")
        }
        .disabled(project.isArchived || !project.hasWorkspaceDirectory)
        .help("Clear this project's local directory permission")
        .accessibilityIdentifier("project-workspace-clear")
        .accessibilityHint("Removes the stored project directory from SoloPM without deleting files.")
    }

    private func chooseProjectDirectory() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose the local folder SoloPM can use for this project")
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            let bookmarkData: Data
            do {
                bookmarkData = try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } catch {
                DispatchQueue.main.async {
                    viewModel.reportProjectWorkspaceSelectionFailure()
                }
                return
            }
            DispatchQueue.main.async {
                _ = viewModel.assignProjectWorkspacePath(url.path, bookmarkData: bookmarkData, projectID: project.id)
            }
        }
        #endif
    }

    private func archiveSelectedProjectAfterConfirmationDismissal() {
        isConfirmingArchive = false
        DispatchQueue.main.async {
            viewModel.archiveSelectedProject()
        }
    }

    private func deleteSelectedProjectAfterConfirmationDismissal() {
        isConfirmingDelete = false
        DispatchQueue.main.async {
            viewModel.deleteSelectedProject()
        }
    }
}

private struct ProjectInspectorMetadataSummary: View {
    let project: ProjectBoardProject

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
            metadataPills
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project summary")
        .accessibilityValue("\(statusLabel), \(openTaskCount) open tasks, \(project.taskCount) total tasks, \(project.artifacts.count) artifacts")
        .accessibilityIdentifier("project-inspector-metadata-summary")
    }

    @ViewBuilder
    private var metadataPills: some View {
        InspectorMetadataPill(
            label: "Status",
            value: statusLabel,
            systemImage: statusSystemImage,
            tint: statusTint
        )

        InspectorMetadataPill(
            label: "Open",
            value: "\(openTaskCount)",
            systemImage: "circle",
            tint: .blue
        )

        InspectorMetadataPill(
            label: "Tasks",
            value: "\(project.taskCount)",
            systemImage: "checklist",
            tint: .secondary
        )

        InspectorMetadataPill(
            label: "Artifacts",
            value: "\(project.artifacts.count)",
            systemImage: "doc.text",
            tint: .purple
        )
    }

    private var openTaskCount: Int {
        project.tasks.filter { $0.status != .done }.count
    }

    private var statusLabel: String {
        if project.isArchived {
            return "Archived"
        }
        if project.isCompleted {
            return "Completed"
        }
        return "Active"
    }

    private var statusSystemImage: String {
        if project.isArchived {
            return "archivebox"
        }
        if project.isCompleted {
            return "checkmark.seal"
        }
        return "circle.fill"
    }

    private var statusTint: Color {
        if project.isArchived {
            return .secondary
        }
        if project.isCompleted {
            return .green
        }
        return .blue
    }
}

private struct ProjectInspectorSuggestionSection: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(suggestionText, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                applySuggestion()
            } label: {
                Label("Apply Suggestion", systemImage: "wand.and.stars")
            }
            .disabled(suggestionAction == .none)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Applies the local next-step suggestion to the selected project")
            .accessibilityIdentifier("project-inspector-apply-suggestion")
            .accessibilityHint("Applies the local next-step suggestion to the selected project.")
        }
    }

    private var suggestionAction: ProjectInspectorSuggestionAction {
        if project.isArchived {
            return .restoreProject
        }
        if project.taskCount == 0 {
            return .createFirstTask
        }
        if !project.isCompleted && project.tasks.allSatisfy({ $0.status == .done }) {
            return .completeProject
        }
        if let blockedTask = project.tasks.first(where: { $0.status == .blocked }) {
            return .openTask(blockedTask.id)
        }
        if let highPriorityTask = project.tasks.first(where: { $0.status != .done && $0.priority == .high }) {
            return .openTask(highPriorityTask.id)
        }
        if let dueTask = project.tasks
            .filter({ $0.status != .done && $0.dueAt != nil })
            .sorted(by: { ($0.dueAt ?? "") < ($1.dueAt ?? "") })
            .first {
            return .openTask(dueTask.id)
        }
        return .none
    }

    private var suggestionText: String {
        switch suggestionAction {
        case .restoreProject:
            return localizedDisplay("Restore this project before editing tasks or including it in active summaries.")
        case .createFirstTask:
            return localizedDisplay("Create a first concrete task so the project has a next action.")
        case .completeProject:
            return localizedDisplay("All tasks are done. Complete the project to keep active views focused.")
        case .openTask:
            return localizedDisplay("Open the highest-signal task and decide its next move in the inspector.")
        case .none:
            return localizedDisplay("No project-level suggestion is needed right now.")
        }
    }

    private func applySuggestion() {
        switch suggestionAction {
        case .restoreProject:
            viewModel.restoreSelectedProject()
        case .createFirstTask:
            _ = viewModel.createTask(title: localizedDisplay("Define next action"), projectID: project.id, status: .backlog)
        case .completeProject:
            viewModel.completeSelectedProject()
        case .openTask(let taskID):
            viewModel.selectedTaskID = taskID
        case .none:
            break
        }
    }
}

private enum ProjectInspectorSuggestionAction: Equatable {
    case restoreProject
    case createFirstTask
    case completeProject
    case openTask(Int64)
    case none
}

private struct TaskInspectorView: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onClose: () -> Void

    @State private var title: String
    @State private var detail: String
    @State private var status: ProjectTaskStatus
    @State private var priority: ProjectTaskPriority
    @State private var dueAt: String
    @State private var isConfirmingDelete = false

    init(task: ProjectBoardTask, viewModel: ProjectBoardViewModel, onClose: @escaping () -> Void) {
        self.task = task
        self.viewModel = viewModel
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _detail = State(initialValue: task.detail)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        _dueAt = State(initialValue: task.dueAt ?? "")
    }

    var body: some View {
        Form {
            Section {
                InspectorCloseHeader(
                    title: "Task Details",
                    systemImage: "checklist",
                    closeTitle: "Close Task Details",
                    closeHelp: String(localized: "Close Task Details"),
                    closeAccessibilityIdentifier: "task-inspector-close",
                    onClose: onClose
                )
            }

            Section("Summary") {
                TaskInspectorMetadataSummary(task: task, projectTitle: viewModel.projectTitle(for: task))
            }

            Section("Edit") {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("task-inspector-title")
                TextField("Detail", text: $detail, axis: .vertical)
                    .lineLimit(4...8)
                    .accessibilityIdentifier("task-inspector-detail")
            }

            Section("Fields") {
                Picker("Status", selection: $status) {
                    ForEach(ProjectTaskStatus.allCases) { status in
                        Label {
                            Text(LocalizedStringKey(status.title))
                        } icon: {
                            Image(systemName: status.systemImage)
                        }
                            .tag(status)
                    }
                }
                .accessibilityIdentifier("task-inspector-status")

                Picker("Priority", selection: $priority) {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Text(LocalizedStringKey(priority.label))
                            .tag(priority)
                    }
                }
                .accessibilityIdentifier("task-inspector-priority")

                TextField("Due", text: $dueAt)
                    .accessibilityIdentifier("task-inspector-due")
            }

            Section("Save") {
                Button {
                    viewModel.updateSelectedTask(
                        title: title,
                        detail: detail,
                        status: status,
                        priority: priority,
                        dueAt: dueAt.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                    )
                } label: {
                    Label("Save Changes", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut("s", modifiers: [.command])
                .help("Saves edits to the selected task in the local SoloPM database")
                .accessibilityIdentifier("task-inspector-save")
                .accessibilityHint("Saves edits to the selected task in the local SoloPM database.")
            }

            Section("Suggestion") {
                TaskInspectorSuggestionSection(task: task, viewModel: viewModel)
            }

            Section("Automation") {
                TaskInspectorAutomationSection(task: task, viewModel: viewModel)
            }

            Section("Danger Zone") {
                if isConfirmingDelete {
                    InspectorDestructiveConfirmation(
                        title: "Delete this task?",
                        message: "This removes the task from the local SoloPM database.",
                        confirmTitle: "Delete Task",
                        confirmSystemImage: "trash",
                        // The runtime AX preflight tracks this generated cancel
                        // identifier after opening the destructive confirmation:
                        // task-inspector-delete-confirmation-cancel.
                        accessibilityIdentifier: "task-inspector-delete-confirmation",
                        confirmAction: deleteSelectedTaskAfterConfirmationDismissal,
                        cancelAction: { isConfirmingDelete = false }
                    )
                } else {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .help("Deletes the selected task after confirmation")
                    .accessibilityIdentifier("task-inspector-delete")
                    .accessibilityHint("Deletes the selected task after confirmation.")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-inspector")
        .accessibilityLabel("Task inspector for \(task.title)")
        .accessibilityHint("Edit, save, move, or delete the selected task.")
        .onAppear {
            refreshFields(from: task)
        }
        .onChange(of: task) { _, newTask in
            refreshFields(from: newTask)
        }
    }

    private func refreshFields(from task: ProjectBoardTask) {
        title = task.title
        detail = task.detail
        status = task.status
        priority = task.priority
        dueAt = task.dueAt ?? ""
    }

    private func deleteSelectedTaskAfterConfirmationDismissal() {
        isConfirmingDelete = false
        DispatchQueue.main.async {
            viewModel.deleteSelectedTask()
        }
    }
}

private struct InspectorDestructiveConfirmation: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmSystemImage: String
    let accessibilityIdentifier: String
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel, action: cancelAction)
                    .accessibilityIdentifier("\(accessibilityIdentifier)-cancel")
                    .accessibilityLabel("Cancel \(confirmTitle)")
                    .accessibilityHint("Cancels \(confirmTitle) and returns to the inspector.")
                Button(role: .destructive, action: confirmAction) {
                    Label(confirmTitle, systemImage: confirmSystemImage)
                }
                .accessibilityIdentifier("\(accessibilityIdentifier)-confirm")
                .accessibilityLabel("Confirm \(confirmTitle)")
                .accessibilityHint("Confirms \(confirmTitle).")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct TaskInspectorMetadataSummary: View {
    let task: ProjectBoardTask
    let projectTitle: String

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
            metadataPills
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task summary")
        .accessibilityValue("\(task.status.title), \(task.priority.label), \(dueValue), \(projectTitle)")
        .accessibilityIdentifier("task-inspector-metadata-summary")
    }

    @ViewBuilder
    private var metadataPills: some View {
        InspectorMetadataPill(
            label: "Status",
            value: task.status.title,
            systemImage: task.status.systemImage,
            tint: task.status.tint
        )

        InspectorMetadataPill(
            label: "Priority",
            value: task.priority.label,
            systemImage: "flag",
            tint: task.priority.color
        )

        InspectorMetadataPill(
            label: "Due",
            value: dueValue,
            systemImage: "calendar",
            tint: task.dueLabel == nil ? .secondary : .blue
        )

        InspectorMetadataPill(
            label: "Project",
            value: projectTitle,
            systemImage: "folder",
            tint: .purple
        )
    }

    private var dueValue: String {
        task.dueLabel ?? "No due date"
    }
}

private struct InspectorMetadataPill: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(LocalizedStringKey(value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .help("\(label): \(value)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct TaskInspectorSuggestionSection: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var targetStatus: ProjectTaskStatus? {
        if task.status == .blocked {
            return .inProgress
        }
        return task.status.nextStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(suggestionText, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard let targetStatus else {
                    return
                }
                viewModel.moveSelectedTask(to: targetStatus)
            } label: {
                Label("Apply Suggestion", systemImage: "wand.and.stars")
            }
            .disabled(targetStatus == nil)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Applies the local next-step suggestion to the selected task")
            .accessibilityIdentifier("task-inspector-apply-suggestion")
            .accessibilityHint("Applies the local next-step suggestion to the selected task.")
        }
    }

    private var suggestionText: String {
        if task.status == .done {
            return localizedDisplay("This task is already complete.")
        }
        if task.status == .blocked {
            return localizedDisplay("If the blocker is resolved, move this task back into active work.")
        }
        if task.priority == .high {
            return localizedDisplay("High-priority task: move it forward when the next step is clear.")
        }
        return localizedDisplay("Move this task to the next status when you are ready.")
    }
}

private struct TaskInspectorAutomationSection: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var hasReviewDraft: Bool {
        viewModel.taskAutomationReviewDecision?.selectedTasks.contains(where: { $0.id == task.id }) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review-only task automation", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.prepareAutomationReviewForSelectedTask()
            } label: {
                Label("Review automation plan", systemImage: "doc.text.magnifyingglass")
            }
            .help("Prepares review-only local automation for the selected task")
            .accessibilityIdentifier("task-auto-execution-review")
            .accessibilityHint("Prepares review-only local automation for the selected task.")

            Button {
                viewModel.runApprovedAutomationForSelectedTask()
            } label: {
                Label("Run approved plan", systemImage: "play.circle")
            }
            .disabled(!hasReviewDraft)
            .help("Runs the reviewed local task step after explicit user approval")
            .accessibilityIdentifier("task-auto-execution-run-plan")
            .accessibilityHint("Runs the reviewed local task step after explicit user approval.")

            if hasReviewDraft {
                Text(localizedDisplay("Review draft is ready. Running it only starts local task execution."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasReviewDraft && !documentDeliverableReviews.isEmpty {
                documentDeliverableReviewView(documentDeliverableReviews)
            }

            if let receipt = latestApprovedExecutionReceipt {
                approvedExecutionReceiptView(receipt)
            }
        }
    }

    private var documentDeliverableReviews: [TaskAutomationDocumentDeliverableReview] {
        viewModel.taskAutomationDocumentDeliverableReviews
    }

    private var latestApprovedExecutionReceipt: ApprovedAutomationExecutionReceipt? {
        // Show the persisted redacted receipt, not current task text, so the audit trail
        // stays tied to what the user approved.
        viewModel.approvedAutomationExecutionReceipts.last { $0.taskID == task.id }
    }

    private func documentDeliverableReviewView(_ reviews: [TaskAutomationDocumentDeliverableReview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Document deliverables", systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))

            ForEach(reviews) { deliverable in
                VStack(alignment: .leading, spacing: 6) {
                    Text(deliverable.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(localizedDisplay(deliverable.riskLevel.rawValue.capitalized))
                        Text(deliverable.suggestedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Text(deliverable.rationale)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if !deliverable.sourceDocuments.isEmpty {
                        Text("Source documents")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(deliverable.sourceDocuments) { source in
                            documentSourceRow(source)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-auto-execution-document-deliverables")
        .accessibilityLabel("Document deliverables")
        .accessibilityHint("Shows the draft-only document outputs and redacted source documents for the reviewed automation plan.")
    }

    private func documentSourceRow(_ source: TaskAutomationDocumentSourceReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
            Text(source.redactedSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(source.inclusionReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("task-auto-execution-document-source-\(source.id)")
        .accessibilityLabel("Automation document source")
        .accessibilityValue(documentSourceAccessibilityValue(source))
        .accessibilityHint("Shows the redacted document source preview used for the reviewed automation draft.")
    }

    private func documentSourceAccessibilityValue(_ source: TaskAutomationDocumentSourceReview) -> String {
        [
            "Title \(source.title)",
            "Summary \(source.redactedSummary)",
            "Reason \(source.inclusionReason)"
        ].joined(separator: ", ")
    }

    private func approvedExecutionReceiptView(_ receipt: ApprovedAutomationExecutionReceipt) -> some View {
        let statusText = [
            "Status: \(localizedDisplay(receipt.statusBefore.title))",
            "to \(localizedDisplay(receipt.statusAfter.title))"
        ].joined(separator: " ")

        return VStack(alignment: .leading, spacing: 6) {
            Label("Approved execution receipt", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))

            Text("Task: \(receipt.redactedTaskTitle)")
                .lineLimit(2)
            Text("Reviewed detail: \(receipt.redactedTaskDetail)")
                .lineLimit(3)
            Text(statusText)
            Text("Reason: \(receipt.reviewReason)")
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("approved-execution-receipt")
        .accessibilityLabel("Approved execution receipt")
        .accessibilityValue(approvedExecutionReceiptAccessibilityValue(receipt))
        .accessibilityHint("Shows the redacted task title and detail that were approved and executed.")
    }

    private func approvedExecutionReceiptAccessibilityValue(_ receipt: ApprovedAutomationExecutionReceipt) -> String {
        [
            "Task \(receipt.redactedTaskTitle)",
            "Reviewed detail \(receipt.redactedTaskDetail)",
            "Status \(localizedDisplay(receipt.statusBefore.title)) to \(localizedDisplay(receipt.statusAfter.title))",
            "Reason \(receipt.reviewReason)"
        ].joined(separator: ", ")
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

private extension ProjectPortfolioHealth {
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

private extension ArtifactCreatedState {
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
