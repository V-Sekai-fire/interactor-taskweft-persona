import Lean.Data.Json
import Persona.Jsonld

/-! Composition of domains: planning against several domain documents as one.

The documents are merged in the order given, before planning, and each stays an ordinary `domain:Definition`:
* actions are appended; an action name two documents both define is an error, since neither may silently replace the other;
* a method's alternatives are appended, so an earlier document's alternative is tried first (the planner tries them in order);
* variables are merged by name; a fact two documents both initialise must give it the same value.
Everything else (`@context`, `description`, ...) comes from the first document, and the name is the names joined with `+`. -/

namespace Persona.Compose
open Lean

def objOf (j : Json) : List (String × Json) := match j.getObj? with | .ok o => o.toList | .error _ => []
def arrOf (j : Json) : List Json := match j.getArr? with | .ok a => a.toList | .error _ => []
def strOf (j : Json) : String := match j.getStr? with | .ok s => s | .error _ => ""

/-- Add the entries of `more` to `acc` by key; `join` decides what two entries with the same key become. -/
def addAll (what : String) (join : String → Json → Json → Except String Json)
    (acc more : List (String × Json)) : Except String (List (String × Json)) :=
  more.foldlM (fun (acc : List (String × Json)) (k, v) =>
    match acc.find? (·.1 == k) with
    | none => pure (acc ++ [(k, v)])
    | some (_, old) => do
      let j ← join (what ++ " " ++ k) old v
      pure (acc.map fun (k', v') => if k' == k then (k', j) else (k', v'))) acc

def twice (what : String) (_ _ : Json) : Except String Json := throw (what ++ " is defined by two documents")

/-- Two definitions of one method: the second's alternatives follow the first's. -/
def joinMethod (_ : String) (a b : Json) : Except String Json :=
  pure (Json.mkObj (((objOf a).filter (·.1 != "alternatives")) ++
    [("alternatives", Json.arr ((arrOf (a.getObjValD "alternatives") ++ arrOf (b.getObjValD "alternatives")).toArray))]))

def sameFact (what : String) (a b : Json) : Except String Json :=
  if a == b then pure a else throw (what ++ " is initialised to two different values")

/-- Variables group by name; the facts of a group join. -/
def variables (docs : List Json) : Except String Json := do
  let groups ← docs.foldlM (fun (acc : List (String × Json)) d =>
    addAll "variable" (fun w a b => do
        let init ← addAll (w ++ " fact") sameFact (objOf (a.getObjValD "init")) (objOf (b.getObjValD "init"))
        pure (Json.mkObj (((objOf a).filter (·.1 != "init")) ++ [("init", Json.mkObj init)])))
      acc ((arrOf (d.getObjValD "variables")).map fun v => (strOf (v.getObjValD "name"), v))) []
  pure (Json.arr (groups.map (·.2)).toArray)

/-- The documents as one domain document. -/
def merge (texts : List String) : Except String String := do
  let docs ← texts.mapM Json.parse
  let first := (docs.head?).getD Json.null
  let actions ← docs.foldlM (fun acc d => addAll "action" twice acc (objOf (d.getObjValD "actions"))) []
  let methods ← docs.foldlM (fun acc d => addAll "method" joinMethod acc (objOf (d.getObjValD "methods"))) []
  let vars ← variables docs
  let name := "+".intercalate (docs.map fun d => strOf (d.getObjValD "name"))
  let own := ["name", "variables", "actions", "methods", "module", "composed_from"]
  pure (Json.compress (Json.mkObj (((objOf first).filter fun (k, _) => !own.contains k) ++
    [("name", Json.str name), ("variables", vars), ("actions", Json.mkObj actions), ("methods", Json.mkObj methods)])))

end Persona.Compose
