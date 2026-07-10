import Foundation
import SoloPMCore
import SwiftUI
import UniformTypeIdentifiers

/// One optional next-step button for an empty workflow surface, so empty
/// states can point at the most useful capture action instead of dead-ending.
struct WorkflowEmptyStateAction {
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
    let handler: () -> Void
}

struct WorkflowTaskSurface<HeaderAccessory: View, Footer: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tasks: [ProjectBoardTask]
    let emptyTitle: String
    let emptyDescription: String
    let emptyStateAction: WorkflowEmptyStateAction?
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onSelectTask: ((ProjectBoardTask) -> Void)?
    let fillsAvailableHeight: Bool
    let triageSummary: (ProjectBoardTask) -> InboxTriageSummary?
    @ViewBuilder var headerAccessory: () -> HeaderAccessory
    @ViewBuilder var footer: () -> Footer

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tasks: [ProjectBoardTask],
        emptyTitle: String,
        emptyDescription: String,
        emptyStateAction: WorkflowEmptyStateAction? = nil,
        viewModel: ProjectBoardViewModel,
        onSelectTask: ((ProjectBoardTask) -> Void)? = nil,
        fillsAvailableHeight: Bool = true,
        triageSummary: @escaping (ProjectBoardTask) -> InboxTriageSummary? = { _ in nil },
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory = { EmptyView() },
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tasks = tasks
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.emptyStateAction = emptyStateAction
        self.viewModel = viewModel
        self.onSelectTask = onSelectTask
        self.fillsAvailableHeight = fillsAvailableHeight
        self.triageSummary = triageSummary
        self.headerAccessory = headerAccessory
        self.footer = footer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header accessories can contain the Today command surface and
            // several localized actions. A single vertical proposal avoids
            // ViewThatFits recursively sizing both header branches while
            // preserving the header-before-accessory reading/action order.
            VStack(alignment: .leading, spacing: 10) {
                WorkflowHeader(title: title, subtitle: subtitle, systemImage: systemImage)
                headerAccessory()
            }

            if tasks.isEmpty {
                ContentUnavailableView {
                    Label(LocalizedStringKey(emptyTitle), systemImage: systemImage)
                } description: {
                    Text(LocalizedStringKey(emptyDescription))
                } actions: {
                    if let emptyStateAction {
                        Button {
                            emptyStateAction.handler()
                        } label: {
                            Label(LocalizedStringKey(emptyStateAction.title), systemImage: emptyStateAction.systemImage)
                        }
                        .accessibilityIdentifier(emptyStateAction.accessibilityIdentifier)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(tasks) { task in
                            WorkflowTaskRow(
                                task: task,
                                projectTitle: viewModel.projectTitle(for: task),
                                triageSummary: triageSummary(task),
                                isSelected: viewModel.selectedTaskID == task.id,
                                onSelect: { selectTask(task) },
                                onToggleCompletion: { viewModel.toggleTaskCompletion(id: task.id) }
                            )
                            .draggable(String(task.id))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            footer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
    }

    private func selectTask(_ task: ProjectBoardTask) {
        if let onSelectTask {
            onSelectTask(task)
            return
        }
        viewModel.selectedTaskID = task.id
    }
}

struct WorkflowDoneToggle: View {
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        Toggle(isOn: Binding(
            get: { viewModel.showsCompletedWorkflowTasks },
            set: { viewModel.setShowsCompletedWorkflowTasks($0) }
        )) {
            Label("Show Done", systemImage: viewModel.showsCompletedWorkflowTasks ? "checkmark.square" : "square")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .help("Show completed tasks in Inbox and Today")
        .accessibilityIdentifier("workflow-show-completed-toggle")
        .accessibilityLabel("Show completed tasks")
        .accessibilityValue(viewModel.showsCompletedWorkflowTasks ? "On" : "Off")
    }
}

struct WorkflowHeader: View {
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

private struct WorkflowTaskRow: View {
    let task: ProjectBoardTask
    let projectTitle: String
    let triageSummary: InboxTriageSummary?
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleCompletion: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onToggleCompletion) {
                Label {
                    Text(LocalizedStringKey(toggleCompletionTitle))
                } icon: {
                    Image(systemName: task.status == .done ? "checkmark.square.fill" : "square")
                }
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(task.status.tint)
            .help(LocalizedStringKey(toggleCompletionTitle))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(toggleCompletionAccessibilityLabel)
            .accessibilityHint("Updates the task status in the local SoloPM database without opening the inspector.")
            .accessibilityIdentifier("workflow-task-completion-\(task.id)")

            Button(action: onSelect) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(task.title)
                        HStack(spacing: 8) {
                            Label(projectTitle, systemImage: "folder")
                            Label {
                                Text(LocalizedStringKey(task.status.title))
                            } icon: {
                                Image(systemName: task.status.systemImage)
                            }
                            if let dueLabel = task.todayDueDisplayLabel() {
                                Label(
                                    dueLabel,
                                    systemImage: isOverdue ? "calendar.badge.exclamationmark" : "calendar"
                                )
                                .foregroundStyle(isOverdue ? .red : .secondary)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        if let triageSummary {
                            InboxTriagePill(summary: triageSummary)
                                .accessibilityIdentifier("inbox-row-triage-summary-\(task.id)")
                        }
                    }

                    Spacer(minLength: 8)

                    Label {
                        Text(LocalizedStringKey(task.priority.label))
                    } icon: {
                        Image(systemName: "flag")
                    }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(task.priority.color)
                        .help(LocalizedStringKey(task.priority.label))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Open task \(task.title)")
            .accessibilityValue(workflowAccessibilityValue)
            .accessibilityHint("Selects this task so Inbox actions or task inspector edits can use it.")
            .accessibilityIdentifier("workflow-task-row-\(task.id)")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.12))
        }
        .accessibilityElement(children: .contain)
    }

    private var workflowAccessibilityValue: String {
        var values = [
            "Project: \(projectTitle)",
            "\(String(localized: "Status")): \(String(localized: String.LocalizationValue(task.status.title)))",
            "\(String(localized: "Priority")): \(String(localized: String.LocalizationValue(task.priority.label)))"
        ]
        if let triageSummary {
            values.append(triageSummary.accessibilityValue)
        }
        if let dueLabel = task.todayDueDisplayLabel() {
            values.append("\(String(localized: "Due")): \(dueLabel)")
        }
        return values.joined(separator: ", ")
    }

    private var toggleCompletionTitle: String {
        task.status == .done ? "Reopen task" : "Complete task"
    }

    private var toggleCompletionAccessibilityLabel: String {
        if task.status == .done {
            return localizedDisplay("Reopen task %@", task.title)
        }
        return localizedDisplay("Complete task %@", task.title)
    }

    private var isOverdue: Bool {
        task.isOverdueForToday()
    }

}

private struct InboxTriagePill: View {
    let summary: InboxTriageSummary

    var body: some View {
        Label {
            Text("\(summary.sourceLabel) · \(summary.interpretationLabel)")
        } icon: {
            Image(systemName: summary.systemImage)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Inbox source and interpretation")
        .accessibilityValue(summary.accessibilityValue)
    }

    private var tint: Color {
        switch summary.tintName {
        case "blue":
            .blue
        case "red":
            .red
        default:
            .secondary
        }
    }
}
