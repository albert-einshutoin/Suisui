import SwiftUI

/// Shared layout and styling tokens for SoloPM surfaces.
/// Views should consume these instead of hardcoding magic numbers so
/// spacing, corner radii, and status colors stay consistent across the app.
/// See docs/ux/design-system.md for usage guidance.
enum SoloPMSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum SoloPMRadius {
    static let control: CGFloat = 6
    static let card: CGFloat = 10
}

/// Semantic status tones. Always route status coloring through this enum so
/// the same meaning renders the same color on every screen and in both themes.
enum SoloPMTone {
    case neutral
    case attention
    case danger
    case positive

    var color: Color {
        switch self {
        case .neutral:
            .secondary
        case .attention:
            .orange
        case .danger:
            .red
        case .positive:
            .green
        }
    }
}

/// A compact count/status badge, used for glanceable values such as
/// overdue counts in the menu bar summary.
struct SoloPMStatusChip: View {
    let text: String
    let tone: SoloPMTone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
            .padding(.horizontal, SoloPMSpacing.sm)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tone == .neutral ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(tone.color.opacity(0.14)))
            )
    }
}

extension View {
    /// Standard inset card treatment for grouped content inside panels.
    func soloCard() -> some View {
        padding(SoloPMSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SoloPMRadius.card, style: .continuous)
                    .fill(.quaternary.opacity(0.5))
            )
    }
}
