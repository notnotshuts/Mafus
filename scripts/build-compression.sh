#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/vendor
if [[ ! -f .build/vendor/xz-5.8.4/Makefile ]]; then
    tar -xzf vendor/xz-5.8.4.tar.gz -C .build/vendor
    (cd .build/vendor/xz-5.8.4 && ./configure --disable-shared --enable-static --disable-nls --disable-xzdec --disable-lzmadec --disable-lzmainfo CFLAGS='-O2 -mmacosx-version-min=14.0')
fi
(cd .build/vendor/xz-5.8.4 && make -s -j4)
if [[ ! -f .build/vendor/zstd-1.5.7/programs/Makefile ]]; then tar -xzf vendor/zstd-1.5.7.tar.gz -C .build/vendor; fi
(cd .build/vendor/zstd-1.5.7/programs && make -j4 zstd-release HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 CFLAGS='-O2 -mmacosx-version-min=14.0')
