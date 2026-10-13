import SwiftUI

struct SettingsCard<C: View>: View {
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
struct SettingsToggle: View {
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
