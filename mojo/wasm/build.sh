#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# persona.elf (the Mojo guest) as WebAssembly under libriscv, with binary translation.
#
#   build.sh <libriscv-checkout> <out-dir> [module|cli] [regcache ON|OFF (OFF)] [translated-C flags (-O1)]
#   NBIT=OFF turns off the power-of-two address mask (on).
#
# The translation is emitted by running the module's own code under node, because the hash of a
# translation covers the layout of libriscv's Machine, and that layout is the wasm32 one. C99
# emitted by a 64-bit host never matches. Needs emcc (Python 3.10 or newer: set EMSDK_PYTHON),
# cmake, ninja, node, xxd, and mojo/guest/build/persona.elf.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rv="$(cd "${1:?libriscv checkout}" && pwd)"
out="$(mkdir -p "${2:?out dir}" && cd "$2" && pwd)"
target="${3:-module}"
regcache="${4:-OFF}"
bopt="${5:--O1}"
elf="${ELF:-$here/../guest/build/persona.elf}"

mkdir -p "$out/src"
xxd -i < "$elf" > "$out/src/persona_elf.inc"
cflags="-fexceptions -include cstdlib -I$out/src -O3"

configure() {   # <build-dir> <target> <bintr-dir or empty>
  CXXFLAGS="$cflags" emcmake cmake -S "$here" -B "$1" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DLIBRISCV_DIR="$rv" -DPERSONA_TARGET="$2" -DBINTR_DIR="$3" -DPERSONA_REGCACHE="$regcache" \
    -DBINTR_OPT="$bopt" -DPERSONA_NBIT="${NBIT:-ON}" >/dev/null
}

# 1. The same module without the translation, as a command line tool: it emits the C99.
configure "$out/gen" cli ""
ninja -C "$out/gen"
mkdir -p "$out/bintr"
node "$out/gen/persona_cli.js" --gen "$out/bintr/persona_bintr.c"

# 2. The module with it compiled in.
configure "$out/final" "$target" "$out/bintr"
ninja -C "$out/final"
ls -la "$out/final" | grep -E "persona\.(mjs|wasm)|persona_cli"
