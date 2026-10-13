import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

extension AppModel {
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
        guard !busy, !downloading, let url = URL(string: address), url.scheme == "https", ["iso", "img", "vhd", "gz", "bz2", "xz", "zst", "zip"].contains(url.pathExtension.lowercased()) else { error = L("Укажите прямую HTTPS-ссылку на образ."); return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = url.lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else { error = L("Выберите новое имя файла: существующий образ не перезаписывается."); return }
        downloading = true; downloadProgress = 0; downloadBytes = 0; downloadTotal = 0
        downloadName = destination.lastPathComponent; downloadStatus = L("Соединяемся с сервером…")
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
                        downloadStatus = L("Загружаем образ…")
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { poll.cancel(); session.invalidateAndCancel(); downloading = false; downloadTask = nil }
            do {
                let (file, response) = try await session.download(from: url)
                defer { try? FileManager.default.removeItem(at: file) }
                poll.cancel(); try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), response.url?.scheme == "https" else { throw MafusError.message(L("Сервер не вернул образ по HTTPS.")) }
                let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
                guard let size = attrs[.size] as? Int64, size > 0 else { throw MafusError.message(L("Получен пустой файл.")) }
                if let type = response.mimeType, type.lowercased().contains("text/html") { throw MafusError.message(L("Сервер вернул веб-страницу вместо образа.")) }
                downloadBytes = size; downloadTotal = size; downloadProgress = 1
                if let expectedChecksum {
                    downloadStatus = L("Проверяем SHA-256…")
                    let verification = Task.detached { try ImageHashes.sha256File(file) }
                    let actual = try await withTaskCancellationHandler { try await verification.value } onCancel: { verification.cancel() }
                    guard actual.caseInsensitiveCompare(expectedChecksum) == .orderedSame else { throw MafusError.message(L("SHA-256 не совпадает с опубликованной суммой. Образ не сохранён.")) }
                    record(L("SHA-256 загруженного образа совпадает с опубликованной суммой"))
                }
                try Task.checkCancellation()
                // Copy to a unique sibling then rename: failures never leave a completed-looking ISO.
                let partial = destination.deletingLastPathComponent().appendingPathComponent(".mafus-\(UUID().uuidString).partial")
                defer { try? FileManager.default.removeItem(at: partial) }
                try FileManager.default.moveItem(at: file, to: partial)
                try Task.checkCancellation()
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw MafusError.message(L("Файл назначения уже существует.")) }
                try FileManager.default.moveItem(at: partial, to: destination)
                downloadStatus = L("Образ загружен"); record(L("Образ загружен: {0}" , destination.lastPathComponent)); setImage(destination); if asDOS { mode = .dos; persistenceGiB = 0 }
            } catch {
                downloadStatus = Task.isCancelled ? L("Загрузка отменена") : L("Загрузка не завершена")
                if !Task.isCancelled { self.error = error.localizedDescription }
                record(downloadStatus + ": " + error.localizedDescription)
            }
        }
    }
}
