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

public enum OnboardingRequirement: String, Equatable, Sendable {
    case required
    case optional
}

public enum OnboardingReadinessState: Equatable, Sendable {
    case unknown
    case checking
    case ready
    case needsAction(reason: String)
    case unavailable(reason: String)

    public var isReady: Bool {
        self == .ready
    }

    public var reason: String? {
        switch self {
        case let .needsAction(reason), let .unavailable(reason):
            reason
        case .unknown, .checking, .ready:
            nil
        }
    }
}

public struct OnboardingReadinessItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let requirement: OnboardingRequirement
    public let state: OnboardingReadinessState

    public init(
        id: String,
        title: String,
        requirement: OnboardingRequirement,
        state: OnboardingReadinessState
    ) {
        self.id = id
        self.title = title
        self.requirement = requirement
        self.state = state
    }
}

public struct OnboardingReadinessSnapshot: Equatable, Sendable {
    public let selectedProvider: AIProvider
    public let planningState: OnboardingReadinessState
    public let items: [OnboardingReadinessItem]

    public var canStartUsing: Bool {
        // Optional integrations must never block the local-first core. The
        // selected provider remains visible as the required planning gate.
        true
    }

    public init(
        selectedProvider: AIProvider,
        planningState: OnboardingReadinessState,
        items: [OnboardingReadinessItem]
    ) {
        self.selectedProvider = selectedProvider
        self.planningState = planningState
        self.items = items
    }

    public static func make(
        selectedProvider: AIProvider,
        providerReadiness: AIProviderReadiness,
        permissions: PermissionSnapshot
    ) -> OnboardingReadinessSnapshot {
        let planningState: OnboardingReadinessState
        switch providerReadiness {
        case .unknown:
            planningState = .unknown
        case .checking:
            planningState = .checking
        case .ready:
            planningState = .ready
        case let .needsAction(reason):
            planningState = .needsAction(reason: reason)
        case let .unavailable(reason):
            planningState = .unavailable(reason: reason)
        }

        let items = [
            OnboardingReadinessItem(
                id: "ai-provider",
                title: "AI provider",
                requirement: .required,
                state: planningState
            ),
            permissionItem(
                id: "microphone",
                title: "Microphone",
                permission: .microphone,
                permissions: permissions
            ),
            permissionItem(
                id: "calendar",
                title: "Calendar",
                permission: .calendar,
                permissions: permissions
            ),
            permissionItem(
                id: "reminders",
                title: "Reminders",
                permission: .reminders,
                permissions: permissions
            ),
            permissionItem(
                id: "notifications",
                title: "Notifications",
                permission: .notifications,
                permissions: permissions
            )
        ]

        return OnboardingReadinessSnapshot(
            selectedProvider: selectedProvider,
            planningState: planningState,
            items: items
        )
    }

    private static func permissionItem(
        id: String,
        title: String,
        permission: AppPermission,
        permissions: PermissionSnapshot
    ) -> OnboardingReadinessItem {
        let state: OnboardingReadinessState
        switch permissions.status(for: permission) {
        case .granted:
            state = .ready
        case .notDetermined:
            state = .needsAction(reason: "Permission has not been requested yet.")
        case .denied:
            state = .needsAction(reason: "Permission is denied. Review it in System Settings when needed.")
        case .restricted:
            state = .unavailable(reason: "This permission is restricted by macOS.")
        }

        return OnboardingReadinessItem(
            id: id,
            title: title,
            requirement: .optional,
            state: state
        )
    }
}

public enum FirstRunOnboardingGate {
    public static let completionDefaultsKey = "solopm.onboarding.completed"
    public static let dismissedDefaultsKey = "solopm.onboarding.dismissed"
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
        shouldPresent(hasDismissedOnboarding: hasCompletedOnboarding, environment: environment)
    }

    public static func shouldPresent(
        hasDismissedOnboarding: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard !hasDismissedOnboarding else {
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

    public static func migrateLegacyCompletionIfNeeded(defaults: UserDefaults) {
        guard defaults.object(forKey: dismissedDefaultsKey) == nil,
              defaults.bool(forKey: completionDefaultsKey) else {
            return
        }
        // The old key meant “do not show this modal again”, not that the
        // integrations were ready. Preserve that UX choice without making the
        // legacy completion bit the source of truth for current readiness.
        defaults.set(true, forKey: dismissedDefaultsKey)
    }
}

/// App-level owner of the onboarding rerun request. Multiple Project Board
/// windows can register themselves; only the primary window receives the
/// rerun so the Settings button always opens exactly one setup flow even when
/// no Project Board window is mounted yet.
@MainActor
public final class OnboardingRerunCoordinator: ObservableObject {
    public static let shared = OnboardingRerunCoordinator()

    @Published public private(set) var primaryWindowID: UUID?
    @Published public private(set) var rerunRequestToken: UUID?
    @Published public private(set) var lastHandledToken: UUID?

    private var registrations: [UUID: Date] = [:]
    private var insertionOrder: [UUID] = []

    public init() {}

    @discardableResult
    public func register(windowID: UUID = UUID()) -> Bool {
        if registrations[windowID] == nil {
            registrations[windowID] = Date()
            insertionOrder.append(windowID)
            if primaryWindowID == nil {
                primaryWindowID = windowID
            }
        }
        return primaryWindowID == windowID
    }

    public func unregister(windowID: UUID) {
        guard registrations.removeValue(forKey: windowID) != nil else {
            return
        }
        insertionOrder.removeAll { $0 == windowID }
        if primaryWindowID == windowID {
            primaryWindowID = insertionOrder.first
        }
    }

    public func requestRerun() {
        rerunRequestToken = UUID()
    }

    /// Atomic check-and-mark: returns the pending rerun token only if the
    /// caller is the current primary window, the token has not been handled
    /// already, and one is currently pending. Using this single entry point
    /// from both `onAppear` (after `register`) and the published-token
    /// observer guarantees the Settings button always opens exactly one
    /// onboarding sheet — even when no Project Board window is mounted yet at
    /// the moment `requestRerun()` fires.
    @discardableResult
    public func consumePendingRerun(for windowID: UUID) -> UUID? {
        guard primaryWindowID == windowID else {
            return nil
        }
        guard let token = rerunRequestToken else {
            return nil
        }
        guard token != lastHandledToken else {
            return nil
        }
        lastHandledToken = token
        return token
    }

    public func markHandled(token: UUID) {
        lastHandledToken = token
    }

    public func snapshotForTests() -> (primary: UUID?, registered: [UUID]) {
        (primaryWindowID, insertionOrder)
    }
}
