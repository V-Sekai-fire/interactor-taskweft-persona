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
  holds : List (String × Int)
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
  , holds := body.filterMap fun b =>
      let e := b.getObjValD "eval"
      if str (e.getObjValD "type") == "pointer/ge" then
        some (str (e.getObjValD "pointer"), ((e.getObjValD "value").getInt?.toOption).getD 1)
      else none
  , sets := body.filterMap fun b =>
      match b.getObjVal? "pointer/set" with
      | .ok p => some (str p, ((b.getObjValD "value").getInt?.toOption).getD 0)
      | .error _ => none }

/-- A domain document: actions, methods, and the variables it declares with their defaults. -/
def parse (text : String) : Except String Spec := do
  let j ← Json.parse text
  let init := (items (j.getObjValD "variables")).flatMap fun v =>
    (entries (v.getObjValD "init")).map fun (k, x) =>
      ("/" ++ str (v.getObjValD "name") ++ "/" ++ k, (x.getInt?.toOption).getD 0)
  return { acts := (entries (j.getObjValD "actions")).map fun (n, a) => parseAct n a
         , methods := (entries (j.getObjValD "methods")).map fun (p, m) =>
             (p, (items (m.getObjValD "alternatives")).map fun alt =>
               (items (alt.getObjValD "subtasks")).map parseTask)
         , init, edges := [] }

structure Problem where
  name  : String
  init  : List (String × Int)
  edges : List (String × String × String)
  goals : List String

/-- A problem document: the facts that hold at the start, the graph edges, and the goals. -/
def parseProblem (text : String) : Except String Problem := do
  let j ← Json.parse text
  let init := (items (j.getObjValD "variables")).flatMap fun v =>
    (entries (v.getObjValD "init")).map fun (k, x) =>
      ("/" ++ str (v.getObjValD "name") ++ "/" ++ k, (x.getInt?.toOption).getD 0)
  let edges := (items (((j.getObjValD "capabilities").getObjValD "graph").getObjValD "edges")).map
    fun e => (str (e.getObjValD "subject"), str (e.getObjValD "rel"), str (e.getObjValD "object"))
  let goals := (items (j.getObjValD "todo_list")).flatMap fun t =>
    (items (t.getObjValD "goal")).map fun g => str (g.getObjValD "pointer")
  return { name := str (j.getObjValD "name"), init, edges, goals }

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
      if a.evals.all (fun e => s.edges.contains e) && a.holds.all (fun h => lookup s.vals h.1 ≥ h.2) then
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

def docName (text : String) : String :=
  match Json.parse text with
  | .ok j => str (j.getObjValD "name")
  | .error _ => ""

def vsekai : String := "\"@context\":{\"VSEKAI\":\"https://v-sekai.org/\",\"domain\":\"VSEKAI:planning/domain/\"}"

def refusal (domain problem why : String) : String :=
  "{" ++ vsekai ++ ",\"@type\":\"domain:Plan\",\"domain\":" ++ Guest.quote domain
    ++ ",\"problem\":" ++ Guest.quote problem ++ ",\"refused\":" ++ Guest.quote why ++ "}"

/-- The plan document: the domain and the problem it answers, the steps in order, and whether the
planner's own goal test holds on the final state for every goal of the problem. -/
def planOf (domain problem : String) : String :=
  let dn := docName domain
  let pn := docName problem
  match parse domain, parseProblem problem with
  | .error _, _ => refusal dn pn "bad_domain"
  | _, .error _ => refusal dn pn "bad_problem"
  | .ok sp, .ok pb =>
    let known := sp.init ++ pb.init
    if pb.goals.isEmpty then refusal dn pn "no_goal"
    else if pb.goals.any (fun g => !(known.any (·.1 == g))) then refusal dn pn "undeclared_goal"
    else
      let start : St := { vals := pb.init.foldl (fun v w => store v w.1 w.2) sp.init
                        , edges := pb.edges, plan := [] }
      match pb.goals.foldlM (fun st g => run sp 12 (.goal g) st) start with
      | none => refusal dn pn "unreachable"
      | some s =>
        let st : GTNState := { variables := s.vals.mapIdx fun i x => ⟨i, x.2⟩
                             , executable_trace := [] }
        let ok := pb.goals.all fun g =>
          is_node_satisfied st (.goal_geq ((s.vals.findIdx? (·.1 == g)).getD 0) 1)
        let steps := s.plan.map fun n => "{\"action\":" ++ Guest.quote n ++ ",\"params\":[]}"
        "{" ++ vsekai ++ ",\"@type\":\"domain:Plan\",\"name\":" ++ Guest.quote (pn ++ "_plan")
          ++ ",\"domain\":" ++ Guest.quote dn ++ ",\"problem\":" ++ Guest.quote pn
          ++ ",\"reached\":" ++ (if ok then "true" else "false")
          ++ ",\"steps\":[" ++ String.intercalate "," steps ++ "]}"

end Persona.Jsonld
