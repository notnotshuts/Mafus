import SwiftUI

private enum SettingsPage: Int, CaseIterable {
    case writing, windows, tools, downloads, journal
    var title: String { ["Запись", "Windows", "Инструменты", "Загрузка", "Журнал"][rawValue] }
    var icon: String { ["externaldrive", "desktopcomputer", "wrench.and.screwdriver", "arrow.down.circle", "text.alignleft"][rawValue] }
    var subtitle: String {
        ["Разметка накопителя и параметры проверки", "Настройте установку системы под себя", "Форматирование, резервные копии и диагностика", "Образы систем из официальных источников", "История операций и сообщения приложения"][rawValue]
    }
}

struct AdvancedView: View {
    @ObservedObject var model: AppModel
    let requestOperation: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var downloadURL = ""
    private var page: SettingsPage { SettingsPage(rawValue: model.settingsTab) ?? .writing }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.title).font(.system(size: 23, weight: .semibold))
                        Text(page.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26) }
                        .buttonStyle(.borderless).help("Закрыть параметры").accessibilityLabel("Закрыть параметры")
                        .keyboardShortcut(.cancelAction)
                }.padding(24)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .writing: writing
                        case .windows: windows
                        case .tools: tools
                        case .downloads: downloads
                        case .journal: journal
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.scrollIndicators(.automatic)
                Divider()
                HStack {
                    Label("Mafus", systemImage: "externaldrive.fill").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Готово") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }.padding(.horizontal, 24).padding(.vertical, 14)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 780, height: 650)
        .preferredColorScheme(model.appearance == "dark" ? .dark : model.appearance == "light" ? .light : nil)
        .onDisappear { model.savePreferences() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text("Настройки").font(.headline)
            }.padding(.horizontal, 8).padding(.top, 12)
            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases, id: \.rawValue) { item in
                    Button { model.settingsTab = item.rawValue } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.icon).font(.system(size: 15)).frame(width: 20)
                            Text(item.title).font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).frame(height: 40)
                            .foregroundStyle(page == item ? Color.accentColor : Color.primary)
                            .background(page == item ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }
            Spacer()
            Text("Всё для вашего USB").font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 10)
        }.padding(16).frame(width: 190).frame(maxHeight: .infinity).background(.regularMaterial)
    }
    private var writing: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Накопитель") {
                setting("Режим записи") { Picker("Режим записи", selection: $model.mode) { ForEach(WriteMode.allCases) { Text($0.title).tag($0) } }.labelsHidden() }
                Divider()
                setting("Схема разделов") { Picker("Схема разделов", selection: $model.scheme) { Text("MBR").tag("MBR"); Text("GPT").tag("GPT") }.labelsHidden() }
                Divider()
                setting("Метка тома") { TextField("MAFUS", text: $model.label).textFieldStyle(.roundedBorder).accessibilityLabel("Метка тома") }
                Divider()
                setting("Файловая система") { Picker("Файловая система", selection: $model.filesystem) { Text("FAT32").tag("FAT32"); Text("FAT16").tag("FAT16"); Text("exFAT").tag("ExFAT") }.labelsHidden() }
                Divider()
                setting("Размер кластера") {
                    Picker("Размер кластера", selection: $model.cluster) {
                        Text("Автоматически").tag(0)
                        ForEach([4096,8192,16384,32768], id: \.self) { Text("\($0 / 1024) КиБ").tag($0) }
                    }.labelsHidden().disabled(model.filesystem == "ExFAT")
                }
            }
            SettingsCard("Linux Persistence") {
                Stepper(model.persistenceGiB == 0 ? "Не сохранять изменения" : "Раздел сохранения: \(model.persistenceGiB) ГиБ", value: $model.persistenceGiB, in: 0...128)
                note("Ubuntu Desktop, Debian Live и Linux Mint. Создаёт ext4-раздел и добавляет параметр загрузки; остальные ISO отклоняются до записи. Требуется дополнительное место на Mac. 0 — обычная прямая запись.")
            }
            SettingsCard("Проверка и оформление") {
                SettingsToggle("Проверять записанные данные", detail: "Сравнить содержимое USB с исходным образом", isOn: $model.verify)
                Divider()
                setting("Оформление") { Picker("Оформление", selection: $model.appearance) { Text("Как в системе").tag("system"); Text("Светлое").tag("light"); Text("Тёмное").tag("dark") }.labelsHidden() }
            }
            note("Windows использует FAT32 или NTFS с UEFI:NTFS. При прямой записи Linux разметка и загрузчики берутся из самого образа.")
        }.disabled(model.busy).onChange(of: model.filesystem) { _, value in if value == "ExFAT" { model.cluster = 0 } }
    }
    private var windows: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Загрузка Windows") {
                SettingsToggle("NTFS и UEFI:NTFS", detail: "Без разбиения больших WIM; отдельный FAT-раздел с EFI-драйвером", isOn: $model.windowsNTFS)
                Divider()
                setting("Целевая прошивка") {
                    Picker("Целевая прошивка", selection: $model.bootTarget) {
                        Text("UEFI").tag("uefi")
                        Text("BIOS / CSM").tag("bios")
                        Text("BIOS / CSM + UEFI").tag("both")
                    }.labelsHidden()
                }
                note("BIOS/CSM требует NTFS, MBR и BIOS-загрузчик в ISO. Режим UEFI:NTFS поддерживает только USB с логическими секторами 512 байт. ARM64 не поддерживает BIOS/CSM.")
            }
            SettingsCard("Установочный образ") {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Редакции Windows").font(.system(size: 13, weight: .medium))
                        Text(model.image?.url.lastPathComponent ?? "Сначала выберите ISO Windows").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button(model.analyzingWindows ? "Анализ…" : "Посмотреть") { Task { await model.analyzeWindows() } }.disabled(model.image == nil || model.analyzingWindows)
                }
                if !model.windowsDetails.isEmpty { Divider(); codeBlock(model.windowsDetails) }
            }
            SettingsCard("Установка") {
                SettingsToggle("Пропустить аппаратные проверки", detail: "TPM, Secure Boot, RAM и CPU — зависит от версии Windows", isOn: $model.windows.bypassHardware)
                Divider()
                SettingsToggle("Локальная учётная запись", detail: "Создать пользователя при установке", isOn: $model.windows.localAccount)
                if model.windows.localAccount {
                    Divider()
                    setting("Имя пользователя") { TextField("User", text: $model.windows.username).textFieldStyle(.roundedBorder).accessibilityLabel("Имя пользователя") }
                    setting("Пароль") { SecureField("Не задан", text: $model.windows.password).textFieldStyle(.roundedBorder).accessibilityLabel("Пароль") }
                    note("Пароль будет виден в файле ответа на USB. Пустое поле создаёт учётную запись без пароля.", icon: "lock")
                }
                Divider()
                SettingsToggle("Пропустить вопросы о приватности", detail: "Настроить первоначальное приветствие Windows", isOn: $model.windows.privacy)
                Divider()
                SettingsToggle("Не включать шифрование автоматически", detail: "Настройка автоматического шифрования устройства", isOn: $model.windows.disableEncryption)
            }
            SettingsCard("Quality of Life") {
                SettingsToggle("Убрать Teams", detail: "Удалить приложение и отключить автоматическую установку чата", isOn: $model.windows.removeTeams)
                Divider()
                SettingsToggle("Убрать новый Outlook", detail: "Удалить Appx-приложение; классический Office не затрагивается", isOn: $model.windows.removeOutlook)
                Divider()
                SettingsToggle("Отключить Copilot", detail: "Удалить Appx и применить политику Windows Copilot", isOn: $model.windows.disableCopilot)
                Divider()
                SettingsToggle("Отключить OneDrive", detail: "Отключить синхронизацию и запустить штатное удаление клиента", isOn: $model.windows.disableOneDrive)
                Divider()
                SettingsToggle("Меньше рекомендаций", detail: "Отключить быстрый запуск, потребительские предложения, новости и поиск Bing", isOn: $model.windows.qualityOfLife)
                note("Изменения выполняются при установке и первом входе. Результат зависит от редакции Windows; журналы — Windows/Temp/Mafus-*.log.")
            }
            SettingsCard("Защита загрузки Windows") {
                SettingsToggle("SkuSiPolicy.p7b на ESP", detail: "При первом входе скопировать политику из установленной Windows на её EFI-раздел", isOn: $model.windows.applySkuPolicy)
                note("Блокирует откат некоторых компонентов VBS. По KB5042562 это может препятствовать загрузке старых носителей восстановления. Используется только файл установленной Windows; собственного файла Mafus не подставляет.")
            }
            SettingsCard("Регион") {
                setting("Язык и регион") { TextField("Например, ru-RU", text: $model.windows.locale).textFieldStyle(.roundedBorder).accessibilityLabel("Язык и регион") }
                Divider()
                setting("Часовой пояс") { TextField("Russian Standard Time", text: $model.windows.timeZone).textFieldStyle(.roundedBorder).accessibilityLabel("Часовой пояс") }
            }
            SettingsCard("Файл ответа") {
                HStack {
                    Label(model.windows.customAnswer?.lastPathComponent ?? "Свой autounattend.xml", systemImage: "doc.text").font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Button("Выбрать…") { model.chooseAnswer() }
                    if model.windows.customAnswer != nil { Button("Убрать") { model.windows.customAnswer = nil } }
                }
                note("Свой XML заменяет настройки выше. Он может автоматически стереть диск компьютера при установке — проверьте его содержимое.")
            }
        }.disabled(model.busy)
    }
    private var tools: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("Выбранный накопитель") {
                Label(model.drive.map { "\($0.name) · \($0.capacity)" } ?? "USB не подключён", systemImage: "externaldrive").font(.system(size: 13, weight: .medium))
                if let drive = model.drive { Text(drive.device).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
            SettingsCard("DOS") {
                toolRow("FreeDOS 1.4 LiteUSB", detail: "Официальный установочный USB-образ · BIOS/CSM", icon: "terminal", button: "Скачать…") {
                    model.download("https://download.freedos.org/1.4/FD14-LiteUSB.zip", expectedChecksum: "857dcd2ebf9d3d094320154db5fb5b830acba6fb98f981a95a0ca7ab3350338b", asDOS: true)
                }
                Divider()
                toolRow("MS-DOS: свой образ", detail: "Выберите лицензированный загрузочный IMG; системные файлы не включены", icon: "doc", button: "Выбрать…") { model.chooseDOSImage() }
                note("ZIP с одним IMG распаковывается ядром перед записью. FreeDOS LiteUSB — установочный носитель проекта FreeDOS. DOS загружается через BIOS/CSM; нативного UEFI-режима DOS нет.")
            }
            SettingsCard("Обслуживание") {
                toolRow("Форматировать USB", detail: "Файловая система и разметка из раздела «Запись»", icon: "externaldrive.badge.plus", button: "Начать…") { requestOperation("format") }
                Divider()
                toolRow("Резервная копия", detail: "Сохранить накопитель в IMG или фиксированный VHD", icon: "square.and.arrow.down", button: "Сохранить…") { if model.chooseBackup() { requestOperation("backup") } }
                Divider()
                toolRow("Проверить чтение", detail: "Прочитать все блоки без изменения данных", icon: "checkmark.shield", button: "Проверить…") { requestOperation("read-test") }
            }
            SettingsCard("Тесты с полным стиранием") {
                Stepper("Проходов теста: \(model.passes)", value: $model.passes, in: 1...4).font(.system(size: 13))
                Divider()
                toolRow("Проверить блоки и ёмкость", detail: "Тест записи и чтения. Все данные будут стёрты", icon: "waveform.path.ecg", button: "Начать…", destructive: true) { requestOperation("bad-blocks") }
                Divider()
                toolRow("Обнулить USB", detail: "Записать нули на весь накопитель", icon: "eraser", button: "Обнулить…", destructive: true) { requestOperation("zero") }
            }
            SettingsCard("Контрольные суммы образа") {
                HStack {
                    Text("MD5 · SHA-1 · SHA-256 · SHA-512").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.hashing ? "Считаем…" : "Рассчитать") { Task { await model.calculateHashes() } }.disabled(model.image == nil || model.hashing)
                }
                if let hashes = model.hashes { Divider(); codeBlock(hashes.text) }
            }
        }.disabled(model.busy)
    }
    private var downloads: some View {
        VStack(alignment: .leading, spacing: 20) {
            DownloadCatalogView(model: model)
            SettingsCard("Своя ссылка на образ") {
                Text("Нужного образа нет в каталоге? Укажите прямую HTTPS-ссылку ниже.").font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard("Скачать по ссылке") {
                Text("Прямая ссылка HTTPS").font(.system(size: 13, weight: .medium))
                TextField("https://example.com/image.iso", text: $downloadURL).textFieldStyle(.roundedBorder).accessibilityLabel("Прямая ссылка HTTPS")
                HStack {
                    if model.downloading { ProgressView().controlSize(.small); Text("Загружаем образ…").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if model.downloading { Button("Отменить") { model.cancelDownload() } }
                    else { Button("Скачать…") { model.download(downloadURL) }.disabled(downloadURL.trimmingCharacters(in: .whitespaces).isEmpty || model.busy) }
                }
                note("Сохраните образ на внутренний диск Mac. После загрузки он автоматически появится в главном окне.")
            }
        }
    }
    private var journal: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard("История операций") {
                if model.log.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.alignleft").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text("Журнал пока пуст").font(.headline)
                        Text("Здесь появятся этапы операций и сообщения об ошибках").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 42)
                } else { codeBlock(model.log) }
            }
            SettingsCard("Сохранение") {
                SettingsToggle("Хранить журнал между запусками", detail: "История остаётся на этом Mac", isOn: $model.persistLog)
                Divider()
                HStack { Text("Экспорт в текстовый файл").font(.system(size: 13)); Spacer(); Button("Сохранить…") { model.saveLog() }.disabled(model.log.isEmpty) }
            }
        }
    }
    private func setting<C: View>(_ title: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control().frame(width: 230)
        }.frame(minHeight: 30)
    }
    private func toolRow(_ title: String, detail: String, icon: String, button: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(destructive ? Color.orange : Color.accentColor).frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button(button, action: action).disabled(!model.canUseDrive)
        }.padding(.vertical, 3)
    }
    private func sourceLink(_ name: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 9) { Image(systemName: symbol).font(.system(size: 22)); Text(name).font(.caption.weight(.medium)) }
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func note(_ text: String, icon: String = "info.circle") -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).padding(.top, 1)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(.secondary)
    }
    private func codeBlock(_ text: String) -> some View {
        Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsCard<C: View>: View {
    let title: String
    @ViewBuilder let content: () -> C
    init(_ title: String, @ViewBuilder content: @escaping () -> C) { self.title = title; self.content = content }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase).padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12, content: content).padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.055)))
        }
    }
}
private struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    init(_ title: String, detail: String, isOn: Binding<Bool>) { self.title = title; self.detail = detail; self._isOn = isOn }
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .fixedSize().accessibilityLabel(title).accessibilityHint(detail)
        }.padding(.vertical, 2)
    }
}
