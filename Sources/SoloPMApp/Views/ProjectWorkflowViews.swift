import SoloPMCore
import SwiftUI

enum ProjectBoardSidebarDestination: Hashable {
    case inbox
    case today
    case project(Int64)

    var title: String {
        switch self {
        case .inbox:
            "Inbox"
        case .today:
            "Today"
        case .project:
            "Project"
        }
    }

    var systemImage: String {
        switch self {
        case .inbox:
            "tray"
        case .today:
            "sun.max"
        case .project:
            "folder"
        }
    }
}

struct ProjectBoardSidebarDestinationRow: View {
    let destination: ProjectBoardSidebarDestination
    let count: Int

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(destination.title)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } icon: {
            Image(systemName: destination.systemImage)
        }
    }
}

struct TodayWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var tasks: [ProjectBoardTask] {
        viewModel.todayTasks()
    }

    var body: some View {
        WorkflowTaskSurface(
            title: "Today",
            subtitle: "\(tasks.count) open due or overdue tasks",
            systemImage: "sun.max",
            tasks: tasks,
            emptyTitle: "No tasks due today",
            emptyDescription: "Captured work remains in Inbox until it is scheduled or moved to a project.",
            viewModel: viewModel,
            footer: {
                TodaySuggestionPanel(tasks: tasks, viewModel: viewModel)
            }
        )
    }
}

struct InboxWorkflowView: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var quickTitle = ""

    private var tasks: [ProjectBoardTask] {
        viewModel.inboxTasks
    }

    var body: some View {
        WorkflowTaskSurface(
            title: "Inbox",
            subtitle: "\(tasks.count) unprocessed captured items",
            systemImage: "tray",
            tasks: tasks,
            emptyTitle: "Inbox is clear",
            emptyDescription: "Voice notes, manual captures, and unassigned tasks land here before classification.",
            viewModel: viewModel,
            headerAccessory: {
                HStack(spacing: 8) {
                    TextField("Capture an inbox item", text: $quickTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addInboxTask)
                    Button(action: addInboxTask) {
                        Label("Quick Add", systemImage: "plus")
                    }
                    .disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            },
            footer: {
                InboxActionPanel(task: viewModel.selectedTask, viewModel: viewModel)
            }
        )
    }

    private func addInboxTask() {
        let title = quickTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let inboxID = viewModel.inboxProject?.id else {
            return
        }
        _ = viewModel.createTask(title: title, projectID: inboxID, status: .backlog)
        quickTitle = ""
    }
}

private struct WorkflowTaskSurface<HeaderAccessory: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tasks: [ProjectBoardTask]
    let emptyTitle: String
    let emptyDescription: String
    @ObservedObject var viewModel: ProjectBoardViewModel
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var footer: () -> Footer

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tasks: [ProjectBoardTask],
        emptyTitle: String,
        emptyDescription: String,
        viewModel: ProjectBoardViewModel,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tasks = tasks
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.viewModel = viewModel
        self.headerAccessory = headerAccessory
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    WorkflowHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                    Spacer(minLength: 12)
                    headerAccessory()
                }

                VStack(alignment: .leading, spacing: 10) {
                    WorkflowHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                    headerAccessory()
                }
            }

            if tasks.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: systemImage,
                    description: Text(emptyDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            WorkflowTaskRow(
                                task: task,
                                projectTitle: viewModel.projectTitle(for: task),
                                isSelected: viewModel.selectedTaskID == task.id,
                                onSelect: { viewModel.selectedTaskID = task.id }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            footer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WorkflowHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
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

private struct WorkflowTaskRow: View {
    let task: ProjectBoardTask
    let projectTitle: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: task.status == .done ? "checkmark.square.fill" : "square")
                    .foregroundStyle(task.status.tint)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(task.title)
                    HStack(spacing: 8) {
                        Label(projectTitle, systemImage: "folder")
                        Label(task.status.title, systemImage: task.status.systemImage)
                        if let dueLabel = task.dueLabel {
                            Label(dueLabel, systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                Label(task.priority.label, systemImage: "flag")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(task.priority.color)
                    .labelStyle(.iconOnly)
                    .help(task.priority.label)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.12))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct InboxActionPanel: View {
    let task: ProjectBoardTask?
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Classify Selected Item")
                .font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    actionButtons
                }
            }
            .disabled(task == nil)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            viewModel.markSelectedTaskAsTask()
        } label: {
            Label("Make Task", systemImage: "checkmark.circle")
        }
        Button {
            viewModel.convertSelectedTaskToProject()
        } label: {
            Label("Make Project", systemImage: "folder.badge.plus")
        }
        Button {
            viewModel.scheduleSelectedTaskForToday()
        } label: {
            Label("Schedule Today", systemImage: "calendar.badge.plus")
        }
        Button {
            viewModel.deferSelectedTaskForLater()
        } label: {
            Label("Review Later", systemImage: "clock")
        }
    }
}

private struct TodaySuggestionPanel: View {
    let tasks: [ProjectBoardTask]
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        Label {
            Text(suggestion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } icon: {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private var suggestion: String {
        if let highPriority = tasks.first(where: { $0.priority == .high }) {
            return "Start with \(highPriority.title) in \(viewModel.projectTitle(for: highPriority))."
        }
        if let firstTask = tasks.first {
            return "Start with \(firstTask.title), then clear the next due item."
        }
        return "No due work is scheduled for today."
    }
}
