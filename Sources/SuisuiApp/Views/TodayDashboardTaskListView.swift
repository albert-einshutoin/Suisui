import SuisuiCore
import SwiftUI

struct TodayDashboardTaskListView: View {
    let tasks: [ProjectBoardTask]
    let rows: [TodayTaskRowSnapshot]
    let selectedTaskID: Int64?
    let toggleCompletion: (Int64) -> Void
    let selectTask: (ProjectBoardTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Label("Today", systemImage: "checklist")
                .font(SuisuiTypography.sectionTitle)
            if tasks.isEmpty {
                ContentUnavailableView("No tasks due today", systemImage: "tray")
            } else {
                ForEach(Array(zip(tasks, rows)), id: \.0.id) { task, row in
                    HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                        Button { toggleCompletion(task.id) } label: {
                            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(task.status == .done ? "Mark incomplete" : "Mark complete")
                        .accessibilityIdentifier("workflow-task-completion-\(task.id)")

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

                        Image(systemName: task.status.systemImage)
                            .foregroundStyle(task.status.tint)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, SuisuiSpacing.sm)
                    .padding(.horizontal, SuisuiSpacing.md)
                    .background(selectedTaskID == task.id ? SuisuiBrand.soloBlue.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: SuisuiRadius.card))
                }
            }
        }
        .soloCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-task-list")
    }
}
