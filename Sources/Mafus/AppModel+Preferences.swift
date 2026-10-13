import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

extension AppModel {
    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(scheme, forKey: "scheme"); defaults.set(label, forKey: "label")
        defaults.set(filesystem, forKey: "filesystem"); defaults.set(cluster, forKey: "cluster"); defaults.set(verify, forKey: "verify"); defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(appearance, forKey: "appearance"); defaults.set(persistLog, forKey: "persistLog")
        if persistLog { defaults.set(String(log.suffix(200_000)), forKey: "log") }
    }

    func record(_ text: String) {
        log += "[\(Date().formatted(date: .omitted, time: .standard))] \(text)\n"
        if persistLog { UserDefaults.standard.set(String(log.suffix(200_000)), forKey: "log") }
    }

    func saveLog() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "mafus.log"
        if panel.runModal() == .OK, let url = panel.url { do { try log.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
}
