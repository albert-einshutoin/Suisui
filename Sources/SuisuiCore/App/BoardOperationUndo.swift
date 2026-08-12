import Foundation

/// Inverse description of one user-driven Project Board task mutation.
///
/// Entries describe how to put the board back, not what the user did. Applying
/// an entry only calls existing store APIs (snapshot restore, field revert,
/// delete) and never re-runs completion side effects such as recurrence
/// regeneration, so undoing never spawns new work.
public enum BoardOperationUndoEntry: Equatable, Sendable {
    /// Inverse of deleting a task: recreate it from the pre-delete snapshot,
    /// preserving detail, due date, priority, recurrence, and the original
    /// completion timestamp.
    case restoreTask(snapshot: ProjectBoardTask)
    /// Inverse of deleting a task that owns Inbox voice captures. The capture
    /// rows are recreated after the task so SQLite's foreign key remains valid
    /// and the managed audio paths stay reachable for Undo playback.
    case restoreTaskWithCaptures(snapshot: ProjectBoardTask, captures: [InboxCaptureRecord])
    /// Inverse of a status move (keyboard, card controls, or a single-card
    /// drag & drop): put the previous status back.
    case revertStatus(snapshot: ProjectBoardTask)
    /// Inverse of an inspector edit: restore every editable field from the
    /// pre-edit snapshot.
    case revertFields(snapshot: ProjectBoardTask)
    /// Inverse of completing a task. When the completion regenerated the next
    /// recurrence occurrence, `regenerated` carries that occurrence exactly as
    /// it was created; undo deletes it only while it is still untouched.
    case undoCompletion(snapshot: ProjectBoardTask, regenerated: ProjectBoardTask?)
    /// Inverse of completing/reopening an Inbox task. The mutation carries the
    /// task fields and explicit Inbox disposition together so Edit-menu Undo
    /// cannot restore one half of the lifecycle and leave the read model stale.
    case revertInboxTriage(mutation: InboxTriageMutation, regenerated: ProjectBoardTask?)
    /// Inverse of a multi-task drag & drop status move. `regenerated` carries
    /// every next occurrence spawned by recurring tasks completed in the batch.
    case revertStatusBatch(snapshots: [ProjectBoardTask], regenerated: [ProjectBoardTask])
}

/// Pure in-memory LIFO stack of board undo entries.
///
/// The stack is deliberately session-only (no persistence) and capped at
/// ``maxEntries``: pushing beyond the cap drops the oldest entry first.
public struct BoardOperationUndoStack: Equatable, Sendable {
    public static let maxEntries = 10

    public private(set) var entries: [BoardOperationUndoEntry]

    public init() {
        entries = []
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    public var count: Int {
        entries.count
    }

    /// The entry that the next undo will apply (most recent operation).
    public var last: BoardOperationUndoEntry? {
        entries.last
    }

    public mutating func push(_ entry: BoardOperationUndoEntry) {
        entries.append(entry)
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    @discardableResult
    public mutating func pop() -> BoardOperationUndoEntry? {
        entries.popLast()
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}
