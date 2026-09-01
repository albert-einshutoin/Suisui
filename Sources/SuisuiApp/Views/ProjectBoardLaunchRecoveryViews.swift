import SuisuiCore
import SwiftUI

struct ProjectBoardLaunchRecoveryView: View {
    @StateObject private var viewModel: ProjectBoardViewModel
    private let appSettings: () -> AppSettings
    @State private var isInspectorPresented = false

    init(
        viewModel: ProjectBoardViewModel,
        appSettings: @escaping () -> AppSettings = { .default }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.appSettings = appSettings
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            workflowBody
            recoveryInspector
        }
            .frame(minWidth: 960, idealWidth: 1_180, minHeight: 572, idealHeight: 760)
            .task {
                loadRuntimeState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange)) { _ in
                loadRuntimeState()
            }
    }

    @ViewBuilder
    private var workflowBody: some View {
        switch resolvedSelectedDestination {
        case .inbox:
            InboxWorkflowView(viewModel: viewModel, selectInboxTask: selectWorkflowTask)
        case .schedule:
            ScheduleWorkflowView(viewModel: viewModel)
        case .today:
            TodayWorkflowView(
                viewModel: viewModel,
                selectTodayTask: selectWorkflowTask,
                openInspectorForTodayRailTask: openInspectorForWorkflowTask,
                prefersContinuousRail: VisualEvidenceRuntimeContext() != nil
                    ? CockpitLayoutPolicy.presentsSplitRail(
                        contentWidth: CockpitLayoutPolicy.standardContentWidth
                    )
                    : nil
            )
        case .done:
            DoneWorkflowView(viewModel: viewModel, appSettings: appSettings())
        case .assistantQueue:
            AssistantQueueWorkflowView(viewModel: viewModel)
        case .projects:
            if ProjectBoardUIEvidenceRecoveryEnvironment.isEnabled {
                ProjectBoardUIEvidenceProjectsOverviewRecoveryView(viewModel: viewModel)
            } else {
                ProjectBoardRuntimeCRUDRecoveryView(projectID: nil, viewModel: viewModel)
            }
        case .project(let projectID):
            if ProjectBoardLayoutStabilityRecoveryEnvironment.isEnabled {
                ProjectBoardLayoutStabilityRecoveryView(projectID: projectID, viewModel: viewModel)
            } else if ProjectBoardRuntimeCRUDRecoveryEnvironment.isEnabled || ProjectBoardUIEvidenceRecoveryEnvironment.isEnabled {
                ProjectBoardRuntimeCRUDRecoveryView(projectID: projectID, viewModel: viewModel)
            } else {
                ProjectDevelopmentAutomationRecoveryView(
                    projectID: projectID,
                    viewModel: viewModel
                )
            }
        }
    }

    @ViewBuilder
    private var recoveryInspector: some View {
        if isInspectorPresented, let task = viewModel.selectedTask {
            ProjectBoardLaunchRecoveryTaskInspector(
                task: task,
                viewModel: viewModel,
                onClose: { isInspectorPresented = false }
            )
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
            .padding(.vertical, 18)
            .padding(.trailing, 18)
        }
    }

    private var selectedDestination: ProjectBoardLaunchRecoveryDestination {
        let rawValue = ProcessInfo.processInfo.environment["SUISUI_PROJECT_BOARD_SELECTED_DESTINATION"]
        return ProjectBoardLaunchRecoveryDestination(rawValue: rawValue ?? "") ?? .today
    }

    private var resolvedSelectedDestination: ProjectBoardLaunchRecoveryDestination {
        selectedDestination.resolved(availableProjects: viewModel.snapshot.projects)
    }

    private func loadRuntimeState() {
        viewModel.load()
        applySelectedTaskOverrideIfNeeded()
        _ = viewModel.scheduleMissedTaskDailyFollowUp(settings: appSettings())
    }

    private func selectWorkflowTask(_ task: ProjectBoardTask) {
        viewModel.selectedTaskID = task.id
        isInspectorPresented = false
    }

    private func openInspectorForWorkflowTask(_ taskID: Int64) {
        viewModel.selectedTaskID = taskID
        guard viewModel.selectedTask != nil else {
            return
        }

        isInspectorPresented = true
    }

    private func applySelectedTaskOverrideIfNeeded() {
        guard let taskID = ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID,
              viewModel.snapshot.projects.flatMap(\.tasks).contains(where: { $0.id == taskID }) else {
            return
        }
        // Recovery launches must not mutate persisted Project Board selection;
        // the env override only restores deterministic rail context for smoke evidence.
        viewModel.selectedTaskID = taskID
    }
}

private enum ProjectBoardUIEvidenceRecoveryEnvironment {
    private static let flagName = "SUISUI_UI_EVIDENCE_RECOVERY_MODE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[flagName] == "1"
    }
}

private struct ProjectBoardUIEvidenceProjectsOverviewRecoveryView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var summaries: [ProjectPortfolioSummary] {
        viewModel.projectPortfolioSummaries()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Projects", systemImage: "folder")
                    .font(.headline)
                    .accessibilityIdentifier("sidebar-destination-projects")

                Text("Portfolio Watchlist")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(width: 240, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)

            VStack(alignment: .leading, spacing: 16) {
                Label("Projects", systemImage: "rectangle.grid.2x2")
                    .font(.title3.weight(.semibold))

                if summaries.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "folder.badge.questionmark")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(summaries.prefix(6)) { summary in
                            portfolioCard(summary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("projects-portfolio-overview")
            .accessibilityLabel("Projects portfolio overview")
        }
        .frame(minWidth: 960, idealWidth: 1_180, minHeight: 572, idealHeight: 760)
    }

    private func portfolioCard(_ summary: ProjectPortfolioSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.title)
                .font(.headline)
                .lineLimit(1)

            ProgressView(value: summary.progress)
                .accessibilityLabel("Progress")
                .accessibilityValue("\(Int((summary.progress * 100).rounded())) percent")

            HStack(spacing: 10) {
                metric("Open tasks", value: "\(summary.openTaskCount)")
                metric("Blocked", value: "\(summary.blockedTaskCount)")
            }

            Text(summary.riskReason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-portfolio-card-\(summary.projectID)")
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProjectBoardLaunchRecoveryTaskInspector: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onClose: () -> Void

    @State private var title: String
    @State private var detail: String
    @State private var status: ProjectTaskStatus
    @State private var priority: ProjectTaskPriority
    @State private var dueAt: String

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
                HStack(spacing: 12) {
                    Label("Task Details", systemImage: "checklist")
                        .font(.headline)
                    Spacer(minLength: 12)
                    Button {
                        onClose()
                    } label: {
                        Label("Close Task Details", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Close Task Details")
                    .accessibilityIdentifier("task-inspector-close")
                    .accessibilityHint("Close Task Details")
                }
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
                        Text(LocalizedStringKey(status.title))
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
                    let trimmedDueAt = dueAt.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.updateSelectedTask(
                        title: title,
                        detail: detail,
                        status: status,
                        priority: priority,
                        dueAt: trimmedDueAt.isEmpty ? nil : trimmedDueAt,
                        // The recovery inspector has no repeat picker; keep the
                        // task's recurrence unchanged on save.
                        recurrence: task.recurrence
                    )
                } label: {
                    Label("Save Changes", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Saves edits to the selected task in the local Suisui database")
                .accessibilityIdentifier("task-inspector-save")
                .accessibilityHint("Saves edits to the selected task in the local Suisui database.")
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-inspector")
        .accessibilityLabel("Task inspector for \(task.title)")
        .accessibilityHint("Edit and save the selected task.")
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
}

private enum ProjectBoardLayoutStabilityRecoveryEnvironment {
    private static let flagName = "SUISUI_LAYOUT_STABILITY_RECOVERY_MODE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[flagName] == "1"
    }
}

private struct ProjectBoardLayoutStabilityRecoveryView: View {
    let projectID: Int64
    @ObservedObject var viewModel: ProjectBoardViewModel

    @State private var isSidebarVisible = true
    @State private var selectedProjectID: Int64

    init(projectID: Int64, viewModel: ProjectBoardViewModel) {
        self.projectID = projectID
        self.viewModel = viewModel
        _selectedProjectID = State(initialValue: projectID)
    }

    var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar
                    .frame(width: 240)
                    .frame(maxHeight: .infinity)

                Divider()
            }

            VStack(spacing: 0) {
                header
                Divider()
                detail
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            inspector
                .frame(width: 320)
                .frame(maxHeight: .infinity)
        }
        .frame(minWidth: 960, idealWidth: 1_180, minHeight: 572, idealHeight: 760)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    isSidebarVisible.toggle()
                } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
                .accessibilityIdentifier("project-board-sidebar-toggle")
                .accessibilityLabel(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }
        }
        .onAppear {
            restoreSelectedProjectIfNeeded()
        }
        .onChange(of: viewModel.snapshot.projects) { _, _ in
            restoreSelectedProjectIfNeeded()
        }
    }

    private var layoutProjects: [ProjectBoardProject] {
        viewModel.snapshot.projects.filter { !$0.isArchived }
    }

    private var selectedProject: ProjectBoardProject? {
        layoutProjects.first { $0.id == selectedProjectID } ?? layoutProjects.first
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projects")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(layoutProjects) { project in
                        Button {
                            selectedProjectID = project.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: project.id == selectedProjectID ? "folder.fill" : "folder")
                                    .frame(width: 18)

                                Text(project.title)
                                    .lineLimit(1)

                                Spacer(minLength: 8)

                                Text("\(project.taskCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("project-sidebar-row-\(project.id)")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-sidebar")
        .accessibilityLabel("Project navigation")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Project Board", systemImage: "rectangle.3.group")
                .font(.headline)

            if let selectedProject {
                Text(selectedProject.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-header-bar")
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedProject {
                Text(selectedProject.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 12) {
                    layoutMetric(title: "Status", value: selectedProject.status.capitalized)
                    layoutMetric(title: "Tasks", value: "\(selectedProject.taskCount)")
                    layoutMetric(title: "Milestones", value: selectedProject.milestoneSummary)
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach(selectedProject.columns) { column in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(column.title)
                                .font(.headline)
                                .lineLimit(1)

                            ForEach(column.tasks.prefix(3)) { task in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.title)
                                        .lineLimit(1)
                                    Text(task.detail.isEmpty ? task.status.title : task.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(.quaternary, lineWidth: 1)
                                )
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            } else {
                ContentUnavailableView("No Projects", systemImage: "folder.badge.questionmark")
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-detail")
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedProject {
                Label("Project Details", systemImage: "folder")
                    .font(.headline)

                Divider()

                LabeledContent("Title", value: selectedProject.title)
                LabeledContent("Status", value: selectedProject.status.capitalized)
                LabeledContent("Tasks", value: "\(selectedProject.taskCount)")
                LabeledContent("Workspace", value: selectedProject.workspaceDisplayName ?? "Not set")

                Spacer(minLength: 0)
            } else {
                ContentUnavailableView("No Projects", systemImage: "folder.badge.questionmark")
            }
        }
        .padding(18)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-inspector")
    }

    private func layoutMetric(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
        }
        .padding(10)
        .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func restoreSelectedProjectIfNeeded() {
        // Layout stability evidence must exercise real seeded project data while
        // staying independent from the full Project Board's WindowGroup startup path.
        if layoutProjects.contains(where: { $0.id == selectedProjectID }) {
            return
        }
        if layoutProjects.contains(where: { $0.id == projectID }) {
            selectedProjectID = projectID
            return
        }
        if let firstProjectID = layoutProjects.first?.id {
            selectedProjectID = firstProjectID
        }
    }
}

private enum ProjectBoardRuntimeCRUDRecoveryEnvironment {
    private static let flagName = "SUISUI_RUNTIME_CRUD_RECOVERY_MODE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[flagName] == "1"
    }
}

private struct ProjectBoardRuntimeCRUDRecoveryView: View {
    let projectID: Int64?
    @ObservedObject var viewModel: ProjectBoardViewModel
    @StateObject private var settingsViewModel = AppRuntimeFactory.makeAppSettingsViewModel(
        refreshProviderSecretStatusesOnInit: false
    )
    @ObservedObject private var shortcutSettingsViewModel = GlobalShortcutRuntime.shared.settingsViewModel
    @AppStorage(SuisuiAppearancePreference.storageKey) private var appearancePreference: SuisuiAppearancePreference = .system
    @AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system

    @State private var projectTitle = ""
    @State private var isShowingEmbeddedSettings = false
    @State private var isShowingEmbeddedVoice = false
    @State private var isTaskComposerVisible = false
    @State private var taskTitle = ""
    @State private var taskDetail = ""
    @State private var taskInspectorTitle = ""
    @State private var taskInspectorDetail = ""
    @State private var isConfirmingTaskDelete = false
    @State private var isConfirmingProjectDelete = false

    private var project: ProjectBoardProject? {
        guard let selectedProjectID = projectID ?? viewModel.selectedProjectID else {
            return nil
        }
        return viewModel.snapshot.projects.first { $0.id == selectedProjectID }
    }

    private var selectedTask: ProjectBoardTask? {
        viewModel.selectedTask
    }

    private var hasReviewDraft: Bool {
        guard let taskID = selectedTask?.id else {
            return false
        }
        return viewModel.taskAutomationReviewDecision?.selectedTasks.contains { $0.id == taskID } == true
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            projectsColumn

            if isShowingEmbeddedSettings {
                SuisuiSettingsWorkspace(
                    settingsViewModel: settingsViewModel,
                    shortcutSettingsViewModel: shortcutSettingsViewModel,
                    appearancePreference: $appearancePreference,
                    languagePreference: $languagePreference
                )
            } else if isShowingEmbeddedVoice {
                VoiceCaptureWorkspaceHost()
            } else if let project {
                projectColumn(project)
            } else {
                ContentUnavailableView(
                    "No project selected",
                    systemImage: "folder",
                    description: Text("Create or select a project for runtime CRUD verification.")
                )
            }

            if let selectedTask {
                taskInspector(selectedTask)
            }
        }
        .padding(18)
        .frame(minWidth: 960, idealWidth: 1_180, minHeight: 572, idealHeight: 760, alignment: .topLeading)
        .task {
            loadRuntimeState()
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange)) { _ in
            loadRuntimeState()
        }
    }

    private var projectsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Projects", systemImage: "folder")
                .font(.headline)

            Button {
                viewModel.selectedTaskID = nil
                isShowingEmbeddedSettings = false
                isShowingEmbeddedVoice = false
            } label: {
                Label("Inbox", systemImage: "tray")
            }
            .buttonStyle(.plain)
            .help("Opens the Inbox workflow entry for accessibility verification")
            .accessibilityIdentifier("sidebar-destination-inbox")
            .accessibilityHint("Opens the Inbox workflow entry for accessibility verification.")

            Button {
                viewModel.selectedTaskID = nil
                isShowingEmbeddedSettings = false
                isShowingEmbeddedVoice = false
            } label: {
                Label("Today", systemImage: "sun.max")
            }
            .buttonStyle(.plain)
            .help("Opens the Today workflow entry for accessibility verification")
            .accessibilityIdentifier("sidebar-destination-today")
            .accessibilityHint("Opens the Today workflow entry for accessibility verification.")

            Button {
                _ = viewModel.createProject()
            } label: {
                Label("Add Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("Creates a new local project in the Suisui database")
            .accessibilityIdentifier("project-board-add-project")
            .accessibilityHint("Creates a new local project in the Suisui database.")

            Button {
                viewModel.selectedTaskID = nil
                isShowingEmbeddedVoice = false
                isShowingEmbeddedSettings.toggle()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .help("Open Settings")
            .accessibilityIdentifier("project-board-settings-link")
            .accessibilityHint("Opens Settings.")

            Button {
                viewModel.selectedTaskID = nil
                isShowingEmbeddedSettings = false
                isShowingEmbeddedVoice.toggle()
            } label: {
                Label("Voice Quick Capture", systemImage: "mic")
            }
            .buttonStyle(.bordered)
            .help("Open Voice Quick Capture")
            .accessibilityIdentifier("project-board-voice-command")
            .accessibilityHint("Opens Voice Quick Capture.")

            ForEach(viewModel.snapshot.projects) { project in
                Button {
                    viewModel.selectedProjectID = project.id
                    viewModel.selectedTaskID = nil
                    projectTitle = project.title
                    isConfirmingProjectDelete = false
                    isShowingEmbeddedSettings = false
                isShowingEmbeddedVoice = false
                } label: {
                    Text(project.title)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 220, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-sidebar")
        .accessibilityLabel("Project navigation")
    }

    private func projectColumn(_ project: ProjectBoardProject) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Project Details", systemImage: "folder")
                .font(.headline)

            TextField("Project title", text: $projectTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("project-inspector-title")

            Button {
                viewModel.updateSelectedProject(title: projectTitle)
            } label: {
                Label("Save Project", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Saves edits to the selected project in the local Suisui database")
            .accessibilityIdentifier("project-inspector-save")
            .accessibilityHint("Saves edits to the selected project in the local Suisui database.")

            Button {
                isTaskComposerVisible = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .help("Add task to \(project.title)")
            .accessibilityIdentifier("project-header-add-task")
            .accessibilityHint("Opens the inline composer for a new local task.")

            if isTaskComposerVisible {
                taskComposer(projectID: project.id)
            }

            taskList(project.tasks)

            Divider()

            Button {
                viewModel.completeSelectedProject()
            } label: {
                Label("Complete Project", systemImage: "checkmark.seal")
            }
            .disabled(project.isCompleted)
            .help("Completes the selected project in the local Suisui database")
            .accessibilityIdentifier("project-inspector-complete")
            .accessibilityHint("Completes the selected project in the local Suisui database.")

            if isConfirmingProjectDelete {
                ProjectBoardRuntimeCRUDDestructiveConfirmation(
                    title: "Delete this project?",
                    message: "This permanently removes the project and its local tasks from Suisui.",
                    confirmTitle: "Delete Project",
                    accessibilityIdentifier: "project-inspector-delete-confirmation",
                    confirmAction: {
                        isConfirmingProjectDelete = false
                        viewModel.deleteSelectedProject()
                    },
                    cancelAction: { isConfirmingProjectDelete = false }
                )
            } else {
                Button(role: .destructive) {
                    isConfirmingProjectDelete = true
                } label: {
                    Label("Delete Project", systemImage: "trash")
                }
                .help("Deletes the selected project after confirmation")
                .accessibilityIdentifier("project-inspector-delete")
                .accessibilityHint("Deletes the selected project after confirmation.")
            }
        }
        .frame(minWidth: 320, maxWidth: 420, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-board-detail")
        .accessibilityLabel("Project board detail")
        .onAppear {
            projectTitle = project.title
        }
        .onChange(of: project.id) { _, _ in
            projectTitle = project.title
            isTaskComposerVisible = false
            isConfirmingProjectDelete = false
        }
        .onChange(of: project.title) { _, newTitle in
            if projectTitle.isEmpty || projectTitle == newTitle {
                projectTitle = newTitle
            }
        }
    }

    private func taskComposer(projectID: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Task title", text: $taskTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("inline-task-title")

            TextField("Detail", text: $taskDetail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)
                .accessibilityIdentifier("inline-task-detail")

            Button {
                _ = viewModel.createTask(
                    title: taskTitle,
                    detail: taskDetail,
                    projectID: projectID,
                    status: .backlog
                )
                taskTitle = ""
                taskDetail = ""
                isTaskComposerVisible = false
            } label: {
                Label("Add", systemImage: "checkmark")
            }
            .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Creates the task in the local Suisui database")
            .accessibilityIdentifier("inline-task-create")
            .accessibilityHint("Creates the task in the local Suisui database.")
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func taskList(_ tasks: [ProjectBoardTask]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tasks) { task in
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        viewModel.selectedProjectID = task.projectID
                        viewModel.selectedTaskID = task.id
                        taskInspectorTitle = task.title
                        taskInspectorDetail = task.detail
                        isConfirmingTaskDelete = false
                    } label: {
                        Text(task.title)
                            .lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task-card-open-details")
                    .accessibilityLabel("Open task \(task.title)")
                    .accessibilityHint("Opens task details in the inspector.")

                    HStack(spacing: 6) {
                        runtimeStatusButton(task: task, targetStatus: task.status.previousStatus)
                        Text(LocalizedStringKey(task.status.title))
                            .font(.caption)
                        runtimeStatusButton(task: task, targetStatus: task.status.nextStatus)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("task-status-move-controls")
                }
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func runtimeStatusButton(task: ProjectBoardTask, targetStatus: ProjectTaskStatus?) -> some View {
        Button {
            guard let targetStatus else {
                return
            }
            viewModel.moveTask(id: task.id, to: targetStatus)
        } label: {
            Label("Move task", systemImage: "chevron.right")
                .labelStyle(.iconOnly)
        }
        .disabled(targetStatus == nil)
        .accessibilityIdentifier(targetStatus.map { "task-status-move-\($0.rawValue)-\(task.id)" } ?? "task-status-move-disabled-\(task.id)")
        .accessibilityLabel(targetStatus.map { "Move to \($0.title)" } ?? "Move task")
    }

    private func taskInspector(_ task: ProjectBoardTask) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Task Details", systemImage: "checklist")
                .font(.headline)

            TextField("Title", text: $taskInspectorTitle)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("task-inspector-title")

            TextField("Detail", text: $taskInspectorDetail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)
                .accessibilityIdentifier("task-inspector-detail")

            Button {
                viewModel.updateSelectedTask(
                    title: taskInspectorTitle,
                    detail: taskInspectorDetail,
                    status: task.status,
                    priority: task.priority,
                    dueAt: task.dueAt,
                    // The recovery inspector has no repeat picker; keep the
                    // task's recurrence unchanged on save.
                    recurrence: task.recurrence
                )
            } label: {
                Label("Save Changes", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .disabled(taskInspectorTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Saves edits to the selected task in the local Suisui database")
            .accessibilityIdentifier("task-inspector-save")
            .accessibilityHint("Saves edits to the selected task in the local Suisui database.")

            Button {
                let nextStatus = task.status == .blocked ? ProjectTaskStatus.inProgress : task.status.nextStatus
                guard let nextStatus else {
                    return
                }
                viewModel.moveTask(id: task.id, to: nextStatus)
            } label: {
                Label("Apply Suggestion", systemImage: "wand.and.stars")
            }
            .disabled(task.status.nextStatus == nil && task.status != .blocked)
            .help("Applies the local next-step suggestion to the selected task")
            .accessibilityIdentifier("task-inspector-apply-suggestion")
            .accessibilityHint("Applies the local next-step suggestion to the selected task.")

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

            if let receipt = viewModel.approvedAutomationExecutionReceipts.last(where: { $0.taskID == task.id }) {
                approvedExecutionReceiptView(receipt)
            }

            if isConfirmingTaskDelete {
                ProjectBoardRuntimeCRUDDestructiveConfirmation(
                    title: "Delete this task?",
                    message: "This removes the task from the local Suisui database.",
                    confirmTitle: "Delete Task",
                    accessibilityIdentifier: "task-inspector-delete-confirmation",
                    confirmAction: {
                        isConfirmingTaskDelete = false
                        viewModel.deleteSelectedTask()
                    },
                    cancelAction: { isConfirmingTaskDelete = false }
                )
            } else {
                Button(role: .destructive) {
                    isConfirmingTaskDelete = true
                } label: {
                    Label("Delete Task", systemImage: "trash")
                }
                .help("Deletes the selected task after confirmation")
                .accessibilityIdentifier("task-inspector-delete")
                .accessibilityHint("Deletes the selected task after confirmation.")
            }
        }
        .frame(minWidth: 300, maxWidth: 380, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-inspector")
        .accessibilityLabel("Task inspector for \(task.title)")
        .accessibilityHint("Edit, save, move, or delete the selected task.")
        .onAppear {
            refreshTaskFields(from: task)
        }
        .onChange(of: task.id) { _, _ in
            refreshTaskFields(from: task)
        }
        .onChange(of: task.title) { _, _ in
            refreshTaskFields(from: task)
        }
    }

    private func approvedExecutionReceiptView(_ receipt: ApprovedAutomationExecutionReceipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Approved execution receipt", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))
            Text("Task: \(receipt.redactedTaskTitle)")
            Text("Reviewed detail: \(receipt.redactedTaskDetail)")
        }
        .font(.caption)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("approved-execution-receipt")
        .accessibilityLabel("Approved execution receipt")
        .accessibilityValue("Task \(receipt.redactedTaskTitle), Reviewed detail \(receipt.redactedTaskDetail)")
        .accessibilityHint("Shows the redacted task title and detail that were approved and executed.")
    }

    private func refreshTaskFields(from task: ProjectBoardTask) {
        taskInspectorTitle = task.title
        taskInspectorDetail = task.detail
    }

    private func loadRuntimeState() {
        viewModel.load()
        if let projectID {
            viewModel.selectedProjectID = projectID
        }
        if let project {
            projectTitle = project.title
        }
        if let selectedTask {
            refreshTaskFields(from: selectedTask)
        }
    }
}

private struct ProjectBoardRuntimeCRUDDestructiveConfirmation: View {
    let title: String
    let message: String
    let confirmTitle: String
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
            HStack(spacing: 8) {
                Button("Cancel", role: .cancel, action: cancelAction)
                    .accessibilityIdentifier("\(accessibilityIdentifier)-cancel")
                    .accessibilityLabel("Cancel \(confirmTitle)")
                Button(role: .destructive, action: confirmAction) {
                    Label(confirmTitle, systemImage: "trash")
                }
                .accessibilityIdentifier("\(accessibilityIdentifier)-confirm")
                .accessibilityLabel("Confirm \(confirmTitle)")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private enum ProjectBoardLaunchRecoveryDestination: Equatable {
    case inbox
    case schedule
    case today
    case done
    case assistantQueue
    case projects
    case project(Int64)

    init?(rawValue: String) {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawValue.hasPrefix("project:") {
            let rawProjectID = rawValue.dropFirst("project:".count)
            guard let projectID = Int64(rawProjectID), projectID > 0 else {
                return nil
            }
            self = .project(projectID)
            return
        }

        switch rawValue {
        case "inbox":
            self = .inbox
        case "schedule":
            self = .schedule
        case "today", "":
            self = .today
        case "done":
            self = .done
        case "assistant-queue":
            self = .assistantQueue
        case "projects":
            self = .projects
        default:
            return nil
        }
    }

    func resolved(availableProjects: [ProjectBoardProject]) -> ProjectBoardLaunchRecoveryDestination {
        switch self {
        case .project(let projectID):
            return availableProjects.contains(where: { $0.id == projectID }) ? self : .today
        case .inbox, .schedule, .today, .done, .assistantQueue, .projects:
            return self
        }
    }

}

private struct ProjectDevelopmentAutomationRecoveryView: View {
    let projectID: Int64
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var didLoad = false
    @State private var repositoryEditRelativePath = ""
    @State private var repositoryEditContents = ""
    @State private var commitRelativePaths = ""
    @State private var commitMessage = ""

    private var project: ProjectBoardProject? {
        viewModel.snapshot.projects.first { $0.id == projectID }
    }

    private var task: ProjectBoardTask? {
        viewModel.selectedTask
    }

    private var readiness: ProjectDevelopmentAutomationReadiness? {
        guard let project else {
            return nil
        }
        return viewModel.developmentAutomationReadiness(for: project, task: task)
    }

    private var progress: ProjectDevelopmentAutomationProgress? {
        guard let project else {
            return nil
        }
        return viewModel.developmentAutomationProgress(for: project, task: task)
    }

    private var canQueueRepositoryEditReview: Bool {
        progress?.canQueueRepositoryEditReview == true
            && !repositoryEditRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryEditContents.isEmpty
    }

    private var canQueueCommitReview: Bool {
        progress?.canQueueCommitReview == true
            && !commitRelativePaths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var repositoryEditPreview: ProjectDevelopmentAutomationApprovalPreview? {
        guard let project else {
            return nil
        }
        return viewModel.developmentRepositoryEditPreview(
            for: project,
            task: task,
            operation: .create,
            relativePath: repositoryEditRelativePath,
            contents: repositoryEditContents,
            expectedSHA256: nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project, let readiness {
                Label(
                    LocalizedStringKey(readiness.statusLabel),
                    systemImage: readiness.isReady ? "checkmark.seal" : "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(readiness.isReady ? .green : .orange)
                .accessibilityIdentifier("project-development-automation-status")

                Text(project.title)
                    .font(.title3)
                    .textSelection(.enabled)

                if let task {
                    Text(task.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let blockingReason = readiness.blockingReason {
                    Text(LocalizedStringKey(blockingReason))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let branchNamePreview = readiness.branchNamePreview {
                    LabeledContent("Branch Preview", value: branchNamePreview)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("project-development-automation-branch-preview")
                }

                Button {
                    _ = viewModel.enqueueDevelopmentAutomationReview(for: project, task: task)
                } label: {
                    Label("Queue branch automation", systemImage: "tray.and.arrow.down")
                }
                .disabled(!readiness.isReady)
                .help("Adds the development branch preparation plan to Assistant Queue without creating a branch.")
                .accessibilityIdentifier("project-development-automation-queue")
                .accessibilityHint("Adds the development branch preparation plan to Assistant Queue for review and approval.")

                // The recovery surface mirrors the next approval step so runtime
                // smoke can prove repository edits stay review-gated without
                // loading the full board's heavier AX tree.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repository edit review")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Repository file path", text: $repositoryEditRelativePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-edit-path")

                    TextEditor(text: $repositoryEditContents)
                        .font(.caption)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )
                        .accessibilityLabel("Repository file contents")
                        .accessibilityIdentifier("project-development-automation-edit-contents")

                    if let repositoryEditPreview {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(LocalizedStringKey(repositoryEditPreview.title), systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)

                            ForEach(repositoryEditPreview.rows) { row in
                                LabeledContent(LocalizedStringKey(row.label), value: row.value)
                                    .font(.caption2)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("project-development-automation-edit-preview-row-\(row.id)")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("project-development-automation-edit-preview")
                        .accessibilityHint("Shows the reviewed repository operation, path, branch, replacement summary, and content digest before queueing approval.")
                    }

                    Button {
                        _ = viewModel.enqueueDevelopmentRepositoryEditReview(
                            for: project,
                            task: task,
                            operation: .create,
                            relativePath: repositoryEditRelativePath,
                            contents: repositoryEditContents,
                            expectedSHA256: nil
                        )
                    } label: {
                        Label("Queue repository edit review", systemImage: "doc.badge.gearshape")
                    }
                    .disabled(!canQueueRepositoryEditReview)
                    .help("Queues a scoped create file review after branch preparation evidence exists.")
                    .accessibilityIdentifier("project-development-automation-edit-queue")
                    .accessibilityHint("Adds the reviewed repository edit to Assistant Queue before verification.")
                }

                Button {
                    _ = viewModel.enqueueDevelopmentVerificationReview(for: project, task: task)
                } label: {
                    Label("Queue verification review", systemImage: "checkmark.shield")
                }
                .disabled(progress?.canQueueVerificationReview != true)
                .help("Queues an approved local verification command after branch preparation evidence exists.")
                .accessibilityIdentifier("project-development-automation-verification-queue")
                .accessibilityHint("Adds a local verification command to Assistant Queue before commit or push.")

                // This mirrors the normal Project detail commit gate without
                // loading the full board tree, keeping runtime AX proof fast and
                // focused on the reviewed approval boundary.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Commit review")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Commit file paths", text: $commitRelativePaths)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-commit-paths")

                    TextField("Commit message", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-commit-message")

                    Button {
                        _ = viewModel.enqueueDevelopmentCommitReview(
                            for: project,
                            task: task,
                            relativePathsText: commitRelativePaths,
                            commitMessage: commitMessage
                        )
                    } label: {
                        Label("Queue commit review", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!canQueueCommitReview)
                    .help("Queues a local commit review after verification evidence exists.")
                    .accessibilityIdentifier("project-development-automation-commit-queue")
                    .accessibilityHint("Adds the reviewed file list and commit message to Assistant Queue before push.")
                }

                Button {
                    _ = viewModel.enqueueDevelopmentPushReview(for: project, task: task)
                } label: {
                    Label("Queue branch push review", systemImage: "arrow.up.circle")
                }
                .disabled(progress?.canQueueBranchPushReview != true)
                .help("Queues only the reviewed branch push; pull request creation requires a separate approval.")
                .accessibilityIdentifier("project-development-automation-push-queue")
                .accessibilityHint("Adds the reviewed branch push to Assistant Queue before pull request creation.")

                Button {
                    _ = viewModel.enqueueDevelopmentPullRequestCreationReview(for: project, task: task)
                } label: {
                    Label("Queue pull request creation review", systemImage: "arrow.up.right.square")
                }
                .disabled(progress?.canQueuePullRequestCreationReview != true)
                .help("Queues GitHub pull request creation with the reviewed default base branch, title, and body.")
                .accessibilityIdentifier("project-development-automation-pr-create-queue")
                .accessibilityHint("Adds the pull request creation review to Assistant Queue; review and merge still need separate approval.")

                Button {
                    _ = viewModel.enqueueDevelopmentPullRequestLifecycleReview(
                        for: project,
                        task: task,
                        operation: .reviewGate
                    )
                } label: {
                    Label("Queue pull request review gate", systemImage: "checkmark.shield")
                }
                .disabled(progress?.canQueuePullRequestReviewGate != true)
                .help("Uses the pull request creation receipt to queue review, CI, unresolved thread, and mergeability checks.")
                .accessibilityIdentifier("project-development-automation-pr-review-queue")
                .accessibilityHint("Adds only the receipt-backed pull request review gate to Assistant Queue; merge still needs separate approval.")

                Button {
                    _ = viewModel.enqueueDevelopmentPullRequestLifecycleReview(
                        for: project,
                        task: task,
                        operation: .merge
                    )
                } label: {
                    Label("Queue pull request merge gate", systemImage: "arrow.triangle.merge")
                }
                .disabled(progress?.canQueuePullRequestMergeGate != true)
                .help("Uses the review gate receipt to queue merge approval; execution rechecks the approved pull request before merging.")
                .accessibilityIdentifier("project-development-automation-pr-merge-queue")
                .accessibilityHint("Adds the receipt-backed merge gate to Assistant Queue after review evidence exists.")

                if let queueHandoff = progress?.queueHandoff {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Assistant Queue handoff", systemImage: "tray.full")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text(verbatim: "\(queueHandoff.stateLabel) - \(queueHandoff.title)")
                            .font(.caption2)
                        Text(verbatim: queueHandoff.reviewReason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("project-development-automation-queue-handoff")
                    .accessibilityHint("Shows the matching Assistant Queue item for the current development automation approval.")
                }
            } else {
                if didLoad {
                    EmptyView()
                } else {
                    ProgressView("Loading Project")
                }
            }
        }
        // Runtime smoke uses this narrow surface to avoid loading the full board's
        // heavy AX tree; execution remains deferred to the normal Assistant Queue.
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-development-automation")
        .task {
            viewModel.load()
            didLoad = true
            viewModel.selectedProjectID = projectID
            if let taskID = ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID {
                viewModel.selectedTaskID = taskID
            }
        }
    }

}
