// Stand-in for Modular's internal Support/SymbolExport.h (not in the public tree).
#pragma once
#define COMPILERRT_EXPORT extern "C"
#define COMPILERRT_VISIBILITY_EXPORT __attribute__((visibility("default")))
