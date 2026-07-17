import Foundation
import SoloPMCore
import SwiftUI

private enum ProjectPortfolioFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case overdue
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            "All"
        case .active:
            "Active"
        case .overdue:
            "Overdue"
        case .completed:
            "Completed"
        }
    }
}
private enum ProjectPortfolioSort: String, CaseIterable, Identifiable {
    case risk
    case progress
    case due

    var id: String { rawValue }

    var title: String {
        switch self {
        case .risk:
            "Risk"
        case .progress:
            "Progress"
        case .due:
            "Next Due"
        }
    }
}

struct ProjectsPortfolioOverview: View {
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onOpenProject: (Int64) -> Void
    @State private var filter: ProjectPortfolioFilter = .all
    @State private var sort: ProjectPortfolioSort = .risk

    private var summaries: [ProjectPortfolioSummary] {
        sorted(filtered(viewModel.derivedReadModels.projectPortfolioSummaries))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    ProjectPortfolioHeader(
                        title: "Projects",
                        subtitle: String(format: String(localized: "%d projects compared"), summaries.count),
                        systemImage: "folder.circle"
                    )
                    Spacer(minLength: 12)
                    controls
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProjectPortfolioHeader(
                        title: "Projects",
                        subtitle: String(format: String(localized: "%d projects compared"), summaries.count),
                        systemImage: "folder.circle"
                    )
                    controls
                }
            }

            if summaries.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Create a project to compare progress, risk, and next due work.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 12)],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(summaries) { summary in
                            ProjectPortfolioCard(summary: summary) {
                                onOpenProject(summary.projectID)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-portfolio-overview")
        .accessibilityLabel("Projects portfolio overview")
        .accessibilityHint("Compares local project progress, risk, due dates, and next actions.")
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Project Filter", selection: $filter) {
                ForEach(ProjectPortfolioFilter.allCases) { filter in
                    Text(LocalizedStringKey(filter.title)).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .accessibilityIdentifier("projects-portfolio-filter")

            Menu {
                Picker("Sort Projects", selection: $sort) {
                    ForEach(ProjectPortfolioSort.allCases) { sort in
                        Text(LocalizedStringKey(sort.title)).tag(sort)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort projects")
            .accessibilityIdentifier("projects-portfolio-sort")
        }
    }

    private func filtered(_ summaries: [ProjectPortfolioSummary]) -> [ProjectPortfolioSummary] {
        summaries.filter { summary in
            switch filter {
            case .all:
                return true
            case .active:
                return summary.health != .completed
            case .overdue:
                return summary.overdueTaskCount > 0
            case .completed:
                return summary.health == .completed
            }
        }
    }

    private func sorted(_ summaries: [ProjectPortfolioSummary]) -> [ProjectPortfolioSummary] {
        switch sort {
        case .risk:
            return summaries
        case .progress:
            return summaries.sorted {
                if $0.progress == $1.progress {
                    return $0.projectID > $1.projectID
                }
                return $0.progress < $1.progress
            }
        case .due:
            return summaries.sorted {
                ($0.nextDueAt ?? "9999-12-31") < ($1.nextDueAt ?? "9999-12-31")
            }
        }
    }
}

private struct ProjectPortfolioHeader: View {
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

private struct ProjectPortfolioCard: View {
    let summary: ProjectPortfolioSummary
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(summary.title)
                    Label(localizedHealthTitle, systemImage: summary.health.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.health.tint)
                }
                Spacer(minLength: 8)
                Text(percentLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            ProgressView(value: summary.progress)
                .tint(summary.health.tint)
                .accessibilityLabel("Project progress")
                .accessibilityValue(percentLabel)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 6) {
                metric("Open", value: summary.openTaskCount, systemImage: "tray")
                metric("Done", value: summary.doneTaskCount, systemImage: "checkmark.circle")
                metric("Blocked", value: summary.blockedTaskCount, systemImage: "exclamationmark.octagon")
                metric("Overdue", value: summary.overdueTaskCount, systemImage: "clock.badge.exclamationmark")
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(summary.nextDueAt ?? String(localized: "No due date"), systemImage: "calendar")
                Label(localizedRiskReason, systemImage: "heart.text.square")
                Label(summary.nextActionTitle, systemImage: "arrow.right.circle")
                Label(localizedHealthRuleDescription, systemImage: "checklist")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpen) {
                Label("Open Project", systemImage: "arrow.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open project detail")
            .accessibilityIdentifier("projects-portfolio-open-\(summary.projectID)")
            .accessibilityHint("Opens the selected project detail without changing task status.")
        }
        .padding(12)
        .frame(minHeight: ProjectBoardLayoutMetrics.portfolioCardMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(summary.health.tint.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projects-portfolio-card-\(summary.projectID)")
        .accessibilityLabel(String(format: String(localized: "Project %@"), summary.title))
        .accessibilityValue("\(localizedHealthTitle), \(percentLabel), \(localizedRiskReason)")
    }

    private var percentLabel: String {
        "\(Int((summary.progress * 100).rounded()))%"
    }

    private var localizedHealthTitle: String {
        String(localized: String.LocalizationValue(summary.health.title))
    }

    private var localizedHealthRuleDescription: String {
        String(localized: String.LocalizationValue(summary.localHealthRuleDescription))
    }

    private var localizedRiskReason: String {
        var reasons: [String] = []
        if summary.blockedTaskCount > 0 {
            reasons.append(String(format: String(localized: "%d blocked"), summary.blockedTaskCount))
        }
        if summary.overdueTaskCount > 0 {
            reasons.append(String(format: String(localized: "%d overdue"), summary.overdueTaskCount))
        }
        if !reasons.isEmpty {
            return reasons.joined(separator: ", ")
        }
        switch summary.health {
        case .completed:
            return String(localized: "All tracked tasks are done.")
        case .attention:
            return String(localized: "Progress is below 25% with open work.")
        case .onTrack:
            return String(localized: "No blocked or overdue open tasks.")
        case .atRisk:
            return String(localized: "Local risk rule detected schedule pressure.")
        }
    }

    private func metric(_ title: String, value: Int, systemImage: String) -> some View {
        Label {
            Text("\(value) \(String(localized: String.LocalizationValue(title)))")
                .monospacedDigit()
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct ProjectBoardDetail: View {
    let project: ProjectBoardProject
    @Binding var displayMode: ProjectBoardDisplayMode
    @ObservedObject var viewModel: ProjectBoardViewModel
    var onOpenProjectInspector: () -> Void = {}
    var onOpenTaskInspector: (Int64) -> Void = { _ in }
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
                        onEditProject: onOpenProjectInspector,
                        onAddTask: { startComposingTask() }
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProjectHeaderSummary(project: project)

                    ProjectHeaderActions(
                        project: project,
                        displayMode: $displayMode,
                        onEditProject: onOpenProjectInspector,
                        onAddTask: { startComposingTask() }
                    )
                }
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
                        onAddTask: { startComposingTask() },
                        onOpenTaskInspector: onOpenTaskInspector
                    )
                case .board:
                    ProjectKanbanBoard(
                        project: project,
                        composingStatus: $composingStatus,
                        viewModel: viewModel,
                        onOpenTaskInspector: onOpenTaskInspector
                    )
                case .list:
                    ProjectTaskList(
                        project: project,
                        viewModel: viewModel,
                        onOpenTaskInspector: onOpenTaskInspector
                    )
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
    let onOpenTaskInspector: (Int64) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ProjectProgressOverview(project: project)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ProjectTaskSnapshotSection(
                        project: project,
                        onAddTask: onAddTask,
                        onOpenTaskInspector: onOpenTaskInspector
                    )
                    ProjectMilestoneSection(project: project, viewModel: viewModel)
                    ProjectArtifactSection(project: project, viewModel: viewModel)
                    ProjectTimelineSection(project: project)
                    ProjectAssistantPanel(project: project, viewModel: viewModel)
                    ProjectLocalSuggestionPanel(
                        project: project,
                        viewModel: viewModel,
                        onOpenTaskInspector: onOpenTaskInspector
                    )
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
        ProjectMetricBadge(label: "Milestones", value: project.milestones.count, tint: .teal)
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
            Text(LocalizedStringKey(label))
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
    let onAddTask: () -> Void
    let onOpenTaskInspector: (Int64) -> Void

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
                        onOpenTaskInspector(task.id)
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
                                Text(task.dueLabel ?? localizedDisplay(task.status.title))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Label {
                                Text(LocalizedStringKey(task.priority.label))
                            } icon: {
                                Image(systemName: "flag")
                            }
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

private struct ProjectMilestoneSection: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var milestoneTitle = ""
    @State private var milestoneDueAt = ""

    var body: some View {
        ProjectOverviewPanel(title: "Milestones", systemImage: "flag.checkered") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    milestoneTitleField
                    milestoneDueField
                    addButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    milestoneTitleField
                    milestoneDueField
                    addButton
                }
            }

            if project.milestones.isEmpty {
                Text("No milestones yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(project.milestones.prefix(4)) { milestone in
                    HStack(spacing: 8) {
                        Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "flag")
                            .foregroundStyle(milestone.isCompleted ? .green : .teal)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(milestone.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(milestone.dueAt ?? String(localized: "No due date"))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button {
                            _ = viewModel.completeProjectMilestone(id: milestone.id, projectID: project.id)
                        } label: {
                            Label("Complete milestone", systemImage: "checkmark.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(project.isArchived || milestone.isCompleted)
                        .help("Complete milestone")
                        .accessibilityIdentifier("project-milestone-complete-\(milestone.id)")
                        .accessibilityLabel("Complete milestone \(milestone.title)")
                        .accessibilityHint("Marks this local project milestone as complete.")
                    }
                }
            }
        }
    }

    private func addMilestone() {
        guard viewModel.createProjectMilestone(
            title: milestoneTitle,
            dueAt: milestoneDueAt,
            projectID: project.id
        ) != nil else {
            return
        }
        milestoneTitle = ""
        milestoneDueAt = ""
    }

    private var milestoneTitleField: some View {
        TextField("Milestone title", text: $milestoneTitle)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(addMilestone)
            .accessibilityIdentifier("project-milestone-title")
            .accessibilityLabel("Milestone title")
            .accessibilityHint("Enter a local milestone title for this project.")
    }

    private var milestoneDueField: some View {
        TextField("Due date", text: $milestoneDueAt)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(addMilestone)
            .accessibilityIdentifier("project-milestone-due")
            .accessibilityLabel("Milestone due date")
            .accessibilityHint("Optional local milestone due date.")
    }

    private var addButton: some View {
        Button(action: addMilestone) {
            Label("Add Milestone", systemImage: "plus")
        }
        .controlSize(.small)
        .disabled(project.isArchived || milestoneTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("project-milestone-add")
        .accessibilityHint("Adds a local milestone without creating a task.")
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
                            Text(LocalizedStringKey(artifact.createdState.label))
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

    private var timelineItems: [ProjectTimelineItem] {
        let taskItems = project.tasks
            .compactMap { task -> ProjectTimelineItem? in
                guard let dueAt = task.dueAt else {
                    return nil
                }
                return .task(task, dueAt: dueAt)
            }
        let milestoneItems = project.milestones
            .compactMap { milestone -> ProjectTimelineItem? in
                guard let dueAt = milestone.dueAt else {
                    return nil
                }
                return .milestone(milestone, dueAt: dueAt)
            }
        return (taskItems + milestoneItems).sorted { lhs, rhs in
            if lhs.dueAt == rhs.dueAt {
                return lhs.id < rhs.id
            }
            return lhs.dueAt < rhs.dueAt
        }
    }

    var body: some View {
        ProjectOverviewPanel(title: "Timeline", systemImage: "calendar") {
            if timelineItems.isEmpty {
                Text("No due dates yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(timelineItems.prefix(5)) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(item.tint)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(item.dueAt)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(item.title)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Project timeline item \(item.title)")
                    .accessibilityValue(item.dueAt)
                }
            }
        }
    }
}

private enum ProjectTimelineItem: Identifiable {
    case task(ProjectBoardTask, dueAt: String)
    case milestone(ProjectBoardMilestone, dueAt: String)

    var id: String {
        switch self {
        case .task(let task, _):
            "task-\(task.id)"
        case .milestone(let milestone, _):
            "milestone-\(milestone.id)"
        }
    }

    var title: String {
        switch self {
        case .task(let task, _):
            task.title
        case .milestone(let milestone, _):
            milestone.title
        }
    }

    var dueAt: String {
        switch self {
        case .task(_, let dueAt), .milestone(_, let dueAt):
            dueAt
        }
    }

    var tint: Color {
        switch self {
        case .task(let task, _):
            task.status.tint
        case .milestone(let milestone, _):
            milestone.isCompleted ? .green : .teal
        }
    }
}

private struct ProjectAssistantPanel: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var question = ""

    var body: some View {
        ProjectOverviewPanel(title: "Assistant", systemImage: "bubble.left.and.text.bubble.right") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    questionField
                    askButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    questionField
                    askButton
                }
            }

            if let answer = viewModel.projectAssistantAnswer, answer.projectID == project.id {
                Text(answer.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project-assistant-answer")

                HStack(spacing: 8) {
                    Label(answer.suggestedActionTitle, systemImage: "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button {
                        _ = viewModel.prepareProjectAssistantSuggestedActionForReview(projectID: project.id)
                    } label: {
                        Label("Review Action", systemImage: "doc.text.magnifyingglass")
                    }
                    .controlSize(.small)
                    .help("Prepare suggested action for review")
                    .accessibilityIdentifier("project-assistant-review-action")
                    .accessibilityHint("Prepares the local assistant suggestion for review without writing task status.")
                }
            } else {
                Text("Ask for a local next step without contacting an external LLM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let draft = viewModel.projectAssistantReviewDraft, draft.projectID == project.id {
                Label(draft.suggestedActionTitle, systemImage: "doc.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("project-assistant-review-draft")
            }
        }
    }

    private func ask() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        _ = viewModel.answerProjectAssistantQuestion(trimmed, projectID: project.id)
    }

    private var questionField: some View {
        TextField("Ask about this project", text: $question)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .onSubmit(ask)
            .accessibilityIdentifier("project-assistant-question")
            .accessibilityLabel("Project assistant question")
            .accessibilityHint("Asks the local project assistant for a next step without external LLM execution.")
    }

    private var askButton: some View {
        Button(action: ask) {
            Label("Ask", systemImage: "paperplane")
        }
        .controlSize(.small)
        .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityIdentifier("project-assistant-ask")
        .accessibilityHint("Generates a local assistant answer for this project.")
    }
}

private struct ProjectLocalSuggestionPanel: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onOpenTaskInspector: (Int64) -> Void

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
                        onOpenTaskInspector(suggestedTask.id)
                    } label: {
                        Label("Open Task", systemImage: "sidebar.right")
                    }
                    .controlSize(.small)
                    .help("Open the suggested task")
                    .accessibilityIdentifier("project-local-suggestion-open-task")
                    .accessibilityHint("Opens the suggested task in the inspector.")

                    if suggestedTask.status == .blocked {
                        Button {
                            _ = viewModel.answerProjectAssistantQuestion("Review blocked task", projectID: project.id)
                            _ = viewModel.prepareProjectAssistantSuggestedActionForReview(projectID: project.id)
                        } label: {
                            Label("Review Action", systemImage: "doc.text.magnifyingglass")
                        }
                        .controlSize(.small)
                        .help("Prepare suggested action for review")
                        .accessibilityIdentifier("project-local-suggestion-review-action")
                        .accessibilityHint("Prepares the suggested blocked task action for review without writing task status.")
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
            return localizedDisplay("%@ is blocked. Resolve it before adding more work.", task.title)
        }
        if task.priority == .high {
            return localizedDisplay("%@ is high priority. Make it the next focused task.", task.title)
        }
        if let dueAt = task.dueAt {
            return localizedDisplay("%@ is the next due task at %@.", task.title, dueAt)
        }
        return localizedDisplay("Continue with %@.", task.title)
    }
}

private struct ProjectOverviewPanel<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.headline)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: ProjectBoardLayoutMetrics.overviewPanelMinHeight, alignment: .topLeading)
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
    let onEditProject: () -> Void
    let onAddTask: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                viewPicker
                editProjectButton
                addTaskButton
            }

            VStack(alignment: .leading, spacing: 8) {
                viewPicker
                HStack(spacing: 8) {
                    editProjectButton
                    addTaskButton
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Project view actions")
        .accessibilitySortPriority(1)
    }

    private var viewPicker: some View {
        Picker("View", selection: $displayMode) {
            ForEach(ProjectBoardDisplayMode.allCases) { mode in
                Label {
                    Text(LocalizedStringKey(mode.label))
                } icon: {
                    Image(systemName: mode.systemImage)
                }
                .tag(mode)
                .accessibilityIdentifier("project-display-mode-\(mode.rawValue)")
                .accessibilityLabel(LocalizedStringKey(mode.label))
            }
        }
        .pickerStyle(.segmented)
        .frame(width: ProjectBoardLayoutMetrics.displayModePickerWidth)
    }

    private var addTaskButton: some View {
        Button(action: onAddTask) {
            Label("Add Task", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("n", modifiers: [.command])
        .disabled(project.isArchived)
        .help("Add task to \(project.title)")
        .accessibilityIdentifier("project-header-add-task")
        .accessibilityLabel("Add task to \(project.title)")
        .accessibilityHint("Opens the inline composer for a new local task.")
    }

    private var editProjectButton: some View {
        Button(action: onEditProject) {
            Label("Edit Project", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .help("Open project details")
        .accessibilityIdentifier("project-header-open-inspector")
        .accessibilityHint("Opens this project's editable details in the inspector.")
    }
}

private struct ProjectKanbanBoard: View {
    let project: ProjectBoardProject
    @Binding var composingStatus: ProjectTaskStatus?
    @ObservedObject var viewModel: ProjectBoardViewModel
    var onOpenTaskInspector: (Int64) -> Void = { _ in }
    @FocusState private var isBoardFocused: Bool

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
                        onOpenTaskDetails: onOpenTaskInspector,
                        onMoveTask: { taskID, status in
                            viewModel.moveTask(id: taskID, to: status)
                        },
                        onMoveDroppedTasks: { rawIDs, status in
                            viewModel.moveDroppedTasks(ids: rawIDs, to: status)
                        }
                    )
                }
            }
            .padding(.bottom, 4)
        }
        .defaultScrollAnchor(.topLeading)
        .scrollIndicators(.visible)
        // Keyboard-first task manipulation. The handler is scoped to the board
        // container so text editors outside it (task/project inspector) keep
        // their own focus and never route plain characters here. The inline
        // composer is the only editor inside this container, so its visibility
        // (composingStatus != nil) gates every shortcut.
        .focusable()
        .focusEffectDisabled()
        .focused($isBoardFocused)
        .onKeyPress(phases: .down) { keyPress in
            handleBoardKeyPress(keyPress)
        }
        .onChange(of: viewModel.selectedTaskID) { _, selectedTaskID in
            // Clicking a card should let J/K/E/D/1-3 work immediately, but the
            // board never steals focus while the inline composer is editing.
            if selectedTaskID != nil && composingStatus == nil {
                isBoardFocused = true
            }
        }
        .help("Keyboard: J/K or arrows select tasks, E opens details, D completes, 1/2/3 set priority, ⌘Z undoes")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-kanban-board")
        .accessibilityLabel("Kanban board for \(project.title)")
        .accessibilityHint("Open a task card, use status controls, or move tasks between columns.")
        .accessibilitySortPriority(2)
    }

    private var orderedTaskIDs: [Int64] {
        ProjectBoardKeyboardNavigation.orderedTaskIDs(in: project)
    }

    private func handleBoardKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // While the inline composer is open its text fields own every plain
        // character; ignoring here keeps typed letters out of board shortcuts.
        guard composingStatus == nil else {
            return .ignored
        }
        // ⌘Z board undo shares the container-focus guard with the letter
        // shortcuts: the board only receives keys while the window is key and
        // no text editor owns focus. When a text field is focused the standard
        // Edit > Undo item consumes ⌘Z before it ever reaches this handler.
        if keyPress.modifiers == [.command], keyPress.characters == "z" {
            return undoLastBoardOperation()
        }
        guard keyPress.modifiers.isEmpty else {
            return .ignored
        }

        switch keyPress.key {
        case .downArrow:
            return selectAdjacentTask(forward: true)
        case .upArrow:
            return selectAdjacentTask(forward: false)
        default:
            break
        }

        switch keyPress.characters {
        case "j":
            return selectAdjacentTask(forward: true)
        case "k":
            return selectAdjacentTask(forward: false)
        case "e":
            return openInspectorForSelectedTask()
        case "d":
            return completeSelectedTask()
        case "1":
            return setSelectedTaskPriority(.low)
        case "2":
            return setSelectedTaskPriority(.medium)
        case "3":
            return setSelectedTaskPriority(.high)
        default:
            return .ignored
        }
    }

    private func selectAdjacentTask(forward: Bool) -> KeyPress.Result {
        let targetTaskID = forward
            ? ProjectBoardKeyboardNavigation.nextTaskID(after: viewModel.selectedTaskID, in: orderedTaskIDs)
            : ProjectBoardKeyboardNavigation.previousTaskID(before: viewModel.selectedTaskID, in: orderedTaskIDs)
        guard let targetTaskID else {
            return .ignored
        }
        viewModel.selectedTaskID = targetTaskID
        return .handled
    }

    private func openInspectorForSelectedTask() -> KeyPress.Result {
        guard let selectedBoardTask else {
            return .ignored
        }
        onOpenTaskInspector(selectedBoardTask.id)
        return .handled
    }

    private func undoLastBoardOperation() -> KeyPress.Result {
        guard viewModel.canUndoBoardOperation else {
            return .ignored
        }
        viewModel.undoLastBoardOperation()
        return .handled
    }

    private func completeSelectedTask() -> KeyPress.Result {
        guard let task = selectedBoardTask else {
            return .ignored
        }
        guard task.status != .done else {
            return .handled
        }
        // Same recurrence-aware completion route as the card status controls.
        viewModel.moveTask(id: task.id, to: .done)
        return .handled
    }

    private func setSelectedTaskPriority(_ priority: ProjectTaskPriority) -> KeyPress.Result {
        guard let task = selectedBoardTask else {
            return .ignored
        }
        guard task.priority != priority else {
            return .handled
        }
        viewModel.updateSelectedTask(
            title: task.title,
            detail: task.detail,
            status: task.status,
            priority: priority,
            dueAt: task.dueAt,
            recurrence: task.recurrence
        )
        return .handled
    }

    private var selectedBoardTask: ProjectBoardTask? {
        guard let selectedTaskID = viewModel.selectedTaskID else {
            return nil
        }
        return project.tasks.first { $0.id == selectedTaskID }
    }
}

private struct BoardColumnView: View {
    let column: ProjectBoardColumn
    let isComposing: Bool
    let selectedTaskID: Int64?
    let onStartComposing: () -> Void
    let onCancelComposing: () -> Void
    let onCreateTask: (String, String, ProjectTaskPriority, String?) -> Void
    let onOpenTaskDetails: (Int64) -> Void
    let onMoveTask: (Int64, ProjectTaskStatus) -> Void
    let onMoveDroppedTasks: ([String], ProjectTaskStatus) -> Bool

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label {
                    Text(LocalizedStringKey(column.title))
                } icon: {
                    Image(systemName: column.status.systemImage)
                }
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
                    .frame(maxWidth: .infinity, minHeight: ProjectBoardLayoutMetrics.emptyColumnMinHeight, alignment: .topLeading)
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
                    taskRow(task)
                }
            }
        }
        .frame(width: ProjectBoardLayoutMetrics.boardColumnWidth, alignment: .topLeading)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? column.status.tint.opacity(0.72) : Color.secondary.opacity(0.14), lineWidth: isDropTargeted ? 1.5 : 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { rawIDs, _ in
            onMoveDroppedTasks(rawIDs, column.status)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
    }

    private func taskRow(_ task: ProjectBoardTask) -> some View {
        BoardTaskCard(
            task: task,
            isSelected: selectedTaskID == task.id,
            onOpenDetails: { onOpenTaskDetails(task.id) },
            onMoveStatus: { status in onMoveTask(task.id, status) }
        )
        .draggable(String(task.id)) {
            BoardTaskDragPreview(task: task)
        }
        .dropDestination(for: String.self) { rawIDs, _ in
            onMoveDroppedTasks(rawIDs, column.status)
        }
        .contextMenu {
            taskContextMenu(for: task)
        }
    }

    @ViewBuilder
    private func taskContextMenu(for task: ProjectBoardTask) -> some View {
        Button {
            onOpenTaskDetails(task.id)
        } label: {
            Label("Open Details", systemImage: "sidebar.right")
        }

        Menu {
            ForEach(ProjectTaskStatus.allCases.filter { $0 != task.status }) { status in
                Button {
                    onMoveTask(task.id, status)
                } label: {
                    Label {
                        Text(LocalizedStringKey(status.title))
                    } icon: {
                        Image(systemName: status.systemImage)
                    }
                }
            }
        } label: {
            Label("Move To", systemImage: "arrow.right.arrow.left")
        }
    }
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
                        Text(LocalizedStringKey(priority.label)).tag(priority)
                    }
                }
                .labelsHidden()
                .frame(width: ProjectBoardLayoutMetrics.inlinePriorityPickerWidth)
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
    let onOpenDetails: () -> Void
    let onMoveStatus: (ProjectTaskStatus) -> Void
    @State private var isPointerHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onOpenDetails) {
                TaskCardSelectableSummary(task: task, isSelected: isSelected, isPointerHovered: isPointerHovered)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open task \(task.title)")
            .accessibilityValue(accessibilityValueText)
            .accessibilityHint("Opens task details in the inspector. Task inspector fields can then be edited without dragging.")
            .accessibilityIdentifier("task-card-open-details-\(task.id)")
            .accessibilitySortPriority(2)

            TaskStatusMoveControls(task: task, onMove: onMoveStatus)
                .accessibilityIdentifier("task-status-move-controls")
                .accessibilitySortPriority(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 8)
                    .fill(task.status.tint.opacity(0.05))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isPointerHovered ? task.status.tint.opacity(0.7) : Color.secondary.opacity(0.16))
            }
        }
        // Keep every selection decoration behind the card content. Some hosted
        // SwiftUI renderers clear label sublayers beneath a transparent overlay;
        // the background stroke preserves the same non-color selection cue.
        .shadow(color: Color.black.opacity(isPointerHovered ? 0.10 : 0.04), radius: isPointerHovered ? 12 : 8, x: 0, y: isPointerHovered ? 4 : 2)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isPointerHovered = $0 }
        .animation(.snappy(duration: 0.16), value: isPointerHovered)
        .accessibilityElement(children: .contain)
    }

    private var accessibilityValueText: String {
        isSelected
            ? "\(localizedDisplay("Selected")), \(accessibilityMetadataValue)"
            : accessibilityMetadataValue
    }

    private var accessibilityMetadataValue: String {
        ([localizedStatusValue, localizedPriorityValue, localizedDueValue] + (recurrenceValue.map { [$0] } ?? []))
            .joined(separator: ", ")
    }

    private var localizedStatusValue: String {
        localizedDisplay(task.status.title)
    }

    private var localizedPriorityValue: String {
        localizedDisplay(task.priority.label)
    }

    private var localizedDueValue: String {
        task.dueLabel.map(localizedDisplay) ?? localizedDisplay("No due date")
    }

    private var recurrenceValue: String? {
        switch task.recurrence {
        case "daily": localizedDisplay("Daily")
        case "weekly": localizedDisplay("Weekly")
        case "monthly": localizedDisplay("Monthly")
        default: nil
        }
    }
}

private struct TaskCardSelectableSummary: View {
    let task: ProjectBoardTask
    let isSelected: Bool
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

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(Color(nsColor: .labelColor))
                            .help("Selected")
                            .accessibilityHidden(true)
                    }

                    Spacer(minLength: 6)

                    TaskDragAffordance(tint: task.status.tint, isPointerHovered: isPointerHovered)
                }

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .labelColor))
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
            .frame(width: ProjectBoardLayoutMetrics.taskStatusRailWidth)
            .frame(height: ProjectBoardLayoutMetrics.taskStatusRailHeight)
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
                Label {
                    Text(LocalizedStringKey(task.status.title))
                } icon: {
                    Image(systemName: "arrow.right.arrow.left")
                }
                    .foregroundStyle(task.status.tint)
                Label {
                    Text(LocalizedStringKey(task.priority.label))
                } icon: {
                    Image(systemName: "flag")
                }
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

            Text(LocalizedStringKey(task.status.title))
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color(nsColor: .labelColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 76)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
                .help(LocalizedStringKey(task.status.title))
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
        .accessibilityIdentifier(targetStatus.map { "task-status-move-\($0.rawValue)-\(task.id)" } ?? "task-status-move-disabled-\(task.id)")
        .accessibilityLabel(targetStatus.map { "\(title) to \($0.title)" } ?? title)
        .accessibilityHint("Changes \(task.title) status.")
    }
}

private struct TaskCardMetadataStrip: View {
    let task: ProjectBoardTask

    var body: some View {
        // This two-row structure is retained because it is the card metadata
        // layout proven to render on the hosted visual runner. Each
        // semantic row owns one Text node, avoiding icon-only chip failures.
        VStack(alignment: .leading, spacing: 6) {
            TaskMetadataLine(value: identityLineValue, tint: task.status.tint)

            if let scheduleLineValue {
                TaskMetadataLine(value: scheduleLineValue, tint: .blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task metadata")
        .accessibilityValue(accessibilityMetadataValue)
        .accessibilityIdentifier("task-card-metadata-strip-\(task.id)")
    }

    private var identityLineValue: String {
        "\(localizedStatusValue) · \(localizedPriorityValue)"
    }

    private var scheduleLineValue: String? {
        var components: [String] = []
        if let dueLabel = task.dueLabel {
            components.append(localizedDisplay(dueLabel))
        }
        if let recurrenceValue {
            components.append(recurrenceValue)
        }
        return components.isEmpty ? nil : components.joined(separator: " · ")
    }

    private var accessibilityMetadataValue: String {
        ([localizedStatusValue, localizedPriorityValue, localizedDueValue] + (recurrenceValue.map { [$0] } ?? []))
            .joined(separator: ", ")
    }

    private var localizedStatusValue: String {
        localizedDisplay(task.status.title)
    }

    private var localizedPriorityValue: String {
        localizedDisplay(task.priority.label)
    }

    private var localizedDueValue: String {
        task.dueLabel.map(localizedDisplay) ?? localizedDisplay("No due date")
    }

    private var recurrenceValue: String? {
        switch task.recurrence {
        case "daily":
            localizedDisplay("Daily")
        case "weekly":
            localizedDisplay("Weekly")
        case "monthly":
            localizedDisplay("Monthly")
        default:
            nil
        }
    }
}

private struct TaskMetadataLine: View {
    let value: String
    let tint: Color

    var body: some View {
        Text(verbatim: value)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.82)
            .layoutPriority(1)
            .foregroundColor(Color(nsColor: .labelColor))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(
                minWidth: ProjectBoardLayoutMetrics.taskMetadataChipMinWidth,
                maxWidth: .infinity,
                minHeight: ProjectBoardLayoutMetrics.taskMetadataChipMinHeight,
                alignment: .leading
            )
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help(value)
    }
}

private struct ProjectTaskList: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onOpenTaskInspector: (Int64) -> Void

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
                Label {
                    Text(LocalizedStringKey(task.status.title))
                } icon: {
                    Image(systemName: task.status.systemImage)
                }
            }

            TableColumn("Priority") { task in
                Label {
                    Text(LocalizedStringKey(task.priority.label))
                } icon: {
                    Image(systemName: "flag")
                }
                    .foregroundStyle(task.priority.color)
            }

            TableColumn("Due") { task in
                Text(task.dueLabel ?? "")
                    .foregroundStyle(.secondary)
            }

            TableColumn("Details") { task in
                Button {
                    onOpenTaskInspector(task.id)
                } label: {
                    Label("Open Details", systemImage: "sidebar.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Open task details")
                .accessibilityIdentifier("task-list-open-details-\(task.id)")
                .accessibilityLabel("Open details for \(task.title)")
                .accessibilityHint("Opens the selected task in the inspector.")
            }
            .width(54)
        }
        .accessibilityIdentifier("project-task-list")
        .accessibilityLabel("Project task list")
        .accessibilityHint("Lists the selected project's current tasks before creating, editing, executing, or deleting task content.")
    }
}
