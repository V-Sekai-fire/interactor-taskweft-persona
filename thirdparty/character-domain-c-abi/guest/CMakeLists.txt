cmake_minimum_required(VERSION 3.16)
project(character_guest C)

# A self-contained RISC-V64 Linux guest (godot-sandbox / libriscv). Mirrors
# 3-interactor/usd-guest and the RECTGTN domain's guest: it emits the
# `.sandbox_variant` section and exports the character_* C-ABI symbols.
set(CMAKE_C_STANDARD 11)
add_executable(character main.c)
target_include_directories(character PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)

option(DOUBLE_PRECISION "Emit a 40-byte Variant (double) instead of 24" ON)
option(STRIPPED "Strip debug info but keep .symtab" ON)
if(DOUBLE_PRECISION)
  target_compile_definitions(character PRIVATE DOUBLE_PRECISION)
endif()
if(STRIPPED)
  add_link_options(-Wl,--strip-debug)
endif()

# The host reads the Variant size from .sandbox_variant at load time.
add_custom_command(TARGET character POST_BUILD
  COMMAND ${CMAKE_OBJCOPY} -O binary --only-section=.sandbox_variant
          $<TARGET_FILE:character> ${CMAKE_BINARY_DIR}/variant.bin
  COMMENT "Extracting .sandbox_variant")
