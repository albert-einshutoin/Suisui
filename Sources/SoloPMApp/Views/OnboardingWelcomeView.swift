import SoloPMCore
import SwiftUI

struct OnboardingWelcomeView: View {
    @ObservedObject var settingsViewModel: AppSettingsViewModel
    let onFinish: () -> Void

    @State private var flow = FirstRunOnboardingFlow()
    @Environment(\.openWindow) private var openWindow

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
        case .permissions:
            permissionsStep
        case .finish:
            finishStep
        }
    }

    private var welcomeStep: some View {
        onboardingStep(
            systemImage: "waveform.badge.mic",
            title: "Welcome to SoloPM"
        ) {
            Text("Speak or type what you need to do. SoloPM drafts the tasks, events, and reminders for you, and writes nothing until you approve it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var aiProviderStep: some View {
        onboardingStep(
            systemImage: "brain",
            title: "Set up your AI"
        ) {
            Text("SoloPM plans with the AI provider you choose. Add an API key in Settings, or pick a local model that needs no key.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if let row = selectedProviderRow {
                VStack(spacing: 4) {
                    Text(localizedDisplay("Selected provider: %@", row.provider.displayName))
                        .font(.headline)
                    Text(localizedSettingsDisplay(row.statusLabel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .accessibilityIdentifier("onboarding-provider-status")
            }

            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("onboarding-open-settings")
            .accessibilityHint("Opens Settings to choose an AI provider and store its API key in Keychain.")
        }
    }

    private var permissionsStep: some View {
        onboardingStep(
            systemImage: "checkmark.shield",
            title: "Connect your Mac"
        ) {
            Text("SoloPM works with your microphone, Calendar, Reminders, and Notifications. macOS asks for each permission the first time it is needed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Microphone", systemImage: "mic")
                Label("Calendar", systemImage: "calendar")
                Label("Reminders", systemImage: "checklist")
                Label("Notifications", systemImage: "bell")
            }
            .font(.subheadline)
            .padding(.top, 4)
            .accessibilityIdentifier("onboarding-permission-list")
        }
    }

    private var finishStep: some View {
        onboardingStep(
            systemImage: "checkmark.circle",
            title: "You're ready"
        ) {
            Text("Try saying: \"Plan a release checklist due next Friday.\" Review the plan, then approve it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                completeOnboarding()
                openWindow(id: "voice-capture")
            } label: {
                Label("Open Voice Command", systemImage: "mic.circle")
            }
            .accessibilityIdentifier("onboarding-open-voice-command")
            .accessibilityHint("Finishes setup and opens the Voice Command window.")
        }
    }

    private func onboardingStep(
        systemImage: String,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)
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

            Text(localizedDisplay("Step %d of %d", flow.stepIndex + 1, flow.stepCount))
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding-step-indicator")

            Spacer()

            if !flow.isFirstStep {
                Button("Back") {
                    flow.goBack()
                }
                .accessibilityIdentifier("onboarding-back")
            }

            if flow.isLastStep {
                Button("Start Using SoloPM") {
                    completeOnboarding()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-finish")
            } else {
                Button("Continue") {
                    flow.advance()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding-continue")
            }
        }
    }

    private var selectedProviderRow: AIProviderReadinessRow? {
        settingsViewModel.providerReadinessRows.first(where: { $0.isSelected })
    }

    private func completeOnboarding() {
        onFinish()
    }
}
