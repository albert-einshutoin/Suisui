import SwiftUI

/// Control-layer Liquid Glass surfaces for macOS 26+, with Material fallback on
/// macOS 14. Content workflow cards intentionally stay on solid semantic tokens.
enum SuisuiLiquidGlass {
    static func controlCornerRadius(compact: Bool = false) -> CGFloat {
        compact ? SuisuiRadius.control : SuisuiRadius.card + 2
    }
}

private struct SuisuiLiquidGlassControlSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .background {
                    shape.fill(.clear)
                }
                .glassEffect(
                    interactive ? .regular.interactive() : .regular,
                    in: shape
                )
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(SuisuiBorder.subtle.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}

private struct SuisuiLiquidGlassCapturePanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: SuisuiRadius.card, style: .continuous)
        if #available(macOS 26.0, *) {
            content
                .padding(SuisuiSpacing.md)
                .background {
                    shape.fill(.clear)
                }
                .glassEffect(.regular, in: shape)
        } else {
            content
                .soloCard()
        }
    }
}

extension View {
    /// Floating control chrome for sidebar search, quick actions, and compact
    /// command affordances. Does not replace native toolbar or split-view roots.
    func suisuiLiquidGlassControlSurface(
        cornerRadius: CGFloat = SuisuiLiquidGlass.controlCornerRadius(),
        interactive: Bool = false
    ) -> some View {
        modifier(
            SuisuiLiquidGlassControlSurfaceModifier(
                cornerRadius: cornerRadius,
                interactive: interactive
            )
        )
    }

    /// Voice Command capture panel uses glass on the control layer while keeping
    /// workflow review cards on semantic solid surfaces.
    func suisuiLiquidGlassCapturePanel() -> some View {
        modifier(SuisuiLiquidGlassCapturePanelModifier())
    }

    /// Groups sibling Liquid Glass controls so macOS 26 can share sampling and
    /// morph nearby shapes. Older releases keep the content unchanged.
    @ViewBuilder
    func suisuiLiquidGlassControlGroup(
        spacing: CGFloat = SuisuiSpacing.md
    ) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }
}
