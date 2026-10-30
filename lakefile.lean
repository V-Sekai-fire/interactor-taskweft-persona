import Lake
open Lake DSL

package «persona» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

-- The planner is a library, not a reference. The persona requires the RECTGTN
-- domain over GitHub, exactly as the character domain does, and composes its
-- answer in the shared GTN space.
require «taskweft» from git
  "https://github.com/V-Sekai-fire/interactor-rectgtn-domain-c-abi" @ "main"

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
