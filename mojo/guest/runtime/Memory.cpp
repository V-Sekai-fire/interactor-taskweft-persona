// Fork of Mojo/lib/CompilerRT/Memory.cpp (modular/modular e6e596ce, Apache-2.0 with
// LLVM exceptions). The tcmalloc globals and logging of the original are replaced
// by libc aligned_alloc and free.
#include "upstream/Memory.h"
#include "Support/SymbolExport.h"
#include <cstdlib>

static constexpr size_t kPreferredMemoryAlignment = 64;

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_SetAsanAllocators() {}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *
KGEN_CompilerRT_AlignedAlloc(ssize_t alignment, ssize_t size) {
  if (alignment <= 0) alignment = kPreferredMemoryAlignment;
  size_t a = (size_t)alignment, n = (size_t)size;
  return std::aligned_alloc(a, (n + a - 1) / a * a);
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AlignedFree(void *ptr) {
  std::free(ptr);
}
