import Persona.Guest

namespace Persona.Grid

open Persona

/-- One skill on the grid: its id, whether it is already done, and the skills it needs. -/
structure Skill where
  id    : Nat
  done  : Bool
  needs : List Nat

def words (line : String) : List String :=
  (line.splitOn " ").filter (fun w => w != "")

/-- The spec is one `skill ID DONE NEED...` line a skill and one `goal ID` line. -/
def parse (spec : String) : Option (List Skill × Nat) :=
  let lines := ((spec.splitOn "\n").map words).filter (fun l => !l.isEmpty)
  let skills := lines.filterMap fun
    | "skill" :: i :: d :: ns => do
      let i ← i.toNat?
      let d ← d.toNat?
      pure { id := i, done := d == 1, needs := ns.filterMap String.toNat? }
    | _ => none
  let goals := lines.filterMap fun
    | ["goal", g] => g.toNat?
    | _ => none
  match goals with
  | [g] => some (skills, g)
  | _   => none

def indexOf (ss : List Skill) (id : Nat) : Option Nat :=
  ss.findIdx? (fun s => s.id == id) |>.bind fun i => if i < ss.length then some i else none

/-- The grid as a persona domain: one variable a skill, one action a skill still to do,
and the needs of a skill as the variables its action requires. -/
def domainOf (ss : List Skill) : Domain :=
  let todo := ss.filter (fun s => !s.done)
  let slot := fun (id : Nat) => (indexOf ss id).getD 0
  { variables := ss.mapIdx fun i s => ⟨i, if s.done then 1 else 0⟩
  , codebook := { levels := [2] }
  , actions := todo.map fun s => ⟨s!"activate-{s.id}", [], [(slot s.id, .number 1)]⟩
  , requires := todo.map fun s =>
      (s!"activate-{s.id}", (s.needs.filterMap (indexOf ss)).map fun j => (j, 1)) }

/-- The activation order that reaches the goal, or the refusal by name. -/
def planOf (spec : String) : String :=
  match parse spec with
  | none => "{\"refused\":\"bad_spec\"}"
  | some (ss, g) =>
    match indexOf ss g with
    | none => "{\"refused\":\"undeclared_goal\"}"
    | some gi =>
      let dom := domainOf ss
      let goal : Goal := { node := .goal_geq gi 1 }
      match ({ domain := dom } : Persona).answer goal (dom.actions.length + 1) with
      | none => "{\"refused\":\"unreachable\"}"
      | some plan =>
        let reached := is_node_satisfied (dom.execute plan) goal.node
        "{\"plan\":" ++ Guest.planJson plan ++ ",\"reached\":"
          ++ (if reached then "true" else "false") ++ "}"

/-- The guest entry the wasm shim calls: one spec in, one answer out. -/
@[export persona_plan_text]
def planText (spec : String) : String := planOf spec

end Persona.Grid
