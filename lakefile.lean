import Lake
open Lake DSL

package «persona» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

-- The planner is a library, not a reference. The RECTGTN domain is vendored as a
-- subtree, so the build reads the planner from this tree rather than over the network.
require «taskweft» from "thirdparty/rectgtn-domain-c-abi"

-- The character domain unions with the same planner, and is vendored beside it.
require «character» from "thirdparty/character-domain-c-abi"

@[default_target]
lean_lib «Persona» where
  srcDir := "."

-- The ask surface: one domain, one goal, one answer printed.
@[default_target]
lean_exe «persona» where
  root := `PersonaMain

-- The green gate: a positive and a negative control per invariant, exit 0 and
-- print "OK:" when every invariant holds.
@[default_target]
lean_exe «persona_witness» where
  root := `PersonaWitness
