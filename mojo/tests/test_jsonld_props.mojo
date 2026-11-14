# SPDX-License-Identifier: MIT
# Property tests of the JSON-LD planner against the witness ladder, each with a
# planted-false control: a random needs-graph written as a RECTGTN domain and
# problem, an independent model of what is reachable, and the codecs of
# timeutil round-tripped.
from witness.ladder import *
from persona.jsonld import plan_of
from persona.timeutil import parse_duration, parse_stamp, fmt_stamp, fmt_dur


struct Tally(Movable):
    var total: Int
    var failed: Int

    def __init__(out self):
        self.total = 0
        self.failed = 0


def check(mut t: Tally, cond: Bool, name: String):
    t.total += 1
    if cond:
        print("  [ok  ] " + name)
    else:
        t.failed += 1
        print("  [FAIL] " + name)


@fieldwise_init
struct Node(Copyable, Movable):
    var done: Bool
    var needs: List[Int]


@fieldwise_init
struct Dag(Copyable, Movable):
    var nodes: List[Node]
    var goal: Int

    def domain(self) -> String:
        var acts = String()
        var ms = String()
        for i in range(len(self.nodes)):
            var body = String()
            var sub = String()
            for j in self.nodes[i].needs:
                body += "{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/s/" + String(j) + "\"},\"b\":1}},"
                sub += "[\"goal\",\"/s/" + String(j) + "\"],"
            acts += ("," if i > 0 else "") + "\"a" + String(i) + "\":{\"body\":[" + body + "{\"pointer/set\":\"/s/" + String(i) + "\",\"value\":1}]}"
            ms += ("," if i > 0 else "") + "\"/s/" + String(i) + "\":{\"alternatives\":[{\"name\":\"do\",\"subtasks\":[" + sub + "[\"a" + String(i) + "\"]]}]}"
        return "{\"name\":\"dag\",\"variables\":[],\"actions\":{" + acts + "},\"methods\":{" + ms + "}}"

    def problem(self) -> String:
        var init = String()
        for i in range(len(self.nodes)):
            init += ("," if i > 0 else "") + "\"" + String(i) + "\":" + ("1" if self.nodes[i].done else "0")
        return "{\"name\":\"dag_problem\",\"variables\":[{\"name\":\"s\",\"init\":{" + init + "}}],\"todo_list\":[{\"goal\":[{\"pointer\":\"/s/" + String(self.goal) + "\",\"eq\":1}]}]}"


def gen_dag(mut r: Run, lvl: Level) -> Dag:
    var n = r.int_range(1, 3 + lvl.idx * 2)
    var nodes = List[Node]()
    for _ in range(n):
        var needs = List[Int]()
        for _ in range(r.int_range(0, 2)):
            needs.append(r.int_range(0, n - 1))
        nodes.append(Node(r.int_range(0, 3) == 0, needs^))
    return Dag(nodes^, r.int_range(0, n - 1))


def show_dag(d: Dag) -> String:
    var s = String("goal ") + String(d.goal) + ":"
    for i in range(len(d.nodes)):
        s += " " + String(i) + ("*" if d.nodes[i].done else "") + "<-"
        for j in d.nodes[i].needs:
            s += String(j) + ","
    return s^


# the method for a node decomposes it through its needs, so a cycle never
# bottoms out: reachable = done, or all needs reachable without revisiting
def reach(d: Dag, i: Int, mut visiting: List[Bool]) -> Bool:
    if d.nodes[i].done:
        return True
    if visiting[i]:
        return False
    visiting[i] = True
    var ok = True
    for j in d.nodes[i].needs:
        if not reach(d, j, visiting):
            ok = False
    visiting[i] = False
    return ok


def model_reaches(d: Dag) -> Bool:
    var visiting = List[Bool]()
    for _ in range(len(d.nodes)):
        visiting.append(False)
    return reach(d, d.goal, visiting)


def steps_of(t: String) -> List[String]:
    var out = List[String]()
    var first = True
    for part in t.split("\"action\":\""):
        if first:
            first = False
            continue
        var nm = String()
        for cp in String(part).codepoint_slices():
            if cp == "\"":
                break
            nm += String(cp)
        out.append(nm^)
    return out^


def atoi(s: String) -> Int:
    var n = 0
    for b in s.as_bytes():
        n = n * 10 + Int(b) - 48
    return n


def p_dag_refusal_is_model(d: Dag, mut r: Run) -> Bool:
    var out = plan_of(d.domain(), d.problem())
    var want = model_reaches(d)
    r.classify(want, "reachable")
    if want:
        return "\"reached\":true" in out and not ("\"refused\"" in out)
    return "\"unreachable\"" in out


# replaying the steps: every action finds its needs already set, and the goal ends set
def p_dag_steps_replay(d: Dag, mut r: Run) -> Bool:
    if not model_reaches(d):
        return True
    var held = List[Bool]()
    for n in d.nodes:
        held.append(n.done)
    var steps = steps_of(plan_of(d.domain(), d.problem()))
    r.classify(len(steps) > 0, "has steps")
    for s in steps:
        var i = atoi(String(s.removeprefix("a")))
        for j in d.nodes[i].needs:
            if not held[j]:
                return False
        held[i] = True
    return held[d.goal]


def p_wrong_always_reaches(d: Dag, mut r: Run) -> Bool:
    return "\"reached\":true" in plan_of(d.domain(), d.problem())


def p_wrong_at_most_two_steps(d: Dag, mut r: Run) -> Bool:
    return len(steps_of(plan_of(d.domain(), d.problem()))) <= 2


# ---- codecs -----------------------------------------------------------------------------
def gen_secs(mut r: Run, lvl: Level) -> Int:
    var pick = r.int_range(0, 3)
    if pick == 0:
        return r.int_range(0, 120)
    if pick == 1:
        return r.int_range(0, 5 * 86400)
    return r.int_range(0, 4000000000)


def gen_stamp_secs(mut r: Run, lvl: Level) -> Int:
    return r.int_range(0, 7000000000)


def p_dur_round_trip(s: Int, mut r: Run) -> Bool:
    var back = 0
    return parse_duration(fmt_dur(s), back) and back == s


def p_stamp_round_trip(s: Int, mut r: Run) -> Bool:
    var back = 0
    return parse_stamp(fmt_stamp(s), back) and back == s


def p_stamp_is_20_chars(s: Int, mut r: Run) -> Bool:
    return fmt_stamp(s).byte_length() == 20


def p_wrong_dur_in_days(s: Int, mut r: Run) -> Bool:
    var back = 0
    return parse_duration(fmt_dur(s), back) and back == (s // 86400) * 86400


def p_wrong_stamp_before_2100(s: Int, mut r: Run) -> Bool:
    return fmt_stamp(s).startswith("20")


def show_int(n: Int) -> String:
    return String(n)


def holds[T: Value](mut t: Tally, name: String, gen: def(mut Run, Level) thin -> T, pred: def(T, mut Run) thin -> Bool, show: def(T) thin -> String):
    var tr = resolve[T](name, gen, pred, no_shrink[T], show, 0x5EED)
    check(t, tr.outcome == Outcome.PROVABLY_NONE, "property: " + name)
    if tr.outcome != Outcome.PROVABLY_NONE:
        print("         " + tr.message)


def falsified[T: Value](mut t: Tally, name: String, gen: def(mut Run, Level) thin -> T, pred: def(T, mut Run) thin -> Bool, show: def(T) thin -> String):
    var tr = resolve[T](name, gen, pred, no_shrink[T], show, 0x5EED)
    check(t, tr.outcome == Outcome.FOUND, "control: " + name + " is falsified")


def main() raises:
    var t = Tally()
    holds[Dag](t, "planner: a needs-graph is refused exactly when the model says unreachable", gen_dag, p_dag_refusal_is_model, show_dag)
    holds[Dag](t, "planner: replaying the steps finds every need set and the goal at the end", gen_dag, p_dag_steps_replay, show_dag)
    holds[Int](t, "timeutil: a duration written canonical parses back to the same seconds", gen_secs, p_dur_round_trip, show_int)
    holds[Int](t, "timeutil: a datestamp written parses back to the same seconds", gen_stamp_secs, p_stamp_round_trip, show_int)
    holds[Int](t, "timeutil: a datestamp is twenty characters", gen_stamp_secs, p_stamp_is_20_chars, show_int)
    falsified[Dag](t, "planner: every needs-graph reaches its goal", gen_dag, p_wrong_always_reaches, show_dag)
    falsified[Dag](t, "planner: no plan has more than two steps", gen_dag, p_wrong_at_most_two_steps, show_dag)
    falsified[Int](t, "timeutil: a duration only counts whole days", gen_secs, p_wrong_dur_in_days, show_int)
    falsified[Int](t, "timeutil: every datestamp is in the 2000s", gen_stamp_secs, p_wrong_stamp_before_2100, show_int)
    if t.failed == 0:
        print("OK: persona planner properties (mojo), " + String(t.total) + " hold")
    else:
        print("FAIL: " + String(t.failed) + " of " + String(t.total))
        raise Error("planner properties failed")
