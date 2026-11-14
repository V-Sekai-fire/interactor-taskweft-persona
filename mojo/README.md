# interactor-taskweft-persona in Mojo

The persona's core, ported from Lean to Mojo 1.3 (`mojo==1.3.0.dev2026111316`), and tested with
[contract-witness-mojo](https://github.com/V-Sekai-fire/contract-witness-mojo), vendored as a subtree
in `thirdparty/witness-mojo`.

    cd mojo
    pixi run test       # 43 checks: invariants, 6 properties on the witness ladder, 5 planted-false controls
    pixi run mutants    # 12 planted bugs in the port; every one must turn the gate red
    pixi run parity     # 1505 grid specs through Lean (the oracle) and Mojo; answers must match line for line
    pixi run ask        # same output as `lake exe persona`
    pixi run vocabulary # same output as `lake exe persona --vocabulary`

`parity` and `ask` compare against the Lean build, so they need elan (`ELAN_TOOLCHAIN=leanprover/lean4:v4.34.1`) and a prior `lake build`.

## Slices

| Slice | Lean source | Mojo | State |
| --- | --- | --- | --- |
| Codebook, value, action, domain, search | `Persona.lean` | `src/persona/core.mojo` | ported |
| Delivery domain, guest JSON | `Persona/Demo.lean`, `Persona/Guest.lean` | `src/persona/guest.mojo` | ported |
| Skill grid | `Persona/Grid.lean` | `src/persona/grid.mojo` | ported, Lean parity |
| CLI | `PersonaMain.lean` | `app/ask.mojo` | ported, output identical |
| RECTGTN JSON-LD planner, temporal schedule | `Persona/Jsonld.lean`, `Persona/Web.lean` | | not yet |
| KHR_interactivity graphs | `Persona/Khr.lean` | | not yet |
| A2A peer | `Persona/A2A.lean`, `thirdparty/a2a` | | not yet |
| riscv64 guest ELF, wasm shim | `guest/`, `wasm/` | | not yet |

The 11 gate checks that need the JSON-LD planner (campus gold plan, temporal, GTPyhop cases, enums, vocab, params, graph, KHR)
are not ported, so this gate is not the Lean gate's 29 invariants. It holds the 18 checks of the Lean list that the core owns, plus its own.

## What differs from the Lean

- No `Nat`. Codebook arithmetic is `Int` (the 2^48 vocabulary fits). Grid ids are kept as canonical decimal text, so a huge id cannot overflow.
- `PlanElement` is the action name: the Lean `command` element is never produced by the search.
- `Value` is `PValue`, because the witness ladder exports a `Value` of its own.
- The search returns a `Bool` and fills a `mut` plan, since a generic `Optional[List]` result is awkward without closures.

## Not verified

- Not run on linux-64 or in CI. No workflow was added.
- The parity corpus is skewed: 671 of 1505 answers are `undeclared_goal`.
