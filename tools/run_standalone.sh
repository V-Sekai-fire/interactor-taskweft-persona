#!/bin/sh
# Run persona.elf standalone: no viewer, no scene. A headless entities-godot host
# loads the godot-sandbox extension and libriscv emulates the guest, so
# Sandbox.vmcall reaches persona_version and persona_ask directly.
#
#   GODOT=<entities-godot editor binary, double> \
#   SANDBOX_ADDON=<dir holding godot-riscv.gdextension and bin/> \
#   tools/run_standalone.sh <persona.elf> [goal]
#
# SPDX-License-Identifier: MIT
set -eu
elf=${1:?usage: run_standalone.sh <persona.elf> [goal]}
: "${GODOT:?set GODOT to the entities-godot editor binary}"
: "${SANDBOX_ADDON:?set SANDBOX_ADDON to the godot_sandbox addon dir (has bin/godot-riscv.gdextension)}"
here=$(cd "$(dirname "$0")" && pwd)
proj=$(mktemp -d)
trap 'rm -rf "$proj"' EXIT
# A copy, not a symlink: res:// does not follow one, and a second path to the same extension
# registers every Sandbox class twice.
mkdir -p "$proj/addons/godot_sandbox/bin" "$proj/.godot"
cp "$SANDBOX_ADDON/bin/godot-riscv.gdextension" "$proj/addons/godot_sandbox/bin/"
cp -R "$SANDBOX_ADDON"/bin/libgodot_riscv.*.double.* "$proj/addons/godot_sandbox/bin/"
echo 'res://addons/godot_sandbox/bin/godot-riscv.gdextension' > "$proj/.godot/extension_list.cfg"
printf 'config_version=5\n\n[application]\nconfig/name="persona-standalone"\nconfig/features=PackedStringArray("4.4", "Double Precision")\n' > "$proj/project.godot"
cp "$elf" "$proj/persona.elf"
cp "$here/run_guest.gd" "$proj/"
"$GODOT" --headless --path "$proj" --import >/dev/null 2>&1 || true
# The run is bounded: a guest that hangs the emulator is a failure, not a wait.
timeout 60 "$GODOT" --headless --path "$proj" -s res://run_guest.gd -- res://persona.elf "${2:-}"
