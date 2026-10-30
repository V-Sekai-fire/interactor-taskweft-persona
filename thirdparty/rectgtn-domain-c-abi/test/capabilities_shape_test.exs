# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.CapabilitiesShapeTest do
  @moduledoc """
  `graph.edges` is the only representation of a capability holding.

  The loader used to compile a flat `capabilities.entities` map into
  `HAS_CAPABILITY` edges, and it also populated `_cap_<cap>` state vars. Both
  are gone: the schema closes the `capabilities` set to `graph`, so a document
  that still writes the sugar holds nothing, and the same document written the
  canonical way plans.

  The two domains below differ only in that block, so the pair is its own
  control: if the sugar were still compiled the first case would plan.
  """

  use ExUnit.Case, async: true

  @context %{
    "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
    "domain" => "khr:planning/domain/"
  }

  @capabilities_sugar %{"entities" => %{"drone_1" => ["fly"]}}

  @capabilities_graph %{
    "graph" => %{
      "edges" => [%{"subject" => "drone_1", "rel" => "HAS_CAPABILITY", "object" => "fly"}],
      "definitions" => %{}
    }
  }

  defp domain(capabilities) do
    %{
      "@context" => @context,
      "@type" => "domain:Definition",
      "name" => "cap_shape",
      "variables" => [%{"name" => "loc", "type" => "int", "init" => %{"drone_1" => 0}}],
      "capabilities" => capabilities,
      "actions" => %{
        "a_fly" => %{
          "params" => ["agent", "to_loc"],
          "body" => [
            %{
              "eval" => %{
                "type" => "rebac/check",
                "rel" => "HAS_CAPABILITY",
                "subject" => "{agent}",
                "object" => "fly"
              }
            },
            %{"pointer/set" => "/loc/{agent}", "value" => "{to_loc}"}
          ]
        }
      },
      "methods" => %{
        "top" => %{
          "params" => [],
          "alternatives" => [%{"name" => "fly", "subtasks" => [["a_fly", "drone_1", 1]]}]
        }
      },
      "todo_list" => [["top"]]
    }
    |> Jason.encode!()
  end

  defp plan(domain_json) do
    case Taskweft.plan(domain_json) do
      {:ok, out} -> {:ok, Jason.decode!(out)["plan"]}
      {:error, reason} -> {:error, reason}
    end
  end

  test "the graph form holds the capability and the guarded action runs" do
    assert plan(domain(@capabilities_graph)) == {:ok, [["a_fly", "drone_1", "1"]]}
  end

  test "control: the entities sugar holds no capability, so the action is refused" do
    assert {:error, reason} = plan(domain(@capabilities_sugar))
    assert reason =~ "no_plan"
  end

  test "control: the two domains differ only in the capabilities block" do
    sugar = domain(@capabilities_sugar) |> Jason.decode!() |> Map.delete("capabilities")
    graph = domain(@capabilities_graph) |> Jason.decode!() |> Map.delete("capabilities")

    assert sugar == graph
  end
end
