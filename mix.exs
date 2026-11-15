defmodule Persona.MixProject do
  use Mix.Project

  def project do
    [
      app: :persona,
      version: "0.1.0",
      elixir: "~> 1.18",
      compilers: [:leanler] ++ Mix.compilers(),
      deps: deps(),
      leanler: leanler()
    ]
  end

  def application, do: [extra_applications: [:logger]]

  # LEANLER_PATH points at a local checkout of leanler while it is developed.
  defp deps do
    case System.get_env("LEANLER_PATH") do
      nil -> [{:leanler, github: "V-Sekai-fire/leanler"}]
      path -> [{:leanler, path: path}]
    end
  end

  # The Lean persona as a BEAM library. `:nif` loads it in the VM; PERSONA_NATIVE=cnode runs it
  # as its own OS process that joins the cluster, so a Lean crash cannot take the VM down.
  defp leanler do
    [
      mode: if(System.get_env("PERSONA_NATIVE") == "cnode", do: :cnode, else: :nif),
      module: Persona.Native,
      package: "persona",
      modules: ["Persona.Web", "Persona.Guest", "Persona.Grid"],
      exports: [
        ask: [symbol: "persona_ask_json", args: [:string], returns: :string],
        version: [symbol: "persona_version_text", args: [:string], returns: :string],
        plan_grid: [symbol: "persona_plan_text", args: [:string], returns: :string],
        goals: [symbol: "persona_goals_text", args: [:string, :string], returns: :string],
        plan_jsonld: [
          symbol: "persona_plan_jsonld_text",
          args: [:string, :string, :string],
          returns: :string
        ],
        plan_shortest: [
          symbol: "persona_plan_shortest_text",
          args: [:string, :string, :nat],
          returns: :string
        ]
      ]
    ]
  end
end
