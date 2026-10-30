# interactor-rectgtn-domain-c-abi

The RECTGTN **domain C-ABI** for the IEC 61131-3 function-block-diagram (FBD) /
gltf2-interactivity taskweft. This is the guest program that the **RISC-V Linux
guest** (godot-sandbox / libriscv) loads and runs: a pure-Lean reference model,
exposed through the C-ABI `rectgtn_api.h`.

## How it runs: the host calls the domain natively

The domain logic lives in **pure Lean**. At load time the godot-sandbox addon
**binary-translates** the RISC-V guest's `.text` into C99
(`bintr-<hash>.c`, via `tr_emit`), clang-compiles it into a native shared
library, and the host calls the `rectgtn_*` functions through that translation
(`sb.has_function` / `sb.vmcall`).

That "compiles to c" step is the **existing green engine**, not a future step:
it is the same mechanism the motion / skintokens / rfdetr guests are green on
(`tools/check_bintr.exs` — translated output == interpreted output, byte for
byte). It is what proves the RECTGTN domain runs on the host.

So the pipeline is:

```
pure-Lean domain (this repo)
  -> Lean-compiled RISC-V guest ELF (rectgtn.elf)
  -> godot-sandbox addon binary-translation  -> native C
  -> host calls rectgtn_* via sb.vmcall
```

## What it is

- A pure-Lean domain model (`lean/`) for RECTGTN — Relationship-Enabled
  Capability-Temporal Goal-Task-Network — with formal properties.
- A **C-ABI** (`api/rectgtn_api.h`) the domain is exposed through, built for
  the RISC-V guest.
- A **guest** (`guest/`) — the RISC-V64 Linux executable the sandbox loads,
  emitting the `.sandbox_variant` section (SBXV magic + Variant size) and
  exporting the `rectgtn_*` symbols.
- The **planner engine** — the C++20 implementation of the same model
  (`standalone/`), wrapped as the Erlang NIF `c_src/taskweft_nif.cpp` and
  exposed to Elixir as `taskweft_nif` (`lib/`, `mix.exs`). It builds into
  `priv/libtaskweft_nif.so` from the repository root, beside the Lean package.

The Lean model and the C++ engine are two implementations of one domain: the
witness exes certify the model, the NIF's differential harness cross-checks the
engine against the same corpus, and `test/differential/` holds the fixtures both
read.

This repository took the planner when `V-Sekai-fire/nif` was retired; that fork
of `taskweft/nif` is archived, and its history is merged in here.

## Two invariants

1. **Pascal strings.** Every string across the C-ABI is length + bytes, exactly
   like Godot's native `String` — never null-terminated (issue #1).
2. **Temporal is intrinsic.** Every plan is a temporal plan; the temporal
   block is a required member of `RectGTNPlan`, not a separate
   `temporal(plan)` recompute function (issue #2).

## Build the Lean reference model

```sh
lean  # Lean 4 toolchain (4.35+)
lake build
lake exe mcp_auth_witness   # witness gate: must exit 0, print "OK:"
lake exe khr_tier1_witness   # witness gate: must exit 0, print "OK:"
```

Both witness exes are the green gate for the domain (they certify the MCP
authorization ReBAC witness and the KHR Tier 1 decomposition witness, and
fail with a non-zero exit on refusal).

## Build the guest ELF

```sh
riscv64-linux-gnu-gcc --version
riscv64-linux-gnu-g++ --version
cmake -B build \
  -DCMAKE_TOOLCHAIN_FILE=guest/toolchain.cmake \
  -DCMAKE_BUILD_TYPE=MinSizeRel -DSTRIPPED=ON -S guest
cmake --build build
file build/rectgtn.elf
```

The artifact is a stripped, position-independent **RISC-V64 Linux ELF** with a
`.sandbox_variant` section (`SBXV` magic + the 4-byte little-endian Variant
size, 40 for double precision) and the `rectgtn_*` symbols resolvable by
name, mirroring `godot-sandbox`'s `gdscript.elf` build.

## Build the planner NIF

```sh
mix deps.get
mix compile                  # builds priv/libtaskweft_nif.so
mix test                     # unit suite
mix test --only differential # the differential harness against the corpus
```

The NIF is no longer published to Hex. Consumers take it as a git dependency on
this repository — the mix project sits at the root, so no subdirectory is
involved:

```elixir
{:taskweft_nif, git: "https://github.com/V-Sekai-fire/interactor-rectgtn-domain-c-abi"}
```

`interactor-taskweft` is the consumer; its `.github/workflows/nif.yml` here runs
the same three commands on Linux, Windows (mingw and msvc) and macOS.

## Stage 1: the C-shim guest

The Lean core is not yet compiled to a RISC-V guest — that requires the Lean
runtime port to `riscv64-linux` (RFD 66606-2153 stage 3). Until it lands, the
guest exports **stub** `rectgtn_*` bodies so the CI can prove the guest ELF
shape (symbol names present, `.sandbox_variant` correct) without the runtime
port. When stage 3 lands, these stubs become the real Lean-compiled RISC-V
functions, and the addon's binary-translation engine converts them to native
C at load time (this file shrinks to glue).

## Subtree

This repo is designed to be pulled as a subtree by `interactor-taskweft`,
which deletes its own C implementation and uses this tree. The C-ABI is the
contract between the guest and the host; the pure-Lean reference model is
authoritative, and the host reaches it natively through the addon's
binary-translation of the RISC-V guest.

## License

MIT.
