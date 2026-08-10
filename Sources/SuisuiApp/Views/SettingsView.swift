import Combine
import Foundation
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

enum SettingsTab: String {
    case overview = "Overview"
    case appearance = "Appearance"
    case ai = "AI"
    case mcp = "MCP"
    case sync = "Sync"
    case privacy = "Privacy"
}

extension VoiceModelID {
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

@MainActor
final class LazyDependencyLoader<Value>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var isLoading = false
    let loadValue: () -> Value

    init(loadValue: @escaping () -> Value) {
        self.loadValue = loadValue
    }

    func loadIfNeeded() {
        guard value == nil, isLoading == false else {
            return
        }
        isLoading = true

        // Dependencies can open persistent stores. Kick off loading on a
        // delayed main-task to keep Settings shell paint responsive while the tab
        // starts hydrating.
        Task { @MainActor in
            await Task.yield()
            self.value = self.loadValue()
            self.isLoading = false
        }
    }
}

@MainActor
final class LazyObservableObjectLoader<Value: ObservableObject>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var isLoading = false
    let loadValue: () -> Value
    var valueCancellable: AnyCancellable?

    init(loadValue: @escaping () -> Value) {
        self.loadValue = loadValue
    }

    func loadIfNeeded() {
        guard value == nil, isLoading == false else {
            return
        }
        isLoading = true

        Task { @MainActor in
            await Task.yield()
            let loadedValue = self.loadValue()
            // The loader owns tab-scoped view models outside SwiftUI's direct
            // @ObservedObject path, so it republishes nested changes to keep lazy
            // Settings tabs live after actions mutate their model.
            self.valueCancellable = loadedValue.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            self.value = loadedValue
            self.isLoading = false
        }
    }
}

struct SettingsView: View {
    let watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot
    let integrationPermissionSnapshot: PermissionSnapshot
    let watcherDiagnosticsSnapshotFactory: () -> WatcherDiagnosticsSnapshot
    let externalMCPSettingsViewModelFactory: () -> ExternalMCPSettingsViewModel
    let syncSettingsViewModelFactory: () -> SyncSettingsViewModel
    let isGoogleCalendarRuntimeEnabled: Bool
    let googleCalendarStatusProvider: () -> GoogleCalendarRuntimeSyncStatus
    let googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?
    let googleCalendarOAuthDisconnecter: (any GoogleCalendarOAuthDisconnecting)?
    let googleCalendarListProviderFactory: () -> (any GoogleCalendarListProviding)?
    let textToSpeechPreviewerFactory: (AppSettings) -> any TextToSpeechPreviewing
    let onboardingRerunRequest: () -> Void
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @ObservedObject private var shortcutSettingsViewModel: ShortcutSettingsViewModel
    @StateObject private var launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    @StateObject private var watcherDiagnosticsLoader: LazyDependencyLoader<WatcherDiagnosticsSnapshot>
    @StateObject private var externalMCPSettingsViewModelLoader: LazyObservableObjectLoader<ExternalMCPSettingsViewModel>
    @StateObject private var syncSettingsViewModelLoader: LazyObservableObjectLoader<SyncSettingsViewModel>
    @Binding private var appearancePreference: SuisuiAppearancePreference
    @Binding private var languagePreference: AppLanguagePreference
    @State private var isConfirmingMCPRegistrationDeletion = false
    @State private var isConfirmingGoogleCalendarOAuthDisconnect = false
    @State private var pendingBackupRestoreDocument: WorkspaceBackupDocument?
    @State private var isConfirmingBackupRestore = false
    @State private var backupStatusMessage: String?
    @State private var backupErrorMessage: String?
    @State private var diagnosticsExportErrorMessage: String?
    @State private var selectedTab: SettingsTab
    @State private var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus?
    @State private var googleCalendarSetupMessage: String?
    @State private var isGoogleCalendarOAuthAuthorizationInProgress = false
    @State private var googleCalendarListProvider: (any GoogleCalendarListProviding)?
    @State private var isLoadingGoogleCalendarList = false
    @State private var googleCalendarListOptions: [GoogleCalendarRuntimeCalendarListEntry] = []
    @State private var googleCalendarListLoadGeneration = 0
    @State private var hasLoadedCalendarListProvider = false
    @AppStorage("suisui.settings.showAdvanced") private var showAdvancedSettings = false
    @State private var forcesAdvancedTabsForInitialTab: Bool

    init(
        settingsViewModel: AppSettingsViewModel,
        shortcutSettingsViewModel: ShortcutSettingsViewModel,
        launchAtLoginViewModel: LaunchAtLoginSettingsViewModel,
        watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot,
        integrationPermissionSnapshot: PermissionSnapshot,
        watcherDiagnosticsSnapshotFactory: @escaping () -> WatcherDiagnosticsSnapshot,
        externalMCPSettingsViewModelFactory: @escaping () -> ExternalMCPSettingsViewModel,
        syncSettingsViewModelFactory: @escaping () -> SyncSettingsViewModel,
        isGoogleCalendarRuntimeEnabled: Bool,
        googleCalendarStatusProvider: @escaping () -> GoogleCalendarRuntimeSyncStatus,
        googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?,
        googleCalendarOAuthDisconnecter: (any GoogleCalendarOAuthDisconnecting)?,
        googleCalendarListProviderFactory: @escaping () -> (any GoogleCalendarListProviding)?,
        textToSpeechPreviewerFactory: @escaping (AppSettings) -> any TextToSpeechPreviewing,
        appearancePreference: Binding<SuisuiAppearancePreference>,
        languagePreference: Binding<AppLanguagePreference>,
        initialTab: SettingsTab = .overview,
        onboardingRerunRequest: @escaping () -> Void = {}
    ) {
        self.watcherDiagnosticsSnapshot = watcherDiagnosticsSnapshot
        self.integrationPermissionSnapshot = integrationPermissionSnapshot
        self.watcherDiagnosticsSnapshotFactory = watcherDiagnosticsSnapshotFactory
        self.externalMCPSettingsViewModelFactory = externalMCPSettingsViewModelFactory
        self.syncSettingsViewModelFactory = syncSettingsViewModelFactory
        self.isGoogleCalendarRuntimeEnabled = isGoogleCalendarRuntimeEnabled
        self.googleCalendarStatusProvider = googleCalendarStatusProvider
        self.googleCalendarOAuthConnector = googleCalendarOAuthConnector
        self.googleCalendarOAuthDisconnecter = googleCalendarOAuthDisconnecter
        self.googleCalendarListProviderFactory = googleCalendarListProviderFactory
        self.textToSpeechPreviewerFactory = textToSpeechPreviewerFactory
        self.onboardingRerunRequest = onboardingRerunRequest
        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
        _shortcutSettingsViewModel = ObservedObject(wrappedValue: shortcutSettingsViewModel)
        _launchAtLoginViewModel = StateObject(wrappedValue: launchAtLoginViewModel)
        _watcherDiagnosticsLoader = StateObject(
            wrappedValue: LazyDependencyLoader(loadValue: watcherDiagnosticsSnapshotFactory)
        )
        _externalMCPSettingsViewModelLoader = StateObject(
            wrappedValue: LazyObservableObjectLoader(loadValue: externalMCPSettingsViewModelFactory)
        )
        _syncSettingsViewModelLoader = StateObject(
            wrappedValue: LazyObservableObjectLoader(loadValue: syncSettingsViewModelFactory)
        )
        _appearancePreference = appearancePreference
        _languagePreference = languagePreference
        _selectedTab = State(initialValue: initialTab)
        // The release evidence harness opens the MCP / Sync tabs directly via initialTab, so those
        // windows must keep the advanced tabs visible even when the persisted toggle is off.
        _forcesAdvancedTabsForInitialTab = State(initialValue: initialTab == .mcp || initialTab == .sync)
        _googleCalendarSyncStatus = State(initialValue: nil)
        _googleCalendarSetupMessage = State(initialValue: nil)
        _googleCalendarListProvider = State(wrappedValue: nil)
    }

    private var watcherDiagnosticsSnapshotForPrivacy: WatcherDiagnosticsSnapshot {
        watcherDiagnosticsLoader.value ?? watcherDiagnosticsSnapshot
    }

    private var externalMCPViewModel: ExternalMCPSettingsViewModel? {
        externalMCPSettingsViewModelLoader.value
    }

    private var syncViewModel: SyncSettingsViewModel? {
        syncSettingsViewModelLoader.value
    }

    private var showsAdvancedSettingsTabs: Bool {
        showAdvancedSettings || forcesAdvancedTabsForInitialTab
    }

    private var settingsOverviewDependencies: SettingsOverviewDependencies {
        let builder = SettingsOverviewProjectionBuilder(
            integrationPermissionSnapshot: integrationPermissionSnapshot,
            googleCalendarStatusProvider: googleCalendarStatusProvider,
            onboardingRerunRequest: onboardingRerunRequest,
            settingsViewModel: settingsViewModel,
            launchAtLoginViewModel: launchAtLoginViewModel,
            externalMCPSettingsViewModelLoader: externalMCPSettingsViewModelLoader,
            syncSettingsViewModelLoader: syncSettingsViewModelLoader,
            selectedTab: $selectedTab,
            googleCalendarSyncStatus: $googleCalendarSyncStatus,
            googleCalendarSetupMessage: $googleCalendarSetupMessage,
            showAdvancedSettings: $showAdvancedSettings
        )
        let syncStatusLabel = builder.syncViewModel?.statusLabel ?? "Set up when needed"
        let mcpStatusLabel = builder.externalMCPViewModel?.connectionCheckResultLabel ?? "Set up when needed"
        return SettingsOverviewDependencies(
            groups: SettingsReadinessPresentation.grouped(
                rows: builder.settingsReadinessRows(
                    syncStatusLabel: syncStatusLabel,
                    mcpStatusLabel: mcpStatusLabel
                ),
                showsAdvanced: showAdvancedSettings
            ),
            showAdvanced: $showAdvancedSettings,
            syncStatusLabel: syncStatusLabel,
            syncValueLabel: builder.syncPaidValueLabel,
            syncBoundaryLabel: builder.syncSafetyBoundaryLabel,
            syncTone: builder.syncOverviewTone,
            mcpStatusLabel: builder.mcpExecutionStatusLabel,
            mcpValueLabel: builder.mcpExecutionValueLabel,
            mcpBoundaryLabel: builder.mcpExecutionSafetyBoundaryLabel,
            mcpTone: builder.mcpExecutionTone,
            performReadinessAction: builder.performSettingsReadinessAction,
            rerunOnboarding: onboardingRerunRequest
        )
    }

    private var settingsAppearanceDependencies: SettingsAppearanceDependencies {
        SettingsAppearanceDependencies(
            appearancePreference: $appearancePreference,
            languagePreference: $languagePreference
        )
    }

    private var settingsAIDependencies: SettingsAIDependencies {
        SettingsAIDependencies(
            shortcutSettingsViewModel: shortcutSettingsViewModel,
            makeTextToSpeechPreviewer: { [settingsViewModel, textToSpeechPreviewerFactory] in
                textToSpeechPreviewerFactory(settingsViewModel.settings)
            }
        )
    }

    private var settingsSyncDependencies: SettingsSyncDependencies {
        let builder = SettingsSyncProjectionBuilder(
            googleCalendarStatusProvider: googleCalendarStatusProvider,
            googleCalendarOAuthConnector: googleCalendarOAuthConnector,
            googleCalendarOAuthDisconnecter: googleCalendarOAuthDisconnecter,
            settingsViewModel: settingsViewModel,
            syncSettingsViewModelLoader: syncSettingsViewModelLoader,
            isConfirmingGoogleCalendarOAuthDisconnect: $isConfirmingGoogleCalendarOAuthDisconnect,
            googleCalendarSyncStatus: $googleCalendarSyncStatus,
            googleCalendarSetupMessage: $googleCalendarSetupMessage,
            isGoogleCalendarOAuthAuthorizationInProgress: $isGoogleCalendarOAuthAuthorizationInProgress,
            googleCalendarListProvider: $googleCalendarListProvider,
            isLoadingGoogleCalendarList: $isLoadingGoogleCalendarList,
            googleCalendarListOptions: $googleCalendarListOptions,
            googleCalendarListLoadGeneration: $googleCalendarListLoadGeneration
        )
        let loadState: SettingsFeatureLoadState<SyncSettingsViewModel>
        if let viewModel = syncSettingsViewModelLoader.value {
            loadState = .loaded(viewModel)
        } else if syncSettingsViewModelLoader.isLoading {
            loadState = .loading
        } else {
            loadState = .unavailable
        }
        return SettingsSyncDependencies(
            loadState: loadState,
            isGoogleCalendarRuntimeEnabled: isGoogleCalendarRuntimeEnabled,
            syncPaidValueLabel: builder.syncPaidValueLabel,
            syncSafetyBoundaryLabel: builder.syncSafetyBoundaryLabel,
            syncOverviewTone: builder.syncOverviewTone,
            googleCalendarListOptions: googleCalendarListOptions,
            shouldShowCurrentGoogleCalendarManualOption: builder.shouldShowCurrentGoogleCalendarManualOption,
            googleCalendarManualCalendarLabel: builder.googleCalendarManualCalendarLabel,
            googleCalendarPickerLabel: builder.googleCalendarPickerLabel,
            isLoadingGoogleCalendarList: isLoadingGoogleCalendarList,
            canLoadGoogleCalendarList: !isLoadingGoogleCalendarList && !isGoogleCalendarOAuthAuthorizationInProgress && googleCalendarListProvider != nil,
            googleCalendarSettingsReadinessRow: builder.googleCalendarSettingsReadinessRow,
            googleCalendarSettingsTone: builder.googleCalendarSettingsTone,
            googleCalendarOAuthActionLabel: builder.googleCalendarOAuthActionLabel,
            canStartGoogleCalendarOAuthAuthorization: !isGoogleCalendarOAuthAuthorizationInProgress && googleCalendarOAuthConnector != nil,
            canDisconnectGoogleCalendarOAuthAuthorization: !isGoogleCalendarOAuthAuthorizationInProgress && googleCalendarOAuthDisconnecter != nil,
            hiddenConnectorPolicySummary: builder.hiddenConnectorPolicySummary,
            isConfirmingGoogleCalendarOAuthDisconnect: $isConfirmingGoogleCalendarOAuthDisconnect,
            googleCalendarSetupMessage: $googleCalendarSetupMessage,
            saveGoogleCalendarIDSetting: builder.saveGoogleCalendarIDSetting,
            loadGoogleCalendarList: builder.loadGoogleCalendarList,
            refreshGoogleCalendarSettingsStatus: builder.refreshGoogleCalendarSettingsStatus,
            startGoogleCalendarOAuthAuthorization: builder.startGoogleCalendarOAuthAuthorization,
            disconnectGoogleCalendarOAuthAuthorization: builder.disconnectGoogleCalendarOAuthAuthorization
        )
    }

    private var settingsPrivacyDependencies: SettingsPrivacyDependencies {
        let builder = SettingsPrivacyProjectionBuilder(
            settingsViewModel: settingsViewModel,
            launchAtLoginViewModel: launchAtLoginViewModel,
            watcherDiagnosticsLoader: watcherDiagnosticsLoader,
            pendingBackupRestoreDocument: $pendingBackupRestoreDocument,
            isConfirmingBackupRestore: $isConfirmingBackupRestore,
            backupStatusMessage: $backupStatusMessage,
            backupErrorMessage: $backupErrorMessage,
            diagnosticsExportErrorMessage: $diagnosticsExportErrorMessage
        )
        let diagnosticsLoadState: SettingsFeatureLoadState<WatcherDiagnosticsSnapshot>
        if let snapshot = watcherDiagnosticsLoader.value {
            diagnosticsLoadState = .loaded(snapshot)
        } else if watcherDiagnosticsLoader.isLoading {
            diagnosticsLoadState = .loading
        } else {
            diagnosticsLoadState = .unavailable
        }
        return SettingsPrivacyDependencies(
            launchAtLoginEnabled: launchAtLoginViewModel.isEnabled,
            canToggleLaunchAtLogin: launchAtLoginViewModel.canToggle,
            launchAtLoginStatusLabel: launchAtLoginViewModel.statusLabel,
            launchAtLoginStatusDetail: launchAtLoginViewModel.statusDetail,
            launchAtLoginErrorMessage: launchAtLoginViewModel.errorMessage,
            setLaunchAtLoginEnabled: launchAtLoginViewModel.setEnabled,
            dataLocationOverviewStatusLabel: builder.dataLocationOverviewStatusLabel,
            diagnosticsLoadState: diagnosticsLoadState,
            pendingBackupRestoreDocument: $pendingBackupRestoreDocument,
            isConfirmingBackupRestore: $isConfirmingBackupRestore,
            backupStatusMessage: $backupStatusMessage,
            backupErrorMessage: $backupErrorMessage,
            diagnosticsExportErrorMessage: $diagnosticsExportErrorMessage,
            backupRestoreConfirmationMessage: builder.backupRestoreConfirmationMessage,
            presentBackupExportPanel: builder.presentBackupExportPanel,
            presentBackupRestorePanel: builder.presentBackupRestorePanel,
            presentDiagnosticsExportPanel: builder.presentDiagnosticsExportPanel,
            applyPendingBackupRestore: builder.applyPendingBackupRestore
        )
    }

    private var settingsMCPDependencies: SettingsMCPDependencies {
        let loadState: SettingsFeatureLoadState<ExternalMCPSettingsViewModel>
        if let viewModel = externalMCPSettingsViewModelLoader.value {
            loadState = .loaded(viewModel)
        } else if externalMCPSettingsViewModelLoader.isLoading {
            loadState = .loading
        } else {
            loadState = .unavailable
        }
        let plan = syncSettingsViewModelLoader.value
        let requiredPlan = FeatureGate.advancedMCPExecution.requiredPlan.displayName
        let isExecutionAllowed = plan?.status.plan.allows(.advancedMCPExecution) == true
        return SettingsMCPDependencies(
            loadState: loadState,
            planLabel: plan?.planLabel ?? "Unavailable",
            mcpExecutionStatusLabel: isExecutionAllowed ? "Execution unlocked" : "Execution gated",
            mcpExecutionValueLabel: isExecutionAllowed
                ? localizedDisplay("Advanced MCP tools can execute on %@.", plan?.planLabel ?? requiredPlan)
                : localizedDisplay("%@ is required before external MCP tools can execute.", requiredPlan),
            mcpExecutionSafetyBoundaryLabel: "Register and Check stay available; tools/call still requires entitlement, tool policy, and approval.",
            mcpExecutionTone: isExecutionAllowed ? .ready : .warning,
            isConfirmingMCPRegistrationDeletion: $isConfirmingMCPRegistrationDeletion
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsOverviewFeatureView(
                dependencies: settingsOverviewDependencies
            )
                .tabItem { Label("Overview", systemImage: "gauge.with.dots.needle.bottom.50percent") }
                .tag(SettingsTab.overview)

SettingsAppearanceFeatureView(context: settingsAppearanceDependencies)
                .tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }
                .tag(SettingsTab.appearance)

SettingsAIFeatureView(
                settingsViewModel: settingsViewModel,
                context: settingsAIDependencies
            )
                .tabItem { Label("AI", systemImage: "brain.head.profile") }
                .tag(SettingsTab.ai)

            if showsAdvancedSettingsTabs {
SettingsMCPFeatureView(
                    settingsViewModel: settingsViewModel,
                    context: settingsMCPDependencies
                )
                    .tabItem { Label("MCP", systemImage: "externaldrive.connected.to.line.below") }
                    .tag(SettingsTab.mcp)

SettingsSyncFeatureView(
                    settingsViewModel: settingsViewModel,
                    context: settingsSyncDependencies
                )
                    .tabItem { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(SettingsTab.sync)
            }

SettingsPrivacyFeatureView(
                settingsViewModel: settingsViewModel,
                context: settingsPrivacyDependencies
            )
                .tabItem { Label("Privacy", systemImage: "lock.shield") }
                .tag(SettingsTab.privacy)
        }
        .frame(width: 680, height: 584)
        .scenePadding()
        .onAppear {
            launchAtLoginViewModel.refresh()
            requestRuntimeDependencies(for: selectedTab)
        }
        .onChange(of: selectedTab) { _, tab in
            requestRuntimeDependencies(for: tab)
        }
        .onChange(of: showAdvancedSettings) { _, isAdvancedVisible in
            if !isAdvancedVisible,
               !forcesAdvancedTabsForInitialTab,
               selectedTab == .mcp || selectedTab == .sync {
                selectedTab = .overview
            }
        }
        .confirmationDialog(
            "Delete MCP Server",
            isPresented: $isConfirmingMCPRegistrationDeletion
        ) {
            Button("Delete", role: .destructive) {
                externalMCPViewModel?.deleteRegistration()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the saved registration from Suisui.")
        }
        .confirmationDialog(
            "Disconnect Google Calendar",
            isPresented: $isConfirmingGoogleCalendarOAuthDisconnect
        ) {
            Button("Disconnect", role: .destructive) {
settingsSyncDependencies.disconnectGoogleCalendarOAuthAuthorization()
            }
            .accessibilityIdentifier("settings-google-calendar-oauth-disconnect-confirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local Google Calendar OAuth tokens from Keychain. Tasks and saved calendar ID stay unchanged.")
        }
    }

    private func requestRuntimeDependencies(for tab: SettingsTab) {
        switch tab {
        case .mcp:
            // MCP audit/history needs sqlite/opened stores; load only when the tab is visible.
            externalMCPSettingsViewModelLoader.loadIfNeeded()
        case .sync:
            // Google Calendar sync tooling and list provider are not needed until the sync tab opens.
            syncSettingsViewModelLoader.loadIfNeeded()
            prepareGoogleCalendarListProviderIfNeeded()
        case .privacy:
            // Watcher diagnostics are a best-effort status surface; keep shell paint first.
            watcherDiagnosticsLoader.loadIfNeeded()
        default:
            break
        }
    }

    private func prepareGoogleCalendarListProviderIfNeeded() {
        guard googleCalendarListProvider == nil, hasLoadedCalendarListProvider == false else {
            return
        }
        hasLoadedCalendarListProvider = true

        Task { @MainActor in
            await Task.yield()
            googleCalendarListProvider = googleCalendarListProviderFactory()
        }
    }

}

@MainActor
struct SettingsOverviewProjectionBuilder {
    let integrationPermissionSnapshot: PermissionSnapshot
    let googleCalendarStatusProvider: () -> GoogleCalendarRuntimeSyncStatus
    let onboardingRerunRequest: () -> Void
    let settingsViewModel: AppSettingsViewModel
    let launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    let externalMCPSettingsViewModelLoader: LazyObservableObjectLoader<ExternalMCPSettingsViewModel>
    let syncSettingsViewModelLoader: LazyObservableObjectLoader<SyncSettingsViewModel>
    @Binding var selectedTab: SettingsTab
    @Binding var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus?
    @Binding var googleCalendarSetupMessage: String?
    @Binding var showAdvancedSettings: Bool

    var externalMCPViewModel: ExternalMCPSettingsViewModel? {
        externalMCPSettingsViewModelLoader.value
    }

    var syncViewModel: SyncSettingsViewModel? {
        syncSettingsViewModelLoader.value
    }


    func settingsReadinessRows(
        syncStatusLabel: String,
        mcpStatusLabel: String
    ) -> [SettingsReadinessRow] {
        var rows = [
            SettingsReadinessPresentation.aiProviderCapability(
                id: "ai",
                title: "AI Provider",
                detail: localizedDisplay(
                    "%@: %@",
                    settingsViewModel.settings.aiProvider.displayName,
                    activeAIProviderStatusLabel
                ),
                statusLabel: activeAIProviderStatusLabel,
                readiness: activeAIProviderReadinessRow.readiness
            ),
            SettingsReadinessPresentation.voiceProviderCapability(
                id: "stt",
                title: "STT",
                detail: sttOverviewDetailLabel,
                statusLabel: settingsViewModel.localSTTProviderReadinessRow.statusLabel
            ),
            SettingsReadinessPresentation.voiceProviderCapability(
                id: "tts",
                title: "TTS",
                detail: ttsOverviewDetailLabel,
                statusLabel: settingsViewModel.ttsProviderReadinessRow.statusLabel
            ),
            permissionReadinessRow(
                id: "calendar",
                title: "Calendar",
                status: integrationPermissionSnapshot.status(for: .calendar),
                detail: calendarOverviewDetailLabel
            ),
            permissionReadinessRow(
                id: "reminders",
                title: "Reminder",
                status: integrationPermissionSnapshot.status(for: .reminders),
                detail: reminderOverviewDetailLabel
            ),
            permissionReadinessRow(
                id: "notifications",
                title: "Notifications",
                status: integrationPermissionSnapshot.status(for: .notifications),
                detail: PermissionDisplayPolicy.label(
                    for: integrationPermissionSnapshot.status(for: .notifications)
                )
            ),
            googleCalendarOverviewReadinessRow,
            readinessRow(
                id: "privacy",
                title: "Privacy",
                detail: localizedDisplay(
                    "Login Item: %@",
                    localizedSettingsDisplay(launchAtLoginViewModel.statusLabel)
                ),
                tone: privacyOverviewTone,
                action: .openPrivacy
            ),
            readinessRow(
                id: "data-location",
                title: "Data Location",
                detail: dataLocationOverviewDetailLabel,
                tone: dataLocationOverviewTone,
                action: .openPrivacy
            )
        ]

        if showAdvancedSettings {
            rows.append(advancedReadinessRow(
                id: "mcp",
                title: "MCP",
                detail: mcpStatusLabel,
                tone: mcpOverviewTone,
                action: .openMCP
            ))
            rows.append(advancedReadinessRow(
                id: "sync",
                title: "Sync",
                detail: syncStatusLabel,
                tone: syncOverviewTone,
                action: .openSync
            ))
        }
        return rows
    }

    func readinessRow(
        id: String,
        title: String,
        detail: String,
        tone: SettingsStatusTone,
        action: SettingsReadinessAction
    ) -> SettingsReadinessRow {
        switch tone {
        case .ready:
            SettingsReadinessPresentation.readyCapability(
                id: id,
                title: title,
                detail: detail,
                action: action
            )
        case .danger:
            SettingsReadinessPresentation.failedCapability(
                id: id,
                title: title,
                redactedReason: detail,
                action: action
            )
        case .warning, .neutral:
            SettingsReadinessPresentation.capability(
                id: id,
                title: title,
                detail: detail,
                state: .setupWhenNeeded,
                action: action
            )
        }
    }

    func permissionReadinessRow(
        id: String,
        title: String,
        status: PermissionStatus,
        detail: String
    ) -> SettingsReadinessRow {
        switch status {
        case .granted:
            SettingsReadinessPresentation.readyCapability(
                id: id,
                title: title,
                detail: detail,
                action: .openSync
            )
        case .notDetermined:
            SettingsReadinessPresentation.capability(
                id: id,
                title: title,
                detail: detail,
                state: .setupWhenNeeded,
                action: .openSync
            )
        case .denied:
            SettingsReadinessPresentation.capability(
                id: id,
                title: title,
                detail: detail,
                state: .blocked,
                action: .openSync
            )
        case .restricted:
            SettingsReadinessPresentation.capability(
                id: id,
                title: title,
                detail: detail,
                state: .unsupported,
                action: .openSync
            )
        }
    }

    var googleCalendarOverviewReadinessRow: SettingsReadinessRow {
        guard let status = googleCalendarSyncStatus else {
            return SettingsReadinessPresentation.capability(
                id: "google-calendar",
                title: "Google Calendar",
                detail: googleCalendarSettingsReadinessRow.detailLabel,
                state: .checking,
                action: .retry(featureID: "google-calendar")
            )
        }

        switch status.state {
        case .ready:
            return SettingsReadinessPresentation.readyCapability(
                id: "google-calendar",
                title: "Google Calendar",
                detail: status.detailLabel,
                action: .openSync
            )
        case .calendarNotConfigured, .oauthDisconnected:
            return SettingsReadinessPresentation.capability(
                id: "google-calendar",
                title: "Google Calendar",
                detail: status.detailLabel,
                state: .setupWhenNeeded,
                action: .openSync
            )
        case .upgradeRequired, .runtimeNotConfigured:
            return SettingsReadinessPresentation.capability(
                id: "google-calendar",
                title: "Google Calendar",
                detail: status.detailLabel,
                state: .unsupported,
                action: .openSync
            )
        case .invalidCalendarID:
            return SettingsReadinessPresentation.capability(
                id: "google-calendar",
                title: "Google Calendar",
                detail: status.detailLabel,
                state: .blocked,
                action: .openSync
            )
        case .missingRequiredScope, .tokenExpiredWithoutRefresh, .failed:
            return SettingsReadinessPresentation.failedCapability(
                id: "google-calendar",
                title: "Google Calendar",
                redactedReason: status.detailLabel,
                action: .retry(featureID: "google-calendar")
            )
        }
    }

    func advancedReadinessRow(
        id: String,
        title: String,
        detail: String,
        tone: SettingsStatusTone,
        action: SettingsReadinessAction
    ) -> SettingsReadinessRow {
        let row = readinessRow(id: id, title: title, detail: detail, tone: tone, action: action)
        return SettingsReadinessRow(
            id: row.id,
            title: row.title,
            detail: row.detail,
            state: row.state,
            group: .advanced,
            action: row.action
        )
    }

    func performSettingsReadinessAction(_ action: SettingsReadinessAction) {
        switch action {
        case .openAI:
            selectedTab = .ai
        case .openPrivacy:
            selectedTab = .privacy
        case .showAdvanced:
            showAdvancedSettings = true
        case .openMCP:
            showAdvancedSettings = true
            selectedTab = .mcp
        case .openSync:
            showAdvancedSettings = true
            selectedTab = .sync
        case .retry(let featureID):
            if featureID == "google-calendar" {
                refreshGoogleCalendarSettingsStatus()
                showAdvancedSettings = true
                selectedTab = .sync
            } else if ["calendar", "reminders", "notifications", "sync"].contains(featureID) {
                showAdvancedSettings = true
                selectedTab = .sync
            } else if featureID == "mcp" {
                showAdvancedSettings = true
                selectedTab = .mcp
            } else {
                selectedTab = featureID == "privacy" || featureID == "data-location" ? .privacy : .ai
            }
        }
    }



    var activeAIProviderReadinessRow: AIProviderReadinessRow {
        settingsViewModel.providerReadinessRow(for: settingsViewModel.settings.aiProvider)
    }

    var activeAIProviderStatusLabel: String {
        activeAIProviderReadinessRow.statusLabel
    }

    var sttOverviewDetailLabel: String {
        localizedDisplay(
            "Local whisper.cpp: %@",
            localizedSettingsDisplay(settingsViewModel.localSTTProviderReadinessRow.statusLabel)
        )
    }

    var ttsOverviewDetailLabel: String {
        settingsViewModel.ttsProviderReadinessRow.statusLabel
    }

    var googleCalendarSettingsReadinessRow: GoogleCalendarSettingsReadinessRow {
        GoogleCalendarSettingsReadinessRow(status: googleCalendarSyncStatus)
    }

    func refreshGoogleCalendarSettingsStatus() {
        googleCalendarSetupMessage = nil
        googleCalendarSyncStatus = googleCalendarStatusProvider()
    }

    var calendarOverviewDetailLabel: String {
        integrationOverviewDetailLabel(
            for: integrationPermissionSnapshot.status(for: .calendar),
            serviceName: "Calendar"
        )
    }

    var reminderOverviewDetailLabel: String {
        integrationOverviewDetailLabel(
            for: integrationPermissionSnapshot.status(for: .reminders),
            serviceName: "Reminder"
        )
    }

    var dataLocationOverviewDetailLabel: String {
        if settingsViewModel.settings.validate().contains(where: { $0.field == "defaultWorkspacePath" }) {
            return "Choose an absolute folder path."
        }
        guard let path = settingsViewModel.settings.defaultWorkspacePath else {
            return "No custom workspace path configured."
        }
        return localizedDisplay("Folder: %@", URL(fileURLWithPath: path).lastPathComponent)
    }

    var dataLocationOverviewTone: SettingsStatusTone {
        if settingsViewModel.settings.validate().contains(where: { $0.field == "defaultWorkspacePath" }) {
            return .danger
        }
        // The app container is already a valid local-first data location. Treating
        // the absence of a custom folder as incomplete would turn a safe default
        // into setup work that the user never requested.
        return .ready
    }

    func tone(for row: AIProviderReadinessRow) -> SettingsStatusTone {
        switch row.statusLabel {
        case "Configured", "Approved", "Local":
            return .ready
        case "Invalid", "Unavailable":
            return .danger
        default:
            return .warning
        }
    }

    var mcpOverviewTone: SettingsStatusTone {
        guard let externalMCPViewModel else {
            return .neutral
        }

        if externalMCPViewModel.connectionCheckResultLabel == "Connected" {
            return .ready
        }
        if externalMCPViewModel.connectionCheckResultLabel.hasPrefix("Failed") {
            return .danger
        }
        return externalMCPViewModel.display.isEnabled ? .warning : .neutral
    }

    func integrationOverviewDetailLabel(for status: PermissionStatus, serviceName: String) -> String {
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

    var syncStatusLabelForOverview: String {
        syncViewModel?.statusLabel ?? "Unavailable"
    }

    var mcpExecutionStatusLabel: String {
        guard let syncViewModel else {
            return "Execution gated"
        }

        return syncViewModel.status.plan.allows(.advancedMCPExecution) ? "Execution unlocked" : "Execution gated"
    }

    var mcpExecutionValueLabel: String {
        let requiredPlan = FeatureGate.advancedMCPExecution.requiredPlan.displayName
        guard let syncViewModel else {
            return localizedDisplay("%@ is required before external MCP tools can execute.", requiredPlan)
        }

        if syncViewModel.status.plan.allows(.advancedMCPExecution) {
            return localizedDisplay("Advanced MCP tools can execute on %@.", syncViewModel.planLabel)
        }
        return localizedDisplay("%@ is required before external MCP tools can execute.", requiredPlan)
    }

    var mcpExecutionSafetyBoundaryLabel: String {
        "Register and Check stay available; tools/call still requires entitlement, tool policy, and approval."
    }

    var mcpExecutionTone: SettingsStatusTone {
        guard let syncViewModel else {
            return .warning
        }

        return syncViewModel.status.plan.allows(.advancedMCPExecution) ? .ready : .warning
    }

    var syncOverviewTone: SettingsStatusTone {
        switch syncStatusLabelForOverview {
        case "Ready", "Syncing":
            .ready
        case "Failed":
            .danger
        default:
            .warning
        }
    }

    var syncPaidValueLabel: String {
        switch syncStatusLabelForOverview {
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

    var syncSafetyBoundaryLabel: String {
        switch syncStatusLabelForOverview {
        case "Ready", "Syncing":
            "Only selected Suisui data classes are included."
        case "Sync backend is not configured":
            "No upload starts while the backend is missing."
        case "Upgrade required":
            "Free stays local. No data leaves this Mac."
        default:
            "Sync fails closed before external communication."
        }
    }

    var privacyOverviewTone: SettingsStatusTone {
        // Privacy readiness describes the local/Keychain boundary, while
        // notification permission has its own row and must not redefine privacy.
        .ready
    }

}

@MainActor
struct SettingsSyncProjectionBuilder {
    let googleCalendarStatusProvider: () -> GoogleCalendarRuntimeSyncStatus
    let googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?
    let googleCalendarOAuthDisconnecter: (any GoogleCalendarOAuthDisconnecting)?
    let settingsViewModel: AppSettingsViewModel
    let syncSettingsViewModelLoader: LazyObservableObjectLoader<SyncSettingsViewModel>
    @Binding var isConfirmingGoogleCalendarOAuthDisconnect: Bool
    @Binding var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus?
    @Binding var googleCalendarSetupMessage: String?
    @Binding var isGoogleCalendarOAuthAuthorizationInProgress: Bool
    @Binding var googleCalendarListProvider: (any GoogleCalendarListProviding)?
    @Binding var isLoadingGoogleCalendarList: Bool
    @Binding var googleCalendarListOptions: [GoogleCalendarRuntimeCalendarListEntry]
    @Binding var googleCalendarListLoadGeneration: Int
    var syncViewModel: SyncSettingsViewModel? {
        syncSettingsViewModelLoader.value
    }




    func settingsLazyLoadUnavailableHint(message: String) -> some View {
        Label(message, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityIdentifier("settings-tab-lazy-load-hint")
    }

    var googleCalendarSettingsReadinessRow: GoogleCalendarSettingsReadinessRow {
        GoogleCalendarSettingsReadinessRow(status: googleCalendarSyncStatus)
    }

    var googleCalendarSettingsTone: SettingsStatusTone {
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

    var hiddenConnectorPolicySummary: String {
        let hiddenCount = ExternalConnectorExposurePolicy.all.count - ExternalConnectorExposurePolicy.settingsVisible.count
        let draftOnlyCount = ExternalConnectorExposurePolicy.assistantQueueDraftOnly.count
        return String(localized: "\(hiddenCount) connector policies stay out of Settings until connect, check, revoke, and audit UI is complete. \(draftOnlyCount) connector send paths remain Assistant Queue draft-only.")
    }

    var googleCalendarOAuthActionLabel: String {
        switch googleCalendarSyncStatus?.state {
        case .missingRequiredScope, .tokenExpiredWithoutRefresh:
            return "Reconnect with OAuth authorization"
        default:
            return "Connect with OAuth authorization"
        }
    }

    func refreshGoogleCalendarSettingsStatus() {
        googleCalendarSetupMessage = nil
        googleCalendarSyncStatus = googleCalendarStatusProvider()
    }

    func saveGoogleCalendarIDSetting() {
        settingsViewModel.saveSettings()
        guard settingsViewModel.errorMessage == nil else {
            return
        }
        refreshGoogleCalendarSettingsStatus()
    }

    func loadGoogleCalendarList() {
        guard !isGoogleCalendarOAuthAuthorizationInProgress else {
            googleCalendarSetupMessage = "Wait for Google Calendar OAuth authorization to finish before loading calendars."
            return
        }
        guard let googleCalendarListProvider else {
            googleCalendarSetupMessage = "Google Calendar list is not available in this build."
            return
        }

        googleCalendarListLoadGeneration += 1
        let generation = googleCalendarListLoadGeneration
        isLoadingGoogleCalendarList = true
        googleCalendarSetupMessage = "Loading Google Calendars."
        Task {
            do {
                let options = try await Task.detached(priority: .userInitiated) {
                    try googleCalendarListProvider.listWritableCalendars()
                }.value
                guard generation == googleCalendarListLoadGeneration else {
                    return
                }
                googleCalendarListOptions = options
                if options.isEmpty {
                    googleCalendarSetupMessage = "No writable Google Calendars were returned."
                } else {
                    googleCalendarSetupMessage = "Google Calendar list loaded. Choose a calendar, then save."
                }
            } catch {
                guard generation == googleCalendarListLoadGeneration else {
                    return
                }
                googleCalendarSetupMessage = googleCalendarListFailureMessage(from: error)
            }
            isLoadingGoogleCalendarList = false
        }
    }

    func invalidateGoogleCalendarListOptions() {
        googleCalendarListLoadGeneration += 1
        googleCalendarListOptions = []
        isLoadingGoogleCalendarList = false
    }

    func disconnectGoogleCalendarOAuthAuthorization() {
        guard let googleCalendarOAuthDisconnecter else {
            googleCalendarSetupMessage = "Google Calendar OAuth disconnect is not available in this build."
            return
        }

        do {
            invalidateGoogleCalendarListOptions()
            try googleCalendarOAuthDisconnecter.disconnect()
            googleCalendarSetupMessage = "Google Calendar OAuth disconnected. Tokens were removed from Keychain."
            googleCalendarSyncStatus = googleCalendarStatusProvider()
            NotificationCenter.default.post(name: .suisuiGoogleCalendarReadinessDidChange, object: nil)
        } catch {
            googleCalendarSetupMessage = UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: "Google Calendar OAuth disconnect failed."
            )
        }
    }

    var shouldShowCurrentGoogleCalendarManualOption: Bool {
        let currentID = settingsViewModel.settings.googleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentID.isEmpty == false else {
            return false
        }
        return !googleCalendarListOptions.contains { $0.id == currentID }
    }

    var googleCalendarManualCalendarLabel: String {
        String(format: localizedSettingsDisplay("Current manual ID: %@"), settingsViewModel.settings.googleCalendarID)
    }

    func googleCalendarPickerLabel(for option: GoogleCalendarRuntimeCalendarListEntry) -> String {
        if option.isPrimary {
            return String(format: localizedSettingsDisplay("%@ (Primary calendar)"), option.summary)
        }
        return option.summary
    }

    func startGoogleCalendarOAuthAuthorization() {
        guard let googleCalendarOAuthConnector else {
            googleCalendarSetupMessage = "Google Calendar OAuth authorization is not available in this build."
            return
        }

        invalidateGoogleCalendarListOptions()
        isGoogleCalendarOAuthAuthorizationInProgress = true
        googleCalendarSetupMessage = "OAuth authorization opens in the system browser with PKCE. Tokens stay in Keychain before calendar writes are enabled."
        googleCalendarOAuthConnector.startAuthorization { result in
            isGoogleCalendarOAuthAuthorizationInProgress = false
            switch result {
            case .success:
                googleCalendarSetupMessage = "Google Calendar OAuth authorization completed. Check Status to refresh readiness."
                googleCalendarSyncStatus = googleCalendarStatusProvider()
                NotificationCenter.default.post(name: .suisuiGoogleCalendarReadinessDidChange, object: nil)
            case .failure(let error):
                googleCalendarSetupMessage = googleCalendarOAuthFailureMessage(from: error)
            }
        }
    }

    func googleCalendarListFailureMessage(from error: Error) -> String {
        if let runtimeError = error as? GoogleCalendarRuntimeError {
            switch runtimeError {
            case .disconnected:
                return "Connect Google Calendar with OAuth before loading calendars."
            case .missingRequiredScope(let scope):
                if scope == GoogleCalendarRuntimeOAuthScope.calendarListReadOnly {
                    return "Reconnect Google Calendar with OAuth before loading calendars."
                }
                return "Google Calendar OAuth is missing the required \(scope) scope."
            default:
                break
            }
        }
        return UserFacingErrorMessageSanitizer.message(
            from: error,
            fallback: "Google Calendar list could not be loaded."
        )
    }

    func googleCalendarOAuthFailureMessage(from error: Error) -> String {
        if let authorizationError = error as? GoogleCalendarOAuthAuthorizationError {
            switch authorizationError {
            case .missingClientID:
                return "Google Calendar OAuth client ID is not configured. Set SUISUI_GOOGLE_CALENDAR_OAUTH_CLIENT_ID or SuisuiGoogleCalendarOAuthClientID before connecting."
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

    var syncStatusLabelForOverview: String {
        syncViewModel?.statusLabel ?? "Unavailable"
    }

    var syncOverviewTone: SettingsStatusTone {
        switch syncStatusLabelForOverview {
        case "Ready", "Syncing":
            .ready
        case "Failed":
            .danger
        default:
            .warning
        }
    }

    var syncPaidValueLabel: String {
        switch syncStatusLabelForOverview {
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

    var syncSafetyBoundaryLabel: String {
        switch syncStatusLabelForOverview {
        case "Ready", "Syncing":
            "Only selected Suisui data classes are included."
        case "Sync backend is not configured":
            "No upload starts while the backend is missing."
        case "Upgrade required":
            "Free stays local. No data leaves this Mac."
        default:
            "Sync fails closed before external communication."
        }
    }

}

@MainActor
struct SettingsPrivacyProjectionBuilder {
    let settingsViewModel: AppSettingsViewModel
    let launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    let watcherDiagnosticsLoader: LazyDependencyLoader<WatcherDiagnosticsSnapshot>
    @Binding var pendingBackupRestoreDocument: WorkspaceBackupDocument?
    @Binding var isConfirmingBackupRestore: Bool
    @Binding var backupStatusMessage: String?
    @Binding var backupErrorMessage: String?
    @Binding var diagnosticsExportErrorMessage: String?
    var backupRestoreConfirmationMessage: String {
        guard let document = pendingBackupRestoreDocument else {
            return ""
        }
        return localizedDisplay(
            "Restore is additive: %d projects, %d tasks, and %d knowledge frames are added as new items. Existing data is never changed or deleted.",
            document.projects.count,
            document.tasks.count,
            document.knowledgeFrames.count
        )
    }

    var defaultBackupFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Suisui-Backup-\(formatter.string(from: Date())).json"
    }

    func presentBackupExportPanel() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultBackupFilename
        panel.prompt = String(localized: "Back Up")
        panel.message = String(localized: "Choose where to save the Suisui backup file")
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            DispatchQueue.main.async {
                exportBackup(to: url)
            }
        }
        #endif
    }

    func exportBackup(to url: URL) {
        do {
            let document = try AppRuntimeFactory.makeWorkspaceBackupExporter().export()
            try WorkspaceBackupCoding.encode(document).write(to: url, options: [.atomic])
            backupErrorMessage = nil
            backupStatusMessage = localizedDisplay(
                "Backed up %d projects, %d tasks, and %d knowledge frames.",
                document.projects.count,
                document.tasks.count,
                document.knowledgeFrames.count
            )
        } catch {
            backupStatusMessage = nil
            // Name the file so the inline error is actionable; the buttons
            // above stay in place for an immediate retry.
            backupErrorMessage = localizedDisplay(
                "Could not write backup file %@: %@",
                url.lastPathComponent,
                error.localizedDescription
            )
        }
    }

    var defaultDiagnosticsFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return "suisui-diagnostics-\(formatter.string(from: Date())).txt"
    }

    func presentDiagnosticsExportPanel() {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = defaultDiagnosticsFilename
        panel.prompt = String(localized: "Export")
        panel.message = String(localized: "Choose where to save the Suisui diagnostics report")
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            DispatchQueue.main.async {
                exportDiagnostics(to: url)
            }
        }
        #endif
    }

    func exportDiagnostics(to url: URL) {
        do {
            let report = AppRuntimeFactory.makeDiagnosticsReportText()
            try Data(report.utf8).write(to: url, options: [.atomic])
            diagnosticsExportErrorMessage = nil
        } catch {
            diagnosticsExportErrorMessage = error.localizedDescription
        }
    }

    func presentBackupRestorePanel() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = String(localized: "Choose")
        panel.message = String(localized: "Choose a Suisui backup file to restore")
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }
            DispatchQueue.main.async {
                loadBackupForRestore(from: url)
            }
        }
        #endif
    }

    func loadBackupForRestore(from url: URL) {
        do {
            let document = try WorkspaceBackupCoding.decode(try Data(contentsOf: url))
            pendingBackupRestoreDocument = document
            backupErrorMessage = nil
            // Counts are confirmed in the dialog before any row is written.
            isConfirmingBackupRestore = true
        } catch {
            pendingBackupRestoreDocument = nil
            backupStatusMessage = nil
            // Decoding errors alone do not mention the chosen file; name it so
            // the user knows which file failed and can retry in place.
            backupErrorMessage = localizedDisplay(
                "Could not read backup file %@: %@",
                url.lastPathComponent,
                error.localizedDescription
            )
        }
    }

    func applyPendingBackupRestore() {
        guard let document = pendingBackupRestoreDocument else {
            return
        }
        pendingBackupRestoreDocument = nil
        do {
            let summary = try AppRuntimeFactory.makeWorkspaceBackupImporter().restore(document, mode: .merge)
            backupErrorMessage = nil
            backupStatusMessage = localizedDisplay(
                "Restored %d projects, %d tasks, and %d knowledge frames. Skipped %d duplicate frames.",
                summary.projectsCreated,
                summary.tasksCreated,
                summary.framesCreated,
                summary.framesSkipped
            )
            AppRuntimeFactory.postProjectBoardDidChange()
        } catch {
            backupStatusMessage = nil
            backupErrorMessage = error.localizedDescription
        }
    }


    var settingsSaveButton: some View {
        Button {
            settingsViewModel.saveSettings()
        } label: {
            Label("Save Settings", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("settings-save-button")
        .accessibilityHint("Persists non-secret settings to local UserDefaults.")
    }

    func quietHoursMinuteOfDayBinding(
        get minuteOfDay: @escaping () -> Int,
        set: @escaping (Int) -> Void
    ) -> Binding<Date> {
        Binding(
            get: {
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: Date())
                return calendar.date(byAdding: .minute, value: minuteOfDay(), to: dayStart) ?? dayStart
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                set((components.hour ?? 0) * 60 + (components.minute ?? 0))
            }
        )
    }

    var dataLocationOverviewStatusLabel: String {
        if settingsViewModel.settings.validate().contains(where: { $0.field == "defaultWorkspacePath" }) {
            return "Needs attention"
        }
        return settingsViewModel.settings.defaultWorkspacePath == nil ? "Default app container" : "Custom folder"
    }

    func diagnosticDateLabel(_ date: Date?) -> String {
        guard let date else {
            return "Never"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func permissionLabel(_ status: PermissionStatus) -> String {
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

}
