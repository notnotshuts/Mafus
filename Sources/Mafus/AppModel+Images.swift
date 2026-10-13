import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

extension AppModel {
    func analyzeWindows() async {
        guard !analyzingWindows, let image else { return }
        let requestID = imageID
        analyzingWindows = true; defer { analyzingWindows = false }
        let core = coreURL.path
        do {
            let result = try await Task.detached { try runCommand(core, ["windows-info", "--image", image.url.path]) }.value
            guard result.code == 0 else { throw MafusError.message(result.error) }
            guard requestID == imageID else { return }
            windowsDetails = String(decoding: result.data, as: UTF8.self)
        } catch { if requestID == imageID { self.error = error.localizedDescription } }
    }

    func calculateHashes() async {
        guard !hashing, let image else { return }
        let requestID = imageID
        hashing = true; defer { hashing = false }
        do { let result = try await Task.detached { try ImageHashes.calculate(image.url) }.value; guard requestID == imageID else { return }; hashes = result; record(L("Контрольные суммы рассчитаны")) }
        catch { if requestID == imageID { self.error = error.localizedDescription } }
    }

    func chooseDOSImage() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = L("Загрузочный IMG MS-DOS / FreeDOS"); panel.allowedContentTypes = [.init(filenameExtension: "img") ?? .data]
        if panel.runModal() == .OK, let url = panel.url { setImage(url); mode = .dos; persistenceGiB = 0 }
    }

    func chooseAnswer() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.xml]
        if panel.runModal() == .OK { windows.customAnswer = panel.url }
    }

    func chooseBackup() -> Bool {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.init(filenameExtension: "img") ?? .data, .init(filenameExtension: "vhd") ?? .data]; panel.nameFieldStringValue = "USB-backup.img"
        if panel.runModal() == .OK, let url = panel.url { pendingOutput = url; pendingOperation = "backup"; return true }
        return false
    }

    func chooseImage() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = L("Выберите загрузочный образ"); panel.allowedContentTypes = ["iso", "img", "vhd", "gz", "bz2", "xz", "zst", "zip"].map { .init(filenameExtension: $0) ?? .data }
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setImage(url)
    }

    func setImage(_ url: URL) {
        guard !busy else { return }
        do {
            image = try ImageFile(url: url); imageID = UUID(); windowsDetails = ""; completed = false; hashes = nil; phase = L("Готов к работе"); progress = 0
            detectedMode = nil; inspectionFailed = false
            let id = UUID(); inspectionID = id
            let core = coreURL.path
            guard coreAvailable else { return }
            inspecting = true
            Task {
                defer { if inspectionID == id { inspecting = false } }
                do {
                    let result = try await Task.detached { try runCommand(core, ["inspect", "--image", url.path]) }.value
                    guard inspectionID == id else { return }
                    if result.code == 0 { detectedMode = WriteMode(rawValue: String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) }
                    else { inspectionFailed = true; phase = L("Выберите режим записи в параметрах") }
                } catch { if inspectionID == id { inspectionFailed = true; phase = L("Не удалось определить тип образа") } }
            }
        }
        catch { self.error = error.localizedDescription }
    }
}
