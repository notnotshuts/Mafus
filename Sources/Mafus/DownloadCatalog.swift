import Foundation

enum ImageArchitecture: String, CaseIterable, Identifiable, Sendable {
    case x64, arm64
    var id: String { rawValue }
    var title: String { self == .x64 ? "Intel / AMD · x64" : "ARM · arm64" }
    var debian: String { self == .x64 ? "amd64" : "arm64" }
    var linux: String { self == .x64 ? "x86_64" : "aarch64" }
}
struct CatalogImage: Identifiable, Sendable {
    let id: String, name: String, detail: String, symbol: String
    let architectures: [ImageArchitecture]
    enum Resolver: Sendable {
        case directory(String, String)
        case latestDirectory(String, String)
        case fedora(String)
        case direct(String)
    }
    let resolver: Resolver
    static let all: [Self] = [
        .init(id: "ubuntu", name: "Ubuntu", detail: "LTS · Desktop", symbol: "circle.hexagongrid.fill", architectures: [.x64], resolver: .directory("https://releases.ubuntu.com/26.04/", "ubuntu-.*-desktop-amd64\\.iso$")),
        .init(id: "ubuntu-server", name: "Ubuntu Server", detail: L("LTS · сервер"), symbol: "server.rack", architectures: [.x64,.arm64], resolver: .directory("{ubuntu-server}", "^ubuntu-.*-live-server-{deb}\\.iso$")),
        .init(id: "kubuntu", name: "Kubuntu", detail: "LTS · KDE Plasma", symbol: "k.circle.fill", architectures: [.x64], resolver: .directory("https://cdimage.ubuntu.com/kubuntu/releases/26.04/release/", "kubuntu-.*-desktop-amd64\\.iso$")),
        .init(id: "xubuntu", name: "Xubuntu", detail: "LTS · Xfce", symbol: "x.circle.fill", architectures: [.x64], resolver: .directory("https://cdimage.ubuntu.com/xubuntu/releases/26.04/release/", "xubuntu-.*-desktop-amd64\\.iso$")),
        .init(id: "lubuntu", name: "Lubuntu", detail: "LTS · LXQt", symbol: "l.circle.fill", architectures: [.x64], resolver: .directory("https://cdimage.ubuntu.com/lubuntu/releases/26.04/release/", "lubuntu-.*-desktop-amd64\\.iso$")),
        .init(id: "debian", name: "Debian", detail: "Stable · netinst", symbol: "circle.dotted.circle", architectures: [.x64,.arm64], resolver: .directory("https://cdimage.debian.org/debian-cd/current/{deb}/iso-cd/", "^debian-[0-9].*-{deb}-netinst\\.iso$")),
        .init(id: "debian-live", name: "Debian Live", detail: "Stable · Xfce", symbol: "circle.dotted.circle", architectures: [.x64], resolver: .directory("https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid/", "debian-live-.*-amd64-xfce\\.iso$")),
        .init(id: "fedora", name: "Fedora", detail: "Workstation · GNOME", symbol: "f.circle.fill", architectures: [.x64,.arm64], resolver: .fedora("Workstation")),
        .init(id: "fedora-kde", name: "Fedora KDE", detail: "KDE Plasma Desktop", symbol: "f.circle.fill", architectures: [.x64,.arm64], resolver: .fedora("KDE")),
        .init(id: "mint", name: "Linux Mint", detail: "Stable · Cinnamon", symbol: "leaf.fill", architectures: [.x64], resolver: .latestDirectory("https://mirrors.edge.kernel.org/linuxmint/stable/", "linuxmint-.*-cinnamon-64bit\\.iso$")),
        .init(id: "arch", name: "Arch Linux", detail: L("Rolling · установщик"), symbol: "a.circle.fill", architectures: [.x64], resolver: .directory("https://geo.mirror.pkgbuild.com/iso/latest/", "archlinux-.*-x86_64\\.iso$")),
        .init(id: "opensuse", name: "openSUSE", detail: "Tumbleweed · DVD", symbol: "o.circle.fill", architectures: [.x64], resolver: .directory("https://download.opensuse.org/tumbleweed/iso/", "openSUSE-Tumbleweed-DVD-x86_64-Current\\.iso$")),
        .init(id: "alpine", name: "Alpine Linux", detail: L("Standard · компактная система"), symbol: "mountain.2.fill", architectures: [.x64,.arm64], resolver: .directory("https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/{linux}/", "alpine-standard-.*-{linux}\\.iso$")),
        .init(id: "kali", name: "Kali Linux", detail: L("Installer · инструменты безопасности"), symbol: "k.circle", architectures: [.x64,.arm64], resolver: .directory("https://cdimage.kali.org/current/", "kali-linux-.*-installer-{deb}\\.iso$")),
        .init(id: "rocky", name: "Rocky Linux", detail: "10 · Minimal", symbol: "mountain.2", architectures: [.x64,.arm64], resolver: .directory("https://download.rockylinux.org/pub/rocky/10/isos/{linux}/", "Rocky-.*-{linux}-minimal\\.iso$")),
        .init(id: "alma", name: "AlmaLinux", detail: "10 · Minimal", symbol: "circle.grid.2x2.fill", architectures: [.x64,.arm64], resolver: .directory("https://repo.almalinux.org/almalinux/10/isos/{linux}/", "AlmaLinux-.*-{linux}-minimal\\.iso$"))
    ]
}
struct ResolvedImage: Sendable {
    let url: URL
    let name: String
    let checksum: String?
    let checksumSource: URL?
}
enum CatalogResolver {
    static func links(in html: String, relativeTo base: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"href\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive) else { return [] }
        let ns = html as NSString
        var seen = Set<String>()
        return regex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap {
            let value = ns.substring(with: $0.range(at: 1)).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: value, relativeTo: base)?.absoluteURL, url.scheme == "https", seen.insert(url.absoluteString).inserted else { return nil }
            return url
        }
    }
    static func newestISO(_ urls: [URL], matching pattern: String) -> URL? {
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return urls.filter { url in
            let name = url.lastPathComponent
            return url.pathExtension.lowercased() == "iso" && regex?.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }.first
    }
    static func sha256(in manifest: String, filename: String) -> String? {
        let pattern = #"(?i)\b[0-9a-f]{64}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for line in manifest.components(separatedBy: .newlines) {
            // Exact filename token for GNU hashes, or filename in BSD-style parentheses.
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard tokens.contains(filename) || tokens.contains("*" + filename) || line.contains("(" + filename + ")") else { continue }
            if let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) { return (line as NSString).substring(with: match.range).lowercased() }
        }
        return nil
    }
    static func fetch(_ url: URL) async throws -> (String, URL) {
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("Mafus/0.3 (macOS; ISO catalog)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let final = response.url, final.scheme == "https", response.expectedContentLength <= 8 * 1024 * 1024 else { throw MafusError.message("Источник образа временно недоступен. Попробуйте обновить каталог позже.") }
        var data = Data(); data.reserveCapacity(128 * 1024)
        for try await byte in bytes {
            guard data.count < 8 * 1024 * 1024 else { throw MafusError.message("Сервер вернул слишком большой каталог.") }
            if data.count % 4096 == 0 { try Task.checkCancellation() }
            data.append(byte)
        }
        return (String(decoding: data, as: UTF8.self), final)
    }
    static func resolve(_ image: CatalogImage, architecture: ImageArchitecture) async throws -> ResolvedImage {
        guard image.architectures.contains(architecture) else { throw MafusError.message("Эта архитектура недоступна для выбранного образа.") }
        func expand(_ text: String) -> String { text.replacingOccurrences(of: "{deb}", with: architecture.debian).replacingOccurrences(of: "{linux}", with: architecture.linux).replacingOccurrences(of: "{ubuntu-server}", with: architecture == .x64 ? "https://releases.ubuntu.com/26.04/" : "https://cdimage.ubuntu.com/releases/26.04/release/") }
        let url: URL
        var listing: [URL] = []
        var base: URL
        switch image.resolver {
        case .direct(let address):
            url = URL(string: expand(address))!; base = url.deletingLastPathComponent()
        case .directory(let address, let pattern):
            let result = try await fetch(URL(string: expand(address))!)
            base = result.1; listing = links(in: result.0, relativeTo: base)
            guard let selected = newestISO(listing, matching: expand(pattern)) else { throw MafusError.message(L("На официальном сервере не найден подходящий ISO. Возможно, изменилась структура выпуска.")) }
            url = selected
        case .latestDirectory(let address, let pattern):
            let result = try await fetch(URL(string: address)!); base = result.1
            let versions = links(in: result.0, relativeTo: base).filter { $0.host == base.host && $0.path.hasPrefix(base.path) && $0.hasDirectoryPath && $0.lastPathComponent.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            guard let latest = versions.first else { throw MafusError.message(L("Не найден стабильный выпуск дистрибутива.")) }
            let release = try await fetch(latest); base = release.1; listing = links(in: release.0, relativeTo: base)
            guard let selected = newestISO(listing, matching: expand(pattern)) else { throw MafusError.message(L("ISO выбранного выпуска не найден.")) }
            url = selected
        case .fedora(let variant):
            let result = try await fetch(URL(string: "https://fedoraproject.org/releases.json")!)
            let data = Data(result.0.utf8)
            guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw MafusError.message(L("Не удалось прочитать каталог Fedora.")) }
            let candidates = entries.compactMap { entry -> (Int, URL, String?)? in
                guard let arch = entry["arch"] as? String, arch == architecture.linux,
                      let versionText = entry["version"] as? String, let version = Int(versionText),
                      let subvariant = entry["subvariant"] as? String, subvariant == variant,
                      let link = entry["link"] as? String, let candidate = URL(string: link), candidate.scheme == "https", candidate.pathExtension == "iso" else { return nil }
                let hash = (entry["sha256"] as? String).flatMap { $0.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil ? $0.lowercased() : nil }
                return (version, candidate, hash)
            }
            guard let selected = candidates.sorted(by: { $0.0 > $1.0 }).first else { throw MafusError.message(L("Fedora ISO для этой архитектуры не найден.")) }
            if let hash = selected.2 { return ResolvedImage(url: selected.1, name: image.name, checksum: hash, checksumSource: URL(string: "https://fedoraproject.org/releases.json")) }
            url = selected.1; base = url.deletingLastPathComponent()
            if let release = try? await fetch(base) { listing = links(in: release.0, relativeTo: release.1) }
        }
        let manifests = listing.filter { let name = $0.lastPathComponent.lowercased(); return name.contains("sha256") && !name.hasSuffix(".gpg") && !name.hasSuffix(".sig") || name.hasSuffix("-checksum") || name == "checksum" }
        let fallback = ["SHA256SUMS", "sha256sums.txt", url.lastPathComponent + ".sha256"].map { base.appendingPathComponent($0) }
        for manifest in Array((manifests + fallback).prefix(6)) {
            try Task.checkCancellation()
            if let content = try? await fetch(manifest) {
                let raw = content.0.trimmingCharacters(in: .whitespacesAndNewlines)
                let singleFileHash = manifest.lastPathComponent == url.lastPathComponent + ".sha256" && raw.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil ? raw.lowercased() : nil
                if let checksum = sha256(in: content.0, filename: url.lastPathComponent) ?? singleFileHash {
                    return ResolvedImage(url: url, name: image.name, checksum: checksum, checksumSource: content.1)
                }
            }
        }
        return ResolvedImage(url: url, name: image.name, checksum: nil, checksumSource: nil)
    }
}
