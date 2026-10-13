#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/vendor
if [[ ! -f .build/vendor/wimlib-1.14.4/Makefile ]]; then
    tar -xzf vendor/wimlib-1.14.4.tar.gz -C .build/vendor
    (cd .build/vendor/wimlib-1.14.4 && ./configure --without-ntfs-3g --without-fuse --disable-shared --enable-static CFLAGS='-O2 -mmacosx-version-min=14.0')
fi
(cd .build/vendor/wimlib-1.14.4 && make -j4)
