// Stand-in for Modular's internal Support/ADT/GlobalTable.h. A named table of
// lazily created globals, destroyed in reverse creation order by clear().
#pragma once
#include "llvm/ADT/StringRef.h"
#include <cassert>
#include <cstddef>
#include <mutex>
#include <string>
#include <utility>
#include <vector>
namespace M {
class GlobalTable {
  struct Entry { std::string name; void *value; void (*destroy)(void *); };
  std::mutex mu;
  std::vector<Entry> entries;
public:
  // A null initFn only looks the name up.
  void *getOrCreate(llvm::StringRef name, void *(*initFn)(), void (*destroyFn)(void *)) {
    std::lock_guard<std::mutex> lock(mu);
    for (auto &e : entries)
      if (e.name.size() == name.size() && !std::memcmp(e.name.data(), name.data(), name.size()))
        return e.value;
    if (!initFn) return nullptr;
    // initFn may itself create globals, so it runs outside the table's view of "entries".
    void *v = initFn();
    entries.push_back({name.str(), v, destroyFn});
    return v;
  }
  void clear() {
    std::vector<Entry> old;
    { std::lock_guard<std::mutex> lock(mu); old.swap(entries); }
    for (size_t i = old.size(); i-- > 0;)
      if (old[i].destroy && old[i].value) old[i].destroy(old[i].value);
  }
};
} // namespace M
