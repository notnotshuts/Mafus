import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

extension AppModel {
    func prepareOperation(_ operation: String) {
        pendingOperation = operation; pendingDrive = drive; pendingImageURL = image?.url
    }

    func cancel() {
        guard busy, let path = cancelPath else { return }
        do { try Data().write(to: URL(fileURLWithPath: path), options: .withoutOverwriting); cancelling = true; record(L("Запрошена отмена после текущего этапа")) }
        catch { self.error = error.localizedDescription }
    }

    func write() async { await perform("write") }

    func perform(_ operation: String) async {
        guard canUseDrive, let current = drive, let drive = pendingDrive, current == drive else { error = L("Накопитель изменился после подтверждения. Выберите USB и подтвердите операцию заново."); return }
        if operation == "write" && image?.url != pendingImageURL { error = L("Образ изменился после подтверждения. Подтвердите запись заново."); return }
        if operation == "write", let issue = validationIssue { error = issue; return }
        if operation == "write" && !canWrite { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Mafus performs a USB operation")
        defer { if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil }
        busy = true; completed = false; cancelling = false; progress = 0; speed = ""; phase = L("Проверка накопителя…")
        let progressPath = "/var/tmp/mafus-\(UUID().uuidString).progress"
        cancelPath = progressPath.replacingOccurrences(of: ".progress", with: ".cancel")
        var stagedAnswer: URL?
        defer { if let stagedAnswer { try? FileManager.default.removeItem(at: stagedAnswer) } }
        defer {
            if let cancelPath { try? FileManager.default.removeItem(atPath: cancelPath) }
            busy = false; cancelPath = nil; pendingDrive = nil; cancelling = false; remainingTime = ""
        }
        var arguments = [coreURL.path, operation, "--mode", mode.rawValue, "--device", drive.device, "--expected-size", String(drive.size), "--expected-attachment", String(drive.attachmentID), "--expected-name", drive.name, "--progress", progressPath, "--scheme", scheme, "--label", label.uppercased(), "--filesystem", (operation == "write" && windowsNTFS && mode != .dos ? "NTFS" : filesystem), "--boot-target", bootTarget, "--persistence-gib", String(operation == "write" ? persistenceGiB : 0), "--cluster", String(operation == "write" && windowsNTFS && mode != .dos ? 0 : cluster), "--passes", String(passes), "--owner-uid", String(getuid())] + (verify ? ["--verify"] : [])
        if let image { arguments += ["--image", image.url.path] }
        let preflightArguments = ["preflight"] + Array(arguments.dropFirst(2))
        do {
            let executable = coreURL.path
            let result = try await Task.detached { try runCommand(executable, preflightArguments) }.value
            guard result.code == 0 else { throw MafusError.message(result.error) }
        } catch { self.error = error.localizedDescription; phase = L("Проверка USB не пройдена"); return }
        if cancelling { phase = L("Операция отменена"); return }
        if let pendingOutput, operation == "backup" { arguments += ["--output", pendingOutput.path] }
        do {
            if operation == "write" && mode != .linux && mode != .dos {
                if let custom = windows.customAnswer { arguments += ["--answer", custom.path] }
                else if windows.enabled {
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mafus")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let staging = directory.appendingPathComponent("answer-\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                    stagedAnswer = staging
                    let answer = staging.appendingPathComponent("autounattend.xml")
                    let contents = Data(try windows.answer().utf8)
                    guard FileManager.default.createFile(atPath: answer.path, contents: contents, attributes: [.posixPermissions: 0o600]) else { throw MafusError.message(L("Не удалось сохранить файл ответа Windows.")) }
                    arguments += ["--answer", answer.path]
                    for (name, script) in windows.scriptFiles {
                        guard FileManager.default.createFile(atPath: staging.appendingPathComponent(name).path, contents: Data(([0xEF,0xBB,0xBF] as [UInt8])) + Data(script.utf8), attributes: [.posixPermissions: 0o600]) else { throw MafusError.message(L("Не удалось сохранить сценарий Windows.")) }
                    }
                    if !windows.scriptFiles.isEmpty { arguments += ["--customizations", staging.path] }
                }
            }
        } catch { self.error = error.localizedDescription; busy = false; return }
        defer { if let stagedAnswer { try? FileManager.default.removeItem(at: stagedAnswer) } }
        record(L("Начало {0}: {1}, {2}" , operation, drive.name, drive.device))

        phase = L("Ожидание прав администратора…")
        let script = "do shell script " + appleScriptQuote(arguments.map(shellQuote).joined(separator: " ")) + " with administrator privileges"
        let polling = Task { [weak self] in
            while !Task.isCancelled {
                if let line = lastProgressLine(progressPath), let status = WriteProgress(line: line) {
                    let newPhase = ["prepare": L("Подготовка образа Windows…"), "format": L("Подготовка USB…"), "copy": L("Копирование файлов Windows…"), "decompress": L("Распаковка образа…"), "verify": L("Проверка данных…"), "write": L("Запись образа…"), "backup": L("Сохранение образа USB…"), "zero": L("Обнуление USB…"), "bad-blocks": L("Тест записи блоков…"), "read-test": L("Проверка чтения USB…")][status.phase] ?? L("Подготовка…")
                    if self?.phase != newPhase { self?.record(newPhase) }
                    self?.phase = newPhase
                    self?.progress = status.fraction
                    let seconds = status.bytesPerSecond > 0 ? (status.total - status.completed) / status.bytesPerSecond : 0
                    self?.remainingTime = seconds > 1 && seconds.isFinite ? "≈ " + (seconds >= 60 ? L("{0} мин" , Int(seconds / 60)) : L("{0} с" , Int(seconds))) : ""
                    self?.speed = status.total > 0 ? ByteCountFormatter.string(fromByteCount: Int64(status.bytesPerSecond), countStyle: .file) + L("/с") : ""
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        do {
            let result = try await Task.detached { try runCommand("/usr/bin/osascript", ["-e", script]) }.value
            guard result.code == 0 else { throw MafusError.message(result.error.isEmpty ? L("Запись не завершена.") : result.error) }
            completed = true; progress = 1; phase = operation == "backup" ? L("Резервный образ сохранён") : L("Операция завершена"); speed = L("Можно безопасно извлечь"); record(String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            let message = error.localizedDescription
            let cancelled = cancelling || message.contains("(-128)") || message.localizedCaseInsensitiveContains("operation cancelled")
            phase = cancelled ? L("Операция отменена") : L("Операция не завершена")
            if !cancelled { self.error = message }
            speed = ""; record(message)
        }
        polling.cancel()
        busy = false
        await refresh(showErrors: false)
    }
}
