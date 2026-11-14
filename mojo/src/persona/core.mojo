# SPDX-License-Identifier: MIT
# Persona.lean in Mojo: a codebook, a value that is a code or a number, an
# action, a domain, and the search that answers a goal with a plan or nothing.
# Every rule and every name follows the Lean source line for line.

comptime NODE_TASK = 0
comptime NODE_GOAL_GEQ = 1
comptime NODE_VERIFY_GOAL = 2


@fieldwise_init
struct StateVar(Copyable, Movable):
    var id: Int
    var val: Int


@fieldwise_init
struct Codebook(Copyable, Movable):
    """One level count per dimension, packed mixed-radix."""

    var levels: List[Int]

    def size(self) -> Int:
        var acc = 1
        for l in self.levels:
            acc *= l
        return acc

    def basis(self) -> List[Int]:
        """The prefix product before each dimension."""
        var out = List[Int]()
        var acc = 1
        for l in self.levels:
            out.append(acc)
            acc *= l
        return out^

    def index(self, code: List[Int]) -> Int:
        """The index a code names, mixed-radix. zip stops at the shorter."""
        var b = self.basis()
        var n = len(b) if len(b) < len(code) else len(code)
        var acc = 0
        for i in range(n):
            acc += code[i] * b[i]
        return acc

    def holds(self, code: List[Int]) -> Bool:
        """One digit per dimension, each one in range."""
        if len(code) != len(self.levels):
            return False
        for i in range(len(code)):
            if not (code[i] < self.levels[i]):
                return False
        return True

    def vocabulary(self, stages: Int) -> Int:
        var acc = 1
        var s = self.size()
        for _ in range(stages):
            acc *= s
        return acc


@fieldwise_init
struct PValue(Copyable, Movable):
    """A code of the codebook, or a number."""

    var is_code: Bool
    var code: List[Int]
    var number: Int


def code_value(c: List[Int]) -> PValue:
    return PValue(True, c.copy(), 0)


def number_value(n: Int) -> PValue:
    return PValue(False, List[Int](), n)


@fieldwise_init
struct Write(Copyable, Movable):
    var var_id: Int
    var value: PValue


@fieldwise_init
struct Action(Copyable, Movable):
    var name: String
    var params: List[String]
    var writes: List[Write]


@fieldwise_init
struct Need(Copyable, Movable):
    var var_id: Int
    var threshold: Int


@fieldwise_init
struct Require(Copyable, Movable):
    var action: String
    var needs: List[Need]


@fieldwise_init
struct Node(Copyable, Movable):
    """One node of the planner's own GTN space."""

    var kind: Int
    var var_id: Int
    var threshold: Int


def goal_geq(var_id: Int, threshold: Int) -> Node:
    return Node(NODE_GOAL_GEQ, var_id, threshold)


def verify_goal(var_id: Int, value: Int) -> Node:
    return Node(NODE_VERIFY_GOAL, var_id, value)


def task_node() -> Node:
    return Node(NODE_TASK, 0, 0)


@fieldwise_init
struct GTNState(Copyable, Movable):
    var variables: List[StateVar]
    var trace: List[String]


def is_node_satisfied(st: GTNState, n: Node) -> Bool:
    """Task nodes are never self-satisfied; goal nodes read the variable."""
    if n.kind == NODE_TASK:
        return False
    for sv in st.variables:
        if sv.id == n.var_id:
            if n.kind == NODE_GOAL_GEQ:
                return n.threshold <= sv.val
            return sv.val == n.threshold
    return False


@fieldwise_init
struct Domain(Copyable, Movable):
    var variables: List[StateVar]
    var codebook: Codebook
    var actions: List[Action]
    var requires: List[Require]

    def resolve(self, v: PValue) -> Int:
        """A code resolves through the codebook; a number is itself."""
        if not v.is_code:
            return v.number
        if self.codebook.holds(v.code):
            return self.codebook.index(v.code)
        return 0

    def accepts(self, v: PValue) -> Bool:
        """A number is always accepted; a code only when the codebook holds it."""
        if not v.is_code:
            return True
        return self.codebook.holds(v.code)

    def initial(self) -> GTNState:
        return GTNState(self.variables.copy(), List[String]())

    def apply(self, a: Action, st: GTNState) -> GTNState:
        """Every variable the action writes takes its value."""
        var vars = List[StateVar]()
        for sv in st.variables:
            var val = sv.val
            for w in a.writes:
                if w.var_id == sv.id:
                    val = self.resolve(w.value)
                    break
            vars.append(StateVar(sv.id, val))
        var trace = st.trace.copy()
        trace.append(a.name)
        return GTNState(vars^, trace^)

    def execute(self, plan: List[String]) -> GTNState:
        """Run a plan in order; a name no action carries leaves the state."""
        var st = self.initial()
        for name in plan:
            for a in self.actions:
                if a.name == name:
                    st = self.apply(a, st)
                    break
        return st^

    def applicable(self, a: Action, st: GTNState) -> Bool:
        """Open when every variable the action requires meets its threshold."""
        for r in self.requires:
            if r.action == a.name:
                for q in r.needs:
                    var found = False
                    var ok = False
                    for sv in st.variables:
                        if sv.id == q.var_id:
                            found = True
                            ok = q.threshold <= sv.val
                            break
                    if not found or not ok:
                        return False
                return True
        return True


def _blacklisted(blacklist: List[String], name: String) -> Bool:
    for b in blacklist:
        if b == name:
            return True
    return False


def answer_from(
    d: Domain,
    goal: Node,
    blacklist: List[String],
    st: GTNState,
    fuel: Int,
    mut plan: List[String],
) -> Bool:
    """The answer: a plan (in `plan`), or False. An action already tried on
    this branch is blacklisted, so the search does not repeat itself."""
    if is_node_satisfied(st, goal):
        plan = List[String]()
        return True
    if fuel <= 0:
        return False
    for a in d.actions:
        if not d.applicable(a, st):
            continue
        if _blacklisted(blacklist, a.name):
            continue
        var bl = blacklist.copy()
        bl.append(a.name)
        var rest = List[String]()
        if answer_from(d, goal, bl, d.apply(a, st), fuel - 1, rest):
            var out = List[String]()
            out.append(a.name)
            for r in rest:
                out.append(r)
            plan = out^
            return True
    return False


def answer(d: Domain, goal: Node, mut plan: List[String], fuel: Int = 8) -> Bool:
    """Ask a persona. The fuel bounds the longest plan it composes."""
    return answer_from(d, goal, List[String](), d.initial(), fuel, plan)
