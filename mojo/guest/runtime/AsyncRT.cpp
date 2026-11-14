// Replaces Mojo/lib/CompilerRT/AsyncRT.cpp (modular/modular e6e596ce). The original
// is a thread pool on AsyncRT/Runtime, which is not in the public tree. This is the
// same entry points on a pool of one worker: the thread that waits. Execute and
// AndThen queue the coroutine, and the queue runs, in order, whenever the program
// waits on a chain or the runtime is released. Complete moves a chain's
// continuations onto the queue, as the original does with its work queue.
//
// A chain is the pointer-sized slot Mojo's _Chain holds, pointing at a ChainState.
#include "Support/SymbolExport.h"
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <utility>
#include <vector>

namespace {

using Resume = void (*)(int8_t *);

struct Job { Resume resume; int8_t *hdl; };

struct ChainState {
  bool ready = false;
  std::vector<Job> waiters;
};

// The one worker's queue.
std::deque<Job> &queue() {
  static std::deque<Job> q;
  return q;
}

bool runOne() {
  if (queue().empty()) return false;
  Job j = queue().front();
  queue().pop_front();
  j.resume(j.hdl);
  return true;
}

void drain() { while (runOne()) {} }

char cpuDevice;

ChainState *&state(void *chain) { return *static_cast<ChainState **>(chain); }

// Chains that wait on a Godot timer, earliest deadline first.
struct Armed { long deadline_us; ChainState *chain; };
std::vector<Armed> &armed() {
  static std::vector<Armed> a;
  return a;
}

} // namespace

extern "C" void sandbox_drain(void) { drain(); }
extern "C" long sandbox_ticks_usec(void);
extern "C" void sandbox_arm_timer_ns(long ns);

// Arms a one-shot host timer that completes `chain` when it fires. The caller suspends, so the
// guest returns to the host and nothing runs, or is charged, until the timer's timeout.
extern "C" void sandbox_wake_chain_after(void *chain, long ns) {
  armed().push_back({sandbox_ticks_usec() + ns / 1000, *static_cast<ChainState **>(chain)});
  sandbox_arm_timer_ns(ns);
}

// The host timer's timeout: the earliest armed chain completes and its waiters run.
extern "C" void sandbox_timer_fired(void) {
  std::vector<Armed> &a = armed();
  if (a.empty()) return;
  size_t first = 0;
  for (size_t i = 1; i < a.size(); i++)
    if (a[i].deadline_us < a[first].deadline_us) first = i;
  ChainState *s = a[first].chain;
  a.erase(a.begin() + first);
  s->ready = true;
  for (Job &j : s->waiters) queue().push_back(j);
  s->waiters.clear();
  drain();
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_InitializeChain(void *chain) {
  state(chain) = new ChainState();
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_DestroyChain(void *chain) {
  delete state(chain);
  state(chain) = nullptr;
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_Complete(void *chain) {
  ChainState *s = state(chain);
  s->ready = true;
  for (Job &j : s->waiters) queue().push_back(j);
  s->waiters.clear();
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_Wait(void *chain) {
  ChainState *s = state(chain);
  while (!s->ready) {
    if (!runOne()) {
      // Nothing is queued and no other thread exists to complete the chain.
      std::fputs("AsyncRT: Wait on a chain that nothing can complete\n", stderr);
      std::abort();
    }
  }
}

// With one worker only queued work can complete a chain, so the queue is drained first. If the
// chain is still not ready, the deadline is waited out on Godot's clock. A host with no clock
// answers at once.
extern "C" long sandbox_ticks_usec(void);

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT bool KGEN_CompilerRT_AsyncRT_Wait_Timeout(void *chain, int64_t ns) {
  ChainState *s = state(chain);
  while (!s->ready && runOne()) {}
  if (s->ready) return true;
  long start = sandbox_ticks_usec();
  if (start < 0) return false;
  while (sandbox_ticks_usec() - start < ns / 1000) {}
  return false;
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_AsyncRT_Execute(Resume resume, int8_t *hdl, ssize_t desiredWorkerId) {
  (void)desiredWorkerId; // there is only worker 0
  queue().push_back({resume, hdl});
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void
KGEN_CompilerRT_AsyncRT_AndThen(Resume resume, void *chain, int8_t *hdl) {
  ChainState *s = state(chain);
  if (s->ready) queue().push_back({resume, hdl});
  else s->waiters.push_back({resume, hdl});
}

COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *KGEN_CompilerRT_AsyncRT_GetCurrentCPUDevice() { return nullptr; }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *KGEN_CompilerRT_AsyncRT_GetOrCreateCPUDevice() { return &cpuDevice; }
// The device is released as the program ends, so tasks nobody waited for run now.
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_ReleaseCPUDevice(void *) { drain(); }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT uint32_t KGEN_CompilerRT_AsyncRT_ParallelismLevel() { return 1; }

// A spin waiter on one worker lets the queue make progress instead of spinning.
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void *KGEN_CompilerRT_AsyncRT_InitializeSpinWaiter() { return new char; }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_SpinWaiter_Wait(void *) { runOne(); }
COMPILERRT_EXPORT COMPILERRT_VISIBILITY_EXPORT void KGEN_CompilerRT_AsyncRT_DestroySpinWaiter(void *w) { delete static_cast<char *>(w); }
