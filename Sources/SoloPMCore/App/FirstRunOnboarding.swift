import Foundation

public enum FirstRunOnboardingStep: String, CaseIterable, Equatable, Sendable {
    case welcome
    case aiProvider
    case permissions
    case finish
}

public struct FirstRunOnboardingFlow: Equatable, Sendable {
    public private(set) var step: FirstRunOnboardingStep

    public init(step: FirstRunOnboardingStep = .welcome) {
        self.step = step
    }

    public var isFirstStep: Bool {
        step == FirstRunOnboardingStep.allCases.first
    }

    public var isLastStep: Bool {
        step == FirstRunOnboardingStep.allCases.last
    }

    public var stepIndex: Int {
        FirstRunOnboardingStep.allCases.firstIndex(of: step) ?? 0
    }

    public var stepCount: Int {
        FirstRunOnboardingStep.allCases.count
    }

    public mutating func advance() {
        let steps = FirstRunOnboardingStep.allCases
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else {
            return
        }
        step = steps[index + 1]
    }

    public mutating func goBack() {
        let steps = FirstRunOnboardingStep.allCases
        guard let index = steps.firstIndex(of: step), index > 0 else {
            return
        }
        step = steps[index - 1]
    }
}

public enum FirstRunOnboardingGate {
    public static let completionDefaultsKey = "solopm.onboarding.completed"
    public static let disableEnvironmentKey = "SOLOPM_DISABLE_ONBOARDING"

    // Evidence, smoke, and launch-verification harnesses drive the real app
    // and must never sit behind a first-run sheet.
    private static let harnessEnvironmentKeys = [
        "SOLOPM_DATABASE_PATH",
        "SOLOPM_LAUNCH_RECOVERY_MODE",
        "SOLOPM_FORCE_PROJECT_BOARD_FALLBACK",
        "SOLOPM_OPEN_SETTINGS_ON_LAUNCH",
        "SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH"
    ]

    public static func shouldPresent(
        hasCompletedOnboarding: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard !hasCompletedOnboarding else {
            return false
        }
        if environment[disableEnvironmentKey] == "1" {
            return false
        }
        for key in harnessEnvironmentKeys {
            if let value = environment[key], !value.isEmpty {
                return false
            }
        }
        return true
    }
}
