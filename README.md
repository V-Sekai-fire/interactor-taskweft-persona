# interactor-taskweft-persona

A persona that answers from a planning domain instead of a neural network: it
takes a domain and a goal and returns the plan, with no weights and no sampling.

## What it is for

A language model answers by predicting the next token. This answers by searching
a goal-task network: the domain is a JSON-LD document that declares the
variables, the actions and the methods, the goal is a task list, and the answer
is the exact plan that reaches it — or a named reason it cannot.

The engine is the RECTGTN planner (`interactor-rectgtn-domain-c-abi`): its Lean
model is the reference, and its C++20 `standalone/` headers are the twin that
runs natively. This repository is the ask surface over that engine: one binary,
two file arguments, a plan on stdout.

    persona <domain.jsonld> <problem.jsonld> [origin ISO-8601 duration]

What comes back, in order:

- the goal, read back from the problem's `todo_list`;
- the plan, as action calls in order and as JSON;
- the temporal block: each step's duration, start and end from the origin;
- when no plan exists, the failure tree naming the task that could not be
  refined and why.

## What it accepts

A category or a number, and nothing else. Every argument a goal binds is either
a member of a declared category — an entity name, an enum member, a boolean — or
a number. There is no prose to parse: the persona composes only from its domain,
so a request in words reaches it by way of whoever authors the domain, or of a
grammar over the names the domain already holds.

    persona --vocabulary <domain.jsonld>

prints that surface: the categories and numbers the domain declares with their
current values, the actions with the parameters a call binds and their
durations, and the tasks a goal may ask for. An undeclared task is refused by
name rather than approximated, which is what makes the answer exact.

## What it is not

It knows only what the domain declares. It has no world knowledge, it does not
read prose, and it cannot answer a question that is not a goal. Every capability
it has is one somebody authored as an action or a method.

## Build and run

The headers come from a planner checkout, pinned by revision:

    PLANNER=../rectgtn-domain-c-abi make
    ./persona --vocabulary bench/domains/warehouse_domain.jsonld
    ./persona bench/domains/warehouse_domain.jsonld bench/problems/problem_single_delivery.jsonld

`verify.py` runs the planner's differential fixtures through the binary and
counts what it solved, so a change to the ask surface is measured rather than
asserted. It carries a control that must report NO PLAN, and it fails when the
planner checkout is absent.

## Licence

MIT.
