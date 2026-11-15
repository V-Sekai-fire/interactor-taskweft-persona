defmodule Persona.Native do
  @moduledoc """
  The persona's Lean planner, called from Elixir.

  Every function returns `{:ok, json}` or `{:error, reason}`. The JSON is what the guest ELF
  and the browser module answer: a plan, or a refusal by name (`{"refused":"undeclared_goal"}`).
  A refusal is an answer, so it comes back inside `{:ok, _}`.

      {:ok, json} = Persona.Native.ask("")
      {:ok, json} = Persona.Native.plan_jsonld(domain, problem, "")

  Built by `Leanler` from the `:leanler` configuration in `mix.exs`. As a NIF it loads with the
  application. Built with `PERSONA_NATIVE=cnode`, start it under a supervisor first:

      children = [Persona.Native]
  """
  use Leanler
end
