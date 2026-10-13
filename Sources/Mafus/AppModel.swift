import AppKit
import UniformTypeIdentifiers
import SwiftUI
import Darwin

@MainActor final class AppModel: ObservableObject {
    @Published var drives: [USBDrive] = []
    @Published var selectedDriveID = "" {
        didSet { if selectedDriveID != oldValue { completed = false; progress = 0 } }
    }
    @Published var image: ImageFile?
    @Published var mode = WriteMode.automatic
    @Published var detectedMode: WriteMode?
    @Published var inspecting = false
    @Published var inspectionFailed = false
    private var inspectionID = UUID()
    private var imageID = UUID()
    private var watcher: DeviceWatcher?
    private var refreshTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    @Published var pendingDrive: USBDrive?
    private var pendingImageURL: URL?
    @Published var remainingTime = ""
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
    func prepareOperation(_ operation: String) {
        pendingOperation = operation; pendingDrive = drive; pendingImageURL = image?.url
    }
    var validationIssue: String? {
        if label.isEmpty || label.utf8.count > 11 || !label.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95 }) { return "Метка USB: 1–11 латинских букв, цифр, дефис или подчёркивание" }
        if (mode == .windows || (mode == .automatic && detectedMode == .windows)) && !windowsNTFS && filesystem != "FAT32" { return "Для установки Windows выберите FAT32 в параметрах" }
        if (mode == .windows || (mode == .automatic && detectedMode == .windows)) && bootTarget != "uefi" && (!windowsNTFS || scheme != "MBR") { return "Для BIOS/CSM Windows включите NTFS и выберите MBR" }
        if persistenceGiB > 0 && (mode == .windows || (mode == .automatic && detectedMode == .windows) || mode == .dos) { return "Persistence доступен для Linux Live" }
        return nil
    }
    @Published var verify = true
    @Published var busy = false
    @Published var scanning = false
    @Published var phase = "Готов к работе"
    @Published var progress = 0.0
    @Published var speed = ""
    @Published var error: String?
    @Published var completed = false
    @Published var windowsNTFS = false
    @Published var bootTarget = "uefi"
    @Published var persistenceGiB = 0
    @Published var scheme = "MBR"
    @Published var label = "MAFUS"
    @Published var filesystem = "FAT32"
    @Published var cluster = 0
    @Published var passes = 1
    @Published var windows = WindowsOptions()
    @Published var log = ""
    @Published var showAdvanced = false
    @Published var settingsTab = 0
    @Published var persistLog = false
    @Published var appearance = "system"
    init() {
        let defaults = UserDefaults.standard
        persistLog = defaults.bool(forKey: "persistLog")
        if persistLog { log = defaults.string(forKey: "log") ?? "" }
        scheme = defaults.string(forKey: "scheme") ?? "MBR"
        label = defaults.string(forKey: "label") ?? "MAFUS"
        appearance = defaults.string(forKey: "appearance") ?? "system"
        if let saved = defaults.string(forKey: "filesystem"), ["FAT16", "FAT32", "ExFAT"].contains(saved) { filesystem = saved }
        if let saved = defaults.object(forKey: "cluster") as? Int, [0,4096,8192,16384,32768].contains(saved) { cluster = filesystem == "ExFAT" ? 0 : saved }
        if let saved = defaults.object(forKey: "verify") as? Bool { verify = saved }
        if let saved = defaults.string(forKey: "mode"), let value = WriteMode(rawValue: saved) { mode = value }
    }
    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(scheme, forKey: "scheme"); defaults.set(label, forKey: "label")
        defaults.set(filesystem, forKey: "filesystem"); defaults.set(cluster, forKey: "cluster"); defaults.set(verify, forKey: "verify"); defaults.set(mode.rawValue, forKey: "mode")
        defaults.set(appearance, forKey: "appearance"); defaults.set(persistLog, forKey: "persistLog")
        if persistLog { defaults.set(String(log.suffix(200_000)), forKey: "log") }
    }
    @Published var hashes: ImageHashes?
    @Published var windowsDetails = ""
    @Published var analyzingWindows = false
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
    @Published var hashing = false
    @Published var downloading = false
    @Published var downloadProgress = 0.0
    @Published var downloadStatus = ""
    @Published var downloadName = ""
    @Published var downloadBytes: Int64 = 0
    @Published var downloadTotal: Int64 = 0
    @Published var catalogResolving = false
    @Published var downloadArchitecture = ImageArchitecture.x64
    @Published var resolvedImage: ResolvedImage?
    private var catalogTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    func cancelDownload() { downloadTask?.cancel() }
    func resolveCatalog(_ item: CatalogImage, architecture: ImageArchitecture) {
        catalogTask?.cancel(); resolvedImage = nil; catalogResolving = true
        catalogTask = Task {
            do {
                let result = try await CatalogResolver.resolve(item, architecture: architecture)
                try Task.checkCancellation(); resolvedImage = result; catalogResolving = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription; catalogResolving = false
            }
        }
    }
    func clearCatalogSelection() { catalogTask?.cancel(); catalogResolving = false; resolvedImage = nil }
    func download(_ address: String, expectedChecksum: String? = nil, asDOS: Bool = false) {
        guard !busy, !downloading, let url = URL(string: address), url.scheme == "https", ["iso", "img", "vhd", "gz", "bz2", "xz", "zst", "zip"].contains(url.pathExtension.lowercased()) else { error = "Укажите прямую HTTPS-ссылку на образ."; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else { error = "Выберите новое имя файла: существующий образ не перезаписывается."; return }
        downloading = true; downloadProgress = 0; downloadBytes = 0; downloadTotal = 0
        downloadName = destination.lastPathComponent; downloadStatus = "Соединяемся с сервером…"
        downloadTask = Task {
            let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 24 * 60 * 60
            let session = URLSession(configuration: config)
            let poll = Task {
                while !Task.isCancelled {
                    let tasks = await session.allTasks
                    guard !Task.isCancelled else { return }
                    if let task = tasks.first {
                        downloadBytes = task.countOfBytesReceived; downloadTotal = max(0, task.countOfBytesExpectedToReceive)
                        downloadProgress = downloadTotal > 0 ? min(1, Double(downloadBytes) / Double(downloadTotal)) : 0
                        downloadStatus = "Загружаем образ…"
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { poll.cancel(); session.invalidateAndCancel(); downloading = false; downloadTask = nil }
            do {
                let (file, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: file) }
                poll.cancel(); try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.url?.scheme == "https" else { throw MafusError.message("Сервер не вернул образ по HTTPS.") }
                let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                guard let size = attrs[.size] as? Int64, size > 0 else { throw MafusError.message("Получен пустой файл.") }
                if let type = response.mimeType, type.lowercased().contains("text/html") { throw MafusError.message("Сервер вернул веб-страницу вместо образа.") }
                downloadBytes = size; downloadTotal = size; downloadProgress = 1
                if let expectedChecksum {
                    downloadStatus = "Проверяем SHA-256…"
                    let verification = Task.detached { try ImageHashes.sha256File(file) }
                    let actual = try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
                    guard actual.caseInsensitiveCompare(expectedChecksum) == .orderedSame else { throw MafusError.message("SHA-256 не совпадает с опубликованной суммой. Образ не сохранён.") }
                    record("SHA-256 загруженного образа совпадает с опубликованной суммой")
                }
                try Task.checkCancellation()
                // Copy to a unique sibling then rename: failures never leave a completed-looking ISO.
                let partial = destination.deletingLastPathComponent().appendingPathComponent(".mafus-\(UUID().uuidString).partial")
                defer { try? FileManager.default.removeItem(at: partial) }
                try FileManager.default.moveItem(at: file, to: partial)
                try Task.checkCancellation()
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw MafusError.message("Файл назначения уже существует.") }
                try FileManager.default.moveItem(at: partial, to: destination)
                downloadStatus = "Образ загружен"; record("Образ загружен: \(destination.lastPathComponent)"); setImage(destination); if asDOS { mode = .dos; persistenceGiB = 0 }
            } catch {
                downloadStatus = Task.isCancelled ? "Загрузка отменена" : "Загрузка не завершена"
                if !Task.isCancelled { self.error = error.localizedDescription }
                record(downloadStatus + ": " + error.localizedDescription)
            }
        }
    }
    var operationTitle: String {
        ["write": "Записать образ", "format": "Форматировать USB", "backup": "Сохранить USB в образ", "read-test": "Проверить чтение USB", "bad-blocks": "Тестировать запись и ёмкость", "zero": "Обнулить USB"][pendingOperation] ?? "Операция с USB"
    }
    var operationDestructive: Bool { ["write", "format", "bad-blocks", "zero"].contains(pendingOperation) }
    var confirmationText: String {
        let target = "\(pendingDrive?.device ?? "") · \(pendingDrive?.capacity ?? "")"
        if operationDestructive { return "\(target)\nВсе данные на этом USB будут уничтожены." + (pendingOperation == "write" ? "\nОбраз: \(image?.url.lastPathComponent ?? "не выбран")" : "") + (windows.customAnswer != nil && pendingOperation == "write" ? "\nСвой файл ответа может автоматически стереть диск компьютера при установке Windows." : "") }
        return "\(target)\nБудут прочитаны все блоки накопителя. На время операции его разделы будут размонтированы."
    }
    @Published var cancelling = false
    @Published var pendingOperation = "write"
    @Published var pendingOutput: URL?
    private var cancelPath: String?
    var canUseDrive: Bool { !busy && !scanning && !downloading && coreAvailable && drive != nil }
    func record(_ text: String) {
        log += "[\(Date().formatted(date: .omitted, time: .standard))] \(text)\n"
        if persistLog { UserDefaults.standard.set(String(log.suffix(200_000)), forKey: "log") }
    }
    func saveLog() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "mafus.log"
        if panel.runModal() == .OK, let url = panel.url { do { try log.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription } }
    }
    func calculateHashes() async {
        guard !hashing, let image else { return }
        let requestID = imageID
        hashing = true; defer { hashing = false }
        do { let result = try await Task.detached { try ImageHashes.calculate(image.url) }.value; guard requestID == imageID else { return }; hashes = result; record("Контрольные суммы рассчитаны") }
        catch { if requestID == imageID { self.error = error.localizedDescription } }
    }
    func chooseDOSImage() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Загрузочный IMG MS-DOS / FreeDOS"; panel.allowedContentTypes = [.init(filenameExtension: "img") ?? .data]
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
    func cancel() {
        guard busy, let path = cancelPath else { return }
        do { try Data().write(to: URL(fileURLWithPath: path), options: .withoutOverwriting); cancelling = true; record("Запрошена отмена после текущего этапа") }
        catch { self.error = error.localizedDescription }
    }
    var drive: USBDrive? { drives.first { $0.id == selectedDriveID } }
    var coreURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mafus-core") }
    var coreAvailable: Bool { FileManager.default.isExecutableFile(atPath: coreURL.path) }
    var canWrite: Bool { !busy && !downloading && !scanning && !inspecting && validationIssue == nil && (mode != .automatic || !inspectionFailed) && coreAvailable && image != nil && drive != nil && image!.size <= drive!.size }

    var systemDescription: String {
        if inspecting { return "Определяем тип образа…" }
        if mode == .automatic && inspectionFailed { return "Выберите Windows или Linux в параметрах" }
        let resolved = mode == .automatic ? detectedMode : mode
        switch resolved {
        case .windows: return windowsNTFS ? "Windows · NTFS · \(bootTarget == "uefi" ? "UEFI" : bootTarget == "bios" ? "BIOS / CSM" : "BIOS / UEFI")" : "Windows · установочный USB для UEFI"
        case .linux: return "Linux · прямая запись ISO / IMG"
        case .dos: return "DOS · BIOS / CSM · исходная разметка IMG"
        default: return "Windows и Linux · автоматический выбор режима"
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
    func chooseImage() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Выберите загрузочный образ"; panel.allowedContentTypes = ["iso", "img", "vhd", "gz", "bz2", "xz", "zst", "zip"].map { .init(filenameExtension: $0) ?? .data }
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setImage(url)
    }
    func setImage(_ url: URL) {
        guard !busy else { return }
        do {
            image = try ImageFile(url: url); imageID = UUID(); windowsDetails = ""; completed = false; hashes = nil; phase = "Готов к работе"; progress = 0
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
                    else { inspectionFailed = true; phase = "Выберите режим записи в параметрах" }
                } catch { if inspectionID == id { inspectionFailed = true; phase = "Не удалось определить тип образа" } }
            }
        }
        catch { self.error = error.localizedDescription }
    }
    func write() async { await perform("write") }
    func perform(_ operation: String) async {
        guard canUseDrive, let current = drive, let drive = pendingDrive, current == drive else { error = "Накопитель изменился после подтверждения. Выберите USB и подтвердите операцию заново."; return }
        if operation == "write" && image?.url != pendingImageURL { error = "Образ изменился после подтверждения. Подтвердите запись заново."; return }
        if operation == "write", let issue = validationIssue { error = issue; return }
        if operation == "write" && !canWrite { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: "Mafus performs a USB operation")
        defer { if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil }
        busy = true; completed = false; cancelling = false; progress = 0; speed = ""; phase = "Проверка накопителя…"
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
        } catch { self.error = error.localizedDescription; phase = "Проверка USB не пройдена"; return }
        if cancelling { phase = "Операция отменена"; return }
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
                    guard FileManager.default.createFile(atPath: answer.path, contents: contents, attributes: [.posixPermissions: 0o600]) else { throw MafusError.message("Не удалось сохранить файл ответа Windows.") }
                    arguments += ["--answer", answer.path]
                    for (name, script) in windows.scriptFiles {
                        guard FileManager.default.createFile(atPath: staging.appendingPathComponent(name).path, contents: Data(([0xEF,0xBB,0xBF] as [UInt8])) + Data(script.utf8), attributes: [.posixPermissions: 0o600]) else { throw MafusError.message("Не удалось сохранить сценарий Windows.") }
                    }
                    if !windows.scriptFiles.isEmpty { arguments += ["--customizations", staging.path] }
                }
            }
        } catch { self.error = error.localizedDescription; busy = false; return }
        defer { if let stagedAnswer { try? FileManager.default.removeItem(at: stagedAnswer) } }
        record("Начало \(operation): \(drive.name), \(drive.device)")

        phase = "Ожидание прав администратора…"
        let script = "do shell script " + appleScriptQuote(arguments.map(shellQuote).joined(separator: " ")) + " with administrator privileges"
        let polling = Task { [weak self] in
            while !Task.isCancelled {
                if let line = lastProgressLine(progressPath), let status = WriteProgress(line: line) {
                    let newPhase = ["prepare": "Подготовка образа Windows…", "format": "Подготовка USB…", "copy": "Копирование файлов Windows…", "decompress": "Распаковка образа…", "verify": "Проверка данных…", "write": "Запись образа…", "backup": "Сохранение образа USB…", "zero": "Обнуление USB…", "bad-blocks": "Тест записи блоков…", "read-test": "Проверка чтения USB…"][status.phase] ?? "Подготовка…"
                    if self?.phase != newPhase { self?.record(newPhase) }
                    self?.phase = newPhase
                    self?.progress = status.fraction
                    let seconds = status.bytesPerSecond > 0 ? (status.total - status.completed) / status.bytesPerSecond : 0
                    self?.remainingTime = seconds > 1 && seconds.isFinite ? "≈ " + (seconds >= 60 ? "\(Int(seconds / 60)) мин" : "\(Int(seconds)) с") : ""
                    self?.speed = status.total > 0 ? ByteCountFormatter.string(fromByteCount: Int64(status.bytesPerSecond), countStyle: .file) + "/с" : ""
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        do {
            let result = try await Task.detached { try runCommand("/usr/bin/osascript", ["-e", script]) }.value
            guard result.code == 0 else { throw MafusError.message(result.error.isEmpty ? "Запись не завершена." : result.error) }
            completed = true; progress = 1; phase = operation == "backup" ? "Резервный образ сохранён" : "Операция завершена"; speed = "Можно безопасно извлечь"; record(String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            let message = error.localizedDescription
            let cancelled = cancelling || message.contains("(-128)") || message.localizedCaseInsensitiveContains("operation cancelled")
            phase = cancelled ? "Операция отменена" : "Операция не завершена"
            if !cancelled { self.error = message }
            speed = ""; record(message)
        }
        polling.cancel()
        await refresh(showErrors: false)
    }
    func eject() async {
        guard !busy, let drive else { return }
        do {
            let result = try await Task.detached { try runCommand("/usr/sbin/diskutil", ["eject", drive.device]) }.value
            guard result.code == 0 else { throw MafusError.message(result.error) }
            phase = "Накопитель извлечён"; await refresh()
        } catch { self.error = error.localizedDescription }
    }
}
