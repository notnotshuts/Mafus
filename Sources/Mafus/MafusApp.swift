import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.busy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Дождитесь завершения записи"
        alert.informativeText = "Прерывание записи может оставить USB незагрузочным."
        alert.addButton(withTitle: "Продолжить запись"); alert.runModal()
        return .terminateCancel
    }
}

@main struct MafusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 560, idealWidth: 640, maxWidth: 860, minHeight: 600, idealHeight: 650, maxHeight: 840)
                .task { delegate.model = model; model.startWatching(); await model.refresh() }
        }
        .defaultSize(width: 640, height: 650)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть образ…") { model.chooseImage() }.keyboardShortcut("o").disabled(model.busy)
            }
            CommandMenu("Инструменты") {
                Button("Параметры…") { model.settingsTab = 0; model.showAdvanced = true }.keyboardShortcut(",")
                Button("Журнал") { model.settingsTab = 4; model.showAdvanced = true }.keyboardShortcut("l")
                Button("Сохранить журнал…") { model.saveLog() }.keyboardShortcut("p")
                Button("Контрольные суммы образа") { Task { await model.calculateHashes() } }.disabled(model.image == nil || model.hashing)
            }
            CommandMenu("Накопитель") {
                Button("Обновить список") { Task { await model.refresh() } }.keyboardShortcut("r").disabled(model.busy)
                Button("Извлечь") { Task { await model.eject() } }.disabled(model.busy || model.drive == nil)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var confirm = false
    @State private var dragging = false
    @State private var confirmAfterSettings = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let accent = Color(red: 0.27, green: 0.38, blue: 0.96)
    var body: some View {
        ZStack {
            background
            VStack(spacing: 22) {
                header
                VStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ОБРАЗ СИСТЕМЫ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        imageRow
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("USB-НАКОПИТЕЛЬ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                        driveRow
                    }
                }
                HStack {
                    Label(model.systemDescription, systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button { model.showAdvanced.toggle() } label: { Image(systemName: "slider.horizontal.3").padding(9) }
                        .buttonStyle(.plain).modifier(GlassSurface(corner: 12, interactive: true))
                        .help("Параметры записи").accessibilityLabel("Параметры записи")
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
                        HStack { Label(model.downloadStatus, systemImage: "arrow.down.circle").font(.caption); Spacer(); Button("Отменить") { model.cancelDownload() }.font(.caption) }
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
                    Text("Ядро записи отсутствует. Соберите приложение через scripts/build.sh.").font(.caption).foregroundStyle(.orange)
                }
                if model.busy {
                    Button(model.cancelling ? "Отмена после текущего этапа…" : "Отменить операцию") { model.cancel() }.disabled(model.cancelling)
                }
                actionButton
                Text(model.busy ? "Не отключайте накопитель до завершения" : model.drive == nil ? "Подключите USB и выберите образ для начала" : "Данные на выбранном USB будут стёрты")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 30).padding(.top, 40).padding(.bottom, 25)
        }
        .preferredColorScheme(model.appearance == "dark" ? .dark : model.appearance == "light" ? .light : nil)
        .tint(accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.busy)
        .confirmationDialog("\(model.operationTitle): \(model.pendingDrive?.name ?? "накопитель")?", isPresented: $confirm, titleVisibility: .visible) {
            Button(model.operationTitle, role: model.operationDestructive ? .destructive : nil) { Task { await model.perform(model.pendingOperation) } }
        } message: {
            Text(model.confirmationText)
        }
        .alert("Mafus", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("Понятно") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            if !reduceTransparency {
                Ellipse().fill(accent.opacity(0.12)).frame(width: 460, height: 370).blur(radius: 75).offset(x: -210, y: -210)
                Ellipse().fill(Color.cyan.opacity(0.09)).frame(width: 330, height: 350).blur(radius: 75).offset(x: 200, y: 150)
            }
        }.ignoresSafeArea()
    }
    private var header: some View {
        HStack(spacing: 15) {
            Image(systemName: "externaldrive.fill.badge.plus")
                .font(.system(size: 25, weight: .medium)).foregroundStyle(accent)
                .frame(width: 60, height: 60).modifier(GlassSurface(corner: 19))
            VStack(alignment: .leading, spacing: 4) {
                Text("mafus").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Ваш загрузочный USB").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.bottom, 12)
    }
    private var imageRow: some View {
        HStack(spacing: 14) {
            Image(systemName: model.image == nil ? "opticaldisc" : "doc.fill").font(.title2).foregroundStyle(accent).frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.image?.url.lastPathComponent ?? "Выберите образ").font(.headline).lineLimit(1)
                    .help(model.image?.url.path ?? "ISO, IMG, VHD, ZIP или сжатый образ")
                Text(model.image.map { "\($0.capacity) · \($0.url.pathExtension.uppercased())" } ?? "ISO, IMG, VHD · Windows и Linux").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(spacing: 7) {
                Button(model.image == nil ? "Выбрать файл…" : "Изменить") { model.chooseImage() }.disabled(model.busy)
                Button("Скачать ISO") { model.settingsTab = 3; model.showAdvanced = true }.buttonStyle(.link).font(.caption).disabled(model.busy)
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
    private var driveRow: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive").font(.title2).foregroundStyle(accent).frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                if model.drives.isEmpty {
                    Text(model.scanning ? "Поиск USB…" : "Подключите USB").font(.headline)
                    Text("Внешний накопитель для записи").font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("USB-накопитель", selection: $model.selectedDriveID) {
                        ForEach(model.drives) { drive in Text("\(drive.name) · \(drive.capacity)").tag(drive.id) }
                    }.labelsHidden().disabled(model.busy)
                    Text(model.drive?.device ?? "").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let image = model.image, let drive = model.drive, image.size > drive.size {
                    Text("Образ больше накопителя").font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 4)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain).padding(6).help("Обновить накопители").accessibilityLabel("Обновить накопители")
                .disabled(model.busy || model.scanning)
        }.padding(18).frame(minHeight: 80).modifier(GlassSurface(corner: 20))
    }
    @ViewBuilder private var actionButton: some View {
        if model.completed {
            Button { Task { await model.eject() } } label: { Label("Извлечь USB", systemImage: "eject.fill").frame(maxWidth: .infinity).padding(.vertical, 10) }
                .modifier(PrimaryGlassButton()).disabled(model.drive == nil)
        } else {
            Button { model.prepareOperation("write"); confirm = true } label: {
                Label(model.busy ? "Выполняется операция…" : "Создать загрузочный USB", systemImage: "arrow.down.to.line")
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }.modifier(PrimaryGlassButton()).disabled(!model.canWrite)
        }
    }

}

private struct GlassSurface: ViewModifier {
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
private struct PrimaryGlassButton: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.buttonStyle(.glassProminent).controlSize(.large) }
        else { content.buttonStyle(.borderedProminent).controlSize(.large) }
    }
}
