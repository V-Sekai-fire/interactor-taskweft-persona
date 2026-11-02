#include <lean/lean.h>
#include <string.h>
#include <stdlib.h>
void lean_initialize_runtime_module(void);
void lean_io_mark_end_initialization(void);
extern lean_object *initialize_persona_Persona_Grid(uint8_t builtin);
extern lean_object *initialize_persona_Persona_Web(uint8_t builtin);
extern lean_object *persona_plan_text(lean_object *spec);
extern lean_object *persona_goals_text(lean_object *domain, lean_object *problem);
extern lean_object *persona_plan_shortest_text(lean_object *domain, lean_object *problem, lean_object *limit);
extern lean_object *persona_plan_jsonld_text(lean_object *domain, lean_object *problem, lean_object *goal);
const char *uv_strerror(int e) { return "uv unavailable"; }
/* Modules that import Lean.* call this first. The runtime is up before persona_init reaches them, and
   each module initializes the Init and Lean.Data modules it needs, so there is nothing more to start. */
void lean_initialize(void) {}
static char *out = NULL;
static const char *keep(lean_object *res) {
  free(out);
  out = strdup(lean_string_cstr(res));
  lean_dec(res);
  return out;
}
int persona_init(void) {
  lean_initialize_runtime_module();
  lean_object *r = initialize_persona_Persona_Grid(1);
  if (!lean_io_result_is_ok(r)) return 1;
  lean_dec_ref(r);
  r = initialize_persona_Persona_Web(1);
  if (!lean_io_result_is_ok(r)) return 1;
  lean_dec_ref(r);
  lean_io_mark_end_initialization();
  return 0;
}
/* A skill grid as text in, the activation order out. */
const char *persona_plan(const char *spec) {
  return keep(persona_plan_text(lean_mk_string(spec)));
}
/* A RECTGTN JSON-LD domain and problem in, the goals the problem asks out. */
const char *persona_goals(const char *domain, const char *problem) {
  return keep(persona_goals_text(lean_mk_string(domain), lean_mk_string(problem)));
}
/* A domain and a problem in, a plan document out. An empty goal plans every goal of the problem. */
const char *persona_plan_jsonld(const char *domain, const char *problem, const char *goal) {
  return keep(persona_plan_jsonld_text(lean_mk_string(domain), lean_mk_string(problem),
                                       lean_mk_string(goal)));
}
/* The plan with the fewest actions: a domain and a problem in, a plan out. `limit` is the longest plan tried. */
const char *persona_plan_shortest(const char *domain, const char *problem, int limit) {
  return keep(persona_plan_shortest_text(lean_mk_string(domain), lean_mk_string(problem), lean_box(limit)));
}
