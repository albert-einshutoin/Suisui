import Foundation

public enum OverdueSkipReason: Equatable, Sendable {
    case noOverdueRule
    case muted
    case alreadyNotifiedToday
}

public struct OverdueNotificationCandidate: Equatable, Sendable {
    public var item: DeadlineItem
    public var rule: DeadlineRule

    public init(item: DeadlineItem, rule: DeadlineRule) {
        self.item = item
        self.rule = rule
    }
}

public struct OverdueSkippedItem: Equatable, Sendable {
    public var item: DeadlineItem
    public var rule: DeadlineRule?
    public var reason: OverdueSkipReason

    public init(item: DeadlineItem, rule: DeadlineRule? = nil, reason: OverdueSkipReason) {
        self.item = item
        self.rule = rule
        self.reason = reason
    }
}

public struct OverdueCheckResult: Equatable, Sendable {
    public var candidates: [OverdueNotificationCandidate]
    public var skipped: [OverdueSkippedItem]

    public init(candidates: [OverdueNotificationCandidate] = [], skipped: [OverdueSkippedItem] = []) {
        self.candidates = candidates
        self.skipped = skipped
    }
}

public final class OverdueChecker: @unchecked Sendable {
    private let queryService: DeadlineQueryService
    private let ruleStore: SQLiteDeadlineRuleStore
    private let dateProvider: any DateProvider
    private let settings: AppSettings

    public init(
        queryService: DeadlineQueryService,
        ruleStore: SQLiteDeadlineRuleStore,
        dateProvider: any DateProvider = SystemDateProvider(),
        settings: AppSettings = .default
    ) {
        self.queryService = queryService
        self.ruleStore = ruleStore
        self.dateProvider = dateProvider
        self.settings = settings
    }

    public func check() throws -> OverdueCheckResult {
        let overdueItems = try queryService.summary().overdue
        var candidates: [OverdueNotificationCandidate] = []
        var skipped: [OverdueSkippedItem] = []

        for item in overdueItems {
            let rules = try ruleStore.list(for: item.ruleTarget).filter { $0.kind == .overdueDaily }
            guard !rules.isEmpty else {
                skipped.append(OverdueSkippedItem(item: item, reason: .noOverdueRule))
                continue
            }

            for rule in rules {
                if rule.isMuted {
                    skipped.append(OverdueSkippedItem(item: item, rule: rule, reason: .muted))
                } else if hasAlreadyNotifiedToday(rule) {
                    skipped.append(OverdueSkippedItem(item: item, rule: rule, reason: .alreadyNotifiedToday))
                } else {
                    candidates.append(OverdueNotificationCandidate(item: item, rule: rule))
                }
            }
        }

        return OverdueCheckResult(candidates: candidates, skipped: skipped)
    }

    private func hasAlreadyNotifiedToday(_ rule: DeadlineRule) -> Bool {
        guard let lastNotifiedAt = rule.lastNotifiedAt else {
            return false
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: settings.timeZoneIdentifier) ?? .current
        return calendar.isDate(lastNotifiedAt, inSameDayAs: dateProvider.now)
    }
}

private extension DeadlineItem {
    var ruleTarget: DeadlineRuleTarget {
        switch kind {
        case .project:
            .project(id)
        case .task:
            .task(id)
        }
    }
}
