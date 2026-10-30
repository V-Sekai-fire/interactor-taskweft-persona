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

## Licence

MIT.
