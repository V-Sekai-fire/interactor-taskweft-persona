# SPDX-License-Identifier: MIT
# Persona/Jsonld.lean and Persona/Web.lean: a RECTGTN JSON-LD domain and
# problem in, a plan document out, or a refusal by name. Same search order, same
# refusals, same bytes. EmberJson parses; everything after that is the arena.
from persona.jdoc import *
from persona.khr import Entry, run_graph, lookup_val, lookup_or0, store
from persona.timeutil import *
from persona.guest import quote

comptime NO_TASK = "no-numeric-argument"


# ---- vocabulary --------------------------------------------------------------
@fieldwise_init
struct EnumDef(Copyable, Movable):
    var name: String
    var members: List[Entry]


struct Vocab(Copyable, Movable):
    var names: List[String]
    var enums: List[EnumDef]

    def __init__(out self):
        self.names = List[String]()
        self.enums = List[EnumDef]()


def names_index(v: Vocab, s: String) -> Int:
    for i in range(len(v.names)):
        if v.names[i] == s:
            return i
    return -1


def vocab_of(doc: JDoc, j: Int) -> Vocab:
    """The codebook, and the enums: an object of members with their integers,
    or an array of members numbered from zero."""
    var v = Vocab()
    for x in jitems(doc, jget(doc, j, "codebook")):
        if jis_str(doc, x):
            v.names.append(jstr(doc, x))
    var e = jget(doc, j, "enums")
    if doc.kind[e] == J_OBJ:
        for i in range(len(doc.keys[e])):
            var body = doc.kids[e][i]
            var members = List[Entry]()
            if doc.kind[body] == J_ARR:
                var n = 0
                for m in doc.kids[body]:
                    if jis_str(doc, m):
                        members.append(Entry(jstr(doc, m), n))
                        n += 1
            elif doc.kind[body] == J_OBJ:
                for k in range(len(doc.keys[body])):
                    var x = 0
                    if jint(doc, doc.kids[body][k], x):
                        members.append(Entry(doc.keys[body][k], x))
            v.enums.append(EnumDef(doc.keys[e][i], members^))
    return v^


def vocab_text(text: String) -> Vocab:
    var doc = JDoc()
    var root = 0
    if parse_json(text, doc, root):
        return vocab_of(doc, root)
    return Vocab()


def merge_vocab(d: Vocab, p: Vocab) -> Vocab:
    """A problem's own codebook replaces the domain's; enums add up."""
    var out = Vocab()
    out.names = p.names.copy() if len(p.names) > 0 else d.names.copy()
    for e in d.enums:
        out.enums.append(EnumDef(e.name, e.members.copy()))
    for e in p.enums:
        out.enums.append(EnumDef(e.name, e.members.copy()))
    return out^


def key_of(v: Vocab, k: String) -> String:
    var i = names_index(v, k)
    return String(i) if i >= 0 else k


def member_of(v: Vocab, s: String, mut out: Int) -> Bool:
    """`enum.member`, or `member` when no other enum has it."""
    var parts = List[String]()
    for p in s.split("."):
        parts.append(String(p))
    if len(parts) == 2:
        for e in v.enums:
            if e.name == parts[0]:
                for m in e.members:
                    if m.key == parts[1]:
                        out = m.val
                        return True
                return False
        return False
    if len(parts) == 1:
        var hits = 0
        var val = 0
        for e in v.enums:
            for m in e.members:
                if m.key == parts[0]:
                    hits += 1
                    val = m.val
                    break
        if hits == 1:
            out = val
            return True
    return False


def int_of(doc: JDoc, v: Vocab, j: Int, mut out: Int) -> Bool:
    """An integer, written as a number, a bool or an enum member."""
    if jint(doc, j, out):
        return True
    var b = False
    if jbool(doc, j, b):
        out = 1 if b else 0
        return True
    if jis_str(doc, j):
        var s = jstr(doc, j)
        if member_of(v, s, out):
            return True
        var i = names_index(v, s)
        if i >= 0:
            out = i
            return True
    return False


def int_or(doc: JDoc, v: Vocab, j: Int, dflt: Int) -> Int:
    var out = 0
    if int_of(doc, v, j, out):
        return out
    return dflt


def arg_num(doc: JDoc, v: Vocab, j: Int, mut out: String) -> Bool:
    var i = 0
    if int_of(doc, v, j, i):
        out = String(i)
        return True
    if jis_str(doc, j):
        var k = names_index(v, jstr(doc, j))
        if k >= 0:
            out = String(k)
            return True
    return False


# ---- tasks, actions, alternatives ---------------------------------------------
@fieldwise_init
struct Task(Copyable, Movable):
    var is_goal: Bool
    var name: String
    var args: List[String]


@fieldwise_init
struct Tri(Copyable, Movable):
    var s: String
    var r: String
    var o: String

    def same(self, other: Tri) -> Bool:
        return self.s == other.s and self.r == other.r and self.o == other.o


@fieldwise_init
struct Act(Copyable, Movable):
    var name: String
    var params: List[String]
    var param_enum: List[String]
    var param_enum_set: List[Bool]
    var raw: Int
    var dur: Int
    var has_start: Bool
    var start: Int
    var has_end: Bool
    var end: Int
    var evals: List[Tri]
    var holds: List[Entry]
    var eqs: List[Entry]
    var sets: List[Entry]


@fieldwise_init
struct Alt(Copyable, Movable):
    var eqs: List[Entry]
    var graph: Int  # arena node, or -1
    var params: List[String]
    var raw: Int
    var checks: List[Entry]
    var tasks: List[Task]


@fieldwise_init
struct Meth(Copyable, Movable):
    var name: String
    var alts: List[Alt]


struct Spec(Movable):
    var acts: List[Act]
    var methods: List[Meth]
    var init: List[Entry]
    var vocab: Vocab

    def __init__(out self):
        self.acts = List[Act]()
        self.methods = List[Meth]()
        self.init = List[Entry]()
        self.vocab = Vocab()


def parse_task(doc: JDoc, v: Vocab, j: Int) -> Task:
    var it = jitems(doc, j)
    if len(it) >= 2:
        if jstr(doc, it[0]) == "goal":
            return Task(True, jstr(doc, it[1]), List[String]())
        var args = List[String]()
        for k in range(1, len(it)):
            var a = String()
            if not arg_num(doc, v, it[k], a):
                return Task(False, NO_TASK, List[String]())
            args.append(a^)
        return Task(False, jstr(doc, it[0]), args^)
    if len(it) == 1:
        return Task(False, jstr(doc, it[0]), List[String]())
    return Task(False, "", List[String]())


def hold_of(doc: JDoc, v: Vocab, e: Int, mut key: String, mut val: Int) -> Bool:
    """`pointer/ge`, or `math/ge` over a `pointer/get`."""
    var ty = jstr(doc, jget(doc, e, "type"))
    if ty == "pointer/ge":
        key = jstr(doc, jget(doc, e, "pointer"))
        val = int_or(doc, v, jget(doc, e, "value"), 1)
        return True
    if ty == "math/ge":
        key = jstr(doc, jget(doc, jget(doc, e, "a"), "pointer"))
        val = int_or(doc, v, jget(doc, e, "b"), 1)
        return True
    return False


def eq_of(doc: JDoc, v: Vocab, e: Int, mut key: String, mut val: Int) -> Bool:
    """`math/eq` over a `pointer/get` and a number."""
    if jstr(doc, jget(doc, e, "type")) == "math/eq":
        key = jstr(doc, jget(doc, jget(doc, e, "a"), "pointer"))
        val = int_or(doc, v, jget(doc, e, "b"), 0)
        return True
    return False


def dur_of(doc: JDoc, j: Int) -> Int:
    var secs = 0
    if parse_duration(jstr(doc, jget(doc, j, "duration")), secs):
        return secs
    var a = 0
    var b = 0
    if parse_stamp(jstr(doc, jget(doc, j, "start")), a) and parse_stamp(jstr(doc, jget(doc, j, "end")), b):
        return monus(b, a)
    return 0


def param_name(doc: JDoc, j: Int) -> String:
    if jis_str(doc, j):
        return jstr(doc, j)
    return jstr(doc, jget(doc, j, "name"))


def parse_act(doc: JDoc, v: Vocab, name: String, j: Int) -> Act:
    var body = jitems(doc, jget(doc, j, "body"))
    var params = List[String]()
    var penum = List[String]()
    var penum_set = List[Bool]()
    for p in jitems(doc, jget(doc, j, "params")):
        params.append(param_name(doc, p))
        var en = jget(doc, p, "enum")
        penum.append(jstr(doc, en))
        penum_set.append(jis_str(doc, en))
    var st = 0
    var en_ = 0
    var has_start = parse_stamp(jstr(doc, jget(doc, j, "start")), st)
    var has_end = parse_stamp(jstr(doc, jget(doc, j, "end")), en_)
    var evals = List[Tri]()
    var holds = List[Entry]()
    var eqs = List[Entry]()
    var sets = List[Entry]()
    for b in body:
        var e = jget(doc, b, "eval")
        if jstr(doc, jget(doc, e, "type")) == "rebac/check":
            evals.append(Tri(jstr(doc, jget(doc, e, "subject")), jstr(doc, jget(doc, e, "rel")), jstr(doc, jget(doc, e, "object"))))
        var k = String()
        var x = 0
        if hold_of(doc, v, e, k, x):
            holds.append(Entry(k, x))
        if eq_of(doc, v, e, k, x):
            eqs.append(Entry(k, x))
        if jhas(doc, b, "pointer/set"):
            sets.append(Entry(jstr(doc, jget(doc, b, "pointer/set")), int_or(doc, v, jget(doc, b, "value"), 0)))
    return Act(name, params^, penum^, penum_set^, j, dur_of(doc, j), has_start, st, has_end, en_, evals^, holds^, eqs^, sets^)


def parse_alt(doc: JDoc, v: Vocab, params: List[String], alt: Int) -> Alt:
    var checks = List[Entry]()
    var eqs = List[Entry]()
    for c in jitems(doc, jget(doc, alt, "check")):
        var k = String()
        var x = 0
        if eq_of(doc, v, jget(doc, c, "eval"), k, x):
            eqs.append(Entry(k, x))
    for c in jitems(doc, jget(doc, alt, "check")):
        var k = String()
        var x = 0
        if hold_of(doc, v, jget(doc, c, "eval"), k, x):
            checks.append(Entry(k, x))
    var tasks = List[Task]()
    for t in jitems(doc, jget(doc, alt, "subtasks")):
        tasks.append(parse_task(doc, v, t))
    var g = jget(doc, alt, "graph") if jhas(doc, alt, "graph") else -1
    return Alt(eqs^, g, params.copy(), alt, checks^, tasks^)


# ---- substitution -------------------------------------------------------------
def to_int_text(s: String, mut out: Int) -> Bool:
    var b = s.as_bytes()
    var i = 0
    var neg = False
    if len(b) > 0 and b[0] == 45:
        neg = True
        i = 1
    if i >= len(b):
        return False
    var n = 0
    while i < len(b):
        if b[i] < 48 or b[i] > 57:
            return False
        n = n * 10 + Int(b[i]) - 48
        i += 1
    out = -n if neg else n
    return True


def subst_str(env_k: List[String], env_v: List[String], s: String) -> String:
    var acc = s
    for i in range(len(env_k)):
        acc = acc.replace("[" + env_k[i] + "]", env_v[i])
    return acc^


def subst_json(mut doc: JDoc, env_k: List[String], env_v: List[String], j: Int) -> Int:
    """`[name]` replaced by its argument in every string, and `{"param": name}`
    by its number."""
    var kind = doc.kind[j]
    if kind == J_STR:
        return doc.add(J_STR, 0, subst_str(env_k, env_v, doc.text[j]))
    if kind == J_ARR:
        var kids = List[Int]()
        var old = doc.kids[j].copy()
        for c in old:
            kids.append(subst_json(doc, env_k, env_v, c))
        return doc.add_arr(kids^)
    if kind == J_OBJ:
        var keys = doc.keys[j].copy()
        var old = doc.kids[j].copy()
        if len(keys) == 1 and keys[0] == "param":
            var p = jstr(doc, old[0])
            for i in range(len(env_k)):
                if env_k[i] == p:
                    var n = 0
                    if to_int_text(env_v[i], n):
                        return doc.add(J_INT, n, "")
                    return j
            return j
        var kids = List[Int]()
        for c in old:
            kids.append(subst_json(doc, env_k, env_v, c))
        return doc.add_obj(keys^, kids^)
    return j


def without_graph(mut doc: JDoc, j: Int) -> Int:
    var keys = List[String]()
    var kids = List[Int]()
    if doc.kind[j] == J_OBJ:
        for i in range(len(doc.keys[j])):
            if doc.keys[j][i] != "graph":
                keys.append(doc.keys[j][i])
                kids.append(doc.kids[j][i])
    return doc.add_obj(keys^, kids^)


def with_graph(mut doc: JDoc, g: Int, j: Int) -> Int:
    if g < 0:
        return j
    var keys = List[String]()
    var kids = List[Int]()
    if doc.kind[j] == J_OBJ:
        keys = doc.keys[j].copy()
        kids = doc.kids[j].copy()
    keys.append("graph")
    kids.append(g)
    return doc.add_obj(keys^, kids^)


def inst_act(mut doc: JDoc, v: Vocab, a: Act, args: List[String], mut out: Act) -> Bool:
    if len(a.params) != len(args):
        return False
    if len(a.params) == 0:
        out = a.copy()
        return True
    out = parse_act(doc, v, a.name, subst_json(doc, a.params, args, a.raw))
    return True


def inst_alt(mut doc: JDoc, v: Vocab, a: Alt, args: List[String], mut out: Alt) -> Bool:
    if len(a.params) != len(args):
        return False
    if len(a.params) == 0:
        out = a.copy()
        return True
    var sub = subst_json(doc, a.params, args, without_graph(doc, a.raw))
    out = parse_alt(doc, v, List[String](), with_graph(doc, a.graph, sub))
    return True


def step_key(n: String, args: List[String]) -> String:
    if len(args) == 0:
        return n
    var s = n + "("
    for i in range(len(args)):
        s += ("," if i > 0 else "") + args[i]
    return s + ")"


def split_key(k: String, mut name: String, mut args: List[String]):
    var parts = List[String]()
    for p in k.split("("):
        parts.append(String(p))
    args = List[String]()
    if len(parts) <= 1:
        name = k
        return
    name = parts[0]
    var joined = String()
    for i in range(1, len(parts)):
        joined += ("(" if i > 1 else "") + parts[i]
    var inner = String(joined[byte=0 : joined.byte_length() - 1]) if joined.byte_length() > 0 else String()
    for a in inner.split(","):
        args.append(String(a))


# ---- documents ---------------------------------------------------------------
def parse_domain(mut doc: JDoc, j: Int) -> Spec:
    var sp = Spec()
    sp.vocab = vocab_of(doc, j)
    var voc = sp.vocab.copy()
    for v in jitems(doc, jget(doc, j, "variables")):
        var init = jget(doc, v, "init")
        if doc.kind[init] == J_OBJ:
            for i in range(len(doc.keys[init])):
                sp.init.append(Entry("/" + jstr(doc, jget(doc, v, "name")) + "/" + key_of(voc, doc.keys[init][i]), int_or(doc, voc, doc.kids[init][i], 0)))
    var acts = jget(doc, j, "actions")
    if doc.kind[acts] == J_OBJ:
        for i in range(len(doc.keys[acts])):
            sp.acts.append(parse_act(doc, voc, doc.keys[acts][i], doc.kids[acts][i]))
    var ms = jget(doc, j, "methods")
    if doc.kind[ms] == J_OBJ:
        for i in range(len(doc.keys[ms])):
            var m = doc.kids[ms][i]
            var params = List[String]()
            for p in jitems(doc, jget(doc, m, "params")):
                params.append(param_name(doc, p))
            var alts = List[Alt]()
            for a in jitems(doc, jget(doc, m, "alternatives")):
                alts.append(parse_alt(doc, voc, params, a))
            sp.methods.append(Meth(doc.keys[ms][i], alts^))
    return sp^


struct Problem(Movable):
    var name: String
    var init: List[Entry]
    var edges: List[Tri]
    var goals: List[String]
    var calls: List[Task]
    var origin: String

    def __init__(out self):
        self.name = String()
        self.init = List[Entry]()
        self.edges = List[Tri]()
        self.goals = List[String]()
        self.calls = List[Task]()
        self.origin = String()


def parse_problem(doc: JDoc, j: Int, voc: Vocab) -> Problem:
    var pb = Problem()
    pb.name = jstr(doc, jget(doc, j, "name"))
    pb.origin = jstr(doc, jget(doc, j, "origin"))
    for v in jitems(doc, jget(doc, j, "variables")):
        var init = jget(doc, v, "init")
        if doc.kind[init] == J_OBJ:
            for i in range(len(doc.keys[init])):
                pb.init.append(Entry("/" + jstr(doc, jget(doc, v, "name")) + "/" + key_of(voc, doc.keys[init][i]), int_or(doc, voc, doc.kids[init][i], 0)))
    for e in jitems(doc, jget(doc, jget(doc, jget(doc, j, "capabilities"), "graph"), "edges")):
        pb.edges.append(Tri(jstr(doc, jget(doc, e, "subject")), jstr(doc, jget(doc, e, "rel")), jstr(doc, jget(doc, e, "object"))))
    var todo = jitems(doc, jget(doc, j, "todo_list"))
    for t in todo:
        for g in jitems(doc, jget(doc, t, "goal")):
            pb.goals.append(jstr(doc, jget(doc, g, "pointer")))
    for t in todo:
        var it = jitems(doc, t)
        if len(it) == 0:
            continue
        var args = List[String]()
        var all_ok = True
        for k in range(1, len(it)):
            var a = String()
            if arg_num(doc, voc, it[k], a):
                args.append(a^)
            else:
                all_ok = False
        if all_ok:
            pb.calls.append(Task(False, jstr(doc, it[0]), args^))
        else:
            pb.calls.append(Task(False, NO_TASK, List[String]()))
    return pb^


# ---- the search ----------------------------------------------------------------
struct St(Copyable, Movable):
    var vals: List[Entry]
    var edges: List[Tri]
    var plan: List[String]

    def __init__(out self, var vals: List[Entry], var edges: List[Tri]):
        self.vals = vals^
        self.edges = edges^
        self.plan = List[String]()


@fieldwise_init
struct TF(Copyable, Movable):
    var task: Task
    var fuel: Int


def holds_all(vals: List[Entry], hs: List[Entry]) -> Bool:
    for h in hs:
        if lookup_or0(vals, h.key) < h.val:
            return False
    return True


def eqs_all(vals: List[Entry], hs: List[Entry]) -> Bool:
    for h in hs:
        if lookup_or0(vals, h.key) != h.val:
            return False
    return True


def expand_alt(mut doc: JDoc, v: Vocab, alt0: Alt, args: List[String], vals: List[Entry], mut tasks: List[Task]) -> Bool:
    """The tasks an alternative gives on the state `vals`, or False when it does
    not apply. A graph runs first; one that cannot run makes it not apply."""
    var alt = alt0.copy()
    if not inst_alt(doc, v, alt0, args, alt):
        return False
    if alt.graph < 0:
        if holds_all(vals, alt.checks) and eqs_all(vals, alt.eqs):
            tasks = alt.tasks.copy()
            return True
        return False
    var inputs = List[Entry]()
    for i in range(min(len(alt0.params), len(args))):
        var n = 0
        if to_int_text(args[i], n):
            inputs.append(Entry(alt0.params[i], n))
    var gv = List[Entry]()
    try:
        run_graph(doc, alt.graph, vals, inputs, gv)
    except:
        return False
    var vals_g = vals.copy()
    var env_k = List[String]()
    var env_v = List[String]()
    for e in gv:
        vals_g.append(Entry("/graph/" + e.key, e.val))
        env_k.append(e.key)
        env_v.append(String(e.val))
    var alt2 = parse_alt(doc, v, List[String](), subst_json(doc, env_k, env_v, without_graph(doc, alt.raw)))
    if holds_all(vals_g, alt2.checks) and eqs_all(vals_g, alt2.eqs):
        tasks = alt2.tasks.copy()
        return True
    return False


def find_method(sp: Spec, name: String) -> Int:
    for i in range(len(sp.methods)):
        if sp.methods[i].name == name:
            return i
    return -1


def find_act(sp: Spec, name: String) -> Int:
    for i in range(len(sp.acts)):
        if sp.acts[i].name == name:
            return i
    return -1


def has_edge(edges: List[Tri], e: Tri) -> Bool:
    for x in edges:
        if x.same(e):
            return True
    return False


def run_alts(mut doc: JDoc, sp: Spec, bound: Int, m: Int, args: List[String], fuel: Int, rest: List[TF], s: St, mut res: St) -> Bool:
    """The first alternative whose subtasks all succeed in order."""
    var alts = sp.methods[m].alts.copy()
    for alt0 in alts:
        var tasks = List[Task]()
        if not expand_alt(doc, sp.vocab, alt0, args, s.vals, tasks):
            continue
        var stack = List[TF]()
        for t in tasks:
            stack.append(TF(t.copy(), fuel))
        for r in rest:
            stack.append(r.copy())
        if run(doc, sp, bound, stack, s, res):
            return True
    return False


def run(mut doc: JDoc, sp: Spec, bound: Int, stack: List[TF], s: St, mut res: St) -> Bool:
    if len(stack) == 0:
        res = s.copy()
        return True
    var head = stack[0].copy()
    var rest = List[TF]()
    for i in range(1, len(stack)):
        rest.append(stack[i].copy())
    if not head.task.is_goal:
        var n = head.task.name
        var m = find_method(sp, n)
        if m >= 0:
            if head.fuel == 0:
                return False
            return run_alts(doc, sp, bound, m, head.task.args, head.fuel - 1, rest, s, res)
        var ai = find_act(sp, n)
        if ai < 0:
            return False
        var a = sp.acts[ai].copy()
        if not inst_act(doc, sp.vocab, sp.acts[ai], head.task.args, a):
            return False
        if len(s.plan) < bound:
            var ok = True
            for e in a.evals:
                if not has_edge(s.edges, e):
                    ok = False
            if ok and holds_all(s.vals, a.holds) and eqs_all(s.vals, a.eqs):
                var s2 = s.copy()
                for w in a.sets:
                    store(s2.vals, w.key, w.val)
                s2.plan.append(step_key(n, head.task.args))
                return run(doc, sp, bound, rest, s2, res)
        return False
    var p = head.task.name
    if lookup_or0(s.vals, p) >= 1:
        return run(doc, sp, bound, rest, s, res)
    if head.fuel == 0:
        return False
    var m = find_method(sp, p)
    if m < 0:
        return False
    return run_alts(doc, sp, bound, m, List[String](), head.fuel - 1, rest, s, res)


# ---- the plan document --------------------------------------------------------
def readable(sp: Spec, names: List[String], k: String) -> List[String]:
    """A step's arguments as they read: an enum member's name, else the number."""
    var n = String()
    var args = List[String]()
    split_key(k, n, args)
    var ai = find_act(sp, n)
    if ai < 0:
        return args^
    var out = List[String]()
    for i in range(len(args)):
        var x = args[i]
        var en = String()
        var has = False
        if i < len(sp.acts[ai].param_enum):
            en = sp.acts[ai].param_enum[i]
            has = sp.acts[ai].param_enum_set[i]
        var iv = 0
        if has and to_int_text(x, iv):
            if en == "codebook":
                var idx = iv if iv > 0 else 0
                out.append(names[idx] if idx < len(names) else x)
                continue
            var named = x
            for e in sp.vocab.enums:
                if e.name == en:
                    for m in e.members:
                        if m.val == iv:
                            named = m.key
                            break
                    break
            out.append(named)
            continue
        out.append(x)
    return out^


def doc_name(text: String) -> String:
    var doc = JDoc()
    var root = 0
    if parse_json(text, doc, root):
        return jstr(doc, jget(doc, root, "name"))
    return String()


comptime VSEKAI = "\"@context\":{\"VSEKAI\":\"https://v-sekai.org/\",\"domain\":\"VSEKAI:planning/domain/\"}"


def refusal(domain: String, problem: String, why: String) -> String:
    return "{" + VSEKAI + ",\"@type\":\"domain:Plan\",\"domain\":" + quote(domain) + ",\"problem\":" + quote(problem) + ",\"refused\":" + quote(why) + "}"


def field(name: String, has: Bool, value: String) -> String:
    if has:
        return ",\"" + name + "\":" + quote(value)
    return String()


def _contains(xs: List[String], s: String) -> Bool:
    for x in xs:
        if x == s:
            return True
    return False


def plan_of(domain: String, problem: String, only_set: Bool = False, only: String = "", bound: Int = 1000000) -> String:
    var dn = doc_name(domain)
    var pn = doc_name(problem)
    var voc = merge_vocab(vocab_text(domain), vocab_text(problem))
    var ddoc = JDoc()
    var dj = 0
    if not parse_json(domain, ddoc, dj):
        return refusal(dn, pn, "bad_domain")
    var pdoc = JDoc()
    var pj = 0
    if not parse_json(problem, pdoc, pj):
        return refusal(dn, pn, "bad_problem")
    var sp = parse_domain(ddoc, dj)
    var pb = parse_problem(pdoc, pj, voc)
    if only_set:
        pb.goals = List[String]()
        pb.goals.append(only)
    var known = List[String]()
    for e in sp.init:
        known.append(e.key)
    for e in pb.init:
        known.append(e.key)
    if len(pb.goals) == 0 and len(pb.calls) == 0:
        return refusal(dn, pn, "no_goal")
    var undeclared = False
    for g in pb.goals:
        if not _contains(known, g):
            undeclared = True
    for c in pb.calls:
        if find_method(sp, c.name) < 0 and find_act(sp, c.name) < 0:
            undeclared = True
    if undeclared:
        return refusal(dn, pn, "undeclared_goal")
    var vals = sp.init.copy()
    for w in pb.init:
        store(vals, w.key, w.val)
    var start = St(vals^, pb.edges.copy())
    var fuel = len(sp.methods) + 1000
    var stack = List[TF]()
    for g in pb.goals:
        stack.append(TF(Task(True, g, List[String]()), fuel))
    for c in pb.calls:
        stack.append(TF(c.copy(), fuel))
    var s = start.copy()
    if not run(ddoc, sp, bound, stack, start, s):
        return refusal(dn, pn, "unreachable")
    var ok = True
    for g in pb.goals:
        if lookup_or0(s.vals, g) < 1:
            ok = False
    # the distinct steps, in the order they first appear
    var firsts = List[String]()
    for n in s.plan:
        if not _contains(firsts, n):
            firsts.append(n)
    var acts = List[Act]()
    var found = List[Bool]()
    for k in firsts:
        var nm = String()
        var args = List[String]()
        split_key(k, nm, args)
        var ai = find_act(sp, nm)
        var a = Act(nm, List[String](), List[String](), List[Bool](), 0, 0, False, 0, False, 0, List[Tri](), List[Entry](), List[Entry](), List[Entry]())
        var f = False
        if ai >= 0:
            f = inst_act(ddoc, sp.vocab, sp.acts[ai], args, a)
        acts.append(a^)
        found.append(f)
    var origin = 0
    var has_origin = parse_stamp(pb.origin, origin)
    if not has_origin:
        var any = False
        for i in range(len(firsts)):
            if found[i] and acts[i].has_start:
                if not any or acts[i].start < origin:
                    origin = acts[i].start
                any = True
        has_origin = any
    # schedule: each step starts when every earlier step that sets a fact it needs has ended
    var sb = List[Int]()
    var se = List[Int]()
    var total = 0
    for i in range(len(firsts)):
        if not found[i]:
            sb.append(0)
            se.append(0)
            continue
        var release = 0
        if has_origin and acts[i].has_start:
            release = monus(acts[i].start, origin)
        var st = release
        for k in range(i):
            if found[k]:
                var dep = False
                for w in acts[k].sets:
                    for h in acts[i].holds:
                        if h.key == w.key:
                            dep = True
                    for h in acts[i].eqs:
                        if h.key == w.key:
                            dep = True
                if dep and se[k] > st:
                    st = se[k]
        sb.append(st)
        se.append(st + acts[i].dur)
    for e in se:
        if e > total:
            total = e
    # the last possible start and end of each step that still lets the plan finish at `total`
    var lb = List[Int]()
    var le = List[Int]()
    for _ in range(len(firsts)):
        lb.append(0)
        le.append(0)
    for ii in range(len(firsts)):
        var i = len(firsts) - 1 - ii
        var d = acts[i].dur if found[i] else 0
        var fin = total
        if has_origin and found[i] and acts[i].has_end:
            fin = min(total, monus(acts[i].end, origin))
        for k in range(len(firsts)):
            if k > i and found[i] and found[k]:
                var dep = False
                for w in acts[i].sets:
                    for h in acts[k].holds:
                        if h.key == w.key:
                            dep = True
                if dep:
                    fin = min(fin, lb[k])
        lb[i] = monus(fin, d)
        le[i] = fin
    var consistent = True
    for i in range(len(firsts)):
        if has_origin and found[i] and acts[i].has_end:
            if not (se[i] + origin <= acts[i].end):
                consistent = False
    var rows = String()
    var seen = List[String]()
    for n in s.plan:
        var b = 0
        var e = 0
        var at = -1
        for i in range(len(firsts)):
            if firsts[i] == n:
                at = i
                break
        if _contains(seen, n):
            b = lb[at]
            e = le[at]
        else:
            b = sb[at]
            e = se[at]
        seen.append(n)
        var nm = String()
        var args = List[String]()
        split_key(n, nm, args)
        var ps = String()
        var rd = readable(sp, voc.names, n)
        for i in range(len(rd)):
            ps += ("," if i > 0 else "") + quote(rd[i])
        rows += ("," if len(seen) > 1 else "") + "{\"action\":" + quote(nm) + ",\"params\":[" + ps + "]"
        rows += field("start", has_origin, fmt_stamp(origin + b)) + field("end", has_origin, fmt_stamp(origin + e))
        rows += ",\"duration\":" + quote(fmt_dur(monus(e, b))) + "}"
    return (
        "{" + VSEKAI + ",\"@type\":\"domain:Plan\",\"name\":" + quote(pn + "_plan")
        + ",\"domain\":" + quote(dn) + ",\"problem\":" + quote(pn)
        + ",\"reached\":" + ("true" if ok else "false")
        + ",\"temporal\":{\"consistent\":" + ("true" if consistent else "false")
        + field("origin", has_origin, fmt_stamp(origin)) + ",\"total\":" + quote(fmt_dur(total)) + "}"
        + ",\"steps\":[" + rows + "]}"
    )


def shortest_of(domain: String, problem: String, max_bound: Int) -> String:
    """The plan with the fewest actions: plan with a rising bound on the
    actions until one is found."""
    var free = plan_of(domain, problem)
    if "\"refused\"" in free:
        return free
    for b in range(max_bound + 1):
        var r = plan_of(domain, problem, False, "", b)
        if not ("\"refused\"" in r) and "\"reached\":true" in r:
            return String(r[byte=0 : r.byte_length() - 1]) + ",\"optimal\":true,\"length\":" + String(b) + "}"
    return refusal(doc_name(domain), doc_name(problem), "limit")


# ---- Persona/Web.lean ---------------------------------------------------------
def goals_of(domain: String, problem: String) -> String:
    var voc = merge_vocab(vocab_text(domain), vocab_text(problem))
    var ddoc = JDoc()
    var dj = 0
    if not parse_json(domain, ddoc, dj):
        return "{\"refused\":\"bad_domain\"}"
    var pdoc = JDoc()
    var pj = 0
    if not parse_json(problem, pdoc, pj):
        return "{\"refused\":\"bad_problem\"}"
    var sp = parse_domain(ddoc, dj)
    var pb = parse_problem(pdoc, pj, voc)
    var known = sp.init.copy()
    for e in pb.init:
        known.append(e.copy())
    var out = String()
    for i in range(len(pb.goals)):
        var g = pb.goals[i]
        var declared = False
        for e in known:
            if e.key == g:
                declared = True
        out += ("," if i > 0 else "") + "{\"goal\":" + quote(g) + ",\"declared\":" + ("true" if declared else "false")
        out += ",\"held\":" + ("true" if lookup_or0(known, g) >= 1 else "false") + "}"
    return "{\"problem\":" + quote(pb.name) + ",\"actions\":" + String(len(sp.acts)) + ",\"methods\":" + String(len(sp.methods)) + ",\"goals\":[" + out + "]}"


def plan_with(domain: String, problem: String, goal: String) -> String:
    return plan_of(domain, problem, goal != "", goal)
