import Foundation
import SoloPMCore

extension AppRuntimeFactory {
    static func makeSafeDailyCheckRunner() throws -> SafeDailyCheckRunner {
        let connection = try migratedConnection()
        let settings = loadRuntimeSettings().settings
        let queryService = DeadlineQueryService(
            projectStore: SQLiteProjectStore(connection: connection),
            taskStore: SQLiteTaskStore(connection: connection),
            settings: settings
        )
        let ruleStore = SQLiteDeadlineRuleStore(connection: connection)
        let auditLogger = try? makeAuditLogger()
        let runner = DailyCheckRunner(
            overdueChecker: OverdueChecker(
                queryService: queryService,
                ruleStore: ruleStore,
                settings: settings
            ),
            notificationScheduler: DeadlineNotificationScheduler(
                notificationClient: UserNotificationsNotificationClient(),
                settings: settings
            ),
            ruleStore: ruleStore,
            stateStore: SQLiteDailyCheckStateStore(connection: connection),
            settings: settings,
            auditLogger: auditLogger
        )
        return SafeDailyCheckRunner(runner: runner, auditLogger: auditLogger)
    }

    static func makeMorningDigestScheduler() throws -> MorningDigestScheduler {
        let connection = try migratedConnection()
        let settings = loadRuntimeSettings().settings
        return MorningDigestScheduler(
            queryService: DeadlineQueryService(
                projectStore: SQLiteProjectStore(connection: connection),
                taskStore: SQLiteTaskStore(connection: connection),
                settings: settings
            ),
            stateStore: SQLiteMorningDigestStateStore(connection: connection),
            notificationClient: UserNotificationsNotificationClient(),
            settings: settings
        )
    }

    static func makeWeeklyReviewSummaryScheduler() throws -> WeeklyReviewSummaryScheduler {
        let connection = try migratedConnection()
        let settings = loadRuntimeSettings().settings
        return WeeklyReviewSummaryScheduler(
            taskStore: SQLiteTaskStore(connection: connection),
            stateStore: SQLiteWeeklyReviewSummaryStateStore(connection: connection),
            notificationClient: UserNotificationsNotificationClient(),
            settings: settings
        )
    }
}

/// Activates the deadline watcher for real app launches: the daily check and
/// the morning digest run shortly after launch and then on a repeating
/// interval, so notifications fire even when the user never opens a window.
/// Both underlying runners are once-per-day idempotent, which makes frequent
/// ticks safe and lets the watcher catch midnight rollovers and Macs waking
/// from sleep.
@MainActor
final class DeadlineWatcherRuntime {
    static let shared = DeadlineWatcherRuntime()

    private static let initialDelay: TimeInterval = 8
    private static let tickInterval: TimeInterval = 30 * 60
    private static let harnessEnvironmentKeys = [
        "SOLOPM_DATABASE_PATH",
        "SOLOPM_LAUNCH_RECOVERY_MODE",
        "SOLOPM_FORCE_PROJECT_BOARD_FALLBACK",
        "SOLOPM_UI_EVIDENCE_RECOVERY_MODE",
        "SOLOPM_RUNTIME_CRUD_RECOVERY_MODE",
        "SOLOPM_LAYOUT_STABILITY_RECOVERY_MODE",
        "SOLOPM_OPEN_SETTINGS_ON_LAUNCH",
        "SOLOPM_OPEN_VOICE_COMMAND_ON_LAUNCH",
        "SOLOPM_RUNTIME_DEVELOPMENT_PR_SMOKE_BOOKMARK"
    ]

    private var timer: Timer?
    private var didStart = false

    func start(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard !didStart else {
            return
        }
        guard Self.shouldStart(environment: environment, bundleIdentifier: bundleIdentifier) else {
            return
        }
        didStart = true

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialDelay) {
            DeadlineWatcherRuntime.tick(reason: .appLaunch)
        }

        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { _ in
            DeadlineWatcherRuntime.tick(reason: .scheduledDaily)
        }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func shouldStart(environment: [String: String], bundleIdentifier: String?) -> Bool {
        // Notification scheduling requires a real app bundle (see
        // SoloPMNotificationResponder), while release/evidence harnesses use
        // isolated app-bundle launches whose databases and timing must stay
        // deterministic. Keep the background watcher out of those runs.
        guard bundleIdentifier != nil else {
            return false
        }
        return !harnessEnvironmentKeys.contains { key in
            guard let value = environment[key], !value.isEmpty else {
                return false
            }
            return key == "SOLOPM_DATABASE_PATH" || value == "1"
        }
    }

    private nonisolated static func tick(reason: DailyCheckReason) {
        Task.detached(priority: .utility) {
            if let runner = try? AppRuntimeFactory.makeSafeDailyCheckRunner() {
                _ = runner.run(reason: reason)
            }
            if let digest = try? AppRuntimeFactory.makeMorningDigestScheduler() {
                _ = digest.scheduleIfNeeded()
            }
            if let weeklyReview = try? AppRuntimeFactory.makeWeeklyReviewSummaryScheduler() {
                _ = weeklyReview.scheduleIfNeeded()
            }
            await MainActor.run {
                DockTileBadgeController.shared.refresh()
            }
        }
    }
}
