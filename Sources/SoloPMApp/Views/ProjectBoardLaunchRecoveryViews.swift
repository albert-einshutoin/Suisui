import SoloPMCore
import SwiftUI

struct ProjectBoardLaunchRecoveryView: View {
    @StateObject private var viewModel: ProjectBoardViewModel
    private let appSettings: () -> AppSettings
    @State private var isInspectorPresented = false

    init(
        viewModel: ProjectBoardViewModel,
        appSettings: @escaping () -> AppSettings = { .default }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.appSettings = appSettings
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            workflowBody
            recoveryInspector
        }
            .frame(minWidth: 960, idealWidth: 1_180, minHeight: 620, idealHeight: 760)
            .task {
                loadRuntimeState()
            }
            .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
                loadRuntimeState()
            }
    }

    @ViewBuilder
    private var workflowBody: some View {
        switch resolvedSelectedDestination {
        case .inbox:
            InboxWorkflowView(viewModel: viewModel, selectInboxTask: selectWorkflowTask)
        case .schedule:
            ScheduleWorkflowView(viewModel: viewModel)
        case .today:
            TodayWorkflowView(
                viewModel: viewModel,
                selectTodayTask: selectWorkflowTask,
                openInspectorForTodayRailTask: openInspectorForWorkflowTask
            )
        case .done:
            DoneWorkflowView(viewModel: viewModel, appSettings: appSettings())
        case .assistantQueue:
            AssistantQueueWorkflowView(viewModel: viewModel)
        case .project(let projectID):
            ProjectDevelopmentAutomationRecoveryView(
                projectID: projectID,
                viewModel: viewModel
            )
        }
    }

    @ViewBuilder
    private var recoveryInspector: some View {
        if isInspectorPresented, let task = viewModel.selectedTask {
            ProjectBoardLaunchRecoveryTaskInspector(
                task: task,
                viewModel: viewModel,
                onClose: { isInspectorPresented = false }
            )
            .frame(minWidth: 300, idealWidth: 320, maxWidth: 360, maxHeight: .infinity)
            .padding(.vertical, 18)
            .padding(.trailing, 18)
        }
    }

    private var selectedDestination: ProjectBoardLaunchRecoveryDestination {
        let rawValue = ProcessInfo.processInfo.environment["SOLOPM_PROJECT_BOARD_SELECTED_DESTINATION"]
        return ProjectBoardLaunchRecoveryDestination(rawValue: rawValue ?? "") ?? .today
    }

    private var resolvedSelectedDestination: ProjectBoardLaunchRecoveryDestination {
        selectedDestination.resolved(availableProjects: viewModel.snapshot.projects)
    }

    private func loadRuntimeState() {
        viewModel.load()
        applySelectedTaskOverrideIfNeeded()
        _ = viewModel.scheduleMissedTaskDailyFollowUp(settings: appSettings())
    }

    private func selectWorkflowTask(_ task: ProjectBoardTask) {
        viewModel.selectedTaskID = task.id
        isInspectorPresented = false
    }

    private func openInspectorForWorkflowTask(_ taskID: Int64) {
        viewModel.selectedTaskID = taskID
        guard viewModel.selectedTask != nil else {
            return
        }

        isInspectorPresented = true
    }

    private func applySelectedTaskOverrideIfNeeded() {
        guard let taskID = ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID,
              viewModel.snapshot.projects.flatMap(\.tasks).contains(where: { $0.id == taskID }) else {
            return
        }
        // Recovery launches must not mutate persisted Project Board selection;
        // the env override only restores deterministic rail context for smoke evidence.
        viewModel.selectedTaskID = taskID
    }
}

private struct ProjectBoardLaunchRecoveryTaskInspector: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onClose: () -> Void

    @State private var title: String
    @State private var detail: String
    @State private var status: ProjectTaskStatus
    @State private var priority: ProjectTaskPriority
    @State private var dueAt: String

    init(task: ProjectBoardTask, viewModel: ProjectBoardViewModel, onClose: @escaping () -> Void) {
        self.task = task
        self.viewModel = viewModel
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _detail = State(initialValue: task.detail)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        _dueAt = State(initialValue: task.dueAt ?? "")
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Label("Task Details", systemImage: "checklist")
                        .font(.headline)
                    Spacer(minLength: 12)
                    Button {
                        onClose()
                    } label: {
                        Label("Close Task Details", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("Close Task Details")
                    .accessibilityIdentifier("task-inspector-close")
                    .accessibilityHint("Close Task Details")
                }
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
                        Text(LocalizedStringKey(status.title))
                            .tag(status)
                    }
                }
                .accessibilityIdentifier("task-inspector-status")

                Picker("Priority", selection: $priority) {
                    ForEach(ProjectTaskPriority.allCases) { priority in
                        Text(LocalizedStringKey(priority.label))
                            .tag(priority)
                    }
                }
                .accessibilityIdentifier("task-inspector-priority")

                TextField("Due", text: $dueAt)
                    .accessibilityIdentifier("task-inspector-due")
            }

            Section("Save") {
                Button {
                    let trimmedDueAt = dueAt.trimmingCharacters(in: .whitespacesAndNewlines)
                    viewModel.updateSelectedTask(
                        title: title,
                        detail: detail,
                        status: status,
                        priority: priority,
                        dueAt: trimmedDueAt.isEmpty ? nil : trimmedDueAt
                    )
                } label: {
                    Label("Save Changes", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Saves edits to the selected task in the local SoloPM database")
                .accessibilityIdentifier("task-inspector-save")
                .accessibilityHint("Saves edits to the selected task in the local SoloPM database.")
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-inspector")
        .accessibilityLabel("Task inspector for \(task.title)")
        .accessibilityHint("Edit and save the selected task.")
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

private enum ProjectBoardLaunchRecoveryDestination: Equatable {
    case inbox
    case schedule
    case today
    case done
    case assistantQueue
    case project(Int64)

    init?(rawValue: String) {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawValue.hasPrefix("project:") {
            let rawProjectID = rawValue.dropFirst("project:".count)
            guard let projectID = Int64(rawProjectID), projectID > 0 else {
                return nil
            }
            self = .project(projectID)
            return
        }

        switch rawValue {
        case "inbox":
            self = .inbox
        case "schedule":
            self = .schedule
        case "today", "":
            self = .today
        case "done":
            self = .done
        case "assistant-queue":
            self = .assistantQueue
        default:
            return nil
        }
    }

    func resolved(availableProjects: [ProjectBoardProject]) -> ProjectBoardLaunchRecoveryDestination {
        switch self {
        case .project(let projectID):
            return availableProjects.contains(where: { $0.id == projectID }) ? self : .today
        case .inbox, .schedule, .today, .done, .assistantQueue:
            return self
        }
    }

}

private struct ProjectDevelopmentAutomationRecoveryView: View {
    let projectID: Int64
    @ObservedObject var viewModel: ProjectBoardViewModel
    @State private var didLoad = false
    @State private var repositoryEditRelativePath = ""
    @State private var repositoryEditContents = ""
    @State private var commitRelativePaths = ""
    @State private var commitMessage = ""

    private var project: ProjectBoardProject? {
        viewModel.snapshot.projects.first { $0.id == projectID }
    }

    private var task: ProjectBoardTask? {
        viewModel.selectedTask
    }

    private var readiness: ProjectDevelopmentAutomationReadiness? {
        guard let project else {
            return nil
        }
        return viewModel.developmentAutomationReadiness(for: project, task: task)
    }

    private var progress: ProjectDevelopmentAutomationProgress? {
        guard let project else {
            return nil
        }
        return viewModel.developmentAutomationProgress(for: project, task: task)
    }

    private var canQueueRepositoryEditReview: Bool {
        progress?.canQueueRepositoryEditReview == true
            && !repositoryEditRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryEditContents.isEmpty
    }

    private var canQueueCommitReview: Bool {
        progress?.canQueueCommitReview == true
            && !commitRelativePaths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var repositoryEditPreview: ProjectDevelopmentAutomationApprovalPreview? {
        guard let project else {
            return nil
        }
        return viewModel.developmentRepositoryEditPreview(
            for: project,
            task: task,
            operation: .create,
            relativePath: repositoryEditRelativePath,
            contents: repositoryEditContents,
            expectedSHA256: nil
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project, let readiness {
                Label(
                    LocalizedStringKey(readiness.statusLabel),
                    systemImage: readiness.isReady ? "checkmark.seal" : "exclamationmark.triangle"
                )
                .font(.headline)
                .foregroundStyle(readiness.isReady ? .green : .orange)
                .accessibilityIdentifier("project-development-automation-status")

                Text(project.title)
                    .font(.title3)
                    .textSelection(.enabled)

                if let task {
                    Text(task.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let blockingReason = readiness.blockingReason {
                    Text(LocalizedStringKey(blockingReason))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let branchNamePreview = readiness.branchNamePreview {
                    LabeledContent("Branch Preview", value: branchNamePreview)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("project-development-automation-branch-preview")
                }

                Button {
                    _ = viewModel.enqueueDevelopmentAutomationReview(for: project, task: task)
                } label: {
                    Label("Queue branch automation", systemImage: "tray.and.arrow.down")
                }
                .disabled(!readiness.isReady)
                .help("Adds the development branch preparation plan to Assistant Queue without creating a branch.")
                .accessibilityIdentifier("project-development-automation-queue")
                .accessibilityHint("Adds the development branch preparation plan to Assistant Queue for review and approval.")

                // The recovery surface mirrors the next approval step so runtime
                // smoke can prove repository edits stay review-gated without
                // loading the full board's heavier AX tree.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Repository edit review")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Repository file path", text: $repositoryEditRelativePath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-edit-path")

                    TextEditor(text: $repositoryEditContents)
                        .font(.caption)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )
                        .accessibilityLabel("Repository file contents")
                        .accessibilityIdentifier("project-development-automation-edit-contents")

                    if let repositoryEditPreview {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(LocalizedStringKey(repositoryEditPreview.title), systemImage: "doc.text.magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)

                            ForEach(repositoryEditPreview.rows) { row in
                                LabeledContent(LocalizedStringKey(row.label), value: row.value)
                                    .font(.caption2)
                                    .textSelection(.enabled)
                                    .accessibilityIdentifier("project-development-automation-edit-preview-row-\(row.id)")
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("project-development-automation-edit-preview")
                        .accessibilityHint("Shows the reviewed repository operation, path, branch, replacement summary, and content digest before queueing approval.")
                    }

                    Button {
                        _ = viewModel.enqueueDevelopmentRepositoryEditReview(
                            for: project,
                            task: task,
                            operation: .create,
                            relativePath: repositoryEditRelativePath,
                            contents: repositoryEditContents,
                            expectedSHA256: nil
                        )
                    } label: {
                        Label("Queue repository edit review", systemImage: "doc.badge.gearshape")
                    }
                    .disabled(!canQueueRepositoryEditReview)
                    .help("Queues a scoped create file review after branch preparation evidence exists.")
                    .accessibilityIdentifier("project-development-automation-edit-queue")
                    .accessibilityHint("Adds the reviewed repository edit to Assistant Queue before verification.")
                }

                Button {
                    _ = viewModel.enqueueDevelopmentVerificationReview(for: project, task: task)
                } label: {
                    Label("Queue verification review", systemImage: "checkmark.shield")
                }
                .disabled(progress?.canQueueVerificationReview != true)
                .help("Queues an approved local verification command after branch preparation evidence exists.")
                .accessibilityIdentifier("project-development-automation-verification-queue")
                .accessibilityHint("Adds a local verification command to Assistant Queue before commit or push.")

                // This mirrors the normal Project detail commit gate without
                // loading the full board tree, keeping runtime AX proof fast and
                // focused on the reviewed approval boundary.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Commit review")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Commit file paths", text: $commitRelativePaths)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-commit-paths")

                    TextField("Commit message", text: $commitMessage)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-commit-message")

                    Button {
                        _ = viewModel.enqueueDevelopmentCommitReview(
                            for: project,
                            task: task,
                            relativePathsText: commitRelativePaths,
                            commitMessage: commitMessage
                        )
                    } label: {
                        Label("Queue commit review", systemImage: "tray.and.arrow.down")
                    }
                    .disabled(!canQueueCommitReview)
                    .help("Queues a local commit review after verification evidence exists.")
                    .accessibilityIdentifier("project-development-automation-commit-queue")
                    .accessibilityHint("Adds the reviewed file list and commit message to Assistant Queue before push.")
                }

                Button {
                    _ = viewModel.enqueueDevelopmentPushReview(for: project, task: task)
                } label: {
                    Label("Queue branch push review", systemImage: "arrow.up.circle")
                }
                .disabled(progress?.canQueueBranchPushReview != true)
                .help("Queues only the reviewed branch push; pull request creation requires a separate approval.")
                .accessibilityIdentifier("project-development-automation-push-queue")
                .accessibilityHint("Adds the reviewed branch push to Assistant Queue before pull request creation.")

                Button {
                    _ = viewModel.enqueueDevelopmentPullRequestCreationReview(for: project, task: task)
                } label: {
                    Label("Queue pull request creation review", systemImage: "arrow.up.right.square")
                }
                .disabled(progress?.canQueuePullRequestCreationReview != true)
                .help("Queues GitHub pull request creation with the reviewed default base branch, title, and body.")
                .accessibilityIdentifier("project-development-automation-pr-create-queue")
                .accessibilityHint("Adds the pull request creation review to Assistant Queue; review and merge still need separate approval.")

                Button {
                    _ = viewModel.enqueueDevelopmentPullRequestLifecycleReview(
                        for: project,
                        task: task,
                        operation: .reviewGate
                    )
                } label: {
                    Label("Queue pull request review gate", systemImage: "checkmark.shield")
                }
                .disabled(progress?.canQueuePullRequestReviewGate != true)
                .help("Uses the pull request creation receipt to queue review, CI, unresolved thread, and mergeability checks.")
                .accessibilityIdentifier("project-development-automation-pr-review-queue")
                .accessibilityHint("Adds only the receipt-backed pull request review gate to Assistant Queue; merge still needs separate approval.")

                Button {
                    _ = viewModel.enqueueDevelopmentPullRequestLifecycleReview(
                        for: project,
                        task: task,
                        operation: .merge
                    )
                } label: {
                    Label("Queue pull request merge gate", systemImage: "arrow.triangle.merge")
                }
                .disabled(progress?.canQueuePullRequestMergeGate != true)
                .help("Uses the review gate receipt to queue merge approval; execution rechecks the approved pull request before merging.")
                .accessibilityIdentifier("project-development-automation-pr-merge-queue")
                .accessibilityHint("Adds the receipt-backed merge gate to Assistant Queue after review evidence exists.")

                if let queueHandoff = progress?.queueHandoff {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Assistant Queue handoff", systemImage: "tray.full")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text(verbatim: "\(queueHandoff.stateLabel) - \(queueHandoff.title)")
                            .font(.caption2)
                        Text(verbatim: queueHandoff.reviewReason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("project-development-automation-queue-handoff")
                    .accessibilityHint("Shows the matching Assistant Queue item for the current development automation approval.")
                }
            } else {
                if didLoad {
                    EmptyView()
                } else {
                    ProgressView("Loading Project")
                }
            }
        }
        // Runtime smoke uses this narrow surface to avoid loading the full board's
        // heavy AX tree; execution remains deferred to the normal Assistant Queue.
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-development-automation")
        .task {
            viewModel.load()
            didLoad = true
            viewModel.selectedProjectID = projectID
            if let taskID = ProjectBoardTaskSelectionPersistence.environmentOverrideTaskID {
                viewModel.selectedTaskID = taskID
            }
        }
    }

}
