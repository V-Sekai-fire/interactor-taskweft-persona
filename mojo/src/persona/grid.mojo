# SPDX-License-Identifier: MIT
# Persona/Grid.lean: a skill grid as text in, the activation order out.
# One `skill ID DONE NEED...` line a skill and one `goal ID` line.
#
# A Lean Nat is unbounded, so an id is kept as its canonical decimal text
# (no leading zeros) and compared as text; nothing can overflow.
from persona.core import *
from persona.guest import quote, plan_json


@fieldwise_init
struct Skill(Copyable, Movable):
    var id: String
    var done: Bool
    var needs: List[String]


def words(line: String) -> List[String]:
    var out = List[String]()
    for w in line.split(" "):
        if w.byte_length() > 0:
            out.append(String(w))
    return out^


def to_nat(s: String) -> Optional[String]:
    """Lean's String.toNat?: decimal digits only, as canonical text."""
    var b = s.as_bytes()
    if len(b) == 0:
        return None
    for i in range(len(b)):
        if b[i] < 48 or b[i] > 57:
            return None
    var start = 0
    while start < len(b) - 1 and b[start] == 48:
        start += 1
    return String(s[byte=start:])


def parse(spec: String, mut skills: List[Skill], mut goal: String) -> Bool:
    var lines = List[List[String]]()
    for ln in spec.split("\n"):
        var ws = words(String(ln))
        if len(ws) > 0:
            lines.append(ws^)
    skills = List[Skill]()
    var goals = List[String]()
    for ws in lines:
        if len(ws) >= 3 and ws[0] == "skill":
            var i = to_nat(ws[1])
            var d = to_nat(ws[2])
            if i and d:
                var needs = List[String]()
                for k in range(3, len(ws)):
                    var n = to_nat(ws[k])
                    if n:
                        needs.append(n.value())
                skills.append(Skill(i.value(), d.value() == "1", needs^))
        elif len(ws) == 2 and ws[0] == "goal":
            var g = to_nat(ws[1])
            if g:
                goals.append(g.value())
    if len(goals) == 1:
        goal = goals[0]
        return True
    return False


def index_of(ss: List[Skill], id: String) -> Int:
    """The first skill with this id, or -1."""
    for i in range(len(ss)):
        if ss[i].id == id:
            return i
    return -1


def domain_of(ss: List[Skill]) -> Domain:
    """One variable a skill, one action a skill still to do, and the needs of
    a skill as the variables its action requires."""
    var vars = List[StateVar]()
    for i in range(len(ss)):
        vars.append(StateVar(i, 1 if ss[i].done else 0))
    var levels = List[Int]()
    levels.append(2)
    var acts = List[Action]()
    var reqs = List[Require]()
    for s in ss:
        if s.done:
            continue
        var slot = index_of(ss, s.id)
        if slot < 0:
            slot = 0
        var w = List[Write]()
        w.append(Write(slot, number_value(1)))
        var name = "activate-" + s.id
        acts.append(Action(name, List[String](), w^))
        var needs = List[Need]()
        for n in s.needs:
            var j = index_of(ss, n)
            if j >= 0:
                needs.append(Need(j, 1))
        reqs.append(Require(name, needs^))
    return Domain(vars^, Codebook(levels^), acts^, reqs^)


def plan_of(spec: String) -> String:
    """The activation order that reaches the goal, or the refusal by name."""
    var ss = List[Skill]()
    var goal = String()
    if not parse(spec, ss, goal):
        return "{\"refused\":\"bad_spec\"}"
    var gi = index_of(ss, goal)
    if gi < 0:
        return "{\"refused\":\"undeclared_goal\"}"
    var dom = domain_of(ss)
    var g = goal_geq(gi, 1)
    var plan = List[String]()
    if not answer(dom, g, plan, len(dom.actions) + 1):
        return "{\"refused\":\"unreachable\"}"
    var reached = is_node_satisfied(dom.execute(plan), g)
    return (
        "{\"plan\":"
        + plan_json(plan)
        + ",\"reached\":"
        + ("true" if reached else "false")
        + "}"
    )
