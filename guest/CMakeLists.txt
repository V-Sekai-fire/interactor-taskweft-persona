# The persona guest: a riscv64 godot-sandbox ELF whose body is the persona's Lean.
#
# Two pieces of workspace machinery, both from the goal manifest's siblings:
#   * contract-guest-runtime's `cmake/guest_runtime.cmake` gives `sandbox_api`
#     and `add_sandbox_program`, so the guest's surface is a set of Godot-typed
#     functions (guest/main.cpp) rather than a hand-rolled C ABI. sandbox-api's
#     api.cpp emits the `.sandbox_variant` marker for the Variant size it was
#     built with, so this guest must not emit a second one.
#   * interactor-lean-guest's `cmake/lean_guest.cmake` gives the Lean runtime and
#     Init for riscv64 (`leanrt_guest`, `leaninit_guest`).
#
#   cmake -S guest -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
#     -DCMAKE_TOOLCHAIN_FILE=<ws>/5-repository/riscv64-sysroot/toolchain.cmake \
#     -DGUEST_RUNTIME_ROOT=<ws>/2-contract/guest-runtime \
#     -DLEAN_GUEST_DIR=<ws>/3-interactor/lean-guest
#   cmake --build build --target persona
#   cp build/persona build/persona.elf
#
# SPDX-License-Identifier: MIT
cmake_minimum_required(VERSION 3.20)
project(persona_guest C CXX)

set(GUEST_RUNTIME_ROOT "" CACHE PATH "contract-guest-runtime checkout")
set(LEAN_GUEST_DIR "" CACHE PATH "interactor-lean-guest checkout")
if(NOT GUEST_RUNTIME_ROOT OR NOT LEAN_GUEST_DIR)
  message(FATAL_ERROR "pass -DGUEST_RUNTIME_ROOT=<contract-guest-runtime> and -DLEAN_GUEST_DIR=<interactor-lean-guest>")
endif()

# --strip-debug, never -s: the host resolves every guest function through .symtab.
set(STRIPPED ON CACHE BOOL "" FORCE)

set(PERSONA_ROOT ${CMAKE_CURRENT_LIST_DIR}/..)

# The Lean release and the libuv version are pinned in interactor-lean-guest's own
# CMakeLists.txt, which its cmake/lean_guest.cmake expects to have been read already. Read them
# from there so there is one source of truth, and refuse a persona toolchain that disagrees: the
# C the persona emits and the runtime it links must be the same release.
file(STRINGS ${LEAN_GUEST_DIR}/CMakeLists.txt _lean_guest_pins REGEX "^set\\((LEAN|LIBUV)_VERSION ")
foreach(_pin IN LISTS _lean_guest_pins)
  string(REGEX MATCH "set\\(([A-Z]+)_VERSION \"([^\"]+)\"" _match "${_pin}")
  set(${CMAKE_MATCH_1}_VERSION "${CMAKE_MATCH_2}" CACHE STRING "")
endforeach()
file(STRINGS ${PERSONA_ROOT}/lean-toolchain _persona_toolchain)
string(REGEX REPLACE "^leanprover/lean4:v" "" _persona_lean "${_persona_toolchain}")
if(NOT _persona_lean STREQUAL LEAN_VERSION)
  message(FATAL_ERROR
    "the persona's lean-toolchain is ${_persona_lean} and the guest runtime is ${LEAN_VERSION}; "
    "the emitted C and the runtime must be the same release")
endif()

include(${GUEST_RUNTIME_ROOT}/cmake/guest_runtime.cmake)
include(${LEAN_GUEST_DIR}/cmake/lean_guest.cmake)

# The persona's own modules, and the planner it requires as a library. Lake
# resolves both from the persona root; the planner's C lands in the vendored
# domain's own `.lake/build/ir`, which is where the paths below point.
set(GUEST_MODULES
  Persona.Guest
  Persona
  Persona.Demo
  Planner.Types
  Planner.BlocksWorld
  Planner.UnifiedGTN)

file(GLOB_RECURSE GUEST_LEAN ${PERSONA_ROOT}/*.lean)
list(FILTER GUEST_LEAN EXCLUDE REGEX "/\\.lake/")

set(GUEST_C)
foreach(_m IN LISTS GUEST_MODULES)
  string(REPLACE "." "/" _path ${_m})
  if(_m MATCHES "^Planner\\.")
    list(APPEND GUEST_C ${PERSONA_ROOT}/thirdparty/rectgtn-domain-c-abi/.lake/build/ir/${_path}.c)
  else()
    list(APPEND GUEST_C ${PERSONA_ROOT}/.lake/build/ir/${_path}.c)
  endif()
endforeach()

# One lake invocation for all six. `Persona:c` cannot be addressed: the library and
# the module share the name, so lake answers with the library and refuses the `c`
# facet. The module's C comes out of the two exes' closure instead, since both import
# it, and only the guest module is asked for by name.
add_custom_command(OUTPUT ${GUEST_C}
  COMMAND ${LAKE_EXE} build Persona.Guest:c persona persona_witness
  WORKING_DIRECTORY ${PERSONA_ROOT}
  DEPENDS ${GUEST_LEAN}
  VERBATIM)

add_sandbox_program(persona ${CMAKE_CURRENT_LIST_DIR}/main.cpp ${GUEST_C})
target_compile_features(persona PRIVATE cxx_std_23)
target_link_libraries(persona PRIVATE leaninit_guest pthread)
# One section a function: the guest carries the whole Lean runtime and sandbox_api's
# whole archive, and only the reachable parts of both should reach the ELF.
target_compile_options(persona PRIVATE -ffunction-sections -fdata-sections)
target_link_options(persona PRIVATE -Wl,--gc-sections)
