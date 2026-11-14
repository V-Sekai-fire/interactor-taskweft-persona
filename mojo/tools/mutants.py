#!/usr/bin/env python3
"""Plant one bug at a time in the port and require the gate to go red.

Each mutant replaces exactly one occurrence (a miss fails loudly), must still
build, and must make tests/test_persona.mojo exit non-zero. A clean copy must
pass first, so a red run means the bug, not the harness.
"""
import os, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUTANTS = [
    ("core.mojo", "            out.append(acc)\n            acc *= l", "            acc *= l\n            out.append(acc)", "basis off by one stage"),
    ("core.mojo", "if not (code[i] < self.levels[i]):", "if not (code[i] <= self.levels[i]):", "digit at its level held"),
    ("core.mojo", "if len(code) != len(self.levels):", "if len(code) > len(self.levels):", "short code held"),
    ("core.mojo", "ok = q.threshold <= sv.val", "ok = q.threshold < sv.val", "need needs more than its threshold"),
    ("core.mojo", "if _blacklisted(blacklist, a.name):", "if False:", "blacklist ignored"),
    ("core.mojo", "if self.codebook.holds(v.code):", "if True:", "unheld code resolved"),
    ("core.mojo", "if fuel <= 0:", "if fuel < 0:", "one fuel too many"),
    ("core.mojo", "return sv.val == n.threshold", "return sv.val >= n.threshold", "verify_goal is a threshold"),
    ("grid.mojo", 'd.value() == "1"', 'd.value() == "0"', "done flag inverted"),
    ("grid.mojo", "for n in s.needs:", "for n in List[String]():", "needs dropped"),
    ("grid.mojo", "if len(goals) == 1:", "if len(goals) >= 1:", "two goals accepted"),
    ("guest.mojo", 'elif cp == "\\\\":', 'elif cp == "\\\\\\\\":', "backslash not escaped"),
]


def run(src_dir, tag):
    exe = os.path.join(src_dir, "t_" + tag)
    b = subprocess.run(["pixi", "run", "--manifest-path", os.path.join(ROOT, "pixi.toml"), "mojo", "build",
                        "-I", os.path.join(src_dir, "src"),
                        "-I", os.path.join(ROOT, "thirdparty/witness-mojo/src"),
                        os.path.join(ROOT, "tests/test_persona.mojo"), "-o", exe],
                       capture_output=True, text=True)
    if b.returncode != 0:
        return "build-error", b.stderr[-400:]
    r = subprocess.run([exe], capture_output=True, text=True)
    return ("pass" if r.returncode == 0 else "red"), r.stdout[-200:]


def main():
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copytree(os.path.join(ROOT, "src"), os.path.join(tmp, "src"))
        state, _ = run(tmp, "clean")
        if state != "pass":
            print("clean copy does not pass:", state); sys.exit(2)
        for i, (f, old, new, why) in enumerate(MUTANTS):
            path = os.path.join(tmp, "src/persona", f)
            orig = open(path).read()
            if orig.count(old) != 1:
                print(f"PLANT MISSED ({orig.count(old)} hits): {why}"); bad += 1; continue
            open(path, "w").write(orig.replace(old, new))
            state, tail = run(tmp, str(i))
            open(path, "w").write(orig)
            ok = state == "red"
            bad += 0 if ok else 1
            print(("killed   " if ok else "SURVIVED ") + f"[{state}] {why}")
    print("OK: every mutant killed" if bad == 0 else f"FAIL: {bad} mutant(s) not killed")
    sys.exit(1 if bad else 0)


main()
