import SwiftUI
import UniformTypeIdentifiers

struct DriveSelectionCard: View {
    @ObservedObject var model: AppModel
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive").font(.title2).foregroundStyle(accent).frame(width: 34)
                .symbolEffect(.pulse, options: .repeating, isActive: model.scanning && !reduceMotion)
            VStack(alignment: .leading, spacing: 5) {
                if model.drives.isEmpty {
                    Text(model.scanning ? L("Поиск USB…") : L("Подключите USB")).font(.headline)
                    Text(L("Внешний накопитель для записи")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker(L("USB-накопитель"), selection: $model.selectedDriveID) {
                        ForEach(model.drives) { drive in Text("\(drive.name) · \(drive.capacity)").tag(drive.id) }
                    }.labelsHidden().disabled(model.busy)
                    Text(model.drive?.device ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let image = model.image, let drive = model.drive, image.size > drive.size {
                    Text(L("Образ больше накопителя")).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 4)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).padding(6).help(L("Обновить накопители")).accessibilityLabel(L("Обновить накопители"))
                .disabled(model.busy || model.scanning)
        }.padding(18).frame(minHeight: 80).modifier(GlassSurface(corner: 20))
    }
}
