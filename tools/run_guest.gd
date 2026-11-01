extends SceneTree
# Run persona.elf standalone in an entities-godot host (headless), no scene needed.
#
#   godot --headless --path <project> -s res://run_guest.gd -- res://persona.elf [goal]
#
# Exits non-zero unless the guest loads, reports its version, and answers a goal
# with a plan (and refuses a goal it cannot reach, by name).

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	if a.is_empty():
		push_error("usage: -- <persona.elf> [goal]")
		quit(2)
		return
	var sb := Sandbox.new()
	sb.set_redirect_stdout(func(line): print("guest| ", line))
	sb.set_program(load(a[0]))
	var goal: String = a[1] if a.size() > 1 else ""
	var version = sb.vmcall("persona_version")
	print("persona_version: ", version)
	var plan = sb.vmcall("persona_ask", goal)
	print("persona_ask(", goal, "): ", str(plan).left(400))
	var refusal = sb.vmcall("persona_ask", "no-such-goal-xyzzy")
	print("persona_ask(refused): ", str(refusal).left(200))
	var ok: bool = str(version) != "" and str(plan) != "" and str(plan) != str(refusal)
	sb.free()
	quit(0 if ok else 1)
