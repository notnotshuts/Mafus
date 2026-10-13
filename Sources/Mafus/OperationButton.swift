import SwiftUI
import UniformTypeIdentifiers

struct OperationButton: View {
    @ObservedObject var model: AppModel
    let onWrite: () -> Void
    @ViewBuilder var body: some View {
        if model.completed {
            Button { Task { await model.eject() } } label: { Label(L("Извлечь USB"), systemImage: "eject.fill").frame(maxWidth: .infinity).padding(.vertical, 10) }
                .modifier(PrimaryGlassButton()).disabled(model.drive == nil)
        } else {
            Button { onWrite() } label: {
                Label(model.busy ? L("Выполняется операция…") : L("Создать загрузочный USB"), systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.modifier(PrimaryGlassButton()).disabled(!model.canWrite)
        }
    }
}
