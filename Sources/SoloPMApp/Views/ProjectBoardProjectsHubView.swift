import SoloPMCore
import SwiftUI

struct ProjectBoardProjectsHubView<Content: View>: View {
    @Binding var route: BoardRoute
    let projects: [ProjectBoardProject]
    let smartLists: [SmartList]
    let showsArchivedProjects: Bool
    let onCreateProject: () -> Void
    let onCreateSmartList: () -> Void
    let onDeleteSmartList: (SmartList) -> Void
    let onToggleArchivedProjects: () -> Void
    let onMoveDroppedTasks: ([String], Int64) -> Bool
    @ViewBuilder let content: () -> Content

    private var activeProjects: [ProjectBoardProject] {
        projects.filter { !$0.isCompleted && !$0.isArchived }
    }

    private var completedProjects: [ProjectBoardProject] {
        projects.filter { $0.isCompleted && !$0.isArchived }
    }

    private var archivedProjects: [ProjectBoardProject] {
        projects.filter(\.isArchived)
    }

    var body: some View {
        GeometryReader { proxy in
            switch ProjectBoardHubPresentationPolicy.presentation(
                for: Double(proxy.size.width)
            ) {
            case .wide:
                HSplitView {
                    projectsNavigation
                        .frame(minWidth: 190, idealWidth: 220, maxWidth: 300)
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .compact:
                VStack(spacing: 0) {
                    compactNavigation
                    Divider()
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-hub")
    }

    private var projectsNavigation: some View {
        VStack(spacing: 0) {
            List(selection: projectSelection) {
                Section {
                    Label("Portfolio", systemImage: "rectangle.grid.2x2")
                        .tag(BoardRoute.primary(.projects))
                        .accessibilityIdentifier("projects-hub-portfolio")
                }

                Section("Smart Lists") {
                    ForEach(smartLists) { smartList in
                        Label {
                            smartListTitle(smartList)
                                .lineLimit(1)
                                .help(
                                    smartList.isPreset
                                        ? localizedDisplay(smartList.name)
                                        : smartList.name
                                )
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                        }
                        .tag(BoardRoute.smartList(smartList.id))
                        .contextMenu {
                            if !smartList.isPreset {
                                Button(role: .destructive) {
                                    onDeleteSmartList(smartList)
                                } label: {
                                    Label("Delete Smart List", systemImage: "trash")
                                }
                            }
                        }
                        .accessibilityIdentifier("project-board-smart-list-row-\(smartList.id)")
                    }

                    Button(action: onCreateSmartList) {
                        Label("New Smart List…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("project-board-smart-list-new")
                }
                .accessibilityIdentifier("projects-hub-smart-lists")

                Section("Active") {
                    projectRows(activeProjects)
                }
                .accessibilityIdentifier("projects-hub-active")

                if !completedProjects.isEmpty {
                    Section("Completed") {
                        projectRows(completedProjects)
                    }
                    .accessibilityIdentifier("projects-hub-completed")
                }

                if showsArchivedProjects {
                    Section("Archived") {
                        projectRows(archivedProjects)
                    }
                    .accessibilityIdentifier("projects-hub-archived")
                }
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("projects-hub-navigation")
            .accessibilityLabel("Projects navigation")

            Divider()

            Button(action: onToggleArchivedProjects) {
                Label(
                    "Show Archived",
                    systemImage: showsArchivedProjects ? "checkmark.square" : "square"
                )
            }
            .buttonStyle(.borderless)
            .help("Show archived projects")
            .accessibilityIdentifier("project-board-show-archived")
            .accessibilityLabel("Show archived projects")
            .accessibilityValue(showsArchivedProjects ? "On" : "Off")
            .accessibilityHint("Shows archived projects in the sidebar without deleting local data.")
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Button(action: onCreateProject) {
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
    }

    private var compactNavigation: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Portfolio") { route = .primary(.projects) }
                if !smartLists.isEmpty {
                    Divider()
                    ForEach(smartLists) { smartList in
                        Button(smartList.isPreset ? localizedDisplay(smartList.name) : smartList.name) {
                            route = .smartList(smartList.id)
                        }
                    }
                }
                if !activeProjects.isEmpty {
                    Divider()
                    ForEach(activeProjects) { project in
                        Button(project.title) { route = .project(project.id) }
                    }
                }
            } label: {
                Label("Choose Project View", systemImage: "sidebar.left")
            }
            .accessibilityIdentifier("projects-hub-compact-navigation")

            Spacer()
            Button(action: onCreateProject) {
                Label("Add Project", systemImage: "folder.badge.plus")
            }
            .accessibilityIdentifier("projects-hub-compact-add-project")
        }
        .padding(10)
    }

    private var projectSelection: Binding<BoardRoute?> {
        Binding(
            get: {
                switch route {
                case .primary(.projects), .project, .smartList:
                    return route
                case .primary, .review:
                    return nil
                }
            },
            set: { selectedRoute in
                guard let selectedRoute else {
                    return
                }
                route = selectedRoute
            }
        )
    }

    @ViewBuilder
    private func smartListTitle(_ smartList: SmartList) -> some View {
        if smartList.isPreset {
            Text(LocalizedStringKey(smartList.name))
        } else {
            // User-authored names are display data, not localization keys.
            Text(verbatim: smartList.name)
        }
    }

    @ViewBuilder
    private func projectRows(_ projects: [ProjectBoardProject]) -> some View {
        ForEach(projects) { project in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title)
                        .lineLimit(1)
                        .help(project.title)
                    Text(project.isArchived ? "Archived" : localizedTaskCount(project.taskCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(
                    systemName: project.isArchived
                        ? "archivebox"
                        : project.isCompleted ? "checkmark.circle" : "folder"
                )
            }
            .tag(BoardRoute.project(project.id))
            .accessibilityIdentifier("project-sidebar-row-\(project.id)")
            .accessibilityLabel(project.accessibilityProjectsHubLabel)
            .dropDestination(for: String.self) { rawIDs, _ in
                onMoveDroppedTasks(rawIDs, project.id)
            }
        }
    }
}

private extension ProjectBoardProject {
    var accessibilityProjectsHubLabel: String {
        let state = localizedDisplay(isArchived ? "Archived" : isCompleted ? "Completed" : "Active")
        return "\(title), \(state), \(localizedTaskCount(taskCount))"
    }
}
