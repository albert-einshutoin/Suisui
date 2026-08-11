import Foundation

public enum InboxTriageDisposition: String, Codable, Equatable, Sendable {
    case unprocessed
    case task
    case scheduled
    case reviewLater = "review_later"
    case project
}

public enum InboxTriageError: Error, Equatable, Sendable {
    case missingReviewDate
    case unexpectedReviewDate
    case reviewDateUnavailable
}

public struct InboxTriageRecord: Equatable, Sendable {
    public let taskID: Int64
    public let disposition: InboxTriageDisposition
    public let reviewAt: String?
    public let updatedAt: String

    public init(
        taskID: Int64,
        disposition: InboxTriageDisposition,
        reviewAt: String?,
        updatedAt: String
    ) throws {
        guard disposition == .reviewLater ? reviewAt != nil : reviewAt == nil else {
            throw disposition == .reviewLater
                ? InboxTriageError.missingReviewDate
                : InboxTriageError.unexpectedReviewDate
        }
        self.taskID = taskID
        self.disposition = disposition
        self.reviewAt = reviewAt
        self.updatedAt = updatedAt
    }
}

public enum InboxTriageAction: Equatable, Sendable {
    case makeTask
    case makeProject
    case scheduleToday
    case reviewLater
    case complete
    case reopen
}

public enum InboxReviewClock {
    public static func nextReviewDate(after referenceDate: Date, calendar: Calendar) throws -> Date {
        let start = calendar.startOfDay(for: referenceDate)
        // Calendar performs the local-time/DST conversion; adding 24 hours would
        // schedule the wrong instant on daylight-saving boundaries.
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
              let review = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) else {
            throw InboxTriageError.reviewDateUnavailable
        }
        return review
    }
}
