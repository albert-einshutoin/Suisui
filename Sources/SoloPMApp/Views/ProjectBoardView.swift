import SoloPMCore
import SwiftUI

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: ProjectBoardViewModel
    @State private var displayMode: ProjectBoardDisplayMode = .board
    @AppStorage(SoloPMAppearancePreference.storageKey) private var appearancePreference: SoloPMAppearancePreference = .system

    init(viewModel: ProjectBoardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $viewModel.selectedProjectID) {
                    ForEach(viewModel.snapshot.projects) { project in
                        ProjectSidebarRow(project: project)
                            .tag(project.id)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                Toggle(
                    "Show Archived",
                    isOn: Binding(
                        get: { viewModel.showsArchivedProjects },
                        set: { viewModel.setShowsArchivedProjects($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .padding(.horizontal, 10)
                .padding(.top, 8)

                Button {
                    viewModel.createProject()
                } label: {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .navigationTitle("Projects")
        } detail: {
            if let project = viewModel.selectedProject {
                ProjectBoardDetail(
                    project: project,
                    displayMode: $displayMode,
                    appearancePreference: $appearancePreference,
                    viewModel: viewModel
                )
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            openWindow(id: "voice-capture")
                        } label: {
                            Label("Voice Command", systemImage: "mic")
                        }

                        SettingsLink {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                }
                .inspector(isPresented: inspectorBinding) {
                    if let task = viewModel.selectedTask {
                        TaskInspectorView(task: task, viewModel: viewModel)
                            .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
                    }
                }
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Project Board Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if viewModel.isEmptyProjectStateVisible {
                ContentUnavailableView("No Projects", systemImage: "folder")
            }
        }
        .navigationTitle("SoloPM")
        .task {
            viewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
            viewModel.load()
        }
        .preferredColorScheme(appearancePreference.colorScheme)
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.selectedTask != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.selectedTaskID = nil
                }
            }
        )
    }
}

extension Notification.Name {
    static let soloPMProjectBoardDidChange = Notification.Name("dev.solopm.projectBoardDidChange")
}

private enum ProjectBoardDisplayMode: String, CaseIterable, Identifiable {
    case board
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board:
            "Board"
        case .list:
            "List"
        }
    }

    var systemImage: String {
        switch self {
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

private struct ProjectBoardDetail: View {
    let project: ProjectBoardProject
    @Binding var displayMode: ProjectBoardDisplayMode
    @Binding var appearancePreference: SoloPMAppearancePreference
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var composingStatus: ProjectTaskStatus?
    @State private var projectTitle = ""
    @State private var isConfirmingArchive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    ProjectHeaderTitleEditor(
                        project: project,
                        projectTitle: $projectTitle,
                        onSave: { viewModel.updateSelectedProject(title: projectTitle) }
                    )

                    Spacer(minLength: 12)

                    ProjectHeaderActions(
                        project: project,
                        displayMode: $displayMode,
                        appearancePreference: $appearancePreference,
                        onCompleteProject: viewModel.completeSelectedProject,
                        onArchiveProject: { isConfirmingArchive = true },
                        onRestoreProject: viewModel.restoreSelectedProject,
                        onAddTask: { composingStatus = .backlog }
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProjectHeaderTitleEditor(
                        project: project,
                        projectTitle: $projectTitle,
                        onSave: { viewModel.updateSelectedProject(title: projectTitle) }
                    )

                    ProjectHeaderActions(
                        project: project,
                        displayMode: $displayMode,
                        appearancePreference: $appearancePreference,
                        onCompleteProject: viewModel.completeSelectedProject,
                        onArchiveProject: { isConfirmingArchive = true },
                        onRestoreProject: viewModel.restoreSelectedProject,
                        onAddTask: { composingStatus = .backlog }
                    )
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if project.isArchived {
                ArchivedProjectPlaceholder()
            } else {
                switch displayMode {
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
        .onAppear {
            projectTitle = project.title
        }
        .onChange(of: project.id) { _, _ in
            projectTitle = project.title
        }
        .onChange(of: project.title) { _, newTitle in
            projectTitle = newTitle
        }
        .onChange(of: project.isArchived) { _, isArchived in
            if isArchived {
                composingStatus = nil
                viewModel.selectedTaskID = nil
            }
        }
        .confirmationDialog(
            "Archive this project?",
            isPresented: $isConfirmingArchive,
            titleVisibility: .visible
        ) {
            Button("Archive Project", role: .destructive) {
                viewModel.archiveSelectedProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This hides the project from the active board and deadline summaries. Existing local tasks are kept in the SoloPM database.")
        }
    }
}

private struct ArchivedProjectPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Archived Project",
            systemImage: "archivebox",
            description: Text("Restore this project to edit tasks or include it in active deadline summaries.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProjectHeaderTitleEditor: View {
    let project: ProjectBoardProject
    @Binding var projectTitle: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Project title", text: $projectTitle)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(project.title)
                    .frame(minWidth: 160, maxWidth: 520)

                Button(action: onSave) {
                    Label("Save Project", systemImage: "checkmark")
                }
                .labelStyle(.iconOnly)
                .disabled(projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || projectTitle == project.title)
            }

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
    }
}

private struct ProjectHeaderActions: View {
    let project: ProjectBoardProject
    @Binding var displayMode: ProjectBoardDisplayMode
    @Binding var appearancePreference: SoloPMAppearancePreference
    let onCompleteProject: () -> Void
    let onArchiveProject: () -> Void
    let onRestoreProject: () -> Void
    let onAddTask: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                AppearancePicker(preference: $appearancePreference)
                viewPicker
                projectActionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    AppearancePicker(preference: $appearancePreference)
                    viewPicker
                }
                projectActionButtons
            }
        }
    }

    @ViewBuilder
    private var projectActionButtons: some View {
        if project.isArchived {
            restoreProjectButton
        } else {
            HStack(spacing: 8) {
                completeProjectButton
                archiveProjectButton
                addTaskButton
            }
        }
    }

    private var viewPicker: some View {
        Picker("View", selection: $displayMode) {
            ForEach(ProjectBoardDisplayMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 168)
    }

    private var completeProjectButton: some View {
        Button(action: onCompleteProject) {
            Label("Complete Project", systemImage: "checkmark.seal")
        }
        .disabled(project.isCompleted)
    }

    private var archiveProjectButton: some View {
        Button(role: .destructive, action: onArchiveProject) {
            Label("Archive Project", systemImage: "archivebox")
        }
    }

    private var restoreProjectButton: some View {
        Button(action: onRestoreProject) {
            Label("Restore Project", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.borderedProminent)
    }

    private var addTaskButton: some View {
        Button(action: onAddTask) {
            Label("Add Task", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("n", modifiers: [.command])
    }
}

private struct AppearancePicker: View {
    @Binding var preference: SoloPMAppearancePreference

    var body: some View {
        Picker("Appearance", selection: $preference) {
            ForEach(SoloPMAppearancePreference.allCases) { preference in
                Label(preference.label, systemImage: preference.systemImage)
                    .tag(preference)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 210)
        .help("Switch between system, light, and dark appearance")
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
        .scrollIndicators(.visible)
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
                Label(column.title, systemImage: column.status.systemImage)
                    .font(.headline)
                Spacer()
                Text("\(column.tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onStartComposing) {
                    Label("Add", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }

            if isDropTargeted {
                Label("Drop to move to \(column.title)", systemImage: "arrow.down.doc")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
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
                            .foregroundStyle(.secondary)
                        Text("No tasks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                    .padding(10)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(column.tasks) { task in
                    BoardTaskCard(
                        task: task,
                        isSelected: selectedTaskID == task.id,
                        onSelect: { onSelectTask(task.id) },
                        onMoveStatus: { status in onMoveTask(task.id, status) }
                    )
                    .draggable(String(task.id))
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
        .frame(width: 190, alignment: .topLeading)
        .padding(8)
        .background(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { taskIDs, _ in
            onMoveDroppedTasks(taskIDs, column.status)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
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

            TextField("Detail", text: $detail, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...3)

            HStack {
                Picker("Priority", selection: $priority) {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Text(priority.label).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                TextField("Due", text: $dueAt)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button(action: submit) {
                    Label("Add", systemImage: "checkmark")
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: onCancel) {
                    Label("Cancel", systemImage: "xmark")
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(task.title)

                Spacer(minLength: 6)

                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .help("Drag to another status column")
                    .accessibilityLabel("Drag to another status column")
            }

            if !task.detail.isEmpty {
                Text(task.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .help(task.detail)
            }

            TaskMetadataRow(task: task)
            TaskStatusMoveControls(task: task, onMove: onMoveStatus)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.16))
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onSelect)
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

            statusMoveButton(
                title: "Move to next status",
                systemImage: "chevron.right",
                targetStatus: task.status.nextStatus
            )
        }
        .buttonStyle(.borderless)
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
    }
}

private struct TaskMetadataRow: View {
    let task: ProjectBoardTask

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                priorityLabel

                Spacer(minLength: 8)

                dueLabel
            }

            VStack(alignment: .leading, spacing: 4) {
                priorityLabel
                dueLabel
            }
        }
        .font(.caption)
    }

    private var priorityLabel: some View {
        Label(task.priority.label, systemImage: "flag")
            .foregroundStyle(task.priority.color)
            .lineLimit(1)
    }

    @ViewBuilder
    private var dueLabel: some View {
        if let dueLabel = task.dueLabel {
            Label(dueLabel, systemImage: "calendar")
                .lineLimit(1)
                .truncationMode(.tail)
                .help(dueLabel)
        }
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
            Section("Task") {
                TextField("Title", text: $title)
                TextField("Detail", text: $detail, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section("Fields") {
                Picker("Status", selection: $status) {
                    ForEach(ProjectTaskStatus.allCases) { status in
                        Label(status.title, systemImage: status.systemImage)
                            .tag(status)
                    }
                }

                Picker("Priority", selection: $priority) {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Text(priority.label)
                            .tag(priority)
                    }
                }

                TextField("Due", text: $dueAt)
            }

            Section {
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
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete Task", systemImage: "trash")
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete this task?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                viewModel.deleteSelectedTask()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the task from the local SoloPM database.")
        }
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

private extension ProjectTaskPriority {
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

private extension ProjectTaskStatus {
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
