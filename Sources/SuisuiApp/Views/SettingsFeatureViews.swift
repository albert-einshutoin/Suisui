import AppKit
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI

enum SettingsFeatureLoadState<Value> {
    case loading
    case unavailable
    case loaded(Value)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

@MainActor
struct SettingsOverviewFeatureView: View {
    let dependencies: SettingsOverviewDependencies
    @State private var selectedRowID: String?

    private var selectedRow: SettingsReadinessRow? {
        let rows = dependencies.groups.flatMap(\.rows)
        if let selectedRowID {
            return rows.first { $0.id == selectedRowID } ?? rows.first
        }
        return rows.first
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = CockpitLayoutPolicy.presentsSplitRail(contentWidth: Double(proxy.size.width))
            HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                overviewForm
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if isWide {
                    overviewDetailRail
                        .frame(width: max(240, CGFloat(CockpitLayoutPolicy.railWidth) + 40))
                }
            }
        }
        .onAppear {
            if selectedRowID == nil {
                selectedRowID = dependencies.groups.flatMap(\.rows).first?.id
            }
        }
        .onChange(of: dependencies.groups.map(\.group)) { _, _ in
            let rows = dependencies.groups.flatMap(\.rows)
            if let selectedRowID, rows.contains(where: { $0.id == selectedRowID }) {
                return
            }
            self.selectedRowID = rows.first?.id
        }
    }

    private var overviewForm: some View {
        Form {
            Section("Status Overview") {
                SettingsStatusOverviewView(
                    groups: dependencies.groups,
                    performAction: dependencies.performReadinessAction,
                    selectedRowID: selectedRowID,
                    onSelectRow: { selectedRowID = $0.id }
                )

                Button {
                    // The rerun request is owned by the app-level coordinator so
                    // it works even when no Project Board window is mounted and
                    // never opens more than one onboarding sheet.
                    dependencies.rerunOnboarding()
                } label: {
                    Label("Run Setup Again", systemImage: "arrow.clockwise.circle")
                }
                .accessibilityIdentifier("settings-run-onboarding")
                .accessibilityHint("Reopens onboarding to review current provider and permission readiness.")
            }

            if dependencies.showAdvanced {
                Section("Pro Value") {
                    ProValueOverviewRow(
                        syncStatusLabel: dependencies.syncStatusLabel,
                        syncValueLabel: dependencies.syncValueLabel,
                        syncBoundaryLabel: dependencies.syncBoundaryLabel,
                        syncTone: dependencies.syncTone,
                        mcpStatusLabel: dependencies.mcpStatusLabel,
                        mcpValueLabel: dependencies.mcpValueLabel,
                        mcpBoundaryLabel: dependencies.mcpBoundaryLabel,
                        mcpTone: dependencies.mcpTone
                    )
                }
            }

            Section("Advanced") {
                Toggle("Show advanced settings", isOn: dependencies.$showAdvanced)
                    .accessibilityIdentifier("settings-show-advanced-toggle")
                    .accessibilityHint("Reveals the MCP and Sync tabs and advanced AI options.")

                Text("Reveals MCP, Sync, and managed billing controls.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var overviewDetailRail: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            Label("Selected readiness", systemImage: "sidebar.right")
                .font(SuisuiTypography.sectionTitle)

            if let selectedRow {
                Text(localizedSettingsDisplay(selectedRow.title))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Text(localizedSettingsDisplay(selectedRow.detail))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let action = selectedRow.action {
                    Button(actionTitle(for: action)) {
                        dependencies.performReadinessAction(action)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("settings-overview-detail-action")
                } else {
                    Text("No action needed now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Select a readiness row to review details.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-overview-detail-rail")
    }

    private func actionTitle(for action: SettingsReadinessAction) -> String {
        switch action {
        case .openAI: localizedSettingsDisplay("Open AI")
        case .openPrivacy: localizedSettingsDisplay("Open Privacy")
        case .showAdvanced: localizedSettingsDisplay("Show Advanced")
        case .openMCP: localizedSettingsDisplay("Open MCP")
        case .openSync: localizedSettingsDisplay("Open Sync")
        case .retry: localizedSettingsDisplay("Retry")
        }
    }
}

@MainActor
struct SettingsAppearanceFeatureView: View {
    let context: SettingsAppearanceDependencies

    var body: some View {
        Form {
            SettingsAppearanceSection(appearancePreference: context.$appearancePreference, languagePreference: context.$languagePreference)
        }
        .formStyle(.grouped)
    }
}

@MainActor
struct SettingsAIFeatureView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let context: SettingsAIDependencies

    private var aiReadinessRows: [SettingsReadinessRow] {
        let preferredIDs: Set<String> = ["ai", "stt", "tts", "privacy", "data-location"]
        return context.readinessGroups
            .flatMap(\.rows)
            .filter { preferredIDs.contains($0.id) }
    }

    var body: some View {
        GeometryReader { proxy in
            let isWide = CockpitLayoutPolicy.presentsSplitRail(contentWidth: Double(proxy.size.width))
            HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                aiSettingsForm
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if isWide {
                    aiReadinessRail
                        .frame(width: max(240, CGFloat(CockpitLayoutPolicy.railWidth) + 40))
                }
            }
        }
    }

    private var aiSettingsForm: some View {
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
                    "Automation mode",
                    selection: Binding(
                        get: { settingsViewModel.settings.taskAutoExecution.mode },
                        set: { settingsViewModel.setTaskAutoExecutionMode($0) }
                    )
                ) {
                    ForEach(TaskAutoExecutionMode.allCases, id: \.self) { mode in
                        Text(mode.label)
                            .tag(mode)
                    }
                }
                .accessibilityIdentifier("settings-task-auto-execution-mode")
                .accessibilityHint("Auto-create runs a plan automatically only when it is a single low-risk task; everything else still requires review.")

                Text("Auto-create runs a plan automatically only when it is a single low-risk task; everything else still requires review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-task-auto-execution-mode-caption")

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
                DisclosureGroup("Advanced AI Options") {
                    Toggle(
                        isOn: Binding(
                            get: { settingsViewModel.settings.managedAIBilling.isEnabled },
                            set: { settingsViewModel.setManagedAIBillingEnabled($0) }
                        )
                    ) {
                        Label("Managed AI billing", systemImage: "creditcard")
                    }
                    .accessibilityIdentifier("settings-managed-ai-billing-toggle")
                    .accessibilityHint("Enables local cost cap controls for Suisui-managed AI work.")

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
                }
                .accessibilityIdentifier("settings-advanced-ai-options-billing")

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
                Picker(
                    "STT routing",
                    selection: Binding(
                        get: { settingsViewModel.settings.sttRoutingPreference },
                        set: { settingsViewModel.setSTTRoutingPreference($0) }
                    )
                ) {
                    ForEach(VoiceRoutingPreference.allCases, id: \.self) { preference in
                        Text(preference.displayName)
                            .tag(preference)
                    }
                }
                .accessibilityIdentifier("settings-stt-routing-preference")
                .accessibilityHint("Prioritizes Apple or local speech engines when STT retries after a recoverable failure.")

                if settingsViewModel.settings.sttProvider == .localWhisperCpp {
                    LocalPathSelectionField(
                        title: "whisper.cpp executable",
                        text: Binding(
                            get: { settingsViewModel.settings.whisperCppExecutablePath ?? "" },
                            set: { settingsViewModel.setWhisperCppExecutablePath($0) }
                        ),
                        selectionKind: .file,
                        accessibilityIdentifier: "settings-whisper-cpp-executable-path"
                    )
                    .accessibilityHint("Sets the absolute path to whisper-cli for offline speech to text.")
                }

                LocalSTTProviderStatusRow(row: settingsViewModel.selectedSTTProviderReadinessRow)

                Toggle(
                    isOn: Binding(
                        get: { settingsViewModel.settings.isLowLatencyVoiceAgentModeEnabled },
                        set: { settingsViewModel.setLowLatencyVoiceAgentModeEnabled($0) }
                    )
                ) {
                    Label("Low-latency voice agent", systemImage: "waveform")
                }
                .accessibilityIdentifier("settings-low-latency-voice-agent-toggle")
                .accessibilityHint("Enables explicit Start and Stop controls in the Voice Command window.")

                Toggle(
                    isOn: Binding(
                        get: { settingsViewModel.settings.isLowLatencyVoiceAgentCloudFallbackCostVisible },
                        set: { settingsViewModel.setLowLatencyVoiceAgentCloudFallbackCostVisible($0) }
                    )
                ) {
                    Label("Show realtime cloud cost", systemImage: "dollarsign.circle")
                }
                .accessibilityIdentifier("settings-low-latency-voice-agent-cost-visible")

                Toggle(
                    isOn: Binding(
                        get: { settingsViewModel.settings.isLowLatencyVoiceAgentCloudFallbackEnabled },
                        set: { settingsViewModel.setLowLatencyVoiceAgentCloudFallbackEnabled($0) }
                    )
                ) {
                    Label("Allow realtime cloud fallback", systemImage: "cloud")
                }
                .disabled(!settingsViewModel.settings.isLowLatencyVoiceAgentCloudFallbackCostVisible)
                .accessibilityIdentifier("settings-low-latency-voice-agent-cloud-fallback")

                Label("Voice agent sessions start only from the Voice Command window; cloud fallback requires visible cost disclosure before it can be saved.", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-low-latency-voice-agent-boundary")

                VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
                    LocalizedValueLabeledContent("Global Shortcut", value: context.shortcutSettingsViewModel.statusLabel)
                    LabeledContent("Voice Command", value: context.shortcutSettingsViewModel.displayShortcut)

                    if let detail = context.shortcutSettingsViewModel.state.detail {
                        Label(localizedSettingsDisplay(detail), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Label(
                        localizedDisplay(
                            "In-app fallback: %@",
                            context.shortcutSettingsViewModel.fallbackShortcutLabel
                        ),
                        systemImage: "keyboard"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let recoveryHint = context.shortcutSettingsViewModel.recoveryHint {
                        Label(localizedSettingsDisplay(recoveryHint), systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(SuisuiTone.caution.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings-global-voice-shortcut-recovery")
                    }

                    HStack {
                        Button(
                            context.shortcutSettingsViewModel.isRetryingRegistration
                                ? "Retry Global Shortcut"
                                : "Register Global Shortcut"
                        ) {
                            context.shortcutSettingsViewModel.registerDefaultVoiceCaptureShortcut()
                        }
                        .disabled(!context.shortcutSettingsViewModel.canRegister)
                        .accessibilityIdentifier("settings-global-voice-shortcut-register")

                        Button("Disable Global Shortcut") {
                            context.shortcutSettingsViewModel.unregisterVoiceCaptureShortcut()
                        }
                        .disabled(!context.shortcutSettingsViewModel.canUnregister)
                        .accessibilityIdentifier("settings-global-voice-shortcut-disable")
                    }
                }
                .accessibilityIdentifier("settings-global-voice-shortcut")
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

                Picker(
                    "TTS routing",
                    selection: Binding(
                        get: { settingsViewModel.settings.ttsRoutingPreference },
                        set: { settingsViewModel.setTTSRoutingPreference($0) }
                    )
                ) {
                    ForEach(VoiceRoutingPreference.allCases, id: \.self) { preference in
                        Text(preference.displayName)
                            .tag(preference)
                    }
                }
                .accessibilityIdentifier("settings-tts-routing-preference")
                .accessibilityHint("Prioritizes Apple or local speech engines when TTS retries after a recoverable failure.")

                SelectedTTSProviderStatusRow(row: settingsViewModel.ttsProviderReadinessRow)

                if settingsViewModel.settings.ttsProvider == .localKokoro {
                    LocalPathSelectionField(
                        title: "Kokoro executable",
                        text: Binding(
                            get: { settingsViewModel.settings.kokoroExecutablePath ?? "" },
                            set: { settingsViewModel.setKokoroExecutablePath($0) }
                        ),
                        selectionKind: .file,
                        accessibilityIdentifier: "settings-kokoro-executable-path"
                    )
                    .accessibilityHint("Sets the absolute path to the local Kokoro TTS executable.")
                }

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

                if settingsViewModel.settings.ttsProvider == .systemSpeech {
                    Picker(
                        "TTS voice",
                        selection: Binding<String?>(
                            get: { settingsViewModel.settings.systemSpeechVoiceID },
                            set: { settingsViewModel.setSystemSpeechVoiceID($0) }
                        )
                    ) {
                        Text("System Default").tag(String?.none)
                        if let unavailableVoiceID = unavailableSystemSpeechVoiceID {
                            Text("Unavailable voice")
                                .tag(Optional(unavailableVoiceID))
                        }
                        ForEach(settingsViewModel.selectableSystemSpeechVoices) { voice in
                            Text(voice.displayLabel)
                                .tag(Optional(voice.identifier))
                        }
                    }
                    .accessibilityIdentifier("settings-tts-voice-id")
                } else {
                    TextField(
                        "TTS voice",
                        text: Binding(
                            get: { settingsViewModel.settings.selectedTTSVoiceID },
                            set: { settingsViewModel.setTTSVoiceID($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("settings-tts-voice-id")
                }

                Button("Test Play") {
                    Task {
                        await settingsViewModel.testTTSPlayback(
                            using: context.makeTextToSpeechPreviewer()
                        )
                    }
                }
                .disabled(!settingsViewModel.ttsProviderReadinessRow.isReady)
                .accessibilityIdentifier("settings-tts-test-play")
                .accessibilityHint("Tests the selected TTS provider when it is ready.")

                settingsSaveButton
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
        .onAppear {
            settingsViewModel.refreshAppleSpeechReadiness()
            settingsViewModel.refreshSystemSpeechReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settingsViewModel.refreshAppleSpeechReadiness()
            settingsViewModel.refreshSystemSpeechReadiness()
        }
        .onReceive(NotificationCenter.default.publisher(for: .suisuiAppleSpeechAuthorizationDidChange)) { _ in
            settingsViewModel.refreshAppleSpeechReadiness()
        }
    }

    private var aiReadinessRail: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.md) {
            Label("Readiness", systemImage: "gauge.with.dots.needle.bottom.50percent")
                .font(SuisuiTypography.sectionTitle)

            if aiReadinessRows.isEmpty {
                Text("Readiness details appear once Overview has loaded provider status.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(aiReadinessRows, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedSettingsDisplay(row.title))
                            .font(.subheadline.weight(.semibold))
                        Text(localizedSettingsDisplay(row.detail))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        SuisuiTone.neutral.color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: SuisuiRadius.control, style: .continuous)
                    )
                    .accessibilityIdentifier("settings-ai-readiness-\(row.id)")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SuisuiSurface.groupedContent, in: RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-ai-readiness-rail")
    }

    private var unavailableSystemSpeechVoiceID: String? {
        guard let selectedID = settingsViewModel.settings.systemSpeechVoiceID,
              !settingsViewModel.selectableSystemSpeechVoices.contains(where: {
                  $0.identifier == selectedID
              })
        else {
            return nil
        }
        return selectedID
    }
}

struct GoogleCalendarSettingsSaveControls: View {
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

@MainActor
struct SettingsSyncFeatureView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let context: SettingsSyncDependencies

    @ViewBuilder
    var body: some View {
        Group {
            if case .loaded(let loadedSyncViewModel) = context.loadState {
                Form {
                    Section("Sync") {
                        LabeledContent("Plan", value: loadedSyncViewModel.planLabel)
                        LocalizedValueLabeledContent("Status", value: loadedSyncViewModel.statusLabel)
                        LocalizedValueLabeledContent("Last Attempt", value: loadedSyncViewModel.lastAttemptLabel)
                        LocalizedValueLabeledContent("Data Included", value: loadedSyncViewModel.dataIncludedLabel)
                        SyncValueStatusRow(
                            planLabel: loadedSyncViewModel.planLabel,
                            statusLabel: loadedSyncViewModel.statusLabel,
                            valueLabel: context.syncPaidValueLabel,
                            boundaryLabel: context.syncSafetyBoundaryLabel,
                            tone: context.syncOverviewTone
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

                    if context.isGoogleCalendarRuntimeEnabled {
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
                                calendarListOptions: context.googleCalendarListOptions,
                                shouldShowCurrentManualOption: context.shouldShowCurrentGoogleCalendarManualOption,
                                manualCalendarLabel: context.googleCalendarManualCalendarLabel,
                                calendarPickerLabel: context.googleCalendarPickerLabel,
                                isLoadingCalendarList: context.isLoadingGoogleCalendarList,
                                isCalendarListLoadDisabled: !context.canLoadGoogleCalendarList,
                                saveCalendarID: context.saveGoogleCalendarIDSetting,
                                loadCalendarList: context.loadGoogleCalendarList
                            )
                            ExternalConnectorScopeRow(
                                name: "Google Calendar",
                                status: context.googleCalendarSettingsReadinessRow.statusLabel,
                                detail: context.googleCalendarSettingsReadinessRow.detailLabel,
                                nextAction: context.googleCalendarSettingsReadinessRow.nextActionLabel,
                                privacyBoundary: context.googleCalendarSettingsReadinessRow.privacyBoundaryLabel,
                                systemImage: ExternalConnectorExposurePolicy.exposure(for: .googleCalendar).systemImage,
                                tone: context.googleCalendarSettingsTone,
                                statusActionLabel: context.googleCalendarSettingsReadinessRow.statusCheckActionLabel,
                                onStatusAction: context.refreshGoogleCalendarSettingsStatus
                            )
                            Button(localizedSettingsDisplay(context.googleCalendarOAuthActionLabel)) {
                                context.startGoogleCalendarOAuthAuthorization()
                            }
                            .disabled(!context.canStartGoogleCalendarOAuthAuthorization)
                            .accessibilityIdentifier("settings-google-calendar-oauth-setup")
                            .accessibilityHint("Opens Google Calendar OAuth authorization with PKCE. Tokens stay in Keychain.")
                            Button(role: .destructive) {
                                context.isConfirmingGoogleCalendarOAuthDisconnect = true
                            } label: {
                                Label("Disconnect Google Calendar", systemImage: "xmark.circle")
                            }
                            .disabled(!context.canDisconnectGoogleCalendarOAuthAuthorization)
                            .accessibilityIdentifier("settings-google-calendar-oauth-disconnect")
                            .accessibilityHint("Deletes local Google Calendar OAuth metadata and Keychain tokens without changing tasks.")
                            if let googleCalendarSetupMessage = context.googleCalendarSetupMessage {
                                Label(localizedSettingsDisplay(googleCalendarSetupMessage), systemImage: "info.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier("settings-google-calendar-oauth-setup-message")
                            }
                            Label(context.hiddenConnectorPolicySummary, systemImage: "eye.slash")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings-external-connector-policy-boundary")
                        }
                    }

                }
                .formStyle(.grouped)
            } else if context.loadState.isLoading {
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
}

@MainActor
struct SettingsPrivacyFeatureView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let context: SettingsPrivacyDependencies

    var body: some View {
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
                        get: { settingsViewModel.settings.notificationPreferences.quietHours.enabled },
                        set: { settingsViewModel.setNotificationQuietHoursEnabled($0) }
                    )
                ) {
                    Label("Quiet hours", systemImage: "moon.zzz")
                }
                .accessibilityIdentifier("settings-notification-quiet-hours-toggle")
                .accessibilityHint("Defers notifications inside the quiet window until the window ends.")
                DatePicker(
                    "Quiet hours start",
                    selection: quietHoursMinuteOfDayBinding(
                        get: { settingsViewModel.settings.notificationPreferences.quietHours.startMinuteOfDay },
                        set: { settingsViewModel.setNotificationQuietHoursStartMinuteOfDay($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!settingsViewModel.settings.notificationPreferences.quietHours.enabled)
                .accessibilityIdentifier("settings-notification-quiet-hours-start")
                .accessibilityHint("Sets the local time when the notification quiet window begins.")
                DatePicker(
                    "Quiet hours end",
                    selection: quietHoursMinuteOfDayBinding(
                        get: { settingsViewModel.settings.notificationPreferences.quietHours.endMinuteOfDay },
                        set: { settingsViewModel.setNotificationQuietHoursEndMinuteOfDay($0) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!settingsViewModel.settings.notificationPreferences.quietHours.enabled)
                .accessibilityIdentifier("settings-notification-quiet-hours-end")
                .accessibilityHint("Sets the local time when deferred notifications are delivered.")
                Picker(
                    "Remind me",
                    selection: Binding(
                        get: { settingsViewModel.settings.notificationPreferences.deadlineReminderLeadTime },
                        set: { settingsViewModel.setDeadlineReminderLeadTime($0) }
                    )
                ) {
                    ForEach(DeadlineReminderLeadTime.allCases, id: \.self) { leadTime in
                        Text(LocalizedStringKey(leadTime.label))
                            .tag(leadTime)
                    }
                }
                .accessibilityIdentifier("settings-notification-lead-time")
                .accessibilityHint("Moves deadline task reminders earlier than the due time. Digest and weekly summaries are not affected.")
                Text("Deadline reminders fire ahead of the due time by the selected lead. Notifications that land inside quiet hours are deferred to the end of the window, never dropped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-notification-quiet-hours-caption")
                Toggle(
                    isOn: Binding(
                        get: { settingsViewModel.settings.notificationPreferences.avoidsWeekends },
                        set: { settingsViewModel.setRescheduleAvoidsWeekends($0) }
                    )
                ) {
                    Label("Avoid weekends when rescheduling", systemImage: "calendar.badge.exclamationmark")
                }
                .accessibilityIdentifier("settings-reschedule-avoid-weekends")
                .accessibilityHint("Moves missed-task reschedule suggestions that land on Saturday or Sunday to the following Monday.")
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
                        get: { context.launchAtLoginEnabled },
                        set: { context.setLaunchAtLoginEnabled($0) }
                    )
                ) {
                    Label("Launch at Login", systemImage: "power")
                }
                .disabled(!context.canToggleLaunchAtLogin)
                LocalizedValueLabeledContent("Login Item", value: context.launchAtLoginStatusLabel)
                if let statusDetail = context.launchAtLoginStatusDetail {
                    Label(statusDetail, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = context.launchAtLoginErrorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                TextField(
                    "Display Name",
                    text: Binding(
                        get: { settingsViewModel.settings.profileDisplayName ?? "" },
                        set: { settingsViewModel.setProfileDisplayName($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings-profile-display-name")
                .accessibilityHint("Sets the optional name used by the Today greeting. Save Settings to persist it locally.")
                Picker(
                    "Daily work capacity",
                    selection: Binding(
                        get: { settingsViewModel.settings.dailyWorkCapacityMinutes },
                        set: { settingsViewModel.setDailyWorkCapacityMinutes($0) }
                    )
                ) {
                    ForEach(
                        Array(stride(
                            from: AppSettings.minimumDailyWorkCapacityMinutes,
                            through: AppSettings.maximumDailyWorkCapacityMinutes,
                            by: AppSettings.dailyWorkCapacityStepMinutes
                        )),
                        id: \.self
                    ) { minutes in
                        Text(dailyWorkCapacityLabel(minutes))
                            .tag(minutes)
                    }
                }
                .accessibilityIdentifier("settings-daily-work-capacity")
                .accessibilityHint("Sets Today workload capacity in 30-minute steps. Save Settings to persist it locally.")
                Picker("Weather location", selection: weatherLocationModeBinding) {
                    Text("Not configured").tag("unset")
                    Text("Current location").tag("current")
                    Text("Manual city").tag("manual")
                }
                .accessibilityIdentifier("settings-weather-location")
                if weatherLocationMode == "manual" {
                    TextField("City name", text: weatherCityBinding)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings-weather-city")
                    HStack {
                        TextField(
                            "Latitude",
                            value: weatherLatitudeBinding,
                            format: .number.precision(.fractionLength(0...6))
                        )
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings-weather-latitude")
                        TextField(
                            "Longitude",
                            value: weatherLongitudeBinding,
                            format: .number.precision(.fractionLength(0...6))
                        )
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("settings-weather-longitude")
                    }
                    Text("The city name is a label. Coordinates determine where weather is loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Weather uses the selected source for Today and does not keep a location history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LocalPathSelectionField(
                    title: "Workspace",
                    text: Binding(
                        get: { settingsViewModel.settings.defaultWorkspacePath ?? "" },
                        set: { settingsViewModel.setDefaultWorkspacePath($0) }
                    ),
                    selectionKind: .directory,
                    accessibilityIdentifier: "settings-default-workspace-path",
                    canCreateDirectories: true
                )
                LabeledContent("Data Location", value: context.dataLocationOverviewStatusLabel)
                Button {
                    context.presentBackupExportPanel()
                } label: {
                    Label("Back Up All Data…", systemImage: "arrow.down.doc")
                }
                .help("Save all projects, tasks, and knowledge frames to a local JSON file")
                .accessibilityIdentifier("settings-backup-export")
                .accessibilityHint("Writes a local backup file. No data leaves this Mac.")
                Button {
                    context.presentBackupRestorePanel()
                } label: {
                    Label("Restore from Backup…", systemImage: "arrow.up.doc")
                }
                .help("Add items from a Suisui backup file to this workspace")
                .accessibilityIdentifier("settings-backup-restore")
                .accessibilityHint("Opens a backup file and asks for confirmation before adding its items.")
                if let backupStatusMessage = context.backupStatusMessage {
                    Label(backupStatusMessage, systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("settings-backup-status")
                }
                if let backupErrorMessage = context.backupErrorMessage {
                    Label(backupErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings-backup-error")
                }
                Button {
                    context.presentDiagnosticsExportPanel()
                } label: {
                    Label("Export Diagnostics…", systemImage: "stethoscope")
                }
                .help("Save a metadata-only diagnostics report as a local text file")
                .accessibilityIdentifier("settings-export-diagnostics")
                .accessibilityHint("Writes a diagnostics text file with configuration metadata and counts only. No keys or content leave this Mac.")
                Text("The diagnostics file includes app and macOS versions, the selected AI provider kind, notification settings, task and project counts, and watcher check times. It never includes API keys, task, knowledge, or plan content, voice transcripts, or audit log entries.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-export-diagnostics-caption")
                if let diagnosticsExportErrorMessage = context.diagnosticsExportErrorMessage {
                    Label(diagnosticsExportErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings-export-diagnostics-error")
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
                if case .loaded(let diagnosticsSnapshot) = context.diagnosticsLoadState {
                    LabeledContent("Last Check", value: diagnosticDateLabel(diagnosticsSnapshot.lastCheckAt))
                    LabeledContent("Next Check", value: diagnosticDateLabel(diagnosticsSnapshot.nextCheckAt))
                    LocalizedValueLabeledContent("Notifications", value: permissionLabel(diagnosticsSnapshot.notificationPermissionStatus))
                    if let errorMessage = diagnosticsSnapshot.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else if context.diagnosticsLoadState.isLoading {
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
        .confirmationDialog(
            "Restore from backup?",
            isPresented: context.$isConfirmingBackupRestore,
            titleVisibility: .visible
        ) {
            Button("Add Backup Items") {
                context.applyPendingBackupRestore()
            }
            .accessibilityIdentifier("settings-backup-restore-confirm")

            Button("Cancel", role: .cancel) {
                context.pendingBackupRestoreDocument = nil
            }
            .accessibilityIdentifier("settings-backup-restore-cancel")
        } message: {
            Text(context.backupRestoreConfirmationMessage)
        }
    }

    private func dailyWorkCapacityLabel(_ minutes: Int) -> String {
        if minutes.isMultiple(of: 60) {
            return localizedCount(minutes / 60, one: "%d hour", other: "%d hours")
        }
        return String(format: String(localized: "%.1f h"), Double(minutes) / 60)
    }

    private var weatherLocationMode: String {
        switch settingsViewModel.settings.weatherLocationPreference {
        case .unset: "unset"
        case .currentLocation: "current"
        case .manual: "manual"
        }
    }

    private var weatherLocationModeBinding: Binding<String> {
        Binding(
            get: { weatherLocationMode },
            set: { mode in
                switch mode {
                case "current":
                    settingsViewModel.setWeatherLocationPreference(.currentLocation)
                case "manual":
                    if case .manual = settingsViewModel.settings.weatherLocationPreference {
                        break
                    }
                    settingsViewModel.setWeatherLocationPreference(
                        .manual(cityLabel: "Tokyo", latitude: 35.681236, longitude: 139.767125)
                    )
                default:
                    settingsViewModel.setWeatherLocationPreference(.unset)
                }
            }
        )
    }

    private var weatherCityBinding: Binding<String> {
        Binding(
            get: {
                guard case let .manual(label, _, _) = settingsViewModel.settings.weatherLocationPreference else {
                    return ""
                }
                return label
            },
            set: { label in
                let preference = settingsViewModel.settings.weatherLocationPreference
                guard case let .manual(_, latitude, longitude) = preference else { return }
                settingsViewModel.setWeatherLocationPreference(.manual(cityLabel: label, latitude: latitude, longitude: longitude))
            }
        )
    }

    private var manualWeatherLocation: (label: String, latitude: Double, longitude: Double) {
        guard case let .manual(label, latitude, longitude) = settingsViewModel.settings.weatherLocationPreference else {
            return ("Tokyo", 35.681236, 139.767125)
        }
        return (label, latitude, longitude)
    }

    private var weatherLatitudeBinding: Binding<Double> {
        Binding(
            get: { manualWeatherLocation.latitude },
            set: { latitude in
                guard (-90...90).contains(latitude) else { return }
                let location = manualWeatherLocation
                settingsViewModel.setWeatherLocationPreference(
                    .manual(cityLabel: location.label, latitude: latitude, longitude: location.longitude)
                )
            }
        )
    }

    private var weatherLongitudeBinding: Binding<Double> {
        Binding(
            get: { manualWeatherLocation.longitude },
            set: { longitude in
                guard (-180...180).contains(longitude) else { return }
                let location = manualWeatherLocation
                settingsViewModel.setWeatherLocationPreference(
                    .manual(cityLabel: location.label, latitude: location.latitude, longitude: longitude)
                )
            }
        )
    }
}

@MainActor
struct SettingsMCPFeatureView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let context: SettingsMCPDependencies

    @ViewBuilder
    var body: some View {
        Group {
            if case .loaded(let loadedExternalMCPViewModel) = context.loadState {
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
                            planLabel: context.planLabel,
                            statusLabel: context.mcpExecutionStatusLabel,
                            valueLabel: context.mcpExecutionValueLabel,
                            boundaryLabel: context.mcpExecutionSafetyBoundaryLabel,
                            tone: context.mcpExecutionTone
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
                        LocalPathSelectionField(
                            title: "Working Directory",
                            text: Binding(
                                get: { loadedExternalMCPViewModel.registration.workingDirectory ?? "" },
                                set: { loadedExternalMCPViewModel.updateWorkingDirectory($0) }
                            ),
                            selectionKind: .directory,
                            accessibilityIdentifier: "settings-mcp-working-directory"
                        )
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
                                context.isConfirmingMCPRegistrationDeletion = true
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
            } else if context.loadState.isLoading {
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
}

@MainActor
struct SettingsOverviewDependencies {
    let groups: [SettingsReadinessRowGroup]
    @Binding var showAdvanced: Bool
    let syncStatusLabel: String
    let syncValueLabel: String
    let syncBoundaryLabel: String
    let syncTone: SettingsStatusTone
    let mcpStatusLabel: String
    let mcpValueLabel: String
    let mcpBoundaryLabel: String
    let mcpTone: SettingsStatusTone
    let performReadinessAction: (SettingsReadinessAction) -> Void
    let rerunOnboarding: () -> Void
}

@MainActor
struct SettingsAppearanceDependencies {
    @Binding var appearancePreference: SuisuiAppearancePreference
    @Binding var languagePreference: AppLanguagePreference
}

@MainActor
extension SettingsAIFeatureView {
    @ViewBuilder
    var selectedProviderConfigurationFields: some View {
        switch settingsViewModel.settings.aiProvider {
        case .codexLocal:
            codexProviderSettingsFields
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

    @ViewBuilder
    var unavailableProviderSettingsFields: some View {
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
    var openAIProviderSettingsFields: some View {
        LocalizedValueLabeledContent("OpenAI API Key", value: settingsViewModel.openAIAPIKeyStatusLabel)
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
        DisclosureGroup("Advanced AI Options") {
            LocalizedValueLabeledContent("OpenAI Provider Smoke", value: settingsViewModel.openAIProviderSmokeStatusLabel)
        }
        .accessibilityIdentifier("settings-advanced-ai-options-openai")
    }

    @ViewBuilder
    var claudeProviderSettingsFields: some View {
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
    var geminiProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Gemini API Key", value: settingsViewModel.geminiAPIKeyStatusLabel)
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
        DisclosureGroup("Advanced AI Options") {
            LocalizedValueLabeledContent("Gemini Provider Smoke", value: settingsViewModel.geminiProviderSmokeStatusLabel)
        }
        .accessibilityIdentifier("settings-advanced-ai-options-gemini")
    }

    @ViewBuilder
    var groqProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Groq API Key", value: settingsViewModel.groqAPIKeyStatusLabel)
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
        DisclosureGroup("Advanced AI Options") {
            LocalizedValueLabeledContent("Groq Provider Smoke", value: settingsViewModel.groqProviderSmokeStatusLabel)
        }
        .accessibilityIdentifier("settings-advanced-ai-options-groq")
    }

    @ViewBuilder
    var openCodeProviderSettingsFields: some View {
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
    var codexProviderSettingsFields: some View {
        TextField(
            "Codex Executable",
            text: Binding(
                get: { settingsViewModel.settings.codexExecutablePath ?? "" },
                set: { settingsViewModel.setCodexExecutablePath($0) }
            )
        )
        .accessibilityIdentifier("settings-codex-executable-path")
        .accessibilityHint("Enter an absolute path to the Codex CLI executable, not its authentication files.")

        TextField(
            "Codex Model ID (optional)",
            text: Binding(
                get: { settingsViewModel.settings.codexModelID ?? "" },
                set: { settingsViewModel.setCodexModelID($0) }
            )
        )
        .accessibilityIdentifier("settings-codex-model-id")
        .accessibilityHint("Optionally selects a Codex model; leave empty to use the Codex default.")

        Toggle(
            isOn: Binding(
                get: { settingsViewModel.settings.isCodexLocalExecutionApproved },
                set: { settingsViewModel.setCodexLocalExecutionApproved($0) }
            )
        ) {
            Label("Approve Tool-Free Codex Local Execution", systemImage: "lock.shield")
        }
        .accessibilityIdentifier("settings-codex-local-execution-approval")
        .accessibilityHint("Verifies the executable content and OpenAI signing identity before every launch.")

        CodexAccountSettingsView(
            approvedExecutable: settingsViewModel.settings.isCodexLocalExecutionApproved
                ? settingsViewModel.settings.approvedCodexExecutable
                : nil,
            onDisconnect: {
                // The view model rolls back approval state and publishes an
                // error if persistence fails, so UI and runtime stay aligned.
                try? settingsViewModel.disconnectCodexAndSave()
            }
        )

        VStack(alignment: .leading, spacing: 6) {
            Label("Uses your Mac user's Codex-managed ChatGPT login and Codex allowance.", systemImage: "person.crop.circle.badge.checkmark")
            Text("Normal mode accepts only the signed OpenAI Codex executable. Developer Mode can approve an unsigned or custom build; turning Developer Mode off revokes that approval.")
            Text("Approval records SHA-256, signing identifier, Team ID, and designated requirement. Codex updates or replacements require approval again.")
            Text("Suisui does not read or store Codex tokens. ChatGPT sign-in is handled by the local Codex process.")
            Text("Shell, file editing, web, app, plugin, and MCP tools are disabled for this voice-task planning path.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("codex-local-subscription-boundary")
    }

    @ViewBuilder
    var openRouterProviderSettingsFields: some View {
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
    var ollamaProviderSettingsFields: some View {
        LocalizedValueLabeledContent("Provider Status", value: "Local")
        LocalizedValueLabeledContent("API Key", value: "Not required")
    }


    @ViewBuilder
    var settingsSaveButton: some View {
        Button {
            settingsViewModel.saveSettings()
        } label: {
            Label("Save Settings", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("settings-save-button")
        .accessibilityHint("Persists non-secret settings to local UserDefaults.")
    }

    @ViewBuilder
    var taskAutomationSaveButton: some View {
        Button {
            settingsViewModel.saveSettings()
        } label: {
            Label("Save Automation", systemImage: "square.and.arrow.down")
        }
        .accessibilityIdentifier("settings-task-auto-execution-save")
        .accessibilityHint("Persists task automation settings to local UserDefaults.")
    }

    /// Bridges the persisted minutes-of-day quiet-hours bounds to the
    /// hour-and-minute `DatePicker`, which needs a `Date` selection. Only the
    /// wall-clock components matter; the reference day is discarded on set.
    func billingCapValueLabel(_ cents: Int?) -> String {
        guard let cents, cents > 0 else {
            return localizedSettingsDisplay("Not set")
        }
        // A hardcoded "USD %.2f" ignores the user's grouping separator and
        // decimal mark. The cap is genuinely denominated in USD, so the
        // currency stays fixed while the presentation follows the locale.
        return (Decimal(cents) / 100).formatted(
            .currency(code: "USD").locale(localizedDisplayLocale())
        )
    }

    func handleVoiceModelAction(_ row: VoiceModelReadinessRow) {
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

    var activeAIProviderReadinessRow: AIProviderReadinessRow {
        settingsViewModel.providerReadinessRow(for: settingsViewModel.settings.aiProvider)
    }

    var activeAIProviderStatusLabel: String {
        activeAIProviderReadinessRow.statusLabel
    }

    var providerReadinessDetailLabel: String {
        activeAIProviderReadinessRow.detailLabel
    }

    var activeAIProviderNextActionLabel: String {
        activeAIProviderReadinessRow.nextActionLabel
    }

    var activeAIProviderTone: SettingsStatusTone {
        tone(for: activeAIProviderReadinessRow)
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

}

@MainActor
struct SettingsAIDependencies {
    let shortcutSettingsViewModel: ShortcutSettingsViewModel
    let makeTextToSpeechPreviewer: () -> any TextToSpeechPreviewing
    let readinessGroups: [SettingsReadinessRowGroup]
}

@MainActor
struct SettingsSyncDependencies {
    let loadState: SettingsFeatureLoadState<SyncSettingsViewModel>
    let isGoogleCalendarRuntimeEnabled: Bool
    let syncPaidValueLabel: String
    let syncSafetyBoundaryLabel: String
    let syncOverviewTone: SettingsStatusTone
    let googleCalendarListOptions: [GoogleCalendarRuntimeCalendarListEntry]
    let shouldShowCurrentGoogleCalendarManualOption: Bool
    let googleCalendarManualCalendarLabel: String
    let googleCalendarPickerLabel: (GoogleCalendarRuntimeCalendarListEntry) -> String
    let isLoadingGoogleCalendarList: Bool
    let canLoadGoogleCalendarList: Bool
    let googleCalendarSettingsReadinessRow: GoogleCalendarSettingsReadinessRow
    let googleCalendarSettingsTone: SettingsStatusTone
    let googleCalendarOAuthActionLabel: String
    let canStartGoogleCalendarOAuthAuthorization: Bool
    let canDisconnectGoogleCalendarOAuthAuthorization: Bool
    let hiddenConnectorPolicySummary: String
    @Binding var isConfirmingGoogleCalendarOAuthDisconnect: Bool
    @Binding var googleCalendarSetupMessage: String?
    let saveGoogleCalendarIDSetting: () -> Void
    let loadGoogleCalendarList: () -> Void
    let refreshGoogleCalendarSettingsStatus: () -> Void
    let startGoogleCalendarOAuthAuthorization: () -> Void
    let disconnectGoogleCalendarOAuthAuthorization: () -> Void
}

private extension SettingsSyncFeatureView {
    func settingsLazyLoadUnavailableHint(message: String) -> some View {
        Label(message, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityIdentifier("settings-tab-lazy-load-hint")
    }
}

@MainActor
struct SettingsPrivacyDependencies {
    let launchAtLoginEnabled: Bool
    let canToggleLaunchAtLogin: Bool
    let launchAtLoginStatusLabel: String
    let launchAtLoginStatusDetail: String?
    let launchAtLoginErrorMessage: String?
    let setLaunchAtLoginEnabled: (Bool) -> Void
    let dataLocationOverviewStatusLabel: String
    let diagnosticsLoadState: SettingsFeatureLoadState<WatcherDiagnosticsSnapshot>
    @Binding var pendingBackupRestoreDocument: WorkspaceBackupDocument?
    @Binding var isConfirmingBackupRestore: Bool
    @Binding var backupStatusMessage: String?
    @Binding var backupErrorMessage: String?
    @Binding var diagnosticsExportErrorMessage: String?
    let backupRestoreConfirmationMessage: String
    let presentBackupExportPanel: () -> Void
    let presentBackupRestorePanel: () -> Void
    let presentDiagnosticsExportPanel: () -> Void
    let applyPendingBackupRestore: () -> Void
}

private extension SettingsPrivacyFeatureView {
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

    func diagnosticDateLabel(_ date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func permissionLabel(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined: "Not Determined"
        case .granted: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

@MainActor
struct SettingsMCPDependencies {
    let loadState: SettingsFeatureLoadState<ExternalMCPSettingsViewModel>
    let planLabel: String
    let mcpExecutionStatusLabel: String
    let mcpExecutionValueLabel: String
    let mcpExecutionSafetyBoundaryLabel: String
    let mcpExecutionTone: SettingsStatusTone
    @Binding var isConfirmingMCPRegistrationDeletion: Bool
}

private extension SettingsMCPFeatureView {
    func settingsLazyLoadUnavailableHint(message: String) -> some View {
        Label(message, systemImage: "clock")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .accessibilityIdentifier("settings-tab-lazy-load-hint")
    }

    func toolPermissionIcon(_ permission: ExternalMCPToolPermission) -> String {
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

    func toolPermissionColor(_ permission: ExternalMCPToolPermission) -> Color {
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


struct MCPServerSettingsRow: View {
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

struct MCPServerStatusBadge: View {
    let label: String

    var body: some View {
        Label(localizedSettingsDisplay(label), systemImage: label == "Enabled" ? "checkmark.circle" : "pause.circle")
            .foregroundStyle(label == "Enabled" ? .green : .secondary)
            .lineLimit(1)
    }
}

struct MCPServerConnectionBadge: View {
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

struct SelectedAIProviderStatusRow: View {
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

struct SelectedTTSProviderStatusRow: View {
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

struct LocalSTTProviderStatusRow: View {
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

struct AIProviderReadinessSummaryRow: View {
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

struct AIProviderReadinessSummaryItem: View {
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

struct SyncValueStatusRow: View {
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

struct ExternalConnectorScopeRow: View {
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

struct MCPPaidExecutionBoundaryRow: View {
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

struct ProValueOverviewRow: View {
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

struct ProValueOverviewItem: View {
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

struct LocalizedValueLabeledContent: View {
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

enum SettingsStatusTone {
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
