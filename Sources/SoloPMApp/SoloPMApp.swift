import SoloPMCore
import SwiftUI
#if canImport(Sparkle)
import AppKit
import Sparkle
#endif

@main
struct SoloPM: App {
#if canImport(Sparkle)
    @NSApplicationDelegateAdaptor(SparkleAppDelegate.self) private var sparkleAppDelegate
#endif
    @StateObject private var menuBarController: MenuBarSummaryController

    @MainActor
    init() {
        _menuBarController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarSummaryController())
    }

    var body: some Scene {
        WindowGroup("SoloPM", id: "project-board") {
            ProjectBoardView(viewModel: AppRuntimeFactory.makeProjectBoardViewModel())
        }
        .defaultSize(width: 1180, height: 760)

        Window("Voice Command", id: "voice-capture") {
            VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())
        }
        .defaultSize(width: 560, height: 420)

        MenuBarExtra("SoloPM", systemImage: "checklist") {
            MenuBarPanel(controller: menuBarController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settingsViewModel: AppRuntimeFactory.makeAppSettingsViewModel(),
                launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
                watcherDiagnosticsSnapshot: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot(),
                externalMCPViewModel: AppRuntimeFactory.makeExternalMCPSettingsViewModel()
            )
        }
    }
}

#if canImport(Sparkle)
private final class SparkleAppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }
}
#endif

private struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var controller: MenuBarSummaryController

    private var viewModel: MenuBarSummaryViewModel {
        controller.viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SoloPM")
                    .font(.headline)
                Spacer()
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
            }

            Button {
                openWindow(id: "project-board")
            } label: {
                Label("Project Board", systemImage: "rectangle.3.group")
            }

            Button {
                openWindow(id: "voice-capture")
            } label: {
                Label("Voice Command", systemImage: "mic")
            }
            .keyboardShortcut(.space, modifiers: [.option])

            Divider()

            ForEach(viewModel.rows) { row in
                SummaryRow(row: row)
            }

            if let emptyStateLabel = viewModel.emptyStateLabel {
                Text(emptyStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if viewModel.hasRecentProjects {
                Divider()
                Text("Recent Projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.summary.recentProjectTitles, id: \.self) { title in
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(title)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            controller.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
            controller.refresh()
        }
    }
}

private struct VoiceCaptureView: View {
    @StateObject private var viewModel: VoiceCaptureViewModel

    init(viewModel: VoiceCaptureViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Voice Command", systemImage: "mic")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.clear()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(viewModel.draft.text.isEmpty && viewModel.planningResponse == nil)
            }

            StatusRow(phase: viewModel.phase)

            TextEditor(
                text: Binding(
                    get: { viewModel.draft.text },
                    set: { viewModel.updateDraftText($0) }
                )
            )
                .font(.body)
                .frame(minHeight: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.quaternary)
                }

            HStack {
                Button {
                    if viewModel.isRecording {
                        Task {
                            await viewModel.stopRecording(
                                outputURL: recordingOutputURL()
                            )
                        }
                    } else {
                        viewModel.startRecording()
                    }
                } label: {
                    Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.circle" : "record.circle")
                }
                .disabled(viewModel.phase == .generatingPlan || viewModel.phase == .transcribing)

                Spacer()

                Button {
                    Task {
                        await viewModel.generatePlan()
                    }
                } label: {
                    Label("Generate Plan", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGeneratePlan)
            }

            if let response = viewModel.planningResponse {
                Divider()
                if let plan = response.actionPlan, response.validationResult.isValid {
                    ActionReviewPanel(viewModel: AppRuntimeFactory.makeReviewSessionViewModel(plan: plan)) {
                        NotificationCenter.default.post(name: .soloPMProjectBoardDidChange, object: nil)
                    }
                } else {
                    ActionPlanPreview(response: response)
                }
            }
        }
        .padding(16)
    }

    private func recordingOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-recording-\(UUID().uuidString).m4a")
    }
}

private struct StatusRow: View {
    let phase: VoiceCapturePhase

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(isError ? .red : .secondary)
    }

    private var label: String {
        switch phase {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case .generatingPlan:
            "Generating"
        case .reviewReady:
            "Review ready"
        case .failed(let message):
            message
        }
    }

    private var systemImage: String {
        switch phase {
        case .idle, .reviewReady:
            "checkmark.circle"
        case .recording:
            "record.circle"
        case .transcribing, .generatingPlan:
            "hourglass"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    private var isError: Bool {
        if case .failed = phase {
            return true
        }
        return false
    }
}

private struct ActionReviewPanel: View {
    @StateObject private var viewModel: ReviewSessionViewModel
    private let onExecutionFinished: () -> Void

    init(viewModel: ReviewSessionViewModel, onExecutionFinished: @escaping () -> Void = {}) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onExecutionFinished = onExecutionFinished
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.session.originalPlan.summary)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(approvalLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(viewModel.session.originalPlan.riskLevel.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(viewModel.session.originalPlan.riskLevel >= .write ? .orange : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.session.items) { item in
                        ReviewActionRow(item: item, viewModel: viewModel)
                        Divider()
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 260)

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    actionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    actionButtons
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            try? viewModel.approve()
        } label: {
            Label("Approve", systemImage: "checkmark.seal")
        }
        .disabled(!viewModel.canApprove)

        Button {
            try? viewModel.execute()
            if viewModel.session.executionStatus == .completed {
                onExecutionFinished()
            }
        } label: {
            Label("Execute", systemImage: "play.circle")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canExecute)

        Button {
            viewModel.cancel()
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
        .disabled(viewModel.session.executionStatus == .completed || viewModel.session.executionStatus == .canceled)
    }

    private var approvalLabel: String {
        switch viewModel.session.approvalState {
        case .notRequired:
            "No approval required"
        case .pending:
            "Approval required before execution"
        case .approved:
            "Approved"
        case .blocked(let reason):
            reason
        }
    }
}

private struct ReviewActionRow: View {
    let item: ReviewActionItem
    @ObservedObject var viewModel: ReviewSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Toggle(
                    isOn: Binding(
                        get: { item.isEnabled },
                        set: { viewModel.setActionEnabled(actionID: item.id, isEnabled: $0) }
                    )
                ) {
                    Label {
                        Text(item.editedAction.tool.rawValue)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: iconName(for: item.editedAction.actionType))
                    }
                    .font(.subheadline)
                }
                Spacer(minLength: 8)
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }

            if item.editedAction.arguments["title"]?.stringValue != nil {
                TextField(
                    "Title",
                    text: Binding(
                        get: { currentStringArgument("title") },
                        set: { viewModel.updateStringArgument(actionID: item.id, key: "title", value: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }

            let argumentSummary = item.argumentDisplaySummary(maxFields: 4, maxValueLength: 96)
            Text(argumentSummary.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .help(argumentSummary.fullText)

            ForEach(viewModel.validationIssues(for: item.id), id: \.message) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            if let result = item.result {
                Text(result.summary)
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            if let error = item.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            if let failureRecovery = item.failureRecovery {
                Label(failureRecoveryLabel(failureRecovery), systemImage: failureRecovery == .retryable ? "arrow.clockwise" : "lock")
                    .font(.caption)
                    .foregroundStyle(failureRecoveryColor(failureRecovery))
            }
        }
    }

    private var statusLabel: String {
        switch item.executionStatus {
        case .pending:
            "Pending"
        case .executing:
            "Executing"
        case .succeeded:
            "Done"
        case .failed:
            "Failed"
        case .skipped:
            "Skipped"
        }
    }

    private var statusColor: Color {
        switch item.executionStatus {
        case .succeeded:
            .green
        case .failed:
            .red
        case .skipped:
            .secondary
        default:
            .secondary
        }
    }

    private func currentStringArgument(_ key: String) -> String {
        viewModel.session.items
            .first(where: { $0.id == item.id })?
            .editedAction
            .arguments[key]?
            .stringValue ?? ""
    }

    private func iconName(for actionType: ActionType) -> String {
        switch actionType {
        case .project:
            "folder"
        case .task:
            "checkmark.circle"
        case .notification:
            "bell"
        case .calendar:
            "calendar"
        case .reminder:
            "list.bullet"
        case .filesystem:
            "doc"
        case .knowledgeFrame:
            "text.book.closed"
        case .mailDraft:
            "envelope"
        case .developer:
            "terminal"
        }
    }

    private func failureRecoveryLabel(_ recovery: ReviewActionFailureRecovery) -> String {
        switch recovery {
        case .retryable:
            "Retry available after review"
        case .notRetryable:
            "Requires edit or Settings"
        }
    }

    private func failureRecoveryColor(_ recovery: ReviewActionFailureRecovery) -> Color {
        switch recovery {
        case .retryable:
            .secondary
        case .notRetryable:
            .orange
        }
    }
}

private struct ActionPlanPreview: View {
    let response: PlanningResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let plan = response.actionPlan {
                HStack {
                    Text(plan.summary)
                        .font(.headline)
                    Spacer()
                    Text(plan.riskLevel.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(plan.riskLevel >= .write ? .orange : .secondary)
                }

                ForEach(plan.actions, id: \.id) { action in
                    HStack(alignment: .top) {
                        Image(systemName: iconName(for: action.actionType))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(action.tool.rawValue)
                                .font(.subheadline)
                            Text(argumentSummary(action.arguments))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }

            if !response.validationResult.issues.isEmpty {
                ForEach(response.validationResult.issues, id: \.message) { issue in
                    Label(issue.message, systemImage: issue.severity == .blocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(issue.severity == .blocking ? .red : .orange)
                }
            }
        }
    }

    private func iconName(for actionType: ActionType) -> String {
        switch actionType {
        case .project:
            "folder"
        case .task:
            "checkmark.circle"
        case .notification:
            "bell"
        case .calendar:
            "calendar"
        case .reminder:
            "list.bullet"
        case .filesystem:
            "doc"
        case .knowledgeFrame:
            "text.book.closed"
        case .mailDraft:
            "envelope"
        case .developer:
            "terminal"
        }
    }

    private func argumentSummary(_ arguments: [String: JSONValue]) -> String {
        guard !arguments.isEmpty else {
            return "No arguments"
        }

        return arguments
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value.displayValue)" }
            .joined(separator: ", ")
    }
}

private struct SummaryRow: View {
    let row: MenuBarSummaryRow

    var body: some View {
        HStack {
            Label(row.title, systemImage: row.systemImage)
            Spacer()
            Text(row.value)
                .foregroundStyle(row.tone == .attention ? .orange : .secondary)
        }
    }
}

private struct SettingsView: View {
    let watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @StateObject private var launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    @StateObject private var externalMCPViewModel: ExternalMCPSettingsViewModel

    init(
        settingsViewModel: AppSettingsViewModel,
        launchAtLoginViewModel: LaunchAtLoginSettingsViewModel,
        watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot,
        externalMCPViewModel: ExternalMCPSettingsViewModel
    ) {
        self.watcherDiagnosticsSnapshot = watcherDiagnosticsSnapshot
        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _launchAtLoginViewModel = StateObject(wrappedValue: launchAtLoginViewModel)
        _externalMCPViewModel = StateObject(wrappedValue: externalMCPViewModel)
    }

    var body: some View {
        Form {
            Section("AI") {
                Picker(
                    "Provider",
                    selection: Binding(
                        get: { settingsViewModel.settings.aiProvider },
                        set: { settingsViewModel.setAIProvider($0) }
                    )
                ) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                Button {
                    settingsViewModel.saveSettings()
                } label: {
                    Label("Save Provider Selection", systemImage: "square.and.arrow.down")
                }
                LabeledContent("OpenAI API Key", value: settingsViewModel.openAIAPIKeyStatusLabel)
                SecureField(
                    "OpenAI API Key",
                    text: Binding(
                        get: { settingsViewModel.openAIAPIKeyInput },
                        set: { settingsViewModel.updateOpenAIAPIKeyInput($0) }
                    )
                )
                HStack {
                    Button {
                        settingsViewModel.saveOpenAIAPIKey()
                    } label: {
                        Label("Save Key", systemImage: "key")
                    }
                    .disabled(settingsViewModel.openAIAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(role: .destructive) {
                        settingsViewModel.deleteOpenAIAPIKey()
                    } label: {
                        Label("Delete Key", systemImage: "trash")
                    }
                }
                LabeledContent("OpenRouter API Key", value: settingsViewModel.openRouterAPIKeyStatusLabel)
                SecureField(
                    "OpenRouter API Key",
                    text: Binding(
                        get: { settingsViewModel.openRouterAPIKeyInput },
                        set: { settingsViewModel.updateOpenRouterAPIKeyInput($0) }
                    )
                )
                HStack {
                    Button {
                        settingsViewModel.saveOpenRouterAPIKey()
                    } label: {
                        Label("Save OpenRouter Key", systemImage: "key")
                    }
                    .disabled(settingsViewModel.openRouterAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(role: .destructive) {
                        settingsViewModel.deleteOpenRouterAPIKey()
                    } label: {
                        Label("Delete OpenRouter Key", systemImage: "trash")
                    }
                }
            }

            Section("Voice") {
                Picker(
                    "Speech to Text",
                    selection: Binding(
                        get: { settingsViewModel.settings.sttProvider },
                        set: { settingsViewModel.setSTTProvider($0) }
                    )
                ) {
                    ForEach(STTProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                LabeledContent("Shortcut", value: "Option + Space")
            }

            Section("Privacy") {
                Toggle(
                    "Notifications",
                    isOn: Binding(
                        get: { settingsViewModel.settings.notificationsEnabled },
                        set: { settingsViewModel.setNotificationsEnabled($0) }
                    )
                )
                Toggle(
                    isOn: Binding(
                        get: { launchAtLoginViewModel.isEnabled },
                        set: { launchAtLoginViewModel.setEnabled($0) }
                    )
                ) {
                    Label("Launch at Login", systemImage: "power")
                }
                .disabled(!launchAtLoginViewModel.canToggle)
                LabeledContent("Login Item", value: launchAtLoginViewModel.statusLabel)
                if let statusDetail = launchAtLoginViewModel.statusDetail {
                    Label(statusDetail, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = launchAtLoginViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField(
                    "Workspace",
                    text: Binding(
                        get: { settingsViewModel.settings.defaultWorkspacePath ?? "" },
                        set: { settingsViewModel.setDefaultWorkspacePath($0) }
                    )
                )
                Button {
                    settingsViewModel.saveSettings()
                } label: {
                    Label("Save Settings", systemImage: "square.and.arrow.down")
                }
                if let errorMessage = settingsViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let successMessage = settingsViewModel.successMessage {
                    Label(successMessage, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Watcher") {
                LabeledContent("Last Check", value: diagnosticDateLabel(watcherDiagnosticsSnapshot.lastCheckAt))
                LabeledContent("Next Check", value: diagnosticDateLabel(watcherDiagnosticsSnapshot.nextCheckAt))
                LabeledContent("Notifications", value: permissionLabel(watcherDiagnosticsSnapshot.notificationPermissionStatus))
            }

            Section("External MCP") {
                Toggle(
                    isOn: Binding(
                        get: { externalMCPViewModel.registration.isEnabled },
                        set: { externalMCPViewModel.updateEnabled($0) }
                    )
                ) {
                    Label("Server Enabled", systemImage: "externaldrive.connected.to.line.below")
                }
                TextField("Display Name", text: Binding(
                    get: { externalMCPViewModel.registration.displayName },
                    set: { externalMCPViewModel.updateDisplayName($0) }
                ))
                TextField("Command", text: Binding(
                    get: { externalMCPViewModel.registration.command },
                    set: { externalMCPViewModel.updateCommand($0) }
                ))
                TextField("Arguments", text: Binding(
                    get: { externalMCPViewModel.registration.arguments.joined(separator: " ") },
                    set: { externalMCPViewModel.updateArgumentsText($0) }
                ))
                TextField("Working Directory", text: Binding(
                    get: { externalMCPViewModel.registration.workingDirectory ?? "" },
                    set: { externalMCPViewModel.updateWorkingDirectory($0) }
                ))
                LabeledContent("Transport", value: externalMCPViewModel.display.transportLabel)
                LabeledContent("Status", value: externalMCPViewModel.display.statusLabel)
                ForEach(externalMCPViewModel.display.environmentRows, id: \.name) { row in
                    LabeledContent(row.name, value: row.sourceLabel)
                }
                if let errorMessage = externalMCPViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                HStack {
                    Button {
                        externalMCPViewModel.save()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }

                    Button {
                        Task {
                            await externalMCPViewModel.checkConnection()
                        }
                    } label: {
                        Label("Check Connection", systemImage: "network")
                    }
                    .disabled(externalMCPViewModel.isCheckingConnection)

                    if externalMCPViewModel.isCheckingConnection {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            Section("MCP Tool Permissions") {
                if externalMCPViewModel.toolRows.isEmpty {
                    Text("No tools discovered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(externalMCPViewModel.toolRows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(row.title, systemImage: toolPermissionIcon(row.permissionLevel))
                            Spacer()
                            Text(row.permissionLabel)
                                .font(.caption)
                                .foregroundStyle(toolPermissionColor(row.permissionLevel))
                        }
                        Text(row.inputSchemaSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Section("MCP Audit") {
                if externalMCPViewModel.auditRows.isEmpty {
                    Text("No external calls recorded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(externalMCPViewModel.auditRows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(row.toolName, systemImage: row.status == .failed ? "xmark.octagon" : "checkmark.circle")
                            Spacer()
                            Text(row.statusLabel)
                                .font(.caption)
                                .foregroundStyle(row.status == .failed ? .red : .secondary)
                        }
                        Text("\(row.serverName) / \(row.risk) / \(row.approval)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 620, height: 720)
        .onAppear {
            launchAtLoginViewModel.refresh()
        }
    }

    private func diagnosticDateLabel(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func permissionLabel(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined:
            "Not Determined"
        case .granted:
            "Granted"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        }
    }

    private func toolPermissionIcon(_ permission: ExternalMCPToolPermission) -> String {
        switch permission {
        case .read:
            "eye"
        case .draft:
            "doc.text"
        case .writeWithApproval:
            "checkmark.seal"
        case .dangerous:
            "exclamationmark.triangle"
        case .disabled:
            "nosign"
        }
    }

    private func toolPermissionColor(_ permission: ExternalMCPToolPermission) -> Color {
        switch permission {
        case .read, .draft:
            .secondary
        case .writeWithApproval:
            .orange
        case .dangerous:
            .red
        case .disabled:
            .secondary
        }
    }
}

private enum AppRuntimeFactory {
    @MainActor
    static func makeProjectBoardViewModel() -> ProjectBoardViewModel {
        do {
            return ProjectBoardViewModel(
                store: try SQLiteProjectBoardStore(path: applicationDatabaseURL().path),
                onChange: postProjectBoardDidChange
            )
        } catch {
            return ProjectBoardViewModel(store: UnavailableProjectBoardStore(error: error))
        }
    }

    @MainActor
    static func makeMenuBarSummaryController() -> MenuBarSummaryController {
        do {
            let provider = try SQLiteMenuBarSummaryProvider(path: applicationDatabaseURL().path)
            let controller = MenuBarSummaryController(provider: provider)
            controller.refresh()
            return controller
        } catch {
            let controller = MenuBarSummaryController(provider: UnavailableMenuBarSummaryProvider(error: error))
            controller.refresh()
            return controller
        }
    }

    @MainActor
    static func makeAppSettingsViewModel() -> AppSettingsViewModel {
        AppSettingsViewModel(
            settingsStore: UserDefaultsAppSettingsStore(),
            secretStore: makeSecretStore()
        )
    }

    @MainActor
    static func makeLaunchAtLoginSettingsViewModel() -> LaunchAtLoginSettingsViewModel {
        LaunchAtLoginSettingsViewModel(client: SMAppServiceLaunchAtLoginClient())
    }

    static func makeWatcherDiagnosticsSnapshot() -> WatcherDiagnosticsSnapshot {
        let permissionSnapshot = UserNotificationsPermissionSnapshotReader.snapshot()
        do {
            let connection = try migratedConnection()
            let settings = (try? UserDefaultsAppSettingsStore().load()) ?? .default
            return try WatcherDiagnosticsProvider(
                stateStore: SQLiteDailyCheckStateStore(connection: connection),
                permissionSnapshot: permissionSnapshot,
                settings: settings
            ).snapshot()
        } catch {
            return WatcherDiagnosticsSnapshot(
                notificationPermissionStatus: permissionSnapshot.status(for: .notifications)
            )
        }
    }

    @MainActor
    static func makeExternalMCPSettingsViewModel() -> ExternalMCPSettingsViewModel {
        let secretStore = makeSecretStore()
        let launcher = MCPStdioServerLauncher(
            environmentResolver: SecretStoreMCPEnvironmentResolver(secretStore: secretStore)
        )
        return ExternalMCPSettingsViewModel(
            store: UserDefaultsMCPServerRegistrationStore(),
            launcher: launcher,
            auditRows: externalMCPAuditRows()
        )
    }

    @MainActor
    static func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel {
        let secretStore = makeSecretStore()
        let auditLogger = try? makeAuditLogger()
        let settings = ((try? UserDefaultsAppSettingsStore().load()) ?? .default)
        return VoiceCaptureViewModel(
            audioRecorder: AVFoundationAudioRecorder(),
            sttProvider: makeSpeechToTextProvider(settings: settings, secretStore: secretStore),
            llmProvider: makeLLMProvider(settings: settings, secretStore: secretStore),
            auditRecorder: auditLogger.map { PlanningAuditRecorder(logger: $0) }
        )
    }

    private static func makeLLMProvider(settings: AppSettings, secretStore: any SecretStore) -> any LLMProvider {
        switch settings.aiProvider {
        case .openAIResponses:
            OpenAIResponsesProvider(secretStore: secretStore)
        case .openAICompatible:
            ChatCompletionsCompatibleProvider(
                configuration: .openAICompatible(model: "gpt-5.2"),
                secretStore: secretStore
            )
        case .openRouter:
            ChatCompletionsCompatibleProvider(
                configuration: .openRouter(model: "openai/gpt-latest"),
                secretStore: secretStore
            )
        case .ollama:
            ChatCompletionsCompatibleProvider(
                configuration: .ollama(model: "llama3.2"),
                secretStore: secretStore
            )
        }
    }

    private static func makeSpeechToTextProvider(
        settings: AppSettings,
        secretStore: any SecretStore
    ) -> any SpeechToTextProvider {
        switch settings.sttProvider {
        case .appleSpeechAnalyzer:
            AppleSpeechAnalyzerProvider()
        case .localWhisperKit:
            WhisperKitProvider()
        case .localWhisperCpp:
            WhisperCppProvider()
        case .openAITranscribe:
            OpenAITranscribeProvider(secretStore: secretStore)
        }
    }

    @MainActor
    static func makeReviewSessionViewModel(plan: ActionPlan) -> ReviewSessionViewModel {
        let logger = try? makeAuditLogger()
        let registry: ToolRegistry
        let reviewRuntimeValidationMessage: String?
        do {
            let connection = try migratedConnection()
            registry = try ToolRegistry.phase2MVP(
                projectStore: SQLiteProjectStore(connection: connection),
                taskStore: SQLiteTaskStore(connection: connection),
                knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection),
                notificationClient: UserNotificationsNotificationClient(),
                calendarClient: EventKitCalendarClient(),
                reminderClient: EventKitReminderClient(),
                fileAccessClient: LocalFileAccessClient(workspaceRoot: try workspaceRootURL()),
                mailDraftClient: UnavailableMailDraftClient(),
                notificationRequestStore: SQLiteNotificationRequestStore(connection: connection),
                calendarLinkStore: SQLiteCalendarLinkStore(connection: connection),
                reminderLinkStore: SQLiteReminderLinkStore(connection: connection),
                auditLogger: logger
            )
            reviewRuntimeValidationMessage = nil
        } catch {
            reviewRuntimeValidationMessage = "Review execution tools are unavailable because local data stores could not be opened."
            registry = unavailableReviewRegistry(for: plan, message: reviewRuntimeValidationMessage ?? "Review execution tools are unavailable.")
        }

        return ReviewSessionViewModel(
            plan: plan,
            executor: ActionExecutor(registry: registry, auditLogger: logger),
            auditLogger: logger,
            runtimeValidationMessage: reviewRuntimeValidationMessage
        )
    }

    private static func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: applicationDatabaseURL().path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private static func makeSecretStore() -> any SecretStore {
        KeychainSecretStore()
    }

    private static func makeAuditLogger() throws -> any AuditLogger {
        RedactingAuditLogger(base: try SQLiteAuditLogger(path: applicationDatabaseURL().path))
    }

    private static func externalMCPAuditRows() -> [ExternalMCPAuditHistoryRow] {
        do {
            let logger = try SQLiteAuditLogger(path: applicationDatabaseURL().path)
            return ExternalMCPAuditHistory.rows(from: try logger.list(limit: 50))
        } catch {
            return []
        }
    }

    private static func postProjectBoardDidChange() {
        NotificationCenter.default.post(name: .soloPMProjectBoardDidChange, object: nil)
    }

    private static func workspaceRootURL() throws -> URL {
        let directory = try applicationSupportDirectoryURL().appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func unavailableReviewRegistry(for plan: ActionPlan, message: String) -> ToolRegistry {
        let target = ToolRegistry()
        var registeredTools: [ActionTool] = []
        for action in plan.actions where !registeredTools.contains(action.tool) {
            try? target.register(UnavailableReviewTool(name: action.tool, message: message))
            registeredTools.append(action.tool)
        }
        return target
    }

    private static func applicationDatabaseURL() throws -> URL {
        try applicationSupportDirectoryURL().appendingPathComponent("SoloPM.sqlite")
    }

    private static func applicationSupportDirectoryURL() throws -> URL {
        guard let applicationSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw DatabaseError.openFailed("Application Support directory was not found.")
        }

        let directory = applicationSupportURL.appendingPathComponent("SoloPM", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private struct UnavailableProjectBoardStore: ProjectBoardStore {
    let error: Error

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        throw error
    }

    func createProject(title: String) throws -> ProjectBoardProject {
        throw error
    }

    func updateProject(id: Int64, title: String) throws -> ProjectBoardProject {
        throw error
    }

    func completeProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }
}

private struct UnavailableMenuBarSummaryProvider: MenuBarSummaryProviding {
    let error: Error

    func loadMenuBarSummary() throws -> MenuBarSummary {
        throw error
    }
}

private struct UnavailableReviewTool: Tool {
    let name: ActionTool
    let message: String
    let description = "Unavailable review execution tool."
    let inputSchema = ToolInputSchema(additionalProperties: true)
    let permissionLevel: ToolPermissionLevel = .read

    func execute(arguments: [String: JSONValue], context: ToolExecutionContext) throws -> ToolResult {
        throw ToolExecutionError.executionFailed(name, message)
    }
}

private struct UnavailableMailDraftClient: MailDraftClient {
    func createTextDraft(to: String?, subject: String, body: String) throws -> MailDraftRecord {
        throw ToolClientError.invalidRequest("Mail draft integration is not enabled in this release.")
    }

    func listDrafts() throws -> [MailDraftRecord] {
        []
    }
}

private extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    var displayValue: String {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(value)
        case .bool(let value):
            value ? "true" : "false"
        case .object:
            "object"
        case .array:
            "list"
        case .null:
            "null"
        }
    }
}
