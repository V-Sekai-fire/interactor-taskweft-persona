// persona.elf -- the persona's public surface.
//
// Every ADD_API_FUNCTION here is reachable from GDScript as
// Sandbox.vmcall(name, ...). The body is the persona's Lean (Persona/Guest.lean)
// compiled for riscv64 and linked into this guest. The two Lean exports take and
// return a Lean String; this shim converts them to and from Godot's own String,
// so no C string ever crosses the boundary: the host passes a String, the guest
// answers with one.
//
//   persona_version() -> String   the version of this surface
//   persona_ask(goal) -> String   the plan that reaches `goal`, as JSON, or the
//                                 refusal by name; an empty goal means the
//                                 domain's own default
//
// The Lean runtime comes up once, at load. main() registers the surface and
// halts, which is the pause point libriscv wants: a main that returns runs
// glibc's destructors and leaves the machine unusable for later calls.
//
// SPDX-License-Identifier: MIT

#include <api.hpp>

#include <lean/lean.h>

#include <cstdint>
#include <string>

// Emitted by the persona's own modules. `@[export]` takes its argument owned and
// returns an owned value, and the emitted C declares them inside its own
// extern "C", so the declarations here must have C linkage too.
extern "C" {
lean_object *initialize_persona_Persona_Guest(uint8_t builtin);
lean_object *persona_ask_json(lean_object *request);
lean_object *persona_version_text(lean_object *request);
}

static bool g_initialised = false;

static void persona_init()
{
	if (g_initialised)
		return;
	g_initialised = true;
	lean_object *res = initialize_persona_Persona_Guest(1 /* builtin */);
	lean_io_mark_end_initialization();
	if (lean_io_result_is_ok(res)) {
		lean_dec_ref(res);
		lean_init_task_manager();
	} else {
		lean_io_result_show_error(res);
		lean_dec_ref(res);
	}
}

// One answer: a Lean String out of the export, as a Godot String for the host.
static String answer(lean_object *(*entry)(lean_object *), const String &request)
{
	persona_init();
	const std::string in = request;
	lean_object *value = entry(lean_mk_string_from_bytes(in.data(), in.size()));
	const std::string out(lean_string_cstr(value), lean_string_size(value));
	lean_dec_ref(value);
	return String(out);
}

static String persona_version()
{
	return answer(persona_version_text, String(""));
}

static String persona_ask(String goal)
{
	return answer(persona_ask_json, goal);
}

int main()
{
	ADD_API_FUNCTION(persona_version, "String", "",
		"The version of this guest's surface.");
	ADD_API_FUNCTION(persona_ask, "String", "String goal",
		"The plan that reaches the named goal, as JSON, or the refusal by name. "
		"An empty goal means the domain's own default.");
	halt();
}
