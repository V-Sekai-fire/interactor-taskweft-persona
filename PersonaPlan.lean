import Persona.Jsonld
import Persona.Compose

/-- A file's text, or why it could not be read: a missing file is a result, not an exception. -/
def readText (path : String) : IO (Except String String) := do
  match ← (IO.FS.readFile (System.FilePath.mk path)).toBaseIO with
  | .ok text => pure (.ok text)
  | .error e => pure (.error s!"{path}: {e}")

def readAll : List String → IO (Except String (List String))
  | [] => pure (.ok [])
  | p :: ps => do
    match ← readText p with
    | .error e => pure (.error e)
    | .ok t =>
      match ← readAll ps with
      | .error e => pure (.error e)
      | .ok ts => pure (.ok (t :: ts))

/-- `persona_plan <domain.jsonld[,more.jsonld...]> <problem.jsonld> [plan.jsonld]` prints the plan document, and
writes it to the third path when one is given. Several domains, separated by commas, are composed in that order
(`Persona/Compose.lean`) and planned as one. Exit 2: usage, 3: a document could not be read or composed. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | domains :: problem :: rest =>
    match ← readAll (domains.splitOn ",") with
    | .error e => IO.eprintln s!"cannot read: {e}" *> pure 3
    | .ok texts =>
      match ← readText problem with
      | .error e => IO.eprintln s!"cannot read: {e}" *> pure 3
      | .ok prob =>
        let composed : Except String String :=
          match texts with
          | [one] => .ok one
          | many => Persona.Compose.merge many
        match composed with
        | .error e => IO.eprintln s!"cannot compose the domains: {e}" *> pure 3
        | .ok domain =>
          let plan := Persona.Jsonld.planOf domain prob
          IO.println plan
          match rest.head? with
          | some out => (IO.FS.writeFile (System.FilePath.mk out) (plan ++ "\n")).toBaseIO >>= fun
            | .ok _ => pure 0
            | .error e => IO.eprintln s!"cannot write {out}: {e}" *> pure 3
          | none => pure 0
  | _ => IO.eprintln "usage: persona_plan <domain.jsonld[,more.jsonld...]> <problem.jsonld> [plan.jsonld]" *> pure 2
