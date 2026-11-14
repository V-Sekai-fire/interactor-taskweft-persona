# pixi run ask / vocabulary: PersonaMain.lean in Mojo.
from std.sys import argv
from persona.core import *
from persona.guest import demo_domain, delivered


def print_vocabulary():
    var d = demo_domain()
    var cb = d.codebook.copy()
    print("vocabulary: the codebook a persona composes from")
    print("  dimensions      " + String(len(cb.levels)))
    print("  levels          " + _list(cb.levels))
    print("  basis           " + _list(cb.basis()))
    print("  codes a stage   " + String(cb.size()))
    print("  codes, 4 stages " + String(cb.vocabulary(4)))
    print("values: a code of the codebook, or a number")
    print("actions, with the parameters a call binds")
    for a in d.actions:
        var ps = String()
        for i in range(len(a.params)):
            ps += (", " if i > 0 else "") + a.params[i]
        var ws = String()
        for i in range(len(a.writes)):
            var w = a.writes[i].copy()
            ws += (", " if i > 0 else "") + String(w.var_id) + " <- "
            ws += ("code " + _list(w.value.code)) if w.value.is_code else ("number " + String(w.value.number))
        print("  " + a.name + "(" + ps + ") writes " + ws)
    print("goals: a node of the planner's own space")
    print("  delivered = goal_geq 2 1")


def _list(xs: List[Int]) -> String:
    var s = String("[")
    for i in range(len(xs)):
        s += (", " if i > 0 else "") + String(xs[i])
    return s + "]"


def main() raises:
    if len(argv()) > 1 and String(argv()[1]) == "--vocabulary":
        print_vocabulary()
        return
    var d = demo_domain()
    var g = delivered()
    print("goal: RECTGTNNode.goal_geq " + String(g.var_id) + " " + String(g.threshold))
    var plan = List[String]()
    if answer(d, g, plan):
        print("PLAN (" + String(len(plan)) + " steps)")
        for s in plan:
            print("  " + s)
        print("reached: " + ("true" if is_node_satisfied(d.execute(plan), g) else "false"))
    else:
        print("NO PLAN")
        raise Error("no plan")
