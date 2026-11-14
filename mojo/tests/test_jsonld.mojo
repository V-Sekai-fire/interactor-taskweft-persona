# SPDX-License-Identifier: MIT
# The JSON-LD half of PersonaWitness.lean in Mojo: the campus gold plan, the
# engine-shaped reach sample, chains, temporal scheduling, GTN backtracking,
# the web entries, then every file-driven case under tests/ (enums, vocab,
# params, graph, GTPyhop, KHR). Run from mojo/: the cases are one level up.
from persona.jsonld import plan_of, plan_with, goals_of, shortest_of
from persona.timeutil import parse_stamp, fmt_stamp, fmt_dur
from persona.jdoc import *
from persona.khr import Entry, run_graph

comptime ROOT = "../"


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


def read(path: String) raises -> String:
    with open(ROOT + path, "r") as f:
        return f.read()


def has(t: String, sub: String) -> Bool:
    return sub in t


def trim(s: String) -> String:
    return String(s.strip())


def lines(s: String) -> List[String]:
    var out = List[String]()
    for l in s.split("\n"):
        if l.byte_length() > 0:
            out.append(String(l))
    return out^


def same(a: List[String], b: List[String]) -> Bool:
    if len(a) != len(b):
        return False
    for i in range(len(a)):
        if a[i] != b[i]:
            return False
    return True


def until_quote(s: String) -> String:
    var out = String()
    for cp in s.codepoint_slices():
        if cp == "\"":
            break
        out += String(cp)
    return out^


def step_keys(t: String) -> List[String]:
    """`name(arguments)` for each step, or `REFUSED:why`."""
    var out = List[String]()
    if has(t, "\"refused\""):
        var parts = t.split("\"refused\":\"")
        out.append("REFUSED:" + until_quote(String(parts[1])))
        return out^
    var first = True
    for part in t.split("\"action\":\""):
        if first:
            first = False
            continue
        var x = String(part)
        var name = until_quote(x)
        var inner = String()
        var ps = x.split("\"params\":[")
        if len(ps) > 1:
            for cp in String(ps[1]).codepoint_slices():
                if cp == "]":
                    break
                inner += String(cp)
        inner = inner.replace("\"", "")
        out.append(name if inner == "" else name + "(" + inner + ")")
    return out^


def actions_of(t: String) -> List[String]:
    var out = List[String]()
    var first = True
    for part in t.split("\"action\":\""):
        if first:
            first = False
            continue
        out.append(until_quote(String(part)))
    return out^


# ---- builders the Lean witness uses ---------------------------------------------
def chain_dom(n: Int) -> String:
    var ms = String()
    for i in range(n):
        var nxt = "act" if i + 1 == n else "c" + String(i + 1)
        ms += ("," if i > 0 else "") + "\"c" + String(i) + "\":{\"alternatives\":[{\"name\":\"go\",\"subtasks\":[[\"" + nxt + "\"]]}]}"
    return "{\"name\":\"chain\",\"variables\":[],\"actions\":{\"act\":{\"body\":[{\"pointer/set\":\"/v/x\",\"value\":1}]}},\"methods\":{" + ms + "}}"


def chain_prob() -> String:
    return "{\"name\":\"chain_problem\",\"variables\":[],\"todo_list\":[[\"c0\"]]}"


def temp_prob(origin: String) -> String:
    return "{\"name\":\"temporal_problem\",\"origin\":\"" + origin + "\",\"variables\":[],\"todo_list\":[[\"m\"]]}"


def temp_act(n: String, d: String, v: String, needs: List[String]) -> String:
    var s = "\"" + n + "\":{\"duration\":\"" + d + "\",\"body\":["
    for i in range(len(needs)):
        s += ("," if i > 0 else "") + "{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/" + needs[i] + "\"},\"b\":1}}"
    if len(needs) > 0:
        s += ","
    return s + "{\"pointer/set\":\"/v/" + v + "\",\"value\":1}]}"


def temp_dom() -> String:
    var none = List[String]()
    var ab = List[String]()
    ab.append("a")
    ab.append("b")
    return (
        "{\"name\":\"temporal\",\"variables\":[],\"actions\":{"
        + temp_act("a", "P2D", "a", none) + "," + temp_act("b", "P3D", "b", none) + ","
        + temp_act("c", "PT24H", "c", ab)
        + "},\"methods\":{\"m\":{\"alternatives\":[{\"name\":\"go\",\"subtasks\":[[\"a\"],[\"b\"],[\"c\"]]}]}}}"
    )


def temp_win_dom() -> String:
    return temp_dom().replace("\"methods\":{", "\"methods\":{\"w\":{\"alternatives\":[{\"name\":\"win\",\"subtasks\":[[\"m\"],[\"a\"],[\"b\"],[\"c\"]]}]},")


def temp_win_prob(origin: String) -> String:
    return "{\"name\":\"window_problem\",\"origin\":\"" + origin + "\",\"variables\":[],\"todo_list\":[[\"w\"]]}"


def gtn_dom() -> String:
    return (
        "{\"name\":\"shortcut\",\"variables\":[],\"actions\":{"
        + "\"a\":{\"body\":[{\"pointer/set\":\"/v/x\",\"value\":1}]},"
        + "\"b\":{\"body\":[{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/x\"},\"b\":1}},{\"pointer/set\":\"/v/y\",\"value\":1}]},"
        + "\"c\":{\"body\":[{\"pointer/set\":\"/v/y\",\"value\":1}]}},"
        + "\"methods\":{\"/v/y\":{\"alternatives\":[{\"name\":\"long\",\"subtasks\":[[\"goal\",\"/v/x\"],[\"b\"]]},{\"name\":\"short\",\"subtasks\":[[\"c\"]]}]},"
        + "\"/v/x\":{\"alternatives\":[{\"name\":\"do\",\"subtasks\":[[\"a\"]]}]}}}"
    )


def gtn_prob(goals: List[String]) -> String:
    var gs = String()
    for i in range(len(goals)):
        gs += ("," if i > 0 else "") + "{\"pointer\":\"" + goals[i] + "\",\"eq\":1}"
    return "{\"name\":\"shortcut_problem\",\"variables\":[{\"name\":\"v\",\"init\":{\"x\":0,\"y\":0,\"p\":0,\"q\":0,\"r\":0}}],\"todo_list\":[{\"goal\":[" + gs + "]}]}"


def back_dom() -> String:
    return (
        "{\"name\":\"back\",\"variables\":[],\"actions\":{"
        + "\"u1\":{\"body\":[{\"pointer/set\":\"/v/p\",\"value\":1}]},"
        + "\"u2\":{\"body\":[{\"pointer/set\":\"/v/p\",\"value\":1},{\"pointer/set\":\"/v/q\",\"value\":1}]},"
        + "\"w\":{\"body\":[{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/p\"},\"b\":1}},{\"eval\":{\"type\":\"math/ge\",\"a\":{\"type\":\"pointer/get\",\"pointer\":\"/v/q\"},\"b\":1}},{\"pointer/set\":\"/v/r\",\"value\":1}]}},"
        + "\"methods\":{\"/v/p\":{\"alternatives\":[{\"name\":\"first\",\"subtasks\":[[\"u1\"]]},{\"name\":\"second\",\"subtasks\":[[\"u2\"]]}]},"
        + "\"/v/r\":{\"alternatives\":[{\"name\":\"go\",\"subtasks\":[[\"w\"]]}]}}}"
    )


def one(a: String) -> List[String]:
    var l = List[String]()
    l.append(a)
    return l^


def two(a: String, b: String) -> List[String]:
    var l = List[String]()
    l.append(a)
    l.append(b)
    return l^


def stamp_plus(s: String, k: Int) -> String:
    var n = 0
    _ = parse_stamp(s, n)
    return fmt_stamp(n + k)


# ---- campus, temporal, GTN, web -----------------------------------------------------
def inline_checks(mut t: Tally) raises:
    var dom = read("domains/campus-sample.jsonld")
    var prob = read("problems/campus-sample.jsonld")
    var gold = read("plans/campus-sample.jsonld")
    var rdom = read("domains/campus-sample-reach.jsonld")
    var rprob = read("problems/campus-sample-reach.jsonld")
    var ask = plan_of(dom, prob)
    var held = prob.replace("\"3\": 0,\n    \"B1\"", "\"3\": 1,\n    \"B1\"")
    var solved = prob.replace("\"2\": 0,\n    \"3\": 0\n   }", "\"2\": 1,\n    \"3\": 1\n   }").replace("\"3\": 0,\n    \"B1\": 0", "\"3\": 1,\n    \"B1\": 1")

    check(t, trim(ask) == trim(gold), "campus: the planner's plan equals the gold plan")
    check(t, trim(ask) != trim(gold.replace("settle-2", "settle-9")), "campus: a gold plan with one step changed does not match")
    check(t, has(gold, "\"domain\":\"campus_sample\"") and has(gold, "\"problem\":\"campus_sample_problem\""), "campus: the plan names its domain and its problem")
    check(t, held != prob and solved != prob, "campus: the edited problems differ from the original, so their checks bite")
    check(t, not has(plan_of(dom, held), "acquire-token-3") and has(plan_of(dom, held), "settle-3"), "campus: a token already held is not acquired again")
    check(t, has(plan_of(dom, solved), "\"steps\":[]"), "campus: a goal that already holds needs no step")
    check(t, has(plan_of(dom, prob.replace("/rfd/3", "/rfd/9")), "undeclared_goal"), "campus: a goal the problem does not declare is refused")
    check(t, has(plan_of(dom.replace("\"pointer/set\": \"/token/3\"", "\"pointer/set\": \"/token/9\""), prob), "unreachable"), "campus: a token that is never acquired leaves the goal unreachable")
    check(t, has(plan_of("{", prob), "bad_domain"), "campus: a domain that is not JSON is refused")
    check(t, has(plan_of(dom, "{"), "bad_problem"), "campus: a problem that is not JSON is refused")
    check(t, has(plan_of(dom, prob.replace("\"todo_list\"", "\"todos\"")), "no_goal"), "campus: a problem with no goal is refused")
    check(t, same(step_keys(plan_of(rdom, rprob)), step_keys(gold)), "reach: the engine-shaped sample plans to the same steps as the pointer-shaped one")
    check(t, has(plan_of(rdom, rprob.replace("reach-rfd-3", "reach-rfd-9")), "undeclared_goal"), "reach: a task the domain does not name is refused")
    check(t, has(plan_of(rdom, rprob.replace("reach-rfd-3", "reach-rfd-1")), "\"steps\":[]"), "reach: a goal already held by its first alternative needs no step")
    check(t, has(plan_of(rdom, rprob.replace("reach-rfd-3", "")), "no_goal") or has(plan_of(rdom, rprob.replace("\"todo_list\"", "\"todos\"")), "no_goal"), "reach: a todo list with no entry is refused")
    check(t, has(plan_of(chain_dom(20), chain_prob()), "\"reached\":true"), "reach: a chain of methods deeper than twelve still plans")
    check(t, has(plan_of(chain_dom(20).replace("\"act\":{", "\"actx\":{"), chain_prob()), "unreachable"), "reach: the same chain with its action removed is refused")

    var o = "2026-11-02T00:00:00Z"
    var tt = plan_of(temp_dom(), temp_prob(o))
    check(t, has(tt, "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\"") and has(tt, "\"action\":\"b\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-05T00:00:00Z\"") and has(tt, "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\",\"end\":\"2026-11-06T00:00:00Z\""), "temporal: independent steps start together and the dependent one starts at the later end")
    check(t, has(tt, "\"total\":\"P4D\"") and not has(tt, "\"total\":\"P6D\""), "temporal: the total is the critical path, not the sum, and is a duration")
    tt = plan_of(temp_dom(), temp_prob(""))
    check(t, has(tt, "\"params\":[],\"duration\":\"P2D\"") and not has(tt, "\"start\"") and not has(tt, "\"end\":") and not has(plan_of(temp_dom(), temp_prob("2026-13-40T00:00:00Z")), "\"origin\""), "temporal: with no valid origin every start and end is unspecified and durations stay durations")
    var nodur = temp_dom().replace("\"duration\":\"P2D\",", "").replace("\"duration\":\"P3D\",", "").replace("\"duration\":\"PT24H\",", "")
    tt = plan_of(nodur, temp_prob(o))
    check(t, has(tt, "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-02T00:00:00Z\",\"duration\":\"PT0S\"") and has(tt, "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-02T00:00:00Z\",\"duration\":\"PT0S\"") and has(tt, "\"total\":\"PT0S\""), "temporal: an action that states no duration is instantaneous, so its start and end coincide and the total is zero")
    tt = plan_of(nodur, temp_prob(""))
    check(t, has(tt, "\"params\":[],\"duration\":\"PT0S\"") and not has(tt, "\"start\""), "temporal: with no duration and no origin the start and end are unspecified and the duration is PT0S")
    check(t, has(plan_of(temp_dom().replace("\"duration\":\"P2D\"", "\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\""), temp_prob("")), "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\",\"duration\":\"P2D\""), "temporal: an action that states a start and an end has the end minus the start as its duration")
    tt = plan_of(temp_win_dom(), temp_win_prob(o))
    check(t, has(tt, "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-04T00:00:00Z\"") and has(tt, "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-03T00:00:00Z\",\"end\":\"2026-11-05T00:00:00Z\"") and has(tt, "\"action\":\"b\",\"params\":[],\"start\":\"2026-11-02T00:00:00Z\",\"end\":\"2026-11-05T00:00:00Z\"") and has(tt, "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\",\"end\":\"2026-11-06T00:00:00Z\""), "temporal: a step the plan lists again is presented at its last possible time points")
    check(t, has(tt, "\"total\":\"P4D\""), "temporal: listing the steps again does not move the plan's total")
    var rel = temp_dom().replace("\"duration\":\"P2D\"", "\"start\":\"2026-11-05T00:00:00Z\",\"duration\":\"P2D\"")
    tt = plan_of(rel, temp_prob(o))
    check(t, has(tt, "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\",\"end\":\"2026-11-07T00:00:00Z\"") and has(tt, "\"action\":\"c\",\"params\":[],\"start\":\"2026-11-07T00:00:00Z\",\"end\":\"2026-11-08T00:00:00Z\"") and has(tt, "\"total\":\"P6D\"") and has(tt, "\"consistent\":true"), "temporal: a start an action states is a release time, so it and the steps after it start no earlier")
    check(t, has(plan_of(temp_dom().replace("\"duration\":\"P2D\"", "\"end\":\"2026-11-03T00:00:00Z\",\"duration\":\"P2D\""), temp_prob(o)), "\"consistent\":false") and has(plan_of(temp_dom().replace("\"duration\":\"P2D\"", "\"end\":\"2026-11-04T00:00:00Z\",\"duration\":\"P2D\""), temp_prob(o)), "\"consistent\":true"), "temporal: an end an action states is a deadline, and a plan that misses it is not consistent")
    tt = plan_of(rel, temp_prob(""))
    check(t, has(tt, "\"origin\":\"2026-11-05T00:00:00Z\"") and has(tt, "\"action\":\"a\",\"params\":[],\"start\":\"2026-11-05T00:00:00Z\""), "temporal: with no origin stated the plan starts at the earliest start an action states")
    check(t, stamp_plus("2026-02-27T12:00:00Z", 259200) == "2026-03-02T12:00:00Z" and stamp_plus("2028-02-27T00:00:00Z", 172800) == "2028-02-29T00:00:00Z" and stamp_plus("2026-12-31T23:59:59Z", 1) == "2027-01-01T00:00:00Z", "temporal: a datestamp carries across a month end, a leap day and a year end")
    check(t, fmt_dur(0) == "PT0S" and fmt_dur(90000) == "P1DT1H" and fmt_dur(3661) == "PT1H1M1S" and fmt_dur(259200) == "P3D", "temporal: a duration is written in its canonical ISO-8601 form")

    var gd = gtn_dom()
    tt = plan_of(gd, gtn_prob(one("/v/y")))
    check(t, has(tt, "\"action\":\"b\"") and not has(tt, "\"action\":\"c\""), "gtn: the first decomposition found takes the long way")
    tt = shortest_of(gd, gtn_prob(one("/v/y")), 10)
    check(t, has(tt, "\"length\":1") and has(tt, "\"action\":\"c\"") and has(tt, "\"optimal\":true") and not has(tt, "\"action\":\"b\""), "gtn: planning with a rising bound on the actions finds the plan with the fewest")
    tt = plan_of(back_dom(), gtn_prob(two("/v/p", "/v/r")))
    check(t, has(tt, "\"reached\":true") and has(tt, "\"action\":\"u2\"") and not has(tt, "\"action\":\"u1\""), "gtn: a later goal that fails backtracks into the earlier goal's other alternative")
    check(t, has(shortest_of(gd, gtn_prob(one("/v/y")), 1), "\"length\":1") and has(shortest_of(gd, gtn_prob(one("/v/y")), 0), "limit"), "gtn: a bound equal to the shortest plan is enough, one less says limit")
    var cyc_dom = "{\"name\":\"cyc\",\"variables\":[],\"actions\":{},\"methods\":{\"m\":{\"alternatives\":[{\"name\":\"x\",\"subtasks\":[[\"m\"]]}]}}}"
    check(t, has(plan_of(cyc_dom, "{\"name\":\"p\",\"variables\":[],\"todo_list\":[[\"m\"]]}"), "unreachable"), "gtn: a method that only calls itself runs out of fuel and is refused")
    check(t, has(shortest_of(gd, gtn_prob(one("/v/q")), 10), "unreachable") and has(shortest_of(gd.replace("\"c\":{\"body\":[{\"pointer/set\":\"/v/y\",\"value\":1}]}", "\"c\":{\"body\":[{\"pointer/set\":\"/v/z\",\"value\":1}]}"), gtn_prob(one("/v/y")), 1), "limit"), "gtn: a goal no decomposition reaches keeps its refusal, and a bound too small says limit")

    check(t, has(goals_of(dom, prob), "\"goal\":\"/rfd/3\",\"declared\":true"), "web: the goals list names the goal the problem asks and declares it")
    check(t, has(goals_of(dom, held), "\"held\":false") and has(goals_of(dom, solved), "\"held\":true"), "web: a goal the problem holds already is reported held")
    check(t, plan_with(dom, prob, "/rfd/3") == ask and plan_with(dom, prob, "") == ask, "web: planning the one named goal equals planning all goals of a one-goal problem")
    check(t, has(plan_with(dom, prob, "/rfd/9"), "undeclared_goal"), "web: a named goal no variable declares is refused")
    check(t, has(goals_of("{", prob), "bad_domain"), "web: the goals list of a domain that is not JSON is refused")


# ---- file-driven cases ------------------------------------------------------------------
def dir_cases(mut t: Tally, label: String, dir: String, names: List[String]) raises:
    var dom = read(dir + "/domain.jsonld")
    for n in names:
        var prob = read(dir + "/" + n + ".problem.jsonld")
        var expect = lines(read(dir + "/" + n + ".expect"))
        check(t, same(step_keys(plan_of(dom, prob)), expect), label + n)


def names(s: String) -> List[String]:
    var out = List[String]()
    for x in s.split(","):
        out.append(String(x))
    return out^


def file_checks(mut t: Tally) raises:
    dir_cases(t, "enums: ", "tests/enums", names("members-print-as-names,member-as-a-value,qualified-member,ambiguous-member,ambiguous-bare-refused,unknown-member,numbers-still-work"))
    dir_cases(t, "vocab: ", "tests/vocab", names("names-print,order-is-the-problems,equality-refuses,name-not-in-codebook"))
    dir_cases(t, "graph method: ", "tests/graph", names("hit-in-the-middle,first-hit-wins,last-cell,no-hit-falls-back"))
    dir_cases(t, "params: ", "tests/params", names("finish-two,use-without-mark,value-reaches,value-falls-short,missing-argument,finish-name,finish-name-and-number,name-not-interned,digits-as-string"))
    var blocks = names("pickup-a,pickup-b,take-b,pickup-c,take-a,take-c,take-a-put-a-table,goal1a,goal1b,sussman,goal2a,goal2b,goal2b-done,goal3")
    for c in names("blocks_gtn,blocks_htn"):
        dir_cases(t, "gtpyhop " + c + ": ", "tests/gtpyhop/" + c, blocks)
        var dom = read("tests/gtpyhop/" + c + "/domain.jsonld")
        var sus = read("tests/gtpyhop/" + c + "/sussman.problem.jsonld")
        var best = shortest_of(dom, sus, 40)
        check(t, has(best, "\"length\":6") and has(best, "\"optimal\":true"), "gtpyhop " + c + ": the shortest plan for the Sussman anomaly has six actions")
        check(t, has(shortest_of(dom, sus, 5), "limit"), "gtpyhop " + c + ": a bound of five is refused as limit")
    for c in names("blocks_hgn,blocks_goal_splitting,logistics_hgn,simple_htn,simple_hgn,pyhop_simple_travel_example"):
        dir_cases(t, "gtpyhop " + c + ": ", "tests/gtpyhop/" + c, lines(read("tests/gtpyhop/" + c + "/cases")))
    var gtn = lines(read("tests/gtpyhop/blocks_gtn/goal1a.expect"))
    var gs = lines(read("tests/gtpyhop/blocks_goal_splitting/goal1a.expect"))
    check(t, not same(gs, gtn) and len(gs) > len(gtn), "gtpyhop blocks_goal_splitting: goal1a is not the blocks_gtn plan")
    var bt = read("tests/gtpyhop/backtracking_htn/domain.jsonld")
    for n in names("put_it-need0,put_it-need01,put_it-need10,put_it-need1"):
        var prob = read("tests/gtpyhop/backtracking_htn/" + n + ".problem.jsonld")
        var expect = lines(read("tests/gtpyhop/backtracking_htn/" + n + ".expect"))
        var got = actions_of(plan_of(bt, prob))
        var other = names("putv-1,getv-1,getv-1") if same(expect, names("putv-0,getv-0,getv-0")) else names("putv-0,getv-0,getv-0")
        check(t, same(got, expect), "gtpyhop backtracking_htn: " + n + " plans to the expected actions")
        check(t, not same(got, other), "gtpyhop backtracking_htn: " + n + " is not GTPyhop's other expected plan")


def khr_checks(mut t: Tally) raises:
    khr_dir(t, "tests/khr", names("for-sums,for-empty,for-end-read-each-pass,branch-true,branch-false,branch-needs-bool,while-counts,select,math-switch,math-switch-default,int-wraps,eq-one-type,pointer-valid,sequence-string-order,variable-set-two,variable-out-of-range,float-type,unbuilt-node,fuel"))
    # the cases this port adds: a node costs fuel, so a chain of two nodes needs two
    khr_dir(t, "mojo/tests/khr-extra", names("two-nodes-one-fuel"))


def khr_dir(mut t: Tally, dir: String, cases: List[String]) raises:
    for n in cases:
        var g = read(dir + "/" + n + ".graph.json")
        var expect = lines(read(dir + "/" + n + ".expect"))
        var fuel = 100000
        var ft = trim(read(dir + "/" + n + ".fuel"))
        var fv = 0
        if ft.byte_length() > 0:
            var ok = True
            fv = 0
            for b in ft.as_bytes():
                if b < 48 or b > 57:
                    ok = False
                else:
                    fv = fv * 10 + Int(b) - 48
            if ok:
                fuel = fv
        var got = List[String]()
        var doc = JDoc()
        var root = 0
        if not parse_json(g, doc, root):
            got.append("ERROR:parse")
        else:
            var out = List[Entry]()
            try:
                run_graph(doc, root, List[Entry](), List[Entry](), out, fuel)
                for e in out:
                    got.append(e.key + "=" + String(e.val))
            except e:
                got.append("ERROR:" + String(e))
        var ok = False
        if len(expect) == 1 and expect[0].startswith("ERROR:"):
            var want = String(expect[0][byte=6:])
            for x in got:
                if x.startswith("ERROR:") and want in x:
                    ok = True
        else:
            ok = same(got, expect)
        check(t, ok, "khr: " + n)


def main() raises:
    var t = Tally()
    inline_checks(t)
    file_checks(t)
    khr_checks(t)
    if t.failed == 0:
        print("OK: persona jsonld (mojo), " + String(t.total) + " invariants hold")
    else:
        print("FAIL: " + String(t.failed) + " of " + String(t.total) + " invariants failed")
        raise Error("jsonld gate failed")
