import SwiftUI

extension AdvancedView {
    var tools: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(L("Выбранный накопитель")) {
                Label(model.drive.map { "\($0.name) · \($0.capacity)" } ?? L("USB не подключён"), systemImage: "externaldrive").font(.system(size: 13, weight: .medium))
                if let drive = model.drive { Text(drive.device).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            SettingsCard("DOS") {
                toolRow("FreeDOS 1.4 LiteUSB", detail: L("Официальный установочный USB-образ · BIOS/CSM"), icon: "terminal", button: L("Скачать…")) {
                    model.download("https://download.freedos.org/1.4/FD14-LiteUSB.zip", expectedChecksum: "857dcd2ebf9d3d094320154db5fb5b830acba6fb98f981a95a0ca7ab3350338b", asDOS: true)
                }
                Divider()
                toolRow(L("MS-DOS: свой образ"), detail: L("Выберите лицензированный загрузочный IMG; системные файлы не включены"), icon: "doc", button: L("Выбрать…")) { model.chooseDOSImage() }
                note(L("ZIP с одним IMG распаковывается ядром перед записью. FreeDOS LiteUSB — установочный носитель проекта FreeDOS. DOS загружается через BIOS/CSM; нативного UEFI-режима DOS нет."))
            }
            SettingsCard(L("Обслуживание")) {
                toolRow(L("Форматировать USB"), detail: L("Файловая система и разметка из раздела «Запись»"), icon: "externaldrive.badge.plus", button: L("Начать…")) { requestOperation("format") }
                Divider()
                toolRow(L("Резервная копия"), detail: L("Сохранить накопитель в IMG или фиксированный VHD"), icon: "square.and.arrow.down", button: L("Сохранить…")) { if model.chooseBackup() { requestOperation("backup") } }
                Divider()
                toolRow(L("Проверить чтение"), detail: L("Прочитать все блоки без изменения данных"), icon: "checkmark.shield", button: L("Проверить…")) { requestOperation("read-test") }
            }
            SettingsCard(L("Тесты с полным стиранием")) {
                Stepper(L("Проходов теста: {0}" , model.passes), value: $model.passes, in: 1...4).font(.system(size: 13))
                Divider()
                toolRow(L("Проверить блоки и ёмкость"), detail: L("Тест записи и чтения. Все данные будут стёрты"), icon: "waveform.path.ecg", button: L("Начать…"), destructive: true) { requestOperation("bad-blocks") }
                Divider()
                toolRow(L("Обнулить USB"), detail: L("Записать нули на весь накопитель"), icon: "eraser", button: L("Обнулить…"), destructive: true) { requestOperation("zero") }
            }
            SettingsCard(L("Контрольные суммы образа")) {
                HStack {
                    Text("MD5 · SHA-1 · SHA-256 · SHA-512").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.hashing ? L("Считаем…") : L("Рассчитать")) { Task { await model.calculateHashes() } }.disabled(model.image == nil || model.hashing)
                }
                if let hashes = model.hashes { Divider(); codeBlock(hashes.text) }
            }
        }.disabled(model.busy)
    }
}
