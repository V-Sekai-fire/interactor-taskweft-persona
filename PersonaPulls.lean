import Persona.Pulls

/-- Read a pull request's facts on stdin and print the plan to its goal. -/
def main : IO Unit := do
  let spec ← (← IO.getStdin).readToEnd
  IO.println (Persona.Pulls.planOf spec)
