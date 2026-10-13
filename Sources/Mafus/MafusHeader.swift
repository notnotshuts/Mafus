import SwiftUI
import UniformTypeIdentifiers

struct MafusHeader: View {
    let accent: Color
    var body: some View {
        HStack(spacing: 15) {
            Image(systemName: "externaldrive.fill.badge.plus")
                .font(.system(size: 25, weight: .medium)).foregroundStyle(accent)
                .frame(width: 60, height: 60).modifier(GlassSurface(corner: 19))
            VStack(alignment: .leading, spacing: 4) {
                Text("mafus").font(.system(size: 28, weight: .bold, design: .rounded))
                Text(L("Ваш загрузочный USB")).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.bottom, 12)
    }
}
