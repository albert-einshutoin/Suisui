import SuisuiCore
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct Suisui: App {
#if canImport(AppKit)
    @NSApplicationDelegateAdaptor(SuisuiAppDelegate.self) private var appDelegate
#endif
    @StateObject private var menuBarController: MenuBarSummaryController
    @StateObject private var menuBarQuickCaptureController: MenuBarQuickCaptureController
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @StateObject private var onboardingRerunCoordinator: OnboardingRerunCoordinator
    @StateObject private var projectBoardSceneCoordinator: ProjectBoardSceneCoordinator
    @StateObject private var shortcutSettingsViewModel: ShortcutSettingsViewModel
    @AppStorage(SuisuiAppearancePreference.storageKey) private var appearancePreference: SuisuiAppearancePreference = .system
    @AppStorage(AppLanguagePreference.storageKey) private var languagePreference: AppLanguagePreference = .system

    @MainActor
    init() {
        _menuBarController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarSummaryController())
        _menuBarQuickCaptureController = StateObject(wrappedValue: AppRuntimeFactory.makeMenuBarQuickCaptureController())
        _settingsViewModel = StateObject(
            wrappedValue: AppRuntimeFactory.makeAppSettingsViewModel(refreshProviderSecretStatusesOnInit: false)
        )
        _onboardingRerunCoordinator = StateObject(wrappedValue: OnboardingRerunCoordinator.shared)
        _projectBoardSceneCoordinator = StateObject(wrappedValue: ProjectBoardSceneCoordinator.shared)
        _shortcutSettingsViewModel = StateObject(wrappedValue: GlobalShortcutRuntime.shared.settingsViewModel)
#if canImport(AppKit)
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        // Creating a SwiftUI-hosted NSWindow here can enter AppKit layout before
        // the app run loop starts; the delegate owns fallback window creation.
#endif
    }

    var body: some Scene {
        WindowGroup("Suisui", id: "project-board") {
            ProjectBoardWindowRootView(
                settingsViewModel: settingsViewModel,
                onboardingRerunCoordinator: onboardingRerunCoordinator,
                sceneCoordinator: projectBoardSceneCoordinator
            )
            .background(GlobalVoiceShortcutBridge())
            .preferredColorScheme(effectiveAppearancePreference.colorScheme)
            .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .defaultSize(width: ProjectBoardWindowMetrics.defaultWidth, height: ProjectBoardWindowMetrics.defaultHeight)
        // ProjectBoardWindowStateBridge owns the explicit 960x572 minimum.
        // SwiftUI's content-derived minimum can lock the hydrated split view
        // near its 1180pt ideal and reject compact/manual AX resizing.
        .windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            SuisuiWindowCommands()
            SuisuiProjectBoardUndoCommands()
        }

        Window("Voice Command", id: "voice-capture") {
            VoiceCaptureWindowRootView()
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        }
        .defaultSize(width: 760, height: 640)

        MenuBarExtra {
            MenuBarPanel(
                controller: menuBarController,
                quickCaptureController: menuBarQuickCaptureController,
                sceneCoordinator: projectBoardSceneCoordinator
            )
                .preferredColorScheme(effectiveAppearancePreference.colorScheme)
                .environment(\.locale, effectiveLanguagePreference.locale)
        } label: {
            MenuBarExtraLabel(controller: menuBarController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowRootView(
                settingsViewModel: settingsViewModel,
                shortcutSettingsViewModel: shortcutSettingsViewModel,
                onboardingRerunCoordinator: onboardingRerunCoordinator,
                appearancePreference: $appearancePreference,
                languagePreference: $languagePreference
            )
            .preferredColorScheme(effectiveAppearancePreference.colorScheme)
            .environment(\.locale, effectiveLanguagePreference.locale)
        }
    }

    private var effectiveAppearancePreference: SuisuiAppearancePreference {
        SuisuiAppearancePreference.environmentOverride ?? appearancePreference
    }

    private var effectiveLanguagePreference: AppLanguagePreference {
        AppLanguagePreference.environmentOverride ?? languagePreference
    }
}

private struct GlobalVoiceShortcutBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                VoiceWindowActivationCoordinator.shared.installOpenRequest {
                    openWindow(id: "voice-capture")
                }
            }
    }
}

/// Menu bar status item label that surfaces overdue deadline debt at a glance.
/// This lives in its own view (not inline in the App body) because the
/// MenuBarExtra label closure does not re-render for @StateObject changes
/// observed only inside the App struct; @ObservedObject here re-renders the
/// label whenever the controller publishes a refreshed summary. The initial
/// refresh and board-change subscription live here as well, because the label
/// is always present while the panel content only appears after the user opens
/// the menu bar extra.
private struct MenuBarExtraLabel: View {
    @ObservedObject var controller: MenuBarSummaryController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        labelContent
            .onAppear {
                VoiceWindowActivationCoordinator.shared.installOpenRequest {
                    openWindow(id: "voice-capture")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardCommandReady)) { _ in
                // The board owns the launch-critical SQLite read. Refresh the
                // ancillary menu summary only after that read has made the
                // primary task surface usable, avoiding startup DB contention.
                controller.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .suisuiProjectBoardDidChange)) { _ in
                controller.refresh()
            }
    }

    @ViewBuilder
    private var labelContent: some View {
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
/// keyboard anywhere in the app (File menu, next to New Suisui Window).
private struct SuisuiWindowCommands: Commands {
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
    @ObservedObject var onboardingRerunCoordinator: OnboardingRerunCoordinator
    @ObservedObject var sceneCoordinator: ProjectBoardSceneCoordinator
    @State private var viewModel: ProjectBoardViewModel?
    @State private var provisionalSceneID = UUID()
    @SceneStorage(ProjectBoardScenePersistence.sceneIDStorageKey) private var storedSceneIDRawValue = ""
    @State private var isPrimaryOnboardingWindow = false
    @State private var isOnboardingPresented = false
    @AppStorage(FirstRunOnboardingGate.dismissedDefaultsKey) private var hasDismissedOnboarding = false
    @AppStorage(FirstRunOnboardingGate.completionDefaultsKey) private var legacyCompletionFlag = false

    var body: some View {
        Group {
            if let viewModel {
                projectBoardContent(viewModel: viewModel)
            } else {
                ProjectBoardFallbackLoadingView()
            }
        }
        .onAppear {
            persistSceneIdentityIfNeeded()
            isPrimaryOnboardingWindow = onboardingRerunCoordinator.register(windowID: sceneID)
            migrateOnboardingStateIfNeeded()
            // Consume a pending rerun immediately so a Settings tap that
            // arrived before the Project Board window mounted still opens the
            // sheet in this newly-registered primary window.
            if onboardingRerunCoordinator.consumePendingRerun(for: sceneID) != nil {
                isOnboardingPresented = true
            } else {
                isOnboardingPresented = FirstRunOnboardingGate.shouldPresent(
                    hasDismissedOnboarding: hasDismissedOnboarding,
                    isPrimaryWindow: isPrimaryOnboardingWindow
                )
            }
        }
        .onDisappear {
            onboardingRerunCoordinator.unregister(windowID: sceneID)
            isPrimaryOnboardingWindow = false
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingWelcomeView(
                settingsViewModel: settingsViewModel,
                permissionSnapshot: .empty,
                permissionSnapshotProvider: AppRuntimeFactory.makeIntegrationPermissionSnapshotSendable,
                onTrySuisui: { outcome in
                    hasDismissedOnboarding = true
                    isOnboardingPresented = false
                    guard let firstLessonTaskID = outcome.firstLessonTaskID else {
                        return
                    }
                    Task { @MainActor in
                        let retryPolicy = OnboardingTargetedRouteRetryPolicy()
                        var routeRequest: ProjectBoardOpenRequest?
                        for attempt in 1...retryPolicy.maximumAttempts {
                            // Keep routing and lesson focus on the window that owned onboarding.
                            // During a fast first-launch click, its model or scene registration can
                            // still be pending; requestOpen then returns nil and must be retried.
                            if viewModel != nil {
                                routeRequest = sceneCoordinator.requestOpen(
                                    targetSceneID: sceneID,
                                    route: OnboardingExperience.learnProjectTargetRoute
                                )
                            }
                            switch retryPolicy.decision(
                                afterAttempt: attempt,
                                requestWasAccepted: routeRequest != nil
                            ) {
                            case .retry:
                                try? await Task.sleep(for: .milliseconds(50))
                            case .awaitApplication:
                                break
                            case .exhausted:
                                return
                            }
                            if routeRequest != nil {
                                break
                            }
                        }
                        guard let routeRequest else {
                            return
                        }
                        var routeWasApplied = false
                        for _ in 0..<100 {
                            if sceneCoordinator.hasApplied(requestID: routeRequest.id) {
                                routeWasApplied = true
                                break
                            }
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                        guard routeWasApplied else {
                            return
                        }
                        var focusIntent = OnboardingLessonFocusIntent(taskID: firstLessonTaskID)
                        for _ in 0..<100 {
                            if let viewModel {
                                let visibleTaskIDs = Set(
                                    viewModel.snapshot.projects.flatMap(\.tasks).map(\.id)
                                )
                                switch focusIntent.nextAction(
                                    visibleTaskIDs: visibleTaskIDs,
                                    selectedTaskID: viewModel.selectedTaskID
                                ) {
                                case let .select(taskID):
                                    viewModel.selectedTaskID = taskID
                                case .completed:
                                    return
                                case nil:
                                    break
                                }
                            }
                            try? await Task.sleep(for: .milliseconds(50))
                        }
                    }
                }
            ) {
                hasDismissedOnboarding = true
                isOnboardingPresented = false
            }
        }
        .onChange(of: onboardingRerunCoordinator.rerunRequestToken) { _, _ in
            // Atomically check + mark the pending rerun so the same token can
            // never be consumed by more than one window even if multiple
            // Project Board windows are open when the Settings button is hit.
            if onboardingRerunCoordinator.consumePendingRerun(for: sceneID) != nil {
                isOnboardingPresented = true
            }
        }
        .onChange(of: onboardingRerunCoordinator.primaryWindowID) { _, newPrimary in
            isPrimaryOnboardingWindow = newPrimary == sceneID
            if isPrimaryOnboardingWindow,
               FirstRunOnboardingGate.shouldPresent(
                   hasDismissedOnboarding: hasDismissedOnboarding,
                   isPrimaryWindow: true
               ) {
                isOnboardingPresented = true
            }
        }
        .task {
            guard viewModel == nil else {
                return
            }
            guard ProjectBoardLaunchHydrationPolicy.shared.shouldHydrateWindowGroup(
                sceneID: sceneID,
                directFallbackRequested: SuisuiWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow,
                directFallbackWindowExists:
                    SuisuiProjectBoardWindowFallback.shared.windowForDelegateRetention != nil
            ) else {
                // Isolated launch routes intentionally publish an AppKit
                // fallback before the WindowGroup is ready. Hydrating this
                // hidden duplicate would race the visible board for SQLite
                // migration and cold-cache reads without serving the user.
                return
            }
            // Main-window creation must not wait for SQLite migration, receipt
            // stores, or connector composition. Prepare the heavy runtime
            // bundle off-main, then publish the MainActor-only view model.
            // Give SwiftUI one scheduling turn to publish the lightweight
            // loading surface without imposing a fixed delay on fast Macs.
            await Task.yield()
            let runtime = await AppRuntimeFactory.prepareProjectBoardRuntimeBundle()
            guard Task.isCancelled == false else {
                return
            }
            await MainActor.run {
                viewModel = AppRuntimeFactory.makeProjectBoardViewModel(runtime: runtime)
            }
        }
    }

    private var sceneID: UUID {
        UUID(uuidString: storedSceneIDRawValue) ?? provisionalSceneID
    }

    private func persistSceneIdentityIfNeeded() {
        guard UUID(uuidString: storedSceneIDRawValue) == nil else {
            return
        }
        // SceneStorage makes the identity survive SwiftUI view reconstruction
        // and state restoration without turning it into process-wide state.
        storedSceneIDRawValue = provisionalSceneID.uuidString
    }

    private func migrateOnboardingStateIfNeeded() {
        guard legacyCompletionFlag, !hasDismissedOnboarding else {
            return
        }
        FirstRunOnboardingGate.migrateLegacyCompletionIfNeeded(defaults: .standard)
        hasDismissedOnboarding = true
    }

    @ViewBuilder
    private func projectBoardContent(viewModel: ProjectBoardViewModel) -> some View {
        if SuisuiLaunchRecoveryEnvironment.isEnabled {
            ProjectBoardLaunchRecoveryView(
                viewModel: viewModel,
                appSettings: { settingsViewModel.settings }
            )
        } else {
            ProjectBoardView(
                viewModel: viewModel,
                sceneID: sceneID,
                restoresPrimaryPresentationState: isPrimaryOnboardingWindow,
                sceneCoordinator: sceneCoordinator,
                taskAutomationSettings: { settingsViewModel.settings.taskAutoExecution },
                appSettings: { settingsViewModel.settings },
                developmentAutomationReviewSession: AppRuntimeFactory.makeReviewSessionViewModel
            )
            .background(
                ProjectBoardWindowStateBridge(
                    sceneID: sceneID,
                    restoresPrimaryWindow: isPrimaryOnboardingWindow
                )
            )
        }
    }
}

private struct SettingsWindowRootView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    @ObservedObject var shortcutSettingsViewModel: ShortcutSettingsViewModel
    @ObservedObject var onboardingRerunCoordinator: OnboardingRerunCoordinator
    @Binding var appearancePreference: SuisuiAppearancePreference
    @Binding var languagePreference: AppLanguagePreference
    @State private var didScheduleProviderSecretStatusRefresh = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SettingsView(
            settingsViewModel: settingsViewModel,
            shortcutSettingsViewModel: shortcutSettingsViewModel,
            launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
            watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot(),
            integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot(),
            watcherDiagnosticsSnapshotFactory: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot,
            externalMCPSettingsViewModelFactory: AppRuntimeFactory.makeExternalMCPSettingsViewModel,
            syncSettingsViewModelFactory: AppRuntimeFactory.makeSyncSettingsViewModel,
            isGoogleCalendarRuntimeEnabled: AppRuntimeFactory.isGoogleCalendarRuntimeEnabled(),
            googleCalendarStatusProvider: AppRuntimeFactory.makeGoogleCalendarRuntimeSyncStatus,
            googleCalendarOAuthConnector: AppRuntimeFactory.makeGoogleCalendarOAuthConnector(),
            googleCalendarOAuthDisconnecter: AppRuntimeFactory.makeGoogleCalendarOAuthDisconnecter(),
            googleCalendarListProviderFactory: AppRuntimeFactory.makeGoogleCalendarListProvider,
            textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer,
            appearancePreference: $appearancePreference,
            languagePreference: $languagePreference,
            onboardingRerunRequest: {
                // When no Project Board window is mounted we must open one
                // before the coordinator publishes the token; otherwise the
                // `onAppear` consumer would register too late and miss the
                // rerun. If a primary already exists, just request the rerun
                // and the existing window will consume it.
                if onboardingRerunCoordinator.primaryWindowID == nil {
                    openWindow(id: "project-board")
                }
                onboardingRerunCoordinator.requestRerun()
            }
        )
        .task {
            guard !didScheduleProviderSecretStatusRefresh else {
                return
            }
            didScheduleProviderSecretStatusRefresh = true
            // Provider secret status reads are Settings-shell work and should
            // not block the first paint of the Settings window. The async
            // refresh runs the Ollama probe and the Keychain reads off the
            // MainActor, then applies the typed state on the MainActor.
            await settingsViewModel.refreshProviderReadiness()
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
                    .frame(minWidth: 680, minHeight: 640)
                    .accessibilityIdentifier("voice-capture-loading")
            }
        }
        .background(VoiceWindowIdentifierInstaller())
        .task {
            guard viewModel == nil else {
                return
            }
            // Voice runtime construction touches audio, model providers, audit
            // logging, and local stores. Defer it until this secondary window is
            // opened so primary Project Board launch is not blocked.
            viewModel = AppRuntimeFactory.makeVoiceCaptureViewModel()
        }
        .onAppear {
            VoiceWindowActivationCoordinator.shared.markVoiceWindowVisible()
        }
        .onDisappear {
            VoiceWindowActivationCoordinator.shared.markVoiceWindowClosed()
        }
    }
}

private enum SuisuiLaunchRecoveryEnvironment {
    private static let flagName = "SUISUI_LAUNCH_RECOVERY_MODE"

    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        // Isolated databases and keychain-free runs are also used by visual
        // evidence and CRUD smokes, so recovery is explicit. Only launch
        // verification paths opt in when they need the lightweight workflow
        // surface to avoid early AppKit toolbar layout before AX is ready.
        return environment[flagName] == "1"
    }
}

@MainActor
final class ProjectBoardLaunchHydrationPolicy {
    static let shared = ProjectBoardLaunchHydrationPolicy()

    private enum Decision {
        case undecided
        case noSuppression
        case suppressingInitialScene(UUID)
    }

    private var decision = Decision.undecided

    func shouldHydrateWindowGroup(
        sceneID: UUID,
        directFallbackRequested: Bool,
        directFallbackWindowExists: Bool
    ) -> Bool {
        // Production recovery may create a fallback after a normal launch.
        // Suppress only the first isolated-launch WindowGroup, and remember its
        // scene identity so reconstruction cannot accidentally hydrate it.
        // A different scene is a user-created window and keeps its independent
        // view model even while the launch fallback remains alive.
        switch decision {
        case .noSuppression:
            return true
        case let .suppressingInitialScene(suppressedSceneID):
            return suppressedSceneID != sceneID
        case .undecided:
            // The first WindowGroup decides the launch topology. If it already
            // has to hydrate because the requested fallback was not created,
            // a fallback arriving later must not consume the one suppression
            // slot and hide a user-created second window.
            guard directFallbackRequested, directFallbackWindowExists else {
                decision = .noSuppression
                return true
            }
            decision = .suppressingInitialScene(sceneID)
            return false
        }
    }
}

private enum SuisuiWindowlessFallbackEnvironment {
    private static let forceFallbackFlagName = "SUISUI_FORCE_PROJECT_BOARD_FALLBACK"
    private static let disableFallbackFlagName = "SUISUI_DISABLE_PROJECT_BOARD_FALLBACK"
    static let maxWindowGroupRestoreAttempts = 3

    static var shouldForceProjectBoardFallback: Bool {
        ProcessInfo.processInfo.environment[forceFallbackFlagName] == "1"
    }

    static var shouldCreateDirectFallbackWindow: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment[disableFallbackFlagName] != "1" else {
            // Layout evidence must exercise the canonical WindowGroup alone.
            // The opt-out is process-local so production isolated launches
            // retain their early visible fallback and launch resilience.
            return false
        }
        // Direct binary launches with an isolated SQLite path do not always
        // get a SwiftUI WindowGroup quickly enough for AX/screenshot gates.
        // They still need the full board unless launch recovery explicitly opts in.
        return SuisuiLaunchRecoveryEnvironment.isEnabled
            || environment["SUISUI_DATABASE_PATH"] != nil
            || shouldForceProjectBoardFallback
    }
}

private struct ProjectBoardFallbackRootView: View {
    private let taskAutomationSettings: () -> TaskAutoExecutionSettings
    private let appSettings: () -> AppSettings
    @State private var viewModel: ProjectBoardViewModel?
    @State private var isProjectBoardReady = false
    @State private var sceneID = UUID()

    init(
        taskAutomationSettings: @escaping () -> TaskAutoExecutionSettings = { .default },
        appSettings: @escaping () -> AppSettings = { .default }
    ) {
        self.taskAutomationSettings = taskAutomationSettings
        self.appSettings = appSettings
    }

    var body: some View {
        Group {
            if let viewModel, SuisuiLaunchRecoveryEnvironment.isEnabled {
                ProjectBoardLaunchRecoveryView(
                    viewModel: viewModel,
                    appSettings: appSettings
                )
            } else if let viewModel, isProjectBoardReady {
                ProjectBoardView(
                    viewModel: viewModel,
                    sceneID: sceneID,
                    restoresPrimaryPresentationState: false,
                    sceneCoordinator: ProjectBoardSceneCoordinator.shared,
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
            // The window is already visible. Yield once before starting the
            // detached runtime work so first paint wins without a fixed pause.
            await Task.yield()
            let runtime = await AppRuntimeFactory.prepareProjectBoardRuntimeBundle()
            guard Task.isCancelled == false else {
                return
            }
            await MainActor.run {
                viewModel = AppRuntimeFactory.makeProjectBoardViewModel(runtime: runtime)
                isProjectBoardReady = !SuisuiLaunchRecoveryEnvironment.isEnabled
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
        // This temporary surface must advertise only the real minimum. An
        // ideal size here becomes the hosting window's effective minimum and
        // prevents the production board from honoring compact or evidence
        // viewport sizes after hydration completes.
        .frame(minWidth: 960, minHeight: 572)
        .accessibilityIdentifier("project-board-fallback-loading")
    }
}

#if canImport(AppKit)
@MainActor
private final class SuisuiProjectBoardWindowFallback {
    static let shared = SuisuiProjectBoardWindowFallback()

    private var window: NSWindow?

    var windowForDelegateRetention: NSWindow? {
        window
    }

    func showIfNeeded() {
        guard SuisuiWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else {
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
        window.title = "Suisui"
        window.contentViewController = hostingController
        // The loading view is temporary. Pin only the supported compact
        // minimum so its initial fitting size cannot become a permanent
        // 1180pt resize floor after the real board replaces it.
        window.contentMinSize = NSSize(width: 960, height: 572)
        window.isReleasedWhenClosed = false
        window.setFrame(NSRect(x: 120, y: 160, width: 1_180, height: 760), display: true)
        self.window = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        LaunchPerformanceMilestones.record("window-visible")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var visibleProjectBoardWindows: [NSWindow] {
        NSApplication.shared.windows.filter { window in
            // AppKit restoration can mark a window visible before it is actually
            // on-screen; occlusion keeps screenshot/AX gates from trusting that state.
            window.isVisible
                && window.occlusionState.contains(.visible)
                && !window.isMiniaturized
                && (window.title == "Suisui" || window.title == String(localized: "Suisui"))
        }
    }

    private static var effectiveAppearancePreference: SuisuiAppearancePreference {
        SuisuiAppearancePreference.environmentOverride ?? persistedAppearancePreference
    }

    private static var persistedAppearancePreference: SuisuiAppearancePreference {
        guard let rawValue = UserDefaults.standard.string(forKey: SuisuiAppearancePreference.storageKey),
              let preference = SuisuiAppearancePreference(rawValue: rawValue) else {
            return .system
        }
        return preference
    }
}

@MainActor
private final class SuisuiAppDelegate: NSObject, NSApplicationDelegate {
#if canImport(Sparkle)
    private var updaterController: SPUStandardUpdaterController?
#endif
    private var projectBoardWindowRestoreAttempts = 0
    private var fallbackProjectBoardWindow: NSWindow?
    private var settingsEvidenceWindow: NSWindow?
    private var voiceCommandEvidenceWindow: NSWindow?
    private var digestNotificationOpenedObserver: (any NSObjectProtocol)?
    private var commandReadyRuntimeObserver: (any NSObjectProtocol)?
    private var backgroundRuntimesStarted = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SUISUI_VISUAL_EVIDENCE_SYSTEM_APPEARANCE"] == "dark",
              SuisuiAppearancePreference.environmentOverride == .system else {
            return
        }

        // System evidence must keep the product preference on `system`, while
        // rendering against one canonical host appearance. GitHub-hosted GUI
        // sessions do not honor `-AppleInterfaceStyle` consistently, so set
        // the process appearance before any evidence window is materialized.
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        installVisualEvidenceBackdropIfRequested()
        SuisuiNotificationResponder.shared.install()
        installCommandReadyRuntimeObserver()
        ensureProjectBoardWindowIsVisible()
        // Tapping a digest notification must surface the Project Board even
        // when every window was closed; reuse the reopen recovery path.
        digestNotificationOpenedObserver = NotificationCenter.default.addObserver(
            forName: .suisuiDigestNotificationOpened,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // A digest is about today's work: land on Today, not the last
                // visited destination, whether the window is reopened or reused.
                _ = ProjectBoardSceneCoordinator.shared.requestOpen(route: .primary(.today))
                self?.ensureProjectBoardWindowIsVisible()
            }
        }
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

    private func installVisualEvidenceBackdropIfRequested() {
        guard ProcessInfo.processInfo.environment["SUISUI_VISUAL_EVIDENCE_STABLE_BACKDROP"] == "1" else {
            return
        }

        // Native materials otherwise sample the login user's wallpaper and
        // physical display. Keep this capture-only: normal windows retain the
        // platform material behavior and no global accessibility setting moves.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visualEvidenceWindowDidBecomeVisible(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NSApplication.shared.windows.forEach(configureVisualEvidenceBackdrop)
    }

    @objc
    private func visualEvidenceWindowDidBecomeVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        configureVisualEvidenceBackdrop(window)
    }

    private func configureVisualEvidenceBackdrop(_ window: NSWindow) {
        let isDark = window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let component: CGFloat = isDark ? 0.105 : 0.94
        // Capture windows must render in a device-independent color space.
        // Otherwise ColorSync bakes the physical monitor profile into pixels,
        // so identical semantic colors differ from hosted virtual displays.
        window.colorSpace = .sRGB
        let neutralBackdropColor = NSColor(
            srgbRed: component,
            green: component,
            blue: component,
            alpha: 1
        )
        window.backgroundColor = neutralBackdropColor
        window.isOpaque = true
    }

    private func installCommandReadyRuntimeObserver() {
        guard commandReadyRuntimeObserver == nil else {
            return
        }
        commandReadyRuntimeObserver = NotificationCenter.default.addObserver(
            forName: .suisuiProjectBoardCommandReady,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startBackgroundRuntimesOnce()
            }
        }
    }

    private func startBackgroundRuntimesOnce() {
        guard backgroundRuntimesStarted == false else {
            return
        }
        backgroundRuntimesStarted = true
        // Retention, badge, and deadline reads remain automatic, but the first
        // board load gets exclusive access to startup SQLite work so the app's
        // command surface is responsive before ancillary maintenance begins.
        ConversationRetentionRuntime.shared.start()
        DockTileBadgeController.shared.start()
        DeadlineWatcherRuntime.shared.start()
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
        if SuisuiWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow {
            // Isolated release/performance launches deliberately bypass state
            // restoration. Publish their owned fallback window immediately;
            // waiting here would become product launch latency, not resilience.
            createFallbackProjectBoardWindow()
            return
        }
        attemptEnsureProjectBoardWindowIsVisible(after: 0.25)
    }

    private func attemptEnsureProjectBoardWindowIsVisible(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)
            guard self.visibleProjectBoardWindows.isEmpty else {
                return
            }

            if SuisuiWindowlessFallbackEnvironment.shouldCreateDirectFallbackWindow {
                self.createFallbackProjectBoardWindow()
                return
            }

            let didRequestWindow = self.performNewProjectBoardWindowMenuItem()
                || NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)

            self.projectBoardWindowRestoreAttempts += 1
            guard self.projectBoardWindowRestoreAttempts < SuisuiWindowlessFallbackEnvironment.maxWindowGroupRestoreAttempts else {
                self.createFallbackProjectBoardWindow()
                return
            }

            self.attemptEnsureProjectBoardWindowIsVisible(after: didRequestWindow ? 0.75 : 0.25)
        }
    }

    private func performNewProjectBoardWindowMenuItem() -> Bool {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu,
              let itemIndex = fileMenu.items.firstIndex(where: { $0.title == "New Suisui Window" && $0.isEnabled }) else {
            return false
        }

        fileMenu.performActionForItem(at: itemIndex)
        return true
    }

    private func createFallbackProjectBoardWindow() {
        guard SuisuiWindowlessFallbackEnvironment.shouldForceProjectBoardFallback || visibleProjectBoardWindows.isEmpty else {
            return
        }

        SuisuiProjectBoardWindowFallback.shared.showIfNeeded()
        fallbackProjectBoardWindow = SuisuiProjectBoardWindowFallback.shared.windowForDelegateRetention
    }

    private func openSettingsWindowForEvidenceIfRequested() {
        guard ProcessInfo.processInfo.environment["SUISUI_OPEN_SETTINGS_ON_LAUNCH"] == "1" else {
            return
        }
        let selectedTab = SettingsTab(
            rawValue: ProcessInfo.processInfo.environment["SUISUI_SETTINGS_EVIDENCE_TAB"] ?? ""
        ) ?? .overview

        // The release evidence harness opens Settings directly so captures do not depend on keyboard focus, AppleScript toolbar access, or localized menu state.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let hostingController = NSHostingController(
                rootView: SettingsView(
                    settingsViewModel: AppRuntimeFactory.makeAppSettingsViewModel(),
                    shortcutSettingsViewModel: GlobalShortcutRuntime.shared.settingsViewModel,
                    launchAtLoginViewModel: AppRuntimeFactory.makeLaunchAtLoginSettingsViewModel(),
                    watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot(),
                    integrationPermissionSnapshot: AppRuntimeFactory.makeIntegrationPermissionSnapshot(),
                    watcherDiagnosticsSnapshotFactory: AppRuntimeFactory.makeWatcherDiagnosticsSnapshot,
                    externalMCPSettingsViewModelFactory: AppRuntimeFactory.makeExternalMCPSettingsViewModel,
                    syncSettingsViewModelFactory: AppRuntimeFactory.makeSyncSettingsViewModel,
                    isGoogleCalendarRuntimeEnabled: AppRuntimeFactory.isGoogleCalendarRuntimeEnabled(),
                    googleCalendarStatusProvider: AppRuntimeFactory.makeGoogleCalendarRuntimeSyncStatus,
                    googleCalendarOAuthConnector: AppRuntimeFactory.makeGoogleCalendarOAuthConnector(),
                    googleCalendarOAuthDisconnecter: AppRuntimeFactory.makeGoogleCalendarOAuthDisconnecter(),
                    googleCalendarListProviderFactory: AppRuntimeFactory.makeGoogleCalendarListProvider,
                    textToSpeechPreviewerFactory: AppRuntimeFactory.makeTextToSpeechPreviewer,
                    appearancePreference: .constant(SuisuiAppearancePreference.environmentOverride ?? .system),
                    languagePreference: .constant(AppLanguagePreference.environmentOverride ?? .system),
                    initialTab: selectedTab,
                    onboardingRerunRequest: { OnboardingRerunCoordinator.shared.requestRerun() }
                )
                .preferredColorScheme(SuisuiAppearancePreference.environmentOverride?.colorScheme)
                .environment(\.locale, (AppLanguagePreference.environmentOverride ?? .system).locale)
            )
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 572),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = selectedTab.rawValue
            window.contentViewController = hostingController
            window.isReleasedWhenClosed = false
            window.setFrame(NSRect(x: 120, y: 160, width: 680, height: 572), display: true)
            self.settingsEvidenceWindow = window
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func openVoiceCommandWindowForEvidenceIfRequested() {
        guard ProcessInfo.processInfo.environment["SUISUI_OPEN_VOICE_COMMAND_ON_LAUNCH"] == "1" else {
            return
        }

        // Runtime evidence opens Voice Command directly so AX tests do not rely
        // on menu focus, menu bar state, or localized window-opening commands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let hostingController = NSHostingController(
                rootView: VoiceCaptureView(viewModel: AppRuntimeFactory.makeVoiceCaptureViewModel())
                    .preferredColorScheme(SuisuiAppearancePreference.environmentOverride?.colorScheme)
                    .environment(\.locale, (AppLanguagePreference.environmentOverride ?? .system).locale)
            )
            // This deterministic evidence window owns its outer viewport.
            // Prevent SwiftUI fitting hints from becoming AppKit min/max
            // constraints that silently clamp the audited 760x640 frame.
            hostingController.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Voice Command"
            window.identifier = NSUserInterfaceItemIdentifier(VoiceWindowIdentity.identifierRawValue)
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
                && (window.title == "Suisui" || window.title == String(localized: "Suisui"))
        }
    }
}
#endif
