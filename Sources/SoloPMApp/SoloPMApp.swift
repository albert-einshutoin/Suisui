import SoloPMCore
import SwiftUI
#if canImport(Sparkle)
import AppKit
import Sparkle
#endif

@main
struct SoloPMApplication: App {
#if canImport(Sparkle)
    @NSApplicationDelegateAdaptor(SparkleAppDelegate.self) private var sparkleAppDelegate
#endif

    private let menuBarViewModel = AppPreviewFactory.makeMenuBarSummaryViewModel()
    private let settings = AppSettings.default

    var body: some Scene {
        MenuBarExtra("SoloPM", systemImage: "checklist") {
            MenuBarPanel(viewModel: menuBarViewModel)
        }
        .menuBarExtraStyle(.window)

        Window("Voice Command", id: "voice-capture") {
            VoiceCaptureView(viewModel: AppPreviewFactory.makeVoiceCaptureViewModel())
        }
        .defaultSize(width: 560, height: 420)

        Settings {
            SettingsView(
                settings: settings,
                launchAtLoginViewModel: AppPreviewFactory.makeLaunchAtLoginSettingsViewModel(),
                watcherDiagnosticsSnapshot: AppPreviewFactory.makeWatcherDiagnosticsSnapshot(),
                externalMCPRegistration: AppPreviewFactory.makeExternalMCPRegistration(),
                externalMCPToolRows: AppPreviewFactory.makeExternalMCPToolRows(),
                externalMCPAuditRows: AppPreviewFactory.makeExternalMCPAuditRows()
            )
        }
    }
}

#if canImport(Sparkle)
private final class SparkleAppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    let viewModel: MenuBarSummaryViewModel

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
                openWindow(id: "voice-capture")
            } label: {
                Label("Voice Command", systemImage: "mic")
            }

            Divider()

            ForEach(viewModel.rows) { row in
                SummaryRow(row: row)
            }

            if let emptyStateLabel = viewModel.emptyStateLabel {
                Text(emptyStateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.hasRecentProjects {
                Divider()
                Text("Recent Projects")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(viewModel.summary.recentProjectTitles, id: \.self) { title in
                    Text(title)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
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
                                outputURL: FileManager.default.temporaryDirectory
                                    .appendingPathComponent("solopm-demo-recording.m4a")
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
                    ActionReviewPanel(viewModel: AppPreviewFactory.makeReviewSessionViewModel(plan: plan))
                } else {
                    ActionPlanPreview(response: response)
                }
            }
        }
        .padding(16)
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

    init(viewModel: ReviewSessionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.session.originalPlan.summary)
                        .font(.headline)
                    Text(approvalLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(viewModel.session.originalPlan.riskLevel.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(viewModel.session.originalPlan.riskLevel >= .write ? .orange : .secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.session.items) { item in
                        ReviewActionRow(item: item, viewModel: viewModel)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 220)

            if let message = viewModel.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    try? viewModel.approve()
                } label: {
                    Label("Approve", systemImage: "checkmark.seal")
                }
                .disabled(!viewModel.canApprove)

                Button {
                    try? viewModel.execute()
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
        }
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
                    Label(item.editedAction.tool.rawValue, systemImage: iconName(for: item.editedAction.actionType))
                        .font(.subheadline)
                }
                Spacer()
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
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

            Text(argumentSummary(item.editedAction.arguments))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

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
    let settings: AppSettings
    let watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot
    let externalMCPToolRows: [ExternalMCPToolCatalogRow]
    let externalMCPAuditRows: [ExternalMCPAuditHistoryRow]
    @StateObject private var launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    @State private var externalMCPRegistration: MCPServerRegistration

    init(
        settings: AppSettings,
        launchAtLoginViewModel: LaunchAtLoginSettingsViewModel,
        watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot,
        externalMCPRegistration: MCPServerRegistration,
        externalMCPToolRows: [ExternalMCPToolCatalogRow],
        externalMCPAuditRows: [ExternalMCPAuditHistoryRow]
    ) {
        self.settings = settings
        self.watcherDiagnosticsSnapshot = watcherDiagnosticsSnapshot
        self.externalMCPToolRows = externalMCPToolRows
        self.externalMCPAuditRows = externalMCPAuditRows
        _launchAtLoginViewModel = StateObject(wrappedValue: launchAtLoginViewModel)
        _externalMCPRegistration = State(initialValue: externalMCPRegistration)
    }

    var body: some View {
        Form {
            Section("AI") {
                LabeledContent("Provider", value: settings.aiProvider.displayName)
                SecureField("API Key", text: .constant(""))
                    .disabled(true)
            }

            Section("Voice") {
                LabeledContent("Speech to Text", value: settings.sttProvider.displayName)
                LabeledContent("Shortcut", value: "Option + Space")
            }

            Section("Privacy") {
                Toggle("Notifications", isOn: .constant(settings.notificationsEnabled))
                    .disabled(true)
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
                if let errorMessage = launchAtLoginViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                LabeledContent("Workspace", value: settings.defaultWorkspacePath ?? "Not selected")
            }

            Section("Watcher") {
                LabeledContent("Last Check", value: diagnosticDateLabel(watcherDiagnosticsSnapshot.lastCheckAt))
                LabeledContent("Next Check", value: diagnosticDateLabel(watcherDiagnosticsSnapshot.nextCheckAt))
                LabeledContent("Notifications", value: permissionLabel(watcherDiagnosticsSnapshot.notificationPermissionStatus))
            }

            Section("External MCP") {
                Toggle(
                    isOn: Binding(
                        get: { externalMCPRegistration.isEnabled },
                        set: { externalMCPRegistration.isEnabled = $0 }
                    )
                ) {
                    Label("Server Enabled", systemImage: "externaldrive.connected.to.line.below")
                }
                TextField("Display Name", text: Binding(
                    get: { externalMCPRegistration.displayName },
                    set: { externalMCPRegistration.displayName = $0 }
                ))
                TextField("Command", text: Binding(
                    get: { externalMCPRegistration.command },
                    set: { externalMCPRegistration.command = $0 }
                ))
                TextField("Arguments", text: Binding(
                    get: { externalMCPRegistration.arguments.joined(separator: " ") },
                    set: { externalMCPRegistration.arguments = $0.split(separator: " ").map(String.init) }
                ))
                TextField("Working Directory", text: Binding(
                    get: { externalMCPRegistration.workingDirectory ?? "" },
                    set: {
                        let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        externalMCPRegistration.workingDirectory = trimmed.isEmpty ? nil : trimmed
                    }
                ))
                LabeledContent("Transport", value: externalMCPDisplay.transportLabel)
                LabeledContent("Status", value: externalMCPDisplay.statusLabel)
                ForEach(externalMCPDisplay.environmentRows, id: \.name) { row in
                    LabeledContent(row.name, value: row.sourceLabel)
                }
            }

            Section("MCP Tool Permissions") {
                ForEach(externalMCPToolRows, id: \.id) { row in
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
                ForEach(Array(externalMCPAuditRows.enumerated()), id: \.offset) { _, row in
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

    private var externalMCPDisplay: MCPServerRegistrationDisplayModel {
        MCPServerRegistrationDisplayModel(registration: externalMCPRegistration)
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

private enum AppPreviewFactory {
    static func makeMenuBarSummaryViewModel() -> MenuBarSummaryViewModel {
        MenuBarSummaryViewModel(
            summary: MenuBarSummary(
                todayTaskCount: 2,
                overdueTaskCount: 1,
                dueThisWeekCount: 5,
                recentProjectTitles: ["SoloPM Phase 4", "QZT article"]
            )
        )
    }

    @MainActor
    static func makeLaunchAtLoginSettingsViewModel() -> LaunchAtLoginSettingsViewModel {
        LaunchAtLoginSettingsViewModel(client: SMAppServiceLaunchAtLoginClient())
    }

    static func makeWatcherDiagnosticsSnapshot() -> WatcherDiagnosticsSnapshot {
        WatcherDiagnosticsSnapshot(
            lastCheckAt: nil,
            nextCheckAt: Date(),
            notificationPermissionStatus: .notDetermined
        )
    }

    static func makeExternalMCPRegistration() -> MCPServerRegistration {
        MCPServerRegistration(
            id: "development-fake-mcp",
            displayName: "Development Fake MCP",
            command: "node",
            arguments: ["server.js"],
            environment: ["GITHUB_TOKEN": .keychain(.githubToken)],
            workingDirectory: nil,
            isEnabled: false
        )
    }

    static func makeExternalMCPToolRows() -> [ExternalMCPToolCatalogRow] {
        let server = MCPRegisteredServerDescriptor(id: "development-fake-mcp", displayName: "Development Fake MCP")
        let registry = ExternalMCPToolRegistry(
            server: server,
            tools: ExternalMCPTestKit.fakeToolDefinitions(),
            classifier: ExternalMCPToolClassifier(explicitPolicies: [
                "read_status": .read,
                "write_issue": .writeWithApproval,
                "danger_delete": .dangerous
            ])
        )
        return ExternalMCPToolCatalog.rows(from: registry.allDescriptors)
    }

    static func makeExternalMCPAuditRows() -> [ExternalMCPAuditHistoryRow] {
        ExternalMCPAuditHistory.rows(from: [
            AuditEvent(
                category: "external_mcp",
                action: "development-fake-mcp.read_status",
                status: .succeeded,
                metadata: [
                    "server_name": "Development Fake MCP",
                    "tool_name": "read_status",
                    "risk": "read",
                    "approval": "missing",
                    "duration_ms": "12",
                    "arguments": "project=soloPM"
                ]
            )
        ])
    }

    @MainActor
    static func makeVoiceCaptureViewModel() -> VoiceCaptureViewModel {
        VoiceCaptureViewModel(
            sttProvider: FakeSTTProvider(transcript: STTTranscript(text: "Create a task to review the SoloPM Phase 1 UI")),
            llmProvider: DemoPlanningProvider(),
            auditRecorder: PlanningAuditRecorder(logger: RedactingAuditLogger(base: InMemoryAuditLogger()))
        )
    }

    @MainActor
    static func makeReviewSessionViewModel(plan: ActionPlan) -> ReviewSessionViewModel {
        let baseLogger = InMemoryAuditLogger()
        let logger = RedactingAuditLogger(base: baseLogger)
        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent("SoloPMPreviewWorkspace", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        let registry = (try? ToolRegistryFactory.inMemoryPhase2MVP(workspaceRoot: workspaceRoot, auditLogger: logger)) ?? ToolRegistry()

        return ReviewSessionViewModel(
            plan: plan,
            executor: ActionExecutor(registry: registry, auditLogger: logger),
            auditLogger: logger
        )
    }
}

private struct DemoPlanningProvider: LLMProvider {
    let providerID = "demo.local"

    func generatePlan(for request: PlanningRequest) async throws -> PlanningResponse {
        let plan = ActionPlan(
            id: "plan-demo",
            userInput: request.userInput,
            summary: "Create a task",
            actions: [
                PlanAction(
                    id: "action-demo-project",
                    tool: .projectCreate,
                    arguments: [
                        "title": .string("SoloPM Demo")
                    ]
                ),
                PlanAction(
                    id: "action-demo-task",
                    tool: .taskCreate,
                    arguments: [
                        "title": .string(request.userInput),
                        "sourceCommand": .string("voice-capture")
                    ]
                )
            ],
            riskLevel: .write,
            requiresApproval: true
        )

        return PlanningResponse(
            providerID: providerID,
            rawContent: "",
            actionPlan: plan,
            validationResult: ActionPlanValidator().validate(plan)
        )
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
