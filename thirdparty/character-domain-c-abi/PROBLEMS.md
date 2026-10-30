# Inventory of problems

Two inventories: the character-work problems this domain formalizes, and the
triage of the RECTGTN domain's issue tracker
(`V-Sekai-fire/interactor-rectgtn-domain-c-abi/issues`), which is the sibling the
domain unions with.

## A. Character-work problems (what the domain formalizes)

| # | Problem | Where it lives now | Status |
|---|---------|--------------------|--------|
| C1 | **Controller/harness bones in the rig.** The Elaina rig carries 877 bones; only ~292 are needed (202 skinned + their ancestors). The other 585 are zero-skin-weight controller/reference/pole/IK harness bones that must be removed before export. | `Character.HarnessBones` / `CleanRig`; witness checks the removal set is exactly the zero-weight bones and disjoint from the skinned set. | Formalized; the removal criterion is proved. |
| C2 | **The harness leaks into the USD export.** A single-file `.usdz` must exclude controller harness, `cs_*` gizmos and junk empties, but `bpy.ops.wm.usd_export` ships everything. | `Character.GTN.CharGoal.cleanRig` (a GTN task); the export step is `CharGoal.exportUsd`. | Goal modeled; the USD-side filter is open. |
| C3 | **Grey/shiny exported materials.** The live Blender PBR is correct (skin R=0.45/S=0.2), but the exported USD renders grey-shiny because the imported Principled BSDF inputs are node-linked rather than flat. | — (material graph, not a rig/pose fact) | Open; out of this domain's scope. |
| C4 | **Arms penetrate the coat.** The authored rest pose has arms ~65 deg from vertical and pokes the overcoat; one shoulder is flapped. The fix must rotate arms under the coat without introducing twist. | `Character.shortestArc` (roll orientation normalization); `CharGoal.fitUnderGarment`. | Roll normalization formalized; the target pose is open. |
| C5 | **Arm asymmetry with identity quats.** Reverting FK quats to identity still gave asymmetric arms (79.7 deg left vs 63.7 deg right), so the asymmetry is baked into the loaded armature, not the quats. | `Character.shortestArc` (a symmetric, deterministic completion) | Method available; the baked rest frames are open. |
| C6 | **A-pose vs T-pose for VRM/springbone.** VRM expects a clean A-pose base it converts to T-pose; the coat is sculpted to the rest/armature, so final rotations must match rest bones without poking. | `Character.Pose`, `Character.shortestArc` | Pose type + roll normalization in place. |
| C7 | **Blender edit-mode bone deletion is blocked headlessly.** `bpy.ops.object.select_all.poll() failed, context is incorrect`; `armature.data.bones` is read-only, `arm.mode` is read-only. | — (tooling) | Open; the USD-side removal (C1/C2) is the workaround. |

## B. Triage of the RECTGTN domain issues

Triaged against `docs/rectgtn.md`, `priv/schemas/rectgtn_domain.schema.json`,
`lib/taskweft/compose.ex`, and `Planner/Types.lean`. Each issue carried a
`triage` label and a verdict comment on the tracker. Every row below names the
fix that landed, or why nothing is tracked.

| # | Title | Type | Verdict | State |
|---|-------|------|---------|-------|
| 3 | Branch concurrency in temporal planning | enhancement | **Folded into #8** as its ship-side; closed on the tracker, not tracked separately. | Folded |
| 4 | `goal_methods` in `Taskweft.Compose` | doc/cleanup | **Verified:** absent from the schema (`additionalProperties:false`) yet merged at `compose.ex:52` and listed in both tables. | Fixed in `interactor-taskweft`#18 |
| 5 | Syntactic sugar `capabilities.entities` | needs-decision | **Verified inconsistency:** sugar exists for capabilities but not for action requirements. Operator ruled: unship for a single canonical `graph.edges`. | `interactor-taskweft`#20 + the loader change (nif#2, now in `interactor-rectgtn-domain-c-abi`) |
| 6 | Hardcoded ReBAC relations | bug / spec-drift | **Verified:** the spec listed 9 relations incl. `CAN_ENTER`/`CAN_INSTANCE`; the Lean `RelationType` has 8 incl. `IS_A`. The sets differed. | Fixed in `interactor-taskweft`#16 |
| 7 | `TwMultiGoal` permutation backjumping | question | Needed usage data before any keep/unship call. Operator ruled Keep. | Closed, keep |
| 8 | Purely linear "temporal" scheduling | enhancement | **Verified:** durations accumulated linearly while the model already had `after`/`before`/`between`/`within`. Operator ruled: implement real concurrency. | the scheduler change (nif#3, now in `interactor-rectgtn-domain-c-abi`) + `interactor-taskweft`#21 |
| 9 | Composition rules for `capabilities`/`enums` | bug | **Verified, highest impact:** overlays could not add capability edges, memberships or enums — broke the documented overlay use case. | Fixed in `interactor-taskweft`#15 |
| 10 | Tier-2 flow-graph execution engine | enhancement | Valid roadmap item (ADR 0003); not a defect. | Tracked against ADR 0003 |
| 11 | Replan spec for `fail_step >= 0` | bug / doc | **Verified contract hole:** the soundness contract defined only `fail_step == -1`; the C-ABI implied `>= 0` is re-solved but never said how. | Fixed in `interactor-taskweft`#19 + `interactor-rectgtn-domain-c-abi`#13 |

The "fix first" tier is empty: the four verified defects (#4, #6, #9, #11) are
fixed and their issues closed, and the two design calls (#5, #8) carry the
operator's ruling and their PRs. #7 was ruled Keep. #10 is the one open issue
that tracks no code change.

### Where the fixes live

Each issue is fixed in the repository that owns the file: the spec, the schema
and `Taskweft.Compose` in `interactor-taskweft`; the C-ABI header in
`interactor-rectgtn-domain-c-abi`; the planner's loader and temporal analysis in
the same repository, which took them when `V-Sekai-fire/nif` was retired and
archived. The tracker belongs to the sibling domain repo, so an issue closes when
the fixes it names have landed, not when a single PR opens.

`Taskweft.plan/1` calls the NIF directly and does not run the schema, so #5's
schema change alone left the sugar working at plan time, and #8's spec text
describes a scheduler the Hex release `0.2.0-dev.20` did not have. That gap
closes through a git dependency rather than a Hex publish: `taskweft_nif` lapses
at `0.2.0-dev.21` and `interactor-taskweft` pins the planner's repository by SHA,
so the two plan-level controls land as an ordinary re-pin.
