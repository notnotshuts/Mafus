import SwiftUI

extension AdvancedView {
    var windows: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(L("Загрузка Windows")) {
                SettingsToggle(L("NTFS и UEFI:NTFS"), detail: L("Без разбиения больших WIM; отдельный FAT-раздел с EFI-драйвером"), isOn: $model.windowsNTFS)
                Divider()
                setting(L("Целевая прошивка")) {
                    Picker(L("Целевая прошивка"), selection: $model.bootTarget) {
                        Text("UEFI").tag("uefi")
                        Text("BIOS / CSM").tag("bios")
                        Text("BIOS / CSM + UEFI").tag("both")
                    }.labelsHidden()
                }
                note(L("BIOS/CSM требует NTFS, MBR и BIOS-загрузчик в ISO. Режим UEFI:NTFS поддерживает только USB с логическими секторами 512 байт. ARM64 не поддерживает BIOS/CSM."))
            }
            SettingsCard(L("Установочный образ")) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Редакции Windows")).font(.system(size: 13, weight: .medium))
                        Text(model.image?.url.lastPathComponent ?? L("Сначала выберите ISO Windows")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button(model.analyzingWindows ? L("Анализ…") : L("Посмотреть")) { Task { await model.analyzeWindows() } }.disabled(model.image == nil || model.analyzingWindows)
                }
                if !model.windowsDetails.isEmpty { Divider(); codeBlock(model.windowsDetails) }
            }
            SettingsCard(L("Установка")) {
                SettingsToggle(L("Пропустить аппаратные проверки"), detail: L("TPM, Secure Boot, RAM и CPU — зависит от версии Windows"), isOn: $model.windows.bypassHardware)
                Divider()
                SettingsToggle(L("Локальная учётная запись"), detail: L("Создать пользователя при установке"), isOn: $model.windows.localAccount)
                if model.windows.localAccount {
                    Divider()
                    setting(L("Имя пользователя")) { TextField("User", text: $model.windows.username).textFieldStyle(.roundedBorder).accessibilityLabel(L("Имя пользователя")) }
                    setting(L("Пароль")) { SecureField(L("Не задан"), text: $model.windows.password).textFieldStyle(.roundedBorder).accessibilityLabel(L("Пароль")) }
                    note(L("Пароль будет виден в файле ответа на USB. Пустое поле создаёт учётную запись без пароля."), icon: "lock")
                }
                Divider()
                SettingsToggle(L("Пропустить вопросы о приватности"), detail: L("Настроить первоначальное приветствие Windows"), isOn: $model.windows.privacy)
                Divider()
                SettingsToggle(L("Не включать шифрование автоматически"), detail: L("Настройка автоматического шифрования устройства"), isOn: $model.windows.disableEncryption)
            }
            SettingsCard("Quality of Life") {
                SettingsToggle(L("Убрать Teams"), detail: L("Удалить приложение и отключить автоматическую установку чата"), isOn: $model.windows.removeTeams)
                Divider()
                SettingsToggle(L("Убрать новый Outlook"), detail: L("Удалить Appx-приложение; классический Office не затрагивается"), isOn: $model.windows.removeOutlook)
                Divider()
                SettingsToggle(L("Отключить Copilot"), detail: L("Удалить Appx и применить политику Windows Copilot"), isOn: $model.windows.disableCopilot)
                Divider()
                SettingsToggle(L("Отключить OneDrive"), detail: L("Отключить синхронизацию и запустить штатное удаление клиента"), isOn: $model.windows.disableOneDrive)
                Divider()
                SettingsToggle(L("Меньше рекомендаций"), detail: L("Отключить быстрый запуск, потребительские предложения, новости и поиск Bing"), isOn: $model.windows.qualityOfLife)
                note(L("Изменения выполняются при установке и первом входе. Результат зависит от редакции Windows; журналы — Windows/Temp/Mafus-*.log."))
            }
            SettingsCard(L("Защита загрузки Windows")) {
                SettingsToggle(L("SkuSiPolicy.p7b на ESP"), detail: L("При первом входе скопировать политику из установленной Windows на её EFI-раздел"), isOn: $model.windows.applySkuPolicy)
                note(L("Блокирует откат некоторых компонентов VBS. По KB5042562 это может препятствовать загрузке старых носителей восстановления. Используется только файл установленной Windows; собственного файла Mafus не подставляет."))
            }
            SettingsCard(L("Регион")) {
                setting(L("Язык и регион")) { TextField(L("Например, ru-RU"), text: $model.windows.locale).textFieldStyle(.roundedBorder).accessibilityLabel(L("Язык и регион")) }
                Divider()
                setting(L("Часовой пояс")) { TextField("Russian Standard Time", text: $model.windows.timeZone).textFieldStyle(.roundedBorder).accessibilityLabel(L("Часовой пояс")) }
            }
            SettingsCard(L("Файл ответа")) {
                HStack {
                    Label(model.windows.customAnswer?.lastPathComponent ?? L("Свой autounattend.xml"), systemImage: "doc.text").font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Button(L("Выбрать…")) { model.chooseAnswer() }
                    if model.windows.customAnswer != nil { Button(L("Убрать")) { model.windows.customAnswer = nil } }
                }
                note(L("Свой XML заменяет настройки выше. Он может автоматически стереть диск компьютера при установке — проверьте его содержимое."))
            }
        }.disabled(model.busy)
    }
}
