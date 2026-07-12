import Foundation
import os

/// Launch-stage instrumentation, visible in Instruments via the os_signpost
/// tool. The subsystem/category pair and the stage names are documented in
/// docs/quality/performance-budget.md; measuring must never change behavior,
/// so every call site wraps existing work without adding branches.
enum LaunchPerformanceSignposts {
    static let signposter = OSSignposter(subsystem: "dev.solopm.performance", category: "launch")

    @MainActor
    private static var hasRecordedFirstBoardLoad = false

    /// Wraps the first Project Board snapshot load of the process in a
    /// "FirstBoardLoad" interval. Later loads (window reopen, board-change
    /// notifications) run unmeasured so the signpost stays a launch metric.
    @MainActor
    static func measureFirstBoardLoadOnce<T>(_ body: () -> T) -> T {
        guard hasRecordedFirstBoardLoad == false else {
            return body()
        }
        hasRecordedFirstBoardLoad = true
        let state = signposter.beginInterval("FirstBoardLoad")
        defer {
            signposter.endInterval("FirstBoardLoad", state)
        }
        return body()
    }
}
