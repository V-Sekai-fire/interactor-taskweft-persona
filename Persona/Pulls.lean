import Persona.Grid

namespace Persona.Pulls

open Persona

/-- The pull-request lifecycle of this repository as a planning domain. Variables:
0 staged branch name, 1 pushed, 2 open, 3 body free of agent credit, 4 `Lean core + self-test`
green, 5 `persona-elf` green, 6 the operator approves, 7 merged, 8 both checks green.
No action writes 6: the operator merges, so an agent's plan to merge is refused until he says so. -/
def names : List String :=
  ["staged", "pushed", "open", "clean", "lean", "elf", "approved", "merged", "checked"]

def slot (n : String) : Option Nat := names.findIdx? (· == n) |>.bind fun i =>
  if i < names.length then some i else none

def domainOf (init : List (String × Nat)) : Domain :=
  let v := fun (n : String) => (slot n).getD 0
  { variables := names.mapIdx fun i n => ⟨i, ((init.find? (·.1 == n)).map (·.2)).getD 0⟩
  , codebook := { levels := [2] }
  , skipDone := true
  , actions :=
      [ ⟨"name_branch_by_stage", [], [(v "staged", .number 1)]⟩
      , ⟨"push_branch", [], [(v "pushed", .number 1)]⟩
      , ⟨"strip_agent_footer", [], [(v "clean", .number 1)]⟩
      , ⟨"open_pull", [], [(v "open", .number 1)]⟩
      , ⟨"run_lean_check", [], [(v "lean", .number 1)]⟩
      , ⟨"run_elf_check", [], [(v "elf", .number 1)]⟩
      , ⟨"collect_checks", [], [(v "checked", .number 1)]⟩
      , ⟨"merge_pull", [], [(v "merged", .number 1)]⟩ ]
  , requires :=
      [ ("push_branch", [(v "staged", 1)])
      , ("open_pull", [(v "pushed", 1), (v "clean", 1)])
      , ("run_lean_check", [(v "open", 1)])
      , ("run_elf_check", [(v "open", 1)])
      , ("collect_checks", [(v "lean", 1), (v "elf", 1)])
      , ("merge_pull", [(v "open", 1), (v "checked", 1), (v "approved", 1)]) ] }

/-- One `var NAME 0|1` line a fact and one `goal NAME` line. -/
def parse (spec : String) : Option (List (String × Nat) × String) :=
  let ls := ((spec.splitOn "\n").map Grid.words).filter (!·.isEmpty)
  let init := ls.filterMap fun
    | ["var", n, b] => (slot n).bind fun _ => b.toNat?.map (n, ·)
    | _ => none
  match ls.filterMap (fun | ["goal", g] => some g | _ => none) with
  | [g] => some (init, g)
  | _   => none

def planOf (spec : String) : String :=
  match parse spec with
  | none => "{\"refused\":\"bad_spec\"}"
  | some (init, g) =>
    match slot g with
    | none => "{\"refused\":\"undeclared_goal\"}"
    | some gi =>
      let dom := domainOf init
      let goal : Goal := { node := .goal_geq gi 1 }
      match ({ domain := dom } : Persona).answer goal 12 with
      | none => "{\"refused\":\"unreachable\"}"
      | some plan =>
        "{\"plan\":" ++ Guest.planJson plan ++ ",\"reached\":"
          ++ (if is_node_satisfied (dom.execute plan) goal.node then "true" else "false") ++ "}"

@[export persona_pulls_text]
def pullsText (spec : String) : String := planOf spec

end Persona.Pulls
