import SwiftUI

struct GlassSurface: ViewModifier {
    var corner: CGFloat
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: corner))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: corner))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner))
                .overlay(RoundedRectangle(cornerRadius: corner).stroke(.white.opacity(0.16)))
        }
    }
}
struct PrimaryGlassButton: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.buttonStyle(.glassProminent).controlSize(.large) }
        else { content.buttonStyle(.borderedProminent).controlSize(.large) }
    }
}
