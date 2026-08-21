import SuisuiCore
import SwiftUI

/// AppKit-backed detail content width for cockpit split decisions. Nil when the
/// board window has not published a width yet (first layout / non-board hosts).
private struct CockpitAuthoritativeContentWidthKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    var cockpitAuthoritativeContentWidth: Double? {
        get { self[CockpitAuthoritativeContentWidthKey.self] }
        set { self[CockpitAuthoritativeContentWidthKey.self] = newValue }
    }
}

enum CockpitSplitLayout {
    /// Resolve split vs stack using authoritative window content when present.
    static func presentsSplitRail(
        measuredWidth: CGFloat,
        authoritativeContentWidth: Double?
    ) -> Bool {
        CockpitLayoutPolicy.presentsSplitRail(
            measuredContentWidth: Double(measuredWidth),
            authoritativeContentWidth: authoritativeContentWidth
        )
    }

    static func layoutWidth(
        measuredWidth: CGFloat,
        authoritativeContentWidth: Double?
    ) -> CGFloat {
        CGFloat(
            CockpitLayoutPolicy.layoutContentWidth(
                measuredContentWidth: Double(measuredWidth),
                authoritativeContentWidth: authoritativeContentWidth
            )
        )
    }

    static func railWidth(for desk: CockpitLayoutPolicy.Desk, contentWidth: CGFloat) -> CGFloat {
        CGFloat(CockpitLayoutPolicy.railWidth(for: desk, contentWidth: Double(contentWidth)))
    }
}

extension View {
    /// Primary column beside a fixed-width rail: compress under temporary
    /// under-measure without pushing the rail off-screen.
    func cockpitSplitPrimaryColumn() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Keep the secondary rail's intrinsic width winning over expansive primary children.
    func cockpitSplitSecondaryRail(width: CGFloat) -> some View {
        frame(width: width, alignment: .topLeading)
            .layoutPriority(1)
    }
}
