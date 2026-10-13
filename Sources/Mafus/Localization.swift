import Foundation

/// App-owned translations also cover AppKit dialogs and dynamically generated messages.
/// Technical output from diskutil, Windows images and the Rust core stays verbatim in the log.
final class Localization: @unchecked Sendable {
    static let shared = Localization()
    static let languages: [(code: String, name: String)] = [
        ("en", "English"), ("ru", "Русский"), ("de", "Deutsch"), ("fr", "Français"),
        ("es", "Español"), ("it", "Italiano"), ("pt", "Português"), ("nl", "Nederlands"),
        ("pl", "Polski"), ("uk", "Українська"), ("cs", "Čeština"), ("sk", "Slovenčina"),
        ("hu", "Magyar"), ("ro", "Română"), ("tr", "Türkçe"), ("sv", "Svenska"),
        ("da", "Dansk"), ("fi", "Suomi"), ("nb", "Norsk bokmål"), ("el", "Ελληνικά"),
        ("ja", "日本語"), ("ko", "한국어"), ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文")
    ]
    private let lock = NSLock()
    private var tables: [String: [String: String]] = [:]
    private var selected = UserDefaults.standard.string(forKey: "language") ?? "system"
    var language: String {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); defer { lock.unlock() }; selected = newValue }
    }
    var effectiveLanguage: String {
        let choice = language
        if Self.languages.contains(where: { $0.code == choice }) { return choice }
        let supported = Self.languages.map(\.code)
        return Bundle.preferredLocalizations(from: supported, forPreferences: Locale.preferredLanguages).first ?? "en"
    }
    var locale: Locale { Locale(identifier: effectiveLanguage) }
    func text(_ key: String, arguments: [String]) -> String {
        let code = effectiveLanguage
        lock.lock()
        func table(_ code: String) -> [String: String] {
            if let cached = tables[code] { return cached }
            var url = Bundle.main.url(forResource: code, withExtension: "json", subdirectory: "Translations")
            #if SWIFT_PACKAGE
            if url == nil { url = Bundle.module.url(forResource: code, withExtension: "json", subdirectory: "Translations") }
            #endif
            let data = url.flatMap { try? Data(contentsOf: $0) }
            let loaded = data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
            tables[code] = loaded
            return loaded
        }
        let template = table(code)[key] ?? table("en")[key] ?? key
        lock.unlock()
        // Single pass: filenames or other user input containing {1} are never substituted again.
        var result = "", cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]), arguments.indices.contains(index) {
                result += arguments[index]; cursor = template.index(after: end)
            } else { result.append(template[cursor]); cursor = template.index(after: cursor) }
        }
        return result
    }
}

func L(_ key: String, _ arguments: Any...) -> String {
    Localization.shared.text(key, arguments: arguments.map { String(describing: $0) })
}
