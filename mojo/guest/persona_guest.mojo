# SPDX-License-Identifier: MIT
# persona.elf in Mojo: the persona's public surface for a godot-sandbox host.
#
#   persona_version() -> String   the version of this surface
#   persona_ask(goal) -> String   the plan that reaches `goal`, as JSON, or the refusal by name;
#                                 an empty goal means the domain's own default
#
# The answers are persona.guest.answer_json, the code the Lean gate's parity run checks. The C
# glue (runtime/sandbox_abi.c) moves Godot Strings in and out through these two exports.
from std.ffi import external_call
from std.sys import exit
from persona.guest import answer_json, VERSION_TEXT
from persona.jsonld import plan_with, goals_of, shortest_of
from persona.grid import plan_of as grid_plan


def _copy_out(s: String, dst: Int, cap: Int) -> Int:
    """Write the bytes of `s` to `out`; the length, or -34 when `cap` is too small."""
    var n = s.byte_length()
    if n > cap:
        return -34
    var p = MutPointer[UInt8, MutUntrackedOrigin](unsafe_from_address=dst)
    var b = s.as_bytes()
    for i in range(n):
        p[unsafe_offset=i] = b[i]
    return n


@export
def mojo_persona_version(dst: Int, cap: Int) abi("C") -> Int:
    return _copy_out(String(VERSION_TEXT), dst, cap)


@export
def mojo_persona_ask(req: Int, req_len: Int, dst: Int, cap: Int) abi("C") -> Int:
    var bytes = List[UInt8](capacity=req_len)
    var p = ImmPointer[UInt8, ImmUntrackedOrigin](unsafe_from_address=req)
    for i in range(req_len):
        bytes.append(p[unsafe_offset=i])
    var goal: String
    try:
        goal = String(from_utf8=bytes)
    except:
        return -22
    return _copy_out(answer_json(goal), dst, cap)


def _text(addr: Int, n: Int) -> String:
    """The UTF-8 text at `addr`, or the empty String when it is not UTF-8."""
    var bytes = List[UInt8](capacity=n)
    var p = ImmPointer[UInt8, ImmUntrackedOrigin](unsafe_from_address=addr)
    for i in range(n):
        bytes.append(p[unsafe_offset=i])
    try:
        return String(from_utf8=bytes)
    except:
        return String("")


@export
def mojo_persona_plan_jsonld(
    d: Int, dl: Int, p: Int, pl: Int, g: Int, gl: Int, dst: Int, cap: Int
) abi("C") -> Int:
    return _copy_out(plan_with(_text(d, dl), _text(p, pl), _text(g, gl)), dst, cap)


@export
def mojo_persona_goals(d: Int, dl: Int, p: Int, pl: Int, dst: Int, cap: Int) abi("C") -> Int:
    return _copy_out(goals_of(_text(d, dl), _text(p, pl)), dst, cap)


@export
def mojo_persona_plan(spec: Int, n: Int, dst: Int, cap: Int) abi("C") -> Int:
    return _copy_out(grid_plan(_text(spec, n)), dst, cap)


@export
def mojo_persona_plan_shortest(
    d: Int, dl: Int, p: Int, pl: Int, lim: Int, ll: Int, dst: Int, cap: Int
) abi("C") -> Int:
    var limit = 0
    try:
        limit = Int(_text(lim, ll))
    except:
        return -22
    return _copy_out(shortest_of(_text(d, dl), _text(p, pl), limit), dst, cap)


def main():
    print("persona.elf: the persona in Mojo")
    # The Lean gate's expected answers; exit code 0 means the Mojo port still agrees.
    var plan = answer_json("")
    if plan == "{\"goal\":\"delivered\",\"plan\":[\"recharge\",\"move_to_storage\",\"pickup\",\"move_to_shipping\",\"dropoff\"],\"reached\":true}":
        print("RESULT: persona_ask('') is the delivery plan")
    else:
        print("RESULT: persona_ask('') wrong", plan)
        exit(1)
    if answer_json("no-such-goal-xyzzy") == "{\"refused\":\"undeclared_goal\"}":
        print("RESULT: an undeclared goal is refused by name")
    else:
        print("RESULT: the undeclared goal was not refused")
        exit(1)
    external_call["sandbox_register_api", NoneType]()
