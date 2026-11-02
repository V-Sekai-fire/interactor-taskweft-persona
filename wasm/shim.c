#include <lean/lean.h>
#include <string.h>
#include <stdlib.h>
void lean_initialize_runtime_module(void);
void lean_io_mark_end_initialization(void);
extern lean_object *initialize_persona_Persona_Grid(uint8_t builtin);
extern lean_object *persona_plan_text(lean_object *spec);
const char *uv_strerror(int e) { return "uv unavailable"; }
static char *out = NULL;
int persona_init(void) {
  lean_initialize_runtime_module();
  lean_object *r = initialize_persona_Persona_Grid(1);
  if (!lean_io_result_is_ok(r)) return 1;
  lean_dec_ref(r);
  lean_io_mark_end_initialization();
  return 0;
}
const char *persona_plan(const char *spec) {
  lean_object *res = persona_plan_text(lean_mk_string(spec));
  free(out);
  out = strdup(lean_string_cstr(res));
  lean_dec(res);
  return out;
}
