import AppKit
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI

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
