<p align="center"><img src="assets/mafus-logo.svg" width="112" alt="Mafus"></p>
<h1 align="center">Mafus</h1>
<p align="center">Загрузочный USB. С вашего Mac.</p>
<p align="center">
<a href="https://github.com/notnotshuts/Mafus/releases/tag/v0.2.1"><img alt="Release 0.2.1" src="https://img.shields.io/badge/release-0.2.1-6158ef"></a>
<img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-222222">
<img alt="Apple Silicon and Intel" src="https://img.shields.io/badge/Mac-Apple_Silicon_%26_Intel-222222">
<a href="LICENSE"><img alt="GPL 3 or later" src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue"></a>
</p>
<p align="center"><a href="https://notnotshuts.github.io/Mafus/">Сайт</a> · <a href="https://github.com/notnotshuts/Mafus/releases/latest">Скачать</a> · <a href="docs/USAGE.ru.md">Руководство</a> · <a href="FUNCTIONALITY.md">Совместимость</a></p>

Mafus — нативное приложение для создания загрузочных USB на macOS. Интерфейс на **SwiftUI**, запись и подготовка образов — на **Rust**. Liquid Glass на macOS 26+, системные материалы на macOS 14–15. Windows-компьютер для подготовки USB не нужен.

**0.2.1 — экспериментальный релиз.** Сборка и файловые интеграционные тесты пройдены. Форматирование физического USB, загрузка ПК, Windows Setup и сохранение Linux-сессии после реальной перезагрузки пока не проверены. Это не полный функциональный эквивалент Rufus.

## Скачать и запустить

1. Скачайте сборку для **Apple Silicon (arm64)** или **Intel (x86_64)** со [страницы последнего релиза](https://github.com/notnotshuts/Mafus/releases/latest).
2. Распакуйте и переместите **Mafus.app** в «Программы».
3. Откройте приложение, выберите образ и внешнее USB-устройство.
4. Проверьте устройство в подтверждении стирания и запустите запись.

Пакеты предназначены для **Apple Silicon и Intel, macOS 14+**. Подпись локальная (ad hoc); Developer ID и notarization в этом релизе отсутствуют, поэтому Gatekeeper может ограничить запуск. Не отключайте защиту системы целиком. Все необходимые утилиты включены в `.app`; Homebrew и FUSE для работы не нужны.

## Исправлено в 0.2.1

Исправлена ошибка macOS `Inappropriate ioctl for device (os error 25)` при сбросе данных USB. После форматирования программа ждёт монтирования раздела и держит том открытым на время копирования Windows и проверки. Для прямой записи ISO/IMG USB остаётся размонтированным во время операции.

## Новое в 0.2.0

- 24 языка: язык системы или выбор в «Параметры → Запись». Переключение без перезапуска.
- Отдельные нативные сборки для Apple Silicon и Intel со всеми вспомогательными утилитами.
- Плавные переходы в интерфейсе, анимация поиска USB; учитывается системное уменьшение движения.
- Настройки и операции разделены на небольшие компоненты; список USB обновляется после записи.
- Короткий сайт с тёмной и светлой темами, Duck/Utya и автоматическими ссылками на GitHub Releases.

Системные диалоги используют язык macOS. Технические сообщения внешних утилит и исходные данные Windows-образов сохраняются в оригинале. Переводы подготовлены машинно и отредактированы частично; поправки носителей языка приветствуются. [Как улучшить перевод](docs/LOCALIZATION.md).

## Возможности

| Сценарий | Что делает Mafus |
|---|---|
| Windows · FAT32 | Установочный UEFI USB; большой WIM разбивается в SWM, ESD при необходимости конвертируется |
| Windows · UEFI:NTFS | NTFS + отдельный FAT EFI-раздел; большие WIM сохраняются целиком, MBR или GPT |
| Windows · BIOS/CSM | NTFS/MBR с BOOTMGR bootstrap; BIOS-only или BIOS + UEFI при наличии соответствующих загрузчиков ISO |
| Linux | Прямая запись гибридного ISO/IMG с исходными загрузчиками |
| Linux Persistence | Ubuntu Desktop, Debian Live, Linux Mint; ext4 1–128 GiB и настройка Live-пунктов GRUB/ISOLINUX |
| FreeDOS | Официальный FreeDOS 1.4 LiteUSB, загрузка с SHA-256 и запись IMG из ZIP |
| MS-DOS | Свой лицензированный загрузочный IMG; файлы Microsoft DOS не входят в приложение |
| Загрузка образов | Windows 11 через официальный сайт Microsoft; 16 Linux-профилей x64, 8 ARM64; свои HTTPS-ссылки |
| Форматы | ISO, IMG, фиксированный VHD, gzip, bzip2, XZ, Zstandard, ZIP с одним образом |
| Инструменты | FAT16/FAT32/exFAT, IMG/VHD backup, чтение, разрушительный тест блоков/ёмкости, обнуление, MD5/SHA-1/SHA-256/SHA-512 |

Windows-настройки: аппаратные проверки, локальная учётная запись, приватность, шифрование, язык/регион и часовой пояс. Отдельные опции Teams, нового Outlook, Copilot, OneDrive и рекомендаций создают unattended-сценарии для установки и первого входа. **SkuSiPolicy.p7b на ESP** берётся из установленной Windows, сверяется после копирования и включается только по выбору пользователя. Последствия [KB5042562](https://support.microsoft.com/help/5042562) указаны в интерфейсе.

## Границы совместимости

- UEFI:NTFS, Windows BIOS/CSM и persistence требуют **логических секторов 512 байт**. Прямая запись поддерживает также секторы 4 KiB.
- BIOS/CSM Windows требует NTFS и MBR; ARM64 Windows поддерживает только UEFI.
- Secure Boot зависит от прошивки, доверия EFI-сертификатам и списков отзыва.
- Persistence предназначен для поддержанных современных Live ISO. Netinst, серверный ISO и произвольный дистрибутив не становятся Live-системой.
- Для подготовки нужны образ и свободное место на внутреннем диске Mac. NTFS и persistence подготавливаются во временных образах до записи USB.
- MS-DOS из каталога системных файлов, Windows To Go, динамический VHD/VHDX и универсальный установщик GRUB/Syslinux не реализованы.

Полная таблица: [FUNCTIONALITY.md](FUNCTIONALITY.md). Описание настроек, отмены и ограничений: [руководство](docs/USAGE.ru.md).

## Собрать из исходников

Нужны Swift Command Line Tools, Rust/Cargo, Python 3, C-компилятор и стандартные утилиты macOS.

```sh
git clone https://github.com/notnotshuts/Mafus.git
cd Mafus
./scripts/build.sh
open dist/Mafus.app
```

Зависимости собираются из приложенных исходников; результат — локально подписанный `.app`. Скрипт запускает Rust-тесты, проверки Swift, NTFS и ESD/WIM/SWM. Интеграционный тест Linux с read-only монтированием синтетического ISO запускается отдельно:

```sh
cargo test --manifest-path core/Cargo.toml persistence::integration -- --ignored --nocapture
```

Тесты работают с временными файлами и образами. Они не форматируют физические USB.

## Лицензия и вклад

Код Mafus: **GPL-3.0-or-later**. Зависимости имеют собственные лицензии: [THIRD_PARTY.md](THIRD_PARTY.md). Логотип и его исходники находятся в [assets](assets). Mafus не связан с Microsoft, FreeDOS или авторами Rufus.

Ошибки и результаты испытаний на реальном оборудовании: [Issues](https://github.com/notnotshuts/Mafus/issues). Укажите macOS, модель компьютера, архитектуру целевого ПК, режим записи и версию образа. Перед публикацией журнала удалите личные пути и данные.
