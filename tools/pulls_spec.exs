# Copyright (c) 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Prints a pull request's facts as a persona_pulls spec, read from gh.
#   elixir tools/pulls_spec.exs <owner/repo> <number> <goal>
[repo, number, goal] = System.argv()
fields = "state,headRefName,body,statusCheckRollup"
{json, 0} = System.cmd("gh", ["pr", "view", number, "--repo", repo, "--json", fields])
pr = JSON.decode!(json)

done = fn name ->
  Enum.any?(
    pr["statusCheckRollup"] || [],
    &(String.starts_with?(&1["name"] || "", name) and &1["conclusion"] == "SUCCESS")
  )
end

merged = pr["state"] == "MERGED"
staged = String.match?(pr["headRefName"], ~r{^(dev|beta|rc|release|archived)/})
credit = String.match?(pr["body"] || "", ~r/Co-Authored-By|Generated with/i)

facts = [
  staged: staged,
  pushed: true,
  clean: not credit,
  open: pr["state"] in ["OPEN", "MERGED"],
  lean: done.("Lean core"),
  elf: done.("persona-elf"),
  checked: done.("Lean core") and done.("persona-elf"),
  approved: merged,
  merged: merged
]

for {name, on} <- facts, do: IO.puts("var #{name} #{if on, do: 1, else: 0}")
IO.puts("goal #{goal}")
