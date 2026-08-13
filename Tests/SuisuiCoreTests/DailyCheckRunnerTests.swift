import XCTest
@testable import SuisuiCore

final class DailyCheckRunnerTests: XCTestCase {
    func testRunnerSkipsWhenAlreadyCheckedToday() throws {
        let stores = try makeStores()
        let stateStore = InMemoryDailyCheckStateStore(lastRunAt: try Date.iso8601("2026-06-17T01:00:00Z"))
        let logger = InMemoryAuditLogger()
        let runner = try makeRunner(stores: stores, stateStore: stateStore, logger: logger)

        let result = try runner.runIfNeeded(reason: .appLaunch)

        XCTAssertEqual(result.status, .skippedAlreadyRanToday)
        XCTAssertEqual(result.scheduledCount, 0)
        XCTAssertEqual(logger.recordedEvents.last?.status, .skipped)
        XCTAssertEqual(logger.recordedEvents.last?.metadata["reason"], "app_launch")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["scan_count"], "0")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["notification_planned_count"], "0")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["skip_reason"], "already_ran_today")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["error"], "")
    }

    func testRunnerRunsMissedCheckSchedulesOverdueNotificationAndAuditsResult() throws {
        let stores = try makeStores()
        let overdue = try stores.tasks.create(title: "Review alpha", dueAt: "2026-06-16T12:00:00Z")
        let rule = try stores.rules.create(DeadlineRule(target: .task(overdue.id), kind: .overdueDaily))
        let stateStore = InMemoryDailyCheckStateStore(lastRunAt: try Date.iso8601("2026-06-16T01:00:00Z"))
        let notificationClient = InMemoryNotificationClient()
        let logger = InMemoryAuditLogger()
        let runner = try makeRunner(
            stores: stores,
            stateStore: stateStore,
            notificationClient: notificationClient,
            logger: logger
        )

        let result = try runner.runIfNeeded(reason: .appLaunch)

        XCTAssertEqual(result.status, .ran)
        XCTAssertEqual(result.overdueCount, 1)
        XCTAssertEqual(result.scheduledCount, 1)
        XCTAssertEqual(try notificationClient.listScheduled().first?.title, "Deadline: Review alpha")
        XCTAssertEqual(try stores.rules.get(id: try XCTUnwrap(rule.id)).lastNotifiedAt, try Date.iso8601("2026-06-17T12:00:00Z"))
        XCTAssertEqual(try stateStore.lastRunAt(), try Date.iso8601("2026-06-17T12:00:00Z"))
        XCTAssertEqual(logger.recordedEvents.last?.category, "deadline_watcher")
        XCTAssertEqual(logger.recordedEvents.last?.action, "daily_check")
        XCTAssertEqual(logger.recordedEvents.last?.status, .succeeded)
        XCTAssertEqual(logger.recordedEvents.last?.metadata["scheduled_count"], "1")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["scan_count"], "1")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["notification_planned_count"], "1")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["skip_reason"], "")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["error"], "")
    }

    func testRunnerDoesNotScheduleDuplicateDailyNotificationForSameOverdueTask() throws {
        let stores = try makeStores()
        let overdue = try stores.tasks.create(title: "Review alpha", dueAt: "2026-06-16T12:00:00Z")
        _ = try stores.rules.create(DeadlineRule(target: .task(overdue.id), kind: .overdueDaily))
        let notificationClient = InMemoryNotificationClient()
        let firstRunner = try makeRunner(
            stores: stores,
            stateStore: InMemoryDailyCheckStateStore(lastRunAt: try Date.iso8601("2026-06-16T01:00:00Z")),
            notificationClient: notificationClient,
            logger: InMemoryAuditLogger()
        )
        let forcedSameDayRunner = try makeRunner(
            stores: stores,
            stateStore: InMemoryDailyCheckStateStore(lastRunAt: try Date.iso8601("2026-06-16T01:00:00Z")),
            notificationClient: notificationClient,
            logger: InMemoryAuditLogger()
        )

        let first = try firstRunner.runIfNeeded(reason: .scheduledDaily)
        let second = try forcedSameDayRunner.runIfNeeded(reason: .manual)

        XCTAssertEqual(first.scheduledCount, 1)
        XCTAssertEqual(second.scheduledCount, 0)
        XCTAssertEqual(second.skippedCount, 1)
        XCTAssertEqual(second.skipReason, "already_notified_today")
        XCTAssertEqual(try notificationClient.listScheduled().count, 1)
    }

    func testSafeDailyCheckRunnerRecordsFailedScanWithoutThrowing() throws {
        let logger = InMemoryAuditLogger()
        let runner = SafeDailyCheckRunner(
            runner: FailingDailyCheckRunnable(),
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
            auditLogger: logger
        )

        let result = runner.run(reason: .scheduledDaily)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorMessage, "scan failed")
        XCTAssertEqual(logger.recordedEvents.last?.status, .failed)
        XCTAssertEqual(logger.recordedEvents.last?.metadata["scan_count"], "0")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["notification_planned_count"], "0")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["skip_reason"], "")
        XCTAssertEqual(logger.recordedEvents.last?.metadata["error"], "scan failed")
    }

    func testSafeDailyCheckRunnerSurfacesAuditFailureWithoutDroppingScanFailure() throws {
        let runner = SafeDailyCheckRunner(
            runner: FailingDailyCheckRunnable(),
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
            auditLogger: FailingDailyCheckAuditLogger()
        )

        let result = runner.run(reason: .scheduledDaily)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorMessage, "scan failed")
        XCTAssertEqual(result.auditErrorMessage, "Daily check audit log failed: unavailable")
    }

    func testSafeDailyCheckRunnerRedactsAuditFailureBeforeUserDisplay() throws {
        let secret = "sk-daily-audit-secret"
        let runner = SafeDailyCheckRunner(
            runner: FailingDailyCheckRunnable(),
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
            auditLogger: SecretFailingDailyCheckAuditLogger(secret: secret)
        )

        let result = runner.run(reason: .scheduledDaily)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.errorMessage, "scan failed")
        XCTAssertEqual(result.auditErrorMessage, "Daily check audit log failed: audit failed token=[REDACTED_SECRET]")
        XCTAssertFalse(result.auditErrorMessage?.contains(secret) ?? true)
    }

    func testWatcherDiagnosticsProviderBuildsLastNextAndPermissionSnapshot() throws {
        var permissions = PermissionSnapshot.empty
        permissions.setStatus(.granted, for: .notifications)
        let lastRunAt = try Date.iso8601("2026-06-17T01:00:00Z")
        let provider = WatcherDiagnosticsProvider(
            stateStore: InMemoryDailyCheckStateStore(lastRunAt: lastRunAt),
            permissionSnapshot: permissions,
            dateProvider: FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z")),
            settings: AppSettings(timeZoneIdentifier: "UTC")
        )

        let snapshot = try provider.snapshot()

        XCTAssertEqual(snapshot.lastCheckAt, lastRunAt)
        XCTAssertEqual(snapshot.nextCheckAt, try Date.iso8601("2026-06-18T00:00:00Z"))
        XCTAssertEqual(snapshot.notificationPermissionStatus, .granted)
    }

    func testLaunchAtLoginClientCanBeToggledForDailyChecks() throws {
        let client = InMemoryLaunchAtLoginClient()

        XCTAssertEqual(try client.setEnabled(true), .enabled)
        XCTAssertEqual(client.status(), .enabled)
        XCTAssertEqual(try client.setEnabled(false), .disabled)
        XCTAssertEqual(client.status(), .disabled)
    }

    @MainActor
    func testLaunchAtLoginSettingsViewModelTogglesClientAndLabelsStatus() {
        let client = InMemoryLaunchAtLoginClient()
        let viewModel = LaunchAtLoginSettingsViewModel(client: client)

        XCTAssertFalse(viewModel.isEnabled)
        XCTAssertEqual(viewModel.statusLabel, "Off")

        viewModel.setEnabled(true)

        XCTAssertTrue(viewModel.isEnabled)
        XCTAssertEqual(client.status(), .enabled)
        XCTAssertEqual(viewModel.statusLabel, "On")
        XCTAssertNil(viewModel.errorMessage)
    }

    @MainActor
    func testLaunchAtLoginSettingsViewModelExplainsUnavailableStates() {
        let unavailableViewModel = LaunchAtLoginSettingsViewModel(
            client: StaticLaunchAtLoginClient(status: .unavailable)
        )
        let requiresApprovalViewModel = LaunchAtLoginSettingsViewModel(
            client: StaticLaunchAtLoginClient(status: .requiresApproval)
        )

        XCTAssertFalse(unavailableViewModel.canToggle)
        XCTAssertEqual(
            unavailableViewModel.statusDetail,
            "Launch at Login is unavailable for this app bundle. Use a signed app installed in Applications for release verification."
        )
        XCTAssertFalse(requiresApprovalViewModel.canToggle)
        XCTAssertEqual(
            requiresApprovalViewModel.statusDetail,
            "macOS requires approval in System Settings before Suisui can launch at login."
        )
    }

    @MainActor
    func testLaunchAtLoginSettingsViewModelRedactsToggleErrorsBeforeUserDisplay() {
        let viewModel = LaunchAtLoginSettingsViewModel(client: ThrowingLaunchAtLoginClient())

        viewModel.setEnabled(true)

        XCTAssertEqual(viewModel.status, .disabled)
        XCTAssertEqual(viewModel.errorMessage, "Launch at Login failed with [REDACTED_SECRET]")
        XCTAssertFalse(viewModel.errorMessage?.contains("sk-login-secret") ?? true)
    }

    func testSQLiteDailyCheckStateStorePersistsLastRunAt() throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        let store = SQLiteDailyCheckStateStore(connection: connection)
        let date = try Date.iso8601("2026-06-17T12:00:00Z")

        try store.recordRun(at: date)

        XCTAssertTrue(try connection.tableExists("daily_check_state"))
        XCTAssertEqual(try store.lastRunAt(), date)
    }

    private func makeRunner(
        stores: (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, rules: SQLiteDeadlineRuleStore),
        stateStore: any DailyCheckStateStore,
        notificationClient: InMemoryNotificationClient = InMemoryNotificationClient(),
        logger: InMemoryAuditLogger
    ) throws -> DailyCheckRunner {
        let dateProvider = FixedDateProvider(now: try Date.iso8601("2026-06-17T12:00:00Z"))
        let settings = AppSettings(timeZoneIdentifier: "UTC")
        let queryService = DeadlineQueryService(
            projectStore: stores.projects,
            taskStore: stores.tasks,
            dateProvider: dateProvider,
            settings: settings
        )
        let overdueChecker = OverdueChecker(
            queryService: queryService,
            ruleStore: stores.rules,
            dateProvider: dateProvider,
            settings: settings
        )
        let scheduler = DeadlineNotificationScheduler(
            notificationClient: notificationClient,
            dateProvider: dateProvider,
            settings: settings
        )

        return DailyCheckRunner(
            overdueChecker: overdueChecker,
            notificationScheduler: scheduler,
            ruleStore: stores.rules,
            stateStore: stateStore,
            dateProvider: dateProvider,
            settings: settings,
            auditLogger: logger
        )
    }

    private func makeStores() throws -> (projects: SQLiteProjectStore, tasks: SQLiteTaskStore, rules: SQLiteDeadlineRuleStore) {
        let connection = try SQLiteConnection(path: ":memory:")
        try SQLiteMigrationRunner.migrate(connection: connection, migrations: CoreMigrations.phase4)
        return (
            SQLiteProjectStore(connection: connection),
            SQLiteTaskStore(connection: connection),
            SQLiteDeadlineRuleStore(connection: connection)
        )
    }
}

private struct StaticLaunchAtLoginClient: LaunchAtLoginClient {
    var currentStatus: LaunchAtLoginStatus

    init(status: LaunchAtLoginStatus) {
        self.currentStatus = status
    }

    func status() -> LaunchAtLoginStatus {
        currentStatus
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        currentStatus
    }
}

private struct ThrowingLaunchAtLoginClient: LaunchAtLoginClient {
    func status() -> LaunchAtLoginStatus {
        .disabled
    }

    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        throw LaunchAtLoginSecretError()
    }
}

private struct LaunchAtLoginSecretError: Error, LocalizedError {
    var errorDescription: String? {
        "Launch at Login failed with sk-login-secret"
    }
}

private struct FixedDateProvider: DateProvider {
    let now: Date
}

private struct FailingDailyCheckRunnable: DailyCheckRunnable {
    func runIfNeeded(reason: DailyCheckReason) throws -> DailyCheckRunResult {
        throw ToolClientError.invalidRequest("scan failed")
    }
}

private enum DailyCheckAuditTestError: Error, CustomStringConvertible {
    case unavailable

    var description: String {
        "unavailable"
    }
}

private struct FailingDailyCheckAuditLogger: AuditLogger {
    func record(_ event: AuditEvent) throws {
        throw DailyCheckAuditTestError.unavailable
    }
}

private struct SecretFailingDailyCheckAuditLogger: AuditLogger {
    let secret: String

    func record(_ event: AuditEvent) throws {
        throw SecretDailyCheckAuditTestError(secret: secret)
    }
}

private struct SecretDailyCheckAuditTestError: Error, CustomStringConvertible {
    let secret: String

    var description: String {
        "audit failed token=\(secret)"
    }
}

private extension Date {
    static func iso8601(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
