import Persona.Jsonld

/-- `persona_plan <domain.jsonld> <problem.jsonld> [plan.jsonld]` prints the plan document, and
writes it to the third path when one is given. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | domain :: problem :: rest =>
    let plan := Persona.Jsonld.planOf (← IO.FS.readFile domain) (← IO.FS.readFile problem)
    IO.println plan
    if let some out := rest.head? then IO.FS.writeFile out (plan ++ "\n")
    return 0
  | _ => IO.eprintln "usage: persona_plan <domain.jsonld> <problem.jsonld> [plan.jsonld]" *> pure 2
