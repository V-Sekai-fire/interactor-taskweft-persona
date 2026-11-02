import Lean.Data.Json

/-! A subset of KHR_interactivity, the glTF extension for behavior graphs, run against the planner's state.
A graph has `types`, `variables`, `declarations` (each names an `op`) and `nodes` (each names a
declaration, with `configuration`, `values` that read a typed literal or another node's output, and
`flows` to the next nodes). Values are typed: an `int` is a 32-bit two's complement integer that wraps,
and a `bool` is its own type, so a comparison gives a bool and `flow/branch` takes one. The nodes built:
`event/onStart`; `flow/sequence`, `branch`, `switch`, `for` and `while`; `variable/get` and `set`;
`pointer/get` and `set` with `[parameter]` integer template parameters; `math/add`, `sub`, `mul`, `neg`,
`abs`, `min`, `max`, `eq`, `lt`, `le`, `gt`, `ge`, `and`, `or`, `xor`, `not` (logical on bools, bitwise on
ints), `select` and `switch`; and `type/boolToInt` and `type/intToBool`. A graph with a node it does not
build, or a variable or type index out of range, is rejected whole, as the extension requires, and a
run that spends its fuel is refused. Floats, reference template parameters and events other than
`event/onStart` are not built. -/

namespace Persona.Khr

open Lean

inductive V where
  | int  : Int32 → V
  | bool : Bool → V
  deriving Inhabited

def V.toInt : V → Int
  | .int i => i.toInt
  | .bool b => if b then 1 else 0

structure Run where
  vars : Array V
  vals : List (String × Int)
  idx  : List (Nat × Int32)
  fuel : Nat

def items (j : Json) : List Json :=
  match j.getArr? with
  | .ok a => a.toList
  | .error _ => []

def entries (j : Json) : List (String × Json) :=
  match j.getObj? with
  | .ok o => o.toList
  | .error _ => []

def str (j : Json) : String := (j.getStr?.toOption).getD ""
def first (j : Json) : Json := (items j).headD Json.null

def lookup (vals : List (String × Int)) (p : String) : Option Int := (vals.find? (·.1 == p)).map (·.2)

def store (vals : List (String × Int)) (p : String) (v : Int) : List (String × Int) :=
  if vals.any (·.1 == p) then vals.map fun x => if x.1 == p then (p, v) else x else vals ++ [(p, v)]

def node (g : Json) (n : Nat) : Json := (items (g.getObjValD "nodes")).getD n Json.null

def opOf (g : Json) (n : Nat) : String :=
  let d := ((node g n).getObjValD "declaration").getNat?.toOption.getD 0
  str (((items (g.getObjValD "declarations")).getD d Json.null).getObjValD "op")

/-- A configuration value: the first element of its `value` array. -/
def config (g : Json) (n : Nat) (k : String) : Json :=
  first ((((node g n).getObjValD "configuration").getObjValD k).getObjValD "value")

def fits (i : Int) : Bool := -2147483648 ≤ i && i ≤ 2147483647

/-- The signature of a type index: `int` or `bool`, and the others are not built. -/
def tySig (g : Json) (t : Nat) : Except String String :=
  let sig := str (((items (g.getObjValD "types")).getD t Json.null).getObjValD "signature")
  if sig == "int" || sig == "bool" then .ok sig
  else if sig == "" then .error "a type index outside the types array"
  else .error ("the type " ++ sig ++ " is not built")

def literal (g : Json) (ref : Json) : Except String V := do
  let t ← match (ref.getObjValD "type").getNat? with
    | .ok t => pure t
    | .error _ => throw "a literal value socket without a type"
  let sig ← tySig g t
  let x := first (ref.getObjValD "value")
  if sig == "bool" then
    match x.getBool? with
    | .ok b => return .bool b
    | .error _ => throw "a bool literal that is not true or false"
  else
    match x.getInt? with
    | .ok i => if fits i then return .int (Int32.ofInt i) else throw "an int literal outside 32 bits"
    | .error _ => throw "an int literal that is not an integer"

def asInt (v : V) : Except String Int32 :=
  match v with
  | .int i => .ok i
  | .bool _ => .error "a bool where an int is expected"

def asBool (v : V) : Except String Bool :=
  match v with
  | .bool b => .ok b
  | .int _ => .error "an int where a bool is expected"

mutual
  partial def evalRef (g : Json) (r : Run) (ref : Json) : Except String V :=
    match (ref.getObjValD "node").getNat? with
    | .ok n => evalNode g r n (str (ref.getObjValD "socket"))
    | .error _ => literal g ref

  partial def input (g : Json) (r : Run) (n : Nat) (name : String) : Except String V :=
    let ref := ((node g n).getObjValD "values").getObjValD name
    if ref == Json.null then .error ("the node " ++ opOf g n ++ " lacks the input value socket " ++ name)
    else evalRef g r ref

  partial def ints (g : Json) (r : Run) (n : Nat) : Except String (Int32 × Int32) := do
    return (← asInt (← input g r n "a"), ← asInt (← input g r n "b"))

  /-- The effective pointer: each `[name]` path segment is its integer input value socket. -/
  partial def pointerOf (g : Json) (r : Run) (n : Nat) : Except String String := do
    let path := str (config g n "pointer")
    let mut out : List String := []
    for seg in path.splitOn "/" do
      if seg.startsWith "{" then throw "reference template parameters are not built"
      else if seg.startsWith "[" && seg.endsWith "]" && seg.length > 2 then
        let name := (seg.drop 1).dropRight 1
        out := out ++ [toString (← asInt (← input g r n name.toString)).toInt]
      else out := out ++ [seg]
    return String.intercalate "/" out

  partial def evalNode (g : Json) (r : Run) (n : Nat) (socket : String) : Except String V := do
    match opOf g n with
    | "math/add" => let (a, b) ← ints g r n; return .int (a + b)
    | "math/sub" => let (a, b) ← ints g r n; return .int (a - b)
    | "math/mul" => let (a, b) ← ints g r n; return .int (a * b)
    | "math/min" => let (a, b) ← ints g r n; return .int (if a.toInt ≤ b.toInt then a else b)
    | "math/max" => let (a, b) ← ints g r n; return .int (if a.toInt ≥ b.toInt then a else b)
    | "math/neg" => return .int (- (← asInt (← input g r n "a")))
    | "math/abs" =>
      let a ← asInt (← input g r n "a")
      return .int (if a.toInt < 0 then - a else a)
    | "math/lt" => let (a, b) ← ints g r n; return .bool (a.toInt < b.toInt)
    | "math/le" => let (a, b) ← ints g r n; return .bool (a.toInt ≤ b.toInt)
    | "math/gt" => let (a, b) ← ints g r n; return .bool (a.toInt > b.toInt)
    | "math/ge" => let (a, b) ← ints g r n; return .bool (a.toInt ≥ b.toInt)
    | "math/eq" =>
      match (← input g r n "a"), (← input g r n "b") with
      | .int a, .int b => return .bool (a == b)
      | .bool a, .bool b => return .bool (a == b)
      | _, _ => throw "math/eq compares two values of one type"
    | "math/and" =>
      match (← input g r n "a"), (← input g r n "b") with
      | .bool a, .bool b => return .bool (a && b)
      | .int a, .int b => return .int (a &&& b)
      | _, _ => throw "math/and takes two values of one type"
    | "math/or" =>
      match (← input g r n "a"), (← input g r n "b") with
      | .bool a, .bool b => return .bool (a || b)
      | .int a, .int b => return .int (a ||| b)
      | _, _ => throw "math/or takes two values of one type"
    | "math/xor" =>
      match (← input g r n "a"), (← input g r n "b") with
      | .bool a, .bool b => return .bool (a != b)
      | .int a, .int b => return .int (a ^^^ b)
      | _, _ => throw "math/xor takes two values of one type"
    | "math/not" =>
      match (← input g r n "a") with
      | .bool a => return .bool (!a)
      | .int a => return .int (~~~ a)
    | "math/select" =>
      if (← asBool (← input g r n "condition")) then input g r n "a" else input g r n "b"
    | "math/switch" =>
      let sel := (← asInt (← input g r n "selection")).toInt
      let cases := (items (((node g n).getObjValD "configuration").getObjValD "cases" |>.getObjValD "value")).filterMap
        fun x => x.getInt?.toOption
      if cases.contains sel then input g r n (toString sel) else input g r n "default"
    | "type/boolToInt" => return .int (if (← asBool (← input g r n "a")) then 1 else 0)
    | "type/intToBool" => return .bool ((← asInt (← input g r n "a")).toInt != 0)
    | "variable/get" =>
      let i := (config g n "variable").getNat?.toOption.getD 0
      return r.vars.getD i default
    | "pointer/get" =>
      let p ← pointerOf g r n
      let t := (config g n "type").getNat?.toOption.getD 0
      let sig ← tySig g t
      match lookup r.vals p, socket with
      | some x, "value" => return if sig == "bool" then .bool (x != 0) else .int (Int32.ofInt x)
      | none, "value" => return if sig == "bool" then .bool false else .int 0
      | some _, "isValid" => return .bool true
      | none, "isValid" => return .bool false
      | _, _ => throw "pointer/get has the output value sockets value and isValid"
    | "flow/for" =>
      let init := (config g n "initialIndex").getInt?.toOption.getD 0
      return .int (((r.idx.find? (·.1 == n)).map (·.2)).getD (Int32.ofInt init))
    | other => throw ("the node " ++ other ++ " is not built")
end

/-- The nodes and the configuration the interpreter builds, checked over the whole graph before a run:
a graph with a node that is not built or a configuration that is out of range is rejected. -/
def validate (g : Json) : Except String Unit := do
  let built := ["event/onStart", "flow/sequence", "flow/branch", "flow/switch", "flow/for", "flow/while",
    "variable/get", "variable/set", "pointer/get", "pointer/set", "math/add", "math/sub", "math/mul",
    "math/neg", "math/abs", "math/min", "math/max", "math/eq", "math/lt", "math/le", "math/gt", "math/ge",
    "math/and", "math/or", "math/xor", "math/not", "math/select", "math/switch", "type/boolToInt",
    "type/intToBool"]
  let nvars := (items (g.getObjValD "variables")).length
  for t in List.range (items (g.getObjValD "types")).length do
    let _ ← tySig g t
  for n in List.range (items (g.getObjValD "nodes")).length do
    let op := opOf g n
    unless built.contains op do throw ("the node " ++ op ++ " is not built")
    if op == "variable/get" then
      unless ((config g n "variable").getNat?.toOption.getD nvars) < nvars do throw "a variable index out of range"
    if op == "variable/set" then
      let vs := items ((((node g n).getObjValD "configuration").getObjValD "variables").getObjValD "value")
      if vs.isEmpty then throw "variable/set names no variable"
      for v in vs do
        unless (v.getNat?.toOption.getD nvars) < nvars do throw "a variable index out of range"

def follow (g : Json) (n : Nat) (name : String) : Option Nat :=
  ((((node g n).getObjValD "flows").getObjValD name).getObjValD "node").getNat?.toOption

mutual
  partial def exec (g : Json) (n : Nat) (r : Run) : Except String Run :=
    if r.fuel == 0 then .error "the graph ran out of fuel"
    else
      let r := { r with fuel := r.fuel - 1 }
      let next := fun (name : String) (r : Run) =>
        match follow g n name with
        | some m => exec g m r
        | none => .ok r
      match opOf g n with
      | "event/onStart" => next "out" r
      | "flow/sequence" => do
        let ordered := ((entries ((node g n).getObjValD "flows")).filterMap fun (k, v) =>
          (v.getObjValD "node").getNat?.toOption.map (k, ·)).toArray.qsort (fun a b => a.1 < b.1) |>.toList
        let mut cur := r
        for (_, m) in ordered do cur ← exec g m cur
        return cur
      | "flow/branch" => do
        if (← asBool (← input g r n "condition")) then next "true" r else next "false" r
      | "flow/switch" => do
        let sel := (← asInt (← input g r n "selection")).toInt
        let cases := (items (((node g n).getObjValD "configuration").getObjValD "cases" |>.getObjValD "value")).filterMap
          fun x => x.getInt?.toOption
        next (if cases.contains sel then toString sel else "default") r
      | "flow/for" => do
        let a ← asInt (← input g r n "startIndex")
        let r ← loopFor g n { r with idx := (r.idx.filter (·.1 != n)) ++ [(n, a)] }
        next "completed" r
      | "flow/while" => do
        let r ← loopWhile g n r
        next "completed" r
      | "variable/set" => do
        let vs := (items ((((node g n).getObjValD "configuration").getObjValD "variables").getObjValD "value")).filterMap
          fun x => x.getNat?.toOption
        let mut cur := r
        for i in vs do
          let v ← input g r n (toString i)
          let old := cur.vars.getD i default
          match old, v with
          | .int _, .int _ => pure ()
          | .bool _, .bool _ => pure ()
          | _, _ => throw "variable/set gives a variable a value of another type"
          cur := { cur with vars := cur.vars.set! i v }
        next "out" cur
      | "pointer/set" => do
        let p ← pointerOf g r n
        let v ← input g r n "value"
        next "out" { r with vals := store r.vals p v.toInt }
      | other => .error ("the node " ++ other ++ " is not built")

  /-- Each pass reads `endIndex` again, runs `loopBody` while the index is below it, then adds one. -/
  partial def loopFor (g : Json) (n : Nat) (r : Run) : Except String Run := do
    if r.fuel == 0 then throw "the graph ran out of fuel"
    let stop ← asInt (← input g r n "endIndex")
    let i := ((r.idx.find? (·.1 == n)).map (·.2)).getD 0
    if i.toInt ≥ stop.toInt then return r
    let r := { r with fuel := r.fuel - 1 }
    let r ← match follow g n "loopBody" with
      | some m => exec g m r
      | none => pure r
    let i := ((r.idx.find? (·.1 == n)).map (·.2)).getD i
    loopFor g n { r with idx := (r.idx.filter (·.1 != n)) ++ [(n, i + 1)] }

  partial def loopWhile (g : Json) (n : Nat) (r : Run) : Except String Run := do
    if r.fuel == 0 then throw "the graph ran out of fuel"
    else if !(← asBool (← input g r n "condition")) then return r
    else
      let r := { r with fuel := r.fuel - 1 }
      let r ← match follow g n "loopBody" with
        | some m => exec g m r
        | none => pure r
      loopWhile g n r
end

/-- Run a graph from its `event/onStart` node over a copy of the state `vals`. The answer is each variable
that has an `id`, with the value it ends at (a bool as 0 or 1), or the reason the graph was rejected or
could not run. -/
def runGraph (g : Json) (vals : List (String × Int)) (fuel : Nat := 100000) :
    Except String (List (String × Int)) := do
  validate g
  let decls := items (g.getObjValD "variables")
  let mut vars : Array V := #[]
  for d in decls do
    let t := (d.getObjValD "type").getNat?.toOption.getD 0
    vars := vars.push (← literal g (Json.mkObj [("type", Json.num (JsonNumber.fromNat t)), ("value", d.getObjValD "value")]))
  let start := (List.range (items (g.getObjValD "nodes")).length).find? (fun n => opOf g n == "event/onStart")
  match start with
  | none => throw "the graph has no event/onStart node"
  | some s =>
    let r ← exec g s { vars := vars, vals := vals, idx := [], fuel := fuel }
    return (decls.zip r.vars.toList).filterMap fun (v, x) =>
      match v.getObjVal? "id" with
      | .ok i => some (str i, x.toInt)
      | .error _ => none

end Persona.Khr
