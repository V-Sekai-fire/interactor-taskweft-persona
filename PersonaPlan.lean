import Persona.Jsonld

/-- `persona_plan <domain.jsonld>` reads a pull's facts on stdin and prints the plan to its goal. -/
def main (args : List String) : IO UInt32 := do
  let some path := args.head? | IO.eprintln "usage: persona_plan <domain.jsonld>" *> pure 2
  let domain ← IO.FS.readFile path
  let spec ← (← IO.getStdin).readToEnd
  IO.println (Persona.Jsonld.planOf domain spec)
  return 0
