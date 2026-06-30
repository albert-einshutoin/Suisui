import SoloPMCore
import SoloPMGoogleCalendarRuntime
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
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
    @StateObject private var menuBarQuickCaptureViewModel: ProjectBoardViewModel
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @AppStorage(SoloPMAppearancePreference.storageKey) private var appearancePreference: SoloPMAppearancePreference = .system
    @AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system

    @MainActor
    init() {
        _menuBarController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarSummaryController())
        _menuBarQuickCaptureViewModel = StateObject(wrappedValue: AppRuntimeFactory.makeProjectBoardViewModel())
        _settingsViewModel = StateObject(wrappedValue: AppRuntimeFactory.makeAppSettingsViewModel())
#if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        SoloPMProjectBoardWindowFallback.shared.showIfNeeded()
#endif
    }

    var body: some Scene {
        WindowGroup("SoloPM", id: "project-board") {
            ProjectBoardView(
                viewModel: AppRuntimeFactory.makeProjectBoardViewModel(),
                taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution },
                appSettings: { settingsViewModel.settings }
            )
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        Window("Voice Command", id: "voice-capture") {
            VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .defaultSize(width: 560, height: 420)

        MenuBarExtra("SoloPM", systemImage: "checklist") {
            MenuBarPanel(controller: menuBarController, quickCaptureViewModel: menuBarQuickCaptureViewModel)
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settingsViewModel: settingsViewModel,
                launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
                watcherDiagnosticsSnapshot: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot(),
                integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot(),
                externalMCPViewModel: AppRuntimeFactory.makeExternalMCPSettingsViewModel(),
                syncViewModel: AppRuntimeFactory.makeSyncSettingsViewModel(),
                googleCalendarStatusProvider: AppRuntimeFactory.makeGoogleCalendarRuntimeSyncStatus,
                googleCalendarOAuthConnector: AppRuntimeFactory.makeGoogleCalendarOAuthConnector(),
                appearancePreference: $appearancePreference,
                languagePreference: $languagePreference
            )
            .preferredColorScheme(effectiveAppearancePreference.colorScheme)
            .environment(\.locale, effectiveLanguagePreference.locale)
        }
    }

    private var effectiveAppearancePreference: SoloPMAppearancePreference {
        SoloPMAppearancePreference.environmentOverride ?? appearancePreference
    }

    private var effectiveLanguagePreference: AppLanguagePreference {
        AppLanguagePreference.environmentOverride ?? languagePreference
    }
}

#if canImport(AppKit)
@MainActor
private final class SoloPMProjectBoardWindowFallback {
    static let shared = SoloPMProjectBoardWindowFallback()

    private var window: NSWindow?

    var windowForDelegateRetention: NSWindow? {
        window
    }

    func showIfNeeded() {
        guard visibleProjectBoardWindows.isEmpty else {
            return
        }

        // Debug app bundles can reach launch verification before SwiftUI's WindowGroup creates a window; keep a direct fallback so launch smoke tests prove a real board is visible.
        let hostingController = NSHostingController(
            rootView: ProjectBoardView(
                viewModel: AppRuntimeFactory.makeProjectBoardViewModel(),
                taskAutomationSettings: AppRuntimeFactory.loadTaskAutoExecutionSettings,
                appSettings: AppRuntimeFactory.loadRuntimeAppSettings
            )
            .preferredColorScheme(Self.effectiveAppearancePreference.colorScheme)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SoloPM"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 120, y: 160, width: 1_180, height: 760), display: true)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var visibleProjectBoardWindows: [NSWindow] {
        NSApplication.shared.windows.filter { window in
            window.isVisible && !window.isMiniaturized && window.title == "SoloPM"
        }
    }

    private static var effectiveAppearancePreference: SoloPMAppearancePreference {
        SoloPMAppearancePreference.environmentOverride ?? persistedAppearancePreference
    }

    private static var persistedAppearancePreference: SoloPMAppearancePreference {
        guard let rawValue = UserDefaults.standard.string(forKey: SoloPMAppearancePreference.storageKey),
              let preference = SoloPMAppearancePreference(rawValue: rawValue) else {
            return .system
        }
        return preference
    }
}

@MainActor
private final class SoloPMAppDelegate: NSObject, NSApplicationDelegate {
#if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif
    private var projectBoardWindowRestoreAttempts = 0
    private var fallbackProjectBoardWindow: NSWindow?
    private var settingsEvidenceWindow: NSWindow?
    private var voiceCommandEvidenceWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        createFallbackProjectBoardWindow()
        openSettingsWindowForEvidenceIfRequested()
        openVoiceCommandWindowForEvidenceIfRequested()

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
                self.createFallbackProjectBoardWindow()
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

    private func createFallbackProjectBoardWindow() {
        guard visibleProjectBoardWindows.isEmpty else {
            return
        }

        SoloPMProjectBoardWindowFallback.shared.showIfNeeded()
        fallbackProjectBoardWindow = SoloPMProjectBoardWindowFallback.shared.windowForDelegateRetention
    }

    private func openSettingsWindowForEvidenceIfRequested() {
        guard ProcessInfo.processInfo.environment["SOLOPM_OPEN_SETTINGS_ON_LAUNCH"] == "1" else {
            return
        }
        let selectedTab = SettingsTab(
            rawValue: ProcessInfo.processInfo.environment["SOLOPM_SETTINGS_EVIDENCE_TAB"] ?? ""
        ) ?? .overview

        // The release evidence harness opens Settings directly so captures do not depend on keyboard focus, AppleScript toolbar access, or localized menu state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let hostingController = NSHostingController(
                rootView: SettingsView(
                    settingsViewModel: AppRuntimeFactory.makeAppSettingsViewModel(),
                    launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
                    watcherDiagnosticsSnapshot: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot(),
                    integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot(),
                    externalMCPViewModel: AppRuntimeFactory.makeExternalMCPSettingsViewModel(),
                    syncViewModel: AppRuntimeFactory.makeSyncSettingsViewModel(),
                    googleCalendarStatusProvider: AppRuntimeFactory.makeGoogleCalendarRuntimeSyncStatus,
                    googleCalendarOAuthConnector: AppRuntimeFactory.makeGoogleCalendarOAuthConnector(),
                    appearancePreference: .constant(SoloPMAppearancePreference.environmentOverride ?? .system),
                    languagePreference: .constant(AppLanguagePreference.environmentOverride ?? .system),
                    initialTab: selectedTab
                )
                .preferredColorScheme(SoloPMAppearancePreference.environmentOverride?.colorScheme)
                .environment(\.locale, (AppLanguagePreference.environmentOverride ?? .system).locale)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = selectedTab.rawValue
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.setFrame(NSRect(x: 120, y: 160, width: 680, height: 620), display: true)
            self.settingsEvidenceWindow = window
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func openVoiceCommandWindowForEvidenceIfRequested() {
        guard ProcessInfo.processInfo.environment["SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH"] == "1" else {
            return
        }

        // Runtime evidence opens Voice Command directly so AX tests do not rely
        // on menu focus, menu bar state, or localized window-opening commands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let hostingController = NSHostingController(
                rootView: VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())
                    .preferredColorScheme(SoloPMAppearancePreference.environmentOverride?.colorScheme)
                    .environment(\.locale, (AppLanguagePreference.environmentOverride ?? .system).locale)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Voice Command"
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.setFrame(NSRect(x: 160, y: 140, width: 760, height: 640), display: true)
            self.voiceCommandEvidenceWindow = window
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private var visibleProjectBoardWindows: [NSWindow] {
        NSApplication.shared.windows.filter { window in
            window.isVisible && !window.isMiniaturized && window.title == "SoloPM"
        }
    }
}
#endif

private struct MenuBarPanel: View {
    @Environment(\.openWindow) private var openWindow

    @ObservedObject var controller: MenuBarSummaryController
    @ObservedObject var quickCaptureViewModel: ProjectBoardViewModel
    @State private var quickCaptureTitle = ""

    private var viewModel: MenuBarSummaryViewModel {
        controller.viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SoloPM")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

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

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings")
            .accessibilityIdentifier("menu-bar-settings-link")

            Divider()

            quickCaptureSection

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
            quickCaptureViewModel.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloPMProjectBoardDidChange)) { _ in
            controller.refresh()
            quickCaptureViewModel.load()
        }
    }

    private var quickCaptureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Add")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Quick add to Inbox", text: $quickCaptureTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addQuickCapture)
                    .accessibilityIdentifier("menu-bar-quick-capture-title")
                    .accessibilityLabel("Quick add to Inbox")
                    .accessibilityHint("Creates a local Inbox task without opening the Project Board.")

                Button(action: addQuickCapture) {
                    Label("Add", systemImage: "plus")
                }
                .disabled(quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Add to Inbox")
                .accessibilityIdentifier("menu-bar-quick-capture-button")
                .accessibilityHint("Adds the typed item to the local Inbox.")
            }

            if let errorMessage = quickCaptureViewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func addQuickCapture() {
        let title = quickCaptureTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        if quickCaptureViewModel.createInboxTask(title: title) != nil {
            quickCaptureTitle = ""
            controller.refresh()
        }
    }
}

private struct VoiceCaptureView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: VoiceCaptureViewModel
    @State private var clarificationAnswer = ""

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
                        clarificationAnswer = ""
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .disabled(viewModel.draft.text.isEmpty && viewModel.planningResponse == nil)
                    .accessibilityIdentifier("voice-command-clear")
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
                .accessibilityIdentifier("voice-command-input")

                if let routingResult = viewModel.routingResult {
                    VoiceIntentPreview(result: routingResult)
                }

                if let question = viewModel.clarificationQuestion {
                    ClarificationPanel(
                        question: question,
                        turns: viewModel.clarificationSession?.turns ?? [],
                        answerText: $clarificationAnswer,
                        onSubmit: { answer in
                            Task {
                                await viewModel.submitClarificationAnswer(answer)
                                clarificationAnswer = ""
                            }
                        },
                        onCancel: {
                            viewModel.cancelClarification()
                            clarificationAnswer = ""
                        }
                    )
                }

                if let request = viewModel.dailyPlanningReviewRequest {
                    VoiceDailyPlanningReviewRequestPanel(request: request) {
                        postDailyPlanningReviewRequest(request)
                    }
                }

                if let request = viewModel.inboxTriageRequest {
                    VoiceInboxTriageRequestPanel(request: request) {
                        postInboxTriageRequest(request)
                    }
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
                            Task {
                                await viewModel.startRecording()
                            }
                        }
                    } label: {
                        Label(viewModel.isRecording ? "Stop" : "Record", systemImage: viewModel.isRecording ? "stop.circle" : "record.circle")
                    }
                    .disabled(viewModel.phase == .generatingPlan || viewModel.phase == .transcribing)
                    .accessibilityIdentifier("voice-command-record")

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
                    .accessibilityIdentifier("voice-command-generate-plan")
                }

                if let response = viewModel.planningResponse {
                    Divider()
                    if let item = viewModel.assistantQueueItem {
                        AssistantQueuePanel(
                            item: item,
                            onApprove: { viewModel.approveAssistantQueueItem() },
                            onDefer: { viewModel.deferAssistantQueueItem() },
                            onReject: { viewModel.rejectAssistantQueueItem() }
                        )
                    }

                    if let plan = response.actionPlan,
                       response.validationResult.isValid,
                       viewModel.assistantQueueItem?.state == .approved {
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
        .accessibilityIdentifier("voice-command-root")
        .onChange(of: viewModel.dailyPlanningReviewRequest) { _, request in
            guard let request else {
                return
            }
            postDailyPlanningReviewRequest(request)
        }
        .onChange(of: viewModel.inboxTriageRequest) { _, request in
            guard let request else {
                return
            }
            postInboxTriageRequest(request)
        }
    }

    private func recordingOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-recording-\(UUID().uuidString).m4a")
    }

    private func postDailyPlanningReviewRequest(_ request: VoiceDailyPlanningReviewRequest) {
        SoloPMVoiceDailyPlanningReviewBridge.storePendingSourceTranscript(request.sourceTranscript)
        openWindow(id: "project-board")
        NotificationCenter.default.post(
            name: .soloPMVoiceDailyPlanningReviewRequested,
            object: nil,
            userInfo: [SoloPMVoiceDailyPlanningReviewBridge.sourceTranscriptUserInfoKey: request.sourceTranscript]
        )
    }

    private func postInboxTriageRequest(_ request: VoiceInboxTriageRequest) {
        openWindow(id: "project-board")
        guard let bridgeRequest = SoloPMVoiceInboxTriageBridge.storePendingRequest(request) else {
            return
        }
        NotificationCenter.default.post(
            name: .soloPMVoiceInboxTriageRequested,
            object: nil,
            userInfo: [SoloPMVoiceInboxTriageBridge.requestUserInfoKey: bridgeRequest]
        )
    }
}

private struct VoiceDailyPlanningReviewRequestPanel: View {
    let request: VoiceDailyPlanningReviewRequest
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Daily Planning Review"), systemImage: "sun.max")
                .font(.subheadline)

            Text(localizedSettingsDisplay("Opening a local Today review. No provider, Calendar, Reminder, connector, or file write is run."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !request.sourceTranscript.isEmpty {
                Label(request.sourceTranscript, systemImage: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onOpen()
            } label: {
                Label(localizedSettingsDisplay("Open Today Review"), systemImage: "arrow.forward.circle")
            }
            .accessibilityIdentifier("voice-daily-planning-open-board")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-daily-planning-request")
    }
}

private struct VoiceInboxTriageRequestPanel: View {
    let request: VoiceInboxTriageRequest
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Inbox Voice Triage"), systemImage: "tray.and.arrow.down")
                .font(.subheadline)

            Text(localizedSettingsDisplay("Applying a local Inbox command. No provider, Calendar, Reminder, connector, or file write is run."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(localizedSettingsDisplay(request.command.action.accessibilityLabel), systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if !request.sourceTranscript.isEmpty {
                Label(request.sourceTranscript, systemImage: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onOpen()
            } label: {
                Label(localizedSettingsDisplay("Open Inbox"), systemImage: "arrow.forward.circle")
            }
            .accessibilityIdentifier("voice-inbox-triage-open-board")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-inbox-triage-request")
    }
}

private struct AssistantQueuePanel: View {
    let item: AssistantQueueItem
    let onApprove: () -> Void
    let onDefer: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label(localizedSettingsDisplay("Assistant Queue"), systemImage: "tray.full")
                        .font(.subheadline)
                    queueStateLabel
                    Spacer(minLength: 8)
                    riskLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(localizedSettingsDisplay("Assistant Queue"), systemImage: "tray.full")
                        .font(.subheadline)
                    HStack(spacing: 8) {
                        queueStateLabel
                        riskLabel
                    }
                }
            }

            Text(localizedSettingsDisplay(item.redactedSummary))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text(localizedSettingsDisplay(item.reviewReason))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let source = item.sourceTranscript, !source.isEmpty {
                Label(source, systemImage: "quote.bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !item.requiredCapabilities.isEmpty {
                Text(item.requiredCapabilities.map(capabilityLabel).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("voice-assistant-queue-capabilities")
            }

            if let blockingReason = item.blockingReason {
                Label(localizedSettingsDisplay(blockingReason), systemImage: "exclamationmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    onApprove()
                } label: {
                    Label(localizedSettingsDisplay("Approve"), systemImage: "checkmark.seal")
                }
                .disabled(item.state != .waitingReview)
                .accessibilityIdentifier("voice-assistant-queue-approve")

                Button {
                    onDefer()
                } label: {
                    Label(localizedSettingsDisplay("Defer"), systemImage: "clock")
                }
                .disabled(item.state == .blocked || item.state == .done || item.state == .rejected)
                .accessibilityIdentifier("voice-assistant-queue-defer")

                Button {
                    onReject()
                } label: {
                    Label(localizedSettingsDisplay("Reject"), systemImage: "xmark.circle")
                }
                .disabled(item.state == .done || item.state == .rejected)
                .accessibilityIdentifier("voice-assistant-queue-reject")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-assistant-queue-panel")
    }

    private var queueStateLabel: some View {
        Text(localizedSettingsDisplay(stateLabel))
            .font(.caption)
            .foregroundStyle(stateColor)
            .lineLimit(1)
            .accessibilityIdentifier("voice-assistant-queue-state")
    }

    private var riskLabel: some View {
        Text(String(format: localizedSettingsDisplay("Risk: %@"), item.riskLevel.rawValue))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("voice-assistant-queue-risk")
    }

    private var stateLabel: String {
        switch item.state {
        case .captured:
            "Captured"
        case .interpreted:
            "Interpreted"
        case .drafted:
            "Drafted"
        case .waitingReview:
            "Waiting review"
        case .approved:
            "Approved"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .failed:
            "Failed"
        case .rejected:
            "Rejected"
        case .deferred:
            "Deferred"
        }
    }

    private var stateColor: Color {
        switch item.state {
        case .blocked, .failed, .rejected:
            .red
        case .approved, .done:
            .green
        case .deferred:
            .orange
        case .captured, .interpreted, .drafted, .waitingReview, .running:
            .secondary
        }
    }

    private func capabilityLabel(_ capability: AssistantQueueRequiredCapability) -> String {
        switch capability {
        case .tool(let tool):
            return tool.rawValue
        case .appPermission(let permission):
            return permission.rawValue
        case .connectedMacRequired:
            return localizedSettingsDisplay("Connected Mac required")
        case .providerExecutionApproval:
            return localizedSettingsDisplay("Execution approval")
        case .externalMCP(let serverID, let toolName):
            return "\(serverID):\(toolName)"
        }
    }
}

private struct ClarificationPanel: View {
    let question: ClarificationQuestion
    let turns: [ClarificationTurn]
    @Binding var answerText: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localizedSettingsDisplay("Clarification"), systemImage: "questionmark.bubble")
                .font(.subheadline)

            Text(localizedSettingsDisplay(question.prompt))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if !turns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                        Text(String(format: localizedSettingsDisplay("Answered: %@"), turn.response))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(localizedSettingsDisplay("Clarification answer"), text: $answerText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("voice-command-clarification-answer")

                Button {
                    let trimmed = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        return
                    }
                    onSubmit(trimmed)
                } label: {
                    Label(localizedSettingsDisplay("Answer"), systemImage: "arrow.turn.down.left")
                }
                .disabled(answerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("voice-command-clarification-submit")

                Button {
                    onCancel()
                } label: {
                    Label(localizedSettingsDisplay("Cancel"), systemImage: "xmark.circle")
                }
                .accessibilityIdentifier("voice-command-clarification-cancel")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-command-clarification-panel")
    }
}

private struct StatusRow: View {
    let phase: VoiceCapturePhase

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(isError ? .red : .secondary)
            .accessibilityIdentifier("voice-command-status")
    }

    private var label: String {
        switch phase {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case .needsClarification:
            "Clarification needed"
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
        case .needsClarification:
            "questionmark.circle"
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

private struct VoiceIntentPreview: View {
    let result: VoiceCommandRoutingResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    intentLabel
                    confidenceLabel
                    Spacer(minLength: 8)
                    reviewLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    intentLabel
                    HStack(spacing: 8) {
                        confidenceLabel
                        reviewLabel
                    }
                }
            }

            Text(localizedSettingsDisplay(result.interpretationSummary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let reason = result.clarificationReason {
                Label(localizedSettingsDisplay(reason), systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-command-intent-preview")
    }

    private var intentLabel: some View {
        Label(localizedSettingsDisplay(result.intent.displayName), systemImage: iconName)
            .font(.subheadline)
            .lineLimit(1)
            .help(localizedSettingsDisplay(result.intent.displayName))
    }

    private var confidenceLabel: some View {
        Text("\(Int((result.confidence * 100).rounded()))%")
            .font(.caption)
            .foregroundStyle(result.needsClarification ? .orange : .secondary)
            .lineLimit(1)
            .accessibilityLabel(localizedSettingsDisplay("Voice command confidence"))
    }

    private var reviewLabel: some View {
        Text(localizedSettingsDisplay("Review-only"))
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var iconName: String {
        switch result.intent {
        case .taskCreate, .taskTriage:
            "checkmark.circle"
        case .dailyPlanningReview:
            "sun.max"
        case .schedulePlan:
            "calendar"
        case .documentBrief:
            "doc.text"
        case .developmentPRWorkflow:
            "terminal"
        case .notificationDraft:
            "bell"
        case .statusAsk:
            "chart.bar"
        case .clarify:
            "questionmark.circle"
        }
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
            if let message = viewModel.executionReceiptErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let receipt = viewModel.lastExecutionReceipt {
                ExecutionReceiptSummaryView(receipt: receipt)
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
        .accessibilityIdentifier("voice-action-review-panel")
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button {
            viewModel.approveOrReportError()
        } label: {
            Label("Approve", systemImage: "checkmark.seal")
        }
        .disabled(!viewModel.canApprove)
        .accessibilityIdentifier("voice-action-review-approve")

        Button {
            if viewModel.executeOrReportError(), viewModel.session.executionStatus == .completed {
                onExecutionFinished()
            }
        } label: {
            Label("Execute", systemImage: "play.circle")
        }
        .buttonStyle(.borderedProminent)
        .disabled(!viewModel.canExecute)
        .accessibilityIdentifier("voice-action-review-execute")

        Button {
            viewModel.cancel()
        } label: {
            Label("Cancel", systemImage: "xmark.circle")
        }
        .disabled(viewModel.session.executionStatus == .completed || viewModel.session.executionStatus == .canceled)
        .accessibilityIdentifier("voice-action-review-cancel")
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

private struct ExecutionReceiptSummaryView: View {
    let receipt: ExecutionReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label(localizedSettingsDisplay("Execution receipt"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                    statusLabel
                    Spacer(minLength: 8)
                    usageLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    Label(localizedSettingsDisplay("Execution receipt"), systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                    HStack(spacing: 8) {
                        statusLabel
                        usageLabel
                    }
                }
            }

            Text(receipt.outputSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("voice-execution-receipt-output")

            if !receipt.actions.isEmpty {
                Text(String(format: localizedSettingsDisplay("%d actions recorded"), receipt.actions.count))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("voice-execution-receipt")
        .accessibilityLabel(localizedSettingsDisplay("Execution receipt"))
        .accessibilityValue(accessibilityValue)
    }

    private var statusLabel: some View {
        Text(localizedSettingsDisplay(statusText))
            .font(.caption2)
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .accessibilityIdentifier("voice-execution-receipt-status")
    }

    private var usageLabel: some View {
        Text(localizedSettingsDisplay(usageText))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityIdentifier("voice-execution-receipt-cost")
    }

    private var statusText: String {
        switch receipt.status {
        case .notStarted:
            "Not started"
        case .running:
            "Running"
        case .succeeded:
            "Succeeded"
        case .failed:
            "Failed"
        case .skipped:
            "Skipped"
        case .canceled:
            "Canceled"
        }
    }

    private var statusColor: Color {
        switch receipt.status {
        case .succeeded:
            .green
        case .failed:
            .red
        case .canceled, .skipped:
            .orange
        case .notStarted, .running:
            .secondary
        }
    }

    private var usageText: String {
        switch receipt.usage.state {
        case .measured:
            if let totalTokens = receipt.usage.totalTokens {
                return String(format: localizedSettingsDisplay("%d tokens"), totalTokens)
            }
            return "Measured cost"
        case .estimated:
            if let totalTokens = receipt.usage.totalTokens {
                return String(format: localizedSettingsDisplay("%d tokens estimated"), totalTokens)
            }
            return "Estimated cost"
        case .unknown:
            return "Cost unknown"
        case .unavailable:
            return "Cost unavailable"
        }
    }

    private var accessibilityValue: String {
        "\(localizedSettingsDisplay(statusText)). \(receipt.outputSummary)"
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
            Text(localizedSettingsDisplay(approvalLabel))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .help(localizedSettingsDisplay(approvalLabel))
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
                Label(localizedSettingsDisplay(failureRecoveryLabel(failureRecovery)), systemImage: failureRecovery == .retryable ? "arrow.clockwise" : "lock")
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
        Text(localizedSettingsDisplay(statusLabel))
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

private enum SettingsTab: String {
    case overview = "Overview"
    case appearance = "Appearance"
    case ai = "AI"
    case mcp = "MCP"
    case sync = "Sync"
    case privacy = "Privacy"
}

private extension VoiceModelID {
    var voiceModelSystemImage: String {
        switch self {
        case .whisperCppTinyMultilingual:
            "waveform"
        case .kokoro82M:
            "speaker.wave.2"
        case .custom:
            "shippingbox"
        }
    }
}

private struct SettingsView: View {
    let watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot
    let integrationPermissionSnapshot: PermissionSnapshot
    let googleCalendarStatusProvider: () -> GoogleCalendarRuntimeSyncStatus
    let googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @StateObject private var launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    @StateObject private var externalMCPViewModel: ExternalMCPSettingsViewModel
    @StateObject private var syncViewModel: SyncSettingsViewModel
    @Binding private var appearancePreference: SoloPMAppearancePreference
    @Binding private var languagePreference: AppLanguagePreference
    @State private var isConfirmingMCPRegistrationDeletion = false
    @State private var isChoosingDataLocation = false
    @State private var selectedTab: SettingsTab
    @State private var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus?
    @State private var googleCalendarSetupMessage: String?
    @State private var isGoogleCalendarOAuthAuthorizationInProgress = false

    init(
        settingsViewModel: AppSettingsViewModel,
        launchAtLoginViewModel: LaunchAtLoginSettingsViewModel,
        watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot,
        integrationPermissionSnapshot: PermissionSnapshot,
        externalMCPViewModel: ExternalMCPSettingsViewModel,
        syncViewModel: SyncSettingsViewModel,
        googleCalendarStatusProvider: @escaping () -> GoogleCalendarRuntimeSyncStatus,
        googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?,
        appearancePreference: Binding<SoloPMAppearancePreference>,
        languagePreference: Binding<AppLanguagePreference>,
        initialTab: SettingsTab = .overview
    ) {
        self.watcherDiagnosticsSnapshot = watcherDiagnosticsSnapshot
        self.integrationPermissionSnapshot = integrationPermissionSnapshot
        self.googleCalendarStatusProvider = googleCalendarStatusProvider
        self.googleCalendarOAuthConnector = googleCalendarOAuthConnector
        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _launchAtLoginViewModel = StateObject(wrappedValue: launchAtLoginViewModel)
        _externalMCPViewModel = StateObject(wrappedValue: externalMCPViewModel)
        _syncViewModel = StateObject(wrappedValue: syncViewModel)
        _appearancePreference = appearancePreference
        _languagePreference = languagePreference
        _selectedTab = State(initialValue: initialTab)
        _googleCalendarSyncStatus = State(initialValue: nil)
        _googleCalendarSetupMessage = State(initialValue: nil)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            overviewSettingsTab
                .tabItem { Label("Overview", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                .tag(SettingsTab.overview)

            appearanceSettingsTab
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(SettingsTab.appearance)

            aiSettingsTab
                .tabItem { Label("AI", systemImage: "brain.head.profile") }
                .tag(SettingsTab.ai)

            mcpSettingsTab
                .tabItem { Label("MCP", systemImage: "externaldrive.connected.to.line.below") }
                .tag(SettingsTab.mcp)

            syncSettingsTab
                .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .tag(SettingsTab.sync)

            privacySettingsTab
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)
        }
        .frame(width: 680, height: 620)
        .scenePadding()
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

    private var overviewSettingsTab: some View {
        Form {
            Section("Status Overview") {
                SettingsStatusOverview(
                    aiProviderLabel: settingsViewModel.settings.aiProvider.displayName,
                    aiStatusLabel: activeAIProviderStatusLabel,
                    aiTone: activeAIProviderTone,
                    sttStatusLabel: settingsViewModel.settings.sttProvider.displayName,
                    sttDetailLabel: sttOverviewDetailLabel,
                    sttTone: sttOverviewTone,
                    ttsStatusLabel: settingsViewModel.settings.ttsProvider.displayName,
                    ttsDetailLabel: ttsOverviewDetailLabel,
                    ttsTone: ttsOverviewTone,
                    calendarStatusLabel: calendarOverviewStatusLabel,
                    calendarDetailLabel: calendarOverviewDetailLabel,
                    calendarTone: integrationTone(for: integrationPermissionSnapshot.status(for: .calendar)),
                    reminderStatusLabel: reminderOverviewStatusLabel,
                    reminderDetailLabel: reminderOverviewDetailLabel,
                    reminderTone: integrationTone(for: integrationPermissionSnapshot.status(for: .reminders)),
                    mcpStatusLabel: externalMCPViewModel.connectionCheckResultLabel,
                    mcpDetailLabel: externalMCPViewModel.display.statusLabel,
                    mcpTone: mcpOverviewTone,
                    syncStatusLabel: syncViewModel.statusLabel,
                    syncDetailLabel: localizedDisplay("Plan: %@", syncViewModel.planLabel),
                    syncTone: syncOverviewTone,
                    privacyStatusLabel: privacyOverviewStatusLabel,
                    privacyDetailLabel: localizedDisplay("Login Item: %@", localizedSettingsDisplay(launchAtLoginViewModel.statusLabel)),
                    privacyTone: privacyOverviewTone,
                    dataLocationStatusLabel: dataLocationOverviewStatusLabel,
                    dataLocationDetailLabel: dataLocationOverviewDetailLabel,
                    dataLocationTone: dataLocationOverviewTone
                )
            }

            Section("Pro Value") {
                ProValueOverviewRow(
                    syncStatusLabel: syncViewModel.statusLabel,
                    syncValueLabel: syncPaidValueLabel,
                    syncBoundaryLabel: syncSafetyBoundaryLabel,
                    syncTone: syncOverviewTone,
                    mcpStatusLabel: mcpExecutionStatusLabel,
                    mcpValueLabel: mcpExecutionValueLabel,
                    mcpBoundaryLabel: mcpExecutionSafetyBoundaryLabel,
                    mcpTone: mcpExecutionTone
                )
            }

        }
        .formStyle(.grouped)
    }

    private var appearanceSettingsTab: some View {
        Form {
            SettingsAppearanceSection(appearancePreference: $appearancePreference, languagePreference: $languagePreference)
        }
        .formStyle(.grouped)
    }

    private var aiSettingsTab: some View {
        Form {
            Section("AI") {
                Picker(
                    "Provider",
                    selection: Binding(
                        get: { settingsViewModel.settings.aiProvider },
                        set: { settingsViewModel.selectAIProviderAndSave($0) }
                    )
                ) {
                    ForEach(settingsViewModel.selectableAIProviders, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                SelectedAIProviderStatusRow(
                    providerName: settingsViewModel.settings.aiProvider.displayName,
                    statusLabel: activeAIProviderStatusLabel,
                    detailLabel: providerReadinessDetailLabel,
                    nextActionLabel: activeAIProviderNextActionLabel,
                    tone: activeAIProviderTone
                )
                AIProviderReadinessSummaryRow(rows: settingsViewModel.providerReadinessRows)
                selectedProviderConfigurationFields
            }

            Section("Task Automation") {
                Toggle(
                    isOn: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.isEnabled },
                        set: { settingsViewModel.setTaskAutoExecutionEnabled($0) }
                    )
                ) {
                    Label("Review task automation", systemImage: "sparkles")
                }
                .accessibilityIdentifier("settings-task-auto-execution-toggle")
                .accessibilityHint("Enables review-only LLM planning for due and high-priority tasks.")

                Picker(
                    "Frequency",
                    selection: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.cadence },
                        set: { settingsViewModel.setTaskAutoExecutionCadence($0) }
                    )
                ) {
                    ForEach(TaskAutoExecutionCadence.allCases, id: \.self) { cadence in
                        Text(cadence.label)
                            .tag(cadence)
                    }
                }
                .accessibilityIdentifier("settings-task-auto-execution-frequency")
                .accessibilityHint("Manual frequency only prepares reviews after a user action; scheduled reviews require hourly, daily, or weekly frequency.")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.maxTasksPerRun },
                        set: { settingsViewModel.setTaskAutoExecutionMaxTasksPerRun($0) }
                    ),
                    in: 1...10
                ) {
                    LabeledContent("Tasks per run", value: "\(settingsViewModel.settings.taskAutoExecution.maxTasksPerRun)")
                }
                .accessibilityIdentifier("settings-task-auto-execution-max-tasks")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.dailyLLMCallLimit },
                        set: { settingsViewModel.setTaskAutoExecutionDailyLLMCallLimit($0) }
                    ),
                    in: 1...48
                ) {
                    LabeledContent("Daily LLM limit", value: "\(settingsViewModel.settings.taskAutoExecution.dailyLLMCallLimit)")
                }
                .accessibilityIdentifier("settings-task-auto-execution-daily-limit")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.lookaheadHours },
                        set: { settingsViewModel.setTaskAutoExecutionLookaheadHours($0) }
                    ),
                    in: 1...(24 * 30),
                    step: 1
                ) {
                    LabeledContent("Due lookahead", value: "\(settingsViewModel.settings.taskAutoExecution.lookaheadHours)h")
                }
                .accessibilityIdentifier("settings-task-auto-execution-lookahead")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.urgentReviewCooldownMinutes },
                        set: { settingsViewModel.setTaskAutoExecutionUrgentReviewCooldownMinutes($0) }
                    ),
                    in: 5...(24 * 60),
                    step: 5
                ) {
                    LabeledContent("Urgent review cooldown", value: "\(settingsViewModel.settings.taskAutoExecution.urgentReviewCooldownMinutes)m")
                }
                .accessibilityIdentifier("settings-task-auto-execution-urgent-cooldown")
                .accessibilityHint("Controls how soon overdue or due-today tasks may trigger another review before the regular frequency elapses.")

                Label("Plans stay review-before-execution; deletion and completion are never run directly by automation.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-task-auto-execution-boundary")

                settingsSaveButton
            }

            Section("Voice") {
                Picker(
                    "Speech to Text",
                    selection: Binding(
                        get: { settingsViewModel.settings.sttProvider },
                        set: { settingsViewModel.setSTTProvider($0) }
                    )
                ) {
                    ForEach(settingsViewModel.selectableSTTProviders, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                TextField(
                    "whisper.cpp executable",
                    text: Binding(
                        get: { settingsViewModel.settings.whisperCppExecutablePath ?? "" },
                        set: { settingsViewModel.setWhisperCppExecutablePath($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings-whisper-cpp-executable-path")
                .accessibilityHint("Sets the absolute path to whisper-cli for offline speech to text.")
                LabeledContent("Shortcut", value: "Option + Space")
                Picker(
                    "Text to Speech",
                    selection: Binding(
                        get: { settingsViewModel.settings.ttsProvider },
                        set: { settingsViewModel.setTTSProvider($0) }
                    )
                ) {
                    ForEach(settingsViewModel.selectableTTSProviders, id: \.self) { provider in
                        Text(provider.displayName)
                            .tag(provider)
                    }
                }
                .accessibilityIdentifier("settings-tts-provider-picker")

                SelectedTTSProviderStatusRow(row: settingsViewModel.ttsProviderReadinessRow)

                TextField(
                    "Kokoro executable",
                    text: Binding(
                        get: { settingsViewModel.settings.kokoroExecutablePath ?? "" },
                        set: { settingsViewModel.setKokoroExecutablePath($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings-kokoro-executable-path")
                .accessibilityHint("Sets the absolute path to the local Kokoro TTS executable.")

                Picker(
                    "TTS Language",
                    selection: Binding(
                        get: { settingsViewModel.settings.ttsLanguageCode },
                        set: { settingsViewModel.setTTSLanguageCode($0) }
                    )
                ) {
                    Text("English").tag("en")
                    Text("Japanese").tag("ja")
                }
                .accessibilityIdentifier("settings-tts-language-picker")

                TextField(
                    "TTS voice",
                    text: Binding(
                        get: { settingsViewModel.settings.ttsVoiceID },
                        set: { settingsViewModel.setTTSVoiceID($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings-tts-voice-id")

                Button("Test Play") {
                    Task {
                        await settingsViewModel.testTTSPlayback(
                            using: AppRuntimeFactory.makeTextToSpeechPreviewer(settings: settingsViewModel.settings)
                        )
                    }
                }
                .disabled(!settingsViewModel.ttsProviderReadinessRow.isReady)
                .accessibilityIdentifier("settings-tts-test-play")
                .accessibilityHint("Tests the selected local TTS provider when the model and runtime are ready.")
            }

            Section("Voice Models") {
                ForEach(settingsViewModel.voiceModelReadinessRows) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Label(row.displayName, systemImage: row.modelID.voiceModelSystemImage)
                                .font(.headline)
                            Spacer()
                            Text(localizedSettingsDisplay(row.statusLabel))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(row.languageSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(row.sizeLabel) - \(row.detailLabel)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Button(localizedSettingsDisplay(row.actionLabel)) {
                            handleVoiceModelAction(row)
                        }
                        .disabled(row.action == .wait)
                        .accessibilityIdentifier("settings-voice-model-\(row.modelID.rawValue)")
                        .accessibilityHint("Manages the cached local voice model file.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var syncSettingsTab: some View {
        Form {
            Section("Sync") {
                LabeledContent("Plan", value: syncViewModel.planLabel)
                LocalizedValueLabeledContent("Status", value: syncViewModel.statusLabel)
                LocalizedValueLabeledContent("Last Attempt", value: syncViewModel.lastAttemptLabel)
                LocalizedValueLabeledContent("Data Included", value: syncViewModel.dataIncludedLabel)
                SyncValueStatusRow(
                    planLabel: syncViewModel.planLabel,
                    statusLabel: syncViewModel.statusLabel,
                    valueLabel: syncPaidValueLabel,
                    boundaryLabel: syncSafetyBoundaryLabel,
                    tone: syncOverviewTone
                )
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
                if let syncUnavailableLabel = syncViewModel.syncUnavailableLabel {
                    Label(localizedSettingsDisplay(syncUnavailableLabel), systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = syncViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("External Task Tools") {
                Text("Pro unlocks external sync; import/export JSON stays local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ExternalConnectorScopeRow(
                    name: "Google Calendar",
                    status: googleCalendarSettingsReadinessRow.statusLabel,
                    detail: googleCalendarSettingsReadinessRow.detailLabel,
                    nextAction: googleCalendarSettingsReadinessRow.nextActionLabel,
                    privacyBoundary: googleCalendarSettingsReadinessRow.privacyBoundaryLabel,
                    systemImage: "calendar.badge.plus",
                    tone: googleCalendarSettingsTone,
                    statusActionLabel: googleCalendarSettingsReadinessRow.statusCheckActionLabel,
                    onStatusAction: refreshGoogleCalendarSettingsStatus
                )
                Button(localizedSettingsDisplay(googleCalendarOAuthActionLabel)) {
                    startGoogleCalendarOAuthAuthorization()
                }
                .disabled(isGoogleCalendarOAuthAuthorizationInProgress || googleCalendarOAuthConnector == nil)
                .accessibilityIdentifier("settings-google-calendar-oauth-setup")
                .accessibilityHint("Opens Google Calendar OAuth authorization with PKCE. Tokens stay in Keychain.")
                if let googleCalendarSetupMessage {
                    Label(localizedSettingsDisplay(googleCalendarSetupMessage), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-google-calendar-oauth-setup-message")
                }
                ExternalConnectorScopeRow(
                    name: "Todoist",
                    status: "Connector planned",
                    detail: "Task import/export uses the external connector boundary and explicit approval.",
                    systemImage: "checklist",
                    tone: .neutral
                )
                ExternalConnectorScopeRow(
                    name: "Notion",
                    status: "Connector planned",
                    detail: "Database mappings stay explicit before tasks are exported.",
                    systemImage: "doc.richtext",
                    tone: .neutral
                )
                ExternalConnectorScopeRow(
                    name: "Linear",
                    status: "Connector planned",
                    detail: "Issue sync is scoped to the selected team.",
                    systemImage: "line.3.horizontal.decrease.circle",
                    tone: .neutral
                )
                ExternalConnectorScopeRow(
                    name: "GitHub Issues",
                    status: "Connector planned",
                    detail: "Issue sync is scoped to the selected repository.",
                    systemImage: "number",
                    tone: .neutral
                )
            }

        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var selectedProviderConfigurationFields: some View {
        switch settingsViewModel.settings.aiProvider {
        case .openaiResponses:
            openAIProviderSettingsFields
        case .geminiOpenAICompatible:
            unavailableProviderSettingsFields
        case .claudeMessages:
            claudeProviderSettingsFields
        case .geminiDirect:
            geminiProviderSettingsFields
        case .groqOpenAICompatible:
            groqProviderSettingsFields
        case .opencodeLocal:
            openCodeProviderSettingsFields
        case .openRouterCompatible:
            openRouterProviderSettingsFields
        case .ollamaCompatible:
            ollamaProviderSettingsFields
        }
    }

    private var unavailableProviderSettingsFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(
                "Provider",
                value: LLMProviderCatalog.entry(for: settingsViewModel.settings.aiProvider).displayName
            )
            Label(
                LLMProviderCatalog.entry(for: settingsViewModel.settings.aiProvider).unavailableReason
                    ?? LLMProviderCatalog.unavailableReason,
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("ai-provider-unavailable-fields")
    }

    @ViewBuilder
    private var openAIProviderSettingsFields: some View {
        LocalizedValueLabeledContent("OpenAI API Key", value: settingsViewModel.openAIAPIKeyStatusLabel)
        LocalizedValueLabeledContent("OpenAI Provider Smoke", value: settingsViewModel.openAIProviderSmokeStatusLabel)
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
    }

    @ViewBuilder
    private var claudeProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Anthropic API Key", value: settingsViewModel.anthropicAPIKeyStatusLabel)
        SecureField(
            "Anthropic API Key",
            text: Binding(
                get: { settingsViewModel.anthropicAPIKeyInput },
                set: { settingsViewModel.updateAnthropicAPIKeyInput($0) }
            )
        )
        HStack {
            Button {
                settingsViewModel.saveAnthropicAPIKey()
            } label: {
                Label("Save Claude Key", systemImage: "key")
            }
            .disabled(settingsViewModel.anthropicAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                settingsViewModel.deleteAnthropicAPIKey()
            } label: {
                Label("Delete Claude Key", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var geminiProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Gemini API Key", value: settingsViewModel.geminiAPIKeyStatusLabel)
        LocalizedValueLabeledContent("Gemini Provider Smoke", value: settingsViewModel.geminiProviderSmokeStatusLabel)
        TextField(
            "Gemini Model ID",
            text: Binding(
                get: {
                    settingsViewModel.settings.geminiModelID
                        ?? LLMProviderCatalog.entry(for: .geminiDirect).defaultModelID
                },
                set: { settingsViewModel.setGeminiModelID($0) }
            )
        )
        SecureField(
            "Gemini API Key",
            text: Binding(
                get: { settingsViewModel.geminiAPIKeyInput },
                set: { settingsViewModel.updateGeminiAPIKeyInput($0) }
            )
        )
        HStack {
            Button {
                settingsViewModel.saveGeminiAPIKey()
            } label: {
                Label("Save Gemini Key", systemImage: "key")
            }
            .disabled(settingsViewModel.geminiAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                settingsViewModel.deleteGeminiAPIKey()
            } label: {
                Label("Delete Gemini Key", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var groqProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Groq API Key", value: settingsViewModel.groqAPIKeyStatusLabel)
        LocalizedValueLabeledContent("Groq Provider Smoke", value: settingsViewModel.groqProviderSmokeStatusLabel)
        TextField(
            "Groq Base URL",
            text: Binding(
                get: {
                    settingsViewModel.settings.groqBaseURLString
                        ?? LLMProviderCatalog.entry(for: .groqOpenAICompatible).baseURL?.absoluteString
                        ?? "https://api.groq.com/openai/v1"
                },
                set: { settingsViewModel.setGroqBaseURLString($0) }
            )
        )
        SecureField(
            "Groq API Key",
            text: Binding(
                get: { settingsViewModel.groqAPIKeyInput },
                set: { settingsViewModel.updateGroqAPIKeyInput($0) }
            )
        )
        HStack {
            Button {
                settingsViewModel.saveGroqAPIKey()
            } label: {
                Label("Save Groq Key", systemImage: "key")
            }
            .disabled(settingsViewModel.groqAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button(role: .destructive) {
                settingsViewModel.deleteGroqAPIKey()
            } label: {
                Label("Delete Groq Key", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var openCodeProviderSettingsFields: some View {
        TextField(
            "OpenCode Executable",
            text: Binding(
                get: { settingsViewModel.settings.openCodeExecutablePath ?? "" },
                set: { settingsViewModel.setOpenCodeExecutablePath($0) }
            )
        )
        TextField(
            "OpenCode Workspace",
            text: Binding(
                get: { settingsViewModel.settings.openCodeWorkspacePath ?? "" },
                set: { settingsViewModel.setOpenCodeWorkspacePath($0) }
            )
        )
        TextField(
            "OpenCode Model ID",
            text: Binding(
                get: {
                    settingsViewModel.settings.openCodeModelID
                        ?? LLMProviderCatalog.entry(for: .opencodeLocal).defaultModelID
                },
                set: { settingsViewModel.setOpenCodeModelID($0) }
            )
        )
        Toggle(
            isOn: Binding(
                get: { settingsViewModel.settings.isOpenCodeLocalExecutionApproved },
                set: { settingsViewModel.setOpenCodeLocalExecutionApproved($0) }
            )
        ) {
            Label("Approve OpenCode Local Execution", systemImage: "terminal")
        }
    }

    @ViewBuilder
    private var openRouterProviderSettingsFields: some View {
        LocalizedValueLabeledContent("OpenRouter API Key", value: settingsViewModel.openRouterAPIKeyStatusLabel)
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

    @ViewBuilder
    private var ollamaProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Provider Status", value: "Local")
        LocalizedValueLabeledContent("API Key", value: "Not required")
    }

    private var privacySettingsTab: some View {
        Form {
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
                LocalizedValueLabeledContent("Login Item", value: launchAtLoginViewModel.statusLabel)
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
                LabeledContent("Data Location", value: dataLocationOverviewStatusLabel)
                Button {
                    isChoosingDataLocation = true
                } label: {
                    Label("Choose Data Location", systemImage: "folder")
                }
                settingsSaveButton
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
                LocalizedValueLabeledContent("Notifications", value: permissionLabel(watcherDiagnosticsSnapshot.notificationPermissionStatus))
                if let errorMessage = watcherDiagnosticsSnapshot.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isChoosingDataLocation,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    settingsViewModel.setDefaultWorkspacePath(url.path)
                }
            case .failure(let error):
                settingsViewModel.setDefaultWorkspacePath(settingsViewModel.settings.defaultWorkspacePath ?? "")
                settingsViewModel.setTransientErrorMessage(error.localizedDescription)
            }
        }
    }

    private var mcpSettingsTab: some View {
        Form {
            Section("External MCP") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Servers", systemImage: "externaldrive.connected.to.line.below")
                            .font(.headline)
                        Spacer()
                        Button {
                            externalMCPViewModel.createRegistration()
                        } label: {
                            Label("Add Server", systemImage: "plus")
                        }
                    }

                    ForEach(externalMCPViewModel.registrationRows) { row in
                        MCPServerSettingsRow(
                            row: row,
                            isCheckDisabled: externalMCPViewModel.isCheckingConnection,
                            onSelect: {
                                externalMCPViewModel.selectRegistration(id: row.id)
                            },
                            onCheck: {
                                Task {
                                    await externalMCPViewModel.checkConnection(id: row.id)
                                }
                            }
                        )
                    }
                }

                MCPPaidExecutionBoundaryRow(
                    planLabel: syncViewModel.planLabel,
                    statusLabel: mcpExecutionStatusLabel,
                    valueLabel: mcpExecutionValueLabel,
                    boundaryLabel: mcpExecutionSafetyBoundaryLabel,
                    tone: mcpExecutionTone
                )

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
                    LocalizedValueLabeledContent("MCP Keychain Secret", value: settingsViewModel.keychainSecretStatusLabel)
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
                LocalizedValueLabeledContent("Status", value: externalMCPViewModel.display.statusLabel)
                LabeledContent("Protocol Version", value: externalMCPViewModel.protocolVersionLabel)
                LocalizedValueLabeledContent("Check Result", value: externalMCPViewModel.connectionCheckResultLabel)
                LocalizedValueLabeledContent("Resources", value: "Not supported in this release")
                LocalizedValueLabeledContent("Prompts", value: "Not supported in this release")
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
                            Text(localizedSettingsDisplay(row.statusLabel))
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
    }

    private var settingsSaveButton: some View {
        Button {
            settingsViewModel.saveSettings()
        } label: {
            Label("Save Settings", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("settings-save-button")
        .accessibilityHint("Persists non-secret settings to local UserDefaults.")
    }

    private func handleVoiceModelAction(_ row: VoiceModelReadinessRow) {
        switch row.action {
        case .download, .retry:
            Task {
                await settingsViewModel.installVoiceModel(row.modelID)
            }
        case .removeFromCache:
            settingsViewModel.removeVoiceModelFromCache(row.modelID)
        case .wait:
            break
        }
    }

    private var activeAIProviderReadinessRow: AIProviderReadinessRow {
        settingsViewModel.providerReadinessRow(for: settingsViewModel.settings.aiProvider)
    }

    private var activeAIProviderStatusLabel: String {
        activeAIProviderReadinessRow.statusLabel
    }

    private var providerReadinessDetailLabel: String {
        activeAIProviderReadinessRow.detailLabel
    }

    private var activeAIProviderNextActionLabel: String {
        activeAIProviderReadinessRow.nextActionLabel
    }

    private var activeAIProviderTone: SettingsStatusTone {
        tone(for: activeAIProviderReadinessRow)
    }

    private var sttOverviewDetailLabel: String {
        settingsViewModel.settings.sttProvider.isReleaseReady ? "Ready for voice capture" : "Unsupported provider"
    }

    private var sttOverviewTone: SettingsStatusTone {
        settingsViewModel.settings.sttProvider.isReleaseReady ? .ready : .danger
    }

    private var ttsOverviewDetailLabel: String {
        settingsViewModel.ttsProviderReadinessRow.statusLabel
    }

    private var ttsOverviewTone: SettingsStatusTone {
        settingsViewModel.ttsProviderReadinessRow.isReady ? .ready : .warning
    }

    private var googleCalendarSettingsReadinessRow: GoogleCalendarSettingsReadinessRow {
        GoogleCalendarSettingsReadinessRow(status: googleCalendarSyncStatus)
    }

    private var googleCalendarSettingsTone: SettingsStatusTone {
        guard let googleCalendarSyncStatus else {
            return .neutral
        }
        switch googleCalendarSyncStatus.state {
        case .ready:
            return .ready
        case .failed, .invalidCalendarID:
            return .danger
        default:
            return .warning
        }
    }

    private var googleCalendarOAuthActionLabel: String {
        switch googleCalendarSyncStatus?.state {
        case .missingRequiredScope, .tokenExpiredWithoutRefresh:
            return "Reconnect with OAuth authorization"
        default:
            return "Connect with OAuth authorization"
        }
    }

    private func refreshGoogleCalendarSettingsStatus() {
        googleCalendarSetupMessage = nil
        googleCalendarSyncStatus = googleCalendarStatusProvider()
    }

    private func startGoogleCalendarOAuthAuthorization() {
        guard let googleCalendarOAuthConnector else {
            googleCalendarSetupMessage = "Google Calendar OAuth authorization is not available in this build."
            return
        }

        isGoogleCalendarOAuthAuthorizationInProgress = true
        googleCalendarSetupMessage = "OAuth authorization opens in the system browser with PKCE. Tokens stay in Keychain before calendar writes are enabled."
        googleCalendarOAuthConnector.startAuthorization { result in
            isGoogleCalendarOAuthAuthorizationInProgress = false
            switch result {
            case .success:
                googleCalendarSetupMessage = "Google Calendar OAuth authorization completed. Check Status to refresh readiness."
                googleCalendarSyncStatus = googleCalendarStatusProvider()
            case .failure(let error):
                googleCalendarSetupMessage = googleCalendarOAuthFailureMessage(from: error)
            }
        }
    }

    private func googleCalendarOAuthFailureMessage(from error: Error) -> String {
        if let authorizationError = error as? GoogleCalendarOAuthAuthorizationError {
            switch authorizationError {
            case .missingClientID:
                return "Google Calendar OAuth client ID is not configured. Set SOLOPM_GOOGLE_CALENDAR_OAUTH_CLIENT_ID or SoloPMGoogleCalendarOAuthClientID before connecting."
            case .callbackError:
                return "Google Calendar OAuth authorization failed."
            default:
                break
            }
        }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return description
        }
        return UserFacingErrorMessageSanitizer.message(
            from: error,
            fallback: "Google Calendar OAuth authorization failed."
        )
    }

    private var calendarOverviewStatusLabel: String {
        PermissionDisplayPolicy.integrationStatusLabel(for: integrationPermissionSnapshot.status(for: .calendar))
    }

    private var calendarOverviewDetailLabel: String {
        integrationOverviewDetailLabel(
            for: integrationPermissionSnapshot.status(for: .calendar),
            serviceName: "Calendar"
        )
    }

    private var reminderOverviewStatusLabel: String {
        PermissionDisplayPolicy.integrationStatusLabel(for: integrationPermissionSnapshot.status(for: .reminders))
    }

    private var reminderOverviewDetailLabel: String {
        integrationOverviewDetailLabel(
            for: integrationPermissionSnapshot.status(for: .reminders),
            serviceName: "Reminder"
        )
    }

    private var dataLocationOverviewStatusLabel: String {
        if settingsViewModel.settings.validate().contains(where: { $0.field == "defaultWorkspacePath" }) {
            return "Needs attention"
        }
        return settingsViewModel.settings.defaultWorkspacePath == nil ? "Default app container" : "Custom folder"
    }

    private var dataLocationOverviewDetailLabel: String {
        if settingsViewModel.settings.validate().contains(where: { $0.field == "defaultWorkspacePath" }) {
            return "Choose an absolute folder path."
        }
        guard let path = settingsViewModel.settings.defaultWorkspacePath else {
            return "No custom workspace path configured."
        }
        return localizedDisplay("Folder: %@", URL(fileURLWithPath: path).lastPathComponent)
    }

    private var dataLocationOverviewTone: SettingsStatusTone {
        if settingsViewModel.settings.validate().contains(where: { $0.field == "defaultWorkspacePath" }) {
            return .danger
        }
        return settingsViewModel.settings.defaultWorkspacePath == nil ? .neutral : .ready
    }

    private func tone(for row: AIProviderReadinessRow) -> SettingsStatusTone {
        switch row.statusLabel {
        case "Configured", "Approved", "Local":
            return .ready
        case "Invalid", "Unavailable":
            return .danger
        default:
            return .warning
        }
    }

    private var mcpOverviewTone: SettingsStatusTone {
        if externalMCPViewModel.connectionCheckResultLabel == "Connected" {
            return .ready
        }
        if externalMCPViewModel.connectionCheckResultLabel.hasPrefix("Failed") {
            return .danger
        }
        return externalMCPViewModel.display.isEnabled ? .warning : .neutral
    }

    private func integrationOverviewDetailLabel(for status: PermissionStatus, serviceName: String) -> String {
        switch status {
        case .notDetermined:
            return localizedDisplay("%@ permission has not been requested.", serviceName)
        case .granted:
            return localizedDisplay("%@ permission is available; writes still require approval.", serviceName)
        case .denied:
            return localizedDisplay("%@ permission is denied in System Settings.", serviceName)
        case .restricted:
            return localizedDisplay("%@ permission is restricted on this Mac.", serviceName)
        }
    }

    private func integrationTone(for status: PermissionStatus) -> SettingsStatusTone {
        switch status {
        case .notDetermined:
            return .warning
        case .granted:
            return .ready
        case .denied, .restricted:
            return .danger
        }
    }

    private var mcpExecutionStatusLabel: String {
        syncViewModel.status.plan.allows(.advancedMCPExecution) ? "Execution unlocked" : "Execution gated"
    }

    private var mcpExecutionValueLabel: String {
        let requiredPlan = FeatureGate.advancedMCPExecution.requiredPlan.displayName
        if syncViewModel.status.plan.allows(.advancedMCPExecution) {
            return localizedDisplay("Advanced MCP tools can execute on %@.", syncViewModel.planLabel)
        }
        return localizedDisplay("%@ is required before external MCP tools can execute.", requiredPlan)
    }

    private var mcpExecutionSafetyBoundaryLabel: String {
        "Register and Check stay available; tools/call still requires entitlement, tool policy, and approval."
    }

    private var mcpExecutionTone: SettingsStatusTone {
        syncViewModel.status.plan.allows(.advancedMCPExecution) ? .ready : .warning
    }

    private var syncOverviewTone: SettingsStatusTone {
        switch syncViewModel.statusLabel {
        case "Ready", "Syncing":
            .ready
        case "Failed":
            .danger
        default:
            .warning
        }
    }

    private var syncPaidValueLabel: String {
        switch syncViewModel.statusLabel {
        case "Ready", "Syncing":
            "Projects, Tasks, and Settings are ready to sync."
        case "Sync backend is not configured":
            "Pro plan detected. Sync backend is not configured."
        case "Upgrade required":
            "Pro is required for Projects, Tasks, and Settings sync."
        default:
            "Sync keeps the local data classes explicit before any upload."
        }
    }

    private var syncSafetyBoundaryLabel: String {
        switch syncViewModel.statusLabel {
        case "Ready", "Syncing":
            "Only selected SoloPM data classes are included."
        case "Sync backend is not configured":
            "No upload starts while the backend is missing."
        case "Upgrade required":
            "Free stays local. No data leaves this Mac."
        default:
            "Sync fails closed before external communication."
        }
    }

    private var privacyOverviewStatusLabel: String {
        settingsViewModel.settings.notificationsEnabled ? "Notifications on" : "Notifications off"
    }

    private var privacyOverviewTone: SettingsStatusTone {
        settingsViewModel.settings.notificationsEnabled ? .ready : .neutral
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

private struct MCPServerSettingsRow: View {
    let row: MCPServerRegistrationRow
    let isCheckDisabled: Bool
    let onSelect: () -> Void
    let onCheck: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.isSelected ? Color.accentColor : Color.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(row.commandLine.isEmpty ? "Command not set" : row.commandLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                MCPServerStatusBadge(label: row.statusLabel)
                                MCPServerConnectionBadge(label: row.connectionCheckResultLabel)
                                Text("Protocol: \(row.protocolVersionLabel)")
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                MCPServerStatusBadge(label: row.statusLabel)
                                MCPServerConnectionBadge(label: row.connectionCheckResultLabel)
                                Text("Protocol: \(row.protocolVersionLabel)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Select \(row.displayName)")
            .accessibilityLabel(row.isSelected ? "Selected MCP server \(row.displayName)" : "Select MCP server \(row.displayName)")

            if row.isCheckingConnection {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: onCheck) {
                Label("Check", systemImage: "network")
            }
            .controlSize(.small)
            .disabled(isCheckDisabled)
            .help("Check \(row.displayName) connection")
            .accessibilityLabel("Check \(row.displayName) connection")
        }
        .padding(.vertical, 4)
    }
}

private struct MCPServerStatusBadge: View {
    let label: String

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: label == "Enabled" ? "checkmark.circle" : "pause.circle")
            .foregroundStyle(label == "Enabled" ? .green : .secondary)
            .lineLimit(1)
    }
}

private struct MCPServerConnectionBadge: View {
    let label: String

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: systemImage)
            .foregroundStyle(foregroundStyle)
            .lineLimit(1)
    }

    private var systemImage: String {
        if label == "Connected" {
            return "network"
        }
        if label == "Checking" {
            return "clock"
        }
        if label.hasPrefix("Failed") {
            return "exclamationmark.triangle"
        }
        return "questionmark.circle"
    }

    private var foregroundStyle: Color {
        if label == "Connected" {
            return .green
        }
        if label.hasPrefix("Failed") {
            return .red
        }
        return .secondary
    }
}

private struct SelectedAIProviderStatusRow: View {
    let providerName: String
    let statusLabel: String
    let detailLabel: String
    let nextActionLabel: String
    let tone: SettingsStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(providerName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(providerName)

                Text(localizedSettingsDisplay(statusLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(detailLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(nextActionLabel), systemImage: "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ai-provider-readiness-row")
        .accessibilityLabel("AI provider readiness")
        .accessibilityValue("\(providerName), \(localizedSettingsDisplay(statusLabel)), \(localizedSettingsDisplay(nextActionLabel))")
    }
}

private struct SelectedTTSProviderStatusRow: View {
    let row: TTSProviderReadinessRow

    private var tone: SettingsStatusTone {
        row.isReady ? .ready : .warning
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.provider.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(localizedSettingsDisplay(row.statusLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(row.detailLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(row.nextActionLabel), systemImage: row.isReady ? "play.circle" : "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tts-provider-readiness-row")
        .accessibilityLabel("TTS provider readiness")
        .accessibilityValue("\(row.provider.displayName), \(localizedSettingsDisplay(row.statusLabel)), \(localizedSettingsDisplay(row.nextActionLabel))")
    }
}

private struct AIProviderReadinessSummaryRow: View {
    let rows: [AIProviderReadinessRow]

    private let columns = [
        GridItem(.adaptive(minimum: 190), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Provider Readiness", systemImage: "checklist.checked")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    AIProviderReadinessSummaryItem(row: row, tone: tone(for: row))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-provider-readiness-summary")
        .accessibilityLabel("AI Provider readiness summary")
    }

    private func tone(for row: AIProviderReadinessRow) -> SettingsStatusTone {
        switch row.statusLabel {
        case "Configured", "Approved", "Local":
            return .ready
        case "Invalid", "Unavailable":
            return .danger
        case "Not available":
            return .neutral
        default:
            return .warning
        }
    }
}

private struct AIProviderReadinessSummaryItem: View {
    let row: AIProviderReadinessRow
    let tone: SettingsStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: row.isSelected ? "largecircle.fill.circle" : tone.systemImage)
                .foregroundStyle(row.isSelected ? .accentColor : tone.color)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.provider.displayName)
                    .font(.caption.weight(row.isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(row.provider.displayName)

                Text(localizedSettingsDisplay(row.statusLabel))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(row.nextActionLabel))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ai-provider-readiness-summary-\(row.provider.rawValue)")
        .accessibilityLabel(row.provider.displayName)
        .accessibilityValue("\(localizedSettingsDisplay(row.statusLabel)), \(localizedSettingsDisplay(row.nextActionLabel))")
    }
}

private struct SyncValueStatusRow: View {
    let planLabel: String
    let statusLabel: String
    let valueLabel: String
    let boundaryLabel: String
    let tone: SettingsStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(tone.color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedDisplay("%@ Sync", planLabel))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(localizedSettingsDisplay(statusLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(localizedSettingsDisplay(valueLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(boundaryLabel), systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sync-paid-value-row")
        .accessibilityLabel("Sync paid value and safety boundary")
        .accessibilityValue("\(planLabel), \(localizedSettingsDisplay(statusLabel)), \(localizedSettingsDisplay(boundaryLabel))")
    }
}

private struct ExternalConnectorScopeRow: View {
    let name: String
    let status: String
    let detail: String
    let nextAction: String?
    let privacyBoundary: String?
    let systemImage: String
    let tone: SettingsStatusTone
    let statusActionLabel: String?
    let onStatusAction: (() -> Void)?

    init(
        name: String,
        status: String,
        detail: String,
        nextAction: String? = nil,
        privacyBoundary: String? = nil,
        systemImage: String,
        tone: SettingsStatusTone,
        statusActionLabel: String? = nil,
        onStatusAction: (() -> Void)? = nil
    ) {
        self.name = name
        self.status = status
        self.detail = detail
        self.nextAction = nextAction
        self.privacyBoundary = privacyBoundary
        self.systemImage = systemImage
        self.tone = tone
        self.statusActionLabel = statusActionLabel
        self.onStatusAction = onStatusAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(name)

                    Text(localizedSettingsDisplay(status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tone.color)
                        .lineLimit(1)
                }

                Text(localizedSettingsDisplay(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let nextAction {
                    Label(localizedSettingsDisplay(nextAction), systemImage: "arrow.right.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let privacyBoundary {
                    Label(localizedSettingsDisplay(privacyBoundary), systemImage: "key.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let statusActionLabel, let onStatusAction {
                Button(statusActionLabel) {
                    onStatusAction()
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: statusActionLabel == nil ? .combine : .contain)
        .accessibilityIdentifier(name == "Google Calendar" ? "settings-google-calendar-readiness-row" : "settings-external-connector-row")
        .accessibilityLabel("\(name) external connector")
        .accessibilityValue([
            localizedSettingsDisplay(status),
            localizedSettingsDisplay(detail),
            nextAction.map(localizedSettingsDisplay),
            privacyBoundary.map(localizedSettingsDisplay)
        ].compactMap { $0 }.joined(separator: ", "))
    }
}

private struct MCPPaidExecutionBoundaryRow: View {
    let planLabel: String
    let statusLabel: String
    let valueLabel: String
    let boundaryLabel: String
    let tone: SettingsStatusTone

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(tone.color)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(localizedDisplay("%@ MCP Execution", planLabel))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(localizedSettingsDisplay(statusLabel))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(valueLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(boundaryLabel), systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mcp-paid-execution-boundary-row")
        .accessibilityLabel("MCP paid execution boundary")
        .accessibilityValue("\(planLabel), \(localizedSettingsDisplay(statusLabel)), \(localizedSettingsDisplay(boundaryLabel))")
    }
}

private struct ProValueOverviewRow: View {
    let syncStatusLabel: String
    let syncValueLabel: String
    let syncBoundaryLabel: String
    let syncTone: SettingsStatusTone
    let mcpStatusLabel: String
    let mcpValueLabel: String
    let mcpBoundaryLabel: String
    let mcpTone: SettingsStatusTone

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pro unlocks sync and advanced MCP execution", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))

            Text("Local Project and Task CRUD stays free. Paid paths fail closed before upload or tools/call when entitlement, backend, policy, or approval is missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ProValueOverviewItem(
                        title: "Sync",
                        statusLabel: syncStatusLabel,
                        valueLabel: syncValueLabel,
                        boundaryLabel: syncBoundaryLabel,
                        tone: syncTone,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Divider()
                    ProValueOverviewItem(
                        title: "MCP Execution",
                        statusLabel: mcpStatusLabel,
                        valueLabel: mcpValueLabel,
                        boundaryLabel: mcpBoundaryLabel,
                        tone: mcpTone,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    ProValueOverviewItem(
                        title: "Sync",
                        statusLabel: syncStatusLabel,
                        valueLabel: syncValueLabel,
                        boundaryLabel: syncBoundaryLabel,
                        tone: syncTone,
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    Divider()
                    ProValueOverviewItem(
                        title: "MCP Execution",
                        statusLabel: mcpStatusLabel,
                        valueLabel: mcpValueLabel,
                        boundaryLabel: mcpBoundaryLabel,
                        tone: mcpTone,
                        systemImage: "point.3.connected.trianglepath.dotted"
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-pro-value-overview-row")
        .accessibilityLabel("Pro value overview")
        .accessibilityValue("\(syncStatusLabel). \(syncBoundaryLabel). \(mcpStatusLabel). \(mcpBoundaryLabel)")
    }
}

private struct ProValueOverviewItem: View {
    let title: String
    let statusLabel: String
    let valueLabel: String
    let boundaryLabel: String
    let tone: SettingsStatusTone
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(tone.color)
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Text(localizedSettingsDisplay(statusLabel))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .lineLimit(1)

                Text(localizedSettingsDisplay(valueLabel))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Label(localizedSettingsDisplay(boundaryLabel), systemImage: "lock.shield")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(localizedSettingsDisplay(statusLabel)), \(localizedSettingsDisplay(boundaryLabel))")
    }
}

private struct LocalizedValueLabeledContent: View {
    let title: LocalizedStringKey
    let value: String

    init(_ title: LocalizedStringKey, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        LabeledContent {
            Text(localizedSettingsDisplay(value))
        } label: {
            Text(title)
        }
    }
}

private enum SettingsStatusTone {
    case ready
    case warning
    case danger
    case neutral

    var color: Color {
        switch self {
        case .ready:
            .green
        case .warning:
            .orange
        case .danger:
            .red
        case .neutral:
            .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .ready:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .danger:
            "xmark.octagon.fill"
        case .neutral:
            "circle.dashed"
        }
    }
}

private struct SettingsStatusOverview: View {
    let aiProviderLabel: String
    let aiStatusLabel: String
    let aiTone: SettingsStatusTone
    let sttStatusLabel: String
    let sttDetailLabel: String
    let sttTone: SettingsStatusTone
    let ttsStatusLabel: String
    let ttsDetailLabel: String
    let ttsTone: SettingsStatusTone
    let calendarStatusLabel: String
    let calendarDetailLabel: String
    let calendarTone: SettingsStatusTone
    let reminderStatusLabel: String
    let reminderDetailLabel: String
    let reminderTone: SettingsStatusTone
    let mcpStatusLabel: String
    let mcpDetailLabel: String
    let mcpTone: SettingsStatusTone
    let syncStatusLabel: String
    let syncDetailLabel: String
    let syncTone: SettingsStatusTone
    let privacyStatusLabel: String
    let privacyDetailLabel: String
    let privacyTone: SettingsStatusTone
    let dataLocationStatusLabel: String
    let dataLocationDetailLabel: String
    let dataLocationTone: SettingsStatusTone

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            SettingsStatusTile(
                title: "AI Provider",
                value: aiProviderLabel,
                detail: aiStatusLabel,
                tone: aiTone,
                systemImage: "sparkles"
            )
            SettingsStatusTile(
                title: "STT",
                value: sttStatusLabel,
                detail: sttDetailLabel,
                tone: sttTone,
                systemImage: "waveform"
            )
            SettingsStatusTile(
                title: "TTS",
                value: ttsStatusLabel,
                detail: ttsDetailLabel,
                tone: ttsTone,
                systemImage: "speaker.slash"
            )
            SettingsStatusTile(
                title: "Calendar",
                value: calendarStatusLabel,
                detail: calendarDetailLabel,
                tone: calendarTone,
                systemImage: "calendar"
            )
            SettingsStatusTile(
                title: "Reminder",
                value: reminderStatusLabel,
                detail: reminderDetailLabel,
                tone: reminderTone,
                systemImage: "checklist"
            )
            SettingsStatusTile(
                title: "MCP",
                value: mcpStatusLabel,
                detail: mcpDetailLabel,
                tone: mcpTone,
                systemImage: "point.3.connected.trianglepath.dotted"
            )
            SettingsStatusTile(
                title: "Sync",
                value: syncStatusLabel,
                detail: syncDetailLabel,
                tone: syncTone,
                systemImage: "arrow.triangle.2.circlepath"
            )
            SettingsStatusTile(
                title: "Privacy",
                value: privacyStatusLabel,
                detail: privacyDetailLabel,
                tone: privacyTone,
                systemImage: "lock.shield"
            )
            SettingsStatusTile(
                title: "Data Location",
                value: dataLocationStatusLabel,
                detail: dataLocationDetailLabel,
                tone: dataLocationTone,
                systemImage: "folder"
            )
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("settings-status-overview")
    }
}

private struct SettingsStatusTile: View {
    let title: String
    let value: String
    let detail: String
    let tone: SettingsStatusTone
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tone.color)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(localizedSettingsDisplay(title))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Image(systemName: tone.systemImage)
                        .font(.caption)
                        .foregroundStyle(tone.color)
                        .accessibilityHidden(true)
                }

                Text(localizedSettingsDisplay(value))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(localizedSettingsDisplay(value))

                Text(localizedSettingsDisplay(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(localizedSettingsDisplay(detail))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tone.color.opacity(0.22))
        }
    }
}

private enum AppRuntimeFactory {
    private static let googleCalendarOAuthRedirectURI = URL(string: "solopm://oauth/google-calendar")!

    private static let sharedSecretStore: any SecretStore = {
        if ProcessInfo.processInfo.environment["SOLOPM_DISABLE_KEYCHAIN_SECRET_STORE"] == "1" {
            return LaunchVerificationSecretStore()
        }
        return KeychainSecretStore()
    }()

    @MainActor
    static func makeProjectBoardViewModel() -> ProjectBoardViewModel {
        do {
            let connection = try migratedConnection()
            let projectBoardStore = SQLiteProjectBoardStore(connection: connection)
            let externalTaskLinkStore = SQLiteExternalTaskLinkStore(connection: connection)
            let assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
            let executionReceiptStore = try? makeExecutionReceiptStore()
            let secretStore = makeSecretStore()
            let entitlementStore = KeychainEntitlementStore(secretStore: secretStore)
            let googleCalendarSync = try makeGoogleCalendarSyncController(
                connection: connection,
                entitlementStore: entitlementStore,
                store: projectBoardStore,
                linkStore: externalTaskLinkStore,
                secretStore: secretStore
            )
            return ProjectBoardViewModel(
                store: projectBoardStore,
                inboxCaptureStore: SQLiteInboxCaptureStore(connection: connection),
                assistantQueueStore: assistantQueueStore,
                assistantQueueExecutionCoordinator: makeAssistantQueueExecutionCoordinator(
                    connection: connection,
                    assistantQueueStore: assistantQueueStore,
                    executionReceiptStore: executionReceiptStore
                ),
                executionReceiptStore: executionReceiptStore,
                missedTaskReviewStateStore: SQLiteMissedTaskReviewStateStore(connection: connection),
                missedTaskFollowUpNotificationClient: UserNotificationsNotificationClient(),
                externalTaskLinkStore: externalTaskLinkStore,
                googleCalendarSync: googleCalendarSync,
                onChange: postProjectBoardDidChange
            )
        } catch {
            return ProjectBoardViewModel(store: UnavailableProjectBoardStore(error: error))
        }
    }

    private static func makeAssistantQueueExecutionCoordinator(
        connection: SQLiteConnection,
        assistantQueueStore: any AssistantQueueStore,
        executionReceiptStore: (any ExecutionReceiptStore)?
    ) -> AssistantQueueExecutionCoordinator? {
        guard let executionReceiptStore else {
            return nil
        }
        do {
            let auditLogger = try makeAuditLogger()
            let registry = try ToolRegistry.phase2MVP(
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
                artifactStore: SQLiteArtifactStore(connection: connection),
                auditLogger: auditLogger
            )
            return AssistantQueueExecutionCoordinator(
                queueStore: assistantQueueStore,
                executor: ActionExecutor(registry: registry, auditLogger: auditLogger),
                executionReceiptStore: executionReceiptStore
            )
        } catch {
            return nil
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

    static func loadTaskAutoExecutionSettings() -> TaskAutoExecutionSettings {
        // Fallback AppKit windows are created outside the SwiftUI App state,
        // so they read only the persisted non-secret automation settings here.
        // Provider secrets stay in Keychain and are never materialized for this UI decision.
        (try? UserDefaultsAppSettingsStore().load().normalizedForRuntime.taskAutoExecution) ?? .default
    }

    static func loadRuntimeAppSettings() -> AppSettings {
        // Fallback AppKit windows are created outside the SwiftUI App state, so
        // they reload persisted non-secret settings for notification and time
        // zone decisions without touching Keychain-backed provider secrets.
        (try? UserDefaultsAppSettingsStore().load().normalizedForRuntime) ?? .default
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

    static func makeGoogleCalendarRuntimeSyncStatus() -> GoogleCalendarRuntimeSyncStatus {
        do {
            let connection = try migratedConnection()
            let secretStore = makeSecretStore()
            return try GoogleCalendarAppRuntimeFactory.syncStatus(
                entitlementStore: KeychainEntitlementStore(secretStore: secretStore),
                secretStore: secretStore,
                connection: connection,
                calendarID: "primary",
                timeZoneIdentifier: TimeZone.current.identifier
            )
        } catch {
            return GoogleCalendarRuntimeSyncStatus(
                plan: .free,
                state: .failed(message: UserFacingErrorMessageSanitizer.message(
                    from: error,
                    fallback: "Google Calendar sync status is unavailable."
                ))
            )
        }
    }

    @MainActor
    static func makeGoogleCalendarOAuthConnector() -> (any GoogleCalendarOAuthConnecting)? {
#if canImport(AuthenticationServices) && canImport(AppKit)
        GoogleCalendarOAuthAuthenticationSessionController(
            callbackURLScheme: googleCalendarOAuthRedirectURI.scheme,
            serviceFactory: {
                try makeGoogleCalendarOAuthAuthorizationService()
            }
        )
#else
        nil
#endif
    }

    static func makeIntegrationPermissionSnapshot() -> PermissionSnapshot {
        EventKitPermissionSnapshotReader.snapshot(base: UserNotificationsPermissionSnapshotReader.snapshot())
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
        var auditLogger: (any AuditLogger)?
        var assistantQueueStore: (any AssistantQueueStore)?
        var runtimeValidationMessage: String?
        var initialFailureMessage: String?
        do {
            auditLogger = try makeAuditLogger()
            assistantQueueStore = try SQLiteAssistantQueueStore(connection: migratedConnection())
            runtimeValidationMessage = nil
            initialFailureMessage = settingsResult.errorMessage
        } catch {
            auditLogger = nil
            assistantQueueStore = nil
            runtimeValidationMessage = "Voice planning is unavailable because audit logging or local data stores could not be opened."
            initialFailureMessage = runtimeValidationMessage
        }
        return VoiceCaptureViewModel(
            phase: initialFailureMessage.map(VoiceCapturePhase.failed) ?? .idle,
            audioRecorder: AVFoundationAudioRecorder(),
            sttProvider: makeSpeechToTextProvider(settings: settingsResult.settings, secretStore: secretStore),
            llmProvider: makeLLMProvider(settings: settingsResult.settings, secretStore: secretStore),
            auditRecorder: auditLogger.map { PlanningAuditRecorder(logger: $0) },
            runtimeValidationMessage: runtimeValidationMessage,
            assistantQueueStore: assistantQueueStore
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
        switch settings.normalizedForRuntime.aiProvider {
        case .openaiResponses:
            let entry = LLMProviderCatalog.entry(for: .openaiResponses)
            let configuration = OpenAIResponsesConfiguration(model: entry.defaultModelID)
            return OpenAIResponsesProvider(secretStore: secretStore, configuration: configuration)
        case .geminiDirect:
            let entry = LLMProviderCatalog.entry(for: .geminiDirect)
            let configuration = GeminiDirectConfiguration(model: settings.normalizedForRuntime.geminiModelID ?? entry.defaultModelID)
            return GeminiDirectProvider(secretStore: secretStore, configuration: configuration)
        case .claudeMessages:
            let entry = LLMProviderCatalog.entry(for: .claudeMessages)
            let configuration = ClaudeMessagesConfiguration(model: entry.defaultModelID)
            return ClaudeMessagesProvider(secretStore: secretStore, configuration: configuration)
        case .openRouterCompatible:
            let entry = LLMProviderCatalog.entry(for: .openRouterCompatible)
            return ChatCompletionsCompatibleProvider(
                configuration: .openRouter(model: entry.defaultModelID),
                secretStore: secretStore
            )
        case .groqOpenAICompatible:
            let entry = LLMProviderCatalog.entry(for: .groqOpenAICompatible)
            let defaultBaseURL = entry.baseURL
                ?? ChatCompletionsCompatibleConfiguration.groq(model: entry.defaultModelID).baseURL
            return ChatCompletionsCompatibleProvider(
                configuration: .groq(
                    model: entry.defaultModelID,
                    baseURL: settings.normalizedForRuntime.resolvedGroqBaseURL(defaultBaseURL: defaultBaseURL)
                ),
                secretStore: secretStore
            )
        case .ollamaCompatible:
            let entry = LLMProviderCatalog.entry(for: .ollamaCompatible)
            return ChatCompletionsCompatibleProvider(
                configuration: .ollama(model: entry.defaultModelID),
                secretStore: secretStore
            )
        case .opencodeLocal:
            let entry = LLMProviderCatalog.entry(for: .opencodeLocal)
            let normalizedSettings = settings.normalizedForRuntime
            let configuration = OpenCodeLocalConfiguration(
                executablePath: normalizedSettings.openCodeExecutablePath,
                workspacePath: normalizedSettings.openCodeWorkspacePath,
                modelID: normalizedSettings.openCodeModelID ?? entry.defaultModelID,
                isExecutionApproved: normalizedSettings.isOpenCodeLocalExecutionApproved
            )
            return OpenCodeLocalProvider(configuration: configuration)
        case .geminiOpenAICompatible:
            let entry = LLMProviderCatalog.entry(for: .geminiOpenAICompatible)
            return UnavailableLLMProvider(
                providerID: .geminiOpenAICompatible,
                reason: entry.unavailableReason ?? LLMProviderCatalog.unavailableReason
            )
        }
    }

    private static func makeSpeechToTextProvider(
        settings: AppSettings,
        secretStore: any SecretStore
    ) -> any SpeechToTextProvider {
        let normalizedSettings = settings.normalizedForRuntime
        switch normalizedSettings.sttProvider {
        case .openAITranscribe, .appleSpeechAnalyzer, .localWhisperKit:
            return OpenAITranscribeProvider(secretStore: secretStore)
        case .localWhisperCpp:
            let configuration = WhisperCppLocalSTTConfiguration(
                executablePath: normalizedSettings.whisperCppExecutablePath ?? ""
            )
            return WhisperCppLocalSTTProvider(configuration: configuration)
        }
    }

    private static func makeTextToSpeechProvider(settings: AppSettings, outputURL: URL? = nil) -> any TextToSpeechProvider {
        let normalizedSettings = settings.normalizedForRuntime
        switch normalizedSettings.ttsProvider {
        case .systemSpeech, .localKokoro:
            let configuration = KokoroLocalTTSConfiguration(
                executablePath: normalizedSettings.kokoroExecutablePath ?? "",
                languageCode: normalizedSettings.ttsLanguageCode,
                voiceID: normalizedSettings.ttsVoiceID,
                outputURL: outputURL
            )
            return KokoroLocalTTSProvider(configuration: configuration)
        }
    }

    static func makeTextToSpeechPreviewer(settings: AppSettings) -> any TextToSpeechPreviewing {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("solopm-tts-preview-\(UUID().uuidString)", isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent("preview.wav", isDirectory: false)
        return TemporaryDirectoryTextToSpeechPreviewer(
            previewer: TextToSpeechPreviewService(
                provider: makeTextToSpeechProvider(settings: settings, outputURL: outputURL),
                audioPlayer: AVFoundationSpeechAudioPlayer()
            ),
            temporaryDirectory: temporaryDirectory
        )
    }

    @MainActor
    static func makeReviewSessionViewModel(plan: ActionPlan) -> ReviewSessionViewModel {
        let runtime: (
            logger: (any AuditLogger)?,
            receiptStore: (any ExecutionReceiptStore)?,
            registry: ToolRegistry,
            reviewRuntimeValidationMessage: String?
        ) = {
            do {
                let auditLogger = try makeAuditLogger()
                let connection = try migratedConnection()
                let registry = try ToolRegistry.phase2MVP(
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
                    artifactStore: SQLiteArtifactStore(connection: connection),
                    auditLogger: auditLogger
                )
                let receiptStore = try makeExecutionReceiptStore()
                return (auditLogger, receiptStore, registry, nil)
            } catch {
                let baseMessage = "Review execution tools are unavailable because audit logging or local data stores could not be opened."
                let unavailableRegistry = unavailableReviewRegistry(for: plan, message: baseMessage)
                return (nil, nil, unavailableRegistry.registry, unavailableRegistry.message)
            }
        }()

        return ReviewSessionViewModel(
            plan: plan,
            executor: ActionExecutor(registry: runtime.registry, auditLogger: runtime.logger),
            auditLogger: runtime.logger,
            executionReceiptStore: runtime.receiptStore,
            runtimeValidationMessage: runtime.reviewRuntimeValidationMessage
        )
    }

    private static func migratedConnection() throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: applicationDatabaseURL().path)
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.current)
        return connection
    }

    private static func makeSecretStore() -> any SecretStore {
        // Runtime surfaces can be recreated as windows open and close. Sharing the store keeps
        // successful Keychain reads in one process-local cache instead of prompting per surface.
        return sharedSecretStore
    }

    private static func makeGoogleCalendarSyncController(
        connection: SQLiteConnection,
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore
    ) throws -> GoogleCalendarRuntimeSyncController {
        try GoogleCalendarAppRuntimeFactory.makeSyncController(
            entitlementStore: entitlementStore,
            store: store,
            linkStore: linkStore,
            secretStore: secretStore,
            connection: connection,
            idempotencyNamespaceStore: SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: connection),
            calendarID: "primary",
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    private static func makeGoogleCalendarOAuthAuthorizationService() throws -> GoogleCalendarOAuthAuthorizationService {
        let connection = try migratedConnection()
        let secretStore = makeSecretStore()
        let credentialStore = GoogleCalendarOAuthCredentialStore(
            secretStore: secretStore,
            metadataStore: SQLiteGoogleCalendarOAuthCredentialMetadataStore(connection: connection)
        )
        return GoogleCalendarOAuthAuthorizationService(
            configuration: GoogleCalendarOAuthAuthorizationConfiguration(
                clientID: googleCalendarOAuthClientID() ?? "",
                redirectURI: googleCalendarOAuthRedirectURI.absoluteString
            ),
            httpClient: URLSessionSynchronousHTTPDataClient(),
            credentialStore: credentialStore
        )
    }

    private static func googleCalendarOAuthClientID() -> String? {
        for key in ["SOLOPM_GOOGLE_CALENDAR_OAUTH_CLIENT_ID", "GOOGLE_CALENDAR_OAUTH_CLIENT_ID"] {
            if let value = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
               value.isEmpty == false {
                return value
            }
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "SoloPMGoogleCalendarOAuthClientID") as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func makeAuditLogger() throws -> any AuditLogger {
        RedactingAuditLogger(base: try SQLiteAuditLogger(path: applicationDatabaseURL().path))
    }

    private static func makeExecutionReceiptStore() throws -> any ExecutionReceiptStore {
        try FileExecutionReceiptStore(
            directoryURL: applicationSupportDirectoryURL().appendingPathComponent("ExecutionReceipts", isDirectory: true)
        )
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

@MainActor
private protocol GoogleCalendarOAuthConnecting: AnyObject {
    func startAuthorization(
        completion: @escaping @MainActor (Result<GoogleCalendarOAuthCredentialMetadata, Error>) -> Void
    )
}

private enum GoogleCalendarOAuthConnectionError: LocalizedError, Equatable {
    case authorizationCancelled
    case callbackURLMissing
    case sessionDidNotStart

    var errorDescription: String? {
        switch self {
        case .authorizationCancelled:
            return "Google Calendar OAuth authorization was cancelled."
        case .callbackURLMissing:
            return "Google Calendar OAuth authorization did not return a callback URL."
        case .sessionDidNotStart:
            return "Google Calendar OAuth authorization could not start."
        }
    }
}

#if canImport(AuthenticationServices) && canImport(AppKit)
@MainActor
private final class GoogleCalendarOAuthAuthenticationSessionController: NSObject, GoogleCalendarOAuthConnecting, ASWebAuthenticationPresentationContextProviding {
    private let callbackURLScheme: String?
    private let serviceFactory: () throws -> GoogleCalendarOAuthAuthorizationService
    private var activeSession: ASWebAuthenticationSession?

    init(
        callbackURLScheme: String?,
        serviceFactory: @escaping () throws -> GoogleCalendarOAuthAuthorizationService
    ) {
        self.callbackURLScheme = callbackURLScheme
        self.serviceFactory = serviceFactory
    }

    func startAuthorization(
        completion: @escaping @MainActor (Result<GoogleCalendarOAuthCredentialMetadata, Error>) -> Void
    ) {
        do {
            let service = try serviceFactory()
            let request = try service.makeAuthorizationRequest()
            let session = ASWebAuthenticationSession(
                url: request.authorizationURL,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                if let error {
                    Task { @MainActor in
                        self?.activeSession = nil
                        if Self.isCancellation(error) {
                            completion(.failure(GoogleCalendarOAuthConnectionError.authorizationCancelled))
                        } else {
                            completion(.failure(error))
                        }
                    }
                    return
                }
                guard let callbackURL else {
                    Task { @MainActor in
                        self?.activeSession = nil
                        completion(.failure(GoogleCalendarOAuthConnectionError.callbackURLMissing))
                    }
                    return
                }

                // The runtime token exchange writes secrets through SecretStore immediately after
                // Google returns the callback, so Settings never receives raw token material.
                let result = Result {
                    try service.completeAuthorization(callbackURL: callbackURL, pendingRequest: request)
                }
                Task { @MainActor in
                    self?.activeSession = nil
                    completion(result)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            guard session.start() else {
                activeSession = nil
                completion(.failure(GoogleCalendarOAuthConnectionError.sessionDidNotStart))
                return
            }
        } catch {
            activeSession = nil
            completion(.failure(error))
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASWebAuthenticationSessionError.errorDomain
            && nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
    }
}
#endif

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

    func moveTasks(ids: [Int64], toProjectID projectID: Int64) throws -> [ProjectBoardTask] {
        throw error
    }

    func deleteTask(id: Int64) throws {
        throw error
    }

    func createProjectArtifact(projectID: Int64, expectedPath: String) throws -> ProjectBoardArtifact {
        throw error
    }

    func deleteProjectArtifact(id: Int64) throws {
        throw error
    }

    func createProjectMilestone(projectID: Int64, title: String, dueAt: String?) throws -> ProjectBoardMilestone {
        throw error
    }

    func updateProjectMilestone(id: Int64, title: String, dueAt: String?, isCompleted: Bool) throws -> ProjectBoardMilestone {
        throw error
    }

    func deleteProjectMilestone(id: Int64) throws {
        throw error
    }
}

private struct LaunchVerificationSecretStore: SecretStore {
    func save(_ value: String, for key: SecretKey) throws {
        throw SecretStoreError.unexpectedStatus(-25308)
    }

    func read(_ key: SecretKey) throws -> String? {
        return nil
    }

    func delete(_ key: SecretKey) throws {
        throw SecretStoreError.unexpectedStatus(-25308)
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
