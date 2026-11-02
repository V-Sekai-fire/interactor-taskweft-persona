import Persona.Demo
import Persona.Grid
import Persona.Pulls

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

def pull8 : String := "var staged 1\nvar pushed 1\nvar clean 1\nvar open 1\ngoal checked"
def pull7 : String := "var staged 1\nvar pushed 1\nvar clean 1\nvar open 1\nvar lean 1\nvar elf 1\nvar checked 1\nvar approved 1\nvar merged 1\ngoal merged"

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
  , { name := "pulls: an open pull with no checks run is planned to its checks",
      ok := Persona.Pulls.planOf pull8 == "{\"plan\":[\"run_lean_check\",\"run_elf_check\",\"collect_checks\"],\"reached\":true}" }
  , { name := "pulls: a branch with no stage name is planned from the name onward",
      ok := (Persona.Pulls.planOf "goal open").startsWith "{\"plan\":[\"name_branch_by_stage\",\"push_branch\",\"strip_agent_footer\",\"open_pull\"" }
  , { name := "pulls: the agent's plan to merge is refused until the operator approves",
      ok := Persona.Pulls.planOf "var staged 1\nvar pushed 1\nvar clean 1\nvar open 1\nvar lean 1\nvar elf 1\nvar checked 1\ngoal merged" == "{\"refused\":\"unreachable\"}" }
  , { name := "pulls: a merged pull needs nothing more",
      ok := Persona.Pulls.planOf pull7 == "{\"plan\":[],\"reached\":true}" }
  , { name := "domain: every action writes a variable the domain declares",
      ok := domain.actions.all (fun a =>
        a.writes.all fun w => domain.variables.any (fun sv => sv.id == w.1)) }
  , { name := "domain: every code an action writes is held by the codebook",
      ok := domain.actions.all (fun a => a.writes.all fun w => domain.accepts w.2) }
  ]

def run : IO UInt32 := do
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
