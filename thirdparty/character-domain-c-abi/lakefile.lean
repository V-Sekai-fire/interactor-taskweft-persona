import Lake
open Lake DSL

package «character» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

-- UNION with the RECTGTN domain, vendored in the sibling directory: the character
-- domain requires the planner rather than copying its kernel, so a character goal
-- is a first-class GTN node (see Character/GTN.lean).
require «taskweft» from "../rectgtn-domain-c-abi"

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
