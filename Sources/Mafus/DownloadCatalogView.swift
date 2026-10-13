import SwiftUI

struct DownloadCatalogView: View {
    @ObservedObject var model: AppModel
    private var architecture: ImageArchitecture { model.downloadArchitecture }
    @State private var search = ""
    @State private var selectedID: String?
    @State private var windowsPresented = false
    @State private var capturedWindowsURL: URL?
    private var entries: [CatalogImage] {
        CatalogImage.all.filter { $0.architectures.contains(architecture) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Архитектура компьютера для установки").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Picker("Архитектура", selection: $model.downloadArchitecture) { ForEach(ImageArchitecture.allCases) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 180)
            }
            Button { windowsPresented = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "desktopcomputer").font(.system(size: 25)).foregroundStyle(Color.accentColor)
                        .frame(width: 52, height: 52).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Windows 11").font(.headline)
                        Text("Официальный ISO Microsoft · выпуск и язык на выбор").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.accentColor.opacity(0.2)))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }.buttonStyle(.plain).disabled(model.downloading || model.busy)
                .sheet(isPresented: $windowsPresented, onDismiss: {
                    if let url = capturedWindowsURL { capturedWindowsURL = nil; model.download(url.absoluteString) }
                }) {
                    WindowsDownloadView(architecture: architecture) { url in capturedWindowsURL = url }
                }
            HStack {
                Text("LINUX · \(entries.count) ОБРАЗОВ").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                TextField("Найти дистрибутив", text: $search).textFieldStyle(.roundedBorder).frame(width: 210).accessibilityLabel("Найти дистрибутив")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(entries) { item in
                    Button {
                        selectedID = item.id; model.resolveCatalog(item, architecture: architecture)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).font(.system(size: 22)).foregroundStyle(Color.accentColor).frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
                                Text(item.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            if selectedID == item.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).font(.caption) }
                        }.padding(13).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                            .background(selectedID == item.id ? Color.accentColor.opacity(0.09) : Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selectedID == item.id ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06)))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).disabled(model.downloading || model.busy)
                }
            }
            if model.catalogResolving {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Ищем актуальный ISO и контрольную сумму…").font(.caption).foregroundStyle(.secondary) }.padding(.vertical, 8)
            }
            if let resolved = model.resolvedImage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(resolved.name).font(.headline)
                    Text(resolved.url.lastPathComponent).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Label(resolved.checksum == nil ? "HTTPS · без опубликованной SHA-256" : "SHA-256 проверим после загрузки", systemImage: resolved.checksum == nil ? "lock" : "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("Скачать ISO…") { model.download(resolved.url.absoluteString, expectedChecksum: resolved.checksum) }.buttonStyle(.borderedProminent).disabled(model.downloading || model.busy)
                    }
                    Text(resolved.url.host ?? "").font(.caption2).foregroundStyle(.tertiary)
                }.padding(16).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            }
            if model.downloading {
                VStack(alignment: .leading, spacing: 9) {
                    Text(model.downloadName).font(.caption.weight(.medium)).lineLimit(2)
                    HStack { Text(model.downloadStatus); Spacer(); Text(downloadSize).monospacedDigit() }.font(.caption).foregroundStyle(.secondary)
                    if model.downloadTotal > 0 { ProgressView(value: model.downloadProgress) } else { ProgressView().controlSize(.small) }
                    Button("Отменить загрузку") { model.cancelDownload() }
                }.padding(16).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            }
            Text("Выбирайте архитектуру целевого компьютера, а не Mac, на котором создаётся USB. ARM-образ сам по себе не обеспечивает загрузку Linux на Apple Silicon.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.onChange(of: architecture) { _, _ in selectedID = nil; model.clearCatalogSelection() }
    }
    private var downloadSize: String {
        let received = ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file)
        if model.downloadTotal > 0 { return received + " / " + ByteCountFormatter.string(fromByteCount: model.downloadTotal, countStyle: .file) }
        return received
    }
}
