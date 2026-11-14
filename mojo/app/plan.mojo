# plan DOMAIN PROBLEM [--goal G | --goals | --shortest N]: one answer on stdout.
from std.sys import argv
from persona.jsonld import plan_of, plan_with, goals_of, shortest_of


def read(path: String) raises -> String:
    with open(path, "r") as f:
        return f.read()


def main() raises:
    var a = argv()
    var dom = read(String(a[1]))
    var prob = read(String(a[2]))
    if len(a) >= 4 and String(a[3]) == "--goals":
        print(goals_of(dom, prob))
    elif len(a) >= 5 and String(a[3]) == "--goal":
        print(plan_with(dom, prob, String(a[4])))
    elif len(a) >= 5 and String(a[3]) == "--shortest":
        print(shortest_of(dom, prob, Int(String(a[4]))))
    else:
        print(plan_of(dom, prob))
