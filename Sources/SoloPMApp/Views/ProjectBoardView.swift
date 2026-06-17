import SwiftUI

struct ProjectBoardSnapshot: Equatable {
    var projects: [ProjectBoardProject]

    static let demo = ProjectBoardSnapshot(
        projects: [
            ProjectBoardProject(
                id: "public-alpha",
                title: "Public Alpha",
                subtitle: "Packaging, review, and launch readiness",
                columns: [
                    ProjectBoardColumn(
                        id: "backlog",
                        title: "Backlog",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-feedback",
                                title: "Draft feedback issue template",
                                detail: "Keep reports privacy-safe and actionable.",
                                priority: .medium,
                                dueLabel: "This week"
                            ),
                            ProjectBoardTask(
                                id: "task-shortcuts",
                                title: "Polish voice shortcut settings",
                                detail: "Show conflicts and recovery state.",
                                priority: .low,
                                dueLabel: nil
                            )
                        ]
                    ),
                    ProjectBoardColumn(
                        id: "planned",
                        title: "Planned",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-release-notes",
                                title: "Prepare alpha release notes",
                                detail: "Summarize scope, limitations, and install steps.",
                                priority: .high,
                                dueLabel: "Tomorrow"
                            )
                        ]
                    ),
                    ProjectBoardColumn(
                        id: "in-progress",
                        title: "In Progress",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-review-flow",
                                title: "Review generated ActionPlan",
                                detail: "Approve project and task writes before execution.",
                                priority: .high,
                                dueLabel: "Today"
                            )
                        ]
                    ),
                    ProjectBoardColumn(
                        id: "blocked",
                        title: "Blocked",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-notarization",
                                title: "Notarization dry run",
                                detail: "Requires local Developer ID credentials.",
                                priority: .medium,
                                dueLabel: nil
                            )
                        ]
                    ),
                    ProjectBoardColumn(
                        id: "done",
                        title: "Done",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-sparkle",
                                title: "Sparkle update foundation",
                                detail: "Bundle metadata and appcast script are in place.",
                                priority: .low,
                                dueLabel: nil
                            )
                        ]
                    )
                ]
            ),
            ProjectBoardProject(
                id: "deadline-watcher",
                title: "Deadline Watcher",
                subtitle: "Local reminders and artifact progress",
                columns: [
                    ProjectBoardColumn(id: "backlog", title: "Backlog", tasks: []),
                    ProjectBoardColumn(
                        id: "planned",
                        title: "Planned",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-artifact-rules",
                                title: "Tune stale artifact thresholds",
                                detail: "Avoid noisy reminders for recent work.",
                                priority: .medium,
                                dueLabel: "Friday"
                            )
                        ]
                    ),
                    ProjectBoardColumn(id: "in-progress", title: "In Progress", tasks: []),
                    ProjectBoardColumn(id: "blocked", title: "Blocked", tasks: []),
                    ProjectBoardColumn(
                        id: "done",
                        title: "Done",
                        tasks: [
                            ProjectBoardTask(
                                id: "task-daily-check",
                                title: "Daily check runner",
                                detail: "Records last run and schedules overdue notices.",
                                priority: .low,
                                dueLabel: nil
                            )
                        ]
                    )
                ]
            )
        ]
    )
}

struct ProjectBoardProject: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var columns: [ProjectBoardColumn]

    var taskCount: Int {
        columns.reduce(0) { $0 + $1.tasks.count }
    }
}

struct ProjectBoardColumn: Identifiable, Equatable {
    var id: String
    var title: String
    var tasks: [ProjectBoardTask]
}

struct ProjectBoardTask: Identifiable, Equatable {
    enum Priority: String, Equatable {
        case low
        case medium
        case high

        var label: String {
            rawValue.capitalized
        }

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

    var id: String
    var title: String
    var detail: String
    var priority: Priority
    var dueLabel: String?
}

struct ProjectBoardView: View {
    @Environment(\.openWindow) private var openWindow
    @SceneStorage("soloPM.selectedProjectID") private var selectedProjectID: String?

    let snapshot: ProjectBoardSnapshot

    var body: some View {
        NavigationSplitView {
            List(selection: selectedProjectBinding) {
                ForEach(snapshot.projects) { project in
                    ProjectSidebarRow(project: project)
                        .tag(project.id)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Projects")
        } detail: {
            if let project = selectedProject {
                ProjectBoardDetail(project: project)
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
            }
        }
        .navigationTitle("SoloPM")
        .onAppear {
            if selectedProjectID == nil {
                selectedProjectID = snapshot.projects.first?.id
            }
        }
    }

    private var selectedProject: ProjectBoardProject? {
        snapshot.projects.first { $0.id == selectedProjectID } ?? snapshot.projects.first
    }

    private var selectedProjectBinding: Binding<String?> {
        Binding(
            get: { selectedProjectID ?? snapshot.projects.first?.id },
            set: { selectedProjectID = $0 }
        )
    }
}

private struct ProjectSidebarRow: View {
    let project: ProjectBoardProject

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title)
                    .lineLimit(1)
                Text("\(project.taskCount) tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "folder")
        }
    }
}

private struct ProjectBoardDetail: View {
    let project: ProjectBoardProject

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.title2.weight(.semibold))
                Text(project.subtitle)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(project.columns) { column in
                        BoardColumnView(column: column)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(18)
    }
}

private struct BoardColumnView: View {
    let column: ProjectBoardColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(column.title)
                    .font(.headline)
                Spacer()
                Text("\(column.tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if column.tasks.isEmpty {
                Text("No tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            } else {
                ForEach(column.tasks) { task in
                    BoardTaskCard(task: task)
                }
            }
        }
        .frame(width: 246, alignment: .topLeading)
    }
}

private struct BoardTaskCard: View {
    let task: ProjectBoardTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            Text(task.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                Label(task.priority.label, systemImage: "flag")
                    .foregroundStyle(task.priority.color)

                Spacer()

                if let dueLabel = task.dueLabel {
                    Label(dueLabel, systemImage: "calendar")
                }
            }
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        }
    }
}
