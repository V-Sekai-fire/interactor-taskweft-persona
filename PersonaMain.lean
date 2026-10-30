import Persona.Demo

open Persona
open Persona.Demo

namespace PersonaMain

def printVocabulary : IO Unit := do
  let cb := domain.codebook
  IO.println "vocabulary: the codebook a persona composes from"
  IO.println s!"  dimensions      {cb.levels.length}"
  IO.println s!"  levels          {cb.levels}"
  IO.println s!"  basis           {cb.basis}"
  IO.println s!"  codes a stage   {cb.size}"
  IO.println s!"  codes, 4 stages {cb.vocabulary 4}"
  IO.println "values: a code of the codebook, or a number"
  IO.println "actions, with the parameters a call binds"
  for a in domain.actions do
    let written := a.writes.map (fun w => s!"{w.1} <- {value w.2}")
    IO.println s!"  {a.name}({String.intercalate ", " a.params}) writes {String.intercalate ", " written}"
  IO.println "goals: a node of the planner's own space"
  IO.println "  delivered = goal_geq 2 1"

def printAnswer (p : Persona) (g : Goal) : IO UInt32 := do
  IO.println s!"goal: {repr g.node}"
  match p.answer g with
  | some plan =>
    IO.println s!"PLAN ({plan.length} steps)"
    for e in plan do
      match e with
      | .action name _  => IO.println s!"  {name}"
      | .command name _ => IO.println s!"  command {name}"
    let reached := is_node_satisfied (p.domain.execute plan) g.node
    IO.println s!"reached: {reached}"
    return if reached then 0 else 1
  | none =>
    IO.println "NO PLAN"
    return 1

end PersonaMain

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--vocabulary"] => PersonaMain.printVocabulary; return 0
  | _                => PersonaMain.printAnswer persona delivered
