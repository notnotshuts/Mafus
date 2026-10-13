import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
                Button(L("Открыть образ…")) { model.chooseImage() }.keyboardShortcut("o").disabled(model.busy)
            }
            CommandMenu(L("Инструменты")) {
                Button(L("Параметры…")) { model.settingsTab = 0; model.showAdvanced = true }.keyboardShortcut(",")
                Button(L("Журнал")) { model.settingsTab = 4; model.showAdvanced = true }.keyboardShortcut("l")
                Button(L("Сохранить журнал…")) { model.saveLog() }.keyboardShortcut("p")
                Button(L("Контрольные суммы образа")) { Task { await model.calculateHashes() } }.disabled(model.image == nil || model.hashing)
            }
            CommandMenu(L("Накопитель")) {
                Button(L("Обновить список")) { Task { await model.refresh() } }.keyboardShortcut("r").disabled(model.busy)
                Button(L("Извлечь")) { Task { await model.eject() } }.disabled(model.busy || model.drive == nil)
            }
        }
    }
}
