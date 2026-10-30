/-
Character domain — the UNION with the RECTGTN GTN planner.

`Planner.Types` (from the RECTGTN domain, vendored in the sibling directory)
defines the shared space: `Entity`, `PlanElement`, `RECTGTNNode`. This file lifts
the character domain's goals and actions into that shared space, so a character
plan is an ordinary GTN plan and the RECTGTN planner solves it unchanged.
-/

import Character.Types
import Planner.Types

namespace Character.GTN

/-- A character goal, in the character domain's own vocabulary. -/
inductive CharGoal where
  /-- Every bone carries skin; drop the harness/controller bones. -/
  | cleanRig
  /-- Put the arms under a garment without penetrating it. -/
  | fitUnderGarment (garment : String)
  /-- Export one OpenUSD file to `path` (no controller harness). -/
  | exportUsd (path : String)
  deriving Repr, DecidableEq

/-- The union: lift a character goal into the shared GTN as a task node. Every
    character goal becomes a `RECTGTNNode.task`, so the RECTGTN planner sees it
    as an ordinary task. -/
def toGTN : CharGoal → RECTGTNNode
  | .cleanRig            => .task "char.cleanRig" []
  | .fitUnderGarment g   => .task "char.fitUnderGarment" [g.length]
  | .exportUsd p         => .task "char.exportUsd" [p.length]

/-- A character action is a GTN plan element. -/
def actionOf (name : String) (params : List Nat) : PlanElement :=
  .action name params

/-- Every character goal lifts to a task node (never a goal/verify node), so the
    union is closed under `toGTN`. -/
theorem toGTN_is_task (g : CharGoal) :
    ∃ name params, toGTN g = RECTGTNNode.task name params := by
  cases g with
  | cleanRig => exact ⟨"char.cleanRig", [], rfl⟩
  | fitUnderGarment g => exact ⟨"char.fitUnderGarment", [g.length], rfl⟩
  | exportUsd p => exact ⟨"char.exportUsd", [p.length], rfl⟩

/-- A character's identity is an entity in the shared space. -/
def entityOf (c : Character) : Entity := c.id

end Character.GTN
