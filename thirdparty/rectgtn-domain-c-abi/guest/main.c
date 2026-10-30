/*
 * guest/main.c — RECTGTN domain guest C-ABI shim.
 *
 * A self-contained RISC-V64 Linux guest (godot-sandbox / libriscv).
 *
 * It (1) emits the `.sandbox_variant` section — `SBXV` magic plus the
 * 32-bit little-endian Variant size (24 for single precision, 40 for
 * double) — that the host loader reads at load time, and (2) exports the
 * RECTGTN C-ABI symbols declared in `api/rectgtn_api.h`.
 *
 * Two API invariants (api/rectgtn_api.h):
 *   1. Pascal strings.   Every string crossing this boundary is length + bytes,
 *      exactly like Godot's native `String` — NEVER null-terminated.  `length`
 *      counts UTF-8 bytes; `bytes` is NULL only when `length == 0`.
 *   2. Temporal is intrinsic.   Every plan carries its own temporal block as a
 *      required member of `RectGTNPlan`; there is no free-standing
 *      `temporal(plan)` recompute function (issue #2).
 *
 * The domain logic is pure Lean.  When it is compiled to a RISC-V guest
 * (Lean runtime port to riscv64-linux, RFD66606-2153 stage 3), the godot-
 * sandbox addon's binary-translation engine converts that guest's `.text`
 * to native C (`bintr-<hash>.c`, clang) and the host calls every rectgtn_*
 * symbol below through it (`sb.has_function` / `sb.vmcall`).  Today the Lean
 * core is not yet compiled to RISC-V, so this file supplies a minimal stub
 * body for each symbol: it builds end-to-end and the CI proves the guest ELF
 * shape (static RISC-V64 Linux, `.sandbox_variant` SBXV + variant size,
 * stripped symbol table with the rectgtn_* names present) without the Lean
 * runtime port.
 *
 * The host finds guest functions by resolved symbol name (see
 * 4-entities/godot-sandbox src/sandbox.cpp `sb.has_function`), so these plain
 * `extern "C"`-linked names are exactly what it resolves — no generated API is
 * needed for the domain.
 *
 * Build:
 *   cmake -B build -DCMAKE_TOOLCHAIN_FILE=guest/toolchain.cmake \
 *     -DCMAKE_BUILD_TYPE=MinSizeRel -DSTRIPPED=ON -DDOUBLE_PRECISION=ON
 *   cmake --build build
 *
 * The attribute form below mirrors 4-entities/godot-sandbox's
 * program/cpp/docker/api/api.cpp exactly:
 *   __attribute__((section(".sandbox_variant")))
 *   const SandboxVariantSize sandbox_variant_size{ ... };
 *
 * SPDX-License-Identifier: MIT
 */
#include "api/rectgtn_api.h"

/*
 * The `.sandbox_variant` section.
 *
 *   bytes 0-3 : "SBXV" magic
 *   bytes 4-7 : 32-bit little-endian Variant size (24 = single, 40 = double)
 *
 * We build the RECTGTN guest for a double-precision host (40-byte Variant),
 * matching the workspace's other sandbox guests (see
 * 2-contract/guest-runtime/cmake/guest_runtime.cmake, which forces
 * DOUBLE_PRECISION=ON, and 4-entities/opentelemetry-godot-project's
 * `--variant-size=40` gate).  `-DDOUBLE_PRECISION` (default: ON) keeps the
 * size at 40; add `-DDOUBLE_PRECISION=OFF` to ship a single-precision (24) guest.
 */
__attribute__((used, retain, section(".sandbox_variant")))
const unsigned char sandbox_variant_size[8] =
#ifdef DOUBLE_PRECISION
    { 0x53, 0x42, 0x58, 0x56, 40, 0, 0, 0 };
#else
    { 0x53, 0x42, 0x58, 0x56, 24, 0, 0, 0 };
#endif

/* ------------------------------------------------------------------------
 * C-ABI symbols — stubs for the stage-1 skeleton.  When the Lean core is
 * compiled to a RISC-V guest (RFD66606-2153 stage 3), these become real
 * Lean-compiled RISC-V functions, and the addon's binary-translation engine
 * converts them to native C at load time (this file shrinks to glue).  The
 * stubs keep every rectgtn_* name exported so the symbol check in
 * build_guest_elf.yml passes while the skeleton is green.
 * ------------------------------------------------------------------------ */
RectGTNString *rectgtn_version(void)
{
    static const uint8_t bytes[5] = { '0', '.', '1', '.', '0' };
    static RectGTNString v = { (uint32_t)5, bytes };
    return &v;
}
void rectgtn_string_free(RectGTNString *s) { (void)s; }

RectGTNString *rectgtn_domain_compose(const RectGTNString *base,
                                      const RectGTNString *overlay)
{
    (void)base; (void)overlay;
    static RectGTNString empty = { 0, NULL };
    return &empty;
}
RectGTNValidation *rectgtn_domain_validate(const RectGTNString *domain)
{
    (void)domain;
    return (RectGTNValidation *)NULL;
}
RectGTNPlan *rectgtn_plan(const RectGTNString *domain)
{
    (void)domain;
    return (RectGTNPlan *)NULL;
}
RectGTNPlan *rectgtn_replan(const RectGTNString *domain,
                            const RectGTNString *plan_json,
                            int fail_step)
{
    (void)domain; (void)plan_json; (void)fail_step;
    return (RectGTNPlan *)NULL;
}
RectGTNString *rectgtn_plan_json(const RectGTNString *domain)
{
    (void)domain;
    static RectGTNString empty = { 0, NULL };
    return &empty;
}
RectGTNString *rectgtn_replan_json(const RectGTNString *domain,
                                   const RectGTNString *plan_json,
                                   int fail_step)
{
    (void)domain; (void)plan_json; (void)fail_step;
    static RectGTNString empty = { 0, NULL };
    return &empty;
}
void rectgtn_plan_free(RectGTNPlan *p) { (void)p; }
void rectgtn_validation_free(RectGTNValidation *v) { (void)v; }
void rectgtn_free_all(RectGTNPlan *p, RectGTNValidation *v) { (void)p; (void)v; }

bool rectgtn_rebac_check(const RectGTNString *graph_json,
                         const RectGTNString *relation,
                         const RectGTNString *subject,
                         const RectGTNString *object)
{
    (void)graph_json; (void)relation; (void)subject; (void)object;
    return true;
}
bool rectgtn_domain_has_capability(const RectGTNString *domain,
                                   const RectGTNString *subject,
                                   const RectGTNString *relation)
{
    (void)domain; (void)subject; (void)relation;
    return true;
}
RectGTNString *rectgtn_ptr_set(const RectGTNString *state,
                               const RectGTNString *step)
{
    (void)state; (void)step;
    static RectGTNString empty = { 0, NULL };
    return &empty;
}
RectGTNString *rectgtn_ptr_get(const RectGTNString *state,
                               const RectGTNString *key_path)
{
    (void)state; (void)key_path;
    static RectGTNString empty = { 0, NULL };
    return &empty;
}

/*
 * Guest entry point.
 *
 * The Sandbox ABI has no argument count; the host invokes rectgtn_* by
 * resolved symbol name.  We keep an empty `main` so the linker has a
 * conventional entry — the real work is the exported rectgtn_* symbols,
 * which the host finds via `sb.has_function` / dynamic symbol resolution
 * (src/sandbox.cpp).
 */
int main(void) { return 0; }