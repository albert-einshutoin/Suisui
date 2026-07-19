import Foundation

/// Pure selection-ordering logic for keyboard-driven task navigation on the
/// Project Board. The SwiftUI key handlers stay thin; the ordering rules live
/// here so they are unit-testable without a view hierarchy.
public enum ProjectBoardKeyboardNavigation {
    /// The board's visible flattened ordering: column order (Backlog → Done)
    /// with each column's tasks in their rendered order.
    public static func orderedTaskIDs(in project: ProjectBoardProject) -> [Int64] {
        project.columns.flatMap { column in
            column.tasks.map(\.id)
        }
    }

    /// Next task in the visible ordering. With no current selection (or a
    /// selection that is no longer visible) it starts at the first task.
    /// Selection clamps at the end instead of wrapping.
    public static func nextTaskID(after selectedTaskID: Int64?, in orderedTaskIDs: [Int64]) -> Int64? {
        guard !orderedTaskIDs.isEmpty else {
            return nil
        }
        guard let selectedTaskID,
              let selectedIndex = orderedTaskIDs.firstIndex(of: selectedTaskID) else {
            return orderedTaskIDs.first
        }
        return orderedTaskIDs[min(selectedIndex + 1, orderedTaskIDs.count - 1)]
    }

    /// Previous task in the visible ordering. With no current selection (or a
    /// selection that is no longer visible) it starts at the last task.
    /// Selection clamps at the start instead of wrapping.
    public static func previousTaskID(before selectedTaskID: Int64?, in orderedTaskIDs: [Int64]) -> Int64? {
        guard !orderedTaskIDs.isEmpty else {
            return nil
        }
        guard let selectedTaskID,
              let selectedIndex = orderedTaskIDs.firstIndex(of: selectedTaskID) else {
            return orderedTaskIDs.last
        }
        return orderedTaskIDs[max(selectedIndex - 1, 0)]
    }
}
