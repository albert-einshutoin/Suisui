import Foundation

public enum DeadlineRuleTarget: Equatable, Sendable {
    case project(Int64)
    case task(Int64)

    public var targetType: String {
        switch self {
        case .project:
            "project"
        case .task:
            "task"
        }
    }

    public var targetID: Int64 {
        switch self {
        case .project(let id),
             .task(let id):
            id
        }
    }

    public init?(targetType: String, targetID: Int64) {
        switch targetType {
        case "project":
            self = .project(targetID)
        case "task":
            self = .task(targetID)
        default:
            return nil
        }
    }
}

public enum DeadlineRuleKind: String, CaseIterable, Equatable, Sendable {
    case tMinus14 = "T-14"
    case tMinus7 = "T-7"
    case tMinus3 = "T-3"
    case tMinus1 = "T-1"
    case dayOf = "day_of"
    case overdueDaily = "overdue_daily"
    case custom

    fileprivate var dayOffset: Int? {
        switch self {
        case .tMinus14:
            -14
        case .tMinus7:
            -7
        case .tMinus3:
            -3
        case .tMinus1:
            -1
        case .dayOf:
            0
        case .overdueDaily:
            1
        case .custom:
            nil
        }
    }
}

public struct DeadlineRule: Equatable, Sendable {
    public var id: Int64?
    public var target: DeadlineRuleTarget
    public var kind: DeadlineRuleKind
    public var customNotifyAt: Date?
    public var mutedAt: Date?
    public var lastNotifiedAt: Date?

    public init(
        id: Int64? = nil,
        target: DeadlineRuleTarget,
        kind: DeadlineRuleKind,
        customNotifyAt: Date? = nil,
        mutedAt: Date? = nil,
        lastNotifiedAt: Date? = nil
    ) {
        self.id = id
        self.target = target
        self.kind = kind
        self.customNotifyAt = customNotifyAt
        self.mutedAt = mutedAt
        self.lastNotifiedAt = lastNotifiedAt
    }

    public var isMuted: Bool {
        mutedAt != nil
    }

    public func notifyAt(forDueAt dueAt: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        if kind == .custom {
            return customNotifyAt
        }

        guard let dayOffset = kind.dayOffset else {
            return nil
        }

        return calendar.date(byAdding: .day, value: dayOffset, to: dueAt)
    }
}
