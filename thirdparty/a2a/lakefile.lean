import Lake
open Lake DSL

package «a2a» where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

-- The library: the protocol, the routes, and the HTTP/1.1 and stdio transports.
@[default_target]
lean_lib «A2A» where
  srcDir := "."

-- An echo agent served over HTTP/1.1 or stdio, to run the library end to end.
@[default_target]
lean_exe «a2a_demo» where
  root := `Demo

-- The green gate: a positive and a negative control per invariant, exit 0 and
-- print "OK:" when every invariant holds.
@[default_target]
lean_exe «a2a_witness» where
  root := `Witness
