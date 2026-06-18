import SoloPMCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct SoloPM: App {
#if canImport(AppKit)
    @NSApplicationDelegateAdaptor(SoloPMAppDelegate.self) private var appDelegate
#endif
    @StateObject private var menuBarController: MenuBarSummaryController
    @AppStorage(SoloPMAppearancePreference.storageKey) private var appearancePreference: SoloPMAppearancePreference = .system

    @MainActor
    init() {
        _menuBarController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarSummaryController())
    }

    var body: some Scene {
        WindowGroup("SoloPM", id: "project-board") {
            ProjectBoardView(viewModel: AppRuntimeFactory.makeProjectBoardViewModel())
                .preferredColorScheme(appearancePreference.colorScheme)
        }
        .defaultSize(width: 1180, height: 760)

        Window("Voice Command", id: "voice-capture") {
            VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())
                .preferredColorScheme(appearancePreference.colorScheme)
        }
        .defaultSize(width: 560, height: 420)

        MenuBarExtra("SoloPM", systemImage: "checklist") {
            MenuBarPanel(controller: menuBarController)
                .preferredColorScheme(appearancePreference.colorScheme)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settingsViewModel: AppRuntimeFactory.makeAppSettingsViewModel(),
                launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
                watcherDiagnosticsSnapshot: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot(),
                externalMCPViewModel: AppRuntimeFactory.makeExternalMCPSettingsViewModel(),
                syncViewModel: AppRuntimeFactory.makeSyncSettingsViewModel()
            )
            .preferredColorScheme(appearancePreference.colorScheme)
        }
    }
}

#if canImport(AppKit)
@MainActor
private final class SoloPMAppDelegate: NSObject, NSApplicationDelegate {
#if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif
    private var projectBoardWindowRestoreAttempts = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ensureProjectBoardWindowIsVisible()

#if canImport(Sparkle)
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String != nil else {
            return
        }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
#endif
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            ensureProjectBoardWindowIsVisible()
            return false
        }
        return true
    }

    private func ensureProjectBoardWindowIsVisible() {
        projectBoardWindowRestoreAttempts = 0
        attemptEnsureProjectBoardWindowIsVisible(after: 0.25)
    }

    private func attemptEnsureProjectBoardWindowIsVisible(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)
            guard self.visibleProjectBoardWindows.isEmpty else {
                return
            }

            let didRequestWindow = self.performNewProjectBoardWindowMenuItem()
                || NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)

            self.projectBoardWindowRestoreAttempts += 1
            guard self.projectBoardWindowRestoreAttempts < 12 else {
                return
            }

            self.attemptEnsureProjectBoardWindowIsVisible(after: didRequestWindow ? 0.75 : 0.25)
        }
    }

    private func performNewProjectBoardWindowMenuItem() -> Bool {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
              let itemIndex = fileMenu.items.firstIndex(where: { $0.title == "New SoloPM Window" && $0.isEnabled }) else {
            return false
        }

        fileMenu.performActionForItem(at: itemIndex)
        return true
    }

    private var visibleProjectBoardWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.isVisible && !window.isMiniaturized && window.title == "SoloPM"
        }
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

            if let emptyStateLabel = controller.emptyStateLabel {
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
        ScrollView {
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
                if let message = viewModel.auditErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                TextEditor(
                    text: Binding(
                        get: { viewModel.draft.text },
                        set: { viewModel.updateDraftText($0) }
                    )
                )
                .font(.body)
                .frame(minHeight: 180, idealHeight: 220)
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            ActionReviewHeader(
                summary: viewModel.session.originalPlan.summary,
                approvalLabel: approvalLabel,
                riskLevel: viewModel.session.originalPlan.riskLevel
            )

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
            if let message = viewModel.auditErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
            viewModel.approveOrReportError()
        } label: {
            Label("Approve", systemImage: "checkmark.seal")
        }
        .disabled(!viewModel.canApprove)

        Button {
            if viewModel.executeOrReportError(), viewModel.session.executionStatus == .completed {
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

private struct ActionReviewHeader: View {
    let summary: String
    let approvalLabel: String
    let riskLevel: RiskLevel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                titleBlock
                Spacer(minLength: 8)
                riskBadge
            }

            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                riskBadge
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary)
                .font(.headline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(summary)
            Text(approvalLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(approvalLabel)
        }
    }

    private var riskBadge: some View {
        Text(riskLevel.rawValue.capitalized)
            .font(.caption)
            .foregroundStyle(riskLevel >= .write ? .orange : .secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ReviewActionRow: View {
    let item: ReviewActionItem
    @ObservedObject var viewModel: ReviewSessionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ReviewActionTitleRow(
                item: item,
                viewModel: viewModel,
                statusLabel: statusLabel,
                statusColor: statusColor
            )

            if item.editedAction.arguments["title"]?.stringValue != nil {
                TextField(
                    "Title",
                    text: Binding(
                        get: { currentStringArgument("title") },
                        set: { viewModel.updateStringArgument(actionID: item.id, key: "title", value: $0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1)
                .help(currentStringArgument("title"))
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

private struct ReviewActionTitleRow: View {
    let item: ReviewActionItem
    @ObservedObject var viewModel: ReviewSessionViewModel
    let statusLabel: String
    let statusColor: Color

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                enabledToggle
                Spacer(minLength: 8)
                statusBadge
            }

            VStack(alignment: .leading, spacing: 6) {
                enabledToggle
                statusBadge
            }
        }
    }

    private var enabledToggle: some View {
        Toggle(
            isOn: Binding(
                get: { item.isEnabled },
                set: { viewModel.setActionEnabled(actionID: item.id, isEnabled: $0) }
            )
        ) {
            Label {
                Text(item.editedAction.tool.rawValue)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: reviewIconName(for: item.editedAction.actionType))
            }
            .font(.subheadline)
            .help(item.editedAction.tool.rawValue)
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.caption)
            .foregroundStyle(statusColor)
            .lineLimit(1)
    }
}

private func reviewIconName(for actionType: ActionType) -> String {
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
    @StateObject private var syncViewModel: SyncSettingsViewModel
    @State private var isConfirmingMCPRegistrationDeletion = false
    @AppStorage(SoloPMAppearancePreference.storageKey) private var appearancePreference: SoloPMAppearancePreference = .system

    init(
        settingsViewModel: AppSettingsViewModel,
        launchAtLoginViewModel: LaunchAtLoginSettingsViewModel,
        watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot,
        externalMCPViewModel: ExternalMCPSettingsViewModel,
        syncViewModel: SyncSettingsViewModel
    ) {
        self.watcherDiagnosticsSnapshot = watcherDiagnosticsSnapshot
        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _launchAtLoginViewModel = StateObject(wrappedValue: launchAtLoginViewModel)
        _externalMCPViewModel = StateObject(wrappedValue: externalMCPViewModel)
        _syncViewModel = StateObject(wrappedValue: syncViewModel)
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearancePreference) {
                    ForEach(SoloPMAppearancePreference.allCases) { preference in
                        Label(preference.label, systemImage: preference.systemImage)
                            .tag(preference)
                    }
                }
                .pickerStyle(.segmented)
            }

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
                    ForEach(STTProvider.releaseReadyCases, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                LabeledContent("Shortcut", value: "Option + Space")
            }

            Section("Sync") {
                LabeledContent("Plan", value: syncViewModel.planLabel)
                LabeledContent("Status", value: syncViewModel.statusLabel)
                LabeledContent("Last Attempt", value: syncViewModel.lastAttemptLabel)
                LabeledContent("Data Included", value: syncViewModel.dataIncludedLabel)
                Toggle(
                    isOn: Binding(
                        get: { syncViewModel.isSyncEnabled },
                        set: { isEnabled in
                            if isEnabled {
                                syncViewModel.startSync()
                            } else {
                                syncViewModel.stopSync()
                            }
                        }
                    )
                ) {
                    Label("External Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!syncViewModel.canEnableSync)
                if !syncViewModel.canEnableSync {
                    Label("Upgrade required", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = syncViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
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
                if let errorMessage = watcherDiagnosticsSnapshot.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("External MCP") {
                HStack {
                    Picker("Server", selection: Binding(
                        get: { externalMCPViewModel.selectedRegistrationID ?? externalMCPViewModel.registration.id },
                        set: { externalMCPViewModel.selectRegistration(id: $0) }
                    )) {
                        ForEach(externalMCPViewModel.registrationRows) { row in
                            Text(row.displayName)
                                .tag(row.id)
                        }
                    }

                    Button {
                        externalMCPViewModel.createRegistration()
                    } label: {
                        Label("Add Server", systemImage: "plus")
                    }
                }

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
                    get: { externalMCPViewModel.argumentsText },
                    set: { externalMCPViewModel.updateArgumentsText($0) }
                ))
                TextField("Working Directory", text: Binding(
                    get: { externalMCPViewModel.registration.workingDirectory ?? "" },
                    set: { externalMCPViewModel.updateWorkingDirectory($0) }
                ))
                TextField("Environment References", text: Binding(
                    get: { externalMCPViewModel.environmentText },
                    set: { externalMCPViewModel.updateEnvironmentText($0) }
                ), axis: .vertical)
                .lineLimit(2...4)
                .help("Use NAME=keychain:secret_key per line. Raw secret values are rejected.")

                Group {
                    LabeledContent("MCP Keychain Secret", value: settingsViewModel.keychainSecretStatusLabel)
                    TextField("Secret Key", text: Binding(
                        get: { settingsViewModel.keychainSecretKeyInput },
                        set: { settingsViewModel.updateKeychainSecretKeyInput($0) }
                    ))
                    .help("Use the same key name referenced by keychain:<secret_key>.")
                    SecureField("Secret Value", text: Binding(
                        get: { settingsViewModel.keychainSecretValueInput },
                        set: { settingsViewModel.updateKeychainSecretValueInput($0) }
                    ))
                    HStack {
                        Button {
                            settingsViewModel.saveKeychainSecret()
                        } label: {
                            Label("Save Secret", systemImage: "key")
                        }
                        .disabled(
                            settingsViewModel.keychainSecretKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            settingsViewModel.keychainSecretValueInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        Button(role: .destructive) {
                            settingsViewModel.deleteKeychainSecret()
                        } label: {
                            Label("Delete Secret", systemImage: "trash")
                        }
                        .disabled(settingsViewModel.keychainSecretKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                LabeledContent("Transport", value: externalMCPViewModel.display.transportLabel)
                LabeledContent("Status", value: externalMCPViewModel.display.statusLabel)
                LabeledContent("Protocol Version", value: externalMCPViewModel.protocolVersionLabel)
                LabeledContent("Resources", value: "Not supported in this release")
                LabeledContent("Prompts", value: "Not supported in this release")
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

                    Button(role: .destructive) {
                        isConfirmingMCPRegistrationDeletion = true
                    } label: {
                        Label("Delete", systemImage: "trash")
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
                if let auditErrorMessage = externalMCPViewModel.auditErrorMessage {
                    Label(auditErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if externalMCPViewModel.auditRows.isEmpty {
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
        .confirmationDialog(
            "Delete MCP Server",
            isPresented: $isConfirmingMCPRegistrationDeletion
        ) {
            Button("Delete", role: .destructive) {
                externalMCPViewModel.deleteRegistration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved registration from SoloPM.")
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

    @MainActor
    static func makeSyncSettingsViewModel() -> SyncSettingsViewModel {
        SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: KeychainEntitlementStore(secretStore: makeSecretStore()),
                configuration: .notConfigured,
                networkClient: UnavailableSyncNetworkClient()
            )
        )
    }

    static func makeWatcherDiagnosticsSnapshot() -> WatcherDiagnosticsSnapshot {
        let permissionSnapshot = UserNotificationsPermissionSnapshotReader.snapshot()
        do {
            let connection = try migratedConnection()
            let settings = loadRuntimeSettings().settings
            return try WatcherDiagnosticsProvider(
                stateStore: SQLiteDailyCheckStateStore(connection: connection),
                permissionSnapshot: permissionSnapshot,
                settings: settings
            ).snapshot()
        } catch {
            return WatcherDiagnosticsSnapshot(
                notificationPermissionStatus: permissionSnapshot.status(for: .notifications),
                errorMessage: "Watcher diagnostics are unavailable because local state could not be opened."
            )
        }
    }

    @MainActor
    static func makeExternalMCPSettingsViewModel() -> ExternalMCPSettingsViewModel {
        let secretStore = makeSecretStore()
        let launcher = MCPStdioServerLauncher(
            environmentResolver: SecretStoreMCPEnvironmentResolver(secretStore: secretStore)
        )
        let store: any MCPServerRegistrationStore
        do {
            store = SQLiteMCPServerRegistrationStore(connection: try migratedConnection())
        } catch {
            store = UnavailableMCPServerRegistrationStore(error: error)
        }
        let auditLoadResult = externalMCPAuditLoadResult()

        return ExternalMCPSettingsViewModel(
            store: store,
            launcher: launcher,
            auditRows: auditLoadResult.rows,
            auditErrorMessage: auditLoadResult.errorMessage
        )
    }

    @MainActor
    static func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel {
        let secretStore = makeSecretStore()
        let settingsResult = loadRuntimeSettings()
        let auditLogger: (any AuditLogger)?
        let runtimeValidationMessage: String?
        let initialFailureMessage: String?
        do {
            auditLogger = try makeAuditLogger()
            runtimeValidationMessage = nil
            initialFailureMessage = settingsResult.errorMessage
        } catch {
            auditLogger = nil
            runtimeValidationMessage = "Voice planning is unavailable because audit logging or local data stores could not be opened."
            initialFailureMessage = runtimeValidationMessage
        }
        return VoiceCaptureViewModel(
            phase: initialFailureMessage.map(VoiceCapturePhase.failed) ?? .idle,
            audioRecorder: AVFoundationAudioRecorder(),
            sttProvider: makeSpeechToTextProvider(settings: settingsResult.settings, secretStore: secretStore),
            llmProvider: makeLLMProvider(settings: settingsResult.settings, secretStore: secretStore),
            auditRecorder: auditLogger.map { PlanningAuditRecorder(logger: $0) },
            runtimeValidationMessage: runtimeValidationMessage
        )
    }

    private static func loadRuntimeSettings() -> RuntimeSettingsLoadResult {
        do {
            return RuntimeSettingsLoadResult(settings: try UserDefaultsAppSettingsStore().load().normalizedForRuntime)
        } catch {
            return RuntimeSettingsLoadResult(
                settings: .default,
                errorMessage: "Runtime app settings could not be loaded. Defaults are shown until settings are saved again."
            )
        }
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
        switch settings.normalizedForRuntime.sttProvider {
        case .openAITranscribe, .appleSpeechAnalyzer, .localWhisperKit, .localWhisperCpp:
            OpenAITranscribeProvider(secretStore: secretStore)
        }
    }

    @MainActor
    static func makeReviewSessionViewModel(plan: ActionPlan) -> ReviewSessionViewModel {
        let logger: (any AuditLogger)?
        let registry: ToolRegistry
        let reviewRuntimeValidationMessage: String?
        do {
            let auditLogger = try makeAuditLogger()
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
                auditLogger: auditLogger
            )
            logger = auditLogger
            reviewRuntimeValidationMessage = nil
        } catch {
            logger = nil
            let baseMessage = "Review execution tools are unavailable because audit logging or local data stores could not be opened."
            let unavailableRegistry = unavailableReviewRegistry(for: plan, message: baseMessage)
            reviewRuntimeValidationMessage = unavailableRegistry.message
            registry = unavailableRegistry.registry
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

    private static func externalMCPAuditLoadResult() -> ExternalMCPAuditLoadResult {
        do {
            let logger = try SQLiteAuditLogger(path: applicationDatabaseURL().path)
            return ExternalMCPAuditLoadResult(rows: try ExternalMCPAuditHistory.rows(from: logger.list(limit: 50)))
        } catch {
            return ExternalMCPAuditLoadResult(
                rows: [],
                errorMessage: "MCP audit history is unavailable because audit logging could not be opened."
            )
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

    private static func unavailableReviewRegistry(for plan: ActionPlan, message: String) -> UnavailableReviewRegistryResult {
        let target = ToolRegistry()
        var registeredTools: [ActionTool] = []
        var registrationFailures: [String] = []
        for action in plan.actions where !registeredTools.contains(action.tool) {
            do {
                try target.register(UnavailableReviewTool(name: action.tool, message: message))
                registeredTools.append(action.tool)
            } catch {
                registrationFailures.append(action.tool.rawValue)
            }
        }
        let finalMessage: String
        if registrationFailures.isEmpty {
            finalMessage = message
        } else {
            finalMessage = "\(message) Fallback unavailable tools could not be registered: \(registrationFailures.joined(separator: ", "))."
        }
        return UnavailableReviewRegistryResult(registry: target, message: finalMessage)
    }

    private static func applicationDatabaseURL() throws -> URL {
        try SoloPMAppDatabaseLocation.defaultDatabaseURL(createDirectory: true)
    }

    private static func applicationSupportDirectoryURL() throws -> URL {
        try SoloPMAppDatabaseLocation.applicationSupportDirectoryURL(createDirectory: true)
    }
}

private struct RuntimeSettingsLoadResult {
    let settings: AppSettings
    let errorMessage: String?

    init(settings: AppSettings, errorMessage: String? = nil) {
        self.settings = settings
        self.errorMessage = errorMessage
    }
}

private struct ExternalMCPAuditLoadResult {
    let rows: [ExternalMCPAuditHistoryRow]
    let errorMessage: String?

    init(rows: [ExternalMCPAuditHistoryRow], errorMessage: String? = nil) {
        self.rows = rows
        self.errorMessage = errorMessage
    }
}

private struct UnavailableReviewRegistryResult {
    let registry: ToolRegistry
    let message: String
}

private struct UnavailableProjectBoardStore: ProjectBoardStore {
    let error: Error

    func loadSnapshot() throws -> ProjectBoardSnapshot {
        throw error
    }

    func loadSnapshot(includeArchived: Bool) throws -> ProjectBoardSnapshot {
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

    func archiveProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func restoreProject(id: Int64) throws -> ProjectBoardProject {
        throw error
    }

    func deleteProject(id: Int64) throws {
        throw error
    }

    func createTask(_ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func updateTask(id: Int64, _ draft: ProjectBoardTaskDraft) throws -> ProjectBoardTask {
        throw error
    }

    func moveTask(id: Int64, to status: ProjectTaskStatus) throws -> ProjectBoardTask {
        throw error
    }

    func moveTasks(ids: [Int64], to status: ProjectTaskStatus) throws -> [ProjectBoardTask] {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }
}

private struct UnavailableMCPServerRegistrationStore: MCPServerRegistrationStore {
    let error: Error

    func loadRegistrations() throws -> [MCPServerRegistration] {
        throw error
    }

    func saveRegistrations(_ registrations: [MCPServerRegistration]) throws {
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
