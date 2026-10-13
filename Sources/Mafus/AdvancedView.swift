import SwiftUI

enum SettingsPage: Int, CaseIterable {
    case writing, windows, tools, downloads, journal
    var title: String { [L("Запись"), "Windows", L("Инструменты"), L("Загрузка"), L("Журнал")][rawValue] }
    var icon: String { ["externaldrive", "desktopcomputer", "wrench.and.screwdriver", "arrow.down.circle", "text.alignleft"][rawValue] }
    var subtitle: String {
        [L("Разметка накопителя и параметры проверки"), L("Настройте установку системы под себя"), L("Форматирование, резервные копии и диагностика"), L("Образы систем из официальных источников"), L("История операций и сообщения приложения")][rawValue]
    }
}

struct AdvancedView: View {
    @ObservedObject var model: AppModel
    let requestOperation: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State var downloadURL = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var page: SettingsPage { SettingsPage(rawValue: model.settingsTab) ?? .writing }
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
                        .buttonStyle(.borderless).help(L("Закрыть параметры")).accessibilityLabel(L("Закрыть параметры"))
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
                    }.id(page.rawValue).transition(.opacity.combined(with: .offset(y: 8)))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.scrollIndicators(.automatic)
                Divider()
                HStack {
                    Label("Mafus", systemImage: "externaldrive.fill").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Готово")) { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }.padding(.horizontal, 24).padding(.vertical, 14)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 780, height: 650)
        .preferredColorScheme(model.appearance == "dark" ? .dark : model.appearance == "light" ? .light : nil)
        .environment(\.locale, Localization.shared.locale)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page.rawValue)
        .onDisappear { model.savePreferences() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").font(.title3).foregroundStyle(Color.accentColor)
                    .frame(width: 34, height: 34).background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                Text(L("Настройки")).font(.headline)
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
            Text(L("Всё для вашего USB")).font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 10)
        }.padding(16).frame(width: 190).frame(maxHeight: .infinity).background(.regularMaterial)
    }
    func setting<C: View>(_ title: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 14) {
            Text(title).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            control().frame(width: 230)
        }.frame(minHeight: 30)
    }
    func toolRow(_ title: String, detail: String, icon: String, button: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
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
    func sourceLink(_ name: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(spacing: 9) { Image(systemName: symbol).font(.system(size: 22)); Text(name).font(.caption.weight(.medium)) }
                .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    func note(_ text: String, icon: String = "info.circle") -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.caption).padding(.top, 1)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(.secondary)
    }
    func codeBlock(_ text: String) -> some View {
        Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}
