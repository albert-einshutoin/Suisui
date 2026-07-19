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

/// Emits app-owned launch milestones only when the release performance harness
/// supplies a destination. AX traversal remains a correctness check, while
/// these timestamps keep observer traversal cost out of the product SLO.
enum LaunchPerformanceMilestones {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var recordedLabels = Set<String>()

    static func record(_ label: String) {
        guard let path = ProcessInfo.processInfo.environment["SOLOPM_LAUNCH_TIMELINE_PATH"],
              !path.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }
        guard recordedLabels.insert(label).inserted else {
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let line = Data("\(label)\t\(timestamp)\n".utf8)
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else {
            return
        }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            // Launch evidence must never make the product fail to open. The
            // harness treats a missing milestone as a fail-closed test result.
        }
    }
}
