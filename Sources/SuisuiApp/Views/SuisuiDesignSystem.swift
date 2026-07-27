import AppKit
import SwiftUI

/// Shared layout and styling tokens for Suisui surfaces.
/// Views should consume these instead of hardcoding magic numbers so the
/// product can evolve without creating a second, inconsistent visual language.
enum SuisuiSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum SuisuiRadius {
    static let control: CGFloat = 6
    static let card: CGFloat = 10
}

/// Brand colors are adaptive NSColors rather than fixed RGB SwiftUI values.
/// This keeps the identity recognizable while preserving contrast in both
/// appearances and in higher-contrast system configurations.
enum SuisuiBrand {
    static let soloBlue = adaptiveColor(
        name: "Suisui.SoloBlue",
        light: NSColor(srgbRed: 0.06, green: 0.36, blue: 0.82, alpha: 1),
        dark: NSColor(srgbRed: 0.36, green: 0.66, blue: 1.00, alpha: 1)
    )

    static let signalAmber = adaptiveColor(
        name: "Suisui.SignalAmber",
        light: NSColor(srgbRed: 0.75, green: 0.38, blue: 0.03, alpha: 1),
        dark: NSColor(srgbRed: 1.00, green: 0.69, blue: 0.27, alpha: 1)
    )

    private static func adaptiveColor(name: String, light: NSColor, dark: NSColor) -> Color {
        let adaptive = NSColor(
            name: NSColor.Name(name),
            dynamicProvider: { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            }
        )
        return Color(nsColor: adaptive)
    }
}

/// A compact type ramp keeps hierarchy legible without making dense project
/// data feel like a marketing page.
enum SuisuiTypography {
    static let pageTitle: Font = .system(.title2, design: .rounded, weight: .semibold)
    static let sectionTitle: Font = .system(.headline, design: .rounded, weight: .semibold)
    static let body: Font = .body
    static let metadata: Font = .caption
    static let compactLabel: Font = .caption2.weight(.medium)
}

/// Solid semantic surfaces. Native sidebar, toolbar, Form, and inspector roots
/// intentionally continue to use their platform-provided materials.
enum SuisuiSurface {
    static let canvas: AnyShapeStyle = AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
    static let groupedContent: AnyShapeStyle = AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
    static let elevatedSelection: AnyShapeStyle = AnyShapeStyle(SuisuiBrand.soloBlue.opacity(0.12))
    static let assistantSignal: AnyShapeStyle = AnyShapeStyle(SuisuiBrand.signalAmber.opacity(0.11))
}

enum SuisuiBorder {
    static let subtle: Color = Color(nsColor: .separatorColor)
    static let selected: Color = SuisuiBrand.soloBlue.opacity(0.72)
    static let attention: Color = SuisuiBrand.signalAmber.opacity(0.78)
    static let danger: Color = Color(nsColor: .systemRed)
}

/// Motion is opt-in. Callers must pass the accessibility environment value so
/// Reduce Motion disables decorative transitions instead of merely shortening
/// them to an almost-imperceptible animation.
enum SuisuiMotion {
    static let quick: Double = 0.12
    static let standard: Double = 0.20
    static let emphasis: Double = 0.32

    static func animation(duration: Double = standard, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: duration)
    }
}

enum SuisuiIconMetrics {
    static let compact: CGFloat = 12
    static let standard: CGFloat = 16
    static let feature: CGFloat = 34
}

/// ControlSize is semantic and lets AppKit continue to own exact control
/// geometry, focus rings, and input-target behavior.
enum SuisuiControlDensity {
    static let compact: ControlSize = .small
    static let standard: ControlSize = .regular
    static let prominent: ControlSize = .large
}

/// Semantic status tones. Always route status coloring through this enum so
/// the same meaning renders the same color on every screen and in both themes.
enum SuisuiTone {
    case neutral
    /// General warning that needs user action. Signal Amber remains reserved
    /// for assistant guidance so ordinary settings problems cannot look like
    /// an AI recommendation.
    case caution
    case attention
    case danger
    case positive

    var color: Color {
        switch self {
        case .neutral:
            Color(nsColor: .secondaryLabelColor)
        case .caution:
            Color(nsColor: .systemOrange)
        case .attention:
            SuisuiBrand.signalAmber
        case .danger:
            SuisuiBorder.danger
        case .positive:
            Color(nsColor: .systemGreen)
        }
    }
}

/// A compact count/status badge, used for glanceable values such as
/// overdue counts in the menu bar summary.
struct SuisuiStatusChip: View {
    let text: String
    let tone: SuisuiTone

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tone == .neutral ? AnyShapeStyle(.secondary) : AnyShapeStyle(tone.color))
            .padding(.horizontal, SuisuiSpacing.sm)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tone == .neutral ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(tone.color.opacity(0.14)))
            )
    }
}

private struct SuisuiAssistantSignalModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .padding(SuisuiSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
                    .fill(SuisuiSurface.assistantSignal)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
                    .stroke(SuisuiBorder.attention, lineWidth: 1)
            }
            // The modifier adds no animation itself, but must stop inherited
            // decorative animation when the user has requested reduced motion.
            .transaction { transaction in
                if reduceMotion {
                    transaction.animation = nil
                }
            }
    }
}

extension View {
    /// Standard inset card treatment for grouped content inside panels.
    func soloCard() -> some View {
        padding(SuisuiSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
                    .fill(SuisuiSurface.groupedContent)
            )
            .overlay {
                RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
                    .stroke(SuisuiBorder.subtle, lineWidth: 0.5)
            }
    }

    /// Warm, restrained emphasis reserved for AI suggestions or assistant
    /// guidance. It is not a general-purpose warning card.
    func soloAssistantSignal() -> some View {
        modifier(SuisuiAssistantSignalModifier())
    }
}
