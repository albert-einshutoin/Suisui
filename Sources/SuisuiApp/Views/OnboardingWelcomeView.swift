import SuisuiCore
import SwiftUI

struct OnboardingWelcomeView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    private let permissionSnapshotProvider: @Sendable () -> PermissionSnapshot
    private let sampleProjectAction: OnboardingSampleProjectAction?
    private let requestCurrentLocationAuthorization: @MainActor () -> Void
    let onTrySuisui: (OnboardingSampleProjectEnsureResult) -> Void
    let onFinish: () -> Void

    @State private var flow = FirstRunOnboardingFlow()
    @State private var permissionSnapshot: PermissionSnapshot
    @State private var isRefreshingReadiness: Bool = false
    @State private var isCreatingSampleProject = false
    @State private var sampleProjectErrorMessage: String?
    @State private var todayPreferences: OnboardingTodayPreferences
    @State private var todayPreferencesSaveError: String?
    @State private var manualLatitudeText: String
    @State private var manualLongitudeText: String
    @Environment(\.openWindow) private var openWindow

    init(
        settingsViewModel: AppSettingsViewModel,
        permissionSnapshot: PermissionSnapshot,
        permissionSnapshotProvider: @escaping @Sendable () -> PermissionSnapshot,
        sampleProjectAction: OnboardingSampleProjectAction? = OnboardingSampleProjectFactory.makeAction(),
        requestCurrentLocationAuthorization: @escaping @MainActor () -> Void = {},
        onTrySuisui: @escaping (OnboardingSampleProjectEnsureResult) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.settingsViewModel = settingsViewModel
        self.permissionSnapshotProvider = permissionSnapshotProvider
        self.sampleProjectAction = sampleProjectAction
        self.requestCurrentLocationAuthorization = requestCurrentLocationAuthorization
        self.onTrySuisui = onTrySuisui
        self.onFinish = onFinish
        _permissionSnapshot = State(initialValue: permissionSnapshot)
        _todayPreferences = State(initialValue: OnboardingTodayPreferences(settings: settingsViewModel.settings))
        if case let .manual(_, latitude, longitude) = settingsViewModel.settings.weatherLocationPreference {
            _manualLatitudeText = State(initialValue: String(latitude))
            _manualLongitudeText = State(initialValue: String(longitude))
        } else {
            _manualLatitudeText = State(initialValue: "35.681236")
            _manualLongitudeText = State(initialValue: "139.767125")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(28)

            Divider()

            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 460, idealHeight: 500)
        .accessibilityIdentifier("onboarding-welcome")
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.step {
        case .welcome:
            welcomeStep
        case .aiProvider:
            aiProviderStep
        case .finish:
            finishStep
        }
    }

    private var welcomeStep: some View {
        onboardingStep(
            systemImage: "waveform.badge.mic",
            title: "Welcome to Suisui"
        ) {
            Text("Speak it. Review it. Move it.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Talk to Suisui. Review the draft, then move your work forward.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: SuisuiSpacing.sm) {
                onboardingFlowPill(systemImage: "tray.fill", title: "Capture")
                flowArrow
                onboardingFlowPill(systemImage: "sun.max.fill", title: "Today")
                flowArrow
                onboardingFlowPill(systemImage: "checkmark.seal", title: "Complete")
            }
            .padding(.top, SuisuiSpacing.sm)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("onboarding-flow-pills")

            if let sampleProjectErrorMessage {
                Text(verbatim: sampleProjectErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("onboarding-create-sample-error")
            }

            if todayPreferences.shouldAsk {
                todayPreferencesForm
            }
        }
    }

    private var todayPreferencesForm: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.sm) {
            Text("Make Today yours")
                .font(.headline)
            TextField("What should Suisui call you?", text: $todayPreferences.displayName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("onboarding-profile-display-name")
            Picker("Daily capacity", selection: $todayPreferences.dailyWorkCapacityMinutes) {
                ForEach(
                    Array(stride(
                        from: AppSettings.minimumDailyWorkCapacityMinutes,
                        through: AppSettings.maximumDailyWorkCapacityMinutes,
                        by: AppSettings.dailyWorkCapacityStepMinutes
                    )),
                    id: \.self
                ) { minutes in
                    Text(localizedDurationMinutes(minutes)).tag(minutes)
                }
            }
            .accessibilityIdentifier("onboarding-daily-work-capacity")
            Picker("Weather location", selection: weatherLocationModeBinding) {
                Text("Not now").tag("unset")
                Text("Use current location").tag("current")
                Text("Choose a city").tag("manual")
            }
            .accessibilityIdentifier("onboarding-weather-location")
            if weatherLocationMode == "manual" {
                TextField("City name", text: manualCityLabelBinding)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboarding-weather-city")
                HStack(spacing: SuisuiSpacing.sm) {
                    TextField("Latitude", text: manualLatitudeBinding)
                        .textFieldStyle(.roundedBorder)
                    TextField("Longitude", text: manualLongitudeBinding)
                        .textFieldStyle(.roundedBorder)
                }
                .accessibilityIdentifier("onboarding-weather-coordinates")
            }
            Text("Weather uses your choice only while showing Today and does not keep a location history.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("You can change these later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let todayPreferencesSaveError {
                Text(todayPreferencesSaveError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("onboarding-today-preferences-error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .soloCard()
        .accessibilityIdentifier("onboarding-today-preferences")
    }

    private var flowArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func onboardingFlowPill(systemImage: String, title: LocalizedStringKey) -> some View {
        VStack(spacing: SuisuiSpacing.xs) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .frame(minWidth: 72)
        .padding(.vertical, SuisuiSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }

    private var aiProviderStep: some View {
        onboardingStep(
            systemImage: "brain",
            title: "Set up your AI"
        ) {
            Text("Suisui plans with the AI provider you choose. Add an API key in Settings, or pick a local model that needs no key.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let row = selectedProviderRow {
                VStack(spacing: SuisuiSpacing.xs) {
                    Text(localizedDisplay("Selected provider: %@", row.provider.displayName))
                        .font(.headline)
                    Text(localizedSettingsDisplay(row.statusLabel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .soloCard()
                .accessibilityIdentifier("onboarding-provider-status")
            }

            Button {
                openWindow(id: "project-board")
                SuisuiInAppSettingsNavigation.requestOpen()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("onboarding-open-settings")
            .accessibilityHint("Opens Settings to choose an AI provider and store its API key in Keychain.")
        }
    }

    private var finishStep: some View {
        onboardingStep(
            systemImage: displayedPlanningState.isReady ? "checkmark.circle" : "exclamationmark.circle",
            title: displayedPlanningState.isReady ? "You're ready" : "Setup needs attention"
        ) {
            Text(
                displayedPlanningState.isReady
                    ? "Try saying: \"Plan a release checklist due next Friday.\" Review the plan, then approve it."
                    : "Suisui can open now, but planning is not ready yet. Review the required item below or finish setup later from Settings."
            )
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            readinessList

            Button {
                if displayedPlanningState.isReady {
                    completeOnboarding()
                    openWindow(id: "project-board")
                    SuisuiInAppVoiceNavigation.requestOpen()
                } else {
                    completeOnboarding()
                }
            } label: {
                Label(
                    displayedPlanningState.isReady ? "Open Voice Command" : "Finish Setup Later",
                    systemImage: displayedPlanningState.isReady ? "mic.circle" : "arrow.right.circle"
                )
            }
            .accessibilityIdentifier("onboarding-open-voice-command")
            .accessibilityHint(
                displayedPlanningState.isReady
                    ? "Finishes setup and opens Voice Command."
                    : "Closes setup. You can run setup again from Settings."
            )
        }
    }

    private var readinessSnapshot: OnboardingReadinessSnapshot {
        settingsViewModel.onboardingReadinessSnapshot(permissionSnapshot: permissionSnapshot)
    }

    /// While a refresh is in flight, force the displayed planning state to
    /// `.checking` so the sheet never shows a stale "ready" answer before the
    /// Keychain / endpoint / permission reads actually finish.
    private var displayedPlanningState: OnboardingReadinessState {
        if isRefreshingReadiness { return .checking }
        return readinessSnapshot.planningState
    }

    private var readinessList: some View {
        VStack(alignment: .leading, spacing: SuisuiSpacing.xs) {
            ForEach(Array(readinessSnapshot.items.prefix(1))) { item in
                HStack(alignment: .top, spacing: SuisuiSpacing.sm) {
                    Image(systemName: readinessSystemImage(for: item.state))
                        .foregroundStyle(readinessColor(for: item.state))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: SuisuiSpacing.xs) {
                            Text(localizedSettingsDisplay(item.title))
                                .font(.subheadline.weight(.medium))
                            Text(localizedSettingsDisplay(item.requirement == .required ? "Required" : "Optional"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(readinessLabel(for: item.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("onboarding-readiness-\(item.id)")
            }

            Button("Refresh readiness") {
                Task { @MainActor in
                    await refreshReadinessAsync()
                }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("onboarding-refresh-readiness")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .soloCard()
        .accessibilityIdentifier("onboarding-readiness-list")
    }

    private func readinessSystemImage(for state: OnboardingReadinessState) -> String {
        switch state {
        case .ready:
            "checkmark.circle.fill"
        case .needsAction:
            "exclamationmark.triangle.fill"
        case .unavailable:
            "xmark.octagon.fill"
        case .unknown, .checking:
            "circle.dashed"
        }
    }

    private func readinessColor(for state: OnboardingReadinessState) -> Color {
        switch state {
        case .ready:
            .green
        case .needsAction:
            .orange
        case .unavailable:
            .red
        case .unknown, .checking:
            .secondary
        }
    }

    private func readinessLabel(for state: OnboardingReadinessState) -> String {
        switch state {
        case .ready:
            localizedSettingsDisplay("Ready")
        case .checking:
            localizedSettingsDisplay("Checking…")
        case .unknown:
            localizedSettingsDisplay("Status unknown")
        case let .needsAction(reason):
            localizedDisplay("Action needed: %@", localizedSettingsDisplay(reason))
        case let .unavailable(reason):
            localizedDisplay("Unavailable: %@", localizedSettingsDisplay(reason))
        }
    }

    @MainActor
    private func refreshReadinessAsync() async {
        isRefreshingReadiness = true
        defer { isRefreshingReadiness = false }

        // Provider Keychain reads block on TCC/semaphore calls; resolve them
        // off MainActor before we touch the published state.
        let resolvedSnapshot: PermissionSnapshot = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: permissionSnapshotProvider())
            }
        }

        await settingsViewModel.refreshProviderReadiness()

        permissionSnapshot = resolvedSnapshot
    }

    private func onboardingStep(
        systemImage: String,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: SuisuiSpacing.lg) {
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 76, height: 76)
                .background(
                    Circle()
                        .fill(.tint.opacity(0.12))
                )
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("Skip Setup") {
                completeOnboarding()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("onboarding-skip")
            .accessibilityHint("Closes setup. You can configure everything later in Settings.")

            Spacer()

            if flow.step == .welcome {
                Button("Set up AI first") {
                    saveTodayPreferencesThen {
                        flow.advance()
                        Task { @MainActor in
                            await refreshReadinessAsync()
                        }
                    }
                }
                .accessibilityIdentifier("onboarding-set-up-ai")

                Button("Try Suisui now") {
                    saveTodayPreferencesThen(createSampleProject)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreatingSampleProject || sampleProjectAction == nil)
                .accessibilityIdentifier("onboarding-try-suisui")
                .accessibilityHint("Creates or reuses Learn Suisui, opens Today, and selects the first lesson.")
            } else {
                Button("Back") {
                    flow.goBack()
                }
                .accessibilityIdentifier("onboarding-back")

                if flow.isLastStep {
                    Button(readinessSnapshot.planningState.isReady ? "Start Using Suisui" : "Finish Setup Later") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-finish")
                } else {
                    Button("Continue") {
                        flow.advance()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("onboarding-continue")
                }
            }
        }
    }

    private var selectedProviderRow: AIProviderReadinessRow? {
        settingsViewModel.providerReadinessRows.first(where: { $0.isSelected })
    }

    private var weatherLocationMode: String {
        switch todayPreferences.weatherLocationPreference {
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
                    todayPreferences.weatherLocationPreference = .currentLocation
                    requestCurrentLocationAuthorization()
                case "manual":
                    let current = manualCoordinateValues
                    todayPreferences.weatherLocationPreference = .manual(
                        cityLabel: current.label,
                        latitude: current.latitude,
                        longitude: current.longitude
                    ).normalized
                default:
                    todayPreferences.weatherLocationPreference = .unset
                }
            }
        )
    }

    private var manualCoordinateValues: (label: String, latitude: Double, longitude: Double) {
        if case let .manual(label, latitude, longitude) = todayPreferences.weatherLocationPreference {
            return (label, latitude, longitude)
        }
        return ("Tokyo", 35.681236, 139.767125)
    }

    private var manualCityLabelBinding: Binding<String> {
        Binding(
            get: { manualCoordinateValues.label },
            set: { updateManualPreference(label: $0, latitude: manualCoordinateValues.latitude, longitude: manualCoordinateValues.longitude) }
        )
    }

    private var manualLatitudeBinding: Binding<String> {
        Binding(
            get: { manualLatitudeText },
            set: {
                manualLatitudeText = $0
                guard let latitude = Double($0) else { return }
                updateManualPreference(label: manualCoordinateValues.label, latitude: latitude, longitude: manualCoordinateValues.longitude)
            }
        )
    }

    private var manualLongitudeBinding: Binding<String> {
        Binding(
            get: { manualLongitudeText },
            set: {
                manualLongitudeText = $0
                guard let longitude = Double($0) else { return }
                updateManualPreference(label: manualCoordinateValues.label, latitude: manualCoordinateValues.latitude, longitude: longitude)
            }
        )
    }

    private func updateManualPreference(label: String, latitude: Double, longitude: Double) {
        todayPreferences.weatherLocationPreference = .manual(
            cityLabel: label,
            latitude: latitude,
            longitude: longitude
        )
    }

    private func createSampleProject() {
        guard let sampleProjectAction, !isCreatingSampleProject else {
            return
        }
        isCreatingSampleProject = true
        defer { isCreatingSampleProject = false }
        do {
            let outcome = try sampleProjectAction.run()
            sampleProjectErrorMessage = nil
            onTrySuisui(outcome)
        } catch {
            sampleProjectErrorMessage = localizedDisplay("Could not create the sample project.")
        }
    }

    private func saveTodayPreferencesThen(_ action: () -> Void) {
        guard todayPreferences.shouldAsk else {
            action()
            return
        }
        guard settingsViewModel.saveOnboardingTodayPreferences(todayPreferences) else {
            todayPreferencesSaveError = localizedDisplay("Could not save your Today preferences.")
            return
        }
        todayPreferencesSaveError = nil
        action()
    }

    private func completeOnboarding() {
        onFinish()
    }
}
