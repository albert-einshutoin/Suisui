import Foundation

/// Input-local state: parse once when text changes, then edit/save that draft.
public struct QuickCaptureDraft: Equatable, Sendable {
    private enum DueDateSelection: Equatable, Sendable {
        case inferred
        case explicit(String?)
    }
    private var dueDateSelection: DueDateSelection = .inferred
    public var input: String {
        didSet { updateDraft() }
    }
    public private(set) var draft: InboxTaskDraft

    public init(input: String = "", now: Date = Date(), timeZone: TimeZone = .current) {
        self.input = input
        self.draft = InboxTaskDraft.parsing(input, now: now, timeZone: timeZone)
    }

    public var dueDate: Date? { draft.dueAt.flatMap { DeadlineDateParser.date(from: $0) } }

    public mutating func setDueDate(_ date: Date) {
        let dueAt = DeadlineDateParser.string(from: date)
        dueDateSelection = .explicit(dueAt)
        draft.dueAt = dueAt
    }

    public mutating func removeInferredDueDate() {
        // Removing interpretation must not silently discard words from input.
        dueDateSelection = .explicit(nil)
        updateDraft()
    }

    private mutating func updateDraft() {
        switch dueDateSelection {
        case .inferred:
            draft = InboxTaskDraft.parsing(input)
        case .explicit(let dueAt):
            // Title edits must preserve an explicit date choice or removal.
            // Removal also keeps the date words as part of the user's title.
            draft = dueAt == nil
                ? InboxTaskDraft(title: input.trimmingCharacters(in: .whitespacesAndNewlines))
                : InboxTaskDraft.parsing(input)
            draft.dueAt = dueAt
        }
    }
}
