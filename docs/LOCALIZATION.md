# Localization

Mafus 0.2.0 includes 24 languages and 254 application messages. Choose the system language or an explicit language in Settings → Write. Localization happens entirely offline; the app never sends text to a translation service.

Tables live in `Sources/Mafus/Resources/Translations/<language>.json`. Russian source messages are stable keys. Keep every key and preserve `{0}`, `{1}` placeholders exactly. Technical names such as UEFI:NTFS, ISO and SkuSiPolicy.p7b stay unchanged. Do not translate filenames, shell arguments or generated Windows scripts.

Translations were initially machine assisted; English technical terms and selected navigation labels were edited manually. Ukrainian completion was translated locally. Native-speaker reviews are welcome. Raw diskutil/Rust errors, Windows edition metadata and downloaded Microsoft web pages retain their original language. System file dialogs follow macOS language.

Run `python3 scripts/check-localizations.py` before submitting a translation. The build fails on missing messages or altered placeholders. Add new languages to `Localization.languages`, `CFBundleLocalizations` and the checker’s supported list together.
