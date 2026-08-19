import Foundation

/// Shared cockpit breakpoints for Inbox, Today, Projects, Schedule, Done, and
/// Voice. Split rails keep every ordinary action on one screen at the 1024pt
/// product window; narrower windows stack or omit the secondary rail.
public enum CockpitLayoutPolicy {
    public static let standardWindowWidth = 1_024.0
    public static let minimumWindowWidth = 960.0
    public static let sidebarMaxWidth = 240.0
    public static let railWidth = 240.0
    public static let splitSpacing = 12.0
    /// Voice evidence and the 1024pt board detail column both clear this floor.
    public static let splitMinimumContentWidth = 760.0

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
