import SoloPMCore
import Dispatch
import SwiftUI
import UniformTypeIdentifiers

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: ProjectBoardViewModel
    @AppStorage(ProjectBoardSelectionPersistence.storageKey) private var persistedSelectedDestinationRawValue = ProjectBoardSelectionPersistence.defaultRawValue
    @State private var displayMode: ProjectBoardDisplayMode = .board
    @State private var selectedDestination: ProjectBoardSidebarDestination? = .today
    @State private var isInspectorPresented = true
    @State private var isExportingTaskInterop = false
    @State private var isImportingTaskInterop = false
    @State private var taskInteropExportDocument = TaskInteropFileDocument(data: Data())

    init(viewModel: ProjectBoardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedDestination) {
                    Section {
                        ProjectBoardSidebarDestinationRow(destination: .inbox, count: viewModel.inboxTasks.count)
                            .tag(ProjectBoardSidebarDestination.inbox)
                        ProjectBoardSidebarDestinationRow(destination: .today, count: viewModel.todayTasks().count)
                            .tag(ProjectBoardSidebarDestination.today)
                    }

                    Section("Projects") {
                        ForEach(viewModel.snapshot.projects.filter { $0.id != viewModel.inboxProject?.id }) { project in
                            ProjectSidebarRow(project: project)
                                .tag(ProjectBoardSidebarDestination.project(project.id))
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
                .accessibilityLabel("Add Project")
                .accessibilityHint("Creates a new local project and selects it.")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .navigationTitle("SoloPM")
        } detail: {
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
                        TodayWorkflowView(viewModel: viewModel)
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
            .toolbar {
                ToolbarItemGroup {
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
                    }
                    .help("Import, export, and sync task data")

                    Button {
                        openWindow(id: "voice-capture")
                    } label: {
                        Label("Voice Command", systemImage: "mic")
                    }
                }
            }
            .inspector(isPresented: inspectorBinding) {
                Group {
                    if let task = viewModel.selectedTask {
                        TaskInspectorView(task: task, viewModel: viewModel)
                    } else if let project = selectedProjectForInspector {
                        ProjectInspectorView(project: project, viewModel: viewModel)
                    } else {
                        EmptyView()
                    }
                }
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
            }
        }
        .navigationTitle("SoloPM")
        .task {
            viewModel.load()
            restoreSelectedDestinationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
            viewModel.load()
            restoreSelectedDestinationIfNeeded()
        }
        .onChange(of: selectedDestination) { _, destination in
            persistSelectedDestination(destination)
            applySelectedDestination(destination)
        }
        .onChange(of: viewModel.selectedTaskID) { _, selectedTaskID in
            if selectedTaskID != nil {
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

    private var selectedProjectForInspector: ProjectBoardProject? {
        guard case .project(let projectID) = selectedDestination else {
            return nil
        }
        return viewModel.snapshot.projects.first { $0.id == projectID }
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
        case .inbox, .today, .none:
            viewModel.selectedTaskID = nil
            isInspectorPresented = false
        }
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

extension Notification.Name {
    static let soloPMProjectBoardDidChange = Notification.Name("dev.solopm.projectBoardDidChange")
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

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(project.title)
                Text(project.isArchived ? "Archived" : "\(project.taskCount) tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.accessibilitySidebarLabel)
        .accessibilityIdentifier("project-sidebar-row-\(project.id)")
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
        let state = isArchived ? "Archived" : isCompleted ? "Completed" : "Active"
        let taskLabel = taskCount == 1 ? "1 task" : "\(taskCount) tasks"
        return "\(title), \(state), \(taskLabel)"
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
                    ProjectArtifactSection(project: project, viewModel: viewModel)
                    ProjectTimelineSection(project: project)
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
            Text(label)
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
                                Text(task.dueLabel ?? task.status.title)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Label(task.priority.label, systemImage: "flag")
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
                            Text(artifact.createdState.label)
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

    private var dueTasks: [ProjectBoardTask] {
        project.tasks
            .filter { $0.dueAt != nil }
            .sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
    }

    var body: some View {
        ProjectOverviewPanel(title: "Timeline", systemImage: "calendar") {
            if dueTasks.isEmpty {
                Text("No due dates yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dueTasks.prefix(5)) { task in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(task.status.tint)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(task.dueLabel ?? "")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(task.title)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Project timeline item \(task.title)")
                    .accessibilityValue(task.dueLabel ?? "No due date")
                }
            }
        }
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
                            viewModel.moveTask(id: suggestedTask.id, to: .inProgress)
                        } label: {
                            Label("Unblock", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .controlSize(.small)
                        .help("Move the suggested blocked task to In Progress")
                        .accessibilityIdentifier("project-local-suggestion-unblock-task")
                        .accessibilityHint("Moves the suggested blocked task back to In Progress in the local database.")
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
            return "\(task.title) is blocked. Resolve it before adding more work."
        }
        if task.priority == .high {
            return "\(task.title) is high priority. Make it the next focused task."
        }
        if let dueAt = task.dueAt {
            return "\(task.title) is the next due task at \(dueAt)."
        }
        return "Continue with \(task.title)."
    }
}

private struct ProjectOverviewPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
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
                Label(mode.label, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 252)
    }

    private var addTaskButton: some View {
        Button(action: onAddTask) {
            Label("Add Task", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(project.isArchived)
        .help("Add task to \(project.title)")
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
                        onMoveDroppedTasks: { taskIDs, status in
                            viewModel.moveDroppedTasks(ids: taskIDs, to: status)
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
    let onMoveDroppedTasks: ([Int64], ProjectTaskStatus) -> Bool

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(column.title, systemImage: column.status.systemImage)
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
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
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
                    BoardTaskCard(
                        task: task,
                        isSelected: selectedTaskID == task.id,
                        onSelect: { onSelectTask(task.id) },
                        onMoveStatus: { status in onMoveTask(task.id, status) }
                    )
                    .draggable(ProjectTaskDragPayload(taskID: task.id)) {
                        BoardTaskDragPreview(task: task)
                    }
                    .contextMenu {
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
                                    Label(status.title, systemImage: status.systemImage)
                                }
                            }
                        } label: {
                            Label("Move To", systemImage: "arrow.right.arrow.left")
                        }
                    }
                }
            }
        }
        .frame(width: 244, alignment: .topLeading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? column.status.tint.opacity(0.72) : Color.secondary.opacity(0.14), lineWidth: isDropTargeted ? 1.5 : 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .dropDestination(for: ProjectTaskDragPayload.self) { payloads, _ in
            onMoveDroppedTasks(payloads.map(\.taskID), column.status)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }
}

private struct ProjectTaskDragPayload: Codable, Transferable {
    let taskID: Int64

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .soloPMProjectTask)
    }
}

private extension UTType {
    static let soloPMProjectTask = UTType(exportedAs: "dev.solopm.project-task")
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
                        Text(priority.label).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 112)
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
            .frame(width: 4)
            .frame(height: 44)
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
                Label(task.status.title, systemImage: "arrow.right.arrow.left")
                    .foregroundStyle(task.status.tint)
                Label(task.priority.label, systemImage: "flag")
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

            Text(task.status.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 76)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .help(task.status.title)
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
        .frame(minWidth: 64, maxWidth: .infinity, minHeight: 24, alignment: .leading)
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
                Label(task.status.title, systemImage: task.status.systemImage)
            }

            TableColumn("Priority") { task in
                Label(task.priority.label, systemImage: "flag")
                    .foregroundStyle(task.priority.color)
            }

            TableColumn("Due") { task in
                Text(task.dueLabel ?? "")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProjectInspectorView: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel

    @State private var title: String
    @State private var isConfirmingArchive = false
    @State private var isConfirmingDelete = false

    init(project: ProjectBoardProject, viewModel: ProjectBoardViewModel) {
        self.project = project
        self.viewModel = viewModel
        _title = State(initialValue: project.title)
    }

    var body: some View {
        Form {
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

            Section("Suggestion") {
                ProjectInspectorSuggestionSection(project: project, viewModel: viewModel)
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
            return "Restore this project before editing tasks or including it in active summaries."
        case .createFirstTask:
            return "Create a first concrete task so the project has a next action."
        case .completeProject:
            return "All tasks are done. Complete the project to keep active views focused."
        case .openTask:
            return "Open the highest-signal task and decide its next move in the inspector."
        case .none:
            return "No project-level suggestion is needed right now."
        }
    }

    private func applySuggestion() {
        switch suggestionAction {
        case .restoreProject:
            viewModel.restoreSelectedProject()
        case .createFirstTask:
            _ = viewModel.createTask(title: "Define next action", projectID: project.id, status: .backlog)
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

    @State private var title: String
    @State private var detail: String
    @State private var status: ProjectTaskStatus
    @State private var priority: ProjectTaskPriority
    @State private var dueAt: String
    @State private var isConfirmingDelete = false

    init(task: ProjectBoardTask, viewModel: ProjectBoardViewModel) {
        self.task = task
        self.viewModel = viewModel
        _title = State(initialValue: task.title)
        _detail = State(initialValue: task.detail)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        _dueAt = State(initialValue: task.dueAt ?? "")
    }

    var body: some View {
        Form {
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
                        Label(status.title, systemImage: status.systemImage)
                            .tag(status)
                    }
                }
                .accessibilityIdentifier("task-inspector-status")

                Picker("Priority", selection: $priority) {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Text(priority.label)
                            .tag(priority)
                    }
                }
                .accessibilityIdentifier("task-inspector-priority")

                TextField("Due", text: $dueAt)
                    .accessibilityIdentifier("task-inspector-due")
            }

            Section("Suggestion") {
                TaskInspectorSuggestionSection(task: task, viewModel: viewModel)
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

            Section("Danger Zone") {
                if isConfirmingDelete {
                    InspectorDestructiveConfirmation(
                        title: "Delete this task?",
                        message: "This removes the task from the local SoloPM database.",
                        confirmTitle: "Delete Task",
                        confirmSystemImage: "trash",
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
                Button(role: .destructive, action: confirmAction) {
                    Label(confirmTitle, systemImage: confirmSystemImage)
                }
                .accessibilityIdentifier("\(accessibilityIdentifier)-confirm")
                .accessibilityLabel(confirmTitle)
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
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(value)
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
            return "This task is already complete."
        }
        if task.status == .blocked {
            return "If the blocker is resolved, move this task back into active work."
        }
        if task.priority == .high {
            return "High-priority task: move it forward when the next step is clear."
        }
        return "Move this task to the next status when you are ready."
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
