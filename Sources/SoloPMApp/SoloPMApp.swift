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
    @StateObject private var menuBarQuickCaptureController: MenuBarQuickCaptureController
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @AppStorage(SoloPMAppearancePreference.storageKey) private var appearancePreference: SoloPMAppearancePreference = .system
    @AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system

    @MainActor
    init() {
        _menuBarController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarSummaryController())
        _menuBarQuickCaptureController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarQuickCaptureController())
        _settingsViewModel = StateObject(
            wrappedValue: AppRuntimeFactory.makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: false)
        )
#if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Creating a SwiftUI-hosted NSWindow here can enter AppKit layout before
        // the app run loop starts; the delegate owns fallback window creation.
#endif
    }

    var body: some Scene {
        WindowGroup("SoloPM", id: "project-board") {
            ProjectBoardWindowRootView(settingsViewModel: settingsViewModel)
            .preferredColorScheme(effectiveAppearancePreference.colorScheme)
            .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .defaultSize(width: ProjectBoardWindowMetrics.defaultWidth, height: ProjectBoardWindowMetrics.defaultHeight)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            SoloPMWindowCommands()
        }

        Window("Voice Command", id: "voice-capture") {
            VoiceCaptureWindowRootView()
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .defaultSize(width: 560, height: 420)

        MenuBarExtra {
            MenuBarPanel(controller: menuBarController, quickCaptureController: menuBarQuickCaptureController)
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        } label: {
            MenuBarExtraLabel(controller: menuBarController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowRootView(
                settingsViewModel: settingsViewModel,
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

/// Menu bar status item label that surfaces overdue deadline debt at a glance.
/// This lives in its own view (not inline in the App body) because the
/// MenuBarExtra label closure does not re-render for @StateObject changes
/// observed only inside the App struct; @ObservedObject here re-renders the
/// label whenever the controller publishes a refreshed summary.
private struct MenuBarExtraLabel: View {
    @ObservedObject var controller: MenuBarSummaryController

    var body: some View {
        if overdueTaskCount > 0 {
            HStack(spacing: 2) {
                Image(systemName: "checklist")
                Text(verbatim: "\(overdueTaskCount)")
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: controller.viewModel.overdueLabel))
            .accessibilityIdentifier("menu-bar-extra-label")
        } else {
            Image(systemName: "checklist")
                .accessibilityIdentifier("menu-bar-extra-label")
        }
    }

    private var overdueTaskCount: Int {
        controller.viewModel.summary.overdueTaskCount
    }
}

/// App-menu window commands so the primary surfaces are reachable from the
/// keyboard anywhere in the app (File menu, next to New SoloPM Window).
private struct SoloPMWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()

            Button {
                openWindow(id: "project-board")
            } label: {
                Label("Project Board", systemImage: "rectangle.3.group")
            }
            .keyboardShortcut("0", modifiers: [.command])

            Button {
                openWindow(id: "voice-capture")
            } label: {
                Label("Voice Command", systemImage: "mic")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
}

private struct ProjectBoardWindowRootView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    @State private var viewModel: ProjectBoardViewModel?
    @AppStorage(FirstRunOnboardingGate.completionDefaultsKey) private var hasCompletedOnboarding = false
    @State private var isOnboardingPresented = false

    var body: some View {
        Group {
            if let viewModel {
                projectBoardContent(viewModel: viewModel)
            } else {
                ProjectBoardFallbackLoadingView()
            }
        }
        .onAppear {
            isOnboardingPresented = FirstRunOnboardingGate.shouldPresent(
                hasCompletedOnboarding: hasCompletedOnboarding
            )
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingWelcomeView(settingsViewModel: settingsViewModel) {
                hasCompletedOnboarding = true
                isOnboardingPresented = false
            }
        }
        .task {
            guard viewModel == nil else {
                return
            }
            // Main-window creation must not wait for SQLite migration, receipt
            // stores, or connector composition. Prepare the heavy runtime
            // bundle off-main, then publish the MainActor-only view model.
            try? await Task.sleep(nanoseconds: ProjectBoardLaunchHydrationDelay.nanoseconds)
            let runtime = await AppRuntimeFactory.prepareProjectBoardRuntimeBundle()
            guard Task.isCancelled == false else {
                return
            }
            await MainActor.run {
                viewModel = AppRuntimeFactory.makeProjectBoardViewModel(runtime: runtime)
            }
        }
    }

    @ViewBuilder
    private func projectBoardContent(viewModel: ProjectBoardViewModel) -> some View {
        if SoloPMLaunchRecoveryEnvironment.isEnabled {
            ProjectBoardLaunchRecoveryView(
                viewModel: viewModel,
                appSettings: { settingsViewModel.settings }
            )
        } else {
            ProjectBoardView(
                viewModel: viewModel,
                taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution },
                appSettings: { settingsViewModel.settings },
                developmentAutomationReviewSession: AppRuntimeFactory.makeReviewSessionViewModel
            )
        }
    }
}

private enum ProjectBoardLaunchHydrationDelay {
    // AX/window-server publication can lag SwiftUI's first body pass. Keep the
    // pause short because the heavy runtime work already moves off-main.
    static let nanoseconds: UInt64 = 150_000_000
}

private struct SettingsWindowRootView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    @Binding var appearancePreference: SoloPMAppearancePreference
    @Binding var languagePreference: AppLanguagePreference
    @State private var didScheduleProviderSecretStatusRefresh = false

    var body: some View {
        SettingsView(
            settingsViewModel: settingsViewModel,
            launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
            watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot(),
            integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot(),
            watcherDiagnosticsSnapshotFactory: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot,
            externalMCPSettingsViewModelFactory: AppRuntimeFactory.makeExternalMCPSettingsViewModel,
            syncSettingsViewModelFactory: AppRuntimeFactory.makeSyncSettingsViewModel,
            googleCalendarStatusProvider: AppRuntimeFactory.makeGoogleCalendarRuntimeSyncStatus,
            googleCalendarOAuthConnector: AppRuntimeFactory.makeGoogleCalendarOAuthConnector(),
            googleCalendarOAuthDisconnecter: AppRuntimeFactory.makeGoogleCalendarOAuthDisconnecter(),
            googleCalendarListProviderFactory: AppRuntimeFactory.makeGoogleCalendarListProvider,
            textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer,
            appearancePreference: $appearancePreference,
            languagePreference: $languagePreference
        )
        .task {
            guard !didScheduleProviderSecretStatusRefresh else {
                return
            }
            didScheduleProviderSecretStatusRefresh = true
            // Provider secret status reads are Settings-shell work and should
            // not block the first paint of the Settings window.
            settingsViewModel.refreshProviderSecretStatuses()
        }
    }
}

private struct VoiceCaptureWindowRootView: View {
    @State private var viewModel: VoiceCaptureViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VoiceCaptureView(viewModel: viewModel)
            } else {
                ProgressView("Opening Voice Command")
                    .frame(minWidth: 560, minHeight: 420)
                    .accessibilityIdentifier("voice-capture-loading")
            }
        }
        .task {
            guard viewModel == nil else {
                return
            }
            // Voice runtime construction touches audio, model providers, audit
            // logging, and local stores. Defer it until this secondary window is
            // opened so primary Project Board launch is not blocked.
            viewModel = AppRuntimeFactory.makeVoiceCaptureViewModel()
        }
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
    static let maxWindowGroupRestoreAttempts = 3

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
    private let taskAutomationSettings: () -> TaskAutoExecutionSettings
    private let appSettings: () -> AppSettings
    @State private var viewModel: ProjectBoardViewModel?
    @State private var isProjectBoardReady = false

    init(
        taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings = { .default },
        appSettings: @escaping () -> AppSettings = { .default }
    ) {
        self.taskAutomationSettings = taskAutomationSettings
        self.appSettings = appSettings
    }

    var body: some View {
        Group {
            if let viewModel, SoloPMLaunchRecoveryEnvironment.isEnabled {
                ProjectBoardLaunchRecoveryView(
                    viewModel: viewModel,
                    appSettings: appSettings
                )
            } else if let viewModel, isProjectBoardReady {
                ProjectBoardView(
                    viewModel: viewModel,
                    taskAutomationSettings: taskAutomationSettings,
                    appSettings: appSettings,
                    developmentAutomationReviewSession: AppRuntimeFactory.makeReviewSessionViewModel
                )
            } else {
                ProjectBoardFallbackLoadingView()
            }
        }
        .task {
            guard viewModel == nil else {
                return
            }
            // The direct fallback exists for screenshot and AX launches. Ordering a
            // small visible window first prevents SQLite open/migration and the
            // full board's initial SwiftUI layout from leaving evidence scripts
            // with a process but no window.
            try? await Task.sleep(nanoseconds: ProjectBoardLaunchHydrationDelay.nanoseconds)
            let runtime = await AppRuntimeFactory.prepareProjectBoardRuntimeBundle()
            guard Task.isCancelled == false else {
                return
            }
            await MainActor.run {
                viewModel = AppRuntimeFactory.makeProjectBoardViewModel(runtime: runtime)
                isProjectBoardReady = !SoloPMLaunchRecoveryEnvironment.isEnabled
            }
        }
    }
}

private struct ProjectBoardFallbackLoadingView: View {
    var body: some View {
        ContentUnavailableView(
            "Opening Project Board",
            systemImage: "rectangle.3.group",
            description: Text("Preparing local project data for the visible window.")
        )
        .frame(minWidth: 960, idealWidth: 1_180, minHeight: 620, idealHeight: 760)
        .accessibilityIdentifier("project-board-fallback-loading")
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
        SoloPMNotificationResponder.shared.install()
        DockTileBadgeController.shared.start()
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

    // The app owns window recovery through a lightweight fallback window; macOS
    // persistent UI restoration can replay stale SwiftUI window state before
    // launch/evidence gates can observe a real Project Board.
    func application(_ application: NSApplication, shouldSaveApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication, shouldRestoreApplicationState coder: NSCoder) -> Bool {
        false
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
            guard self.projectBoardWindowRestoreAttempts < SoloPMWindowlessFallbackEnvironment.maxWindowGroupRestoreAttempts else {
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
                    watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot(),
                    integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot(),
                    watcherDiagnosticsSnapshotFactory: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot,
                    externalMCPSettingsViewModelFactory: AppRuntimeFactory.makeExternalMCPSettingsViewModel,
                    syncSettingsViewModelFactory: AppRuntimeFactory.makeSyncSettingsViewModel,
                    googleCalendarStatusProvider: AppRuntimeFactory.makeGoogleCalendarRuntimeSyncStatus,
                    googleCalendarOAuthConnector: AppRuntimeFactory.makeGoogleCalendarOAuthConnector(),
                    googleCalendarOAuthDisconnecter: AppRuntimeFactory.makeGoogleCalendarOAuthDisconnecter(),
                    googleCalendarListProviderFactory: AppRuntimeFactory.makeGoogleCalendarListProvider,
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
