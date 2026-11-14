#!/usr/bin/env python3
"""Plant one bug at a time in the JSON-LD planner, KHR runner and time codecs.
A mutant must build, then be caught by at least one of: test_jsonld (the file-driven
and inline invariants), test_jsonld_props (witness ladder), or the Lean parity run."""
import os, shutil, subprocess, sys, tempfile
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ROOT)
# Not here, on purpose: `head.fuel == 0` -> `< 0` in the call path. Fuel is methods + 1000, so
# reaching it takes a chain a thousand deep; the mutant then expands one more level and
# refuses all the same. No document the tests can write tells it from the original.
MUT = [
 ("timeutil.mojo", "return a - b if a > b else 0", "return a - b", "monus goes negative"),
 ("timeutil.mojo", "return era * 146097 + doe - 719468", "return era * 146096 + doe - 719468", "civil date off a cycle"),
 ("timeutil.mojo", "        return 86400 * 1000\n    if u == 4:", "        return 86401 * 1000\n    if u == 4:", "a day is 86401 seconds"),
 ("timeutil.mojo", "and y >= 1970", "and y > 1970", "1970 is not a year"),
 ("jsonld.mojo", "if len(s.plan) < bound:", "if len(s.plan) <= bound:", "bound one action too loose"),
 ("jsonld.mojo", "if lookup_or0(s.vals, p) >= 1:", "if lookup_or0(s.vals, p) > 1:", "a held goal still planned"),
 ("jsonld.mojo", "if lookup_or0(vals, h.key) < h.val:", "if lookup_or0(vals, h.key) <= h.val:", "a threshold must be exceeded"),
 ("jsonld.mojo", "if dep and se[k] > st:", "if dep and se[k] < st:", "a step starts at the earlier end"),
 ("jsonld.mojo", "fin = min(fin, lb[k])", "fin = max(fin, lb[k])", "latest time not the earliest bound"),
 ("jsonld.mojo", "if len(p.names) > 0 else d.names.copy()", "if len(p.names) >= 0 else d.names.copy()", "problem codebook always replaces"),
 ("jsonld.mojo", "acc = acc.replace(\"[\" + env_k[i] + \"]\"", "acc = acc.replace(\"(\" + env_k[i] + \"]\"", "parameter marker misread"),
 ("jsonld.mojo", "for b in range(max_bound + 1):", "for b in range(max_bound):", "shortest misses its bound"),
 ("jsonld.mojo", "if not expand_alt(doc, sp.vocab, alt0, args, s.vals, tasks):\n            continue", "if not expand_alt(doc, sp.vocab, alt0, args, s.vals, tasks):\n            return False", "a failed alternative ends the search"),
 ("khr.mojo", "var y = x & 0xFFFFFFFF", "var y = x & 0xFFFFFFFFF", "int32 does not wrap"),
 ("khr.mojo", "            if i >= stop:\n                break", "            if i > stop:\n                break", "for runs one pass too many"),
 ("khr.mojo", "    r.fuel -= 1\n    var op = op_of(doc, g, n)\n    if op == \"event/onStart\":", "    var op = op_of(doc, g, n)\n    if op == \"event/onStart\":", "a node costs no fuel"),
 ("khr.mojo", "if a.is_bool != b.is_bool:", "if False:", "mixed types compared"),
 ("jdoc.mojo", "if keys[i] < ks[k]:", "if keys[i] > ks[k]:", "object entries sorted backwards"),
]
def build(src, tag, extra):
    out = os.path.join(src, "b_" + tag)
    r = subprocess.run(["pixi","run","--manifest-path",os.path.join(ROOT,"pixi.toml"),"mojo","build","-I",os.path.join(src,"src"),
        "-I",os.path.join(ROOT,"thirdparty/emberjson"),"-I",os.path.join(ROOT,"thirdparty/emberserde"),
        "-I",os.path.join(ROOT,"thirdparty/witness-mojo/src"),extra,"-o",out],capture_output=True,text=True)
    return out, r
def verdict(src, tag):
    caught = []
    for name, f in [("test_jsonld", "tests/test_jsonld.mojo"), ("props", "tests/test_jsonld_props.mojo"), ("plan", "app/plan.mojo")]:
        out, r = build(src, tag + name, os.path.join(ROOT, f))
        if r.returncode != 0:
            return "build-error", r.stderr[-300:]
        if name == "plan":
            p = subprocess.run([sys.executable, os.path.join(ROOT, "tools/parity_plan.py")], capture_output=True, text=True, env={**os.environ, "PLAN_MOJO": out})
        else:
            p = subprocess.run([out], capture_output=True, text=True, cwd=ROOT)
        if p.returncode != 0:
            caught.append("parity" if name == "plan" else name)
    return ("red" if caught else "pass"), ",".join(caught)
def main():
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        shutil.copytree(os.path.join(ROOT, "src"), os.path.join(tmp, "src"))
        st, why = verdict(tmp, "clean")
        if st != "pass":
            print("clean copy:", st, why); sys.exit(2)
        for i, (f, old, new, label) in enumerate(MUT):
            p = os.path.join(tmp, "src/persona", f); orig = open(p).read()
            if orig.count(old) != 1:
                print(f"PLANT MISSED ({orig.count(old)}): {label}"); bad += 1; continue
            open(p, "w").write(orig.replace(old, new))
            st, why = verdict(tmp, str(i)); open(p, "w").write(orig)
            ok = st == "red"; bad += 0 if ok else 1
            print(("killed   " if ok else "SURVIVED ") + f"[{st}: {why}] {label}", flush=True)
    print("OK: every mutant killed" if bad == 0 else f"FAIL: {bad} not killed"); sys.exit(1 if bad else 0)
main()
