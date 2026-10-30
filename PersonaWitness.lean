import Persona.Demo

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
