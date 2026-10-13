#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/vendor .build/tools
if [[ ! -f .build/vendor/pkg-runtime/bin/pkg-config ]]; then
    [[ -d .build/vendor/pkg-config-0.29.2 ]] || tar -xzf vendor/pkg-config-0.29.2.tar.gz -C .build/vendor
    (cd .build/vendor/pkg-config-0.29.2 && ./configure --with-internal-glib --disable-shared --enable-static --prefix="$PWD/../pkg-runtime" && make -j4 CFLAGS='-O2 -Wno-int-conversion' && make install)
fi
if [[ ! -f .build/vendor/ntfs-3g-2026.9.28/Makefile ]]; then
    tar -xzf vendor/ntfs-3g_ntfsprogs-2026.9.28.tgz -C .build/vendor
    (cd .build/vendor/ntfs-3g-2026.9.28 && ./configure --disable-ntfs-3g --disable-shared --enable-static --disable-crypto --without-uuid PKG_CONFIG="$PWD/../pkg-runtime/bin/pkg-config" CFLAGS='-O2 -mmacosx-version-min=14.0')
fi
(cd .build/vendor/ntfs-3g-2026.9.28 && make -s -j4)
cc -O2 -mmacosx-version-min=14.0 -DHAVE_CONFIG_H -I .build/vendor/ntfs-3g-2026.9.28 -I .build/vendor/ntfs-3g-2026.9.28/include scripts/ntfs-populate.c .build/vendor/ntfs-3g-2026.9.28/libntfs-3g/.libs/libntfs-3g.a -framework CoreFoundation -o .build/tools/ntfs-populate
cp .build/vendor/ntfs-3g-2026.9.28/ntfsprogs/mkntfs .build/tools/
if [[ ! -f .build/vendor/xorriso-1.5.8/Makefile ]]; then
    tar -xzf vendor/xorriso-1.5.8.pl02.tar.gz -C .build/vendor
    (cd .build/vendor/xorriso-1.5.8 && ./configure --disable-shared --enable-static --disable-libreadline --disable-libbz2 --disable-libacl --disable-xattr CFLAGS='-O2 -mmacosx-version-min=14.0')
fi
(cd .build/vendor/xorriso-1.5.8 && make -s -j4)
cp .build/vendor/xorriso-1.5.8/xorriso/xorriso .build/tools/
if [[ ! -f .build/vendor/e2fsprogs-1.47.3/Makefile ]]; then
    tar -xzf vendor/e2fsprogs-1.47.3.tar.gz -C .build/vendor
    (cd .build/vendor/e2fsprogs-1.47.3 && ./configure --disable-nls --disable-fuse2fs --disable-uuidd --disable-shared --enable-elf-shlibs=no CFLAGS='-O2 -mmacosx-version-min=14.0')
fi
(cd .build/vendor/e2fsprogs-1.47.3 && make -s -j4)
cp .build/vendor/e2fsprogs-1.47.3/misc/mke2fs .build/tools/
cp .build/vendor/e2fsprogs-1.47.3/debugfs/debugfs .build/tools/
cp .build/vendor/e2fsprogs-1.47.3/e2fsck/e2fsck .build/tools/
cp .build/vendor/e2fsprogs-1.47.3/misc/mke2fs.conf vendor/mke2fs.conf
python3 scripts/boot-resources.py
