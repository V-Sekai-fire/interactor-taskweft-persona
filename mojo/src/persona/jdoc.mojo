# SPDX-License-Identifier: MIT
# A JSON document as an arena, the shape Lean's `Json` has for the planner:
# an object is its entries sorted by key, a missing key reads as null, and a
# node is an index, so `ref == Json.null` is `kind == J_NULL`.
#
# Parsing is EmberJson's `from_json[Value]`; the arena is built from its
# `Value` once, and the planner never touches EmberJson again.
from emberjson import from_json, Value

comptime J_NULL = 0
comptime J_BOOL = 1
comptime J_INT = 2
comptime J_FLOAT = 3
comptime J_STR = 4
comptime J_ARR = 5
comptime J_OBJ = 6


struct JDoc(Copyable, Movable):
    var kind: List[Int]
    var num: List[Int]
    var text: List[String]
    var kids: List[List[Int]]
    var keys: List[List[String]]

    def __init__(out self):
        self.kind = List[Int]()
        self.num = List[Int]()
        self.text = List[String]()
        self.kids = List[List[Int]]()
        self.keys = List[List[String]]()
        _ = self.add(J_NULL, 0, "")  # node 0 is null

    def add(mut self, kind: Int, num: Int, text: String) -> Int:
        self.kind.append(kind)
        self.num.append(num)
        self.text.append(text)
        self.kids.append(List[Int]())
        self.keys.append(List[String]())
        return len(self.kind) - 1

    def add_arr(mut self, var kids: List[Int]) -> Int:
        var i = self.add(J_ARR, 0, "")
        self.kids[i] = kids^
        return i

    def add_obj(mut self, var keys: List[String], var kids: List[Int]) -> Int:
        """Entries sorted by key; a repeated key keeps its last value."""
        var ks = List[String]()
        var vs = List[Int]()
        for i in range(len(keys)):
            var at = -1
            for k in range(len(ks)):
                if ks[k] == keys[i]:
                    at = k
                    break
            if at >= 0:
                vs[at] = kids[i]
                continue
            # insert in key order
            var pos = len(ks)
            for k in range(len(ks)):
                if keys[i] < ks[k]:
                    pos = k
                    break
            ks.insert(pos, keys[i])
            vs.insert(pos, kids[i])
        var i = self.add(J_OBJ, 0, "")
        self.keys[i] = ks^
        self.kids[i] = vs^
        return i


def import_value(mut doc: JDoc, v: Value) raises -> Int:
    if v.is_null():
        return 0
    if v.is_bool():
        return doc.add(J_BOOL, 1 if v.bool() else 0, "")
    if v.is_int():
        return doc.add(J_INT, Int(v.int()), "")
    if v.is_uint():
        var u = v.uint()
        if u > 9223372036854775807:
            return doc.add(J_FLOAT, 0, "")
        return doc.add(J_INT, Int(u), "")
    if v.is_float():
        return doc.add(J_FLOAT, 0, "")
    if v.is_string():
        return doc.add(J_STR, 0, v.string())
    if v.is_array():
        var kids = List[Int]()
        for item in v.array():
            kids.append(import_value(doc, item))
        return doc.add_arr(kids^)
    var keys = List[String]()
    var kids = List[Int]()
    for kv in v.object().items():
        keys.append(kv.key)
        kids.append(import_value(doc, kv.value))
    return doc.add_obj(keys^, kids^)


def parse_json(text: String, mut doc: JDoc, mut root: Int) -> Bool:
    """Parse into the arena; False when the text is not JSON."""
    var v: Value
    try:
        v = from_json[Value](text)
    except:
        return False
    try:
        root = import_value(doc, v)
    except:
        return False
    return True


# ---- readers, with Lean's defaults ------------------------------------------
def jget(doc: JDoc, j: Int, key: String) -> Int:
    """getObjValD: the entry, or null."""
    if doc.kind[j] != J_OBJ:
        return 0
    for i in range(len(doc.keys[j])):
        if doc.keys[j][i] == key:
            return doc.kids[j][i]
    return 0


def jhas(doc: JDoc, j: Int, key: String) -> Bool:
    """getObjVal? succeeds."""
    if doc.kind[j] != J_OBJ:
        return False
    for i in range(len(doc.keys[j])):
        if doc.keys[j][i] == key:
            return True
    return False


def jitems(doc: JDoc, j: Int) -> List[Int]:
    if doc.kind[j] == J_ARR:
        return doc.kids[j].copy()
    return List[Int]()


def jnth(doc: JDoc, j: Int, i: Int) -> Int:
    """items j [i], or null."""
    if doc.kind[j] == J_ARR and i >= 0 and i < len(doc.kids[j]):
        return doc.kids[j][i]
    return 0


def jfirst(doc: JDoc, j: Int) -> Int:
    return jnth(doc, j, 0)


def jis_str(doc: JDoc, j: Int) -> Bool:
    return doc.kind[j] == J_STR


def jstr(doc: JDoc, j: Int) -> String:
    """The string, or empty."""
    if doc.kind[j] == J_STR:
        return doc.text[j]
    return String()


def jint(doc: JDoc, j: Int, mut out: Int) -> Bool:
    """getInt?"""
    if doc.kind[j] == J_INT:
        out = doc.num[j]
        return True
    return False


def jnat(doc: JDoc, j: Int, mut out: Int) -> Bool:
    """getNat?"""
    if doc.kind[j] == J_INT and doc.num[j] >= 0:
        out = doc.num[j]
        return True
    return False


def jnat_or(doc: JDoc, j: Int, dflt: Int) -> Int:
    var n = 0
    if jnat(doc, j, n):
        return n
    return dflt


def jbool(doc: JDoc, j: Int, mut out: Bool) -> Bool:
    """getBool?"""
    if doc.kind[j] == J_BOOL:
        out = doc.num[j] == 1
        return True
    return False


def jlen(doc: JDoc, j: Int) -> Int:
    return len(jitems(doc, j))
