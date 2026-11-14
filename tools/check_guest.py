#!/usr/bin/env python3
"""persona.elf loaded in a pinned double-precision Godot with the godot-sandbox addon, and called.

    python3 tools/check_guest.py --elf=<persona.elf> [--work=<dir>]

The engine and the addon are release binaries from service-godot-build, pinned by tag and
sha256. tests/guest/gate_guest.gd loads the ELF from bytes into a Sandbox, calls
persona_version() and persona_ask() on three goals, and prints one "key value" line each.
This script compares those lines with the answers below. Every check has a control that must
fail.

The host random source cannot be seeded. The Lean runtime in the guest asks for random bytes
with getrandom (syscall 278), and libriscv answers it from the host's own entropy; the Sandbox
API has no hook for it. So the gate runs the guest in two separate Godot processes, each with
fresh entropy, and requires the two answers to be the same, byte for byte, and to equal the
expected plan.

Exit 0 when every check passes.
"""

import hashlib
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "tests/guest"
GODOT_BUILD = "https://github.com/V-Sekai-fire/service-godot-build/releases/download"
ENGINE = {
    "linux": ("v20260930-double.1", "godot.linuxbsd.editor.double.x86_64",
              "37c6962fcc76d1773a596440f310f52ad5cf18011e74a712a5b465c3240e919b"),
    "macos": ("v20260930-double.1", "godot.macos.editor.double.arm64",
              "5f6f2df33708d8f522e0cb5f40af58bd44c1eccb2dda7128081f4056b1de8dce"),
}
ADDON = {
    "linux": ("v20261019-addon.1", "libgodot_riscv.linux.template_release.double.x86_64.so",
              "8ab42de8462452e22bc091af0aedf2446934d8ee691adcd1bbccb9818642aed6"),
    "macos": ("v20261019-addon.1", "libgodot_riscv.macos.template_release.double.universal",
              "14f542887f322bbe9847fa0f24734a46d68458db366f139118b45fc8eb7479f0"),
}
WALL_S = 120

# The answers of Persona/Guest.lean. Change them together with that file.
VERSION = "0.1.0"
PLAN = ('{"goal":"delivered","plan":["recharge","move_to_storage","pickup","move_to_shipping",'
        '"dropoff"],"reached":true}')
REFUSAL = '{"refused":"undeclared_goal"}'
ANSWERS = ("version", "ask_delivered", "ask_default", "ask_undeclared")


def say(s):
    print(s, flush=True)


def fail(why):
    say(f"FAIL {why}")
    sys.exit(1)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def host():
    s, m = platform.system(), platform.machine()
    if s == "Linux" and m == "x86_64":
        return "linux"
    if s == "Darwin":
        return "macos"
    fail(f"no pinned double engine and addon for {s} {m}")


def fetch(tag, name, sha, cache):
    path = cache / name
    if not (path.exists() and sha256(path) == sha):
        cache.mkdir(parents=True, exist_ok=True)
        part = path.with_name(name + ".part")
        url = f"{GODOT_BUILD}/{tag}/{name}"
        say(f"$ curl {url}")
        r = subprocess.run(["curl", "-fsSL", "--retry", "3", "-o", str(part), url],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fail(f"curl exited {r.returncode}: {r.stderr}")
        got = sha256(part)
        if got != sha:
            fail(f"{name}: sha256 {got}, pinned {sha}")
        part.rename(path)
    say(f"{name}: sha256 {sha}")
    return path


def setup(h, work):
    cache = work / "cache"
    engine = fetch(*ENGINE[h], cache)
    engine.chmod(0o755)
    addon = fetch(*ADDON[h], cache)
    shutil.copyfile(addon, PROJECT / "addons/godot_sandbox/bin" / addon.name)
    (PROJECT / ".godot").mkdir(exist_ok=True)
    (PROJECT / ".godot/extension_list.cfg").write_text(
        "res://addons/godot_sandbox/bin/godot-riscv.gdextension\n")
    return engine


def godot(engine, elf):
    """One Godot process, under a wall clock. A guest that hangs the emulator is a failure."""
    cmd = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(PROJECT),
           "--script", "gate_guest.gd", "--", f"--elf={elf}"]
    say("$ " + " ".join(cmd))
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=WALL_S)
        out, rc = r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired as e:
        out, rc = (e.stdout or b"").decode(errors="replace") + "\nFAIL past the wall clock\n", 124
    lines = {}
    for line in out.splitlines():
        k, _, v = line.strip().partition(" ")
        lines.setdefault(k, v)
    lines["rc"] = rc
    lines["out"] = out
    return lines


def loaded(r):
    if r["rc"] != 0:
        return f"godot exited {r['rc']}: {r.get('FAIL', 'no FAIL line')}"
    if r.get("loaded") != "yes":
        return "no loaded line"
    return None


def answers(r, version, plan, refusal):
    """The guest's answers against the expected ones; None when every one matches."""
    bad = loaded(r)
    if bad:
        return bad
    want = {"version": version, "ask_delivered": plan, "ask_default": plan,
            "ask_undeclared": refusal}
    for k, v in want.items():
        if r.get(k) != v:
            return f"{k} is {r.get(k)!r}, not {v!r}"
    if r.get("exceptions") != "0":
        return f"the Sandbox counted {r.get('exceptions')} guest exceptions"
    return None


def same(a, b):
    for k in ANSWERS:
        if a.get(k) is None or a.get(k) != b.get(k):
            return f"{k}: {a.get(k)!r} and {b.get(k)!r}"
    return None


def check(results, name, problem):
    results.append(problem is None)
    say(("ok   " if problem is None else "FAIL ") + name + ("" if problem is None else f": {problem}"))


def control(results, name, problem):
    """A control passes when the check it runs refuses."""
    check(results, "control: " + name, "accepted" if problem is None else None)
    if problem is not None:
        say(f"       refused: {problem}")


def main(argv):
    kv = dict(a.removeprefix("--").partition("=")[::2] for a in argv[1:])
    if "elf" not in kv:
        fail("usage: check_guest.py --elf=<persona.elf> [--work=<dir>]")
    elf = Path(kv["elf"]).resolve()
    if not elf.is_file():
        fail(f"no {elf}")
    work = Path(kv.get("work") or ROOT / "build/guest").resolve()
    work.mkdir(parents=True, exist_ok=True)
    engine = setup(host(), work)
    say(f"persona.elf: sha256 {sha256(elf)}")

    first = godot(engine, elf)
    second = godot(engine, elf)
    (work / "godot.log").write_text(first["out"])
    blob = elf.read_bytes()
    truncated = work / "truncated.elf"
    truncated.write_bytes(blob[: len(blob) // 2])
    cut = godot(engine, truncated)
    (work / "truncated.log").write_text(cut["out"])

    results = []
    check(results, "persona.elf loads, with persona_version and persona_ask", loaded(first))
    check(results, f"persona_version() is {VERSION}, persona_ask() answers the plan and the refusal, "
          "and the guest raised no exception",
          answers(first, VERSION, PLAN, REFUSAL))
    check(results, "a second process, with fresh host entropy, answers the same bytes", same(first, second))
    control(results, "an ELF cut in half does not load", loaded(cut))
    control(results, "the undeclared goal's answer is not taken for the plan",
            answers(first, VERSION, first.get("ask_undeclared"), REFUSAL))
    control(results, "a plan with one step dropped is refused",
            answers(first, VERSION, PLAN.replace('"pickup",', ""), REFUSAL))
    control(results, "another version is refused", answers(first, "0.0.0", PLAN, REFUSAL))
    failed = results.count(False)
    say(f"{len(results) - failed} of {len(results)} checks pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
