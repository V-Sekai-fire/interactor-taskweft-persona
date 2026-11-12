# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Writes the command-battle domain and its round problems, and simulates the same rules
# independently so a check can compare plans step for step.
#   python tools/command_battle.py write        writes domains/ and problems/
#   python tools/command_battle.py simulate N   prints the expected play-out of round N as JSON
import json, sys, os

CTX = {"VSEKAI": "https://v-sekai.org/", "domain": "VSEKAI:planning/domain/"}
LEAD_MAX, CASTER_MAX = 300, 200
ATTACK, SKILL, FINISHER = 45, 110, 220
C_ATTACK, RELEASE = 25, 130
GAUGE_STEP, GAUGE_FULL, SKILL_COST, SKILL_REACH, CAST_FLOOR = 25, 100, 50, 110, 130


def foe_for(round_):
    return 260 + 20 * (round_ - 1), 40 + 2 * (round_ - 1)


class Graph:
    def __init__(self):
        self.decl, self.nodes, self.vars, self.outs = [], [{"declaration": 0}], [], []
        self.decl.append({"op": "event/onStart"})

    def op(self, name):
        for i, d in enumerate(self.decl):
            if d["op"] == name:
                return i
        self.decl.append({"op": name})
        return len(self.decl) - 1

    def add(self, node):
        self.nodes.append(node)
        return {"node": len(self.nodes) - 1, "socket": "value"}

    def ptr(self, p):
        return self.add({"declaration": self.op("pointer/get"),
                         "configuration": {"pointer": {"value": [p]}, "type": {"value": [0]}}})

    def bin(self, o, a, b):
        return self.add({"declaration": self.op(o), "values": {"a": a, "b": b}})

    def sel(self, c, a, b):
        return self.add({"declaration": self.op("math/select"), "values": {"condition": c, "a": a, "b": b}})

    def out(self, name, ref):
        self.vars.append({"id": name, "type": 0, "value": [0]})
        self.outs.append(ref)

    def json(self):
        setter = {"declaration": self.op("variable/set"),
                  "configuration": {"variables": {"value": list(range(len(self.vars)))}},
                  "values": {str(i): r for i, r in enumerate(self.outs)}}
        self.nodes.append(setter)
        self.nodes[0]["flows"] = {"out": {"node": len(self.nodes) - 1, "socket": "in"}}
        return {"types": [{"signature": "int"}, {"signature": "bool"}], "variables": self.vars,
                "declarations": self.decl, "nodes": self.nodes}


def n(v):
    return {"type": 0, "value": [v]}


def get(p):
    return {"type": "pointer/get", "pointer": p}


def eq(p, v):
    return {"eval": {"type": "math/eq", "a": get(p), "b": v}}


def ge(p, v):
    return {"eval": {"type": "math/ge", "a": get(p), "b": v}}


def put(p, v):
    return {"pointer/set": p, "value": v}


def par(x):
    return {"param": x}


def hit(g, amount):
    return g.bin("math/max", g.bin("math/sub", g.ptr("/foe/hp"), n(amount)), n(0))


def domain():
    acts, methods = {}, {}

    def act(name, params, pre, sets, desc):
        acts[name] = {"params": params, "description": desc, "body": pre + [put(p, v) for p, v in sets]}

    def alt(name, check, subtasks, graph=None):
        a = {"name": name, "check": check, "subtasks": subtasks}
        if graph is not None:
            a["graph"] = graph
        return a

    lead_turn = [eq("/turn/slot", 0), ge("/lead/hp", 1), ge("/foe/hp", 1)]
    caster_turn = [eq("/turn/slot", 1), ge("/caster/hp", 1), ge("/foe/hp", 1)]
    act("lead-attack", ["h", "g"], lead_turn, [("/foe/hp", par("h")), ("/lead/gauge", par("g")), ("/turn/slot", 1)],
        f"The lead attacks: {ATTACK} damage, +{GAUGE_STEP} gauge.")
    act("lead-skill", ["h", "g"], lead_turn + [ge("/lead/gauge", SKILL_COST)],
        [("/foe/hp", par("h")), ("/lead/gauge", par("g")), ("/turn/slot", 1)],
        f"The lead uses a skill: {SKILL} damage for {SKILL_COST} gauge, on the same turn.")
    act("lead-finisher", ["h"], lead_turn + [ge("/lead/gauge", GAUGE_FULL)],
        [("/foe/hp", par("h")), ("/lead/gauge", 0), ("/turn/slot", 1)],
        f"The lead's finisher: needs a full gauge, empties it, {FINISHER} damage.")
    act("caster-attack", ["h"], caster_turn + [eq("/caster/charge", 0)], [("/foe/hp", par("h")), ("/turn/slot", 2)],
        f"The caster attacks: {C_ATTACK} damage.")
    act("caster-cast", [], caster_turn + [eq("/caster/charge", 0)], [("/caster/charge", 1), ("/turn/slot", 2)],
        "The caster begins a spell; it lands on the caster's next turn.")
    act("caster-release", ["h"], caster_turn + [eq("/caster/charge", 1)],
        [("/foe/hp", par("h")), ("/caster/charge", 0), ("/turn/slot", 2)], f"The caster releases the spell: {RELEASE} damage.")
    act("foe-strike-lead", ["h"], [eq("/turn/slot", 2), ge("/foe/hp", 1), ge("/lead/hp", 1)],
        [("/lead/hp", par("h")), ("/turn/slot", 0)], "The foe strikes the lead.")
    act("foe-strike-caster", ["h"], [eq("/turn/slot", 2), ge("/foe/hp", 1), eq("/lead/hp", 0), ge("/caster/hp", 1)],
        [("/caster/hp", par("h")), ("/turn/slot", 0)], "The foe strikes the caster, once the lead is down.")
    act("skip-lead", [], [eq("/turn/slot", 0), eq("/lead/hp", 0)], [("/turn/slot", 1)], "A fallen lead loses the turn.")
    act("skip-caster", [], [eq("/turn/slot", 1), eq("/caster/hp", 0)], [("/turn/slot", 2)], "A fallen caster loses the turn.")
    act("victory", [], [eq("/foe/hp", 0)], [("/result/won", 1)], "The foe is down: the round is won.")
    act("defeat", [], [eq("/lead/hp", 0), eq("/caster/hp", 0)], [("/result/lost", 1)], "The party is down: the run ends.")

    def cmd(name, check, action, outs):
        g = Graph()
        for k, ref in outs(g):
            g.out(k, ref)
        methods[name] = {"params": [], "alternatives": [alt("go", check, [[action] + [par(k) for k, _ in outs(Graph())]], g.json())]}

    cmd("cmd-lead-attack", lead_turn, "lead-attack",
        lambda g: [("h", hit(g, ATTACK)), ("g", g.bin("math/min", g.bin("math/add", g.ptr("/lead/gauge"), n(GAUGE_STEP)), n(GAUGE_FULL)))])
    cmd("cmd-lead-skill", lead_turn + [ge("/lead/gauge", SKILL_COST)], "lead-skill",
        lambda g: [("h", hit(g, SKILL)), ("g", g.bin("math/sub", g.ptr("/lead/gauge"), n(SKILL_COST)))])
    cmd("cmd-lead-finisher", lead_turn + [ge("/lead/gauge", GAUGE_FULL)], "lead-finisher", lambda g: [("h", hit(g, FINISHER))])
    cmd("cmd-caster-attack", caster_turn + [eq("/caster/charge", 0)], "caster-attack", lambda g: [("h", hit(g, C_ATTACK))])
    methods["cmd-caster-cast"] = {"params": [], "alternatives": [alt("go", caster_turn + [eq("/caster/charge", 0)], [["caster-cast"]])]}
    cmd("cmd-caster-release", caster_turn + [eq("/caster/charge", 1)], "caster-release", lambda g: [("h", hit(g, RELEASE))])

    def foe_hit(g, who):
        return g.bin("math/max", g.bin("math/sub", g.ptr(f"/{who}/hp"), g.ptr("/foe/atk")), n(0))

    gl, gc = Graph(), Graph()
    gl.out("h", foe_hit(gl, "lead"))
    gc.out("h", foe_hit(gc, "caster"))
    methods["foe-turn"] = {"params": [], "alternatives": [
        alt("lead", [eq("/turn/slot", 2), ge("/foe/hp", 1), ge("/lead/hp", 1)], [["foe-strike-lead", par("h")]], gl.json()),
        alt("caster", [eq("/turn/slot", 2), ge("/foe/hp", 1), eq("/lead/hp", 0), ge("/caster/hp", 1)],
            [["foe-strike-caster", par("h")]], gc.json())]}

    def driver(name, mine):
        methods[name] = {"params": [], "alternatives": [
            alt("foe-down", [eq("/foe/hp", 0)], [["victory"]] if mine == "end" else []),
            alt("party-down", [eq("/lead/hp", 0), eq("/caster/hp", 0)], [["defeat"]] if mine == "end" else []),
            alt("foe", [eq("/turn/slot", 2)], [["foe-turn"], [name]]),
            alt("lead-down", [eq("/turn/slot", 0), eq("/lead/hp", 0)], [["skip-lead"], [name]]),
            alt("caster-down", [eq("/turn/slot", 1), eq("/caster/hp", 0)], [["skip-caster"], [name]]),
        ] + ([alt("lead", [eq("/turn/slot", 0)], [["lead-policy"], [name]]),
              alt("caster", [eq("/turn/slot", 1)], [["caster-policy"], [name]])] if mine == "end"
             else [alt("party-to-move", [], [])])}

    driver("respond", "wait")
    driver("play-out", "end")

    gs = Graph()
    gs.out("near", gs.sel(gs.bin("math/le", gs.ptr("/foe/hp"), n(SKILL_REACH)), n(1), n(0)))
    methods["lead-policy"] = {"params": [], "alternatives": [
        alt("finisher", [ge("/lead/gauge", GAUGE_FULL)], [["cmd-lead-finisher"]]),
        alt("skill", [ge("/lead/gauge", SKILL_COST), ge("/graph/near", 1)], [["cmd-lead-skill"]], gs.json()),
        alt("attack", [], [["cmd-lead-attack"]])]}
    methods["caster-policy"] = {"params": [], "alternatives": [
        alt("release", [eq("/caster/charge", 1)], [["cmd-caster-release"]]),
        alt("cast", [eq("/caster/charge", 0), ge("/foe/hp", CAST_FLOOR)], [["cmd-caster-cast"]]),
        alt("attack", [], [["cmd-caster-attack"]])]}

    return {"@context": CTX, "@type": "domain:Definition", "name": "command_battle", "source": "interactor-taskweft-persona",
            "version": "0.2.0",
            "description": ("A turn-based command battle. A lead and a caster act in a fixed turn order, then the foe. "
                            "Attacks build a gauge; a skill spends half of it on the same turn; a full gauge allows a finisher; "
                            "a spell takes a turn to cast. The page plays one round at a time: 30 rounds for a normal run, 60 for plus."),
            "variables": [{"name": v, "type": "int", "init": {}} for v in ("lead", "caster", "foe", "turn", "result")],
            "actions": acts, "methods": methods}


def state_for(round_, gauge=0):
    hp, atk = foe_for(round_)
    return {"lead": {"hp": LEAD_MAX, "max": LEAD_MAX, "gauge": gauge}, "caster": {"hp": CASTER_MAX, "max": CASTER_MAX, "charge": 0},
            "foe": {"hp": hp, "max": hp, "atk": atk}, "turn": {"slot": 0}, "result": {"won": 0, "lost": 0}}


def problem(round_, todo):
    s = state_for(round_)
    return {"@context": CTX, "@type": "domain:Problem", "name": f"command_battle_round_{round_}", "domain": "command_battle",
            "source": "interactor-taskweft-persona", "version": "0.2.0",
            "description": f"Round {round_}: a fresh party against the round's foe. The persona plays the whole round.",
            "variables": [{"name": k, "type": "int", "init": v} for k, v in s.items()], "todo_list": todo}


def simulate(round_, gauge=0):
    s = state_for(round_, gauge)
    L, C, F, T = s["lead"], s["caster"], s["foe"], s["turn"]
    steps = []
    for _ in range(10000):
        if F["hp"] == 0:
            steps.append(["victory", []]); return steps, "victory", s
        if L["hp"] == 0 and C["hp"] == 0:
            steps.append(["defeat", []]); return steps, "defeat", s
        if T["slot"] == 2:
            if L["hp"] >= 1:
                L["hp"] = max(L["hp"] - F["atk"], 0); steps.append(["foe-strike-lead", [L["hp"]]])
            else:
                C["hp"] = max(C["hp"] - F["atk"], 0); steps.append(["foe-strike-caster", [C["hp"]]])
            T["slot"] = 0
        elif T["slot"] == 0 and L["hp"] == 0:
            steps.append(["skip-lead", []]); T["slot"] = 1
        elif T["slot"] == 1 and C["hp"] == 0:
            steps.append(["skip-caster", []]); T["slot"] = 2
        elif T["slot"] == 0:
            if L["gauge"] >= GAUGE_FULL:
                F["hp"] = max(F["hp"] - FINISHER, 0); L["gauge"] = 0; steps.append(["lead-finisher", [F["hp"]]])
            elif L["gauge"] >= SKILL_COST and F["hp"] <= SKILL_REACH:
                F["hp"] = max(F["hp"] - SKILL, 0); L["gauge"] -= SKILL_COST; steps.append(["lead-skill", [F["hp"], L["gauge"]]])
            else:
                F["hp"] = max(F["hp"] - ATTACK, 0); L["gauge"] = min(L["gauge"] + GAUGE_STEP, GAUGE_FULL)
                steps.append(["lead-attack", [F["hp"], L["gauge"]]])
            T["slot"] = 1
        else:
            if C["charge"] == 1:
                F["hp"] = max(F["hp"] - RELEASE, 0); C["charge"] = 0; steps.append(["caster-release", [F["hp"]]])
            elif F["hp"] >= CAST_FLOOR:
                C["charge"] = 1; steps.append(["caster-cast", []])
            else:
                F["hp"] = max(F["hp"] - C_ATTACK, 0); steps.append(["caster-attack", [F["hp"]]])
            T["slot"] = 2
    raise RuntimeError("simulation did not end")


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(__file__), "..")
    if sys.argv[1] == "write":
        json.dump(domain(), open(os.path.join(root, "domains/command-battle.jsonld"), "w"), indent=1)
        json.dump(problem(1, [["play-out"]]), open(os.path.join(root, "problems/command-battle-round-1.jsonld"), "w"), indent=1)
        print("wrote domains/command-battle.jsonld and problems/command-battle-round-1.jsonld")
    elif sys.argv[1] == "expected":
        out = {}
        for r in range(1, int(sys.argv[2]) + 1):
            st, res, _ = simulate(r)
            out[r] = {"result": res, "steps": st, "problem": problem(r, [["play-out"]])}
        print(json.dumps(out))
