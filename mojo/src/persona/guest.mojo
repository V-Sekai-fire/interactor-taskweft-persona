# SPDX-License-Identifier: MIT
# Persona/Demo.lean and Persona/Guest.lean: the delivery domain and the JSON
# the guest answers with.
from persona.core import *


comptime VERSION_TEXT = "0.1.0"


def demo_domain() -> Domain:
    """A robot at a dock, a package in storage, a delivered flag."""
    var vars = List[StateVar]()
    vars.append(StateVar(0, 0))
    vars.append(StateVar(1, 0))
    vars.append(StateVar(2, 0))
    var levels = List[Int]()
    levels.append(4)
    levels.append(4)
    var agent = List[String]()
    agent.append("agent")
    var agent_pkg = List[String]()
    agent_pkg.append("agent")
    agent_pkg.append("pkg")

    var acts = List[Action]()
    var w = List[Write]()
    w.append(Write(0, code_value([0, 0])))
    acts.append(Action("recharge", agent.copy(), w^))
    w = List[Write]()
    w.append(Write(0, code_value([1, 0])))
    acts.append(Action("move_to_storage", agent.copy(), w^))
    w = List[Write]()
    w.append(Write(1, number_value(1)))
    acts.append(Action("pickup", agent_pkg.copy(), w^))
    w = List[Write]()
    w.append(Write(0, code_value([2, 0])))
    acts.append(Action("move_to_shipping", agent.copy(), w^))
    w = List[Write]()
    w.append(Write(2, number_value(1)))
    w.append(Write(1, number_value(0)))
    acts.append(Action("dropoff", agent_pkg.copy(), w^))
    return Domain(vars^, Codebook(levels^), acts^, List[Require]())


def delivered() -> Node:
    return goal_geq(2, 1)


def goal_of(request: String, mut g: Node) -> Bool:
    """A name the guest does not declare is refused, not approximated."""
    if request == "" or request == "delivered":
        g = delivered()
        return True
    return False


def quote(s: String) -> String:
    """A JSON string holding `s`, with the two characters that could end it
    early escaped."""
    var out = String("\"")
    for cp in s.codepoint_slices():
        if cp == "\"":
            out += "\\\""
        elif cp == "\\":
            out += "\\\\"
        else:
            out += String(cp)
    out += "\""
    return out^


def plan_json(plan: List[String]) -> String:
    var out = String("[")
    for i in range(len(plan)):
        if i > 0:
            out += ","
        out += quote(plan[i])
    out += "]"
    return out^


def answer_json(request: String) -> String:
    var g = delivered()
    if not goal_of(request, g):
        return "{\"refused\":\"undeclared_goal\"}"
    var d = demo_domain()
    var plan = List[String]()
    if not answer(d, g, plan):
        return "{\"goal\":\"delivered\",\"refused\":\"unreachable\"}"
    var reached = is_node_satisfied(d.execute(plan), g)
    return (
        "{\"goal\":\"delivered\",\"plan\":"
        + plan_json(plan)
        + ",\"reached\":"
        + ("true" if reached else "false")
        + "}"
    )
