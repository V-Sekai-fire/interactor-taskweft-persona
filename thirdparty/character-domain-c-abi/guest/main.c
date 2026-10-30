/*
 * guest/main.c — character domain guest C-ABI shim.
 *
 * A self-contained RISC-V64 Linux guest (godot-sandbox / libriscv). It (1)
 * emits the `.sandbox_variant` section -- `SBXV` magic plus the 32-bit
 * little-endian Variant size (24 single, 40 double) -- that the host loader
 * reads at load time, and (2) exports the character_* C-ABI symbols declared in
 * `api/character_api.h`.
 *
 * The domain logic is pure Lean (Character/). When the Lean core is compiled to
 * a RISC-V guest (Lean runtime port to riscv64-linux, RFD66606-2153 stage 3),
 * the godot-sandbox addon's binary-translation engine converts that guest's
 * `.text` to native C and the host calls every character_* symbol below through
 * it (`sb.has_function` / `sb.vmcall`). Today the Lean core is not yet compiled
 * to RISC-V, so this file supplies a minimal stub body for each symbol: it
 * builds end-to-end and CI proves the guest ELF shape (static RISC-V64 Linux,
 * `.sandbox_variant` SBXV + variant size, `.symtab` carrying the character_*
 * names) without the Lean runtime port. The Lean reference model is the
 * authority and is exercised by `lake exe character_witness`.
 *
 * SPDX-License-Identifier: MIT
 */
#include "api/character_api.h"

__attribute__((used, retain, section(".sandbox_variant")))
const unsigned char sandbox_variant_size[8] =
#ifdef DOUBLE_PRECISION
    { 0x53, 0x42, 0x58, 0x56, 40, 0, 0, 0 };
#else
    { 0x53, 0x42, 0x58, 0x56, 24, 0, 0, 0 };
#endif

/* ---- C-ABI stubs (stage 1; the Lean core replaces these at stage 3) ---- */

CharacterString *character_version(void)
{
    static const uint8_t bytes[5] = { '0', '.', '1', '.', '0' };
    static CharacterString v = { (uint32_t)5, bytes };
    return &v;
}
void character_string_free(CharacterString *s) { (void)s; }

bool character_roll_normalize(const float bind[3], const float rest[3], float out4[4])
{
    (void)bind; (void)rest; (void)out4;
    return false;
}

CharacterString *character_harness_bones(const CharacterString *bones_json,
                                         const CharacterString *weights_json)
{
    (void)bones_json; (void)weights_json;
    static CharacterString empty = { 0, NULL };
    return &empty;
}

CharacterString *character_goal_to_gtn(const CharacterString *goal)
{
    (void)goal;
    static CharacterString empty = { 0, NULL };
    return &empty;
}

CharacterValidation *character_domain_validate(const CharacterString *domain)
{
    (void)domain;
    return (CharacterValidation *)NULL;
}
void character_validation_free(CharacterValidation *v) { (void)v; }

/* The Sandbox ABI has no argument count; the host invokes character_* by
 * resolved symbol name, so this conventional entry only satisfies the linker. */
int main(void) { return 0; }
