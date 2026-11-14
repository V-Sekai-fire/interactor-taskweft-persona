// SPDX-License-Identifier: MIT
// persona.elf (the Mojo guest) in a browser: libriscv runs the riscv64 ELF, and this file is the
// godot-sandbox host it expects, cut down to what the persona calls.
//
//   ecall 547 register a guest function   ecall 517 make a String   ecall 519 read a String
//   ecall 512 is-editor (0)               ecall 483 free (a no-op: the scratch is reset per call)
//
// The module exports the surface the Pages site already uses from the Lean build:
//   persona_init() -> 0                       run the guest's main, which registers its functions
//   persona_plan_jsonld(domain, problem, goal) -> String
//   persona_goals(domain, problem) -> String
//   persona_ask(goal) -> String               persona_version() -> String
// The same file is a command line tool (PERSONA_CLI) used to emit the binary translation and to
// time it: node persona_cli.js --gen out.c | --bench N | --verbose | --no-embedded.
#include <libriscv/machine.hpp>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iterator>
#include <map>
#include <memory>
#include <string>
#include <vector>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#else
#define EMSCRIPTEN_KEEPALIVE
#endif

using Machine = riscv::Machine<riscv::RISCV64>;
using addr_t = riscv::address_type<riscv::RISCV64>;

static const unsigned char elf_bytes[] = {
#include "persona_elf.inc"
};

static std::unique_ptr<Machine> g_machine;
static std::map<std::string, addr_t> g_fn;
static std::vector<std::string> g_vars;   // the host's scoped Strings, cleared per call
static addr_t g_scratch = 0, g_scratch_used = 0;
static constexpr size_t SCRATCH = 16 << 20;
static constexpr uint64_t FUEL = 4'000'000'000ull;
static std::string g_answer;
static bool g_verbose = false, g_embedded = true;
static std::string* g_gen = nullptr;

static addr_t scratch_alloc(size_t n) {
	n = (n + 15) & ~size_t(15);
	if (g_scratch_used + n > SCRATCH) throw std::runtime_error("scratch exhausted");
	addr_t a = g_scratch + g_scratch_used;
	g_scratch_used += n;
	return a;
}

static void install() {
	Machine::install_syscall_handler(547, [](Machine& m) {
		auto name = m.memory.memview(m.sysarg<addr_t>(1), m.sysarg<addr_t>(2));
		g_fn[std::string(name)] = m.sysarg<addr_t>(3);
		m.set_result(0);
	});
	Machine::install_syscall_handler(512, [](Machine& m) { m.set_result(0); });
	Machine::install_syscall_handler(483, [](Machine& m) { m.set_result(0); });
	Machine::install_syscall_handler(517, [](Machine& m) {
		addr_t v = m.sysarg<addr_t>(0);
		struct { addr_t data, size; } in;
		m.copy_from_guest(&in, m.sysarg<addr_t>(3), sizeof in);
		g_vars.emplace_back(m.memory.memview(in.data, in.size, 8u << 20));
		int32_t type = 4; int64_t idx = (int64_t)g_vars.size() - 1;
		m.copy_to_guest(v, &type, 4);
		m.copy_to_guest(v + 8, &idx, 8);
		m.set_result(0);
	});
	Machine::install_syscall_handler(519, [](Machine& m) {
		uint32_t idx = (uint32_t)m.sysarg<addr_t>(0);
		struct { addr_t data, size; } out{0, 0};
		if (idx < g_vars.size()) {
			const auto& s = g_vars[idx];
			out.data = scratch_alloc(s.size() + 1);
			out.size = s.size();
			m.copy_to_guest(out.data, s.data(), s.size());
		}
		m.copy_to_guest(m.sysarg<addr_t>(1), &out, sizeof out);
		m.set_result(0);
	});
}

static riscv::MachineOptions<riscv::RISCV64> options() {
	riscv::MachineOptions<riscv::RISCV64> opt;
	opt.memory_max = 512ull << 20;
	opt.verbose_loader = g_verbose;
	// No compiler at run time: the translation is C99 compiled into this module, found by hash.
	opt.translate_invoke_compiler = false;
	opt.translate_enable_embedded = g_embedded;
#ifdef PERSONA_REGCACHE
	// Guest registers become C locals inside a translated block, written back when it exits.
	opt.translate_use_register_caching = true;
#endif
#ifdef PERSONA_NBIT
	// The arena is a power of two, so an address can be masked instead of range-checked.
	opt.translate_automatic_nbit_address_space = true;
#endif
	if (g_gen) {
		riscv::MachineTranslationEmbeddableCodeOptions e;
		e.result_c99 = g_gen;
		opt.cross_compile.push_back(e);
	}
	return opt;
}

static int boot() {
	if (g_machine) return 0;
	static std::string_view elf{(const char*)elf_bytes, sizeof elf_bytes};
	g_machine = std::make_unique<Machine>(elf, options());
	g_machine->setup_linux_syscalls();
	g_machine->setup_linux({"persona.elf"}, {"LC_ALL=C"});
	install();
	g_scratch = g_machine->memory.mmap_allocate(SCRATCH);
	if (g_gen) return 0;   // generating: loading the ELF emitted the C, nothing runs
	try {
		g_machine->simulate(FUEL);
	} catch (const std::exception& e) {
		fprintf(stderr, "persona: the guest's main raised: %s\n", e.what());
		g_machine.reset();
		return 1;
	}
	return g_fn.count("persona_ask") && g_fn.count("persona_plan_jsonld") ? 0 : 2;
}

// Call a registered guest function with String arguments; the answer, or "" when it was NIL.
static const char* call(const char* fn, std::initializer_list<const char*> args) {
	g_answer.clear();
	if (!g_machine || !g_fn.count(fn)) return g_answer.c_str();
	g_scratch_used = 0;
	g_vars.clear();
	try {
		addr_t ret = scratch_alloc(16);
		int32_t nil = 0; int64_t zero = 0;
		g_machine->copy_to_guest(ret, &nil, 4);
		g_machine->copy_to_guest(ret + 8, &zero, 8);
		std::vector<addr_t> av;
		for (const char* a : args) {
			addr_t v = scratch_alloc(16);
			g_vars.emplace_back(a ? a : "");
			int32_t type = 4; int64_t idx = (int64_t)g_vars.size() - 1;
			g_machine->copy_to_guest(v, &type, 4);
			g_machine->copy_to_guest(v + 8, &idx, 8);
			av.push_back(v);
		}
		const addr_t f = g_fn[fn];
		switch (av.size()) {
		case 0: g_machine->vmcall<FUEL>(f, ret); break;
		case 1: g_machine->vmcall<FUEL>(f, ret, av[0]); break;
		case 2: g_machine->vmcall<FUEL>(f, ret, av[0], av[1]); break;
		default: g_machine->vmcall<FUEL>(f, ret, av[0], av[1], av[2]); break;
		}
		int32_t type = 0; int64_t idx = 0;
		g_machine->copy_from_guest(&type, ret, 4);
		g_machine->copy_from_guest(&idx, ret + 8, 8);
		if (type == 4 && (size_t)idx < g_vars.size()) g_answer = g_vars[(size_t)idx];
	} catch (const std::exception& e) {
		fprintf(stderr, "persona: %s raised: %s\n", fn, e.what());
		g_answer.clear();
	}
	return g_answer.c_str();
}

extern "C" {
EMSCRIPTEN_KEEPALIVE int persona_init(void) { return boot(); }
// The hash of the binary translation the guest is running on, or 0 when it is interpreted.
EMSCRIPTEN_KEEPALIVE unsigned persona_translation_hash(void) {
	if (!g_machine) return 0;
	auto& seg = g_machine->cpu.current_execute_segment();
	return seg.is_binary_translated() ? seg.translation_hash() : 0;
}
EMSCRIPTEN_KEEPALIVE const char* persona_version(void) { return call("persona_version", {}); }
EMSCRIPTEN_KEEPALIVE const char* persona_ask(const char* goal) { return call("persona_ask", {goal}); }
EMSCRIPTEN_KEEPALIVE const char* persona_plan(const char* spec) { return call("persona_plan", {spec}); }
EMSCRIPTEN_KEEPALIVE const char* persona_plan_shortest(const char* d, const char* p, int limit) {
	std::string lim = std::to_string(limit);
	return call("persona_plan_shortest", {d, p, lim.c_str()});
}
EMSCRIPTEN_KEEPALIVE const char* persona_goals(const char* d, const char* p) {
	return call("persona_goals", {d, p});
}
EMSCRIPTEN_KEEPALIVE const char* persona_plan_jsonld(const char* d, const char* p, const char* g) {
	return call("persona_plan_jsonld", {d, p, g});
}
}

#ifdef PERSONA_CLI
static std::string slurp(const char* path) {
	std::ifstream f(path, std::ios::binary);
	return std::string(std::istreambuf_iterator<char>(f), {});
}

int main(int argc, char** argv) {
	std::string gen_path, dom, prob, goal, mode;
	int bench = 0;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		if (a == "--verbose") g_verbose = true;
		else if (a == "--no-embedded") g_embedded = false;
		else if (a == "--gen" && i + 1 < argc) gen_path = argv[++i];
		else if (a == "--bench" && i + 1 < argc) bench = atoi(argv[++i]);
		else if (a == "--domain" && i + 1 < argc) dom = slurp(argv[++i]);
		else if (a == "--problem" && i + 1 < argc) prob = slurp(argv[++i]);
		else if (a == "--goal" && i + 1 < argc) goal = argv[++i];
	}
	std::string c99;
	if (!gen_path.empty()) g_gen = &c99;
	auto t0 = std::chrono::steady_clock::now();
	int rc = boot();
	auto t1 = std::chrono::steady_clock::now();
	if (g_gen) {
		std::ofstream(gen_path) << c99;
		printf("wrote %zu bytes of C99 to %s\n", c99.size(), gen_path.c_str());
		return 0;
	}
	if (rc) { printf("boot failed: %d\n", rc); return 1; }
	printf("boot (load + guest main): %.1f ms\n", std::chrono::duration<double, std::milli>(t1 - t0).count());
	printf("persona_version: %s\n", persona_version());
	if (dom.empty()) {
		printf("persona_ask(\"\"): %s\n", persona_ask(""));
		return 0;
	}
	std::string first = persona_plan_jsonld(dom.c_str(), prob.c_str(), goal.c_str());
	printf("answer: %zu bytes, sha %zu\n", first.size(), std::hash<std::string>{}(first));
	if (bench > 0) {
		auto b0 = std::chrono::steady_clock::now();
		for (int i = 0; i < bench; i++) {
			if (first != persona_plan_jsonld(dom.c_str(), prob.c_str(), goal.c_str())) { printf("ANSWER CHANGED\n"); return 1; }
		}
		auto b1 = std::chrono::steady_clock::now();
		double ms = std::chrono::duration<double, std::milli>(b1 - b0).count();
		printf("bench: %d plans in %.1f ms = %.2f ms/plan, %llu guest instructions total\n", bench, ms, ms / bench,
		       (unsigned long long)g_machine->instruction_counter());
	}
	return 0;
}
#endif
