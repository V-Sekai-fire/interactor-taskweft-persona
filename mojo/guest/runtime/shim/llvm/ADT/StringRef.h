// A pointer-and-length view with the layout of llvm::StringRef, which is how
// Mojo's compiled code passes a name to KGEN_CompilerRT_GetOrCreateGlobal.
#pragma once
#include <cstddef>
#include <cstring>
#include <string>
namespace llvm {
class StringRef {
  const char *Data = nullptr;
  size_t Length = 0;
public:
  StringRef() = default;
  StringRef(const char *s) : Data(s), Length(s ? std::strlen(s) : 0) {}
  StringRef(const char *s, size_t n) : Data(s), Length(n) {}
  StringRef(const std::string &s) : Data(s.data()), Length(s.size()) {}
  const char *data() const { return Data; }
  size_t size() const { return Length; }
  std::string str() const { return std::string(Data, Length); }
};
} // namespace llvm
