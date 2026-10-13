import SwiftUI
import UniformTypeIdentifiers

struct ImageSelectionCard: View {
    @ObservedObject var model: AppModel
    let accent: Color
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.image == nil ? "opticaldisc" : "doc.fill").font(.title2).foregroundStyle(accent).frame(width: 34)
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 5) {
                Text(model.image?.url.lastPathComponent ?? L("Выберите образ")).font(.headline).lineLimit(1)
                    .help(model.image?.url.path ?? L("ISO, IMG, VHD, ZIP или сжатый образ"))
                Text(model.image.map { "\($0.capacity) · \($0.url.pathExtension.uppercased())" } ?? L("ISO, IMG, VHD · Windows и Linux")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 7) {
                Button(model.image == nil ? L("Выбрать файл…") : L("Изменить")) { model.chooseImage() }.disabled(model.busy)
                Button(L("Скачать ISO")) { model.settingsTab = 3; model.showAdvanced = true }.buttonStyle(.link).font(.caption).disabled(model.busy)
            }
        }.padding(18).frame(minHeight: 80).modifier(GlassSurface(corner: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(dragging ? accent : .clear, lineWidth: 2))
            .onDrop(of: [.fileURL], isTargeted: $dragging) { providers in
                guard !model.busy, let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }; Task { @MainActor in model.setImage(url) }
                }
                return true
            }
    }
}
