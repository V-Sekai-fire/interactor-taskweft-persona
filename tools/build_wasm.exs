# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Builds the persona planner as WebAssembly: the Lean C of the persona, Init and Std, and the runtime.
#   elixir tools/build_wasm.exs <core-dir> <out-dir>
# <core-dir> holds the C emitted for the toolchain's Init and Std (c/), gen/include and lean4/src,
# the layout interactor-lean-guest builds for its riscv64 core.
[core, out] = System.argv()
root = Path.expand("..", __DIR__)
objs = Path.join(out, "obj")
File.mkdir_p!(objs)

defmodule Wasm do
  @defs ~w(-DNDEBUG -ffp-contract=off -w -DLEAN_EXPORTING -DLEAN_NO_UV -DLEAN_NO_OPENSSL -DLEAN_EMSCRIPTEN)

  def cc(tool, args) do
    case System.cmd(tool, args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {text, _} -> {:error, text}
    end
  end

  def compile(core, src, obj) do
    inc = ["-I#{core}/gen/include", "-I#{core}/lean4/src/include"]

    cc(
      "emcc",
      ["-c", "-O1", "-ffunction-sections", "-fdata-sections"] ++ @defs ++ inc ++ [src, "-o", obj]
    )
  end

  def runtime(core, src, obj) do
    uv = Path.join(core, "../libuv-1.48.0/src/include")

    inc = [
      "-I#{core}/gen/include",
      "-I#{core}/lean4/src/include",
      "-I#{core}/lean4/src",
      "-I#{uv}"
    ]

    cc(
      "emcc",
      ["-c", "-O1", "-std=c++20", "-fwasm-exceptions"] ++ @defs ++ inc ++ [src, "-o", obj]
    )
  end
end

{_, 0} = System.cmd("lake", ["build", "Persona.Grid:c", "Persona.Web:c", "persona_witness"], cd: root)

lean_c =
  for dir <- [
        Path.join(root, ".lake/build/ir"),
        Path.join(root, "thirdparty/rectgtn-domain-c-abi/.lake/build/ir")
      ],
      f <- Path.wildcard(Path.join(dir, "**/*.c")),
      not String.contains?(f, "Witness"),
      do: f

# Init and Std whole, plus the Lean modules the JSON-LD path reaches: the closure of the
# `initialize_*` calls from our own C into the toolchain's Lean.* C (Lean.Data.Json and what it needs).
lean_mods =
  for f <- Path.wildcard(Path.join(core, "c/Lean*.c")),
      into: %{},
      do: {"initialize_" <> (Path.basename(f, ".c") |> String.replace(".", "_")), f}

reach = fn reach, pending, seen ->
  case pending do
    [] ->
      seen

    [f | rest] ->
      calls =
        ~r/initialize_[A-Za-z0-9_]+(?=\()/
        |> Regex.scan(File.read!(f))
        |> List.flatten()
        |> Enum.flat_map(&List.wrap(lean_mods[&1]))
        |> Enum.reject(&MapSet.member?(seen, &1))
        |> Enum.uniq()

      reach.(reach, rest ++ calls, MapSet.union(seen, MapSet.new(calls)))
  end
end

core_lean = reach.(reach, lean_c ++ Path.wildcard(Path.join(core, "c/{Init,Std}*.c")), MapSet.new())

core_c = Path.wildcard(Path.join(core, "c/{Init,Std}*.c")) ++ MapSet.to_list(core_lean)

rt_cpp =
  for f <- Path.wildcard(Path.join(core, "lean4/src/runtime/*.cpp")),
      not String.starts_with?(Path.basename(f), "uv_"),
      do: f

jobs =
  for f <- core_c ++ lean_c,
      do: {&Wasm.compile/3, f, Path.join(objs, "c-" <> Path.basename(f) <> ".o")}

jobs =
  jobs ++
    for(f <- rt_cpp, do: {&Wasm.runtime/3, f, Path.join(objs, "rt-" <> Path.basename(f) <> ".o")})

jobs = jobs ++ [{&Wasm.compile/3, Path.join(root, "wasm/shim.c"), Path.join(objs, "shim.o")}]


failed =
  jobs
  |> Task.async_stream(fn {fun, src, obj} -> {src, fun.(core, src, obj)} end,
    max_concurrency: System.schedulers_online(),
    timeout: :infinity,
    ordered: false
  )
  |> Enum.flat_map(fn
    {:ok, {src, {:error, text}}} -> [{src, text}]
    _ -> []
  end)

if failed != [] do
  for {src, text} <- failed, do: IO.puts("FAIL #{src}\n#{text}")
  System.halt(1)
end

link =
  ~w(-O2 -fwasm-exceptions -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=PersonaModule
     -sENVIRONMENT=web,worker,node -sALLOW_MEMORY_GROWTH=1 -sINITIAL_MEMORY=64MB -sSTACK_SIZE=8MB
     -sEXPORTED_FUNCTIONS=_persona_init,_persona_plan,_persona_goals,_persona_plan_jsonld,_persona_plan_shortest,_malloc,_free
     -sEXPORTED_RUNTIME_METHODS=ccall,cwrap -Wl,--gc-sections) ++
    Path.wildcard(Path.join(objs, "*.o")) ++ ["-o", Path.join(out, "persona.mjs")]

{_, 0} = System.cmd("em++", link, stderr_to_stdout: true)
IO.puts("wasm: #{File.stat!(Path.join(out, "persona.wasm")).size} bytes in #{out}")
