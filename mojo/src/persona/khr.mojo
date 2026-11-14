# SPDX-License-Identifier: MIT
# Persona/Khr.lean: a subset of KHR_interactivity run against the planner's
# state. Values are typed: an `int` is a 32-bit two's complement integer that
# wraps, and a `bool` is its own type. A graph with a node it does not build is
# rejected whole, and a run that spends its fuel is refused. Every error text is
# the Lean text, so a test can match the same reason.
from persona.jdoc import *


@fieldwise_init
struct V(Copyable, Movable):
    var is_bool: Bool
    var n: Int  # the int32 value, or 0/1 for a bool


@fieldwise_init
struct Entry(Copyable, Movable):
    var key: String
    var val: Int


@fieldwise_init
struct IdxE(Copyable, Movable):
    var node: Int
    var val: Int


struct KRun(Copyable, Movable):
    var vars: List[V]
    var vals: List[Entry]
    var idx: List[IdxE]
    var fuel: Int

    def __init__(out self, var vars: List[V], var vals: List[Entry], fuel: Int):
        self.vars = vars^
        self.vals = vals^
        self.idx = List[IdxE]()
        self.fuel = fuel


def wrap32(x: Int) -> Int:
    var y = x & 0xFFFFFFFF
    return y - 4294967296 if y >= 2147483648 else y


def vint(n: Int) -> V:
    return V(False, wrap32(n))


def vbool(b: Bool) -> V:
    return V(True, 1 if b else 0)


def lookup_val(vals: List[Entry], p: String, mut out: Int) -> Bool:
    for e in vals:
        if e.key == p:
            out = e.val
            return True
    return False


def lookup_or0(vals: List[Entry], p: String) -> Int:
    var out = 0
    if lookup_val(vals, p, out):
        return out
    return 0


def store(mut vals: List[Entry], p: String, v: Int):
    for i in range(len(vals)):
        if vals[i].key == p:
            vals[i] = Entry(p, v)
            return
    vals.append(Entry(p, v))


def idx_get(r: KRun, n: Int, mut out: Int) -> Bool:
    for e in r.idx:
        if e.node == n:
            out = e.val
            return True
    return False


def idx_set(mut r: KRun, n: Int, v: Int):
    var keep = List[IdxE]()
    for e in r.idx:
        if e.node != n:
            keep.append(IdxE(e.node, e.val))
    keep.append(IdxE(n, v))
    r.idx = keep^


# ---- the graph ------------------------------------------------------------
def node_of(doc: JDoc, g: Int, n: Int) -> Int:
    return jnth(doc, jget(doc, g, "nodes"), n)


def op_of(doc: JDoc, g: Int, n: Int) -> String:
    var d = jnat_or(doc, jget(doc, node_of(doc, g, n), "declaration"), 0)
    return jstr(doc, jget(doc, jnth(doc, jget(doc, g, "declarations"), d), "op"))


def config(doc: JDoc, g: Int, n: Int, k: String) -> Int:
    """A configuration value: the first element of its `value` array."""
    var c = jget(doc, jget(doc, node_of(doc, g, n), "configuration"), k)
    return jfirst(doc, jget(doc, c, "value"))


def fits(i: Int) -> Bool:
    return -2147483648 <= i and i <= 2147483647


def ty_sig(doc: JDoc, g: Int, t: Int) raises -> String:
    var sig = jstr(doc, jget(doc, jnth(doc, jget(doc, g, "types"), t), "signature"))
    if sig == "int" or sig == "bool":
        return sig
    if sig == "":
        raise Error("a type index outside the types array")
    raise Error("the type " + sig + " is not built")


def literal_typed(doc: JDoc, g: Int, t: Int, x: Int) raises -> V:
    var sig = ty_sig(doc, g, t)
    if sig == "bool":
        var b = False
        if jbool(doc, x, b):
            return vbool(b)
        raise Error("a bool literal that is not true or false")
    var i = 0
    if jint(doc, x, i):
        if fits(i):
            return vint(i)
        raise Error("an int literal outside 32 bits")
    raise Error("an int literal that is not an integer")


def literal(doc: JDoc, g: Int, rf: Int) raises -> V:
    var t = 0
    if not jnat(doc, jget(doc, rf, "type"), t):
        raise Error("a literal value socket without a type")
    return literal_typed(doc, g, t, jfirst(doc, jget(doc, rf, "value")))


def as_int(v: V) raises -> Int:
    if v.is_bool:
        raise Error("a bool where an int is expected")
    return v.n


def as_bool(v: V) raises -> Bool:
    if not v.is_bool:
        raise Error("an int where a bool is expected")
    return v.n == 1


def input(doc: JDoc, g: Int, r: KRun, n: Int, name: String) raises -> V:
    var rf = jget(doc, jget(doc, node_of(doc, g, n), "values"), name)
    if doc.kind[rf] == J_NULL:
        raise Error("the node " + op_of(doc, g, n) + " lacks the input value socket " + name)
    return eval_ref(doc, g, r, rf)


def eval_ref(doc: JDoc, g: Int, r: KRun, rf: Int) raises -> V:
    var n = 0
    if jnat(doc, jget(doc, rf, "node"), n):
        return eval_node(doc, g, r, n, jstr(doc, jget(doc, rf, "socket")))
    return literal(doc, g, rf)


def pointer_of(doc: JDoc, g: Int, r: KRun, n: Int) raises -> String:
    """Each `[name]` path segment is its integer input value socket."""
    var path = jstr(doc, config(doc, g, n, "pointer"))
    var out = String()
    var first = True
    for seg_s in path.split("/"):
        var seg = String(seg_s)
        var piece: String
        if seg.startswith("{"):
            raise Error("reference template parameters are not built")
        elif seg.startswith("[") and seg.endswith("]") and seg.count_codepoints() > 2:
            var name = String(seg[byte=1 : seg.byte_length() - 1])
            piece = String(as_int(input(doc, g, r, n, name)))
        else:
            piece = seg
        out += piece if first else "/" + piece
        first = False
    return out^


def _cases(doc: JDoc, g: Int, n: Int) -> List[Int]:
    var out = List[Int]()
    var c = jget(doc, jget(doc, jget(doc, node_of(doc, g, n), "configuration"), "cases"), "value")
    for x in jitems(doc, c):
        var i = 0
        if jint(doc, x, i):
            out.append(i)
    return out^


def _contains(xs: List[Int], v: Int) -> Bool:
    for x in xs:
        if x == v:
            return True
    return False


def eval_node(doc: JDoc, g: Int, r: KRun, n: Int, socket: String) raises -> V:
    var op = op_of(doc, g, n)
    if op == "math/add" or op == "math/sub" or op == "math/mul" or op == "math/min" or op == "math/max" or op == "math/lt" or op == "math/le" or op == "math/gt" or op == "math/ge":
        var a = as_int(input(doc, g, r, n, "a"))
        var b = as_int(input(doc, g, r, n, "b"))
        if op == "math/add":
            return vint(a + b)
        if op == "math/sub":
            return vint(a - b)
        if op == "math/mul":
            return vint(a * b)
        if op == "math/min":
            return vint(a if a <= b else b)
        if op == "math/max":
            return vint(a if a >= b else b)
        if op == "math/lt":
            return vbool(a < b)
        if op == "math/le":
            return vbool(a <= b)
        if op == "math/gt":
            return vbool(a > b)
        return vbool(a >= b)
    if op == "math/neg":
        return vint(-as_int(input(doc, g, r, n, "a")))
    if op == "math/abs":
        var a = as_int(input(doc, g, r, n, "a"))
        return vint(-a if a < 0 else a)
    if op == "math/eq" or op == "math/and" or op == "math/or" or op == "math/xor":
        var a = input(doc, g, r, n, "a")
        var b = input(doc, g, r, n, "b")
        if a.is_bool != b.is_bool:
            if op == "math/eq":
                raise Error("math/eq compares two values of one type")
            raise Error(op + " takes two values of one type")
        if op == "math/eq":
            return vbool(a.n == b.n)
        if a.is_bool:
            if op == "math/and":
                return vbool(a.n == 1 and b.n == 1)
            if op == "math/or":
                return vbool(a.n == 1 or b.n == 1)
            return vbool(a.n != b.n)
        if op == "math/and":
            return vint(a.n & b.n)
        if op == "math/or":
            return vint(a.n | b.n)
        return vint(a.n ^ b.n)
    if op == "math/not":
        var a = input(doc, g, r, n, "a")
        if a.is_bool:
            return vbool(a.n != 1)
        return vint(~a.n)
    if op == "math/select":
        if as_bool(input(doc, g, r, n, "condition")):
            return input(doc, g, r, n, "a")
        return input(doc, g, r, n, "b")
    if op == "math/switch":
        var sel = as_int(input(doc, g, r, n, "selection"))
        if _contains(_cases(doc, g, n), sel):
            return input(doc, g, r, n, String(sel))
        return input(doc, g, r, n, "default")
    if op == "type/boolToInt":
        return vint(1 if as_bool(input(doc, g, r, n, "a")) else 0)
    if op == "type/intToBool":
        return vbool(as_int(input(doc, g, r, n, "a")) != 0)
    if op == "variable/get":
        var i = jnat_or(doc, config(doc, g, n, "variable"), 0)
        if i < len(r.vars):
            return r.vars[i].copy()
        return vint(0)
    if op == "pointer/get":
        var p = pointer_of(doc, g, r, n)
        var t = jnat_or(doc, config(doc, g, n, "type"), 0)
        var sig = ty_sig(doc, g, t)
        var x = 0
        var found = lookup_val(r.vals, p, x)
        if socket == "value":
            if found:
                return vbool(x != 0) if sig == "bool" else vint(x)
            return vbool(False) if sig == "bool" else vint(0)
        if socket == "isValid":
            return vbool(found)
        raise Error("pointer/get has the output value sockets value and isValid")
    if op == "flow/for":
        var init = 0
        _ = jint(doc, config(doc, g, n, "initialIndex"), init)
        var cur = 0
        if idx_get(r, n, cur):
            return V(False, cur)
        return vint(init)
    raise Error("the node " + op + " is not built")


def validate(doc: JDoc, g: Int) raises:
    """The nodes and configuration the interpreter builds, over the whole
    graph before a run."""
    var built = [
        "event/onStart", "flow/sequence", "flow/branch", "flow/switch", "flow/for", "flow/while",
        "variable/get", "variable/set", "pointer/get", "pointer/set", "math/add", "math/sub", "math/mul",
        "math/neg", "math/abs", "math/min", "math/max", "math/eq", "math/lt", "math/le", "math/gt", "math/ge",
        "math/and", "math/or", "math/xor", "math/not", "math/select", "math/switch", "type/boolToInt",
        "type/intToBool",
    ]
    var nvars = jlen(doc, jget(doc, g, "variables"))
    for t in range(jlen(doc, jget(doc, g, "types"))):
        _ = ty_sig(doc, g, t)
    for n in range(jlen(doc, jget(doc, g, "nodes"))):
        var op = op_of(doc, g, n)
        var ok = False
        for b in built:
            if b == op:
                ok = True
        if not ok:
            raise Error("the node " + op + " is not built")
        if op == "variable/get":
            if not (jnat_or(doc, config(doc, g, n, "variable"), nvars) < nvars):
                raise Error("a variable index out of range")
        if op == "variable/set":
            var vs = jitems(doc, jget(doc, jget(doc, jget(doc, node_of(doc, g, n), "configuration"), "variables"), "value"))
            if len(vs) == 0:
                raise Error("variable/set names no variable")
            for v in vs:
                if not (jnat_or(doc, v, nvars) < nvars):
                    raise Error("a variable index out of range")


def follow(doc: JDoc, g: Int, n: Int, name: String, mut m: Int) -> Bool:
    return jnat(doc, jget(doc, jget(doc, jget(doc, node_of(doc, g, n), "flows"), name), "node"), m)


def _next(doc: JDoc, g: Int, n: Int, name: String, mut r: KRun) raises:
    var m = 0
    if follow(doc, g, n, name, m):
        exec_node(doc, g, m, r)


def exec_node(doc: JDoc, g: Int, n: Int, mut r: KRun) raises:
    if r.fuel == 0:
        raise Error("the graph ran out of fuel")
    r.fuel -= 1
    var op = op_of(doc, g, n)
    if op == "event/onStart":
        _next(doc, g, n, "out", r)
    elif op == "flow/sequence":
        var flows = jget(doc, node_of(doc, g, n), "flows")
        var order = List[Int]()
        if doc.kind[flows] == J_OBJ:
            for i in range(len(doc.keys[flows])):
                var m = 0
                if jnat(doc, jget(doc, doc.kids[flows][i], "node"), m):
                    order.append(m)
        for m in order:
            exec_node(doc, g, m, r)
    elif op == "flow/branch":
        if as_bool(input(doc, g, r, n, "condition")):
            _next(doc, g, n, "true", r)
        else:
            _next(doc, g, n, "false", r)
    elif op == "flow/switch":
        var sel = as_int(input(doc, g, r, n, "selection"))
        _next(doc, g, n, String(sel) if _contains(_cases(doc, g, n), sel) else "default", r)
    elif op == "flow/for":
        var a = as_int(input(doc, g, r, n, "startIndex"))
        idx_set(r, n, a)
        while True:
            if r.fuel == 0:
                raise Error("the graph ran out of fuel")
            var stop = as_int(input(doc, g, r, n, "endIndex"))
            var i = 0
            _ = idx_get(r, n, i)
            if i >= stop:
                break
            r.fuel -= 1
            _next(doc, g, n, "loopBody", r)
            var j = i
            _ = idx_get(r, n, j)
            idx_set(r, n, wrap32(j + 1))
        _next(doc, g, n, "completed", r)
    elif op == "flow/while":
        while True:
            if r.fuel == 0:
                raise Error("the graph ran out of fuel")
            if not as_bool(input(doc, g, r, n, "condition")):
                break
            r.fuel -= 1
            _next(doc, g, n, "loopBody", r)
        _next(doc, g, n, "completed", r)
    elif op == "variable/set":
        var vs = List[Int]()
        for x in jitems(doc, jget(doc, jget(doc, jget(doc, node_of(doc, g, n), "configuration"), "variables"), "value")):
            var i = 0
            if jnat(doc, x, i):
                vs.append(i)
        var cur = List[V]()
        for v in r.vars:
            cur.append(v.copy())
        for i in vs:
            var v = input(doc, g, r, n, String(i))
            var old_is_bool = False
            if i < len(cur):
                old_is_bool = cur[i].is_bool
            if old_is_bool != v.is_bool:
                raise Error("variable/set gives a variable a value of another type")
            if i < len(cur):
                cur[i] = v^
        r.vars = cur^
        _next(doc, g, n, "out", r)
    elif op == "pointer/set":
        var p = pointer_of(doc, g, r, n)
        var v = input(doc, g, r, n, "value")
        store(r.vals, p, v.n)
        _next(doc, g, n, "out", r)
    else:
        raise Error("the node " + op + " is not built")


def run_graph(
    doc: JDoc,
    g: Int,
    vals: List[Entry],
    inputs: List[Entry],
    mut out: List[Entry],
    fuel: Int = 100000,
) raises:
    """Run a graph from its `event/onStart` node over a copy of `vals`. `out`
    gets each variable that has an `id`, with the value it ends at. `inputs`
    replace the initial values of the variables whose ids they name."""
    validate(doc, g)
    var decls = jitems(doc, jget(doc, g, "variables"))
    var vars = List[V]()
    for d in decls:
        var t = jnat_or(doc, jget(doc, d, "type"), 0)
        vars.append(literal_typed(doc, g, t, jfirst(doc, jget(doc, d, "value"))))
    var start = -1
    for n in range(jlen(doc, jget(doc, g, "nodes"))):
        if op_of(doc, g, n) == "event/onStart":
            start = n
            break
    for inp in inputs:
        for i in range(len(decls)):
            if jstr(doc, jget(doc, decls[i], "id")) == inp.key:
                if vars[i].is_bool:
                    vars[i] = vbool(inp.val != 0)
                else:
                    vars[i] = vint(inp.val)
    if start < 0:
        raise Error("the graph has no event/onStart node")
    var r = KRun(vars^, vals.copy(), fuel)
    exec_node(doc, g, start, r)
    out = List[Entry]()
    for i in range(len(decls)):
        if jhas(doc, decls[i], "id"):
            out.append(Entry(jstr(doc, jget(doc, decls[i], "id")), r.vars[i].n))
