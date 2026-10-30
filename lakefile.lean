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

-- The Agent-to-Agent server library is vendored beside them, so the build fetches nothing.
require «a2a» from "thirdparty/a2a"

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

-- Agent-to-Agent: the persona as an A2A v1.0 peer, JSON-RPC over stdio.
@[default_target]
lean_exe «persona_a2a» where
  root := `PersonaA2A

-- The A2A gate: a positive and a negative control per invariant.
@[default_target]
lean_exe «persona_a2a_witness» where
  root := `A2AWitness
