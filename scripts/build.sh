#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v cargo >/dev/null; then
    print -u2 'Rust is required. Install it from https://rustup.rs and retry.'
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/ModuleCache}"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
./scripts/build-filesystems.sh
python3 Tests/ntfs-check.py
./scripts/build-compression.sh
./scripts/build-wimlib.sh
python3 Tests/wimlib-check.py .build/vendor/wimlib-1.14.4/wimlib-imagex
cargo test --manifest-path core/Cargo.toml
cargo build --release --manifest-path core/Cargo.toml
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release
swiftc Sources/Mafus/Models.swift Sources/Mafus/WindowsOptions.swift Sources/Mafus/Utilities.swift Sources/Mafus/DownloadCatalog.swift Tests/checks.swift -o .build/mafus-checks
.build/mafus-checks
bin_dir=$(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release --show-bin-path)
app="dist/Mafus.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Mafus" "$app/Contents/MacOS/Mafus"
cp core/target/release/mafus-core "$app/Contents/MacOS/mafus-core"
cp .build/vendor/wimlib-1.14.4/wimlib-imagex "$app/Contents/MacOS/wimlib-imagex"
mkdir -p "$app/Contents/Resources/ThirdParty"
cp vendor/XZ-*.txt vendor/ZSTD-LICENSE.txt "$app/Contents/Resources/ThirdParty/"
cp vendor/WIMLIB-GPLv3.txt "$app/Contents/Resources/ThirdParty/"
cp vendor/wimlib-1.14.4.tar.gz "$app/Contents/Resources/ThirdParty/"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/wimlib-imagex"
cp .build/vendor/xz-5.8.4/src/xz/xz "$app/Contents/MacOS/xz"
cp .build/vendor/zstd-1.5.7/programs/zstd "$app/Contents/MacOS/zstd"
cp vendor/xz-5.8.4.tar.gz vendor/zstd-1.5.7.tar.gz "$app/Contents/Resources/ThirdParty/"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/xz"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/zstd"
for name in mkntfs ntfs-populate xorriso mke2fs; do
    cp ".build/tools/$name" "$app/Contents/MacOS/$name"
    /usr/bin/codesign --force --sign - "$app/Contents/MacOS/$name"
done
cp vendor/uefi-ntfs.img vendor/windows-*.bin vendor/mke2fs.conf "$app/Contents/Resources/"
cp vendor/*.tar.gz vendor/*.tgz vendor/*LICENSE*.txt vendor/*COPYING*.txt "$app/Contents/Resources/ThirdParty/"
cp LICENSE THIRD_PARTY.md "$app/Contents/Resources/ThirdParty/"
cp scripts/Info.plist "$app/Contents/Info.plist"
swiftc scripts/Icon.swift -o .build/mafus-icon
.build/mafus-icon .build/icon.png
iconset=".build/Mafus.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" .build/icon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" .build/icon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 scripts/make-icon.py "$iconset" "$app/Contents/Resources/Mafus.icns"
/usr/bin/codesign --force --sign - "$app/Contents/MacOS/mafus-core"
/usr/bin/codesign --force --sign - "$app"
print "Built: $PWD/$app"
