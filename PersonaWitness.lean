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

/-- The campus domain is a document, `domains/campus-sample.jsonld`, and every check reads it. -/
def campusChecks (dom : String) : List Check :=
  let ask := fun (spec : String) => Persona.Jsonld.planOf dom spec
  let full := "[\"acquire-token-3\",\"settle-2\",\"acquire-token-B1\",\"settle-3\"]"
  [ { name := "campus: skills and tokens are assembled in order into the goal",
      ok := ask "goal /rfd/3" == "{\"plan\":" ++ full ++ ",\"reached\":true}" }
  , { name := "campus: a token already held is not acquired again",
      ok := ask "var /token/3 1\ngoal /rfd/3"
        == "{\"plan\":[\"settle-2\",\"acquire-token-B1\",\"settle-3\"],\"reached\":true}" }
  , { name := "campus: a settled goal needs nothing more",
      ok := ask "var /rfd/3 1\ngoal /rfd/3" == "{\"plan\":[],\"reached\":true}" }
  , { name := "campus: a goal the domain does not declare is refused",
      ok := ask "goal /rfd/9" == "{\"refused\":\"undeclared_goal\"}" }
  , { name := "campus: a token that is never acquired leaves its skill, and the goal, unreachable",
      ok := Persona.Jsonld.planOf (dom.replace "\"pointer/set\": \"/token/3\"" "\"pointer/set\": \"/token/9\"") "goal /rfd/3"
        == "{\"refused\":\"unreachable\"}" }
  , { name := "campus: a document that is not JSON is refused as a bad domain",
      ok := (Persona.Jsonld.planOf "{" "goal /rfd/3").startsWith "{\"refused\":\"bad_domain\"" } ]

def run : IO UInt32 := do
  let dom ← IO.FS.readFile "domains/campus-sample.jsonld"
  let checks := checks ++ campusChecks dom
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
