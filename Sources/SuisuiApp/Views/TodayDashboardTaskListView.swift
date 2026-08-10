import SuisuiCore
import SwiftUI

struct TodayDashboardTaskListView: View {
    let tasks: [ProjectBoardTask]
    let rows: [TodayTaskRowSnapshot]
    let selectedTaskID: Int64?
    let isWide: Bool
    let toggleCompletion: (Int64) -> Void
    let selectTask: (ProjectBoardTask) -> Void
    let addTask: () -> Void

    init(
        tasks: [ProjectBoardTask],
        rows: [TodayTaskRowSnapshot],
        selectedTaskID: Int64?,
        isWide: Bool = false,
        toggleCompletion: @escaping (Int64) -> Void,
        selectTask: @escaping (ProjectBoardTask) -> Void,
        addTask: @escaping () -> Void = {}
    ) {
        self.tasks = tasks
        self.rows = rows
        self.selectedTaskID = selectedTaskID
        self.isWide = isWide
        self.toggleCompletion = toggleCompletion
        self.selectTask = selectTask
        self.addTask = addTask
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            HStack(spacing: SuisuiSpacing.sm) {
                Label("Today", systemImage: "checklist")
                    .font(SuisuiTypography.sectionTitle)
                taskCountBadge
                Spacer(minLength: 0)
                Button(action: addTask) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Add Task")
            }
            Divider()
            if tasks.isEmpty {
                ContentUnavailableView("No tasks due today", systemImage: "tray")
            } else if isWide {
                wideTaskTable
            } else {
                compactTaskRows
            }
            Divider()
            Button(action: addTask) {
                Label("Add Task", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
            .accessibilityIdentifier("today-task-list-add")
        }
        .todayDashboardCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-task-list")
    }

    private var taskCountBadge: some View {
        Text("\(tasks.count)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.65), in: Capsule())
            .accessibilityLabel(localizedTaskCount(tasks.count))
    }

    private var compactTaskRows: some View {
        ForEach(Array(zip(tasks, rows)), id: \.0.id) { task, row in
            HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                completionButton(for: task)
                Button { selectTask(task) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title).font(.body.weight(.medium))
                        Text([row.projectTitle, row.priorityLabel, row.timeLabel].compactMap { $0 }.joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityValue(selectedTaskID == task.id ? "Selected" : "")
                statusImage(for: task)
            }
            .padding(.vertical, SuisuiSpacing.sm)
            .padding(.horizontal, SuisuiSpacing.md)
            .background(selectedTaskID == task.id ? SuisuiBrand.soloBlue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
        }
    }

    private var wideTaskTable: some View {
        Grid(alignment: .leading, horizontalSpacing: SuisuiSpacing.md, verticalSpacing: SuisuiSpacing.xs) {
            GridRow {
                Color.clear.frame(width: 22)
                Text("Task")
                    .frame(width: 280, alignment: .leading)
                    .gridColumnAlignment(.leading)
                Text("Project")
                    .frame(width: 120, alignment: .leading)
                    .gridColumnAlignment(.leading)
                Text("Priority")
                    .frame(width: 64, alignment: .leading)
                    .gridColumnAlignment(.leading)
                Text("Time")
                    .frame(width: 64, alignment: .leading)
                    .gridColumnAlignment(.leading)
                Color.clear.frame(width: 18)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider()
                .gridCellColumns(6)
            ForEach(Array(zip(tasks, rows)), id: \.0.id) { task, row in
                GridRow(alignment: .firstTextBaseline) {
                    completionButton(for: task)
                    Button { selectTask(task) } label: {
                        Text(row.title)
                            .font(.body.weight(.medium))
                            .lineLimit(2)
                            .frame(width: 280, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selectedTaskID == task.id ? "Selected" : "")
                    Text(row.projectTitle.isEmpty ? "—" : row.projectTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.55), in: Capsule())
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)
                    Text(row.priorityLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(priorityColor(for: task))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(priorityColor(for: task).opacity(0.12), in: Capsule())
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1)
                    Text(row.timeLabel ?? "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                        .lineLimit(1)
                    statusImage(for: task)
                }
                .padding(.vertical, SuisuiSpacing.xs)
                .padding(.horizontal, SuisuiSpacing.sm)
                .background(selectedTaskID == task.id ? SuisuiBrand.soloBlue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
                Divider()
                    .gridCellColumns(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func priorityColor(for task: ProjectBoardTask) -> Color {
        switch task.priority {
        case .high: Color(nsColor: .systemRed)
        case .medium: Color(nsColor: .systemOrange)
        case .low: Color(nsColor: .systemGreen)
        }
    }

    private func completionButton(for task: ProjectBoardTask) -> some View {
        Button { toggleCompletion(task.id) } label: {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(task.status == .done ? "Mark incomplete" : "Mark complete")
        .accessibilityIdentifier("workflow-task-completion-\(task.id)")
    }

    private func statusImage(for task: ProjectBoardTask) -> some View {
        Image(systemName: task.status.systemImage)
            .foregroundStyle(task.status.tint)
            .accessibilityHidden(true)
    }
}
