/*
 * rectgtn_api.h — C surface for the RECTGTN domain, embedded in a RISC-V
 * guest ELF (godot-sandbox / libriscv).
 *
 * The whole domain is pure Lean. On `lake build` the Lean core emits a `.c`
 * intermediate that implements every function below; this header is the
 * contract that intermediate must satisfy. There is no hand-written C
 * implementation of the domain logic -- only the guest entry point and the
 * I/O glue live in C (see guest/main.c).
 *
 * Two API invariants:
 *
 *   1. Pascal strings.   Every string crossing this boundary is length + bytes,
 *      exactly like Godot's native `String` -- NEVER null-terminated.  `length`
 *      counts UTF-8 bytes; `bytes` is NULL only when `length == 0`.
 *
 *   2. Temporal is intrinsic.   Every plan is a temporal plan.  The temporal
 *      block is a required, always-present member of `RectGTNPlan`, NOT a
 *      separate `temporal(plan)` function.  There is no free-standing temporal
 *      recompute -- the temporal block is computed once, per plan, and shipped
 *      with it.  (issue #2: "all RECTGTNs are temporal plans.")
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef RECTGTN_API_H
#define RECTGTN_API_H

#if defined(__cplusplus)
extern "C" {
#endif

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

/* ------------------------------------------------------------------------
 * Pascal string (Godot-style: length + bytes, no null terminator).
 *
 *   Input  : a borrowed `const RectGTNString *`. The caller keeps its bytes
 *            alive for the duration of the call; the function never frees it.
 *   Output : an owning `RectGTNString *` the caller MUST rectgtn_string_free().
 *
 *   An empty string is { .length = 0, .bytes = NULL }.
 */
typedef struct RectGTNString {
    uint32_t  length;         /* bytes (UTF-8) */
    const uint8_t *bytes;      /* length bytes; NULL iff length == 0 */
} RectGTNString;

void rectgtn_string_free(RectGTNString *s);

/* ------------------------------------------------------------------------
 * ISO-8601 duration.  Canonical `P[nY][nM][nD][W]T[nH][nM][nS]` with optional
 * sub-second fraction.  "P" = zero.  Represented as a Pascal string so it can
 * carry the sub-second fraction exactly (no float round-trip). */
typedef RectGTNString RectGTNDuration;

/* ------------------------------------------------------------------------
 * Temporal block.  The intrinsic timing of a plan (or of a single step).
 *
 *   `start` / `end` are absolute offsets from the plan origin (ISO-8601);
 *   `duration` is the step's own duration (PT0S by default when the action has
 *   no duration).  `consistent` is false iff the step overlaps a step that
 *   already ran and is not allowed (STN / action-conflict violation). */
typedef struct {
    RectGTNDuration start;      /* absolute */
    RectGTNDuration end;        /* absolute */
    RectGTNDuration duration;   /* this step's own duration (default PT0S)   */
    bool      consistent;       /* STN-consistent within the plan            */
} RectGTNTemporal;

/* ------------------------------------------------------------------------
 * Plan step.  One element of the step sequence.  A step is a temporal step --
 * it carries its own `start`/`end`/`duration`/`consistent` block, derived
 * from the plan's composed durations. */
typedef struct {
    RectGTNString name;         /* the action name (opaque identity ref)       */
    RectGTNTemporal temporal;   /* intrinsic timing of this step               */
} RectGTNStep;

/* ------------------------------------------------------------------------
 * Plan.  A temporal plan -- the temporal block is intrinsic and always
 * present (there is no `temporal()` side-channel function).  `steps` holds
 * 0..N RectGTNStep's (caller frees via rectgtn_plan_free).  On a refusal
 * (no alternative satisfies every goal) step_count is 0 and consistent is
 * false. */
typedef struct {
    uint32_t  step_count;
    RectGTNStep *steps;         /* length = step_count, may be NULL            */
    RectGTNTemporal total;      /* plan-level block: origin, total duration,   */
                                /* per-step offsets, STN consistency           */
    bool   consistent;          /* overall plan STN-consistency (alias of      */
                                /* total.consistent, redundant for convenience) */
} RectGTNPlan;

/* Free the step array (and its members) of a plan.  The caller owns `total`. */
void rectgtn_plan_free(RectGTNPlan *p);

/* ------------------------------------------------------------------------
 * Validation result. */
typedef struct {
    bool              ok;       /* structural / JSON-LD / schema valid          */
    RectGTNString reason;      /* human-readable reason (empty when ok)       */
    RectGTNString details;     /* optional machine-reason (empty when none)   */
} RectGTNValidation;

void rectgtn_validation_free(RectGTNValidation *v);

/* ------------------------------------------------------------------------
 * Domain lifecycle (JSON-LD in / out) ------------------------------------------------
 */
/*
 * Compose several JSON-LD documents into one domain.  `base` and each
 * `overlay` are Pascal-JSON strings.  Later documents replace `variables`,
 * `methods`, `goalMethods`, `todoList` per the merge rules in
 * docs/rectgtn.md "Composing several documents".
 */
RectGTNString *rectgtn_domain_compose(const RectGTNString *base,
                                      const RectGTNString *overlay);

/*
 * Validate one domain (JSON-LD Pascal string).  Returns a RectGTNValidation;
 * ok is false (with a named reason) when the domain refuses.
 */
RectGTNValidation *rectgtn_domain_validate(const RectGTNString *domain);

/* ------------------------------------------------------------------------
 * Planning --------------------------------------------------------------- */
/*
 * plan(domain) -> the intrinsic temporal plan of `domain`.
 * On a refusal, step_count == 0 and consistent == false.
 */
RectGTNPlan *rectgtn_plan(const RectGTNString *domain);

/*
 * replan(domain, plan_array, fail_step).  `plan_array` is the "plan" member of
 * the plan currently being executed: the array, not the answer that carries it
 * (see replan_json below).  Returns the recovered plan for `domain`.
 *
 * `fail_step` is the 0-based index of the action that failed at runtime; -1
 * means the whole plan ran.  The contract (docs/rectgtn.md "Soundness
 * contract") is replay, blacklist, re-solve:
 *
 *   - the first `fail_step` actions are re-applied, in order, to a copy of the
 *     initial state.  The prefix is replayed, not restored from a pointer
 *     history, so no state mutation is rolled back;
 *   - the command at `fail_step` -- that exact (action, args) instantiation,
 *     not the action name -- is blacklisted, so the search must find another
 *     decomposition rather than retry the same step;
 *   - the planner searches the original task list again from the replayed
 *     state.  The answer is a whole plan from that state, not a suffix, so an
 *     alternative that repeats the prefix repeats it here.
 *
 * The temporal block is that recovered plan's own, not a continuation of the
 * failed plan's timeline.  A `fail_step` at or past the end of the plan is the
 * -1 case.  When no alternative decomposition exists the plan is empty
 * (step_count == 0, consistent == false), the same refusal rectgtn_plan gives.
 */
RectGTNPlan *rectgtn_replan(const RectGTNString *domain,
                            const RectGTNString *plan_array,
                            int fail_step);

/* ------------------------------------------------------------------------
 * Host-facing JSON convenience (NIF-compatible) --------------------------- */
/*
 * plan_json(domain) ->
 *   {"plan": [["<action>", "<arg>", ...], ...],
 *    "temporal": {"consistent": bool, "origin": "<ISO-8601>",
 *                 "total": "<ISO-8601>",
 *                 "steps": [{"action": "<name>", "duration": "<ISO-8601>",
 *                            "start": "<ISO-8601>", "end": "<ISO-8601>"}, ...]}}
 *
 * replan_json(domain, plan_array, fail_step) ->
 *   {"fail_step": int, "completed_steps": int,
 *    "original_plan": [[...]], "new_plan": [[...]], "recovered": bool}
 *
 * `plan_array` is the "plan" member of a plan_json answer, NOT that answer.
 * Passing the whole envelope is accepted and answers "original_plan": [] with
 * "completed_steps": 0, which reads as a complete replan without being one.
 *
 * All strings are Pascal (length + bytes).
 */
RectGTNString *rectgtn_plan_json(const RectGTNString *domain);
RectGTNString *rectgtn_replan_json(const RectGTNString *domain,
                                   const RectGTNString *plan_array,
                                   int fail_step);

/* ------------------------------------------------------------------------
 * ReBAC (capabilities / relationships, ADR 0004) --------------------------- */
/*
 * True iff `subject` is related to `object` via `relation` (direct or through
 * the composition of the `definitions` aliases).  `graph_json` is the
 * composed domain's `capabilities.graph` JSON string.  All are Pascal.
 */
bool rectgtn_rebac_check(const RectGTNString *graph_json,
                         const RectGTNString *relation,
                         const RectGTNString *subject,
                         const RectGTNString *object);

/*
 * Convenience: read `capabilities.graph` from the composed domain and check
 * one relation (subject = "HAS_CAPABILITY"-style edge).
 */
bool rectgtn_domain_has_capability(const RectGTNString *domain,
                                   const RectGTNString *subject,
                                   const RectGTNString *relation);

/* ------------------------------------------------------------------------
 * Pointer state (/var/key) ------------------------------------------------ */
/*
 * Apply a pointer/set step to the running state.  `state` is the current
 * /var/ object (JSON-LD Pascal string); `step` is the pointer/set JSON-LD
 * step.  Returns the NEW state as a Pascal JSON string (caller owns).
 */
RectGTNString *rectgtn_ptr_set(const RectGTNString *state,
                               const RectGTNString *step);

/*
 * Read one pointer path from `state`.  Returns a Pascal string holding the
 * JSON value, or empty when the path is absent.
 */
RectGTNString *rectgtn_ptr_get(const RectGTNString *state,
                               const RectGTNString *key_path);

/* ------------------------------------------------------------------------
 * Memory & version -------------------------------------------------------- */
void rectgtn_free_all(RectGTNPlan *p, RectGTNValidation *v);

RectGTNString *rectgtn_version(void);   /* Pascal; caller frees */

#if defined(__cplusplus)
}
#endif

#endif /* RECTGTN_API_H */
