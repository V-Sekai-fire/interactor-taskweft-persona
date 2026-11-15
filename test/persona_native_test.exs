defmodule Persona.NativeTest do
  use ExUnit.Case, async: true

  @domain File.read!("domains/campus-sample.jsonld")
  @problem File.read!("problems/campus-sample.jsonld")
  @gold File.read!("plans/campus-sample.jsonld")

  test "version" do
    assert {:ok, "0.1.0"} = Persona.Native.version("")
  end

  test "ask answers a plan that reaches the goal" do
    assert {:ok, json} = Persona.Native.ask("")
    assert json =~ ~s("reached":true)
    assert json =~ "recharge"
  end

  test "an undeclared goal is refused by name" do
    assert {:ok, ~s({"refused":"undeclared_goal"})} = Persona.Native.ask("no-such-goal")
  end

  test "the JSON-LD plan equals the committed gold file" do
    assert {:ok, plan} = Persona.Native.plan_jsonld(@domain, @problem, "")
    assert String.trim(plan) == String.trim(@gold)
  end

  test "a changed step does not equal the gold" do
    assert {:ok, plan} = Persona.Native.plan_jsonld(@domain, @problem, "")
    refute String.replace(plan, "settle", "xettle", global: false) == String.trim(@gold)
  end

  test "goals lists what the problem asks" do
    assert {:ok, json} = Persona.Native.goals(@domain, @problem)
    assert json =~ ~s("goals":[)
  end

  test "a Nat argument crosses" do
    assert {:ok, json} = Persona.Native.plan_shortest(@domain, @problem, 4)
    assert is_binary(json)
  end

  test "a bad argument is an error tuple, not a crash" do
    assert {:error, :badarg} = Persona.Native.ask(:not_a_binary)
    assert {:error, :badarg} = Persona.Native.plan_shortest(@domain, @problem, -1)
  end

  test "sixteen processes call concurrently and agree" do
    answers =
      1..16
      |> Task.async_stream(fn _ -> Persona.Native.plan_jsonld(@domain, @problem, "") end,
        max_concurrency: 16
      )
      |> Enum.map(fn {:ok, r} -> r end)
      |> Enum.uniq()

    assert [{:ok, _}] = answers
  end
end
