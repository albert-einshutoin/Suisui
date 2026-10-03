import Foundation

public enum ScheduleApplyResult: Equatable, Sendable {
    case approvalRequired
    case calendarNotConfigured
    case noDraft
    case applied(eventCount: Int)
    case failed(String)
}

public struct ProjectAssistantAnswer: Equatable, Sendable {
    public var projectID: Int64
    public var question: String
    public var message: String
    public var suggestedActionTitle: String
    public var requiresReview: Bool

    public init(projectID: Int64, question: String, message: String, suggestedActionTitle: String, requiresReview: Bool) {
        self.projectID = projectID
        self.question = question
        self.message = message
        self.suggestedActionTitle = suggestedActionTitle
        self.requiresReview = requiresReview
    }
}

public struct ProjectAssistantReviewDraft: Equatable, Sendable {
    public var projectID: Int64
    public var suggestedActionTitle: String
    public var summary: String

    public init(projectID: Int64, suggestedActionTitle: String, summary: String) {
        self.projectID = projectID
        self.suggestedActionTitle = suggestedActionTitle
        self.summary = summary
    }
}
