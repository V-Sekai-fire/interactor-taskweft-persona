import Persona.Grid
/-- Same line format as app/grid_dump.mojo: hex in, planOf out. -/
def unhex (s : String) : String :=
  let v := fun (c : Char) => if c.toNat ≥ 97 then c.toNat - 87 else c.toNat - 48
  let rec go : List Char → List UInt8
    | a :: b :: rest => UInt8.ofNat (v a * 16 + v b) :: go rest
    | _ => []
  String.fromUTF8! (ByteArray.mk (go s.toList).toArray)
def main (args : List String) : IO Unit := do
  let t ← IO.FS.readFile args.head!
  for l in (t.splitOn "\n").filter (· != "") do
    IO.println (Persona.Grid.planOf (if l == "-" then "" else unhex l))
