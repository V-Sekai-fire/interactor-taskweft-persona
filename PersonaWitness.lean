import Persona.Demo
import Persona.Grid
import Persona.Jsonld

open Persona
open Persona.Demo

namespace PersonaWitness

def distinct {α : Type} [DecidableEq α] : List α → Bool
  | []      => true
  | x :: xs => !(xs.any fun y => decide (y = x)) && distinct xs

structure Check where
  name : String
  ok : Bool

def stage : Codebook := { levels := [8, 8, 8, 8] }

def plan : Option (List PlanElement) := persona.answer delivered

def reached : Bool :=
  match plan with
  | some p => is_node_satisfied (domain.execute p) delivered.node
  | none   => false

def gridSpec : String := "skill 1 1\nskill 2 0 1\nskill 3 0 2 1\nskill 4 0 3\ngoal 4"

def gridOrdered : Bool :=
  Persona.Grid.planOf gridSpec == "{\"plan\":[\"activate-2\",\"activate-3\",\"activate-4\"],\"reached\":true}"

def checks : List Check :=
  [ { name := "codebook: eight levels over four dimensions is 4096 codes a stage",
      ok := stage.size == 4096 }
  , { name := "codebook: the basis is the prefix product",
      ok := stage.basis == [1, 8, 64, 512] }
  , { name := "codebook: a code's index is mixed-radix",
      ok := stage.index [1, 2, 3, 4] == 2257 }
  , { name := "codebook: four stages of 4096 codes is the whole vocabulary",
      ok := stage.vocabulary 4 == 281474976710656 }
  , { name := "codebook: a held code carries one digit a dimension, in range",
      ok := stage.holds [7, 7, 7, 7] }
  , { name := "codebook: a digit past its level is refused",
      ok := !(stage.holds [8, 0, 0, 0]) }
  , { name := "codebook: a code of the wrong arity is refused",
      ok := !(stage.holds [1, 2, 3]) }
  , { name := "answer: the goal is reached", ok := plan.isSome }
  , { name := "answer: the plan it composes executes to the goal", ok := reached }
  , { name := "answer: the plan does not repeat an action",
      ok := match plan with | some p => distinct p | none => false }
  , { name := "refusal: a goal the domain cannot reach",
      ok := (persona.answer { node := .goal_geq 2 2 }).isNone }
  , { name := "refusal: a variable the domain does not declare",
      ok := (persona.answer { node := .goal_geq 99 1 }).isNone }
  , { name := "refusal: zero fuel on an unmet goal",
      ok := (persona.answer delivered 0).isNone }
  , { name := "grid: a plan activates every skill after the skills it needs",
      ok := gridOrdered }
  , { name := "grid: a cycle of needs is refused as unreachable",
      ok := Persona.Grid.planOf "skill 1 0 2\nskill 2 0 1\ngoal 1" == "{\"refused\":\"unreachable\"}" }
  , { name := "grid: a goal the spec does not declare is refused",
      ok := Persona.Grid.planOf "skill 1 1\ngoal 9" == "{\"refused\":\"undeclared_goal\"}" }
  , { name := "domain: every action writes a variable the domain declares",
      ok := domain.actions.all (fun a =>
        a.writes.all fun w => domain.variables.any (fun sv => sv.id == w.1)) }
  , { name := "domain: every code an action writes is held by the codebook",
      ok := domain.actions.all (fun a => a.writes.all fun w => domain.accepts w.2) }
  ]

def staged : String := "var staged 1\nvar pushed 1\nvar clean 1\nvar open 1"

/-- The pull-request domain is a document, `domains/pulls.jsonld`, and every check reads it. -/
def pullChecks (dom : String) : List Check :=
  let ask := fun (spec : String) => Persona.Jsonld.planOf dom spec
  [ { name := "pulls: an open pull with no checks run is planned to its checks",
      ok := ask (staged ++ "\ngoal checked")
        == "{\"plan\":[\"run-lean-check\",\"run-elf-check\",\"collect-checks\"],\"reached\":true}" }
  , { name := "pulls: a pull with nothing done is planned from the branch name",
      ok := (ask "goal open").startsWith "{\"plan\":[\"name-branch-by-stage\",\"push-branch\"" }
  , { name := "pulls: the plan to merge is refused until the graph holds operator approves pull",
      ok := ask (staged ++ "\ngoal merged") == "{\"refused\":\"unreachable\"}" }
  , { name := "pulls: the same plan is found once that edge is in the graph",
      ok := (ask (staged ++ "\nedge operator approves pull\ngoal merged")).endsWith
        "\"merge-pull\"],\"reached\":true}" }
  , { name := "pulls: the document drives the plan, so renaming its approval edge refuses the merge",
      ok := Persona.Jsonld.planOf (dom.replace "\"rel\": \"approves\"" "\"rel\": \"vetoes\"")
        (staged ++ "\nedge operator approves pull\ngoal merged") == "{\"refused\":\"unreachable\"}" }
  , { name := "pulls: a merged pull needs nothing more",
      ok := ask (staged ++ "\nvar merged 1\ngoal merged") == "{\"plan\":[],\"reached\":true}" }
  , { name := "pulls: a goal the domain does not declare is refused",
      ok := ask "goal shipped" == "{\"refused\":\"undeclared_goal\"}" }
  , { name := "pulls: a document that is not JSON is refused as a bad domain",
      ok := (Persona.Jsonld.planOf "{" "goal open").startsWith "{\"refused\":\"bad_domain\"" } ]

def run : IO UInt32 := do
  let dom ← IO.FS.readFile "domains/pulls.jsonld"
  let checks := checks ++ pullChecks dom
  for c in checks do
    let tag := if c.ok then "ok  " else "FAIL"
    IO.println s!"  [{tag}] {c.name}"
  let bad := checks.filter (fun c => !c.ok)
  if bad.isEmpty then
    IO.println s!"OK: persona, {checks.length} invariants hold (codebook, answer and refusals verified)"
    return 0
  else
    IO.println s!"FAIL: {bad.length} of {checks.length} invariants failed"
    return 1

end PersonaWitness

def main : IO UInt32 := PersonaWitness.run
