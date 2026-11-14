#!/usr/bin/env python3
"""Deterministic grid specs, valid and malformed, as one hex line each."""
import random, sys
rng = random.Random(20261114)
frags_bad = ["skill", "skill x 1", "skill 1", "goal", "goal x", "goal 1 2", "skill 1_0 1", "skill 007 0 3",
             "skill 1 01", "  skill   2  0   1  ", "bogus line", "skill 1 2", "goal 007", "skill 5 0 5"]
out = []
for _ in range(1500):
    n = rng.randint(0, 7)
    lines = []
    for i in range(n):
        needs = [str(rng.randint(0, n + 2)) for _ in range(rng.randint(0, 3))]
        i_ = rng.choice([i + 1, i + 1, i + 1, rng.randint(1, n + 1)])  # sometimes a duplicate id
        lines.append(" ".join(["skill", str(i_), str(rng.randint(0, 2) if rng.random() < .1 else int(rng.random() < .3))] + needs))
    for _ in range(rng.randint(0, 2)):
        lines.insert(rng.randint(0, len(lines)), rng.choice(frags_bad))
    ngoal = rng.choices([0, 1, 2], [1, 12, 1])[0]
    for _ in range(ngoal):
        lines.insert(rng.randint(0, len(lines)), "goal " + str(rng.randint(0, n + 2)))
    sep = rng.choice(["\n"] * 6 + ["\n\n", " \n"])
    out.append(sep.join(lines))
out += ["", "goal 1", "skill 1 1\ngoal 1", "skill 1 0 2\nskill 2 0 1\ngoal 1", "skill é 1\ngoal 1"]
for s in out:
    print(s.encode().hex() or "-")
