import Foundation

/// Shared cockpit breakpoints for Inbox, Today, Projects, Schedule, Done, and
/// Voice. Split rails keep every ordinary action on one screen at the 1024pt
/// product window; narrower windows stack or omit the secondary rail.
public enum CockpitLayoutPolicy {
    public static let standardWindowWidth = 1_024.0
    public static let minimumWindowWidth = 960.0
    public static let sidebarMaxWidth = 240.0
    public static let railWidth = 240.0
    /// Inbox triage desk needs a wider rail so Convert / Proposed Actions /
    /// Details stay readable at the 1024×676 contract without truncating the
    /// sample's voice-memo density. Other workflows keep `railWidth`.
    public static let inboxRailWidth = 280.0
    public static let splitSpacing = 12.0
    /// Keep the 1024pt board detail column (≈784pt) and slightly padded Settings
    /// surfaces above this floor, while the 960pt minimum window (720pt content)
    /// still stacks rails. 730 leaves headroom for scene padding without losing
    /// the Overview/AI desk split in visual evidence.
    public static let splitMinimumContentWidth = 730.0

    public static var standardContentWidth: Double {
        standardWindowWidth - sidebarMaxWidth
    }

    public static func contentWidth(forWindowWidth windowWidth: Double) -> Double {
        max(0, windowWidth - sidebarMaxWidth)
    }

    public static func presentsSplitRail(contentWidth: Double) -> Bool {
        contentWidth >= splitMinimumContentWidth
    }

    public static func showsSecondaryIntegrations(contentWidth: Double) -> Bool {
        presentsSplitRail(contentWidth: contentWidth)
    }
}
