import Foundation
import SuisuiCore
import SwiftUI

private struct InspectorCloseHeader: View {
    let title: LocalizedStringKey
    let systemImage: String
    let closeTitle: LocalizedStringKey
    let closeHelp: String
    let closeAccessibilityIdentifier: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 12)

            InspectorCloseButton(
                closeTitle: closeTitle,
                closeHelp: closeHelp,
                accessibilityIdentifier: closeAccessibilityIdentifier,
                onClose: onClose
            )
        }
    }
}
private struct InspectorCloseButton: View {
    let closeTitle: LocalizedStringKey
    let closeHelp: String
    let accessibilityIdentifier: String
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Label(closeTitle, systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .keyboardShortcut(.escape, modifiers: [])
        .help(closeHelp)
        .accessibilityLabel(closeTitle)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct ProjectInspectorView: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onReviewDevelopmentAutomation: (ActionPlan) -> Void
    let onClose: () -> Void

    @State private var title: String
    @State private var workspacePathInput: String
    @State private var isConfirmingArchive = false
    @State private var isConfirmingDelete = false

    init(
        project: ProjectBoardProject,
        viewModel: ProjectBoardViewModel,
        onReviewDevelopmentAutomation: @escaping (ActionPlan) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.project = project
        self.viewModel = viewModel
        self.onReviewDevelopmentAutomation = onReviewDevelopmentAutomation
        self.onClose = onClose
        _title = State(initialValue: project.title)
        _workspacePathInput = State(initialValue: project.workspacePath ?? "")
    }

    var body: some View {
        Form {
            Section {
                InspectorCloseHeader(
                    title: "Project Details",
                    systemImage: "folder",
                    closeTitle: "Close Project Details",
                    closeHelp: String(localized: "Close Project Details"),
                    closeAccessibilityIdentifier: "project-inspector-close",
                    onClose: onClose
                )
            }

            Section("Summary") {
                ProjectInspectorMetadataSummary(project: project)
            }

            Section("Project AI Activity") {
                ExecutionReceiptHistoryInspectorSection(
                    snapshot: viewModel.executionReceiptHistorySnapshot(forProjectID: project.id),
                    emptyTitle: "No AI activity for this project yet",
                    emptyDescription: "AI activity appears here after approved AI work references this project.",
                    accessibilityIdentifier: "project-execution-receipts"
                )
            }

            Section("Edit") {
                TextField("Title", text: $title)
                    .accessibilityIdentifier("project-inspector-title")
                LabeledContent("Status", value: project.status.capitalized)
                LabeledContent("Tasks", value: project.subtitle)
                LabeledContent("Artifacts", value: "\(project.artifacts.count)")
            }

            Section("Project Directory") {
                LabeledContent("Current", value: project.workspaceDisplayName ?? "Not set")
                    .accessibilityIdentifier("project-workspace-current")

                LocalPathSelectionField(
                    title: "Project directory path",
                    text: $workspacePathInput,
                    selectionKind: .directory,
                    accessibilityIdentifier: "project-workspace-path-input",
                    browseAccessibilityIdentifier: "project-workspace-choose",
                    canCreateDirectories: true,
                    onSelection: { applyProjectDirectory(url: $0) }
                )
                .disabled(project.isArchived)
                if workspacePathInput.isEmpty == false && workspacePathInput.hasPrefix("/") == false {
                    Label("Enter an absolute path beginning with /.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("project-workspace-path-validation")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        applyProjectDirectoryButton
                        clearProjectDirectoryButton
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        applyProjectDirectoryButton
                        clearProjectDirectoryButton
                    }
                }
            }

            Section("Development Automation") {
                ProjectDevelopmentAutomationPanel(
                    project: project,
                    viewModel: viewModel,
                    onReviewDevelopmentAutomation: onReviewDevelopmentAutomation
                )
            }

            Section("Save") {
                Button {
                    viewModel.updateSelectedProject(title: title)
                } label: {
                    Label("Save Project", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title == project.title)
                .keyboardShortcut("s", modifiers: [.command])
                .help("Saves edits to the selected project in the local Suisui database")
                .accessibilityIdentifier("project-inspector-save")
                .accessibilityHint("Saves edits to the selected project in the local Suisui database.")
            }

            Section("Suggestion") {
                ProjectInspectorSuggestionSection(project: project, viewModel: viewModel)
            }

            Section("Actions") {
                if project.isArchived {
                    Button {
                        viewModel.restoreSelectedProject()
                    } label: {
                        Label("Restore Project", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Restores the selected project to active views in the local Suisui database")
                    .accessibilityIdentifier("project-inspector-restore")
                    .accessibilityHint("Restores the selected project to active views in the local Suisui database.")
                } else {
                    Button {
                        viewModel.completeSelectedProject()
                    } label: {
                        Label("Complete Project", systemImage: "checkmark.seal")
                    }
                    .disabled(project.isCompleted)
                    .help("Completes the selected project in the local Suisui database")
                    .accessibilityIdentifier("project-inspector-complete")
                    .accessibilityHint("Completes the selected project in the local Suisui database.")
                }
            }

            Section("Danger Zone") {
                if isConfirmingArchive {
                    InspectorDestructiveConfirmation(
                        title: "Archive this project?",
                        message: "This hides the project from the active board and deadline summaries. Existing local tasks are kept in the Suisui database.",
                        confirmTitle: "Archive Project",
                        confirmSystemImage: "archivebox",
                        accessibilityIdentifier: "project-inspector-archive-confirmation",
                        confirmAction: archiveSelectedProjectAfterConfirmationDismissal,
                        cancelAction: { isConfirmingArchive = false }
                    )
                } else if !project.isArchived {
                    Button(role: .destructive) {
                        isConfirmingDelete = false
                        isConfirmingArchive = true
                    } label: {
                        Label("Archive Project", systemImage: "archivebox")
                    }
                    .help("Archives the selected project after confirmation")
                    .accessibilityIdentifier("project-inspector-archive")
                    .accessibilityHint("Archives the selected project after confirmation.")
                }

                if isConfirmingDelete {
                    InspectorDestructiveConfirmation(
                        title: "Delete this project?",
                        message: "This permanently removes the project, its local tasks, deadline rules, artifact links, calendar links, and reminder links from Suisui.",
                        confirmTitle: "Delete Project",
                        confirmSystemImage: "trash",
                        accessibilityIdentifier: "project-inspector-delete-confirmation",
                        confirmAction: deleteSelectedProjectAfterConfirmationDismissal,
                        cancelAction: { isConfirmingDelete = false }
                    )
                } else {
                    Button(role: .destructive) {
                        isConfirmingArchive = false
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Project", systemImage: "trash")
                    }
                    .keyboardShortcut(.delete, modifiers: [.command])
                    .help("Deletes the selected project after confirmation")
                    .accessibilityIdentifier("project-inspector-delete")
                    .accessibilityHint("Deletes the selected project after confirmation.")
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-inspector")
        .accessibilityLabel("Project inspector for \(project.title)")
        .accessibilityHint("Edit, save, archive, restore, or delete the selected project.")
        .onAppear {
            refreshFields(from: project)
        }
        .onChange(of: project) { _, newProject in
            refreshFields(from: newProject)
        }
    }

    private func refreshFields(from project: ProjectBoardProject) {
        title = project.title
        workspacePathInput = project.workspacePath ?? ""
    }

    private var applyProjectDirectoryButton: some View {
        Button {
            let path = workspacePathInput.trimmingCharacters(in: .whitespacesAndNewlines)
            applyProjectDirectory(url: URL(fileURLWithPath: path, isDirectory: true))
        } label: {
            Label("Apply Path", systemImage: "checkmark.circle")
        }
        .disabled(
            project.isArchived
                || workspacePathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || workspacePathInput.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") == false
        )
        .help("Store the entered project directory and its local permission")
        .accessibilityIdentifier("project-workspace-apply-path")
        .accessibilityHint("Validates and stores the project directory entered in the path field.")
    }

    private var clearProjectDirectoryButton: some View {
        Button {
            if viewModel.clearProjectWorkspacePath(projectID: project.id) {
                workspacePathInput = ""
            }
        } label: {
            Label("Clear Directory", systemImage: "xmark.circle")
        }
        .disabled(project.isArchived || !project.hasWorkspaceDirectory)
        .help("Clear this project's local directory permission")
        .accessibilityIdentifier("project-workspace-clear")
        .accessibilityHint("Removes the stored project directory from Suisui without deleting files.")
    }

    private func applyProjectDirectory(url: URL) {
        #if canImport(AppKit)
        let standardizedURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            viewModel.reportProjectWorkspaceSelectionFailure()
            return
        }
        let bookmarkData: Data
        do {
            // The bookmark keeps both typed and Finder-selected paths on the
            // same security-scoped persistence boundary used by automation.
            bookmarkData = try standardizedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            viewModel.reportProjectWorkspaceSelectionFailure()
            return
        }
        if viewModel.assignProjectWorkspacePath(
            standardizedURL.path,
            bookmarkData: bookmarkData,
            projectID: project.id
        ) {
            workspacePathInput = standardizedURL.path
        }
        #endif
    }

    private func archiveSelectedProjectAfterConfirmationDismissal() {
        isConfirmingArchive = false
        DispatchQueue.main.async {
            viewModel.archiveSelectedProject()
        }
    }

    private func deleteSelectedProjectAfterConfirmationDismissal() {
        isConfirmingDelete = false
        DispatchQueue.main.async {
            viewModel.deleteSelectedProject()
        }
    }
}

private struct ProjectDevelopmentAutomationPanel: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onReviewDevelopmentAutomation: (ActionPlan) -> Void

    @State private var pullRequestDraftKey: String?
    @State private var pullRequestBaseBranch = ""
    @State private var pullRequestTitle = ""
    @State private var pullRequestBody = ""
    @State private var commitDraftKey: String?
    @State private var commitRelativePaths = ""
    @State private var commitMessage = ""
    @State private var repositoryEditOperation: ProjectDevelopmentRepositoryEditOperation = .create
    @State private var repositoryEditRelativePath = ""
    @State private var repositoryEditExpectedSHA256 = ""
    @State private var repositoryEditContents = ""

    private var readiness: ProjectDevelopmentAutomationReadiness {
        viewModel.developmentAutomationReadiness(for: project, task: viewModel.selectedTask)
    }

    private func repositoryRelativePath(for url: URL) -> String {
        guard let workspacePath = project.workspacePath else {
            return url.path
        }
        let workspaceURL = URL(fileURLWithPath: workspacePath, isDirectory: true).standardizedFileURL
        let selectedURL = url.standardizedFileURL
        let workspacePrefix = workspaceURL.path.hasSuffix("/") ? workspaceURL.path : "\(workspaceURL.path)/"
        guard selectedURL.path.hasPrefix(workspacePrefix) else {
            return selectedURL.path
        }
        return String(selectedURL.path.dropFirst(workspacePrefix.count))
    }

    private var developmentProgress: ProjectDevelopmentAutomationProgress {
        viewModel.developmentAutomationProgress(for: project, task: viewModel.selectedTask)
    }

    private var pullRequestDraft: ProjectDevelopmentPullRequestCreationDraft? {
        viewModel.developmentPullRequestCreationDraft(for: project, task: viewModel.selectedTask)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                LocalizedStringKey(readiness.statusLabel),
                systemImage: readiness.isReady ? "checkmark.seal" : "exclamationmark.triangle"
            )
                .font(.headline)
                .foregroundStyle(readiness.isReady ? .green : .orange)
                .accessibilityIdentifier("project-development-automation-status")

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

            LabeledContent("Prepare Tool", value: readiness.toolName)
                .font(.caption)
                .textSelection(.enabled)

            Button {
                guard let plan = viewModel.prepareDevelopmentAutomationReview(for: project, task: viewModel.selectedTask) else {
                    return
                }
                onReviewDevelopmentAutomation(plan)
            } label: {
                Label("Review branch automation", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(!readiness.isReady)
            .help("Opens an approval-gated review for preparing a local development branch.")
            .accessibilityIdentifier("project-development-automation-review")
            .accessibilityHint("Opens an approval-gated review for preparing a local development branch.")

            Button {
                _ = viewModel.enqueueDevelopmentAutomationReview(for: project, task: viewModel.selectedTask)
            } label: {
                Label("Queue branch automation", systemImage: "tray.and.arrow.down")
            }
            .disabled(!readiness.isReady)
            .help("Adds the development branch preparation plan to Assistant Queue without creating a branch.")
            .accessibilityIdentifier("project-development-automation-queue")
            .accessibilityHint("Adds the development branch preparation plan to Assistant Queue for review and approval.")

            VStack(alignment: .leading, spacing: 8) {
                Text("Repository edit review")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Repository edit operation", selection: $repositoryEditOperation) {
                    ForEach(ProjectDevelopmentRepositoryEditOperation.allCases) { operation in
                        Text(LocalizedStringKey(operation.title)).tag(operation)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("project-development-automation-edit-operation")

                LocalPathSelectionField(
                    title: "Repository file path",
                    text: $repositoryEditRelativePath,
                    selectionKind: .file,
                    accessibilityIdentifier: "project-development-automation-edit-path",
                    baseDirectoryURL: project.workspacePath.map { URL(fileURLWithPath: $0, isDirectory: true) },
                    selectedPath: repositoryRelativePath(for:)
                )

                TextField("Expected SHA for updates", text: $repositoryEditExpectedSHA256)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("project-development-automation-edit-expected-sha")

                TextEditor(text: $repositoryEditContents)
                    .font(.caption)
                    .frame(minHeight: 96)
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
                        task: viewModel.selectedTask,
                        operation: repositoryEditOperation,
                        relativePath: repositoryEditRelativePath,
                        contents: repositoryEditContents,
                        expectedSHA256: repositoryEditExpectedSHA256
                    )
                } label: {
                    Label("Queue repository edit review", systemImage: "doc.badge.gearshape")
                }
                .disabled(!canQueueRepositoryEditReview)
                .help("Queues a scoped create or update file review after branch preparation evidence exists.")
                .accessibilityIdentifier("project-development-automation-edit-queue")
                .accessibilityHint("Adds the reviewed repository edit to Assistant Queue before verification.")
            }

            Button {
                _ = viewModel.enqueueDevelopmentVerificationReview(for: project, task: viewModel.selectedTask)
            } label: {
                Label("Queue verification review", systemImage: "checkmark.shield")
            }
            .disabled(!developmentProgress.canQueueVerificationReview)
            .help("Queues an approved local verification command after branch preparation evidence exists.")
            .accessibilityIdentifier("project-development-automation-verification-queue")
            .accessibilityHint("Adds a local verification command to Assistant Queue before commit or push.")

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
                        task: viewModel.selectedTask,
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
            .onAppear {
                syncCommitDraftIfNeeded()
            }
            .onChange(of: viewModel.selectedTask?.id) { _, _ in
                syncCommitDraftIfNeeded()
            }
            .onChange(of: readiness.branchNamePreview) { _, _ in
                syncCommitDraftIfNeeded()
            }

            Button {
                _ = viewModel.enqueueDevelopmentPushReview(for: project, task: viewModel.selectedTask)
            } label: {
                Label("Queue branch push review", systemImage: "arrow.up.circle")
            }
            .disabled(!developmentProgress.canQueueBranchPushReview)
            .help("Queues a branch push approval; execution rechecks the current branch, clean workspace, and GitHub origin before running.")
            .accessibilityIdentifier("project-development-automation-push-queue")
            .accessibilityHint("Adds only the branch push review to Assistant Queue; pull request creation still needs a separate approval.")

            Button {
                _ = viewModel.enqueueDevelopmentPullRequestCreationReview(
                    for: project,
                    task: viewModel.selectedTask
                )
            } label: {
                Label("Queue pull request creation review", systemImage: "arrow.up.right.square")
            }
            .disabled(!canQueuePullRequestCreationReview)
            .help("Queues GitHub pull request creation with the reviewed draft base branch, title, and body.")
            .accessibilityIdentifier("project-development-automation-pr-create-queue")
            .accessibilityHint("Adds only the pull request creation review to Assistant Queue; review and merge still need separate approval.")

            if let pullRequestDraft {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pull request creation")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Base branch", text: $pullRequestBaseBranch)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-pr-base")

                    TextField("Pull request title", text: $pullRequestTitle)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("project-development-automation-pr-title")

                    TextEditor(text: $pullRequestBody)
                        .font(.caption)
                        .frame(minHeight: 96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(.quaternary)
                        )
                        .accessibilityLabel("Pull request body")
                        .accessibilityIdentifier("project-development-automation-pr-body")

                    Button {
                        _ = viewModel.enqueueDevelopmentPullRequestCreationReview(
                            for: project,
                            task: viewModel.selectedTask,
                            baseBranch: pullRequestBaseBranch,
                            title: pullRequestTitle,
                            body: pullRequestBody
                        )
                    } label: {
                        Label("Queue pull request creation review", systemImage: "arrow.up.right.square")
                    }
                    .disabled(!canQueuePullRequestCreationReview)
                    .help("Queues GitHub pull request creation for approval after reviewing the base branch, title, and body.")
                    .accessibilityIdentifier("project-development-automation-pr-create-detailed-queue")
                    .accessibilityHint("Adds only the pull request creation review to Assistant Queue; review and merge still need separate approval.")
                }
                .onAppear {
                    syncPullRequestDraftIfNeeded(pullRequestDraft)
                }
                .onChange(of: pullRequestDraft) { _, newValue in
                    syncPullRequestDraftIfNeeded(newValue)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pull request progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let nextApproval = developmentProgress.nextApproval {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(LocalizedStringKey(nextApproval.title), systemImage: "arrow.right.circle")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        Text(LocalizedStringKey(nextApproval.detail))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("project-development-automation-next-approval")
                    .accessibilityHint("Shows the next receipt-backed approval to prevent pull requests from being left unreviewed.")
                }

                if let approvalPreview = developmentProgress.approvalPreview {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(LocalizedStringKey(approvalPreview.title), systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)

                        ForEach(approvalPreview.rows) { row in
                            LabeledContent(LocalizedStringKey(row.label), value: row.value)
                                .font(.caption2)
                                .textSelection(.enabled)
                                .accessibilityIdentifier("project-development-automation-approval-preview-row-\(row.id)")
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("project-development-automation-approval-preview")
                    .accessibilityHint("Shows the receipt-backed branch, commit, and pull request evidence for the next development approval.")
                }

                if let queueHandoff = developmentProgress.queueHandoff {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Assistant Queue handoff", systemImage: "tray.full")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)

                        Text(verbatim: "\(queueHandoff.stateLabel) - \(queueHandoff.title)")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(verbatim: queueHandoff.reviewReason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let latestReceiptStatusLabel = queueHandoff.latestReceiptStatusLabel {
                            Text(verbatim: "\(String(localized: "Latest receipt")): \(latestReceiptStatusLabel)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(queueHandoffStatusText(for: queueHandoff))
                            .font(.caption2)
                            .foregroundStyle(queueHandoff.canRun ? .green : .secondary)

                        ForEach(Array(queueHandoff.capabilityLabels.enumerated()), id: \.offset) { index, capability in
                            Text(verbatim: capability)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("project-development-automation-queue-handoff-capability-\(index)")
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("project-development-automation-queue-handoff")
                    .accessibilityHint("Shows the matching Assistant Queue item for the current development automation approval.")
                }

                ForEach(developmentProgress.stages) { stage in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: progressStageIcon(for: stage.status))
                            .foregroundStyle(progressStageColor(for: stage.status))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(LocalizedStringKey(stage.title))
                                    .font(.caption)
                                Text(LocalizedStringKey(stage.status.label))
                                    .font(.caption2)
                                    .foregroundStyle(progressStageColor(for: stage.status))
                            }
                            if let detail = stage.detail {
                                Text(verbatim: detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("project-development-automation-progress-stage-\(stage.id)")
                }

                if let pullRequestURL = developmentProgress.pullRequestURL {
                    LabeledContent("Pull Request", value: pullRequestURL)
                        .font(.caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("project-development-automation-progress-pr-url")
                }
                if let baseBranch = developmentProgress.baseBranch {
                    LabeledContent("Base Branch", value: baseBranch)
                        .font(.caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("project-development-automation-progress-base")
                }
                if let latestCommitOID = developmentProgress.latestCommitOID {
                    LabeledContent("Latest Commit", value: latestCommitOID)
                        .font(.caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("project-development-automation-progress-commit")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        _ = viewModel.enqueueDevelopmentPullRequestLifecycleReview(
                            for: project,
                            task: viewModel.selectedTask,
                            operation: .reviewGate
                        )
                    } label: {
                        Label("Queue pull request review gate", systemImage: "checkmark.shield")
                    }
                    .disabled(!developmentProgress.canQueuePullRequestReviewGate)
                    .help("Uses the pull request creation receipt to queue review, CI, unresolved thread, and mergeability checks.")
                    .accessibilityIdentifier("project-development-automation-pr-review-queue")
                    .accessibilityHint("Adds only the receipt-backed pull request review gate to Assistant Queue; merge still needs separate approval.")

                    Button {
                        _ = viewModel.enqueueDevelopmentPullRequestLifecycleReview(
                            for: project,
                            task: viewModel.selectedTask,
                            operation: .merge
                        )
                    } label: {
                        Label("Queue pull request merge gate", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(!developmentProgress.canQueuePullRequestMergeGate)
                    .help("Uses the review gate receipt to queue merge approval; execution rechecks the approved pull request before merging.")
                    .accessibilityIdentifier("project-development-automation-pr-merge-queue")
                    .accessibilityHint("Adds the receipt-backed merge gate to Assistant Queue after review evidence exists.")
                }

                if let blockingReason = developmentProgress.blockingReason {
                    Text(LocalizedStringKey(blockingReason))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("project-development-automation-progress-message")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("project-development-automation-progress")

            if hasMatchingReviewPlan {
                Text(LocalizedStringKey("Review plan is ready. Approve and execute it before any local branch is created."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project-development-automation-review-ready")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scoped file operations")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(readiness.allowedFileOperations, id: \.self) { operation in
                        Text(operation)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text(LocalizedStringKey(readiness.approvalBoundaryLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("project-development-automation-approval-boundary")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PR lifecycle tools")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(Array(readiness.lifecycleToolNames.enumerated()), id: \.offset) { index, toolName in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(LocalizedStringKey(lifecycleToolDisplayName(for: toolName)), systemImage: lifecycleToolIcon(for: toolName))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(toolName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("project-development-automation-lifecycle-tool-\(index)")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(readiness.reviewSteps.enumerated()), id: \.offset) { index, step in
                    Label(LocalizedStringKey(step), systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("project-development-automation-step-\(index)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project-development-automation")
    }

    private var hasMatchingReviewPlan: Bool {
        guard let action = viewModel.developmentAutomationReviewPlan?.actions.first(where: { $0.tool == .developmentPreparePullRequestWorkflow }) else {
            return false
        }
        return action.arguments["projectId"] == .number(Double(project.id))
            && action.arguments["taskId"] == readiness.taskID.map { .number(Double($0)) }
            && action.arguments["branchName"] == readiness.branchNamePreview.map(JSONValue.string)
    }

    private var canQueuePullRequestCreationReview: Bool {
        developmentProgress.canQueuePullRequestCreationReview
            && !pullRequestBaseBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pullRequestTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !pullRequestBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canQueueCommitReview: Bool {
        developmentProgress.canQueueCommitReview
            && !commitRelativePaths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canQueueRepositoryEditReview: Bool {
        let hasRequiredUpdateDigest = repositoryEditOperation == .create
            || !repositoryEditExpectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return developmentProgress.canQueueRepositoryEditReview
            && !repositoryEditRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !repositoryEditContents.isEmpty
            && hasRequiredUpdateDigest
    }

    private var repositoryEditPreview: ProjectDevelopmentAutomationApprovalPreview? {
        viewModel.developmentRepositoryEditPreview(
            for: project,
            task: viewModel.selectedTask,
            operation: repositoryEditOperation,
            relativePath: repositoryEditRelativePath,
            contents: repositoryEditContents,
            expectedSHA256: repositoryEditExpectedSHA256
        )
    }

    private func syncPullRequestDraftIfNeeded(_ draft: ProjectDevelopmentPullRequestCreationDraft) {
        let key = "\(draft.projectID):\(draft.taskID):\(draft.branchName)"
        guard pullRequestDraftKey != key else {
            return
        }
        pullRequestDraftKey = key
        pullRequestBaseBranch = draft.baseBranch
        pullRequestTitle = draft.title
        pullRequestBody = draft.body
    }

    private func syncCommitDraftIfNeeded() {
        guard let task = viewModel.selectedTask,
              let branchName = readiness.branchNamePreview else {
            return
        }
        let key = "\(project.id):\(task.id):\(branchName)"
        guard commitDraftKey != key else {
            return
        }
        commitDraftKey = key
        commitRelativePaths = ""
        commitMessage = "Update task \(task.id)"
    }

    private func progressStageIcon(for status: ProjectDevelopmentAutomationProgressStageStatus) -> String {
        switch status {
        case .waiting:
            return "circle"
        case .ready:
            return "arrow.right.circle"
        case .succeeded:
            return "checkmark.circle"
        case .failed:
            return "xmark.octagon"
        }
    }

    private func progressStageColor(for status: ProjectDevelopmentAutomationProgressStageStatus) -> Color {
        switch status {
        case .waiting:
            return .secondary
        case .ready:
            return .accentColor
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }

    private func queueHandoffStatusText(
        for handoff: ProjectDevelopmentAutomationQueueHandoff
    ) -> LocalizedStringKey {
        switch handoff.state {
        case .approved:
            return handoff.canRun ? "Ready to run from Assistant Queue" : "Approved in Assistant Queue"
        case .running:
            return "Running in Assistant Queue"
        case .blocked:
            return "Blocked in Assistant Queue"
        case .failed:
            return "Failed in Assistant Queue"
        case .deferred:
            return "Deferred in Assistant Queue"
        case .done:
            return "Completed in Assistant Queue"
        case .rejected:
            return "Rejected in Assistant Queue"
        case .captured, .interpreted, .drafted, .waitingReview:
            return "Waiting for review approval"
        }
    }

    private func lifecycleToolIcon(for toolName: String) -> String {
        if toolName.contains("repository") {
            return "doc.text"
        }
        if toolName.contains("verification") {
            return "checkmark.shield"
        }
        if toolName.contains("commit") {
            return "tray.and.arrow.down"
        }
        if toolName.contains("push") || toolName.contains("pull_request") {
            return "arrow.up.right.circle"
        }
        if toolName.contains("merge") {
            return "arrow.triangle.merge"
        }
        return "point.topleft.down.curvedto.point.bottomright.up"
    }

    private func lifecycleToolDisplayName(for toolName: String) -> String {
        switch toolName {
        case ActionTool.developmentPreparePullRequestWorkflow.rawValue:
            return "Prepare branch"
        case ActionTool.developmentRepositoryListFiles.rawValue:
            return "List project files"
        case ActionTool.developmentRepositoryReadFile.rawValue:
            return "Read project file"
        case ActionTool.developmentRepositoryCreateFile.rawValue:
            return "Create project file"
        case ActionTool.developmentRepositoryUpdateFile.rawValue:
            return "Update project file"
        case ActionTool.developmentRunVerification.rawValue:
            return "Run verification"
        case ActionTool.developmentCommitChanges.rawValue:
            return "Commit changes"
        case ActionTool.developmentPushBranch.rawValue:
            return "Push branch"
        case ActionTool.developmentCreatePullRequest.rawValue:
            return "Create pull request"
        case ActionTool.developmentReviewPullRequestGate.rawValue:
            return "Review pull request"
        case ActionTool.developmentMergePullRequest.rawValue:
            return "Merge pull request"
        default:
            return "Development tool"
        }
    }
}

private struct ProjectInspectorMetadataSummary: View {
    let project: ProjectBoardProject

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
            metadataPills
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project summary")
        .accessibilityValue("\(statusLabel), \(openTaskCount) open tasks, \(project.taskCount) total tasks, \(project.artifacts.count) artifacts")
        .accessibilityIdentifier("project-inspector-metadata-summary")
    }

    @ViewBuilder
    private var metadataPills: some View {
        InspectorMetadataPill(
            label: "Status",
            value: statusLabel,
            systemImage: statusSystemImage,
            tint: statusTint
        )

        InspectorMetadataPill(
            label: "Open",
            value: "\(openTaskCount)",
            systemImage: "circle",
            tint: .blue
        )

        InspectorMetadataPill(
            label: "Tasks",
            value: "\(project.taskCount)",
            systemImage: "checklist",
            tint: .secondary
        )

        InspectorMetadataPill(
            label: "Artifacts",
            value: "\(project.artifacts.count)",
            systemImage: "doc.text",
            tint: .purple
        )
    }

    private var openTaskCount: Int {
        project.tasks.filter { $0.status != .done }.count
    }

    private var statusLabel: String {
        if project.isArchived {
            return "Archived"
        }
        if project.isCompleted {
            return "Completed"
        }
        return "Active"
    }

    private var statusSystemImage: String {
        if project.isArchived {
            return "archivebox"
        }
        if project.isCompleted {
            return "checkmark.seal"
        }
        return "circle.fill"
    }

    private var statusTint: Color {
        if project.isArchived {
            return .secondary
        }
        if project.isCompleted {
            return .green
        }
        return .blue
    }
}

private struct ProjectInspectorSuggestionSection: View {
    let project: ProjectBoardProject
    @ObservedObject var viewModel: ProjectBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(suggestionText, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                applySuggestion()
            } label: {
                Label("Apply Suggestion", systemImage: "wand.and.stars")
            }
            .disabled(suggestionAction == .none)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Applies the local next-step suggestion to the selected project")
            .accessibilityIdentifier("project-inspector-apply-suggestion")
            .accessibilityHint("Applies the local next-step suggestion to the selected project.")
        }
    }

    private var suggestionAction: ProjectInspectorSuggestionAction {
        if project.isArchived {
            return .restoreProject
        }
        if project.taskCount == 0 {
            return .createFirstTask
        }
        if !project.isCompleted && project.tasks.allSatisfy({ $0.status == .done }) {
            return .completeProject
        }
        if let blockedTask = project.tasks.first(where: { $0.status == .blocked }) {
            return .openTask(blockedTask.id)
        }
        if let highPriorityTask = project.tasks.first(where: { $0.status != .done && $0.priority == .high }) {
            return .openTask(highPriorityTask.id)
        }
        if let dueTask = project.tasks
            .filter({ $0.status != .done && $0.dueAt != nil })
            .sorted(by: { ($0.dueAt ?? "") < ($1.dueAt ?? "") })
            .first {
            return .openTask(dueTask.id)
        }
        return .none
    }

    private var suggestionText: String {
        switch suggestionAction {
        case .restoreProject:
            return localizedDisplay("Restore this project before editing tasks or including it in active summaries.")
        case .createFirstTask:
            return localizedDisplay("Create a first concrete task so the project has a next action.")
        case .completeProject:
            return localizedDisplay("All tasks are done. Complete the project to keep active views focused.")
        case .openTask:
            return localizedDisplay("Open the highest-signal task and decide its next move in the inspector.")
        case .none:
            return localizedDisplay("No project-level suggestion is needed right now.")
        }
    }

    private func applySuggestion() {
        switch suggestionAction {
        case .restoreProject:
            viewModel.restoreSelectedProject()
        case .createFirstTask:
            _ = viewModel.createTask(title: localizedDisplay("Define next action"), projectID: project.id, status: .backlog)
        case .completeProject:
            viewModel.completeSelectedProject()
        case .openTask(let taskID):
            viewModel.selectedTaskID = taskID
        case .none:
            break
        }
    }
}

private enum ProjectInspectorSuggestionAction: Equatable {
    case restoreProject
    case createFirstTask
    case completeProject
    case openTask(Int64)
    case none
}

struct TaskInspectorView: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel
    let onClose: () -> Void

    @State private var title: String
    @State private var detail: String
    @State private var status: ProjectTaskStatus
    @State private var priority: ProjectTaskPriority
    @State private var dueDate: TaskDueDateFieldState
    @State private var hasInvalidPersistedDueDate: Bool
    @State private var recurrence: String
    @State private var isConfirmingDelete = false

    init(task: ProjectBoardTask, viewModel: ProjectBoardViewModel, onClose: @escaping () -> Void) {
        self.task = task
        self.viewModel = viewModel
        self.onClose = onClose
        _title = State(initialValue: task.title)
        _detail = State(initialValue: task.detail)
        _status = State(initialValue: task.status)
        _priority = State(initialValue: task.priority)
        let parsedDueDate = TaskDueDateFieldState.parsePersisted(task.dueAt)
        _dueDate = State(initialValue: parsedDueDate.state)
        _hasInvalidPersistedDueDate = State(initialValue: parsedDueDate.isInvalid)
        _recurrence = State(initialValue: task.recurrence ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            if let failure = viewModel.taskSaveFailure(taskID: task.id) {
                HStack(spacing: 8) {
                    Label(failure.message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(SuisuiTone.danger.color)
                        .accessibilityIdentifier("task-inspector-save-error")
                    Spacer(minLength: 8)
                    Button("Retry", systemImage: "arrow.clockwise") {
                        viewModel.retryCurrentFailure()
                    }
                    .accessibilityIdentifier("task-inspector-save-retry")
                    .accessibilityHint("Retries saving the current task edits.")
                }
                .padding(10)
            }

            Form {
                Section {
                    InspectorCloseHeader(
                        title: "Task Details",
                        systemImage: "checklist",
                        closeTitle: "Close Task Details",
                        closeHelp: String(localized: "Close Task Details"),
                        closeAccessibilityIdentifier: "task-inspector-close",
                        onClose: onClose
                    )
                }

                Section("Summary") {
                    TaskInspectorMetadataSummary(
                        task: task, projectTitle: viewModel.projectTitle(for: task))
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
                            Label {
                                Text(LocalizedStringKey(status.title))
                            } icon: {
                                Image(systemName: status.systemImage)
                            }
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

                    if let persistedDate = dueDate.persistedDate {
                        DatePicker(
                            "Due",
                            selection: Binding(
                                get: { persistedDate },
                                set: {
                                    dueDate = .value($0)
                                    hasInvalidPersistedDueDate = false
                                }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .accessibilityIdentifier("task-inspector-due")

                        Button("Clear Due Date", systemImage: "xmark.circle") {
                            dueDate = .empty
                            hasInvalidPersistedDueDate = false
                        }
                        .accessibilityIdentifier("task-inspector-due-clear")
                        .accessibilityHint("Removes the due date after Save Changes is pressed.")
                    } else {
                        Button("Set Due Date", systemImage: "calendar.badge.plus") {
                            dueDate = .value(Date())
                            hasInvalidPersistedDueDate = false
                        }
                        .accessibilityIdentifier("task-inspector-due")
                        .accessibilityHint(
                            "Adds a due date that can be adjusted with the native date picker.")
                    }

                    if hasInvalidPersistedDueDate {
                        Label(
                            "The saved due date is invalid. Set or clear it before saving.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(SuisuiTone.attention.color)
                        .accessibilityIdentifier("task-inspector-due-error")
                    }

                    Picker("Repeat", selection: $recurrence) {
                        Text("None").tag("")
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                        Text("Monthly").tag("monthly")
                    }
                    .help("Repeats the task by creating the next occurrence when it is completed")
                    .accessibilityIdentifier("task-inspector-recurrence-picker")
                }

                Section("Save") {
                    Button {
                        saveChanges()
                    } label: {
                        Label("Save Changes", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || hasInvalidPersistedDueDate
                    )
                    .keyboardShortcut("s", modifiers: [.command])
                    .help("Saves edits to the selected task in the local Suisui database")
                    .accessibilityIdentifier("task-inspector-save")
                    .accessibilityHint(
                        "Saves edits to the selected task in the local Suisui database.")

                }

                Section("Suggestion") {
                    TaskInspectorSuggestionSection(task: task, viewModel: viewModel)
                }

                Section("Automation") {
                    TaskInspectorAutomationSection(task: task, viewModel: viewModel)
                }

                Section("Task AI Activity") {
                    ExecutionReceiptHistoryInspectorSection(
                        snapshot: viewModel.executionReceiptHistorySnapshot(forTaskID: task.id),
                        emptyTitle: "No AI activity for this task yet",
                        emptyDescription:
                            "AI activity appears here after approved AI work references this task.",
                        accessibilityIdentifier: "task-execution-receipts"
                    )
                }

                Section("Danger Zone") {
                    if isConfirmingDelete {
                        InspectorDestructiveConfirmation(
                            title: "Delete this task?",
                            message: "This removes the task from the local Suisui database.",
                            confirmTitle: "Delete Task",
                            confirmSystemImage: "trash",
                            // The runtime AX preflight tracks this generated cancel
                            // identifier after opening the destructive confirmation:
                            // task-inspector-delete-confirmation-cancel.
                            accessibilityIdentifier: "task-inspector-delete-confirmation",
                            confirmAction: deleteSelectedTaskAfterConfirmationDismissal,
                            cancelAction: { isConfirmingDelete = false }
                        )
                    } else {
                        Button(role: .destructive) {
                            isConfirmingDelete = true
                        } label: {
                            Label("Delete Task", systemImage: "trash")
                        }
                        .keyboardShortcut(.delete, modifiers: [.command])
                        .help("Deletes the selected task after confirmation")
                        .accessibilityIdentifier("task-inspector-delete")
                        .accessibilityHint("Deletes the selected task after confirmation.")
                    }
                }
            }
            .formStyle(.grouped)
            .accessibilityIdentifier("task-inspector")
            .accessibilityLabel("Task inspector for \(task.title)")
            .accessibilityHint("Edit, save, move, or delete the selected task.")
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
        let parsedDueDate = TaskDueDateFieldState.parsePersisted(task.dueAt)
        dueDate = parsedDueDate.state
        hasInvalidPersistedDueDate = parsedDueDate.isInvalid
        recurrence = task.recurrence ?? ""
    }

    private func saveChanges() {
        guard !hasInvalidPersistedDueDate else { return }
        viewModel.updateSelectedTask(
            title: title,
            detail: detail,
            status: status,
            priority: priority,
            dueDate: dueDate.persistedDate,
            recurrence: recurrence.nilIfBlank
        )
    }

    private func deleteSelectedTaskAfterConfirmationDismissal() {
        isConfirmingDelete = false
        DispatchQueue.main.async {
            viewModel.deleteSelectedTask()
        }
    }
}

private struct InspectorDestructiveConfirmation: View {
    let title: String
    let message: String
    let confirmTitle: String
    let confirmSystemImage: String
    let accessibilityIdentifier: String
    let confirmAction: () -> Void
    let cancelAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("Cancel", role: .cancel, action: cancelAction)
                    .accessibilityIdentifier("\(accessibilityIdentifier)-cancel")
                    .accessibilityLabel("Cancel \(confirmTitle)")
                    .accessibilityHint("Cancels \(confirmTitle) and returns to the inspector.")
                Button(role: .destructive, action: confirmAction) {
                    Label(confirmTitle, systemImage: confirmSystemImage)
                }
                .accessibilityIdentifier("\(accessibilityIdentifier)-confirm")
                .accessibilityLabel("Confirm \(confirmTitle)")
                .accessibilityHint("Confirms \(confirmTitle).")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct TaskInspectorMetadataSummary: View {
    let task: ProjectBoardTask
    let projectTitle: String

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8)]
    }

    var body: some View {
        LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
            metadataPills
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Task summary")
        .accessibilityValue(
            "\(task.status.title), \(task.priority.label), \(dueValue), \(projectTitle)"
        )
        .accessibilityIdentifier("task-inspector-metadata-summary")
    }

    @ViewBuilder
    private var metadataPills: some View {
        InspectorMetadataPill(
            label: "Status",
            value: task.status.title,
            systemImage: task.status.systemImage,
            tint: task.status.tint
        )

        InspectorMetadataPill(
            label: "Priority",
            value: task.priority.label,
            systemImage: "flag",
            tint: task.priority.color
        )

        InspectorMetadataPill(
            label: "Due",
            value: dueValue,
            systemImage: "calendar",
            tint: localizedTaskDueLabel(task) == nil ? .secondary : .blue
        )

        InspectorMetadataPill(
            label: "Project",
            value: projectTitle,
            systemImage: "folder",
            tint: .purple
        )
    }

    private var dueValue: String {
        localizedTaskDueLabel(task) ?? localizedDisplay("No due date")
    }
}

private struct ExecutionReceiptHistoryInspectorSection: View {
    let snapshot: ExecutionReceiptHistorySnapshot
    let emptyTitle: LocalizedStringKey
    let emptyDescription: LocalizedStringKey
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let unavailableMessage = snapshot.unavailableMessage {
                ContentUnavailableView(
                    "AI activity is unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(unavailableMessage)
                )
            } else if snapshot.rows.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(emptyDescription)
                )
            } else {
                ForEach(snapshot.rows) { row in
                    ExecutionReceiptHistoryRowView(row: row)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct InspectorMetadataPill: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(LocalizedStringKey(value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        }
        .help("\(label): \(value)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct TaskInspectorSuggestionSection: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var targetStatus: ProjectTaskStatus? {
        if task.status == .blocked {
            return .inProgress
        }
        return task.status.nextStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(suggestionText, systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard let targetStatus else {
                    return
                }
                viewModel.moveSelectedTask(to: targetStatus)
            } label: {
                Label("Apply Suggestion", systemImage: "wand.and.stars")
            }
            .disabled(targetStatus == nil)
            .keyboardShortcut(.return, modifiers: [.command])
            .help("Applies the local next-step suggestion to the selected task")
            .accessibilityIdentifier("task-inspector-apply-suggestion")
            .accessibilityHint("Applies the local next-step suggestion to the selected task.")
        }
    }

    private var suggestionText: String {
        if task.status == .done {
            return localizedDisplay("This task is already complete.")
        }
        if task.status == .blocked {
            return localizedDisplay("If the blocker is resolved, move this task back into active work.")
        }
        if task.priority == .high {
            return localizedDisplay("High-priority task: move it forward when the next step is clear.")
        }
        return localizedDisplay("Move this task to the next status when you are ready.")
    }
}

private struct TaskInspectorAutomationSection: View {
    let task: ProjectBoardTask
    @ObservedObject var viewModel: ProjectBoardViewModel

    private var hasReviewDraft: Bool {
        viewModel.taskAutomationReviewDecision?.selectedTasks.contains(where: { $0.id == task.id }) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review-only task automation", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                viewModel.prepareAutomationReviewForSelectedTask()
            } label: {
                Label("Review automation plan", systemImage: "doc.text.magnifyingglass")
            }
            .help("Prepares review-only local automation for the selected task")
            .accessibilityIdentifier("task-auto-execution-review")
            .accessibilityHint("Prepares review-only local automation for the selected task.")

            Button {
                viewModel.runApprovedAutomationForSelectedTask()
            } label: {
                Label("Run approved plan", systemImage: "play.circle")
            }
            .disabled(!hasReviewDraft)
            .help("Runs the reviewed local task step after explicit user approval")
            .accessibilityIdentifier("task-auto-execution-run-plan")
            .accessibilityHint("Runs the reviewed local task step after explicit user approval.")

            if hasReviewDraft {
                Text(localizedDisplay("Review draft is ready. Running it only starts local task execution."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasReviewDraft && !documentDeliverableReviews.isEmpty {
                documentDeliverableReviewView(documentDeliverableReviews)
            }

            if let receipt = latestApprovedExecutionReceipt {
                approvedExecutionReceiptView(receipt)
            }
        }
    }

    private var documentDeliverableReviews: [TaskAutomationDocumentDeliverableReview] {
        viewModel.taskAutomationDocumentDeliverableReviews
    }

    private var latestApprovedExecutionReceipt: ApprovedAutomationExecutionReceipt? {
        // Show the persisted redacted receipt, not current task text, so the audit trail
        // stays tied to what the user approved.
        viewModel.approvedAutomationExecutionReceipts.last { $0.taskID == task.id }
    }

    private func documentDeliverableReviewView(_ reviews: [TaskAutomationDocumentDeliverableReview]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Document deliverables", systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))

            ForEach(reviews) { deliverable in
                VStack(alignment: .leading, spacing: 6) {
                    Text(deliverable.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text(localizedDisplay(deliverable.riskLevel.rawValue.capitalized))
                        Text(deliverable.suggestedPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    Text(deliverable.rationale)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    if !deliverable.sourceDocuments.isEmpty {
                        Text("Source documents")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(deliverable.sourceDocuments) { source in
                            documentSourceRow(source)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-auto-execution-document-deliverables")
        .accessibilityLabel("Document deliverables")
        .accessibilityHint("Shows the draft-only document outputs and redacted source documents for the reviewed automation plan.")
    }

    private func documentSourceRow(_ source: TaskAutomationDocumentSourceReview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
            Text(source.redactedSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(source.inclusionReason)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("task-auto-execution-document-source-\(source.id)")
        .accessibilityLabel("Automation document source")
        .accessibilityValue(documentSourceAccessibilityValue(source))
        .accessibilityHint("Shows the redacted document source preview used for the reviewed automation draft.")
    }

    private func documentSourceAccessibilityValue(_ source: TaskAutomationDocumentSourceReview) -> String {
        [
            "Title \(source.title)",
            "Summary \(source.redactedSummary)",
            "Reason \(source.inclusionReason)"
        ].joined(separator: ", ")
    }

    private func approvedExecutionReceiptView(_ receipt: ApprovedAutomationExecutionReceipt) -> some View {
        let statusText = [
            "Status: \(localizedDisplay(receipt.statusBefore.title))",
            "to \(localizedDisplay(receipt.statusAfter.title))"
        ].joined(separator: " ")

        return VStack(alignment: .leading, spacing: 6) {
            Label("Approved execution receipt", systemImage: "checkmark.seal")
                .font(.caption.weight(.semibold))

            Text("Task: \(receipt.redactedTaskTitle)")
                .lineLimit(2)
            Text("Reviewed detail: \(receipt.redactedTaskDetail)")
                .lineLimit(3)
            Text(statusText)
            Text("Reason: \(receipt.reviewReason)")
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("approved-execution-receipt")
        .accessibilityLabel("Approved execution receipt")
        .accessibilityValue(approvedExecutionReceiptAccessibilityValue(receipt))
        .accessibilityHint("Shows the redacted task title and detail that were approved and executed.")
    }

    private func approvedExecutionReceiptAccessibilityValue(_ receipt: ApprovedAutomationExecutionReceipt) -> String {
        [
            "Task \(receipt.redactedTaskTitle)",
            "Reviewed detail \(receipt.redactedTaskDetail)",
            "Status \(localizedDisplay(receipt.statusBefore.title)) to \(localizedDisplay(receipt.statusAfter.title))",
            "Reason \(receipt.reviewReason)"
        ].joined(separator: ", ")
    }
}
