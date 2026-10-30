# Guest ELF build configuration for the RECTGTN domain.
#
# Builds `rectgtn.elf` — a stripped, position-independent RISC-V64 Linux
# executable that the godot-sandbox / libriscv host loads and runs.
#
# Mirrors 4-entities/godot-sandbox/program/cpp/cmake/gdscript's CMake setup:
# the guest links the sandbox-variant section (SBXV + 4-byte LE Variant size)
# that the host reads at load time, and exposes the RECTGTN C-ABI symbols.
#
#   cmake -B build \
#     -DCMAKE_TOOLCHAIN_FILE=guest/toolchain.cmake \
#     -DCMAKE_BUILD_TYPE=MinSizeRel -DSTRIPPED=ON -DDOUBLE_PRECISION=ON
#   cmake --build build --parallel 4
#   mv build/rectgtn build/rectgtn.elf
#
# `STRIPPED` uses --strip-debug (not --strip-all): the host discovers the
# guest API from .symtab, and --strip-all leaves it unable to find a single
# guest function.
#
# `DOUBLE_PRECISION` (default: ON) makes the `.sandbox_variant` section carry
# a 40-byte (double-precision) Variant, matching the workspace's shared
# guest-runtime contract (2-contract/guest-runtime/cmake/guest_runtime.cmake
# forces DOUBLE_PRECISION=ON, and the opentelemetry-godot-project gate
# checks --variant-size=40). Pass -DDOUBLE_PRECISION=OFF to ship a
# single-precision (24-byte) guest.
#
# RISC-V flags mirror the godot-sandbox guest toolchain (see
# 4-entities/godot-sandbox/program/cpp/cmake/CMakeLists.txt lines 55-76):
# rv64g + C (compressed) + V (vector) + the four bit-manipulation extensions,
# all emulated by libriscv in both interpreter and JIT modes.
#
# The guest C shim (guest/main.c) currently provides stub bodies for every
# rectgtn_* symbol so the guest builds end-to-end. When the Lean core lands
# (RFD66606-2153 stage 3), `lake build` will emit the real .c intermediate
# implementing these symbols, and this CMake will link it against the shim's
# entry-point glue. Until then, `rectgtn.elf` builds and the symbol check
# passes, proving the CI shape.
#
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.10)
project(rectgtn_guest LANGUAGES C)

set(CMAKE_C_STANDARD 11)
option(DOUBLE_PRECISION "Enable double precision real_t (40-byte Variant)" ON)
option(STRIPPED "Strip executable with --strip-debug" ON)
option(MINIMAL "Build minimal programs using -Oz" OFF)

# RISC-V rv64g + C (compressed) + V (vector) + bit-manipulation extensions.
# All emulated by libriscv in both interpreter and JIT modes
# (matching the godot-sandbox guest toolchain).
set(RISCV_ARCH "-march=rv64g")
string(APPEND RISCV_ARCH "c")
string(APPEND RISCV_ARCH "v")
string(APPEND RISCV_ARCH "_zba_zbb_zbs_zbc")
set(RISCV_ABI "-mabi=lp64d")

# Double-precision (40-byte) Variant by default; single-precision (24-byte)
# for the -DDOUBLE_PRECISION=OFF case.
if(DOUBLE_PRECISION)
  add_compile_definitions(DOUBLE_PRECISION)
endif()

# Guest main: the C shim with the rectgtn_* symbols and the
# .sandbox_variant section emitter.  With `-S guest`, this file's source dir
# is `guest/`, so the shim is `main.c` and the header lives at `../api/`.
add_executable(rectgtn
  main.c
)
target_include_directories(rectgtn PRIVATE ${CMAKE_SOURCE_DIR}/../api)
target_compile_options(rectgtn PRIVATE ${RISCV_ARCH} ${RISCV_ABI} -O3 -std=gnu11)
if(MINIMAL)
  target_compile_options(rectgtn PRIVATE -Oz)
endif()

if(STRIPPED)
  target_link_options(rectgtn PRIVATE --strip-debug)
endif()
