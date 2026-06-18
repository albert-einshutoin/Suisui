import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: ProjectBoardViewModel
    @State private var displayMode: ProjectBoardDisplayMode = .board

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
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Add a project")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .navigationTitle("Projects")
        } detail: {
            if let project = viewModel.selectedProject {
                ProjectBoardDetail(
                    project: project,
                    displayMode: $displayMode,
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
                        .keyboardShortcut(",", modifiers: [.command])
                        .help("Open Settings")
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
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var composingStatus: ProjectTaskStatus?
    @State private var projectTitle = ""
    @State private var isConfirmingArchive = false
    @State private var isConfirmingDelete = false

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
                        onCompleteProject: viewModel.completeSelectedProject,
                        onArchiveProject: { isConfirmingArchive = true },
                        onRestoreProject: viewModel.restoreSelectedProject,
                        onDeleteProject: { isConfirmingDelete = true },
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
                        onCompleteProject: viewModel.completeSelectedProject,
                        onArchiveProject: { isConfirmingArchive = true },
                        onRestoreProject: viewModel.restoreSelectedProject,
                        onDeleteProject: { isConfirmingDelete = true },
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
        .confirmationDialog(
            "Delete this project?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                viewModel.deleteSelectedProject()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the project, its local tasks, deadline rules, artifact links, calendar links, and reminder links from SoloPM.")
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
    let onCompleteProject: () -> Void
    let onArchiveProject: () -> Void
    let onRestoreProject: () -> Void
    let onDeleteProject: () -> Void
    let onAddTask: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                viewPicker
                projectActionButtons
            }

            VStack(alignment: .leading, spacing: 8) {
                viewPicker
                projectActionButtons
            }
        }
    }

    @ViewBuilder
    private var projectActionButtons: some View {
        if project.isArchived {
            HStack(spacing: 8) {
                restoreProjectButton
                deleteProjectButton
            }
        } else {
            HStack(spacing: 8) {
                completeProjectButton
                archiveProjectButton
                deleteProjectButton
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

    private var deleteProjectButton: some View {
        Button(role: .destructive, action: onDeleteProject) {
            Label("Delete Project", systemImage: "trash")
        }
    }

    private var addTaskButton: some View {
        Button(action: onAddTask) {
            Label("Add Task", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("n", modifiers: [.command])
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
    @State private var isPointerHovered = false

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

                    Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.caption)
                        .foregroundStyle(task.status.tint)
                        .padding(4)
                        .background(task.status.tint.opacity(isPointerHovered ? 0.18 : 0.10), in: Circle())
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
        .onTapGesture(perform: onSelect)
        .onHover { isPointerHovered = $0 }
        .animation(.snappy(duration: 0.16), value: isPointerHovered)
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

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
