# interactor-taskweft-persona

A persona that answers from a planning domain instead of a neural network: a
domain and a goal go in, an exact plan comes out, with no weights and no
sampling.

## What it is for

A language model answers by predicting the next token. A persona answers by
searching a goal-task network. The planner is a library here, not a reference:
the persona requires the RECTGTN domain, exactly as the character domain does,
and composes its answer in that shared GTN space. The state variable, the GTN
node, the plan element and the goal test are the planner's; the search, the
domain and the codebook are the persona's.

    pixi run ask           # a domain, a goal, and the plan that reaches it
    pixi run vocabulary    # the codebook and the actions it composes from
    pixi run test          # the green gate: 15 invariants, positive and negative controls

## What it accepts

A code or a number, and nothing else. Every value a persona binds is either a
number or a code in the domain's codebook, and a code is the vocabulary: one
level count per dimension, packed mixed-radix, the shape residual FSQ stacks
its stages in. Eight levels over four dimensions is 4096 codes a stage, and four
stages of those is 281474976710656 codes from thirty-two small integers.

That is the whole of what a caller can say. A code the codebook does not hold,
a variable the domain does not declare, and a goal it cannot reach are refused
by name rather than approximated, which is what makes the answer exact.

## What it is not

It knows only what the domain declares. It has no world knowledge, it does not
read prose, and it cannot answer a question that is not a goal. Every capability
it has is one somebody authored as an action.

## Build and run

Lean comes from elan; the `lean-toolchain` file pins v4.34.1.

    pixi run build
    pixi run test

`lake build` compiles the persona against the planner vendored in `thirdparty/`,
so the build fetches no domain from GitHub.

    lake exe persona_witness      # the persona's gate, 15 invariants
    lake exe character_witness    # the character domain's gate, 11 invariants

## Run the guest standalone
`persona.elf` runs with no viewer and no scene: a headless entities-godot host loads the
godot-sandbox extension, libriscv emulates the guest, and `Sandbox.vmcall` reaches
`persona_version` and `persona_ask`. The script exits non-zero unless the guest answers a
goal with a plan and refuses an undeclared goal by name.

    GODOT=<entities-godot editor binary, double precision> \
    SANDBOX_ADDON=<godot_sandbox addon dir, with bin/godot-riscv.gdextension> \
    tools/run_standalone.sh persona.elf [goal]

Two things the guest needs from its siblings. The Lean runtime asks the host for random bytes
with `getrandom`, because a sandbox has no `/dev/urandom` (`interactor-lean-guest`,
`patches/runtime-guest.patch`). A guest function returns a `Variant`, which is what `vmcall`
reads back (`guest/main.cpp`).

## Build the guest on a desk
The guest builds from a workspace laid out as the goal manifest places it (`2-contract/guest-runtime`,
`3-interactor/lean-guest`, `3-interactor/taskweft-persona`, `5-repository/riscv64-sysroot`). Three things
go wrong on a fresh Mac:

- **Compiler.** Apple's clang has no riscv64 backend. Take clang and lld from the sysroot repo's own
  pixi environment (`pixi install` in `5-repository/riscv64-sysroot`, then put
  `.pixi/envs/default/bin` first on `PATH`), as `guest.yml` does. Do not use a Homebrew LLVM.
- **Lean.** Set `ELAN_TOOLCHAIN=leanprover/lean4:v4.34.1`. The generated C must match the runtime,
  and configure stops with `host lean is 4.35.0, LEAN_VERSION is 4.34.1` otherwise.
- **Clone URLs.** A desk with `url.git@github.com:.insteadOf https://github.com/` and no SSH key cannot
  clone the sibling repos. Run the clones with `GIT_CONFIG_GLOBAL=/dev/null`.

Measured 2026-11-01 on osx-arm64, from fresh clones with `interactor-lean-guest` at 28cfe4d
(`getrandom`): configure took 78 s and `cmake --build <dir> --target persona` linked a 5.4 MB
riscv64 `persona`. `tools/run_standalone.sh` then printed `persona_version: 0.1.0`, a plan
`recharge, move_to_storage, pickup, move_to_shipping, dropoff` with `reached: true`, and
`{"refused":"undeclared_goal"}`. Without the `getrandom` change the guest dies opening
`/dev/urandom` (bad file descriptor) and `persona_ask` returns null.

## Vendored domains

Two repositories were vendored as git subtrees, each at the root of its own
directory. Both sources are archived, so this tree is the live copy of them and a
change lands here.

| Path | Repository | Ref |
| --- | --- | --- |
| `thirdparty/rectgtn-domain-c-abi` | `V-Sekai-archive/interactor-rectgtn-domain-c-abi` | `main` at `ec03ba9` |
| `thirdparty/character-domain-c-abi` | `V-Sekai-archive/interactor-character-domain-c-abi` | `main` at `42259d9` |

The subtree link records where each tree came from, and a pull still reads:

    git subtree pull --prefix=thirdparty/rectgtn-domain-c-abi https://github.com/V-Sekai-archive/interactor-rectgtn-domain-c-abi main --squash
    git subtree pull --prefix=thirdparty/character-domain-c-abi https://github.com/V-Sekai-archive/interactor-character-domain-c-abi main --squash

The rectgtn directory is content-identical to its source commit. The character
directory carries the same content with its planner reference moved from the
archived URL to the sibling directory, in `lakefile.lean`, `lake-manifest.json`,
`README.md`, `CITATION.cff`, `docs/domain.md` and `Character/GTN.lean`.

## The guest ELF a viewer loads

The persona also builds as a riscv64 guest for godot-sandbox: the model explorer
loads `persona.elf` and calls it, so a viewer can ask a domain for a plan with no
weights and no model. `guest/main.cpp` registers the surface, and the answer is
JSON.

    persona_version() -> String   the version of this surface
    persona_ask(goal) -> String   the plan that reaches `goal`, as JSON, or the
                                  refusal by name; an empty goal means the
                                  domain's own default

Build it with the goal manifest's siblings (`2-contract/guest-runtime` for
`sandbox_api`, `3-interactor/lean-guest` for the Lean runtime and Init):

    cmake -S guest -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_TOOLCHAIN_FILE=<workspace>/5-repository/riscv64-sysroot/toolchain.cmake \
      -DGUEST_RUNTIME_ROOT=<workspace>/2-contract/guest-runtime \
      -DLEAN_GUEST_DIR=<workspace>/3-interactor/lean-guest
    cmake --build build --target persona
    python3 tools/check_elf.py build/persona

`guest.yml` publishes `persona-elf-<sha>`: the artifact the viewer's release
pipeline downloads by that prefix.

A Lean guest links static glibc, so the linker puts an ifunc trampoline in
`.iplt`, outside `.text`. libriscv loads only `.text` unless
`ignore_text_section` is set, and godot-sandbox does not set it yet, so the guest
loads and its first call faults. That is the one thing between this ELF and the
viewer; the translated-vs-interpreted gate lands with it.

## Agent-to-Agent

The persona is an [A2A v1.0](https://hermes-agent.nousresearch.com/docs/user-guide/messaging/a2a)
peer. A caller sends a goal as the text of a `SendMessage`, and the reply is the
persona's own answer, byte for byte what `persona_ask` returns, in one text part.

    pixi run a2a-test      # the A2A gate: 22 invariants, positive and negative controls
    lake exe persona_a2a --card [url]   # the Agent Card
    lake exe persona_a2a                # JSON-RPC over stdio, one request a line

`Persona/A2A.lean` is the protocol and nothing else: JSON-RPC text in, JSON-RPC
text out. It opens no socket, so the host picks the transport and serves
`agentCard` at `/.well-known/agent-card.json`.

| Method | Answer |
| --- | --- |
| `SendMessage`, `message/send` | the goal's plan, or the refusal by name, as a Message |
| `GetTask`, `CancelTask` | `-32001`: the persona keeps no task |
| `SendStreamingMessage`, `SubscribeToTask` | `-32004`: nothing to stream |
| anything else | `-32601`; a malformed body is `-32700`, a message with no text part `-32602` |

A refusal is an answer, not a transport error: an undeclared goal comes back as
`{"refused":"undeclared_goal"}` inside a successful reply.

The guest ELF does not carry this surface. It links only `Init`, and the JSON
parser lives in `Lean.Data`, so A2A is for the host executable.

## Licence

MIT.
