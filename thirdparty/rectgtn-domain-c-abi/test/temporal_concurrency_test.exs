# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.TemporalConcurrencyTest do
  @moduledoc """
  Steps that touch nothing in common run concurrently, so `temporal.total` is a
  makespan and not a sum.

  The temporal block used to accumulate every duration into one linear
  timeline. Each case below pairs a plan whose steps are independent with a
  plan whose steps contend, so the difference the concurrency rule makes is
  visible against its own control rather than asserted on its own.

  Contention is read off the action bodies: two steps conflict when one writes
  what the other writes or reads, or when their ReBAC guards name the same
  endpoint pair. A read against a read is not a conflict.

  Every state pointer here is `/var/key`, which is the whole pointer grammar —
  `build_action` refuses any other arity, so a one-segment path would make the
  action fail rather than test the schedule.
  """

  use ExUnit.Case, async: true

  @context %{
    "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
    "domain" => "khr:planning/domain/"
  }

  @five "PT5M"

  defp write_action(duration, path) do
    %{"params" => [], "duration" => duration, "body" => [%{"pointer/set" => path, "value" => true}]}
  end

  # A write whose value is itself a pointer read: the action's write set is
  # `to`, its read set is `from`.
  defp copy_action(duration, from, to) do
    %{
      "params" => [],
      "duration" => duration,
      "body" => [
        %{"pointer/set" => to, "value" => %{"type" => "pointer/get", "pointer" => from}}
      ]
    }
  end

  defp rebac_action(duration, subject, object, path) do
    %{
      "params" => [],
      "duration" => duration,
      "body" => [
        %{
          "eval" => %{
            "type" => "rebac/check",
            "rel" => "HAS_CAPABILITY",
            "subject" => subject,
            "object" => object
          }
        },
        %{"pointer/set" => path, "value" => true}
      ]
    }
  end

  defp domain(actions, subtasks, extra \\ %{}) do
    %{
      "@context" => @context,
      "@type" => "domain:Definition",
      "name" => "temporal",
      "variables" => [%{"name" => "s", "type" => "int", "init" => %{"k" => 0}}],
      "actions" => actions,
      "methods" => %{
        "top" => %{
          "params" => [],
          "alternatives" => [%{"name" => "only", "subtasks" => subtasks}]
        }
      },
      "todo_list" => [["top"]]
    }
    |> Map.merge(extra)
    |> Jason.encode!()
  end

  defp temporal(domain_json) do
    {:ok, out} = Taskweft.plan(domain_json)
    Jason.decode!(out)["temporal"]
  end

  defp spans(temporal), do: Enum.map(temporal["steps"], &{&1["action"], &1["start"], &1["end"]})

  describe "state pointers" do
    test "steps writing disjoint paths overlap, so the total is one duration" do
      # The same action, parameterised, called twice on two different agents.
      actions = %{
        "move" => %{
          "params" => ["agent"],
          "duration" => @five,
          "body" => [%{"pointer/set" => "/loc/{agent}", "value" => true}]
        }
      }

      temporal = temporal(domain(actions, [["move", "a"], ["move", "b"]]))

      assert temporal["total"] == @five
      assert temporal["consistent"] == true
      assert spans(temporal) == [{"move", "PT0S", @five}, {"move", "PT0S", @five}]
    end

    test "control: steps writing the same path serialise, so the total is both" do
      actions = %{"move" => write_action(@five, "/loc/a")}
      temporal = temporal(domain(actions, [["move"], ["move"]]))

      assert temporal["total"] == "PT10M"
      assert spans(temporal) == [{"move", "PT0S", @five}, {"move", @five, "PT10M"}]
    end

    test "a write against a read of the same path serialises" do
      actions = %{
        "write_x" => write_action(@five, "/s/x"),
        "read_x" => copy_action(@five, "/s/x", "/s/y")
      }

      temporal = temporal(domain(actions, [["write_x"], ["read_x"]]))

      assert temporal["total"] == "PT10M"
    end

    test "control: a write against a read of another path overlaps" do
      actions = %{
        "write_x" => write_action(@five, "/s/x"),
        "read_z" => copy_action(@five, "/s/z", "/s/y")
      }

      temporal = temporal(domain(actions, [["write_x"], ["read_z"]]))

      assert temporal["total"] == @five
    end

    test "three steps: the contended pair serialises and the free step overlaps" do
      actions = %{
        "w_x" => write_action(@five, "/s/x"),
        "w_y" => write_action(@five, "/s/y"),
        "w_x2" => write_action(@five, "/s/x")
      }

      temporal = temporal(domain(actions, [["w_x"], ["w_y"], ["w_x2"]]))

      assert temporal["total"] == "PT10M"
      assert spans(temporal) == [{"w_x", "PT0S", @five}, {"w_y", "PT0S", @five}, {"w_x2", @five, "PT10M"}]
    end

    test "durations that differ make the makespan the longer of the two" do
      actions = %{
        "short" => write_action("PT2M", "/s/x"),
        "long" => write_action("PT7M", "/s/y")
      }

      temporal = temporal(domain(actions, [["short"], ["long"]]))

      assert temporal["total"] == "PT7M"
      assert spans(temporal) == [{"short", "PT0S", "PT2M"}, {"long", "PT0S", "PT7M"}]
    end
  end

  describe "ReBAC endpoints" do
    @graph %{
      "capabilities" => %{
        "graph" => %{
          "edges" => [
            %{"subject" => "drone_1", "rel" => "HAS_CAPABILITY", "object" => "fly"},
            %{"subject" => "drone_1", "rel" => "HAS_CAPABILITY", "object" => "swim"}
          ],
          "definitions" => %{}
        }
      }
    }

    test "guards naming different endpoints overlap" do
      actions = %{
        "use_fly" => rebac_action(@five, "drone_1", "fly", "/s/a"),
        "use_swim" => rebac_action(@five, "drone_1", "swim", "/s/b")
      }

      temporal = temporal(domain(actions, [["use_fly"], ["use_swim"]], @graph))

      assert temporal["total"] == @five
    end

    test "control: guards naming the same endpoint serialise even with disjoint writes" do
      actions = %{
        "use_fly" => rebac_action(@five, "drone_1", "fly", "/s/a"),
        "use_fly_again" => rebac_action(@five, "drone_1", "fly", "/s/b")
      }

      temporal = temporal(domain(actions, [["use_fly"], ["use_fly_again"]], @graph))

      assert temporal["total"] == "PT10M"
      assert spans(temporal) == [{"use_fly", "PT0S", @five}, {"use_fly_again", @five, "PT10M"}]
    end
  end

  describe "the origin still offsets the schedule" do
    test "an origin shifts every start and leaves the total alone" do
      actions = %{
        "move" => %{
          "params" => ["agent"],
          "duration" => @five,
          "body" => [%{"pointer/set" => "/loc/{agent}", "value" => true}]
        }
      }

      json = domain(actions, [["move", "a"], ["move", "b"]])
      {:ok, out} = Taskweft.plan(json, "PT1H")
      temporal = Jason.decode!(out)["temporal"]

      assert temporal["origin"] == "PT1H"
      assert temporal["total"] == @five
      assert spans(temporal) == [{"move", "PT1H", "PT1H5M"}, {"move", "PT1H", "PT1H5M"}]
    end
  end
end
