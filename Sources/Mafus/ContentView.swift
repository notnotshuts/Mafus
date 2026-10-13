import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var confirm = false
    @State private var confirmAfterSettings = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let accent = Color(red: 0.27, green: 0.38, blue: 0.96)
    var body: some View {
        ZStack {
            MafusBackground(accent: accent)
            VStack(spacing: 22) {
                MafusHeader(accent: accent)
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("ОБРАЗ СИСТЕМЫ")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        ImageSelectionCard(model: model, accent: accent)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("USB-НАКОПИТЕЛЬ")).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        DriveSelectionCard(model: model, accent: accent)
                    }
                }
                HStack {
                    Label(model.systemDescription, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button { model.showAdvanced.toggle() } label: { Image(systemName: "slider.horizontal.3").padding(9) }
                        .buttonStyle(.plain).modifier(GlassSurface(corner: 12, interactive: true))
                        .help(L("Параметры записи")).accessibilityLabel(L("Параметры записи"))
                        .disabled(model.busy)
                        .sheet(isPresented: $model.showAdvanced, onDismiss: {
                            if confirmAfterSettings { confirmAfterSettings = false; confirm = true }
                        }) {
                            AdvancedView(model: model) { operation in
                                model.prepareOperation(operation); confirmAfterSettings = true; model.showAdvanced = false
                            }
                        }
                }
                Spacer(minLength: 0)
                if model.downloading {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label(model.downloadStatus, systemImage: "arrow.down.circle").font(.caption); Spacer(); Button(L("Отменить")) { model.cancelDownload() }.font(.caption) }
                        Text(model.downloadName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        if model.downloadTotal > 0 { ProgressView(value: model.downloadProgress) } else { ProgressView().controlSize(.small) }
                    }
                }
                if model.busy || model.completed {
                    VStack(spacing: 10) {
                        HStack {
                            Label(model.phase, systemImage: model.completed ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                                .foregroundStyle(model.completed ? Color.green : .primary)
                            Spacer()
                            Text([model.speed, model.remainingTime].filter { !$0.isEmpty }.joined(separator: " · ")).foregroundStyle(.secondary)
                        }.font(.caption)
                        if model.busy && model.speed.isEmpty { ProgressView().controlSize(.small).frame(maxWidth: .infinity) }
                        else { ProgressView(value: model.progress).tint(accent) }
                    }
                    .transition(.opacity)
                }
                if let issue = model.validationIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                if !model.coreAvailable {
                    Text(L("Ядро записи отсутствует. Соберите приложение через scripts/build.sh.")).font(.caption).foregroundStyle(.orange)
                }
                if model.busy {
                    Button(model.cancelling ? L("Отмена после текущего этапа…") : L("Отменить операцию")) { model.cancel() }.disabled(model.cancelling)
                }
                OperationButton(model: model) { model.prepareOperation("write"); confirm = true }
                Text(model.busy ? L("Не отключайте накопитель до завершения") : model.drive == nil ? L("Подключите USB и выберите образ для начала") : L("Данные на выбранном USB будут стёрты"))
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 25)
        }
        .preferredColorScheme(model.appearance == "dark" ? .dark : model.appearance == "light" ? .light : nil)
        .tint(accent)
        .environment(\.locale, Localization.shared.locale)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: model.busy)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: model.completed)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: model.downloading)
        .confirmationDialog("\(model.operationTitle): \(model.pendingDrive?.name ?? L("накопитель"))?", isPresented: $confirm, titleVisibility: .visible) {
            Button(model.operationTitle, role: model.operationDestructive ? .destructive : nil) { Task { await model.perform(model.pendingOperation) } }
        } message: {
            Text(model.confirmationText)
        }
        .alert("Mafus", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(L("Понятно")) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
