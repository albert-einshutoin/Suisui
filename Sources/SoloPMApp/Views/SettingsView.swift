import Combine
import Foundation
import SoloPMCore
import SoloPMGoogleCalendarRuntime
import SwiftUI
import UniformTypeIdentifiers

enum SettingsTab: String {
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

@MainActor
private final class LazyDependencyLoader<Value>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var isLoading = false
    private let loadValue: () -> Value

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
private final class LazyObservableObjectLoader<Value: ObservableObject>: ObservableObject {
    @Published private(set) var value: Value?
    @Published private(set) var isLoading = false
    private let loadValue: () -> Value
    private var valueCancellable: AnyCancellable?

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
    let googleCalendarStatusProvider: () -> GoogleCalendarRuntimeSyncStatus
    let googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?
    let googleCalendarOAuthDisconnecter: (any GoogleCalendarOAuthDisconnecting)?
    let googleCalendarListProviderFactory: () -> (any GoogleCalendarListProviding)?
    let textToSpeechPreviewerFactory: (AppSettings) -> any TextToSpeechPreviewing
    @StateObject private var settingsViewModel: AppSettingsViewModel
    @StateObject private var launchAtLoginViewModel: LaunchAtLoginSettingsViewModel
    @StateObject private var watcherDiagnosticsLoader: LazyDependencyLoader<WatcherDiagnosticsSnapshot>
    @StateObject private var externalMCPSettingsViewModelLoader: LazyObservableObjectLoader<ExternalMCPSettingsViewModel>
    @StateObject private var syncSettingsViewModelLoader: LazyObservableObjectLoader<SyncSettingsViewModel>
    @Binding private var appearancePreference: SoloPMAppearancePreference
    @Binding private var languagePreference: AppLanguagePreference
    @State private var isConfirmingMCPRegistrationDeletion = false
    @State private var isConfirmingGoogleCalendarOAuthDisconnect = false
    @State private var isChoosingDataLocation = false
    @State private var selectedTab: SettingsTab
    @State private var googleCalendarSyncStatus: GoogleCalendarRuntimeSyncStatus?
    @State private var googleCalendarSetupMessage: String?
    @State private var isGoogleCalendarOAuthAuthorizationInProgress = false
    @State private var googleCalendarListProvider: (any GoogleCalendarListProviding)?
    @State private var isLoadingGoogleCalendarList = false
    @State private var googleCalendarListOptions: [GoogleCalendarRuntimeCalendarListEntry] = []
    @State private var googleCalendarListLoadGeneration = 0
    @State private var hasLoadedCalendarListProvider = false

    init(
        settingsViewModel: AppSettingsViewModel,
        launchAtLoginViewModel: LaunchAtLoginSettingsViewModel,
        watcherDiagnosticsSnapshot: WatcherDiagnosticsSnapshot,
        integrationPermissionSnapshot: PermissionSnapshot,
        watcherDiagnosticsSnapshotFactory: @escaping () -> WatcherDiagnosticsSnapshot,
        externalMCPSettingsViewModelFactory: @escaping () -> ExternalMCPSettingsViewModel,
        syncSettingsViewModelFactory: @escaping () -> SyncSettingsViewModel,
        googleCalendarStatusProvider: @escaping () -> GoogleCalendarRuntimeSyncStatus,
        googleCalendarOAuthConnector: (any GoogleCalendarOAuthConnecting)?,
        googleCalendarOAuthDisconnecter: (any GoogleCalendarOAuthDisconnecting)?,
        googleCalendarListProviderFactory: @escaping () -> (any GoogleCalendarListProviding)?,
        textToSpeechPreviewerFactory: @escaping (AppSettings) -> any TextToSpeechPreviewing,
        appearancePreference: Binding<SoloPMAppearancePreference>,
        languagePreference: Binding<AppLanguagePreference>,
        initialTab: SettingsTab = .overview
    ) {
        self.watcherDiagnosticsSnapshot = watcherDiagnosticsSnapshot
        self.integrationPermissionSnapshot = integrationPermissionSnapshot
        self.watcherDiagnosticsSnapshotFactory = watcherDiagnosticsSnapshotFactory
        self.externalMCPSettingsViewModelFactory = externalMCPSettingsViewModelFactory
        self.syncSettingsViewModelFactory = syncSettingsViewModelFactory
        self.googleCalendarStatusProvider = googleCalendarStatusProvider
        self.googleCalendarOAuthConnector = googleCalendarOAuthConnector
        self.googleCalendarOAuthDisconnecter = googleCalendarOAuthDisconnecter
        self.googleCalendarListProviderFactory = googleCalendarListProviderFactory
        self.textToSpeechPreviewerFactory = textToSpeechPreviewerFactory
        _settingsViewModel = StateObject(wrappedValue: settingsViewModel)
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
            requestRuntimeDependencies(for: selectedTab)
        }
        .onChange(of: selectedTab) { _, tab in
            requestRuntimeDependencies(for: tab)
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
            Text("This removes the saved registration from SoloPM.")
        }
        .confirmationDialog(
            "Disconnect Google Calendar",
            isPresented: $isConfirmingGoogleCalendarOAuthDisconnect
        ) {
            Button("Disconnect", role: .destructive) {
                disconnectGoogleCalendarOAuthAuthorization()
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

    private var overviewSettingsTab: some View {
        let currentSyncStatusLabel = syncViewModel?.statusLabel ?? "Unavailable"
        let currentSyncPlanLabel = syncViewModel?.planLabel ?? "Unavailable"
        let currentMcpStatusLabel = externalMCPViewModel?.connectionCheckResultLabel ?? "Unavailable"
        let currentMcpDetailLabel = externalMCPViewModel?.display.statusLabel ?? "Unavailable"

        return Form {
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
                    mcpStatusLabel: currentMcpStatusLabel,
                    mcpDetailLabel: currentMcpDetailLabel,
                    mcpTone: mcpOverviewTone,
                    syncStatusLabel: currentSyncStatusLabel,
                    syncDetailLabel: localizedDisplay("Plan: %@", currentSyncPlanLabel),
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
                    syncStatusLabel: currentSyncStatusLabel,
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

                taskAutomationSaveButton

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
            }

            Section("Billing") {
                Toggle(
                    isOn: Binding(
                        get: { settingsViewModel.settings.managedAIBilling.isEnabled },
                        set: { settingsViewModel.setManagedAIBillingEnabled($0) }
                    )
                ) {
                    Label("Managed AI billing", systemImage: "creditcard")
                }
                .accessibilityIdentifier("settings-managed-ai-billing-toggle")
                .accessibilityHint("Enables local cost cap controls for SoloPM-managed AI work.")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.managedAIBilling.perRunCapCents ?? 0 },
                        set: { settingsViewModel.setManagedAIPerRunCapCents($0 == 0 ? nil : $0) }
                    ),
                    in: 0...100_000,
                    step: 25
                ) {
                    LabeledContent("Per-run cap", value: billingCapValueLabel(settingsViewModel.settings.managedAIBilling.perRunCapCents))
                }
                .accessibilityIdentifier("settings-managed-ai-per-run-cap")
                .accessibilityHint("Sets the per-run cap used by managed AI cost previews.")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.managedAIBilling.dailyCapCents ?? 0 },
                        set: { settingsViewModel.setManagedAIDailyCapCents($0 == 0 ? nil : $0) }
                    ),
                    in: 0...1_000_000,
                    step: 50
                ) {
                    LabeledContent("Daily threshold", value: billingCapValueLabel(settingsViewModel.settings.managedAIBilling.dailyCapCents))
                }
                .accessibilityIdentifier("settings-managed-ai-daily-cap")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.managedAIBilling.monthlyCapCents ?? 0 },
                        set: { settingsViewModel.setManagedAIMonthlyCapCents($0 == 0 ? nil : $0) }
                    ),
                    in: 0...10_000_000,
                    step: 100
                ) {
                    LabeledContent("Monthly threshold", value: billingCapValueLabel(settingsViewModel.settings.managedAIBilling.monthlyCapCents))
                }
                .accessibilityIdentifier("settings-managed-ai-monthly-cap")

                Stepper(
                    value: Binding(
                        get: { settingsViewModel.settings.managedAIBilling.workspaceCapCents ?? 0 },
                        set: { settingsViewModel.setManagedAIWorkspaceCapCents($0 == 0 ? nil : $0) }
                    ),
                    in: 0...100_000_000,
                    step: 100
                ) {
                    LabeledContent("Workspace threshold", value: billingCapValueLabel(settingsViewModel.settings.managedAIBilling.workspaceCapCents))
                }
                .accessibilityIdentifier("settings-managed-ai-workspace-cap")

                Label("Per-run cap blocks managed previews; daily, monthly, and workspace caps are enforced from the managed usage ledger before execution.", systemImage: "lock.doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-managed-ai-billing-boundary")

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

                LocalSTTProviderStatusRow(row: settingsViewModel.localSTTProviderReadinessRow)

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
                            using: textToSpeechPreviewerFactory(settingsViewModel.settings)
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

    @ViewBuilder
    private var syncSettingsTab: some View {
        let loadedSyncViewModel = syncSettingsViewModelLoader.value
        Group {
            if let loadedSyncViewModel {
                Form {
                    Section("Sync") {
                        LabeledContent("Plan", value: loadedSyncViewModel.planLabel)
                        LocalizedValueLabeledContent("Status", value: loadedSyncViewModel.statusLabel)
                        LocalizedValueLabeledContent("Last Attempt", value: loadedSyncViewModel.lastAttemptLabel)
                        LocalizedValueLabeledContent("Data Included", value: loadedSyncViewModel.dataIncludedLabel)
                        SyncValueStatusRow(
                            planLabel: loadedSyncViewModel.planLabel,
                            statusLabel: loadedSyncViewModel.statusLabel,
                            valueLabel: syncPaidValueLabel,
                            boundaryLabel: syncSafetyBoundaryLabel,
                            tone: syncOverviewTone
                        )
                        Toggle(
                            isOn: Binding(
                                get: { loadedSyncViewModel.isSyncEnabled },
                                set: { isEnabled in
                                    if isEnabled {
                                        loadedSyncViewModel.startSync()
                                    } else {
                                        loadedSyncViewModel.stopSync()
                                    }
                                }
                            )
                        ) {
                            Label("External Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!loadedSyncViewModel.canEnableSync)
                        if let syncUnavailableLabel = loadedSyncViewModel.syncUnavailableLabel {
                            Label(localizedSettingsDisplay(syncUnavailableLabel), systemImage: "lock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let errorMessage = loadedSyncViewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    Section("External Task Tools") {
                        Text("Pro unlocks external sync; import/export JSON stays local.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        GoogleCalendarSettingsSaveControls(
                            calendarID: Binding(
                                get: { settingsViewModel.settings.googleCalendarID },
                                set: { settingsViewModel.setGoogleCalendarID($0) }
                            ),
                            currentCalendarID: settingsViewModel.settings.googleCalendarID,
                            calendarListOptions: googleCalendarListOptions,
                            shouldShowCurrentManualOption: shouldShowCurrentGoogleCalendarManualOption,
                            manualCalendarLabel: googleCalendarManualCalendarLabel,
                            calendarPickerLabel: { googleCalendarPickerLabel(for: $0) },
                            isLoadingCalendarList: isLoadingGoogleCalendarList,
                            isCalendarListLoadDisabled: isLoadingGoogleCalendarList || isGoogleCalendarOAuthAuthorizationInProgress || googleCalendarListProvider == nil,
                            saveCalendarID: saveGoogleCalendarIDSetting,
                            loadCalendarList: loadGoogleCalendarList
                        )
                        ExternalConnectorScopeRow(
                            name: "Google Calendar",
                            status: googleCalendarSettingsReadinessRow.statusLabel,
                            detail: googleCalendarSettingsReadinessRow.detailLabel,
                            nextAction: googleCalendarSettingsReadinessRow.nextActionLabel,
                            privacyBoundary: googleCalendarSettingsReadinessRow.privacyBoundaryLabel,
                            systemImage: ExternalConnectorExposurePolicy.exposure(for: .googleCalendar).systemImage,
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
                        Button(role: .destructive) {
                            isConfirmingGoogleCalendarOAuthDisconnect = true
                        } label: {
                            Label("Disconnect Google Calendar", systemImage: "xmark.circle")
                        }
                        .disabled(isGoogleCalendarOAuthAuthorizationInProgress || googleCalendarOAuthDisconnecter == nil)
                        .accessibilityIdentifier("settings-google-calendar-oauth-disconnect")
                        .accessibilityHint("Deletes local Google Calendar OAuth metadata and Keychain tokens without changing tasks.")
                        if let googleCalendarSetupMessage {
                            Label(localizedSettingsDisplay(googleCalendarSetupMessage), systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings-google-calendar-oauth-setup-message")
                        }
                        Label(hiddenConnectorPolicySummary, systemImage: "eye.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-external-connector-policy-boundary")
                    }

                }
                .formStyle(.grouped)
            } else if syncSettingsViewModelLoader.isLoading {
                Form {
                    Section("Sync") {
                        HStack {
                            ProgressView()
                            Text("Loading Sync settings...")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("settings-sync-loading")
                    }
                }
                .formStyle(.grouped)
            } else {
                Form {
                    Section("Sync") {
                        Text("Sync settings not loaded yet.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-sync-unavailable")
                        settingsLazyLoadUnavailableHint(message: "Open this tab to load Sync settings.")
                    }
                }.formStyle(.grouped)
            }
        }
    }

    private struct GoogleCalendarSettingsSaveControls: View {
        let calendarID: Binding<String>
        let currentCalendarID: String
        let calendarListOptions: [GoogleCalendarRuntimeCalendarListEntry]
        let shouldShowCurrentManualOption: Bool
        let manualCalendarLabel: String
        let calendarPickerLabel: (GoogleCalendarRuntimeCalendarListEntry) -> String
        let isLoadingCalendarList: Bool
        let isCalendarListLoadDisabled: Bool
        let saveCalendarID: () -> Void
        let loadCalendarList: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Google Calendar ID", text: calendarID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings-google-calendar-id")
                    .accessibilityHint("Sets the Google Calendar id used for approved due-task sync.")
                    .onSubmit(saveCalendarID)

                if !calendarListOptions.isEmpty {
                    Picker("Available Calendar", selection: calendarID) {
                        if shouldShowCurrentManualOption {
                            Text(manualCalendarLabel)
                                .tag(currentCalendarID)
                        }
                        ForEach(calendarListOptions) { option in
                            Text(calendarPickerLabel(option))
                                .tag(option.id)
                        }
                    }
                    .accessibilityIdentifier("settings-google-calendar-picker")
                    .accessibilityHint("Chooses a writable Google Calendar returned by the connected account.")
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button {
                        saveCalendarID()
                    } label: {
                        Label("Save Calendar", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityIdentifier("settings-google-calendar-id-save")
                    .accessibilityHint("Persists the selected Google Calendar id before checking sync readiness.")

                    Button {
                        loadCalendarList()
                    } label: {
                        Label(
                            isLoadingCalendarList ? "Loading Calendars" : "Load Calendars",
                            systemImage: "calendar.badge.checkmark"
                        )
                    }
                    .disabled(isCalendarListLoadDisabled)
                    .accessibilityIdentifier("settings-google-calendar-list-load")
                    .accessibilityHint("Loads writable Google Calendars for the connected OAuth account.")

                    Text("Save Calendar before checking readiness; load calendars after OAuth is connected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings-google-calendar-id-save-note")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings-google-calendar-id-save-flow")
        }
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
                        get: { settingsViewModel.settings.isDeveloperModeEnabled },
                        set: { settingsViewModel.setDeveloperModeEnabled($0) }
                    )
                ) {
                    Label("Developer Mode", systemImage: "hammer")
                }
                .accessibilityIdentifier("settings-developer-mode-toggle")
                Label(
                    "Developer Mode exposes local shell and repository automation controls after explicit approval.",
                    systemImage: "terminal"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings-developer-mode-boundary")
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
                if let diagnosticsSnapshot = watcherDiagnosticsLoader.value {
                    LabeledContent("Last Check", value: diagnosticDateLabel(diagnosticsSnapshot.lastCheckAt))
                    LabeledContent("Next Check", value: diagnosticDateLabel(diagnosticsSnapshot.nextCheckAt))
                    LocalizedValueLabeledContent("Notifications", value: permissionLabel(diagnosticsSnapshot.notificationPermissionStatus))
                    if let errorMessage = diagnosticsSnapshot.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else if watcherDiagnosticsLoader.isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading watcher diagnostics...")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("settings-privacy-watcher-loading")
                } else {
                    Text("Watcher diagnostics not loaded yet.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-privacy-watcher-unavailable")
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

    @ViewBuilder
    private var mcpSettingsTab: some View {
        let loadedExternalMCPViewModel = externalMCPSettingsViewModelLoader.value
        Group {
            if let loadedExternalMCPViewModel {
                Form {
                    Section("External MCP") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Servers", systemImage: "externaldrive.connected.to.line.below")
                                    .font(.headline)
                                Spacer()
                                Button {
                                    loadedExternalMCPViewModel.createRegistration()
                                } label: {
                                    Label("Add Server", systemImage: "plus")
                                }
                            }

                            ForEach(loadedExternalMCPViewModel.registrationRows) { row in
                                MCPServerSettingsRow(
                                    row: row,
                                    isCheckDisabled: loadedExternalMCPViewModel.isCheckingConnection,
                                    onSelect: {
                                        loadedExternalMCPViewModel.selectRegistration(id: row.id)
                                    },
                                    onCheck: {
                                        Task {
                                            await loadedExternalMCPViewModel.checkConnection(id: row.id)
                                        }
                                    }
                                )
                            }
                        }

                        MCPPaidExecutionBoundaryRow(
                            planLabel: syncViewModel?.planLabel ?? "Unavailable",
                            statusLabel: mcpExecutionStatusLabel,
                            valueLabel: mcpExecutionValueLabel,
                            boundaryLabel: mcpExecutionSafetyBoundaryLabel,
                            tone: mcpExecutionTone
                        )

                        Toggle(
                            isOn: Binding(
                                get: { loadedExternalMCPViewModel.registration.isEnabled },
                                set: { loadedExternalMCPViewModel.updateEnabled($0) }
                            )
                        ) {
                            Label("Server Enabled", systemImage: "externaldrive.connected.to.line.below")
                        }
                        TextField("Display Name", text: Binding(
                            get: { loadedExternalMCPViewModel.registration.displayName },
                            set: { loadedExternalMCPViewModel.updateDisplayName($0) }
                        ))
                        TextField("Command", text: Binding(
                            get: { loadedExternalMCPViewModel.registration.command },
                            set: { loadedExternalMCPViewModel.updateCommand($0) }
                        ))
                        TextField("Arguments", text: Binding(
                            get: { loadedExternalMCPViewModel.argumentsText },
                            set: { loadedExternalMCPViewModel.updateArgumentsText($0) }
                        ))
                        TextField("Working Directory", text: Binding(
                            get: { loadedExternalMCPViewModel.registration.workingDirectory ?? "" },
                            set: { loadedExternalMCPViewModel.updateWorkingDirectory($0) }
                        ))
                        TextField("Environment References", text: Binding(
                            get: { loadedExternalMCPViewModel.environmentText },
                            set: { loadedExternalMCPViewModel.updateEnvironmentText($0) }
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

                        LabeledContent("Transport", value: loadedExternalMCPViewModel.display.transportLabel)
                        LocalizedValueLabeledContent("Status", value: loadedExternalMCPViewModel.display.statusLabel)
                        LabeledContent("Protocol Version", value: loadedExternalMCPViewModel.protocolVersionLabel)
                        LocalizedValueLabeledContent("Check Result", value: loadedExternalMCPViewModel.connectionCheckResultLabel)
                        LocalizedValueLabeledContent("Resources", value: "Not supported in this release")
                        LocalizedValueLabeledContent("Prompts", value: "Not supported in this release")
                        ForEach(loadedExternalMCPViewModel.display.environmentRows, id: \.name) { row in
                            LabeledContent(row.name, value: row.sourceLabel)
                        }
                        if let errorMessage = loadedExternalMCPViewModel.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        HStack {
                            Button {
                                loadedExternalMCPViewModel.save()
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
                                    await loadedExternalMCPViewModel.checkConnection()
                                }
                            } label: {
                                Label("Check Connection", systemImage: "network")
                            }
                            .disabled(loadedExternalMCPViewModel.isCheckingConnection)

                            if loadedExternalMCPViewModel.isCheckingConnection {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    Section("MCP Tool Permissions") {
                        if loadedExternalMCPViewModel.toolRows.isEmpty {
                            Text("No tools discovered")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(loadedExternalMCPViewModel.toolRows, id: \.id) { row in
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
                        if let auditErrorMessage = loadedExternalMCPViewModel.auditErrorMessage {
                            Label(auditErrorMessage, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if loadedExternalMCPViewModel.auditRows.isEmpty {
                            Text("No external calls recorded")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(loadedExternalMCPViewModel.auditRows.enumerated()), id: \.offset) { _, row in
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
            } else if externalMCPSettingsViewModelLoader.isLoading {
                Form {
                    Section("External MCP") {
                        HStack {
                            ProgressView()
                            Text("Loading MCP settings...")
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityIdentifier("settings-mcp-loading")
                    }
                }
                .formStyle(.grouped)
            } else {
                Form {
                    Section("External MCP") {
                        Text("MCP settings not loaded yet.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings-mcp-unavailable")
                        settingsLazyLoadUnavailableHint(message: "MCP settings load when this tab is opened.")
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    @ViewBuilder
    private func settingsLazyLoadUnavailableHint(message: String) -> some View {
        Label(message, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityIdentifier("settings-tab-lazy-load-hint")
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

    private var taskAutomationSaveButton: some View {
        Button {
            settingsViewModel.saveSettings()
        } label: {
            Label("Save Automation", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("settings-task-auto-execution-save")
        .accessibilityHint("Persists task automation settings to local UserDefaults.")
    }

    private func billingCapValueLabel(_ cents: Int?) -> String {
        guard let cents, cents > 0 else {
            return localizedSettingsDisplay("Not set")
        }
        return String(format: localizedSettingsDisplay("USD %.2f"), Double(cents) / 100)
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
        localizedDisplay(
            "Local whisper.cpp: %@",
            localizedSettingsDisplay(settingsViewModel.localSTTProviderReadinessRow.statusLabel)
        )
    }

    private var sttOverviewTone: SettingsStatusTone {
        settingsViewModel.localSTTProviderReadinessRow.isReady ? .ready : .warning
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

    private var hiddenConnectorPolicySummary: String {
        let hiddenCount = ExternalConnectorExposurePolicy.all.count - ExternalConnectorExposurePolicy.settingsVisible.count
        let draftOnlyCount = ExternalConnectorExposurePolicy.assistantQueueDraftOnly.count
        return String(localized: "\(hiddenCount) connector policies stay out of Settings until connect, check, revoke, and audit UI is complete. \(draftOnlyCount) connector send paths remain Assistant Queue draft-only.")
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

    private func saveGoogleCalendarIDSetting() {
        settingsViewModel.saveSettings()
        guard settingsViewModel.errorMessage == nil else {
            return
        }
        refreshGoogleCalendarSettingsStatus()
    }

    private func loadGoogleCalendarList() {
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

    private func invalidateGoogleCalendarListOptions() {
        googleCalendarListLoadGeneration += 1
        googleCalendarListOptions = []
        isLoadingGoogleCalendarList = false
    }

    private var shouldShowCurrentGoogleCalendarManualOption: Bool {
        let currentID = settingsViewModel.settings.googleCalendarID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentID.isEmpty == false else {
            return false
        }
        return !googleCalendarListOptions.contains { $0.id == currentID }
    }

    private var googleCalendarManualCalendarLabel: String {
        String(format: localizedSettingsDisplay("Current manual ID: %@"), settingsViewModel.settings.googleCalendarID)
    }

    private func googleCalendarPickerLabel(for option: GoogleCalendarRuntimeCalendarListEntry) -> String {
        if option.isPrimary {
            return String(format: localizedSettingsDisplay("%@ (Primary calendar)"), option.summary)
        }
        return option.summary
    }

    private func startGoogleCalendarOAuthAuthorization() {
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
            case .failure(let error):
                googleCalendarSetupMessage = googleCalendarOAuthFailureMessage(from: error)
            }
        }
    }

    private func disconnectGoogleCalendarOAuthAuthorization() {
        guard let googleCalendarOAuthDisconnecter else {
            googleCalendarSetupMessage = "Google Calendar OAuth disconnect is not available in this build."
            return
        }

        do {
            invalidateGoogleCalendarListOptions()
            try googleCalendarOAuthDisconnecter.disconnect()
            googleCalendarSetupMessage = "Google Calendar OAuth disconnected. Tokens were removed from Keychain."
            googleCalendarSyncStatus = googleCalendarStatusProvider()
        } catch {
            googleCalendarSetupMessage = UserFacingErrorMessageSanitizer.message(
                from: error,
                fallback: "Google Calendar OAuth disconnect failed."
            )
        }
    }

    private func googleCalendarListFailureMessage(from error: Error) -> String {
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

    private var syncStatusLabelForOverview: String {
        syncViewModel?.statusLabel ?? "Unavailable"
    }

    private var mcpExecutionStatusLabel: String {
        guard let syncViewModel else {
            return "Execution gated"
        }

        return syncViewModel.status.plan.allows(.advancedMCPExecution) ? "Execution unlocked" : "Execution gated"
    }

    private var mcpExecutionValueLabel: String {
        let requiredPlan = FeatureGate.advancedMCPExecution.requiredPlan.displayName
        guard let syncViewModel else {
            return localizedDisplay("%@ is required before external MCP tools can execute.", requiredPlan)
        }

        if syncViewModel.status.plan.allows(.advancedMCPExecution) {
            return localizedDisplay("Advanced MCP tools can execute on %@.", syncViewModel.planLabel)
        }
        return localizedDisplay("%@ is required before external MCP tools can execute.", requiredPlan)
    }

    private var mcpExecutionSafetyBoundaryLabel: String {
        "Register and Check stay available; tools/call still requires entitlement, tool policy, and approval."
    }

    private var mcpExecutionTone: SettingsStatusTone {
        guard let syncViewModel else {
            return .warning
        }

        return syncViewModel.status.plan.allows(.advancedMCPExecution) ? .ready : .warning
    }

    private var syncOverviewTone: SettingsStatusTone {
        switch syncStatusLabelForOverview {
        case "Ready", "Syncing":
            .ready
        case "Failed":
            .danger
        default:
            .warning
        }
    }

    private var syncPaidValueLabel: String {
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

    private var syncSafetyBoundaryLabel: String {
        switch syncStatusLabelForOverview {
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

private struct LocalSTTProviderStatusRow: View {
    let row: STTProviderReadinessRow

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

                Label(localizedSettingsDisplay(row.nextActionLabel), systemImage: row.isReady ? "waveform" : "arrow.right.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-local-stt-readiness-row")
        .accessibilityLabel("STT provider readiness")
        .accessibilityHint("Shows whether the local STT model, executable, and local voice runtime smoke are ready.")
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
                        .accessibilityIdentifier(name == "Google Calendar" ? "settings-google-calendar-readiness-status" : "settings-external-connector-status")
                }

                Text(localizedSettingsDisplay(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(name == "Google Calendar" ? "settings-google-calendar-readiness-detail" : "settings-external-connector-detail")

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
                .accessibilityIdentifier(name == "Google Calendar" ? "settings-google-calendar-readiness-check" : "settings-external-connector-readiness-check")
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
