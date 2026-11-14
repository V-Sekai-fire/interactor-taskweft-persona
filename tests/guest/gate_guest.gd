# persona.elf in a Sandbox: load it from bytes, call its surface, print one "key value" line per
# answer for tools/check_guest.py to read. Exit 1 when the Sandbox class or the guest's surface is missing.
#   godot --headless --path tests/guest --script gate_guest.gd -- --elf=<persona.elf>
extends SceneTree

# The goals asked, by label: the declared goal, the empty goal (the domain's default), and one
# the guest does not declare.
const GOALS := [["delivered", "delivered"], ["default", ""], ["undeclared", "no-such-goal-xyzzy"]]


func _initialize() -> void:
	var a := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else ""
	quit(_run(a))


func _run(a: Dictionary) -> int:
	if not ClassDB.class_exists("Sandbox"):
		return _fail("the Sandbox class is not registered")
	var elf := FileAccess.get_file_as_bytes(a.get("elf", ""))
	if elf.is_empty():
		return _fail("%s did not read" % a.get("elf", "(no --elf)"))
	print("elf_bytes %d" % elf.size())
	var sb = ClassDB.instantiate("Sandbox")
	sb.set_redirect_stdout(func(line): print("guest| ", line))
	sb.load_buffer(elf)
	for f in ["persona_version", "persona_ask"]:
		if not sb.has_function(f):
			sb.free()
			return _fail("%s did not load (no %s)" % [a.elf.get_file(), f])
	print("loaded yes")
	print("version %s" % str(sb.vmcall("persona_version")))
	for g in GOALS:
		print("ask_%s %s" % [g[0], str(sb.vmcall("persona_ask", g[1]))])
	print("exceptions %d" % int(sb.get_exceptions()))
	sb.free()
	return 0


func _fail(why: String) -> int:
	print("FAIL %s" % why)
	return 1
