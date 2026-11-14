# interactor-taskweft-persona in Mojo

The persona's core, ported from Lean to Mojo 1.3 (`mojo==1.3.0.dev2026111316`), and tested with
[contract-witness-mojo](https://github.com/V-Sekai-fire/contract-witness-mojo), vendored as a subtree
in `thirdparty/witness-mojo`.

    cd mojo
    pixi run test            # 43 checks: the core, the grid and the guest surface, on the witness ladder
    pixi run test-jsonld     # 163 invariants: campus gold plan, temporal, GTN, web, and every case under tests/
    pixi run test-props      # 9: random needs-graphs against a model, codec round trips, planted-false controls
    pixi run mutants         # 12 planted bugs in the core; every one must turn its gate red
    pixi run mutants-jsonld  # 18 planted bugs in the planner, KHR runner and time codecs; every one must be caught
    pixi run parity          # 1505 grid specs through Lean (the oracle) and Mojo; answers match line for line
    pixi run parity-plan     # 397 domain/problem pairs through `persona_plan` and the Mojo planner; plan documents match byte for byte
    pixi run ask             # same output as `lake exe persona`
    pixi run vocabulary      # same output as `lake exe persona --vocabulary`

The two `parity` tasks compare against the Lean build, so they need elan (`ELAN_TOOLCHAIN=leanprover/lean4:v4.34.1`) and a prior `lake build persona persona_plan`.

## JSON

Mojo's standard library has no JSON parser. The planner reads documents with [EmberJson](https://github.com/bgreni/EmberJson)
0.5.0 (the most used JSON package for Mojo, in the modular-community channel), with EmberSerde 0.2.0 beneath it, both vendored as
subtrees in `thirdparty/`. The published packages are built for Mojo 1.1 and the 0.5.0 source for 1.2, so
neither compiles on 1.3 as it stands. `Patch EmberJson 0.5.0 and EmberSerde 0.2.0 for Mojo 1.3` is the whole change, 9 files, 23 lines:

- six `@__parameter` closures in `_deserialize/tape_indexed.mojo`, one each in `_index/indexer.mojo` (three), `slow_float_parse.mojo`, `_parser_helper.mojo` and `parser.mojo` take a capture list (`{mut idx, base}`) instead; the order is `def f(..) raises E {captures} -> T`;
- `Value`, `Object` and `Array` name `ConversionToPythonErrorType = Error`, which 1.3's `ConvertibleToPython` asks for;
- EmberSerde's `Tuple` deserializer asserts its elements are `Movable`.

All 38 of EmberJson's own test files pass on 1.3 with the patch (about 590 tests, run with `-D ASSERT=all`). The patch stays in this repo and is not sent upstream.

`src/persona/jdoc.mojo` copies a parsed `Value` once into an arena shaped like Lean's `Json`: an object's entries sorted by key, a missing key
reads as null, a node is an index.

## Slices

| Slice | Lean source | Mojo | State |
| --- | --- | --- | --- |
| Codebook, value, action, domain, search | `Persona.lean` | `src/persona/core.mojo` | ported |
| Delivery domain, guest JSON | `Persona/Demo.lean`, `Persona/Guest.lean` | `src/persona/guest.mojo` | ported |
| Skill grid | `Persona/Grid.lean` | `src/persona/grid.mojo` | ported, Lean parity |
| CLI | `PersonaMain.lean` | `app/ask.mojo` | ported, output identical |
| RECTGTN JSON-LD planner, temporal schedule, shortest plan, web entries | `Persona/Jsonld.lean`, `Persona/Web.lean` | `src/persona/jsonld.mojo`, `app/plan.mojo` | ported, Lean parity on 397 pairs |
| KHR_interactivity graphs | `Persona/Khr.lean` | `src/persona/khr.mojo` | ported, 19 graphs plus one extra |
| ISO-8601 durations, datestamps | `Planner/Iso8601Duration.lean`, `Jsonld.lean` | `src/persona/timeutil.mojo` | ported |
| A2A peer | `PersonaA2A.lean`, `thirdparty/a2a` | | dropped, not part of the Mojo port |
| riscv64 guest ELF, wasm shim | `guest/`, `wasm/` | | not yet |


The Lean gate's 29 invariants split across the two Mojo gates: 18 in `test`, and the campus, reach, chain, temporal, GTN and web checks
in `test-jsonld`, together with every file-driven case under `tests/` (enums, vocab, params, graph, the GTPyhop cases and the 19 KHR graphs).
The Lean `A2AWitness` is dropped with the A2A peer, and `BattleWitness` is not ported; the battle domain is compared through `parity-plan` only.

## What differs from the Lean

- No `Nat`. Codebook arithmetic is `Int` (the 2^48 vocabulary fits). Grid ids are kept as canonical decimal text, so a huge id cannot overflow.
- `PlanElement` is the action name: the Lean `command` element is never produced by the search.
- `Value` is `PValue`, because the witness ladder exports a `Value` of its own.
- The search returns a `Bool` and fills a `mut` plan, since a generic `Optional[List]` result is awkward without closures.

- Duplicate object keys: Lean keeps the last, EmberJson refuses the document, so the planner answers `bad_domain` or `bad_problem`.
- A number written with an exponent (`1e2`) is a float to EmberJson and so not an integer; Lean reads it as 100.
- Integers past 64 bits are floats here, and so not integers.
- One mutant is left out of `mutants-jsonld` on purpose: an equivalent one, explained in the script.

## Not verified

- Not run on linux-64 or in CI. No workflow was added.
- The grid parity corpus is skewed: 671 of 1505 answers are `undeclared_goal`. The plan corpus has 222 plans, 39 with a schedule, and 136 refusals.
- `shortest_of` and `goals_of` are checked by the ported Lean invariants only; the Lean `persona_plan` executable has no entry for them to diff against.
