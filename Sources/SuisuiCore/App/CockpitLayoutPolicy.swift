import Foundation

/// Shared cockpit breakpoints and secondary-rail sizing for Inbox, Today,
/// Projects, Schedule, Done, Voice, and Settings.
///
/// ## Window rungs (sidebar capped at `sidebarMaxWidth`)
/// | Window | Content | Mode |
/// | --- | --- | --- |
/// | ≥`defaultLaunchWindowWidth` (1180) | ≥940 | split; Schedule rail may expand |
/// | `standardWindowWidth` (1024) | 784 | split (product / visual contract) |
/// | ≈970 (`splitMinimumContentWidth` + sidebar) | 730 | split floor |
/// | `minimumWindowWidth` (960) | 720 | stack secondary below primary |
/// | content ≤729 | — | stack secondary below primary |
///
/// Split decisions use **detail content width**, not raw window width:
/// `contentWidth = windowWidth - sidebarMaxWidth` (or full window when the
/// sidebar column is hidden).
///
/// ## Secondary rails
/// Every desk **stacks** the secondary rail below the primary when narrow so
/// triage / readiness / understood actions stay reachable. Rails never omit on
/// the supported window range.
///
/// ## Rail widths
/// | Desk | Behavior |
/// | --- | --- |
/// | Today / Projects / Done / Voice Quick Command | fixed `railWidth` (240) |
/// | Inbox | fixed `inboxRailWidth` (280) |
/// | Settings Overview / AI | fixed `settingsRailWidth` (280) |
/// | Voice conversation understanding | fixed `conversationUnderstandingRailWidth` (330) |
/// | Schedule | expands `scheduleRailMinimumWidth`→`scheduleRailMaximumWidth` above the split floor |
public enum CockpitLayoutPolicy {
    public static let standardWindowWidth = 1_024.0
    public static let minimumWindowWidth = 960.0
    /// Matches `ProjectBoardWindowMetrics.defaultWidth` so launch and policy share one rung.
    public static let defaultLaunchWindowWidth = 1_180.0
    public static let sidebarMaxWidth = 240.0
    public static let railWidth = 240.0
    /// Inbox triage desk needs a wider rail so Convert / Proposed Actions /
    /// Details stay readable at the 1024×676 contract without truncating the
    /// sample's voice-memo density. Other workflows keep `railWidth`.
    public static let inboxRailWidth = 280.0
    /// Overview / AI readiness copy needs slightly more than workflow rails.
    public static let settingsRailWidth = 280.0
    /// Conversation Understanding column stays fixed so chat + plan stay readable.
    public static let conversationUnderstandingRailWidth = 330.0
    public static let scheduleRailMinimumWidth = 240.0
    public static let scheduleRailMaximumWidth = 320.0
    /// Growth starts once content clears the split floor (730).
    public static let scheduleRailGrowthRate = 0.12
    public static let splitSpacing = 12.0
    /// Keep the 1024pt board detail column (≈784pt) and slightly padded Settings
    /// surfaces above this floor, while the 960pt minimum window (720pt content)
    /// still stacks rails. 730 leaves headroom for scene padding without losing
    /// the Overview/AI desk split in visual evidence.
    public static let splitMinimumContentWidth = 730.0
    /// Soft floor for the primary column beside a fixed 240pt rail at the split
    /// threshold. Desks apply `minWidth: 0` so SwiftUI can still compress under
    /// temporary GeometryReader under-measure without clipping the rail.
    public static let primaryColumnMinimumWidth = 478.0

    public enum Desk: String, CaseIterable, Sendable {
        case inbox
        case today
        case projects
        case schedule
        case done
        case voiceQuickCommand
        case voiceConversation
        case settings
    }

    public enum NarrowSecondaryPlacement: Equatable, Sendable {
        /// Secondary rail moves under the primary column (supported minimum).
        case stackBelowPrimary
    }

    public static var standardContentWidth: Double {
        standardWindowWidth - sidebarMaxWidth
    }

    public static func contentWidth(forWindowWidth windowWidth: Double) -> Double {
        max(0, windowWidth - sidebarMaxWidth)
    }

    public static func windowWidth(forContentWidth contentWidth: Double) -> Double {
        contentWidth + sidebarMaxWidth
    }

    public static func presentsSplitRail(contentWidth: Double) -> Bool {
        contentWidth >= splitMinimumContentWidth
    }

    /// Prefer AppKit / evidence content width when GeometryReader under-reports
    /// the NavigationSplitView detail column, which would otherwise stack rails
    /// incorrectly at the 1024×676 contract.
    public static func presentsSplitRail(
        measuredContentWidth: Double,
        authoritativeContentWidth: Double?
    ) -> Bool {
        if let authoritativeContentWidth, authoritativeContentWidth > 0 {
            return presentsSplitRail(contentWidth: authoritativeContentWidth)
        }
        return presentsSplitRail(
            contentWidth: layoutContentWidth(measuredContentWidth: measuredContentWidth)
        )
    }

    /// Cap ideal-size inflation from wide children so split HStacks stay inside
    /// the visible detail column (Today recommendation cards ~1050pt ideal).
    public static func layoutContentWidth(measuredContentWidth: Double) -> Double {
        min(max(measuredContentWidth, 1), standardContentWidth)
    }

    public static func showsSecondaryIntegrations(contentWidth: Double) -> Bool {
        presentsSplitRail(contentWidth: contentWidth)
    }

    public static func narrowSecondaryPlacement(contentWidth: Double) -> NarrowSecondaryPlacement {
        _ = contentWidth
        return .stackBelowPrimary
    }

    public static func narrowSecondaryPlacement(for desk: Desk) -> NarrowSecondaryPlacement {
        _ = desk
        return .stackBelowPrimary
    }

    public static func railWidth(for desk: Desk, contentWidth: Double) -> Double {
        switch desk {
        case .today, .projects, .done, .voiceQuickCommand:
            return railWidth
        case .inbox:
            return inboxRailWidth
        case .settings:
            return settingsRailWidth
        case .voiceConversation:
            return conversationUnderstandingRailWidth
        case .schedule:
            return scheduleRailWidth(contentWidth: contentWidth)
        }
    }

    /// Schedule rail is fixed at the split floor, then grows toward
    /// `scheduleRailMaximumWidth` as the detail column widens past launch.
    public static func scheduleRailWidth(contentWidth: Double) -> Double {
        let grown =
            scheduleRailMinimumWidth
            + max(0, contentWidth - splitMinimumContentWidth) * scheduleRailGrowthRate
        return min(scheduleRailMaximumWidth, grown)
    }
}
