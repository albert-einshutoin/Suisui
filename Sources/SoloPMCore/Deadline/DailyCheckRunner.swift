import Foundation

public enum DailyCheckReason: String, Equatable, Sendable {
    case appLaunch = "app_launch"
    case scheduledDaily = "scheduled_daily"
    case manual = "manual"
}

public enum DailyCheckRunStatus: Equatable, Sendable {
    case ran
    case skippedAlreadyRanToday
    case failed
}

public struct DailyCheckRunResult: Equatable, Sendable {
    public var status: DailyCheckRunStatus
    public var overdueCount: Int
    public var scheduledCount: Int
    public var skippedCount: Int
    public var scanCount: Int
    public var notificationPlannedCount: Int
    public var skipReason: String?
    public var errorMessage: String?

    public init(
        status: DailyCheckRunStatus,
        overdueCount: Int = 0,
        scheduledCount: Int = 0,
        skippedCount: Int = 0,
        scanCount: Int = 0,
        notificationPlannedCount: Int = 0,
        skipReason: String? = nil,
        errorMessage: String? = nil
    ) {
        self.status = status
        self.overdueCount = overdueCount
        self.scheduledCount = scheduledCount
        self.skippedCount = skippedCount
        self.scanCount = scanCount
        self.notificationPlannedCount = notificationPlannedCount
        self.skipReason = skipReason
        self.errorMessage = errorMessage
    }
}

public protocol DailyCheckRunnable: Sendable {
    func runIfNeeded(reason: DailyCheckReason) throws -> DailyCheckRunResult
}

public final class DailyCheckRunner: DailyCheckRunnable, @unchecked Sendable {
    private let overdueChecker: OverdueChecker
    private let notificationScheduler: DeadlineNotificationScheduler
    private let ruleStore: SQLiteDeadlineRuleStore
    private let stateStore: any DailyCheckStateStore
    private let dateProvider: any DateProvider
    private let settings: AppSettings
    private let auditLogger: (any AuditLogger)?

    public init(
        overdueChecker: OverdueChecker,
        notificationScheduler: DeadlineNotificationScheduler,
        ruleStore: SQLiteDeadlineRuleStore,
        stateStore: any DailyCheckStateStore,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default,
        auditLogger: (any AuditLogger)? = nil
    ) {
        self.overdueChecker = overdueChecker
        self.notificationScheduler = notificationScheduler
        self.ruleStore = ruleStore
        self.stateStore = stateStore
        self.dateProvider = dateProvider
        self.settings = settings
        self.auditLogger = auditLogger
    }

    public func runIfNeeded(reason: DailyCheckReason) throws -> DailyCheckRunResult {
        let now = dateProvider.now
        if let lastRunAt = try stateStore.lastRunAt(), isSameConfiguredDay(lastRunAt, now) {
            let result = DailyCheckRunResult(
                status: .skippedAlreadyRanToday,
                skipReason: "already_ran_today"
            )
            try recordAudit(status: .skipped, reason: reason, result: result)
            return result
        }

        let check = try overdueChecker.check()
        var scheduledCount = 0
        var scheduleSkipReasons: [String] = []

        for candidate in check.candidates {
            let scheduleResult = notificationScheduler.schedule(rule: candidate.rule, item: candidate.item)
            if scheduleResult.status == .scheduled, let ruleID = candidate.rule.id {
                _ = try ruleStore.markNotified(id: ruleID, at: now)
                scheduledCount += 1
            } else if scheduleResult.status != .scheduled {
                scheduleSkipReasons.append(scheduleResult.status.auditValue)
            }
        }

        let skipReasons = check.skipped.map { $0.reason.auditValue } + scheduleSkipReasons
        try stateStore.recordRun(at: now)
        let result = DailyCheckRunResult(
            status: .ran,
            overdueCount: check.candidates.count,
            scheduledCount: scheduledCount,
            skippedCount: check.skipped.count + scheduleSkipReasons.count,
            scanCount: check.candidates.count + check.skipped.count,
            notificationPlannedCount: scheduledCount,
            skipReason: skipReasons.joinedNonEmpty()
        )
        try recordAudit(status: .succeeded, reason: reason, result: result)
        return result
    }

    private func isSameConfiguredDay(_ lhs: Date, _ rhs: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current
        return calendar.isDate(lhs, inSameDayAs: rhs)
    }

    private func recordAudit(status: AuditStatus, reason: DailyCheckReason, result: DailyCheckRunResult) throws {
        try auditLogger?.record(
            AuditEvent(
                timestamp: dateProvider.now,
                category: "deadline_watcher",
                action: "daily_check",
                status: status,
                metadata: [
                    "reason": reason.rawValue,
                    "run_status": String(describing: result.status),
                    "overdue_count": String(result.overdueCount),
                    "scheduled_count": String(result.scheduledCount),
                    "skipped_count": String(result.skippedCount),
                    "scan_count": String(result.scanCount),
                    "notification_planned_count": String(result.notificationPlannedCount),
                    "skip_reason": result.skipReason ?? "",
                    "error": result.errorMessage ?? ""
                ]
            )
        )
    }
}

public final class SafeDailyCheckRunner: @unchecked Sendable {
    private let runner: any DailyCheckRunnable
    private let dateProvider: any DateProvider
    private let auditLogger: (any AuditLogger)?

    public init(
        runner: any DailyCheckRunnable,
        dateProvider: any DateProvider = SystemDateProvider(),
        auditLogger: (any AuditLogger)? = nil
    ) {
        self.runner = runner
        self.dateProvider = dateProvider
        self.auditLogger = auditLogger
    }

    public func run(reason: DailyCheckReason) -> DailyCheckRunResult {
        do {
            return try runner.runIfNeeded(reason: reason)
        } catch {
            let result = DailyCheckRunResult(
                status: .failed,
                errorMessage: error.auditMessage
            )
            try? auditLogger?.record(
                AuditEvent(
                    timestamp: dateProvider.now,
                    category: "deadline_watcher",
                    action: "daily_check",
                    status: .failed,
                    metadata: [
                        "reason": reason.rawValue,
                        "run_status": String(describing: result.status),
                        "overdue_count": String(result.overdueCount),
                        "scheduled_count": String(result.scheduledCount),
                        "skipped_count": String(result.skippedCount),
                        "scan_count": String(result.scanCount),
                        "notification_planned_count": String(result.notificationPlannedCount),
                        "skip_reason": result.skipReason ?? "",
                        "error": result.errorMessage ?? ""
                    ]
                )
            )
            return result
        }
    }
}

public struct WatcherDiagnosticsSnapshot: Equatable, Sendable {
    public var lastCheckAt: Date?
    public var nextCheckAt: Date?
    public var notificationPermissionStatus: PermissionStatus

    public init(
        lastCheckAt: Date? = nil,
        nextCheckAt: Date? = nil,
        notificationPermissionStatus: PermissionStatus = .notDetermined
    ) {
        self.lastCheckAt = lastCheckAt
        self.nextCheckAt = nextCheckAt
        self.notificationPermissionStatus = notificationPermissionStatus
    }
}

public final class WatcherDiagnosticsProvider: @unchecked Sendable {
    private let stateStore: any DailyCheckStateStore
    private let permissionSnapshot: PermissionSnapshot
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        stateStore: any DailyCheckStateStore,
        permissionSnapshot: PermissionSnapshot = .empty,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.stateStore = stateStore
        self.permissionSnapshot = permissionSnapshot
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func snapshot() throws -> WatcherDiagnosticsSnapshot {
        let lastRunAt = try stateStore.lastRunAt()
        return WatcherDiagnosticsSnapshot(
            lastCheckAt: lastRunAt,
            nextCheckAt: nextCheckAt(after: lastRunAt),
            notificationPermissionStatus: permissionSnapshot.status(for: .notifications)
        )
    }

    private func nextCheckAt(after lastRunAt: Date?) -> Date {
        let now = dateProvider.now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current

        guard let lastRunAt, calendar.isDate(lastRunAt, inSameDayAs: now) else {
            return now
        }

        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
    }
}

private extension OverdueSkipReason {
    var auditValue: String {
        switch self {
        case .noOverdueRule:
            "no_overdue_rule"
        case .muted:
            "muted"
        case .alreadyNotifiedToday:
            "already_notified_today"
        }
    }
}

private extension DeadlineNotificationScheduleStatus {
    var auditValue: String {
        switch self {
        case .scheduled:
            "scheduled"
        case .skippedDuplicate:
            "skipped_duplicate"
        case .skippedPastDate:
            "skipped_past_date"
        case .skippedMissingDate:
            "skipped_missing_date"
        case .failed:
            "failed"
        }
    }
}

private extension Array where Element == String {
    func joinedNonEmpty() -> String? {
        let filtered = filter { !$0.isEmpty }
        return filtered.isEmpty ? nil : filtered.joined(separator: ",")
    }
}

private extension Error {
    var auditMessage: String {
        if let toolClientError = self as? ToolClientError {
            return toolClientError.message
        }
        return String(describing: self)
    }
}
