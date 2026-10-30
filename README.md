# interactor-taskweft-persona

A persona that answers from a planning domain instead of a neural network: a
domain and a goal go in, an exact plan comes out, with no weights and no
sampling.

## What it is for

A language model answers by predicting the next token. A persona answers by
searching a goal-task network. The planner is a library here, not a reference:
the persona requires the RECTGTN domain over GitHub, exactly as the character
domain does, and composes its answer in that shared GTN space. The state
variable, the GTN node, the plan element and the goal test are the planner's;
the search, the domain and the codebook are the persona's.

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

`lake build` fetches the planner from GitHub and compiles it as a dependency, so
the persona is always built against a planner revision that is recorded in
`lake-manifest.json`.

## Licence

MIT.
