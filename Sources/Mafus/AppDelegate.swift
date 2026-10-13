import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.busy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = L("Дождитесь завершения записи")
        alert.informativeText = L("Прерывание записи может оставить USB незагрузочным.")
        alert.addButton(withTitle: L("Продолжить запись")); alert.runModal()
        return .terminateCancel
    }
}
