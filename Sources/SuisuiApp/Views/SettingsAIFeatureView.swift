import AppKit
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI

@MainActor
struct SettingsAIFeatureView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let context: SettingsAIDependencies
    @Environment(\.cockpitAuthoritativeContentWidth) private var authoritativeContentWidth

    private var aiReadinessRows: [SettingsReadinessRow] {
        let preferredIDs: Set<String> = ["ai", "stt", "tts", "privacy", "data-location"]
        return context.readinessGroups
            .flatMap(\.rows)
            .filter { preferredIDs.contains($0.id) }
    }

    var body: some View {
        GeometryReader { proxy in
            let layoutWidth = CockpitSplitLayout.layoutWidth(measuredWidth: proxy.size.width, authoritativeContentWidth: authoritativeContentWidth)
            let isWide = CockpitSplitLayout.presentsSplitRail(
                measuredWidth: proxy.size.width,
                authoritativeContentWidth: authoritativeContentWidth
            )
            let railWidth = CockpitSplitLayout.railWidth(for: .settings, contentWidth: layoutWidth)
            Group {
                if isWide {
                    HStack(alignment: .top, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                        aiSettingsForm
                            .cockpitSplitPrimaryColumn()
                        aiReadinessRail
                            .cockpitSplitSecondaryRail(width: railWidth)
                    }
                    .frame(width: layoutWidth, height: proxy.size.height, alignment: .topLeading)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: CGFloat(CockpitLayoutPolicy.splitSpacing)) {
                            aiSettingsForm
                            aiReadinessRail
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
