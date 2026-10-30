#!/usr/bin/env python3
"""persona.elf: the guest a double-precision viewer loads, carrying the persona's Lean.

    python3 tools/check_elf.py <persona.elf>

Exit 0 and print OK when the file is a static riscv64 Linux executable, its
`.sandbox_variant` names the 40-byte Variant a double engine reads, and its symbol
table carries the two Lean exports the guest's surface is built on. The guest
registers `persona_version` and `persona_ask` with the host at load through
sandbox_api, so those names are not in the symbol table; the engine check
(tools/persona_check.gd in the viewer) is what proves them.

The guest workflow plants a single-precision marker and requires this check to
fail on it.
"""

import sys

MARKER = b"SBXV(\x00\x00\x00"  # SBXV, then 40 as a little-endian u32
SINGLE = b"SBXV\x18\x00\x00\x00"  # 24, which a double engine refuses at load
SYMBOLS = (b"persona_ask_json\x00", b"persona_version_text\x00")
ET_EXEC = 2
EM_RISCV = 0xF3


def problems(path):
    blob = open(path, "rb").read()
    bad = []
    if blob[:4] != b"\x7fELF":
        bad.append("not an ELF")
        return bad
    if blob[4] != 2:
        bad.append("not 64-bit")
    if blob[5] != 1:
        bad.append("not little-endian")
    if int.from_bytes(blob[16:18], "little") != ET_EXEC:
        bad.append("not a static executable")
    if int.from_bytes(blob[18:20], "little") != EM_RISCV:
        bad.append("not RISC-V")
    if MARKER not in blob:
        bad.append("no 40-byte Variant in .sandbox_variant")
    if SINGLE in blob:
        bad.append("a 24-byte Variant marker is present")
    for symbol in SYMBOLS:
        if symbol not in blob:
            bad.append(f"no {symbol[:-1].decode()} in .symtab")
    return bad


def main(argv):
    if len(argv) != 2:
        print("usage: check_elf.py <persona.elf>")
        return 2
    bad = problems(argv[1])
    for problem in bad:
        print(f"FAIL {problem}")
    if bad:
        return 1
    print(f"OK {argv[1]} is a double-precision riscv64 persona guest")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
