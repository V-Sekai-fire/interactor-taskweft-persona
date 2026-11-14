# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: MIT
# Builds a guest ELF: Mojo object, the runtime stand-ins, a static link against the riscv64
# sysroot. Usage: elixir tools/build.exs [source.mojo name]
defmodule Build do
  @triple "riscv64-unknown-linux-gnu"

  def main(argv) do
    File.cd!(Path.expand("..", __DIR__))

    result =
      with {:ok, src, name} <- args(argv),
           {:ok, sysroot} <- sysroot(),
           :ok <- File.mkdir_p("build"),
           :ok <- mojo(src, name),
           :ok <- runtime(sysroot),
           :ok <- link(sysroot, name) do
        run("file", ["build/#{name}.elf"])
      end

    case result do
      :ok -> System.halt(0)
      {:error, reason} -> IO.puts(:stderr, "build failed: #{inspect(reason)}") && System.halt(1)
    end
  end

  defp args([]), do: {:ok, "persona_guest.mojo", "persona"}
  defp args([src, name]), do: {:ok, src, name}
  defp args(_), do: {:error, :usage}

  defp sysroot do
    candidates =
      [System.get_env("SYSROOT_REPO"), "../../../../5-repository/riscv64-sysroot", "../../../riscv64-sysroot"]

    case Enum.find(candidates, &(&1 && File.dir?(Path.join(&1, "sysroot")))) do
      nil -> {:error, :no_sysroot}
      repo -> {:ok, Path.expand(Path.join(repo, "sysroot"))}
    end
  end

  defp mojo(src, name) do
    flags = String.split(System.get_env("MOJO_FLAGS", "-I ../src"), " ", trim: true)

    run(
      "mojo",
      ["build", src] ++
        flags ++
        [
          "--target-accelerator=none",
          "--target-triple=#{@triple}",
          "--target-cpu=generic-rv64",
          "--target-features=+m,+a,+f,+d,+c",
          "--target-abi=lp64d",
          "--emit",
          "object",
          "-o",
          "build/#{name}_mojo.o"
        ]
    )
  end

  defp runtime(sysroot) do
    cxx = [
      "--target=#{@triple}",
      "--sysroot=#{sysroot}",
      "-march=rv64gc",
      "-mabi=lp64d",
      "-O2",
      "-std=c++20",
      "-isystem",
      "#{sysroot}/include/c++/14",
      "-isystem",
      "#{sysroot}/include/c++/14/riscv64-linux-gnu",
      "-Iruntime/shim",
      "-Iruntime"
    ]

    c = [
      "--target=#{@triple}",
      "--sysroot=#{sysroot}",
      "-march=rv64gc",
      "-mabi=lp64d",
      "-O2",
      "-DSANDBOX_VARIANT_SIZE=#{System.get_env("SANDBOX_VARIANT_SIZE", "40")}"
    ]

    sources = [
      {"clang++", cxx, "runtime/AsyncRT.cpp", "build/AsyncRT.o"},
      {"clang++", cxx, "runtime/Memory.cpp", "build/Memory.o"},
      {"clang++", cxx, "runtime/System.cpp", "build/System.o"},
      {"clang++", cxx, "runtime/upstream/Globals.cpp", "build/Globals.o"},
      {"clang", c, "runtime/sandbox_abi.c", "build/sandbox_abi.o"},
      {"clang", c ++ ["-fno-builtin", "-fno-builtin-memcpy"], "runtime/memcpy.c", "build/memcpy.o"}
    ]

    Enum.reduce_while(sources, :ok, fn {cc, flags, src, obj}, :ok ->
      case run(cc, flags ++ ["-c", src, "-o", obj]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp link(sysroot, name) do
    gcclib = "#{sysroot}/lib/gcc-cross/14"
    objects = for o <- ~w(AsyncRT Memory System Globals sandbox_abi memcpy), do: "build/#{o}.o"

    run(
      "clang++",
      [
        "--target=#{@triple}",
        "--sysroot=#{sysroot}",
        "-fuse-ld=lld",
        "-B#{gcclib}",
        "-L#{gcclib}",
        "-static",
        "-o",
        "build/#{name}.elf",
        "build/#{name}_mojo.o"
      ] ++ objects
    )
  end

  defp run(cmd, args) do
    case System.cmd(cmd, args, into: IO.stream(), stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, status} -> {:error, {cmd, status}}
    end
  end
end

Build.main(System.argv())
