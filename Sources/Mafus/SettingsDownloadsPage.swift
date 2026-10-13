import SwiftUI

extension AdvancedView {
    var downloads: some View {
        VStack(alignment: .leading, spacing: 20) {
            DownloadCatalogView(model: model)
            SettingsCard(L("Своя ссылка на образ")) {
                Text(L("Нужного образа нет в каталоге? Укажите прямую HTTPS-ссылку ниже.")).font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(L("Скачать по ссылке")) {
                Text(L("Прямая ссылка HTTPS")).font(.system(size: 13, weight: .medium))
                TextField("https://example.com/image.iso", text: $downloadURL).textFieldStyle(.roundedBorder).accessibilityLabel(L("Прямая ссылка HTTPS"))
                HStack {
                    if model.downloading { ProgressView().controlSize(.small); Text(L("Загружаем образ…")).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if model.downloading { Button(L("Отменить")) { model.cancelDownload() } }
                    else { Button(L("Скачать…")) { model.download(downloadURL) }.disabled(downloadURL.trimmingCharacters(in: .whitespaces).isEmpty || model.busy) }
                }
                note(L("Сохраните образ на внутренний диск Mac. После загрузки он автоматически появится в главном окне."))
            }
        }
    }
}
