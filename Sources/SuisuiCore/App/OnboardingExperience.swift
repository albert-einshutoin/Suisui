public struct OnboardingExperience: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case trySuisui
        case setUpAI
        case skip
    }

    public enum Capability: Equatable, Sendable {
        case ai
        case voice
        case calendar
        case reminders
        case notifications
    }

    public static let initial = OnboardingExperience(
        primaryAction: .trySuisui,
        secondaryAction: .setUpAI,
        requestedPermissions: []
    )

    public static let learnProjectTargetRoute: BoardRoute = .primary(.today)

    public let primaryAction: Action
    public let secondaryAction: Action
    public let requestedPermissions: Set<AppPermission>

    public init(
        primaryAction: Action,
        secondaryAction: Action,
        requestedPermissions: Set<AppPermission>
    ) {
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.requestedPermissions = requestedPermissions
    }

    /// Permissions follow an explicit capability choice so first launch stays
    /// local-first and macOS prompts remain connected to the user's intent.
    public static func permissions(for capability: Capability) -> Set<AppPermission> {
        switch capability {
        case .ai:
            []
        case .voice:
            [.microphone]
        case .calendar:
            [.calendar]
        case .reminders:
            [.reminders]
        case .notifications:
            [.notifications]
        }
    }
}

public struct OnboardingLessonFocusIntent: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case select(Int64)
        case completed
    }

    public private(set) var pendingTaskID: Int64?
    private var consecutiveSelectionObservations = 0

    public init(taskID: Int64?) {
        pendingTaskID = taskID
    }

    /// A route transition can clear selection after the lesson first becomes
    /// visible. Reapply until two observations confirm the target stayed
    /// selected, then consume the one-shot intent.
    public mutating func nextAction(
        visibleTaskIDs: Set<Int64>,
        selectedTaskID: Int64?
    ) -> Action? {
        guard let pendingTaskID else {
            return nil
        }
        guard visibleTaskIDs.contains(pendingTaskID) else {
            consecutiveSelectionObservations = 0
            return nil
        }
        guard selectedTaskID == pendingTaskID else {
            consecutiveSelectionObservations = 0
            return .select(pendingTaskID)
        }
        consecutiveSelectionObservations += 1
        guard consecutiveSelectionObservations >= 2 else {
            return nil
        }
        self.pendingTaskID = nil
        consecutiveSelectionObservations = 0
        return .completed
    }
}

public struct OnboardingTargetedRouteRetryPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case retry
        case awaitApplication
        case exhausted
    }

    public let maximumAttempts: Int

    public init(maximumAttempts: Int = 100) {
        precondition(maximumAttempts > 0, "Route retry attempts must be above zero")
        self.maximumAttempts = maximumAttempts
    }

    /// A targeted scene request is rejected until that scene is registered.
    /// Treat that temporary nil as retryable, while keeping the wait bounded.
    public func decision(afterAttempt attempt: Int, requestWasAccepted: Bool) -> Decision {
        precondition(attempt > 0, "Route retry attempt must be above zero")
        if requestWasAccepted {
            return .awaitApplication
        }
        return attempt < maximumAttempts ? .retry : .exhausted
    }
}
