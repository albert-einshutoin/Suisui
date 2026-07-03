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

#if DEBUG
private struct RuntimeDevelopmentPRSmokeBookmarkResolver: ProjectWorkspaceBookmarkResolving {
    static let flagName = "SOLOPM_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"
    static let markerPrefix = "solopm-runtime-development-pr-smoke:"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[flagName] == "1"
    }

    func resolve(bookmarkData: Data) throws -> ProjectWorkspaceBookmarkResolution {
        if Self.isEnabled,
           let marker = String(data: bookmarkData, encoding: .utf8),
           marker.hasPrefix(Self.markerPrefix) {
            let path = String(marker.dropFirst(Self.markerPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else {
                throw DevelopmentPRWorkflowError.projectWorkspaceMustBeAbsolute
            }

            // Runtime UI smoke is launched from a shell-owned workspace, which cannot mint a
            // user-approved app-owned security scoped bookmark. This DEBUG-only
            // marker resolver preserves the production invariant that a bookmark field must
            // exist, while keeping release builds on the real security-scoped resolver.
            return ProjectWorkspaceBookmarkResolution(
                url: URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL,
                isStale: false,
                didStartAccessing: true,
                stopAccessing: {}
            )
        }

        // When the smoke drives the real NSOpenPanel path, the app stores a real
        // bookmark. Falling through keeps that production path under the same
        // execution resolver instead of accepting only the encoded smoke prefix.
        return try SecurityScopedProjectWorkspaceBookmarkResolver().resolve(bookmarkData: bookmarkData)
    }
}
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
        // Creating a SwiftUI-hosted NSWindow here can enter AppKit layout before
        // the app run loop starts; the delegate owns fallback window creation.
#endif
    }

    var body: some Scene {
        WindowGroup("SoloPM", id: "project-board") {
            Group {
                if SoloPMLaunchRecoveryEnvironment.isEnabled {
                    ProjectBoardLaunchRecoveryView(
                        viewModel: AppRuntimeFactory.makeProjectBoardViewModel(),
                        appSettings: { settingsViewModel.settings }
                    )
                } else {
                    ProjectBoardView(
                        viewModel: AppRuntimeFactory.makeProjectBoardViewModel(),
                        taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution },
                        appSettings: { settingsViewModel.settings },
                        developmentAutomationReviewSession: AppRuntimeFactory.makeReviewSessionViewModel
                    )
                }
            }
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
                googleCalendarOAuthDisconnecter: AppRuntimeFactory.makeGoogleCalendarOAuthDisconnecter(),
                googleCalendarListProvider: AppRuntimeFactory.makeGoogleCalendarListProvider(),
                textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer,
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

private enum SoloPMLaunchRecoveryEnvironment {
    private static let flagName = "SOLOPM_LAUNCH_RECOVERY_MODE"

    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        // Isolated databases and keychain-free runs are also used by visual
        // evidence and CRUD smokes, so recovery is explicit. Only launch
        // verification paths opt in when they need the lightweight workflow
        // surface to avoid early AppKit toolbar layout before AX is ready.
        return environment[flagName] == "1"
    }
}

private enum SoloPMWindowlessFallbackEnvironment {
    private static let forceFallbackFlagName = "SOLOPM_FORCE_PROJECT_BOARD_FALLBACK"

    static var shouldForceProjectBoardFallback: Bool {
        ProcessInfo.processInfo.environment[forceFallbackFlagName] == "1"
    }

    static var shouldCreateDirectFallbackWindow: Bool {
        let environment = ProcessInfo.processInfo.environment
        // Direct binary launches with an isolated SQLite path do not always
        // get a SwiftUI WindowGroup quickly enough for AX/screenshot gates.
        // They still need the full board unless launch recovery explicitly opts in.
        return SoloPMLaunchRecoveryEnvironment.isEnabled
            || environment["SOLOPM_DATABASE_PATH"] != nil
            || shouldForceProjectBoardFallback
    }
}

private struct ProjectBoardFallbackRootView: View {
    @StateObject private var viewModel: ProjectBoardViewModel
    private let taskAutomationSettings: () -> TaskAutoExecutionSettings
    private let appSettings: () -> AppSettings

    init(
        viewModel: ProjectBoardViewModel,
        taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings = { .default },
        appSettings: @escaping () -> AppSettings = { .default }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.taskAutomationSettings = taskAutomationSettings
        self.appSettings = appSettings
    }

    var body: some View {
        Group {
            if SoloPMLaunchRecoveryEnvironment.isEnabled {
                ProjectBoardLaunchRecoveryView(
                    viewModel: viewModel,
                    appSettings: appSettings
                )
            } else {
                ProjectBoardView(
                    viewModel: viewModel,
                    taskAutomationSettings: taskAutomationSettings,
                    appSettings: appSettings,
                    developmentAutomationReviewSession: AppRuntimeFactory.makeReviewSessionViewModel
                )
            }
        }
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
        guard SoloPMWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else {
            return
        }

        // Debug app bundles can reach launch verification before SwiftUI's WindowGroup creates a window; keep a direct fallback so launch smoke tests prove a real board is visible.
        let hostingController = NSHostingController(
            rootView: ProjectBoardFallbackRootView(
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
            // AppKit restoration can mark a window visible before it is actually
            // on-screen; occlusion keeps screenshot/AX gates from trusting that state.
            window.isVisible
                && window.occlusionState.contains(.visible)
                && !window.isMiniaturized
                && window.title == "SoloPM"
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
        ensureProjectBoardWindowIsVisible()
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

            if SoloPMWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow {
                self.createFallbackProjectBoardWindow()
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
        guard SoloPMWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else {
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
                    googleCalendarOAuthDisconnecter: AppRuntimeFactory.makeGoogleCalendarOAuthDisconnecter(),
                    googleCalendarListProvider: AppRuntimeFactory.makeGoogleCalendarListProvider(),
                    textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer,
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
            // AppKit restoration can mark a window visible before it is actually
            // on-screen; occlusion keeps screenshot/AX gates from trusting that state.
            window.isVisible
                && window.occlusionState.contains(.visible)
                && !window.isMiniaturized
                && window.title == "SoloPM"
        }
    }
}
#endif

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
            let entitlementStore = makeEntitlementStore(secretStore: secretStore)
            let googleCalendarSync = makeSettingsBackedGoogleCalendarSyncController(
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
            let registry = try makeRuntimeToolRegistry(connection: connection, auditLogger: auditLogger)
            return AssistantQueueExecutionCoordinator(
                queueStore: assistantQueueStore,
                executor: ActionExecutor(registry: registry, auditLogger: auditLogger),
                executionReceiptStore: executionReceiptStore,
                managedAIUsageLedgerStore: SQLiteManagedAIUsageLedgerStore(connection: connection),
                managedAIBillingSettingsProvider: { loadRuntimeAppSettings().managedAIBilling }
            )
        } catch {
            return nil
        }
    }

    private static func makeRuntimeToolRegistry(
        connection: SQLiteConnection,
        auditLogger: any AuditLogger
    ) throws -> ToolRegistry {
        let projectStore = SQLiteProjectStore(connection: connection)
        let taskStore = SQLiteTaskStore(connection: connection)
        let artifactStore = SQLiteArtifactStore(connection: connection)
        let registry = try ToolRegistry.phase2MVP(
            projectStore: projectStore,
            taskStore: taskStore,
            knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection),
            notificationClient: UserNotificationsNotificationClient(),
            calendarClient: EventKitCalendarClient(),
            reminderClient: EventKitReminderClient(),
            fileAccessClient: LocalFileAccessClient(workspaceRoot: try workspaceRootURL()),
            mailDraftClient: try makeMailDraftClient(),
            notificationRequestStore: SQLiteNotificationRequestStore(connection: connection),
            calendarLinkStore: SQLiteCalendarLinkStore(connection: connection),
            reminderLinkStore: SQLiteReminderLinkStore(connection: connection),
            artifactStore: artifactStore,
            auditLogger: auditLogger
        )
        // Queue execution bridges project-panel approvals to local GitHub Flow
        // tools only after each external write has its own reviewed ActionPlan.
        // Remote/cloud requests still enter as blocked review items instead of
        // reaching this local project-directory registry directly.
        let developmentBookmarkResolver = makeDevelopmentWorkspaceBookmarkResolver()
        try registry.register(AuditedTool(
            base: DevelopmentPRWorkflowTool(
                projectStore: projectStore,
                taskStore: taskStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryListFiles,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryReadFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryCreateFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentRepositoryFileTool(
                name: .developmentRepositoryUpdateFile,
                projectStore: projectStore,
                artifactStore: artifactStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentVerificationCommandTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentCommitWorkflowTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver,
                requireBookmark: true
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPushWorkflowTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPullRequestCreationTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPullRequestReviewGateTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        try registry.register(AuditedTool(
            base: DevelopmentPullRequestMergeTool(
                projectStore: projectStore,
                bookmarkResolver: developmentBookmarkResolver
            ),
            logger: auditLogger
        ))
        for requiredTool in [
            ActionTool.developmentPreparePullRequestWorkflow,
            .developmentRepositoryListFiles,
            .developmentRepositoryReadFile,
            .developmentRepositoryCreateFile,
            .developmentRepositoryUpdateFile,
            .developmentRunVerification,
            .developmentCommitChanges,
            .developmentPushBranch,
            .developmentCreatePullRequest,
            .developmentReviewPullRequestGate,
            .developmentMergePullRequest
        ] {
            guard registry.contains(requiredTool) else {
                throw ToolExecutionError.unknownTool(requiredTool)
            }
        }
        return registry
    }

    private static func makeDevelopmentWorkspaceBookmarkResolver() -> any ProjectWorkspaceBookmarkResolving {
#if DEBUG
        if RuntimeDevelopmentPRSmokeBookmarkResolver.isEnabled {
            return RuntimeDevelopmentPRSmokeBookmarkResolver()
        }
#endif
        return SecurityScopedProjectWorkspaceBookmarkResolver()
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
        let secretStore = makeSecretStore()
        return SyncSettingsViewModel(
            service: SyncService(
                entitlementStore: makeEntitlementStore(secretStore: secretStore),
                configuration: .notConfigured,
                networkClient: UnavailableSyncNetworkClient()
            )
        )
    }

    static func makeGoogleCalendarRuntimeSyncStatus() -> GoogleCalendarRuntimeSyncStatus {
        do {
            let connection = try migratedConnection()
            let secretStore = makeSecretStore()
            let runtimeSettings = loadRuntimeAppSettings()
            return try GoogleCalendarAppRuntimeFactory.syncStatus(
                entitlementStore: makeEntitlementStore(secretStore: secretStore),
                secretStore: secretStore,
                connection: connection,
                calendarID: runtimeSettings.googleCalendarID,
                timeZoneIdentifier: runtimeSettings.timeZoneIdentifier,
                oauthClientID: googleCalendarOAuthClientID()
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

    @MainActor
    static func makeGoogleCalendarOAuthDisconnecter() -> (any GoogleCalendarOAuthDisconnecting)? {
        GoogleCalendarOAuthCredentialDisconnectController {
            try GoogleCalendarAppRuntimeFactory.disconnectOAuthCredential(
                secretStore: makeSecretStore(),
                connection: migratedConnection()
            )
        }
    }

    static func makeGoogleCalendarListProvider() -> (any GoogleCalendarListProviding)? {
        do {
            let secretStore = makeSecretStore()
            let client = try GoogleCalendarAppRuntimeFactory.makeCalendarListClient(
                secretStore: secretStore,
                connection: migratedConnection(),
                oauthClientID: googleCalendarOAuthClientID()
            )
            return GoogleCalendarRuntimeCalendarListProvider(client: client)
        } catch {
            return nil
        }
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
        let audioRecorder = AVFoundationAudioRecorder()
        let sttProvider = makeSpeechToTextProvider(settings: settingsResult.settings, secretStore: secretStore)
        let llmProvider = makeLLMProvider(settings: settingsResult.settings, secretStore: secretStore)
        let managedCostRateCardResolver = ManagedAICostRateCardResolver()
        var auditLogger: (any AuditLogger)?
        var assistantQueueStore: (any AssistantQueueStore)?
        var inboxCaptureService: InboxVoiceCaptureService?
        var developmentProjectProvider: () -> ProjectRecord? = { nil }
        var runtimeValidationMessage: String?
        var initialFailureMessage: String?
        do {
            auditLogger = try makeAuditLogger()
            let connection = try migratedConnection()
            assistantQueueStore = SQLiteAssistantQueueStore(connection: connection)
            let projectStore = SQLiteProjectStore(connection: connection)
            let projectBoardStore = SQLiteProjectBoardStore(connection: connection)
            let inboxCaptureStore = SQLiteInboxCaptureStore(connection: connection)
            inboxCaptureService = InboxVoiceCaptureService(
                audioRecorder: audioRecorder,
                sttProvider: sttProvider,
                projectBoardStore: projectBoardStore,
                inboxCaptureStore: inboxCaptureStore
            )
            developmentProjectProvider = {
                approvedDevelopmentProject(from: projectStore)
            }
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
            audioRecorder: audioRecorder,
            sttProvider: sttProvider,
            llmProvider: llmProvider,
            auditRecorder: auditLogger.map { PlanningAuditRecorder(logger: $0) },
            runtimeValidationMessage: runtimeValidationMessage,
            assistantQueueStore: assistantQueueStore,
            inboxCaptureSaver: inboxCaptureService,
            developmentProjectProvider: developmentProjectProvider,
            appSettingsProvider: { loadRuntimeSettings().settings },
            managedCostRateCardProvider: { managedCostRateCardResolver.rateCard(for: $0) }
        )
    }

    private static func approvedDevelopmentProject(from projectStore: SQLiteProjectStore) -> ProjectRecord? {
        guard let projects = try? projectStore.list() else {
            return nil
        }
        return VoiceDevelopmentProjectSelection.uniqueApprovedActiveProject(from: projects)
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

    static func makeTextToSpeechPreviewer(settings: AppSettings) -> any TextToSpeechPreviewing {
        AppTextToSpeechRuntimeFactory.makePreviewer(settings: settings)
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
                let projectStore = SQLiteProjectStore(connection: connection)
                let taskStore = SQLiteTaskStore(connection: connection)
                let artifactStore = SQLiteArtifactStore(connection: connection)
                let registry = try ToolRegistry.phase2MVP(
                    projectStore: projectStore,
                    taskStore: taskStore,
                    knowledgeStore: SQLiteKnowledgeFrameStore(connection: connection),
                    notificationClient: UserNotificationsNotificationClient(),
                    calendarClient: EventKitCalendarClient(),
                    reminderClient: EventKitReminderClient(),
                    fileAccessClient: LocalFileAccessClient(workspaceRoot: try workspaceRootURL()),
                    mailDraftClient: try makeMailDraftClient(),
                    notificationRequestStore: SQLiteNotificationRequestStore(connection: connection),
                    calendarLinkStore: SQLiteCalendarLinkStore(connection: connection),
                    reminderLinkStore: SQLiteReminderLinkStore(connection: connection),
                    artifactStore: artifactStore,
                    auditLogger: auditLogger
                )
                try registry.register(AuditedTool(
                    base: DevelopmentPRWorkflowTool(
                        projectStore: projectStore,
                        taskStore: taskStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                // Register only local, approval-gated development tools here. The broader
                // developer-mode factory also exposes push and GitHub PR creation, which
                // must stay outside the app ReviewSession runtime until those gates have
                // separate product review and merge readiness checks.
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryListFiles,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryReadFile,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryCreateFile,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentRepositoryFileTool(
                        name: .developmentRepositoryUpdateFile,
                        projectStore: projectStore,
                        artifactStore: artifactStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentVerificationCommandTool(
                        projectStore: projectStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
                try registry.register(AuditedTool(
                    base: DevelopmentCommitWorkflowTool(
                        projectStore: projectStore,
                        requireBookmark: true
                    ),
                    logger: auditLogger
                ))
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

    private static func makeSettingsBackedGoogleCalendarSyncController(
        connection: SQLiteConnection,
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore
    ) -> any GoogleCalendarRuntimeSyncing {
        SettingsBackedGoogleCalendarRuntimeSync(
            settingsStore: UserDefaultsAppSettingsStore(),
            statusFactory: { settings, now in
                try GoogleCalendarAppRuntimeFactory.syncStatus(
                    entitlementStore: entitlementStore,
                    secretStore: secretStore,
                    connection: connection,
                    calendarID: settings.googleCalendarID,
                    timeZoneIdentifier: settings.timeZoneIdentifier,
                    now: now,
                    oauthClientID: googleCalendarOAuthClientID()
                )
            },
            syncFactory: { settings in
                try makeGoogleCalendarSyncController(
                    connection: connection,
                    entitlementStore: entitlementStore,
                    store: store,
                    linkStore: linkStore,
                    secretStore: secretStore,
                    calendarID: settings.googleCalendarID,
                    timeZoneIdentifier: settings.timeZoneIdentifier
                )
            }
        )
    }

    private static func makeGoogleCalendarSyncController(
        connection: SQLiteConnection,
        entitlementStore: any EntitlementStore,
        store: any ProjectBoardStore,
        linkStore: any ExternalTaskLinkStore,
        secretStore: any SecretStore,
        calendarID: String,
        timeZoneIdentifier: String
    ) throws -> GoogleCalendarRuntimeSyncController {
        try GoogleCalendarAppRuntimeFactory.makeSyncController(
            entitlementStore: entitlementStore,
            store: store,
            linkStore: linkStore,
            secretStore: secretStore,
            connection: connection,
            idempotencyNamespaceStore: SQLiteGoogleCalendarIdempotencyNamespaceStore(connection: connection),
            calendarID: calendarID,
            timeZoneIdentifier: timeZoneIdentifier,
            oauthClientID: googleCalendarOAuthClientID()
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

    private static func makeEntitlementStore(secretStore: any SecretStore) -> KeychainEntitlementStore {
        KeychainEntitlementStore(
            secretStore: secretStore,
            verifier: makeLocalLicenseVerifier()
        )
    }

    private static func makeLocalLicenseVerifier() -> any LocalLicenseVerifier {
        guard let publicKeyBase64 = Bundle.main.object(forInfoDictionaryKey: "SoloPMLocalLicensePublicKey") as? String,
              !publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NoBundledLocalLicenseVerifier()
        }
        return SignedLocalLicenseVerifier(publicKeyBase64: publicKeyBase64)
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

    private static func makeMailDraftClient() throws -> any MailDraftClient {
        LocalFileMailDraftClient(
            draftsDirectoryURL: try applicationSupportDirectoryURL().appendingPathComponent("MailDrafts", isDirectory: true)
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

enum AppTextToSpeechRuntimeFactory {
    static func makeProvider(settings: AppSettings, outputURL: URL? = nil) -> any TextToSpeechProvider {
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

    static func makePreviewer(
        settings: AppSettings,
        temporaryDirectoryPrefix: String = "solopm-tts-preview",
        outputFilename: String = "preview.wav"
    ) -> any TextToSpeechPreviewing {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(temporaryDirectoryPrefix)-\(UUID().uuidString)", isDirectory: true)
        let outputURL = temporaryDirectory.appendingPathComponent(outputFilename, isDirectory: false)
        return TemporaryDirectoryTextToSpeechPreviewer(
            previewer: TextToSpeechPreviewService(
                provider: makeProvider(settings: settings, outputURL: outputURL),
                audioPlayer: AVFoundationSpeechAudioPlayer()
            ),
            temporaryDirectory: temporaryDirectory
        )
    }
}

@MainActor
protocol GoogleCalendarOAuthConnecting: AnyObject {
    func startAuthorization(
        completion: @escaping @MainActor (Result<GoogleCalendarOAuthCredentialMetadata, Error>) -> Void
    )
}

@MainActor
protocol GoogleCalendarOAuthDisconnecting: AnyObject {
    func disconnect() throws
}

protocol GoogleCalendarListProviding: Sendable {
    func listWritableCalendars() throws -> [GoogleCalendarRuntimeCalendarListEntry]
}

@MainActor
private final class GoogleCalendarOAuthCredentialDisconnectController: GoogleCalendarOAuthDisconnecting {
    private let disconnectAction: () throws -> Void

    init(disconnectAction: @escaping () throws -> Void) {
        self.disconnectAction = disconnectAction
    }

    func disconnect() throws {
        try disconnectAction()
    }
}

private struct GoogleCalendarRuntimeCalendarListProvider: GoogleCalendarListProviding {
    let client: any GoogleCalendarRuntimeCalendarListClient

    func listWritableCalendars() throws -> [GoogleCalendarRuntimeCalendarListEntry] {
        try client.listWritableCalendars()
    }
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

extension JSONValue {
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
