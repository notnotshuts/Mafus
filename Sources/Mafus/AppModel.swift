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
    var inspectionID = UUID()
    var imageID = UUID()
    var watcher: DeviceWatcher?
    var refreshTask: Task<Void, Never>?
    var activity: NSObjectProtocol?
    @Published var pendingDrive: USBDrive?
    var pendingImageURL: URL?
    @Published var remainingTime = ""

    var validationIssue: String? {
        if label.isEmpty || label.utf8.count > 11 || !label.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 || $0 == 95 }) { return L("Метка USB: 1–11 латинских букв, цифр, дефис или подчёркивание") }
        if (mode == .windows || (mode == .automatic && detectedMode == .windows)) && !windowsNTFS && filesystem != "FAT32" { return L("Для установки Windows выберите FAT32 в параметрах") }
        if (mode == .windows || (mode == .automatic && detectedMode == .windows)) && bootTarget != "uefi" && (!windowsNTFS || scheme != "MBR") { return L("Для BIOS/CSM Windows включите NTFS и выберите MBR") }
        if persistenceGiB > 0 && (mode == .windows || (mode == .automatic && detectedMode == .windows) || mode == .dos) { return L("Persistence доступен для Linux Live") }
        return nil
    }
    @Published var verify = true
    @Published var busy = false
    @Published var scanning = false
    @Published var phase = L("Готов к работе")
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
    @Published var language = UserDefaults.standard.string(forKey: "language") ?? "system" {
        didSet {
            Localization.shared.language = language
            UserDefaults.standard.set(language, forKey: "language")
            if !busy { phase = L("Готов к работе"); completed = false }
        }
    }
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

    @Published var hashes: ImageHashes?
    @Published var windowsDetails = ""
    @Published var analyzingWindows = false

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
    var catalogTask: Task<Void, Never>?
    var downloadTask: Task<Void, Never>?

    var operationTitle: String {
        ["write": L("Записать образ"), "format": L("Форматировать USB"), "backup": L("Сохранить USB в образ"), "read-test": L("Проверить чтение USB"), "bad-blocks": L("Тестировать запись и ёмкость"), "zero": L("Обнулить USB")][pendingOperation] ?? L("Операция с USB")
    }
    var operationDestructive: Bool { ["write", "format", "bad-blocks", "zero"].contains(pendingOperation) }
    var confirmationText: String {
        let target = "\(pendingDrive?.device ?? "") · \(pendingDrive?.capacity ?? "")"
        if operationDestructive { return L("{0}\nВсе данные на этом USB будут уничтожены." , target) + (pendingOperation == "write" ? L("\nОбраз: {0}" , image?.url.lastPathComponent ?? L("не выбран")) : "") + (windows.customAnswer != nil && pendingOperation == "write" ? L("\nСвой файл ответа может автоматически стереть диск компьютера при установке Windows.") : "") }
        return L("{0}\nБудут прочитаны все блоки накопителя. На время операции его разделы будут размонтированы." , target)
    }
    @Published var cancelling = false
    @Published var pendingOperation = "write"
    @Published var pendingOutput: URL?
    var cancelPath: String?
    var canUseDrive: Bool { !busy && !scanning && !downloading && coreAvailable && drive != nil }

    var drive: USBDrive? { drives.first { $0.id == selectedDriveID } }
    var coreURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/mafus-core") }
    var coreAvailable: Bool { FileManager.default.isExecutableFile(atPath: coreURL.path) }
    var canWrite: Bool { !busy && !downloading && !scanning && !inspecting && validationIssue == nil && (mode != .automatic || !inspectionFailed) && coreAvailable && image != nil && drive != nil && image!.size <= drive!.size }

    var systemDescription: String {
        if inspecting { return L("Определяем тип образа…") }
        if mode == .automatic && inspectionFailed { return L("Выберите Windows или Linux в параметрах") }
        let resolved = mode == .automatic ? detectedMode : mode
        switch resolved {
        case .windows: return windowsNTFS ? "Windows · NTFS · \(bootTarget == "uefi" ? "UEFI" : bootTarget == "bios" ? "BIOS / CSM" : "BIOS / UEFI")" : L("Windows · установочный USB для UEFI")
        case .linux: return L("Linux · прямая запись ISO / IMG")
        case .dos: return L("DOS · BIOS / CSM · исходная разметка IMG")
        default: return L("Windows и Linux · автоматический выбор режима")
        }
    }

}
