import Lake
open Lake DSL

package «character» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

-- UNION with the RECTGTN domain, over GitHub.
--
-- The character domain does not copy the GTN planner kernel and does not reach
-- it through a relative path: it requires the RECTGTN domain by URL, so the two
-- Lean packages compose into one build and a character goal is a first-class GTN
-- node (see Character/GTN.lean). This is the "union" -- the shared Entity /
-- PlanElement / RECTGTNNode space, pulled in from GitHub.
require «taskweft» from git
  "https://github.com/V-Sekai-fire/interactor-rectgtn-domain-c-abi" @ "main"

-- The character domain: rig, skin, pose, roll-orientation normalization, and the
-- union of character goals with the shared GTN.
@[default_target]
lean_lib «Character» where
  srcDir := "."

-- The green gate: one positive and one negative control per invariant. Exits 0
-- and prints "OK:" when every invariant holds; a refusal exits non-zero.
@[default_target]
lean_exe «character_witness» where
  root := `CharacterWitness
