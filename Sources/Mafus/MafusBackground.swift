import SwiftUI
import UniformTypeIdentifiers

struct MafusBackground: View {
    let accent: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                Ellipse().fill(accent.opacity(0.12)).frame(width: 460, height: 370).blur(radius: 75).offset(x: -210, y: -210)
                Ellipse().fill(Color.cyan.opacity(0.09)).frame(width: 330, height: 350).blur(radius: 75).offset(x: 200, y: 150)
            }
        }.ignoresSafeArea()
    }
}
