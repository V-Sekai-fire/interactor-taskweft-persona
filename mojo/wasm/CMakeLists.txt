# persona.elf under libriscv, as WebAssembly. Built by tools/build_wasm_host.sh.
#   -DPERSONA_TARGET=module   persona.mjs + persona.wasm, the browser module
#   -DPERSONA_TARGET=cli      persona_cli.js, run with node: emits the translation, times it
# -DBINTR_DIR=<dir> names the directory of translated C99 to compile in (none: interpreter only).
cmake_minimum_required(VERSION 3.10)
project(persona_wasm CXX C)
set(PERSONA_TARGET "module" CACHE STRING "module or cli")
set(BINTR_DIR "" CACHE PATH "directory of translated C99")
set(BINTR_OPT "-O1" CACHE STRING "flags for the translated C99")
option(PERSONA_NBIT "Mask addresses to the power-of-two arena" ON)
option(PERSONA_REGCACHE "Translate with guest registers cached in C locals" OFF)

set(RISCV_BINARY_TRANSLATION ON CACHE BOOL "" FORCE)
set(RISCV_LIBTCC OFF CACHE BOOL "" FORCE)
set(RISCV_EXT_V OFF CACHE BOOL "" FORCE)
set(RISCV_32I OFF CACHE BOOL "" FORCE)
set(RISCV_THREADED ON CACHE BOOL "" FORCE)
set(LIBRISCV_DIR "" CACHE PATH "libriscv checkout")
add_subdirectory(${LIBRISCV_DIR}/lib libriscv)
# The sandbox numbers its ecalls past libriscv's default table of 512.
target_compile_definitions(riscv PUBLIC RISCV_SYSCALLS_MAX=1024)

set(SRC persona_host.cpp)
if (BINTR_DIR)
  file(GLOB BINTR_SOURCES ${BINTR_DIR}/*.c)
  set_source_files_properties(${BINTR_SOURCES} PROPERTIES COMPILE_FLAGS "${BINTR_OPT} -w")
  list(APPEND SRC ${BINTR_SOURCES})
endif()
add_executable(persona_host ${SRC})
target_link_libraries(persona_host PRIVATE riscv)
set_target_properties(persona_host PROPERTIES CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON)
if (PERSONA_NBIT)
  target_compile_definitions(persona_host PRIVATE PERSONA_NBIT=1)
endif()
if (PERSONA_REGCACHE)
  target_compile_definitions(persona_host PRIVATE PERSONA_REGCACHE=1)
endif()

# The one-call-at-a-time answer string is a static; one thread.
set(COMMON "-fexceptions -sTOTAL_MEMORY=1GB -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=4MB")
if (PERSONA_TARGET STREQUAL "cli")
  target_compile_definitions(persona_host PRIVATE PERSONA_CLI=1)
  set_target_properties(persona_host PROPERTIES OUTPUT_NAME persona_cli SUFFIX ".js"
    LINK_FLAGS "${COMMON} -sENVIRONMENT=node -sNODERAWFS=1")
else()
  set_target_properties(persona_host PROPERTIES OUTPUT_NAME persona SUFFIX ".mjs"
    LINK_FLAGS "${COMMON} -sENVIRONMENT=web,node -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createPersona \
-sEXPORTED_FUNCTIONS=_persona_init,_persona_translation_hash,_persona_version,_persona_ask,_persona_plan,_persona_plan_shortest,_persona_goals,_persona_plan_jsonld,_malloc,_free \
-sEXPORTED_RUNTIME_METHODS=cwrap,ccall,UTF8ToString,stringToUTF8,lengthBytesUTF8")
endif()
