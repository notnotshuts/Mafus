import Foundation

struct USBDrive: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let size: Int64
    var attachmentID: UInt64 = 0
    var device: String { "/dev/\(id)" }
    var capacity: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

enum WriteMode: String, CaseIterable, Identifiable, Sendable {
    case automatic = "auto", windows, linux, dos
    var id: String { rawValue }
    var title: String { switch self { case .automatic: return L("Автоматически"); case .windows: return L("Windows · установка"); case .linux: return L("Linux · прямая запись"); case .dos: return "DOS · BIOS / CSM" } }
}

struct ImageFile: Sendable {
    let url: URL
    let size: Int64
    var capacity: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    init(url: URL) throws {
        guard ["iso", "img", "vhd", "gz", "bz2", "xz", "zst", "zip"].contains(url.pathExtension.lowercased()) else { throw MafusError.message(L("Выберите ISO, IMG, фиксированный VHD, ZIP с образом или сжатый ISO / IMG.")) }
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType == .typeRegular, let size = values[.size] as? Int64, size > 0, (["gz", "bz2", "xz", "zst", "zip"].contains(url.pathExtension.lowercased()) || size % 512 == 0) else {
            throw MafusError.message(L("Образ должен быть обычным непустым файлом, размер которого кратен 512 байтам."))
        }
        self.url = url
        self.size = url.pathExtension.lowercased() == "vhd" ? max(0, size - 512) : size
    }
}

enum MafusError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct CommandResult: Sendable { let data: Data; let error: String; let code: Int32 }
func runCommand(_ executable: String, _ arguments: [String]) throws -> CommandResult {
    let process = Process(); let output = Pipe(); let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
    process.standardOutput = output; process.standardError = errors
    // Both pipes drain concurrently so neither can block a long-running child.
    let errorBox = ErrorOutput()
    try process.run()
    let group = DispatchGroup(); group.enter()
    DispatchQueue.global().async { errorBox.set(errors.fileHandleForReading.readDataToEndOfFile()); group.leave() }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); group.wait()
    return CommandResult(data: data, error: String(decoding: errorBox.get(), as: UTF8.self), code: process.terminationStatus)
}
private final class ErrorOutput: @unchecked Sendable {
    private let lock = NSLock(); private var data = Data()
    func set(_ value: Data) { lock.lock(); defer { lock.unlock() }; data = value }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
func appleScriptQuote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }

struct WriteProgress {
    let phase: String
    let completed: Double
    let total: Double
    let bytesPerSecond: Double
    var fraction: Double { total > 0 ? min(1, max(0, completed / total)) : 0 }
    init?(line: String) {
        let fields = line.split(separator: "\t")
        guard fields.count == 4, let done = Double(fields[1]), let total = Double(fields[2]), let speed = Double(fields[3]), done.isFinite, total.isFinite, speed.isFinite, done >= 0, total >= 0, speed >= 0, speed < Double(Int64.max) else { return nil }
        phase = String(fields[0]); completed = done; self.total = total; bytesPerSecond = speed
    }
}

func lastProgressLine(_ path: String) -> String? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    do {
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: size > 2048 ? size - 2048 : 0)
        let data = try handle.read(upToCount: 2048) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let records = text.components(separatedBy: "\n")
        return records.count >= 2 ? records[records.count - 2] : nil
    } catch { return nil }
}
