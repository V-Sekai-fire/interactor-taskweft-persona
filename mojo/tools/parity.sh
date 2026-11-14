#!/usr/bin/env bash
# Lean is the oracle: the same hex-encoded grid specs go through Persona.Grid.planOf
# and through the Mojo port, and the answers must match line for line.
# Usage: tools/parity.sh [mojo-src-dir]   (default: src)
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="${1:-src}"
export ELAN_TOOLCHAIN="${ELAN_TOOLCHAIN:-leanprover/lean4:v4.34.1}"
T="$(mktemp -d "${TMPDIR:-/tmp}/parity.XXXXXX")"
python3 parity/gen_cases.py > "$T/cases.hex"
pixi run mojo build -I "$SRC" app/grid_dump.mojo -o "$T/grid_dump"
"$T/grid_dump" "$T/cases.hex" > "$T/mojo.out"
(cd .. && lake env lean --run mojo/parity/GridOracle.lean "$T/cases.hex") > "$T/lean.out"
n=$(wc -l < "$T/lean.out")
[ "$n" -gt 1000 ] || { echo "oracle gave only $n lines"; exit 2; }
if diff "$T/lean.out" "$T/mojo.out" > "$T/diff"; then
  echo "OK: $n grid specs, Lean and Mojo agree line for line"
  sort "$T/lean.out" | cut -c1-22 | uniq -c | sort -rn | head -5
else
  echo "FAIL: Lean and Mojo differ on $(grep -c '^<' "$T/diff") of $n specs"; head -6 "$T/diff"; exit 1
fi
