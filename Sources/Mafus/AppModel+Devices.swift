import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

extension AppModel {
    func startWatching() {
        guard watcher == nil else { return }
        watcher = DeviceWatcher { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    await self?.refresh(showErrors: false)
                }
            }
        }
    }

    func refresh(showErrors: Bool = true) async {
        guard !busy && !scanning else { return }
        scanning = true; defer { scanning = false }
        do {
            let found = try await Task.detached { try DiskService.list() }.value
            drives = found
            if !found.contains(where: { $0.id == selectedDriveID }) { selectedDriveID = found.first?.id ?? "" }
        } catch { if showErrors { self.error = error.localizedDescription } }
    }

    func eject() async {
        guard !busy, let drive else { return }
        do {
            let result = try await Task.detached { try runCommand("/usr/sbin/diskutil", ["eject", drive.device]) }.value
            guard result.code == 0 else { throw MafusError.message(result.error) }
            phase = L("Накопитель извлечён"); await refresh()
        } catch { self.error = error.localizedDescription }
    }
}
