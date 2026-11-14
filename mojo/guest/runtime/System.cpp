//===----------------------------------------------------------------------===//
// Copyright (c) 2026, Modular Inc. All rights reserved.
//
// Licensed under the Apache License v2.0 with LLVM Exceptions:
// https://llvm.org/LICENSE.txt
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

// Fork of Mojo/lib/CompilerRT/System.cpp (modular/modular e6e596ce, Apache-2.0 with
// LLVM exceptions). Dropped: the HWInfo core counts (a guest has one hart), the
// Config lookup and llvm::sys stack traces (no handler is installed). Kept as
// upstream: KGEN_CompilerRT_fprintf, GetArgV and SetArgV.
#include "upstream/Memory.h"
#include "Support/SymbolExport.h"
#include "llvm/ADT/StringRef.h"
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT size_t KGEN_CompilerRT_NumPhysicalCores() { return 1; }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT size_t KGEN_CompilerRT_NumLogicalCores() { return 1; }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT size_t KGEN_CompilerRT_NumPerformanceCores() { return 1; }

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT int
KGEN_CompilerRT_fprintf(FILE *stream, const char *format, ...) {
  va_list args;
  va_start(args, format);
  int result = vfprintf(stream, format, args);
  va_end(args);
  return result;
}

namespace {
/// This class represents the set of argv values passed to the current mojo
/// program.
struct ArgVList {
  /// The raw list of arguments, used when communicating with Mojo.
  struct RawList {
    llvm::StringRef *args;
    size_t size;
  };

  /// Return the global argv instance.
  static ArgVList &get() {
    static ArgVList argVList;
    return argVList;
  }

  /// Return the raw list of arguments.
  RawList getRawList() { return {args.data(), args.size()}; }

  /// Allow argv[0] to be empty by default, matching python behavior when no
  /// script name is passed.
  std::vector<llvm::StringRef> args{""};
  std::vector<std::string> argStrings;
};
} // namespace

COMPILERRT_EXPORT
COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_GetArgV(ArgVList::RawList *result) {
  *result = ArgVList::get().getRawList();
}

COMPILERRT_EXPORT
COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_SetArgV(int argc,
                                                          char **argv) {
  ArgVList &argVList = ArgVList::get();
  argVList.args.resize(argc);
  argVList.argStrings.resize(argc);
  for (int i = 0; i < argc; ++i)
    argVList.args[i] = argVList.argStrings[i] = argv[i];
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_PrintStackTraceOnFault() {}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT int
KGEN_CompilerRT_GetStackTrace(char **strings, unsigned depth) {
  (void)strings; (void)depth;
  return 0;
}
