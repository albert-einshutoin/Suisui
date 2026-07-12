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

public extension Notification.Name {
    /// Posted after any write that changes Project Board content so open board
    /// windows reload. Defined in core (Foundation-only) so store-level
    /// writers like the onboarding sample creator can signal the board; the
    /// app layer reuses this constant instead of redeclaring it.
    static let soloPMProjectBoardDidChange = Notification.Name("dev.solopm.projectBoardDidChange")
}

// MARK: - Onboarding sample project

/// Pure data description of one "Learn SoloPM" practice task. The English
/// strings double as localization keys: the app passes `localizedDisplay`
/// into `OnboardingSampleProjectCreator` so titles and details are localized
/// at creation time (mirroring how smart list preset names route static
/// known strings through the app localization table).
public struct OnboardingSampleTaskDefinition: Equatable, Sendable {
    public enum DueDate: Equatable, Sendable {
        case none
        case todayAt(hour: Int, minute: Int)
        case tomorrowAt(hour: Int, minute: Int)
    }

    public let title: String
    public let detail: String
    public let priority: ProjectTaskPriority?
    public let recurrence: String?
    public let due: DueDate

    public init(
        title: String,
        detail: String,
        priority: ProjectTaskPriority? = nil,
        recurrence: String? = nil,
        due: DueDate = .none
    ) {
        self.title = title
        self.detail = detail
        self.priority = priority
        self.recurrence = recurrence
        self.due = due
    }
}

public enum OnboardingSampleProjectDefinition {
    public static let projectTitle = "Learn SoloPM"
    /// Stable marker persisted in `projects.source_command` so the sample can
    /// be recognized even if the defaults flag is lost.
    public static let projectMarkerSourceCommand = "onboarding-sample"
    /// Defaults flag that makes sample creation a one-shot action.
    public static let createdDefaultsKey = "solopm.onboarding.sampleProjectCreated"

    /// Six tasks that each teach a real SoloPM feature. The weekly task also
    /// carries a due date because completion-driven recurrence needs one to
    /// schedule the next occurrence (see `TaskRecurrence`).
    public static let tasks: [OnboardingSampleTaskDefinition] = [
        OnboardingSampleTaskDefinition(
            title: "Press ⌘K and search for anything",
            detail: "The command palette matches views, projects, smart lists, and even task content. Try typing part of this sentence.",
            priority: .high,
            due: .todayAt(hour: 18, minute: 0)
        ),
        OnboardingSampleTaskDefinition(
            title: "Drag this task to another column",
            detail: "Kanban columns map to task status. Dropping a card updates the task immediately.",
            priority: .medium
        ),
        OnboardingSampleTaskDefinition(
            title: "Press ⌘Z to undo your last change",
            detail: "Board operations such as complete, move, and edit go onto an undo stack. ⌘Z reverts the latest one.",
            priority: .low
        ),
        OnboardingSampleTaskDefinition(
            title: "Say a task out loud in the Voice window",
            detail: "Open Voice Command from the toolbar or the ⌘K palette, then speak. SoloPM drafts a plan you approve before anything is written.",
            priority: .medium
        ),
        OnboardingSampleTaskDefinition(
            title: "Set a due date by typing 'tomorrow' in Quick Add",
            detail: "Quick Add understands natural-language dates such as 'tomorrow' or 'next Friday' and files the task with the right due date.",
            due: .tomorrowAt(hour: 9, minute: 0)
        ),
        OnboardingSampleTaskDefinition(
            title: "This task repeats weekly — complete it to see the next one appear",
            detail: "Completing a recurring task automatically schedules the next occurrence one week later.",
            recurrence: "weekly",
            due: .todayAt(hour: 10, minute: 0)
        )
    ]
}

public struct OnboardingSampleProjectCreationResult: Equatable, Sendable {
    public let project: ProjectRecord
    public let tasks: [TaskRecord]

    public init(project: ProjectRecord, tasks: [TaskRecord]) {
        self.project = project
        self.tasks = tasks
    }
}

/// Creates the "Learn SoloPM" sample project through the normal store create
/// paths. Stores, defaults, clock, and localization are injected
/// (VoiceRuntimeFactory-style) so tests can drive it against a temporary
/// SQLite database; the app wires it in `OnboardingSampleProjectFactory`.
public final class OnboardingSampleProjectCreator: @unchecked Sendable {
    private let projectStore: SQLiteProjectStore
    private let taskStore: SQLiteTaskStore
    private let defaults: UserDefaults
    private let dateProvider: any DateProvider
    private let timeZoneIdentifier: String
    private let localize: @Sendable (String) -> String
    private let notificationCenter: NotificationCenter

    public init(
        projectStore: SQLiteProjectStore,
        taskStore: SQLiteTaskStore,
        defaults: UserDefaults = .standard,
        dateProvider: any DateProvider = SystemDateProvider(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        localize: @escaping @Sendable (String) -> String = { $0 },
        notificationCenter: NotificationCenter = .default
    ) {
        self.projectStore = projectStore
        self.taskStore = taskStore
        self.defaults = defaults
        self.dateProvider = dateProvider
        self.timeZoneIdentifier = timeZoneIdentifier
        self.localize = localize
        self.notificationCenter = notificationCenter
    }

    /// Idempotent: returns nil without writing anything when the sample was
    /// already created (defaults flag) or a marked project already exists in
    /// the database (covers defaults resets while the database persists).
    @discardableResult
    public func createSampleProjectIfNeeded() throws -> OnboardingSampleProjectCreationResult? {
        guard !defaults.bool(forKey: OnboardingSampleProjectDefinition.createdDefaultsKey) else {
            return nil
        }
        if let projects = try? projectStore.list(includeArchived: true),
           projects.contains(where: { $0.sourceCommand == OnboardingSampleProjectDefinition.projectMarkerSourceCommand }) {
            defaults.set(true, forKey: OnboardingSampleProjectDefinition.createdDefaultsKey)
            return nil
        }

        let project = try projectStore.create(
            title: localize(OnboardingSampleProjectDefinition.projectTitle),
            sourceCommand: OnboardingSampleProjectDefinition.projectMarkerSourceCommand
        )
        var tasks: [TaskRecord] = []
        for definition in OnboardingSampleProjectDefinition.tasks {
            tasks.append(
                try taskStore.create(
                    title: localize(definition.title),
                    projectID: project.id,
                    dueAt: dueAtString(for: definition.due),
                    priority: definition.priority?.rawValue,
                    sourceCommand: OnboardingSampleProjectDefinition.projectMarkerSourceCommand,
                    detail: localize(definition.detail),
                    recurrence: definition.recurrence
                )
            )
        }
        defaults.set(true, forKey: OnboardingSampleProjectDefinition.createdDefaultsKey)
        notificationCenter.post(name: .soloPMProjectBoardDidChange, object: nil)
        return OnboardingSampleProjectCreationResult(project: project, tasks: tasks)
    }

    private func dueAtString(for due: OnboardingSampleTaskDefinition.DueDate) -> String? {
        switch due {
        case .none:
            return nil
        case let .todayAt(hour, minute):
            return isoDueString(daysFromToday: 0, hour: hour, minute: minute)
        case let .tomorrowAt(hour, minute):
            return isoDueString(daysFromToday: 1, hour: hour, minute: minute)
        }
    }

    private func isoDueString(daysFromToday: Int, hour: Int, minute: Int) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let startOfDay = calendar.startOfDay(for: dateProvider.now)
        guard let day = calendar.date(byAdding: .day, value: daysFromToday, to: startOfDay),
              let dueDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
            return nil
        }
        return ISO8601DateFormatter().string(from: dueDate)
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
