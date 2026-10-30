/*
 * character_api.h — C surface for the character domain, embedded in a RISC-V
 * guest ELF (godot-sandbox / libriscv).
 *
 * The whole domain is pure Lean (Character/). On `lake build` the Lean core
 * emits a `.c` intermediate that implements every function below; this header is
 * the contract that intermediate must satisfy. There is no hand-written C
 * implementation of the domain logic -- only the guest entry point and the I/O
 * glue live in C (see guest/main.c).
 *
 * Two API invariants, the same two the RECTGTN domain carries:
 *
 *   1. Pascal strings.  Every string crossing this boundary is length + bytes,
 *      exactly like Godot's native `String` -- NEVER null-terminated.  `length`
 *      counts UTF-8 bytes; `bytes` is NULL only when `length == 0`.
 *
 *   2. The GTN is shared.  A character goal is an ordinary RECTGTN task node
 *      (Character/GTN.lean `toGTN`): the character domain does not define its
 *      own plan type, it unions with the RECTGTN `PlanElement` / `RECTGTNNode`
 *      space, so the RECTGTN planner solves a character plan unchanged.
 *
 * SPDX-License-Identifier: MIT
 */

#ifndef CHARACTER_API_H
#define CHARACTER_API_H

#if defined(__cplusplus)
extern "C" {
#endif

#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

/* ------------------------------------------------------------------------
 * Pascal string (Godot-style: length + bytes, no null terminator). */
typedef struct CharacterString {
    uint32_t       length;   /* bytes (UTF-8) */
    const uint8_t *bytes;    /* length bytes; NULL iff length == 0 */
} CharacterString;

void character_string_free(CharacterString *s);

/* ------------------------------------------------------------------------
 * Roll orientation normalization.
 *
 * The canonical minimal-twist (rank-1 / shortest-arc) rotation that maps the
 * bone's bind direction onto its rest direction with ZERO roll about the bone
 * axis. `bind` and `rest` are 3 floats each; the answer is a unit quaternion
 * (w, x, y, z) in `out4`. Returns false when the rotation is undefined (a zero
 * direction). */
bool character_roll_normalize(const float bind[3], const float rest[3], float out4[4]);

/* ------------------------------------------------------------------------
 * Clean-rig / harness removal.
 *
 * `bones` is N records of (name, parent, length); `weights` is M records of
 * (vertex, bone, weight). Returns a Pascal string holding one name per line:
 * the harness/controller bones to remove -- every bone with no positive skin
 * weight. An empty string means the rig is already clean. */
CharacterString *character_harness_bones(const CharacterString *bones_json,
                                         const CharacterString *weights_json);

/* ------------------------------------------------------------------------
 * The union with RECTGTN.
 *
 * Lift a character goal to the shared GTN task name. `goal` is one of
 * "cleanRig", "fitUnderGarment:<garment>", "exportUsd:<path>"; the answer is the
 * RECTGTN task name (`char.cleanRig`, ...) as a Pascal string. */
CharacterString *character_goal_to_gtn(const CharacterString *goal);

/* ------------------------------------------------------------------------
 * Validate one character document (JSON-LD Pascal string). ok is false (with a
 * named reason) when the document refuses. */
typedef struct {
    bool            ok;
    CharacterString reason;
} CharacterValidation;

CharacterValidation *character_domain_validate(const CharacterString *domain);
void character_validation_free(CharacterValidation *v);

/* ------------------------------------------------------------------------
 * Version. */
CharacterString *character_version(void);   /* Pascal; caller frees */

#if defined(__cplusplus)
}
#endif

#endif /* CHARACTER_API_H */
