import Foundation

public enum DailyCheckReason: String, Equatable, Sendable {
    case appLaunch = "app_launch"
    case scheduledDaily = "scheduled_daily"
    case manual = "manual"
}

public enum DailyCheckRunStatus: Equatable, Sendable {
    case ran
    case skippedAlreadyRanToday
}

public struct DailyCheckRunResult: Equatable, Sendable {
    public var status: DailyCheckRunStatus
    public var overdueCount: Int
    public var scheduledCount: Int
    public var skippedCount: Int

    public init(status: DailyCheckRunStatus, overdueCount: Int = 0, scheduledCount: Int = 0, skippedCount: Int = 0) {
        self.status = status
        self.overdueCount = overdueCount
        self.scheduledCount = scheduledCount
        self.skippedCount = skippedCount
    }
}

public final class DailyCheckRunner: @unchecked Sendable {
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
            let result = DailyCheckRunResult(status: .skippedAlreadyRanToday)
            try recordAudit(status: .skipped, reason: reason, result: result)
            return result
        }

        let check = try overdueChecker.check()
        var scheduledCount = 0

        for candidate in check.candidates {
            let result = notificationScheduler.schedule(rule: candidate.rule, item: candidate.item)
            if result.status == .scheduled, let ruleID = candidate.rule.id {
                _ = try ruleStore.markNotified(id: ruleID, at: now)
                scheduledCount += 1
            }
        }

        try stateStore.recordRun(at: now)
        let result = DailyCheckRunResult(
            status: .ran,
            overdueCount: check.candidates.count,
            scheduledCount: scheduledCount,
            skippedCount: check.skipped.count
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
                    "skipped_count": String(result.skippedCount)
                ]
            )
        )
    }
}
