/* The guest side of the godot-sandbox host contract, for the persona: the size of this
 * program's Variant (.sandbox_variant), fast_exit, and the two public functions. The logic is
 * Mojo (persona_guest.mojo); this file only moves Godot Strings in and out of it.
 * Copied from V-Sekai-fire/interactor-mojo-guest runtime/sandbox_abi.c, reduced to the
 * conversions the persona needs. */
#include <stddef.h>
#include <stdint.h>

struct SandboxVariantSize {
    char magic[4];
    uint32_t size;
};

__attribute__((used, retain, section(".sandbox_variant")))
const struct SandboxVariantSize sandbox_variant_size = { { 'S', 'B', 'X', 'V' }, SANDBOX_VARIANT_SIZE };

#define ECALL_SANDBOX_ADD 547
#define ECALL_IS_EDITOR 512
#define ECALL_VCREATE 517
#define ECALL_VFETCH 519
#define ECALL_ARENA_FREE 483
#define EINVAL_ 22
#define ERANGE_ 34
#define ENOSYS_ 38
enum { VARIANT_NIL = 0, VARIANT_STRING = 4 };

/* The guest's Variant: a 32-bit type, then the payload at offset 8. A string is an index into
 * the host's scoped variants. */
struct GuestVariant {
    int32_t type;
    int32_t pad;
    union {
        int64_t i;
        double f;
    };
};

struct GuestFunctionExtra {
    const char *desc; size_t desc_len;
    const char *ret;  size_t ret_len;
    const char *args; size_t args_len;
};

static void sandbox_add_function(const char *name, size_t name_len, void *address,
                                 const char *ret, const char *args) {
    size_t ret_len = 0, args_len = 0;
    while (ret[ret_len]) ret_len++;
    while (args[args_len]) args_len++;
    struct GuestFunctionExtra extra = { "", 0, ret, ret_len, args, args_len };
    register long a0 __asm__("a0") = 1;
    register const char *a1 __asm__("a1") = name;
    register size_t a2 __asm__("a2") = name_len;
    register void *a3 __asm__("a3") = address;
    register void *a4 __asm__("a4") = &extra;
    register long a7 __asm__("a7") = ECALL_SANDBOX_ADD;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a3), "r"(a4), "r"(a7) : "memory");
}

/* Where every vmcall returns to: the host uses its address as the return address. */
__attribute__((used, retain, noreturn)) void fast_exit(void) {
    __asm__ volatile("1: .insn i SYSTEM, 0, x0, x0, 0x7ff\n j 1b");
    __builtin_unreachable();
}

static long ecall4(long n, long a0v, long a1v, long a2v, long a3v) {
    register long a0 __asm__("a0") = a0v;
    register long a1 __asm__("a1") = a1v;
    register long a2 __asm__("a2") = a2v;
    register long a3 __asm__("a3") = a3v;
    register long a7 __asm__("a7") = n;
    __asm__ volatile("ecall" : "+r"(a0) : "r"(a1), "r"(a2), "r"(a3), "r"(a7) : "memory");
    return a0;
}

/* A host answers ECALL_IS_EDITOR with 0 or 1; anything else is no Sandbox host. */
int sandbox_host_present(void) {
    long r = ecall4(ECALL_IS_EDITOR, -1, 0, 0, 0);
    return r == 0 || r == 1;
}

/* The async runtime asks for a clock and a timer. The persona waits on neither: no clock
 * answers, so a timed wait returns at once, and no timer is armed. */
long sandbox_ticks_usec(void) { return -1; }
void sandbox_arm_timer_ns(long ns) { (void)ns; }

/* VCREATE method 1 takes a pointer and a length and makes a scoped String on the host. */
int sandbox_variant_set_string(struct GuestVariant *v, const char *s, size_t n) {
    struct { const char *data; size_t size; } in = { s, n };
    v->type = VARIANT_NIL;
    ecall4(ECALL_VCREATE, (long)v, VARIANT_STRING, 1, (long)&in);
    return v->type == VARIANT_STRING ? 0 : -ENOSYS_;
}

/* VFETCH method 1 copies the string into the host's arena; it is copied out and freed there. */
int sandbox_variant_get_string(const struct GuestVariant *v, char *buf, size_t cap, size_t *n) {
    struct { char *data; size_t size; } out = { 0, 0 };
    if (v->type != VARIANT_STRING) return -EINVAL_;
    ecall4(ECALL_VFETCH, (long)(unsigned)v->i, (long)&out, 1, 0);
    if (out.data == 0 && out.size == 0) return -ENOSYS_;
    int rc = out.size > cap ? -ERANGE_ : 0;
    if (rc == 0) for (size_t i = 0; i < out.size; i++) buf[i] = out.data[i];
    *n = out.size;
    if (out.data) ecall4(ECALL_ARENA_FREE, (long)out.data, 0, 0, 0);
    return rc;
}

/* The persona's answers, in Mojo. Each writes up to cap bytes and returns the length, or a
 * negative errno. */
extern long mojo_persona_ask(const char *req, long req_len, char *out, long cap) __attribute__((weak));
extern long mojo_persona_version(char *out, long cap) __attribute__((weak));

extern long mojo_persona_plan_jsonld(const char *d, long dl, const char *p, long pl, const char *g, long gl,
                                     char *out, long cap) __attribute__((weak));
extern long mojo_persona_goals(const char *d, long dl, const char *p, long pl, char *out, long cap)
    __attribute__((weak));

extern long mojo_persona_plan(const char *spec, long n, char *out, long cap) __attribute__((weak));
extern long mojo_persona_plan_shortest(const char *d, long dl, const char *p, long pl, const char *lim,
                                       long limlen, char *out, long cap) __attribute__((weak));

#define ANSWER_CAP 16384
/* A domain is about 75 KB (the command battle); room for four of them, and a megabyte of answer. */
#define DOMAIN_CAP (256 * 1024)
#define PROBLEM_CAP (64 * 1024)
#define GOAL_CAP 1024
#define BIG_ANSWER_CAP (1024 * 1024)

static void persona_version(struct GuestVariant *ret) {
    static char out[64];
    long n = mojo_persona_version(out, sizeof out);
    ret->type = VARIANT_NIL;
    if (n >= 0) sandbox_variant_set_string(ret, out, (size_t)n);
}

/* persona_ask(goal) -> String: the plan that reaches the goal, or the refusal by name. A goal
 * that is not a String gives NIL. */
static void persona_ask(struct GuestVariant *ret, const struct GuestVariant *goal) {
    static char req[4096];
    static char out[ANSWER_CAP];
    size_t rn = 0;
    ret->type = VARIANT_NIL;
    if (sandbox_variant_get_string(goal, req, sizeof req, &rn)) return;
    long n = mojo_persona_ask(req, (long)rn, out, sizeof out);
    if (n >= 0) sandbox_variant_set_string(ret, out, (size_t)n);
}

/* persona_plan_jsonld(domain, problem, goal) -> String: a RECTGTN domain and problem in, the plan
 * document out. An empty goal plans every goal of the problem. */
static void persona_plan_jsonld(struct GuestVariant *ret, const struct GuestVariant *d,
                                const struct GuestVariant *p, const struct GuestVariant *g) {
    static char dom[DOMAIN_CAP], prob[PROBLEM_CAP], goal[GOAL_CAP];
    static char out[BIG_ANSWER_CAP];
    size_t dn = 0, pn = 0, gn = 0;
    ret->type = VARIANT_NIL;
    if (sandbox_variant_get_string(d, dom, sizeof dom, &dn)) return;
    if (sandbox_variant_get_string(p, prob, sizeof prob, &pn)) return;
    if (sandbox_variant_get_string(g, goal, sizeof goal, &gn)) return;
    long n = mojo_persona_plan_jsonld(dom, (long)dn, prob, (long)pn, goal, (long)gn, out, sizeof out);
    if (n >= 0) sandbox_variant_set_string(ret, out, (size_t)n);
}

/* persona_goals(domain, problem) -> String: the goals the problem asks, and whether each holds. */
static void persona_goals(struct GuestVariant *ret, const struct GuestVariant *d,
                          const struct GuestVariant *p) {
    static char dom[DOMAIN_CAP], prob[PROBLEM_CAP];
    static char out[ANSWER_CAP];
    size_t dn = 0, pn = 0;
    ret->type = VARIANT_NIL;
    if (sandbox_variant_get_string(d, dom, sizeof dom, &dn)) return;
    if (sandbox_variant_get_string(p, prob, sizeof prob, &pn)) return;
    long n = mojo_persona_goals(dom, (long)dn, prob, (long)pn, out, sizeof out);
    if (n >= 0) sandbox_variant_set_string(ret, out, (size_t)n);
}

/* persona_plan(spec) -> String: a skill grid, one `skill ID DONE NEED...` line a skill and one
 * `goal ID` line, in; the activation order out. */
static void persona_plan(struct GuestVariant *ret, const struct GuestVariant *spec) {
    static char req[DOMAIN_CAP];
    static char out[ANSWER_CAP];
    size_t rn = 0;
    ret->type = VARIANT_NIL;
    if (sandbox_variant_get_string(spec, req, sizeof req, &rn)) return;
    long n = mojo_persona_plan(req, (long)rn, out, sizeof out);
    if (n >= 0) sandbox_variant_set_string(ret, out, (size_t)n);
}

/* persona_plan_shortest(domain, problem, limit) -> String: the plan with the fewest actions; the
 * limit, the longest plan tried, is the decimal text of a number. */
static void persona_plan_shortest(struct GuestVariant *ret, const struct GuestVariant *d,
                                  const struct GuestVariant *p, const struct GuestVariant *lim) {
    static char dom[DOMAIN_CAP], prob[PROBLEM_CAP], limit[GOAL_CAP];
    static char out[BIG_ANSWER_CAP];
    size_t dn = 0, pn = 0, ln = 0;
    ret->type = VARIANT_NIL;
    if (sandbox_variant_get_string(d, dom, sizeof dom, &dn)) return;
    if (sandbox_variant_get_string(p, prob, sizeof prob, &pn)) return;
    if (sandbox_variant_get_string(lim, limit, sizeof limit, &ln)) return;
    long n = mojo_persona_plan_shortest(dom, (long)dn, prob, (long)pn, limit, (long)ln, out, sizeof out);
    if (n >= 0) sandbox_variant_set_string(ret, out, (size_t)n);
}

/* Registration is legal only while the host initializes the guest, which is when main runs. */
void sandbox_register_api(void) {
    sandbox_add_function("persona_version", 15, (void *)persona_version, "String", "");
    sandbox_add_function("persona_ask", 11, (void *)persona_ask, "String", "String goal");
    sandbox_add_function("persona_plan_jsonld", 19, (void *)persona_plan_jsonld, "String",
                         "String domain, String problem, String goal");
    sandbox_add_function("persona_plan", 12, (void *)persona_plan, "String", "String spec");
    sandbox_add_function("persona_plan_shortest", 21, (void *)persona_plan_shortest, "String",
                         "String domain, String problem, String limit");
    sandbox_add_function("persona_goals", 13, (void *)persona_goals, "String", "String domain, String problem");
}
