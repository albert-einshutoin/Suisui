import AppKit
import SuisuiCore
import SuisuiGoogleCalendarRuntime
import SwiftUI

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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-privacy-root")
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
