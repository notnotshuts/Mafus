import SwiftUI

extension AdvancedView {
    var writing: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(L("Накопитель")) {
                setting(L("Режим записи")) { Picker(L("Режим записи"), selection: $model.mode) { ForEach(WriteMode.allCases) { Text($0.title).tag($0) } }.labelsHidden().id(model.language) }
                Divider()
                setting(L("Схема разделов")) { Picker(L("Схема разделов"), selection: $model.scheme) { Text("MBR").tag("MBR"); Text("GPT").tag("GPT") }.labelsHidden() }
                Divider()
                setting(L("Метка тома")) { TextField("MAFUS", text: $model.label).textFieldStyle(.roundedBorder).accessibilityLabel(L("Метка тома")) }
                Divider()
                setting(L("Файловая система")) { Picker(L("Файловая система"), selection: $model.filesystem) { Text("FAT32").tag("FAT32"); Text("FAT16").tag("FAT16"); Text("exFAT").tag("ExFAT") }.labelsHidden() }
                Divider()
                setting(L("Размер кластера")) {
                    Picker(L("Размер кластера"), selection: $model.cluster) {
                        Text(L("Автоматически")).tag(0)
                        ForEach([4096,8192,16384,32768], id: \.self) { Text(L("{0} КиБ" , $0 / 1024)).tag($0) }
                    }.labelsHidden().disabled(model.filesystem == "ExFAT")
                }
            }
            SettingsCard("Linux Persistence") {
                Stepper(model.persistenceGiB == 0 ? L("Не сохранять изменения") : L("Раздел сохранения: {0} ГиБ" , model.persistenceGiB), value: $model.persistenceGiB, in: 0...128)
                note(L("Ubuntu Desktop, Debian Live и Linux Mint. Создаёт ext4-раздел и добавляет параметр загрузки; остальные ISO отклоняются до записи. Требуется дополнительное место на Mac. 0 — обычная прямая запись."))
            }
            SettingsCard(L("Проверка и оформление")) {
                SettingsToggle(L("Проверять записанные данные"), detail: L("Сравнить содержимое USB с исходным образом"), isOn: $model.verify)
                Divider()
                setting(L("Оформление")) { Picker(L("Оформление"), selection: $model.appearance) { Text(L("Как в системе")).tag("system"); Text(L("Светлое")).tag("light"); Text(L("Тёмное")).tag("dark") }.labelsHidden() }
                Divider()
                setting(L("Язык программы")) {
                    Picker(L("Язык программы"), selection: $model.language) {
                        Text(L("Как в системе")).tag("system")
                        ForEach(Localization.languages, id: \.code) { language in Text(language.name).tag(language.code) }
                    }.labelsHidden().disabled(model.busy)
                }
            }
            note(L("Windows использует FAT32 или NTFS с UEFI:NTFS. При прямой записи Linux разметка и загрузчики берутся из самого образа."))
        }.disabled(model.busy).onChange(of: model.filesystem) { _, value in if value == "ExFAT" { model.cluster = 0 } }
    }
}
