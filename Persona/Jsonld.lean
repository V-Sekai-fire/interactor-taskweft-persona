import Persona.Guest
import Lean.Data.Json

namespace Persona.Jsonld

open Lean Persona

inductive Task where
  | goal : String → Task
  | act  : String → Task

structure Act where
  name  : String
  evals : List (String × String × String)
  sets  : List (String × Int)

structure Spec where
  acts    : List Act
  methods : List (String × List (List Task))
  init    : List (String × Int)
  edges   : List (String × String × String)

structure St where
  vals  : List (String × Int)
  edges : List (String × String × String)
  plan  : List String

def entries (j : Json) : List (String × Json) :=
  match j.getObj? with
  | .ok o => o.toList
  | .error _ => []

def items (j : Json) : List Json :=
  match j.getArr? with
  | .ok a => a.toList
  | .error _ => []

def str (j : Json) : String := (j.getStr?.toOption).getD ""

def parseTask (j : Json) : Task :=
  match items j with
  | s :: p :: _ => if str s == "goal" then .goal (str p) else .act (str s)
  | s :: _ => .act (str s)
  | [] => .act ""

def parseAct (name : String) (j : Json) : Act :=
  let body := items (j.getObjValD "body")
  { name := name
  , evals := body.filterMap fun b =>
      let e := b.getObjValD "eval"
      if str (e.getObjValD "type") == "rebac/check" then
        some (str (e.getObjValD "subject"), str (e.getObjValD "rel"), str (e.getObjValD "object"))
      else none
  , sets := body.filterMap fun b =>
      match b.getObjVal? "pointer/set" with
      | .ok p => some (str p, ((b.getObjValD "value").getInt?.toOption).getD 0)
      | .error _ => none }

/-- The planner domain document as the persona reads it: variables with their initial
values, actions as pointer writes and graph checks, and methods as ordered subtasks. -/
def parse (text : String) : Except String Spec := do
  let j ← Json.parse text
  let init := (items (j.getObjValD "variables")).flatMap fun v =>
    (entries (v.getObjValD "init")).map fun (k, x) =>
      ("/" ++ str (v.getObjValD "name") ++ "/" ++ k, (x.getInt?.toOption).getD 0)
  let edges := (items ((j.getObjValD "capabilities").getObjValD "graph" |>.getObjValD "edges")).map
    fun e => (str (e.getObjValD "subject"), str (e.getObjValD "rel"), str (e.getObjValD "object"))
  return { acts := (entries (j.getObjValD "actions")).map fun (n, a) => parseAct n a
         , methods := (entries (j.getObjValD "methods")).map fun (p, m) =>
             (p, (items (m.getObjValD "alternatives")).map fun alt =>
               (items (alt.getObjValD "subtasks")).map parseTask)
         , init, edges }

def lookup (vals : List (String × Int)) (p : String) : Int :=
  ((vals.find? (·.1 == p)).map (·.2)).getD 0

def store (vals : List (String × Int)) (p : String) (v : Int) : List (String × Int) :=
  if vals.any (·.1 == p) then vals.map fun x => if x.1 == p then (p, v) else x else vals ++ [(p, v)]

/-- Decompose a task: a goal already held is no step, a goal is met by the first method
alternative whose subtasks all succeed in order, and an action fails when the graph does
not hold an edge it checks. -/
partial def run (sp : Spec) (fuel : Nat) : Task → St → Option St
  | .act n, s =>
    match sp.acts.find? (·.name == n) with
    | none => none
    | some a =>
      if a.evals.all (fun e => s.edges.contains e) then
        some { s with vals := a.sets.foldl (fun v w => store v w.1 w.2) s.vals,
                      plan := s.plan ++ [n] }
      else none
  | .goal p, s =>
    if lookup s.vals p ≥ 1 then some s
    else match fuel with
      | 0 => none
      | f + 1 =>
        match sp.methods.find? (·.1 == p) with
        | none => none
        | some m => m.2.findSome? fun alt => alt.foldlM (fun st t => run sp f t st) s

/-- A request is `var NAME 0|1` facts, `edge S R O` graph edges and one `goal NAME`. -/
def facts (spec : String) : List (String × Int) × List (String × String × String) × Option String :=
  let ls := ((spec.splitOn "\n").map fun l => (l.splitOn " ").filter (· != "")).filter (!·.isEmpty)
  ( ls.filterMap fun | ["var", n, b] => b.toNat?.map fun x => ("/pull/" ++ n, (x : Int)) | _ => none
  , ls.filterMap fun | ["edge", s, r, o] => some (s, r, o) | _ => none
  , (ls.filterMap fun | ["goal", g] => some ("/pull/" ++ g) | _ => none).head? )

/-- The plan to a goal, checked against the planner's own goal test on the final state. -/
def planOf (domain spec : String) : String :=
  match parse domain with
  | .error e => "{\"refused\":\"bad_domain\",\"detail\":" ++ Guest.quote e ++ "}"
  | .ok sp =>
    let (fv, fe, goal) := facts spec
    match goal with
    | none => "{\"refused\":\"bad_spec\"}"
    | some g =>
      if !(sp.init.any (·.1 == g)) then "{\"refused\":\"undeclared_goal\"}"
      else
        let start : St := { vals := fv.foldl (fun v w => store v w.1 w.2) sp.init
                          , edges := sp.edges ++ fe, plan := [] }
        match run sp 12 (.goal g) start with
        | none => "{\"refused\":\"unreachable\"}"
        | some s =>
          let st : GTNState := { variables := s.vals.mapIdx fun i x => ⟨i, x.2⟩
                               , executable_trace := [] }
          let idx := (s.vals.findIdx? (·.1 == g)).getD 0
          let ok := is_node_satisfied st (.goal_geq idx 1)
          "{\"plan\":" ++ Guest.planJson (s.plan.map fun n => PlanElement.action n [])
            ++ ",\"reached\":" ++ (if ok then "true" else "false") ++ "}"

end Persona.Jsonld
