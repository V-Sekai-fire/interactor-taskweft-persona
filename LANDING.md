# Where a new repository goes, and why

The ask surface is a consumer of the RECTGTN planner. It carries no engine of
its own, so it is placed as a sibling of the family it consumes rather than
beside the engine.

## The constraint that decides the org

The desk's GitHub App installation covers **V-Sekai-fire and nothing else** — 52
repositories, read from `GET /installation/repositories`. The planner family
moved to **V-Sekai-archive** on 2026-10-29:

| repository | now at | note |
| --- | --- | --- |
| interactor-rectgtn-domain-c-abi | V-Sekai-archive | the engine this consumes |
| interactor-character-domain-c-abi | V-Sekai-archive | the first content domain |
| interactor-taskweft | V-Sekai-archive | the Elixir consumer |
| interactor-taskweft-nmm-personas | V-Sekai-archive | GRAFCET personas |
| contract-manifest-taskweft | V-Sekai-archive | archived |

`V-Sekai-fire/<planner repo>` answers `Moved Permanently` for every row above,
and the installation does not reach the new org, so a persona repository cannot
live beside the engine and cannot push engine changes. It pins the engine by
revision instead.

## The proposal

    V-Sekai-fire/interactor-taskweft-persona          (public, MIT)

placed on the interactor side of the live manifest at the same time it is
created, because an unplaced repository is drift:

    <project name="V-Sekai-fire/interactor-taskweft-persona"
             path="3-interactor/taskweft-persona" revision="main" />

The name follows the family the planner already uses — `interactor-taskweft-nmm-personas`
is the sibling — and the `persona` word is the operator's, 2026-10-30.

## What lands together

One bundle, per the session-bundle rule: the repository, its manifest row, and
the RFD that says why. The RFD is allocated from `SERIALS-vsekai-fabric.exs`
under pen 66606; the next free serial is read from that register at allocation
time rather than assumed here.

Commit subject, sentence case, no prefix:

    Add the persona that answers from a planning domain

## Not chosen

- **The engine repository.** V-Sekai-archive, no installation, and the engine is
  a domain C-ABI rather than an ask surface.
- **`manuals-weftspun`.** It already renders every RFD into a planning problem
  (`rectgtn/problems/`, 405 of them) and runs `mix rfd.rectgtn`, so a persona
  over the workspace's own work could live there as a mix task. It would put a
  C++ consumer inside the documents repository, and the documents repository's
  gates measure prose rather than plans.
- **The private live manifest org.** Correct if the persona is desk-private, but
  this desk cannot push there: the installation does not cover it.
