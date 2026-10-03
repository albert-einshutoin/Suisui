import Foundation

/// Canonical local capture values. Presentation previews and persistence use
/// the same draft so saving never interprets the user's text a second time.
public struct InboxTaskDraft: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var priority: ProjectTaskPriority
    public var dueAt: String?

    public init(
        title: String,
        detail: String = "",
        priority: ProjectTaskPriority = .medium,
        dueAt: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.priority = priority
        self.dueAt = dueAt
    }

    public static func parsing(
        _ input: String,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> InboxTaskDraft {
        let parsed = QuickAddDueDateParser.parse(input, now: now, timeZone: timeZone)
        return InboxTaskDraft(
            title: parsed.title,
            dueAt: parsed.dueAt.map { DeadlineDateParser.string(from: $0) }
        )
    }
}
