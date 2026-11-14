# SPDX-License-Identifier: MIT
# The persona's gate in Mojo: the 18 invariants of PersonaWitness.lean that
# the core owns (codebook, answer, refusal, grid, domain), then property
# tests against the witness ladder, each paired with a planted-false control.
from witness.ladder import *
from persona.core import *
from persona.guest import *
from persona.grid import plan_of, parse, domain_of, Skill


# ---- plain invariants ---------------------------------------------------
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


def distinct(plan: List[String]) -> Bool:
    for i in range(len(plan)):
        for j in range(i + 1, len(plan)):
            if plan[i] == plan[j]:
                return False
    return True


def stage() -> Codebook:
    return Codebook([8, 8, 8, 8])


def invariants(mut t: Tally):
    var d = demo_domain()
    var plan = List[String]()
    var got = answer(d, delivered(), plan)
    var reached = got and is_node_satisfied(d.execute(plan), delivered())
    var none = List[String]()

    check(t, stage().size() == 4096, "codebook: eight levels over four dimensions is 4096 codes a stage")
    var b = stage().basis()
    check(t, len(b) == 4 and b[0] == 1 and b[1] == 8 and b[2] == 64 and b[3] == 512, "codebook: the basis is the prefix product")
    check(t, stage().index([1, 2, 3, 4]) == 2257, "codebook: a code's index is mixed-radix")
    check(t, stage().vocabulary(4) == 281474976710656, "codebook: four stages of 4096 codes is the whole vocabulary")
    check(t, stage().holds([7, 7, 7, 7]), "codebook: a held code carries one digit a dimension, in range")
    check(t, not stage().holds([8, 0, 0, 0]), "codebook: a digit past its level is refused")
    check(t, not stage().holds([1, 2, 3]), "codebook: a code of the wrong arity is refused")
    check(t, got, "answer: the goal is reached")
    check(t, reached, "answer: the plan it composes executes to the goal")
    check(t, got and distinct(plan), "answer: the plan does not repeat an action")
    check(t, not answer(d, goal_geq(2, 2), none), "refusal: a goal the domain cannot reach")
    check(t, not answer(d, goal_geq(99, 1), none), "refusal: a variable the domain does not declare")
    check(t, not answer(d, delivered(), none, 0), "refusal: zero fuel on an unmet goal")
    check(
        t,
        plan_of("skill 1 1\nskill 2 0 1\nskill 3 0 2 1\nskill 4 0 3\ngoal 4")
        == "{\"plan\":[\"activate-2\",\"activate-3\",\"activate-4\"],\"reached\":true}",
        "grid: a plan activates every skill after the skills it needs",
    )
    check(t, plan_of("skill 1 0 2\nskill 2 0 1\ngoal 1") == "{\"refused\":\"unreachable\"}", "grid: a cycle of needs is refused as unreachable")
    check(t, plan_of("skill 1 1\ngoal 9") == "{\"refused\":\"undeclared_goal\"}", "grid: a goal the spec does not declare is refused")
    var vars_ok = True
    var codes_ok = True
    for a in d.actions:
        for w in a.writes:
            var declared = False
            for sv in d.variables:
                if sv.id == w.var_id:
                    declared = True
            if not declared:
                vars_ok = False
            if not d.accepts(w.value):
                codes_ok = False
    check(t, vars_ok, "domain: every action writes a variable the domain declares")
    check(t, codes_ok, "domain: every code an action writes is held by the codebook")

    var st5 = GTNState([StateVar(2, 5)], List[String]())
    check(t, not is_node_satisfied(st5, verify_goal(2, 1)) and is_node_satisfied(st5, verify_goal(2, 5)), "node: verify_goal holds on equality, not on a larger value")
    check(t, is_node_satisfied(st5, goal_geq(2, 1)) and not is_node_satisfied(st5, goal_geq(2, 6)), "node: goal_geq holds from its threshold up")
    check(t, not is_node_satisfied(st5, task_node()) and not is_node_satisfied(st5, goal_geq(3, 0)), "node: a task and an absent variable are never satisfied")
    check(t, plan_of("skill 1 1\ngoal 1\ngoal 1") == "{\"refused\":\"bad_spec\"}", "grid: two goals are a bad spec")
    check(t, plan_of("skill 1 1") == "{\"refused\":\"bad_spec\"}", "grid: no goal is a bad spec")

    # the guest surface, as the standalone gate reads it
    check(t, VERSION_TEXT == "0.1.0", "guest: the surface version")
    check(
        t,
        answer_json("") == "{\"goal\":\"delivered\",\"plan\":[\"recharge\",\"move_to_storage\",\"pickup\",\"move_to_shipping\",\"dropoff\"],\"reached\":true}",
        "guest: the default goal plans recharge, move_to_storage, pickup, move_to_shipping, dropoff",
    )
    check(t, answer_json("delivered") == answer_json(""), "guest: a named goal equals the default")
    check(t, answer_json("nope") == "{\"refused\":\"undeclared_goal\"}", "guest: an undeclared goal is refused by name")
    check(t, quote("a\"b\\c") == "\"a\\\"b\\\\c\"", "guest: a quote and a backslash are escaped")
    check(t, d.resolve(code_value([1, 2])) == 9, "domain: a code resolves through the codebook")
    check(t, d.resolve(code_value([4, 0])) == 0, "domain: a code the codebook does not hold resolves to zero")
    check(t, d.resolve(number_value(-7)) == -7, "domain: a number is itself")
    check(t, not d.accepts(code_value([9, 9])) and d.accepts(number_value(5)), "domain: only held codes and numbers are accepted")


# ---- property inputs ----------------------------------------------------
@fieldwise_init
struct Row(Copyable, Movable):
    var id: Int
    var done: Bool
    var needs: List[Int]


@fieldwise_init
struct Grid(Copyable, Movable):
    var rows: List[Row]
    var goal: Int

    def spec(self) -> String:
        var s = String()
        for r in self.rows:
            s += "skill " + String(r.id) + " " + ("1" if r.done else "0")
            for n in r.needs:
                s += " " + String(n)
            s += "\n"
        s += "goal " + String(self.goal)
        return s^


def gen_grid(mut r: Run, lvl: Level) -> Grid:
    var n = r.int_range(1, 4 + 2 * lvl.idx)
    var rows = List[Row]()
    for i in range(n):
        var needs = List[Int]()
        var k = r.int_range(0, 3)
        for _ in range(k):
            needs.append(r.int_range(1, n + 1))  # n + 1 names no skill
        rows.append(Row(i + 1, r.int_range(0, 3) == 0, needs^))
    var goal = r.int_range(1, n)
    if r.int_range(0, 9) == 0:
        goal = n + 3
    return Grid(rows^, goal)


def show_grid(g: Grid) -> String:
    return g.spec().replace("\n", " | ")


def known(g: Grid, id: Int) -> Bool:
    return id >= 1 and id <= len(g.rows)


# An independent model: activate any skill whose known needs are done until
# nothing changes. The goal is reachable when it ends done.
def model_reaches(g: Grid) -> Bool:
    var done = List[Bool]()
    for r in g.rows:
        done.append(r.done)
    var changed = True
    while changed:
        changed = False
        for i in range(len(g.rows)):
            if done[i]:
                continue
            var ok = True
            for n in g.rows[i].needs:
                if known(g, n) and not done[n - 1]:
                    ok = False
            if ok:
                done[i] = True
                changed = True
    return known(g, g.goal) and done[g.goal - 1]


def planned(g: Grid, mut plan: List[String]) -> Bool:
    var ss = List[Skill]()
    var goal = String()
    if not parse(g.spec(), ss, goal):
        return False
    var dom = domain_of(ss)
    return answer(dom, goal_geq(g.goal - 1, 1), plan, len(dom.actions) + 1)


def atoi(s: String) -> Int:
    var n = 0
    for b in s.as_bytes():
        n = n * 10 + Int(b) - 48
    return n


# every activation comes after the known skills it needs, none repeats
def p_grid_plan_is_ordered(g: Grid, mut r: Run) -> Bool:
    if not known(g, g.goal):
        return True
    var plan = List[String]()
    if not planned(g, plan):
        r.classify(True, "unreachable")
        return True
    r.classify(len(plan) > 0, "needs steps")
    var done = List[Bool]()
    for row in g.rows:
        done.append(row.done)
    for step in plan:
        var id = atoi(String(step.removeprefix("activate-")))
        if not known(g, id) or done[id - 1]:
            return False
        for n in g.rows[id - 1].needs:
            if known(g, n) and not done[n - 1]:
                return False
        done[id - 1] = True
    return done[g.goal - 1] and distinct(plan)


def p_grid_reaches_iff_model(g: Grid, mut r: Run) -> Bool:
    if not known(g, g.goal):
        return True
    var plan = List[String]()
    var got = planned(g, plan)
    r.classify(got, "reachable")
    return got == model_reaches(g)


def p_grid_text_names_refusal(g: Grid, mut r: Run) -> Bool:
    var out = plan_of(g.spec())
    if not known(g, g.goal):
        return out == "{\"refused\":\"undeclared_goal\"}"
    if model_reaches(g):
        return out.startswith("{\"plan\":[") and out.endswith("\"reached\":true}")
    return out == "{\"refused\":\"unreachable\"}"


# planted-false: a plan never has more than one step
def p_wrong_plan_short(g: Grid, mut r: Run) -> Bool:
    if not known(g, g.goal):
        return True
    var plan = List[String]()
    if planned(g, plan):
        return len(plan) <= 1
    return True


# planted-false: every goal is reachable
def p_wrong_always_reached(g: Grid, mut r: Run) -> Bool:
    if not known(g, g.goal):
        return True
    var plan = List[String]()
    return planned(g, plan)


# planted-false: the spec text is always accepted as a plan
def p_wrong_never_refuses(g: Grid, mut r: Run) -> Bool:
    return plan_of(g.spec()).startswith("{\"plan\"")


@fieldwise_init
struct CodeCase(Copyable, Movable):
    var levels: List[Int]
    var code: List[Int]


def gen_code_case(mut r: Run, lvl: Level) -> CodeCase:
    var dims = r.int_range(1, 4)
    var levels = List[Int]()
    for _ in range(dims):
        levels.append(r.int_range(1, 9))
    var arity = dims
    if r.int_range(0, 5) == 0:
        arity = r.int_range(0, 6)
    var code = List[Int]()
    for i in range(arity):
        var top = levels[i] if i < dims else 9
        code.append(r.int_range(0, top + (1 if r.int_range(0, 3) == 0 else 0)))
    return CodeCase(levels^, code^)


def show_code_case(c: CodeCase) -> String:
    var s = String("levels")
    for l in c.levels:
        s += " " + String(l)
    s += " code"
    for d in c.code:
        s += " " + String(d)
    return s^


def model_holds(c: CodeCase) -> Bool:
    if len(c.code) != len(c.levels):
        return False
    for i in range(len(c.code)):
        if c.code[i] >= c.levels[i]:
            return False
    return True


def p_code_holds_is_model(c: CodeCase, mut r: Run) -> Bool:
    var held = Codebook(c.levels.copy()).holds(c.code)
    r.classify(held, "held")
    return held == model_holds(c)


# a held code's index is below the size and its digits come back by div/mod
def p_code_index_round_trips(c: CodeCase, mut r: Run) -> Bool:
    var cb = Codebook(c.levels.copy())
    if not cb.holds(c.code):
        return True
    var idx = cb.index(c.code)
    if idx < 0 or idx >= cb.size():
        return False
    var rest = idx
    for i in range(len(c.levels)):
        if rest % c.levels[i] != c.code[i]:
            return False
        rest = rest // c.levels[i]
    return rest == 0


# a code the book refuses resolves to zero, a held one to its index
def p_resolve_refuses(c: CodeCase, mut r: Run) -> Bool:
    var d = Domain(List[StateVar](), Codebook(c.levels.copy()), List[Action](), List[Require]())
    var v = code_value(c.code)
    if d.accepts(v):
        return d.resolve(v) == d.codebook.index(c.code)
    return d.resolve(v) == 0


def p_wrong_every_code_held(c: CodeCase, mut r: Run) -> Bool:
    return Codebook(c.levels.copy()).holds(c.code)


def p_wrong_index_zero(c: CodeCase, mut r: Run) -> Bool:
    var cb = Codebook(c.levels.copy())
    if not cb.holds(c.code):
        return True
    return cb.index(c.code) == 0


def holds_property[T: Value](
    mut t: Tally,
    name: String,
    gen: def(mut Run, Level) thin -> T,
    pred: def(T, mut Run) thin -> Bool,
    shrinker: def(T) thin -> List[T],
    show: def(T) thin -> String,
):
    var trial = resolve[T](name, gen, pred, shrinker, show, 0x5EED)
    var ok = trial.outcome == Outcome.PROVABLY_NONE
    check(t, ok, "property: " + name)
    if not ok:
        print("         " + trial.message)


def planted_false[T: Value](
    mut t: Tally,
    name: String,
    gen: def(mut Run, Level) thin -> T,
    pred: def(T, mut Run) thin -> Bool,
    shrinker: def(T) thin -> List[T],
    show: def(T) thin -> String,
):
    var trial = resolve[T](name, gen, pred, shrinker, show, 0x5EED)
    check(t, trial.outcome == Outcome.FOUND, "control: " + name + " is falsified")


def main() raises:
    var t = Tally()
    invariants(t)
    holds_property[Grid](t, "grid: a plan is ordered, whole and never repeats", gen_grid, p_grid_plan_is_ordered, no_shrink[Grid], show_grid)
    holds_property[Grid](t, "grid: a goal is reached exactly when the model reaches it", gen_grid, p_grid_reaches_iff_model, no_shrink[Grid], show_grid)
    holds_property[Grid](t, "grid: the text answer names each refusal", gen_grid, p_grid_text_names_refusal, no_shrink[Grid], show_grid)
    holds_property[CodeCase](t, "codebook: holds equals the digit-by-digit model", gen_code_case, p_code_holds_is_model, no_shrink[CodeCase], show_code_case)
    holds_property[CodeCase](t, "codebook: a held code's index round-trips through its digits", gen_code_case, p_code_index_round_trips, no_shrink[CodeCase], show_code_case)
    holds_property[CodeCase](t, "domain: a refused code resolves to zero, a held one to its index", gen_code_case, p_resolve_refuses, no_shrink[CodeCase], show_code_case)
    planted_false[Grid](t, "grid: every plan has at most one step", gen_grid, p_wrong_plan_short, no_shrink[Grid], show_grid)
    planted_false[Grid](t, "grid: every goal is reachable", gen_grid, p_wrong_always_reached, no_shrink[Grid], show_grid)
    planted_false[Grid](t, "grid: the text answer is never a refusal", gen_grid, p_wrong_never_refuses, no_shrink[Grid], show_grid)
    planted_false[CodeCase](t, "codebook: every code is held", gen_code_case, p_wrong_every_code_held, no_shrink[CodeCase], show_code_case)
    planted_false[CodeCase](t, "codebook: every held code has index zero", gen_code_case, p_wrong_index_zero, no_shrink[CodeCase], show_code_case)
    if t.failed == 0:
        print("OK: persona (mojo), " + String(t.total) + " invariants hold")
    else:
        print("FAIL: " + String(t.failed) + " of " + String(t.total) + " invariants failed")
        raise Error("persona gate failed")
