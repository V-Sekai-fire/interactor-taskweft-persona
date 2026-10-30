# interactor-character-domain-c-abi

A pure-Lean character model whose rig, skin and pose goals the RECTGTN planner solves unchanged.

## What it is for

Rig cleanup, harness removal and pose roll arrive as one-off scripts that no plan can reuse.

The **character domain C-ABI** — a pure-Lean reference model for character work (rig, skin,
pose, roll-orientation normalization, harness-bone removal), bridged to the **RISC-V Linux
guest** (godot-sandbox / libriscv) through the same C-ABI shape as the RECTGTN domain
(`interactor-rectgtn-domain-c-abi`).

The domain **unions with the RECTGTN GTN planner over GitHub**: it does not copy
the planner kernel and does not reach it through a relative path. `lakefile.lean`
requires the RECTGTN domain by URL, so the two Lean packages compose into one
build and a character goal is an ordinary RECTGTN task node.

So a character plan is a RECTGTN plan, and the RECTGTN planner solves it unchanged.
`theorem toGTN_is_task` certifies the lift is total and closed.

The guest still exports stub `character_*` bodies, because compiling the Lean core to RISC-V
waits on the Lean runtime port to `riscv64-linux` (RFD 66606-2153 stage 3). The pipeline, the
C-ABI invariants, the domain functions and the guest ELF build are in `docs/`.

## Build and run

```sh
lean            # Lean 4 toolchain (see lean-toolchain)
lake build
lake exe character_witness   # green gate: exits 0, prints "OK:"
```

Run the witness after every change to the domain, then take the next problem from
[`PROBLEMS.md`](PROBLEMS.md).

## Licence

MIT.
