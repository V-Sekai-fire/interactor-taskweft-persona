#!/usr/bin/env python3
"""Lean is the oracle: every domain/problem pair under tests/ (and the campus and
battle samples), plus 300 generated needs-graphs with durations, stated starts and
ends and origins, goes through `persona_plan` (Lean) and `build/plan` (Mojo). The plan
documents must be identical, byte for byte, refusals included."""
import glob, json, os, random, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LEAN = os.path.join(ROOT, ".lake/build/bin/persona_plan")
MOJO = os.environ.get("PLAN_MOJO", os.path.join(ROOT, "mojo/build/plan"))

pairs = []
for dom in sorted(glob.glob(os.path.join(ROOT, "tests/**/domain.jsonld"), recursive=True)):
    d = os.path.dirname(dom)
    for prob in sorted(glob.glob(os.path.join(d, "*.problem.jsonld"))):
        pairs.append((dom, prob))
pairs += [(os.path.join(ROOT, "domains/campus-sample.jsonld"), os.path.join(ROOT, "problems/campus-sample.jsonld")),
          (os.path.join(ROOT, "domains/campus-sample-reach.jsonld"), os.path.join(ROOT, "problems/campus-sample-reach.jsonld")),
          (os.path.join(ROOT, "domains/command-battle.jsonld"), os.path.join(ROOT, "problems/command-battle-start.jsonld"))]

rng = random.Random(20261114)
tmp = tempfile.mkdtemp(prefix="pplan.")
DURS = ["P1D", "PT2H", "P2DT3H", "PT90M", "P1W", "PT1.5H", "PT30S", "P1DT", "X", "PT0S"]
for k in range(300):
    n = rng.randint(1, 7)
    acts, ms, init = {}, {}, {}
    for i in range(n):
        needs = [rng.randrange(n) for _ in range(rng.randint(0, 2))]
        body = [{"eval": {"type": "math/ge", "a": {"type": "pointer/get", "pointer": f"/s/{j}"}, "b": 1}} for j in needs]
        body.append({"pointer/set": f"/s/{i}", "value": 1})
        a = {"body": body}
        if rng.random() < .7: a["duration"] = rng.choice(DURS)
        if rng.random() < .2: a["start"] = "2026-11-0%dT00:00:00Z" % rng.randint(1, 9)
        if rng.random() < .15: a["end"] = "2026-11-%02dT00:00:00Z" % rng.randint(1, 20)
        acts[f"a{i}"] = a
        ms[f"/s/{i}"] = {"alternatives": [{"name": "do", "subtasks": [["goal", f"/s/{j}"] for j in needs] + [[f"a{i}"]]}]}
        init[str(i)] = int(rng.random() < .25)
    dom = {"name": "dag", "variables": [], "actions": acts, "methods": ms}
    prob = {"name": "dag_problem", "variables": [{"name": "s", "init": init}],
            "todo_list": [{"goal": [{"pointer": f"/s/{rng.randrange(n + (1 if rng.random() < .1 else 0))}", "eq": 1}]}]}
    if rng.random() < .5: prob["origin"] = rng.choice(["2026-11-02T00:00:00Z", "2026-13-40T00:00:00Z", ""])
    dp, pp = os.path.join(tmp, f"d{k}.jsonld"), os.path.join(tmp, f"p{k}.jsonld")
    json.dump(dom, open(dp, "w")); json.dump(prob, open(pp, "w"))
    pairs.append((dp, pp))

bad = 0; kinds = {}
for dom, prob in pairs:
    a = subprocess.run([LEAN, dom, prob], capture_output=True, text=True)
    b = subprocess.run([MOJO, dom, prob], capture_output=True, text=True)
    k = "refused" if '"refused"' in a.stdout else ("temporal" if '"start"' in a.stdout else ("plan" if '"steps"' in a.stdout else "other"))
    kinds[k] = kinds.get(k, 0) + 1
    if a.stdout != b.stdout or b.returncode != 0:
        bad += 1
        print("DIFF", os.path.relpath(prob, ROOT)); print("  lean:", a.stdout[:300]); print("  mojo:", (b.stdout or b.stderr)[:300])
print(f"{len(pairs)} pairs, {bad} differ; mix {kinds}")
sys.exit(1 if bad else 0)
