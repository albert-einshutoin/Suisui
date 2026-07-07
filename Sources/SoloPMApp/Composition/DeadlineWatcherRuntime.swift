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

    private var timer: Timer?
    private var didStart = false

    func start() {
        guard !didStart else {
            return
        }
        // Notification scheduling requires a real app bundle (see
        // SoloPMNotificationResponder); bare debug binaries skip the watcher.
        guard Bundle.main.bundleIdentifier != nil else {
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

    private nonisolated static func tick(reason: DailyCheckReason) {
        Task.detached(priority: .utility) {
            if let runner = try? AppRuntimeFactory.makeSafeDailyCheckRunner() {
                _ = runner.run(reason: reason)
            }
            if let digest = try? AppRuntimeFactory.makeMorningDigestScheduler() {
                _ = digest.scheduleIfNeeded()
            }
            await MainActor.run {
                DockTileBadgeController.shared.refresh()
            }
        }
    }
}
