import SwiftUI

extension AdvancedView {
    var journal: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsCard(L("История операций")) {
                if model.log.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.alignleft").font(.system(size: 28)).foregroundStyle(.tertiary)
                        Text(L("Журнал пока пуст")).font(.headline)
                        Text(L("Здесь появятся этапы операций и сообщения об ошибках")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 42)
                } else { codeBlock(model.log) }
            }
            SettingsCard(L("Сохранение")) {
                SettingsToggle(L("Хранить журнал между запусками"), detail: L("История остаётся на этом Mac"), isOn: $model.persistLog)
                Divider()
                HStack { Text(L("Экспорт в текстовый файл")).font(.system(size: 13)); Spacer(); Button(L("Сохранить…")) { model.saveLog() }.disabled(model.log.isEmpty) }
            }
        }
    }
}
